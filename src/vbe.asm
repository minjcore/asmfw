; ============================================================================
; vbe.asm -- bring up a linear framebuffer without a VGA option ROM
;
; There is no legacy INT 10h here to call, so the mode is programmed directly
; through the Bochs VBE "dispi" register pair that QEMU's std/vmware/cirrus
; display devices implement. The framebuffer itself is BAR0 of the PCI
; display function.
; ============================================================================

bits 64

VBE_DISPI_INDEX         equ 0x01CE
VBE_DISPI_DATA          equ 0x01CF

VBE_DISPI_ID            equ 0
VBE_DISPI_XRES          equ 1
VBE_DISPI_YRES          equ 2
VBE_DISPI_BPP           equ 3
VBE_DISPI_ENABLE        equ 4
VBE_DISPI_BANK          equ 5
VBE_DISPI_VIRT_WIDTH    equ 6
VBE_DISPI_VIRT_HEIGHT   equ 7
VBE_DISPI_X_OFFSET      equ 8
VBE_DISPI_Y_OFFSET      equ 9

VBE_DISPI_DISABLED      equ 0x00
VBE_DISPI_ENABLED       equ 0x01
VBE_DISPI_LFB_ENABLED   equ 0x40
VBE_DISPI_NOCLEARMEM    equ 0x80

VBE_ID0                 equ 0xB0C0          ; any 0xB0Cx is a usable revision

FB_WIDTH                equ 1024
FB_HEIGHT               equ 768
FB_BPP                  equ 32

; ----------------------------------------------------------------------------
; dispi_write -- AX = index, DX = value
; ----------------------------------------------------------------------------
dispi_write:
    push    rax
    push    rdx
    push    rcx
    mov     cx, dx                          ; stash the value
    mov     dx, VBE_DISPI_INDEX
    out     dx, ax
    mov     dx, VBE_DISPI_DATA
    mov     ax, cx
    out     dx, ax
    pop     rcx
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; dispi_read -- AX = index, returns AX
; ----------------------------------------------------------------------------
dispi_read:
    push    rdx
    mov     dx, VBE_DISPI_INDEX
    out     dx, ax
    mov     dx, VBE_DISPI_DATA
    in      ax, dx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; vga_unblank -- let light out of the VGA core.
;
; Setting a VBE mode is not enough on its own: the attribute controller's
; palette-address-source bit still gates the display, and the chip comes out
; of reset with it clear. On a normal PC the video option ROM sets it during
; INT 10h mode setting -- there is no option ROM here, so the firmware does it.
;
; Port 0x3C0 is a shared index/data register driven by a flip-flop; reading
; the input status register at 0x3DA is what puts it back into index phase.
; ----------------------------------------------------------------------------
vga_unblank:
    push    rax
    push    rdx

    mov     dx, 0x03C2                      ; miscellaneous output:
    mov     al, 0xE3                        ; colour ports, RAM enabled, 25 MHz
    out     dx, al

    mov     dx, 0x03DA
    in      al, dx                          ; index phase
    mov     dx, 0x03C0
    mov     al, 0x20                        ; PAS = 1, no index selected
    out     dx, al

    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; gfx_init -- locate the display, set FB_WIDTH x FB_HEIGHT x 32, record the
; framebuffer in the globals. Returns EAX non-zero on success.
; ----------------------------------------------------------------------------
gfx_init:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi

    mov     dword [abs g_vga_bdf], -1

    ; --- find the PCI display function ------------------------------------
    mov     al, PCI_CLASS_DISPLAY
    call    pci_find_class
    cmp     eax, 0xFFFFFFFF
    je      .no_device
    mov     ebx, eax                        ; config address of the device
    mov     [abs g_vga_bdf], ebx

    ; Memory decode has to be on before the framebuffer BAR means anything.
    mov     edi, ebx
    call    pci_enable

    ; --- is anything answering on the dispi register pair? ----------------
    mov     ax, VBE_DISPI_ID
    call    dispi_read
    movzx   edx, ax
    mov     [abs g_vbe_id], edx
    and     ax, 0xFFF0
    cmp     ax, VBE_ID0
    jne     .no_dispi

    ; --- framebuffer ------------------------------------------------------
    lea     edi, [rbx + PCI_BAR0]
    call    pci_bar_addr
    test    rax, rax
    jz      .no_bar
    mov     [abs g_fb_base], rax

    ; --- program the mode -------------------------------------------------
    ; The device wants the geometry written while it is disabled.
    mov     ax, VBE_DISPI_ENABLE
    mov     dx, VBE_DISPI_DISABLED
    call    dispi_write

    mov     ax, VBE_DISPI_XRES
    mov     dx, FB_WIDTH
    call    dispi_write
    mov     ax, VBE_DISPI_YRES
    mov     dx, FB_HEIGHT
    call    dispi_write
    mov     ax, VBE_DISPI_BPP
    mov     dx, FB_BPP
    call    dispi_write
    mov     ax, VBE_DISPI_VIRT_WIDTH
    mov     dx, FB_WIDTH
    call    dispi_write
    mov     ax, VBE_DISPI_X_OFFSET
    xor     dx, dx
    call    dispi_write
    mov     ax, VBE_DISPI_Y_OFFSET
    xor     dx, dx
    call    dispi_write
    mov     ax, VBE_DISPI_BANK
    xor     dx, dx
    call    dispi_write

    mov     ax, VBE_DISPI_ENABLE
    mov     dx, VBE_DISPI_ENABLED | VBE_DISPI_LFB_ENABLED
    call    dispi_write

    call    vga_unblank

    ; --- confirm the device actually took the mode ------------------------
    mov     ax, VBE_DISPI_XRES
    call    dispi_read
    cmp     ax, FB_WIDTH
    jne     .no_mode

    mov     dword [abs g_fb_w], FB_WIDTH
    mov     dword [abs g_fb_h], FB_HEIGHT
    mov     dword [abs g_fb_pitch], FB_WIDTH * (FB_BPP / 8)
    mov     rax, FB_WIDTH * FB_HEIGHT * (FB_BPP / 8)
    mov     [abs g_fb_size], rax

    call    fb_console_init
    mov     dword [abs g_fb_ok], 1
    mov     eax, 1
    jmp     .done

.no_device:
    puts    msg_gfx_nodev
    jmp     .fail
.no_dispi:
    puts    msg_gfx_nodispi
    mov     eax, [abs g_vbe_id]
    call    con_puthex16
    mov     al, 10
    call    con_putc
    jmp     .fail
.no_bar:
    puts    msg_gfx_nobar
    jmp     .fail
.no_mode:
    puts    msg_gfx_nomode

.fail:
    xor     eax, eax
    mov     dword [abs g_fb_ok], 0
.done:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
CSTR msg_gfx_nodev,    "[DXE] gfx: no PCI display controller on bus 0", 10
CSTR msg_gfx_nodispi,  "[DXE] gfx: display has no Bochs VBE interface, id="
CSTR msg_gfx_nobar,    "[DXE] gfx: display BAR0 is unassigned", 10
CSTR msg_gfx_nomode,   "[DXE] gfx: device rejected the requested mode", 10

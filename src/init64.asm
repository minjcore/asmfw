; ============================================================================
; init64.asm -- the firmware's phase sequence once long mode is live
;
;   SEC  establish a C-like environment: stack, zeroed globals, serial
;   PEI  size RAM and stand up the page allocator
;   DXE  bring up the display and the storage stack, publish EFI protocols
;   BDS  find a boot device and hand control to \EFI\BOOT\BOOTX64.EFI
; ============================================================================

bits 64

MXCSR_DEFAULT   equ 0x1F80

; ----------------------------------------------------------------------------
; SEC
; ----------------------------------------------------------------------------
sec_entry64:
    mov     ax, SEL_D64
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     rsp, FW_STACK_TOP
    xor     rbp, rbp

    ; The x87 FPU and SSE, in the state the UEFI specification requires of an
    ; x64 platform before any image runs (2.3.4): CR0.EM clear and CR0.MP set
    ; so the FPU is native; CR4.OSFXSR and CR4.OSXMMEXCPT set so SSE
    ; instructions execute and fault properly; FCW 0x037F and MXCSR 0x1F80,
    ; every exception masked, round to nearest. Without this the first SSE
    ; instruction an image executes is #UD -- and every compiler targeting
    ; UEFI emits them, for memcpy if nothing else.
    mov     rax, cr0
    and     rax, ~(1 << 2)                      ; EM
    or      rax, 1 << 1                         ; MP
    mov     cr0, rax
    mov     rax, cr4
    or      rax, (1 << 9) | (1 << 10)           ; OSFXSR, OSXMMEXCPT
    mov     cr4, rax
    fninit                                      ; FCW = 0x037F
    push    qword MXCSR_DEFAULT
    ldmxcsr [rsp]
    add     rsp, 8

    ; Globals live in RAM whose contents are undefined at reset.
    mov     rdi, G_BASE
    xor     eax, eax
    mov     rcx, GOFF_TOTAL
    rep stosb

    call    ser_init

    puts    msg_banner
    puts    msg_sec_ok

    call    pei_main
    call    dxe_main
    call    bds_main

    ; BDS comes back either because an image ran and returned, or because
    ; there was nothing to run. Neither is a firmware fault, so neither is a
    ; panic -- there is simply nowhere left to go.
    test    eax, eax
    jz      .nothing
    puts    msg_halted
    jmp     .halt
.nothing:
    puts    msg_no_boot
.halt:
    cli
    hlt
    jmp     .halt

; ----------------------------------------------------------------------------
; PEI -- size memory, arm the allocator
; ----------------------------------------------------------------------------
pei_main:
    push    rax
    push    rbx

    call    mem_size_ram
    mov     [abs g_ram_top], rax
    mov     rbx, rax

    puts    msg_ram
    mov     rax, rbx
    shr     rax, 20
    call    con_putdec
    putsi   " MiB usable below 4 GiB", 10

    cmp     rbx, FW_HEAP_MIN
    jae     .enough
    lea     rsi, [rel msg_low_ram]
    call    panic
.enough:

    ; The page allocator owns everything from FW_HEAP_BASE to the top of RAM.
    mov     rax, FW_HEAP_BASE
    mov     [abs g_heap_next], rax
    mov     [abs g_heap_end], rbx

    puts    msg_pei_ok
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; mem_size_ram -- highest usable byte below 4 GiB, from the CMOS size fields
; QEMU (and every PC BIOS since) publishes.
; ----------------------------------------------------------------------------
mem_size_ram:
    push    rbx
    push    rcx
    push    rdx

    ; 0x34/0x35: memory from 16 MiB up to 4 GiB, in 64 KiB units.
    mov     al, 0x35
    call    cmos_read
    movzx   ebx, al
    shl     ebx, 8
    mov     al, 0x34
    call    cmos_read
    movzx   ecx, al
    or      ebx, ecx
    test    ebx, ebx
    jz      .low_only

    mov     rax, rbx
    shl     rax, 16                         ; x 64 KiB
    add     rax, 16 * 1024 * 1024
    jmp     .done

.low_only:
    ; 0x30/0x31: memory from 1 MiB up to 64 MiB, in KiB.
    mov     al, 0x31
    call    cmos_read
    movzx   ebx, al
    shl     ebx, 8
    mov     al, 0x30
    call    cmos_read
    movzx   ecx, al
    or      ebx, ecx
    mov     rax, rbx
    shl     rax, 10                         ; x 1 KiB
    add     rax, 1024 * 1024

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; cmos_read -- AL = register index, returns AL. NMI stays masked for the
; duration of the access, which is what every other CMOS user expects.
; ----------------------------------------------------------------------------
cmos_read:
    push    rdx
    or      al, 0x80
    mov     dx, 0x70
    out     dx, al
    mov     dx, 0x71
    in      al, dx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; DXE -- device init and protocol publication
; ----------------------------------------------------------------------------
dxe_main:
    push    rax

    ; Nothing has addresses yet: every BAR on the machine reads back zero
    ; until firmware places it.
    call    pci_assign_resources
    puts    msg_pci_ok

    call    gfx_init
    test    eax, eax
    jz      .no_gfx

    ; The banner went out over serial before the display existed; repeat it
    ; now that there is a screen to put it on.
    puts    msg_banner
    puts    msg_gfx
    mov     eax, [abs g_fb_w]
    call    con_putdec
    mov     al, 'x'
    call    con_putc
    mov     eax, [abs g_fb_h]
    call    con_putdec
    putsi   "x32 @ "
    mov     rax, [abs g_fb_base]
    call    con_puthex64
    mov     al, 10
    call    con_putc
    jmp     .storage

.no_gfx:
    puts    msg_no_gfx

.storage:
    call    ata_init
    test    eax, eax
    jz      .no_disk
    puts    msg_disk
    mov     rax, [abs g_ata_sectors]
    shr     rax, 11                             ; sectors -> MiB
    call    con_putdec
    putsi   " MiB on the primary master", 10
    jmp     .protocols
.no_disk:
    puts    msg_no_disk

.protocols:
    ; Input, before anything is published that claims to offer it. The codes
    ; the keyboard sends are not the codes ConIn's table decodes until the
    ; controller has been told to translate them.
    call    kbd_init
    putsi   "kbd   i8042 translation on, set 1 codes", 10

    call    efi_init
    puts    msg_efi_ok
    call    var_init

    ; After efi_init: publishing the RSDP means writing the system table,
    ; which does not exist until the tables have been built.
    call    acpi_init
    ; After acpi_init, which reads the fw_cfg directory this looks names up in.
    call    smbios_init

    puts    msg_dxe_ok
    pop     rax
    ret

; ----------------------------------------------------------------------------
; BDS -- find \EFI\BOOT\BOOTX64.EFI, load it, and start it
; ----------------------------------------------------------------------------
bds_main:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    puts    msg_bds

    cmp     dword [abs g_ata_present], 0
    je       bds_err_no_media

    ; --- partition --------------------------------------------------------
    call    part_find_esp
    test    eax, eax
    jz       bds_err_no_esp
    puts    msg_esp
    mov     rax, [abs g_esp_lba]
    call    con_putdec
    putsi   ", "
    mov     rax, [abs g_esp_sectors]
    shr     rax, 11
    call    con_putdec
    putsi   " MiB", 10

    ; --- filesystem -------------------------------------------------------
    call    fat_mount
    test    eax, eax
    jz       bds_err_no_fs
    call    efi_publish_volume
    puts    msg_fat

    ; --- \EFI\BOOT\BOOTX64.EFI -------------------------------------------
    mov     eax, [abs g_fat_root_clus]
    lea     rsi, [rel name_efi]
    call    fat_lookup
    test    eax, eax
    jz       bds_err_no_file
    test    cl, ATTR_DIRECTORY
    jz       bds_err_no_file

    lea     rsi, [rel name_boot]
    call    fat_lookup
    test    eax, eax
    jz       bds_err_no_file
    test    cl, ATTR_DIRECTORY
    jz       bds_err_no_file

    lea     rsi, [rel name_bootx64]
    call    fat_lookup
    test    eax, eax
    jz       bds_err_no_file
    test    cl, ATTR_DIRECTORY
    jnz      bds_err_no_file

    mov     r12d, eax                           ; first cluster
    mov     r13, rdx                            ; size in bytes
    test    r13, r13
    jz       bds_err_no_file

    puts    msg_found
    mov     rax, r13
    call    con_putdec
    putsi   " bytes", 10

    ; --- read it ----------------------------------------------------------
    ; fat_read_file works in whole clusters, so the buffer is rounded up by
    ; one cluster on top of the file's own page rounding.
    mov     rcx, r13
    mov     eax, [abs g_fat_spc]
    shl     eax, 9
    add     rcx, rax
    add     rcx, 0xFFF
    shr     rcx, 12
    mov     edx, EfiBootServicesData
    call    mem_alloc_pages
    test    rax, rax
    jz       bds_err_no_mem
    mov     rbx, rax                            ; the staging buffer

    mov     eax, r12d
    mov     rdx, r13
    mov     rdi, rbx
    call    fat_read_file
    test    eax, eax
    jnz      bds_err_read_error

    ; --- load it ----------------------------------------------------------
    mov     rsi, rbx
    mov     rdx, r13
    call    pe_load
    test    eax, eax
    jnz      bds_err_pe_error

    puts    msg_loaded
    mov     rax, [abs g_img_base]
    call    con_puthex64
    putsi   ", entry "
    mov     rax, [abs g_img_entry]
    call    con_puthex64
    mov     al, 10
    call    con_putc

    call    bds_publish_image

    ; --- start it ---------------------------------------------------------
    puts    msg_starting

    mov     [abs g_exit_rsp], rsp
    mov     qword [abs g_current_image], H_IMAGE
    and     rsp, -16                            ; the ABI wants 16-byte alignment
    sub     rsp, 32                             ; ...and 32 bytes of shadow space
    mov     rcx, H_IMAGE                        ; ImageHandle
    mov     rdx, EFI_ST                         ; SystemTable
    call    qword [abs g_img_entry]

; Both a normal return and a call to Exit() land here. The image is entitled
; to have clobbered every callee-saved register, so nothing is assumed about
; them: the stack comes back from a global, not from RBP.
image_exit_resume:
    mov     rsp, [abs g_exit_rsp]
    mov     [abs g_exit_status], rax

    puts    msg_returned
    mov     rax, [abs g_exit_status]
    call    con_puthex64
    mov     al, 10
    call    con_putc
    mov     eax, 1                              ; something was booted
    jmp     bds_done

bds_err_no_media:      puts msg_bds_nodisk
                jmp bds_failed
bds_err_no_esp:        puts msg_bds_noesp
                jmp bds_failed
bds_err_no_fs:         puts msg_bds_nofs
                jmp bds_failed
bds_err_no_file:       puts msg_bds_nofile
                jmp bds_failed
bds_err_no_mem:        puts msg_bds_nomem
                jmp bds_failed
bds_err_read_error:    puts msg_bds_readerr
                jmp bds_failed
bds_err_pe_error:
                puts msg_bds_peerr
                call pe_error_string
                call con_puts
                mov al, 10
                call con_putc
bds_failed:
    xor     eax, eax
bds_done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; bds_publish_image -- fill in EFI_LOADED_IMAGE_PROTOCOL and register it
; ----------------------------------------------------------------------------
bds_publish_image:
    push    rax
    push    rsi
    push    rdi

    mov     rdi, EFI_LOADED_IMG
    mov     dword [rdi + LI_REVISION], LOADED_IMAGE_REVISION
    mov     qword [rdi + LI_PARENTHANDLE], 0
    mov     qword [rdi + LI_SYSTEMTABLE], EFI_ST
    mov     qword [rdi + LI_DEVICEHANDLE], H_DISK
    mov     qword [rdi + LI_FILEPATH], 0
    mov     qword [rdi + LI_RESERVED], 0
    mov     dword [rdi + LI_LOADOPTIONSSIZE], 0
    mov     qword [rdi + LI_LOADOPTIONS], 0
    mov     rax, [abs g_img_base]
    mov     [rdi + LI_IMAGEBASE], rax
    mov     rax, [abs g_img_pages]
    shl     rax, 12
    mov     [rdi + LI_IMAGESIZE], rax
    mov     dword [rdi + LI_IMAGECODETYPE], EfiLoaderCode
    mov     dword [rdi + LI_IMAGEDATATYPE], EfiLoaderData
    mov     qword [rdi + LI_UNLOAD], 0

    mov     rax, H_IMAGE
    lea     rsi, [rel guid_loaded_image]
    mov     rdi, EFI_LOADED_IMG
    call    proto_add

    pop     rdi
    pop     rsi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; 8.3 names, space padded, exactly as FAT stores them
; ----------------------------------------------------------------------------
name_efi:       db "EFI        "
name_boot:      db "BOOT       "
name_bootx64:   db "BOOTX64 EFI"

; ----------------------------------------------------------------------------
CSTR msg_banner,  10, "asmfw 0.1 -- UEFI firmware, written in assembly", 10, \
                  "Copyright (c) 2026. No warranty of any kind.", 10, 10
CSTR msg_sec_ok,  "[SEC] long mode entered, 4 GiB identity mapped", 10
CSTR msg_ram,     "[PEI] RAM: "
CSTR msg_pei_ok,  "[PEI] page allocator armed", 10
CSTR msg_pci_ok,  "[DXE] PCI: BARs assigned", 10
CSTR msg_gfx,     "[DXE] GOP: "
CSTR msg_no_gfx,  "[DXE] no framebuffer; console is serial only", 10
CSTR msg_disk,    "[DXE] ATA: "
CSTR msg_no_disk, "[DXE] no disk on the primary ATA channel", 10
CSTR msg_efi_ok,  "[DXE] EFI tables built, protocols published", 10
CSTR msg_dxe_ok,  "[DXE] done", 10
CSTR msg_bds,     "[BDS] searching for a boot device", 10
CSTR msg_esp,     "[BDS] EFI system partition at LBA "
CSTR msg_fat,     "[BDS] FAT32 volume mounted", 10
CSTR msg_found,   "[BDS] \EFI\BOOT\BOOTX64.EFI, "
CSTR msg_loaded,  "[BDS] image at "
CSTR msg_starting, "[BDS] starting image", 10, 10
CSTR msg_returned, 10, "[BDS] image returned, status "

CSTR msg_bds_nodisk,  "[BDS] no disk to boot from", 10
CSTR msg_bds_noesp,   "[BDS] no EFI system partition on the disk", 10
CSTR msg_bds_nofs,    "[BDS] the EFI system partition is not readable FAT32", 10
CSTR msg_bds_nofile,  "[BDS] \EFI\BOOT\BOOTX64.EFI is not on the volume", 10
CSTR msg_bds_nomem,   "[BDS] not enough memory to stage the image", 10
CSTR msg_bds_readerr, "[BDS] the image could not be read off the disk", 10
CSTR msg_bds_peerr,   "[BDS] the image could not be loaded: "

CSTR msg_low_ram, "not enough RAM to run"
CSTR msg_no_boot, "[BDS] nothing to boot; system halted", 10
CSTR msg_halted,  "[BDS] no further boot options; system halted", 10

; ============================================================================
; pci.asm -- type 1 PCI configuration access and a minimal device scan
;
; Address form used throughout: EDI = 0x80000000 | bus<<16 | dev<<11 | fn<<8
;                                            | (register & 0xFC)
; ============================================================================

bits 64

PCI_CFG_ADDR    equ 0x0CF8
PCI_CFG_DATA    equ 0x0CFC

PCI_VENDOR      equ 0x00
PCI_COMMAND     equ 0x04
PCI_CLASS       equ 0x08        ; rev, prog-if, subclass, class
PCI_HEADER      equ 0x0C        ; cache line, latency, header type, BIST
PCI_BAR0        equ 0x10

PCI_CLASS_DISPLAY equ 0x03
PCI_CLASS_STORAGE equ 0x01

; Windows this firmware hands out. The MMIO window sits above the 256 MiB..
; 3 GiB of RAM any sane QEMU invocation has, and below the LAPIC/HPET/flash
; region at the top of the address space. Everything here is mapped uncached
; by the identity map built in init32.asm.
PCI_MMIO_BASE   equ 0xC0000000
PCI_IO_BASE     equ 0xC000

; ----------------------------------------------------------------------------
; pci_read32 -- EDI = config address, returns EAX
; ----------------------------------------------------------------------------
pci_read32:
    push    rdx
    mov     eax, edi
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CFG_ADDR
    out     dx, eax
    mov     dx, PCI_CFG_DATA
    in      eax, dx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; pci_write32 -- EDI = config address, ESI = value
; ----------------------------------------------------------------------------
pci_write32:
    push    rax
    push    rdx
    mov     eax, edi
    and     eax, 0xFFFFFFFC
    or      eax, 0x80000000
    mov     dx, PCI_CFG_ADDR
    out     dx, eax
    mov     dx, PCI_CFG_DATA
    mov     eax, esi
    out     dx, eax
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; pci_find_class -- find the first device whose class byte is AL.
;
; Returns EAX = config address of function 0 of that device, or 0xFFFFFFFF if
; nothing matched. Only bus 0 is scanned: on the QEMU machines this firmware
; targets, the display and storage controllers all live there.
; ----------------------------------------------------------------------------
pci_find_class:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    mov     bl, al                          ; wanted class
    xor     ecx, ecx                        ; device number
.dev:
    mov     edi, ecx
    shl     edi, 11
    or      edi, 0x80000000
    ; A missing device reads back all ones in the vendor/device register.
    call    pci_read32
    cmp     ax, 0xFFFF
    je      .next

    lea     edi, [rdi + PCI_CLASS]
    call    pci_read32
    shr     eax, 24
    cmp     al, bl
    jne     .next

    mov     eax, ecx
    shl     eax, 11
    or      eax, 0x80000000
    jmp     .done
.next:
    inc     ecx
    cmp     ecx, 32
    jb      .dev
    mov     eax, 0xFFFFFFFF
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; pci_bar_addr -- EDI = config address of the BAR, returns the 64-bit base
; in RAX with the type bits stripped. Handles the 64-bit BAR form.
; ----------------------------------------------------------------------------
pci_bar_addr:
    push    rbx
    push    r9
    push    rdi
    call    pci_read32
    mov     ebx, eax
    and     eax, 0xFFFFFFF0
    mov     r9d, eax                        ; low half
    ; bits 2:1 == 10b means the BAR is 64 bits wide and continues in the next
    and     ebx, 0x06
    cmp     ebx, 0x04
    jne     .low_only
    lea     edi, [rdi + 4]
    call    pci_read32
    shl     rax, 32
    or      rax, r9
    jmp     .done
.low_only:
    mov     eax, r9d
.done:
    pop     rdi
    pop     r9
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; pci_enable -- EDI = config address of the device; turn on I/O space,
; memory space and bus mastering.
; ----------------------------------------------------------------------------
pci_enable:
    push    rax
    push    rsi
    push    rdi
    lea     edi, [rdi + PCI_COMMAND]
    call    pci_read32
    or      eax, 0x07                       ; I/O | memory | bus master
    mov     esi, eax
    call    pci_write32
    pop     rdi
    pop     rsi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; pci_bar_size -- EDI = config address of a BAR.
;
; Returns EAX = size in bytes (0 if the BAR is unimplemented) and EDX = the
; value read back, whose low bits carry the BAR type. The BAR is left holding
; the all-ones probe value; the caller is expected to write a real base next.
;
; Only the low 32 bits are sized. A BAR wider than 4 GiB could not be placed
; in the window this firmware hands out anyway.
; ----------------------------------------------------------------------------
pci_bar_size:
    push    rsi
    push    rdi
    mov     esi, 0xFFFFFFFF
    call    pci_write32
    call    pci_read32
    mov     edx, eax
    test    al, 0x01
    jnz     .io
    and     eax, 0xFFFFFFF0
    jz      .none
    jmp     .calc
.io:
    and     eax, 0x0000FFFC                 ; I/O space is 16 bits wide on a PC
    jz      .none
.calc:
    not     eax
    inc     eax
    jmp     .done
.none:
    xor     eax, eax
.done:
    pop     rdi
    pop     rsi
    ret

; ----------------------------------------------------------------------------
; pci_assign_resources -- give every device on bus 0 a home.
;
; QEMU hands the firmware a machine whose BARs are all zero: assigning them is
; firmware's job, and until it happens the framebuffer has no address. Each
; BAR is sized by writing all ones, then placed in the MMIO or I/O window at
; its natural alignment.
;
; Bus 0 only, and type 0 headers only -- the QEMU machines this targets have
; no PCI-to-PCI bridges unless one is asked for on the command line.
; ----------------------------------------------------------------------------
pci_assign_resources:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r14d, PCI_MMIO_BASE
    mov     r15d, PCI_IO_BASE
    xor     r12d, r12d                      ; device
.dev:
    xor     r13d, r13d                      ; function
.fn:
    mov     ebx, r12d
    shl     ebx, 11
    mov     eax, r13d
    shl     eax, 8
    or      ebx, eax
    or      ebx, 0x80000000                 ; config address of this function

    mov     edi, ebx
    call    pci_read32
    cmp     ax, 0xFFFF                      ; no device answers this address
    je      .next_fn

    lea     edi, [rbx + PCI_HEADER]
    call    pci_read32
    shr     eax, 16
    and     al, 0x7F
    jnz     .next_fn                        ; bridge or CardBus: not ours

    ; Decoding must be off while the BARs move, or a half-written address
    ; would briefly claim a window that belongs to someone else.
    lea     edi, [rbx + PCI_COMMAND]
    call    pci_read32
    mov     r9d, eax
    mov     esi, eax
    and     esi, 0xFFFFFFFC                 ; clear I/O and memory decode
    call    pci_write32

    xor     r8d, r8d                        ; BAR index
.bar:
    mov     r10d, r8d
    shl     r10d, 2
    add     r10d, PCI_BAR0
    add     r10d, ebx                       ; config address of this BAR

    mov     edi, r10d
    call    pci_bar_size
    test    eax, eax
    jz      .bar_empty
    mov     r11d, eax                       ; size
    mov     ecx, edx                        ; type bits

    test    cl, 0x01
    jnz     .bar_io

    ; --- memory BAR ------------------------------------------------------
    ; Round the cursor up to the BAR's own size, which is what natural
    ; alignment means for a power-of-two window.
    mov     eax, r11d
    dec     eax
    add     r14d, eax
    not     eax
    and     r14d, eax

    mov     edi, r10d
    mov     esi, r14d
    call    pci_write32
    add     r14d, r11d

    ; A 64-bit BAR occupies this slot and the next one; the upper half is
    ; zero because everything is placed below 4 GiB.
    and     cl, 0x06
    cmp     cl, 0x04
    jne     .bar_next
    lea     edi, [r10 + 4]
    xor     esi, esi
    call    pci_write32
    inc     r8d
    jmp     .bar_next

    ; --- I/O BAR ---------------------------------------------------------
.bar_io:
    mov     eax, r11d
    dec     eax
    add     r15d, eax
    not     eax
    and     r15d, eax

    mov     edi, r10d
    mov     esi, r15d
    call    pci_write32
    add     r15d, r11d
    jmp     .bar_next

.bar_empty:
    ; Leave a probe value behind and the device would decode all of memory.
    mov     edi, r10d
    xor     esi, esi
    call    pci_write32

.bar_next:
    inc     r8d
    cmp     r8d, 6
    jb      .bar

    ; Decode on again, plus bus mastering for the devices that DMA.
    lea     edi, [rbx + PCI_COMMAND]
    mov     esi, r9d
    or      esi, 0x07
    call    pci_write32

.next_fn:
    inc     r13d
    cmp     r13d, 8
    jb      .fn
    inc     r12d
    cmp     r12d, 32
    jb      .dev

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

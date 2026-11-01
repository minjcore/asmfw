; ============================================================================
; ata.asm -- ATA PIO on the primary channel
;
; PIO rather than bus-master DMA: the firmware reads a few megabytes once and
; then hands the machine over, so the transfer rate never matters and PIO
; needs no descriptor tables, no DMA buffers and no interrupt plumbing.
;
; The i440fx machine's PIIX3 IDE function comes up in compatibility mode, so
; the legacy port addresses below are correct regardless of what BAR4 got
; assigned during PCI resource assignment.
; ============================================================================

bits 64

ATA_DATA        equ 0x1F0
ATA_ERROR       equ 0x1F1
ATA_COUNT       equ 0x1F2
ATA_LBA0        equ 0x1F3
ATA_LBA1        equ 0x1F4
ATA_LBA2        equ 0x1F5
ATA_DRIVE       equ 0x1F6
ATA_CMD         equ 0x1F7          ; write: command   read: status
ATA_ALTSTATUS   equ 0x3F6          ; read without clearing the interrupt

ATA_SR_ERR      equ 0x01
ATA_SR_DRQ      equ 0x08
ATA_SR_DF       equ 0x20
ATA_SR_RDY      equ 0x40
ATA_SR_BSY      equ 0x80

ATA_CMD_READ    equ 0x20           ; READ SECTORS, LBA28
ATA_CMD_IDENT   equ 0xEC           ; IDENTIFY DEVICE

SECTOR_SIZE     equ 512

; ----------------------------------------------------------------------------
; ata_delay400 -- the mandatory settle after a drive select or a command.
; Reading the alternate status register four times is the conventional way to
; burn the required 400 ns without a calibrated timer.
; ----------------------------------------------------------------------------
ata_delay400:
    push    rax
    push    rcx
    push    rdx
    mov     dx, ATA_ALTSTATUS
    mov     ecx, 4
.again:
    in      al, dx
    dec     ecx
    jnz     .again
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; ata_wait_bsy -- spin until BSY clears. Returns EAX = 0 on success, 1 if the
; drive never answered.
; ----------------------------------------------------------------------------
ata_wait_bsy:
    push    rcx
    push    rdx
    mov     dx, ATA_ALTSTATUS
    mov     ecx, 0x00400000                 ; bounded: a dead port reads 0xFF forever
.spin:
    in      al, dx
    test    al, ATA_SR_BSY
    jz      .ready
    dec     ecx
    jnz     .spin
    mov     eax, 1
    jmp     .done
.ready:
    xor     eax, eax
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; ata_wait_drq -- wait for the drive to be ready with data.
; Returns EAX = 0 on success, 1 on timeout or a device error.
; ----------------------------------------------------------------------------
ata_wait_drq:
    push    rcx
    push    rdx
    mov     dx, ATA_ALTSTATUS
    mov     ecx, 0x00400000
.spin:
    in      al, dx
    test    al, ATA_SR_BSY
    jnz     .next
    test    al, ATA_SR_ERR | ATA_SR_DF
    jnz     .fail
    test    al, ATA_SR_DRQ
    jnz     .ok
.next:
    dec     ecx
    jnz     .spin
.fail:
    mov     eax, 1
    jmp     .done
.ok:
    xor     eax, eax
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; ata_init -- probe the primary master.
;
; Sets g_ata_present and g_ata_sectors. Returns EAX non-zero if a disk is
; there and readable.
; ----------------------------------------------------------------------------
ata_init:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     dword [abs g_ata_present], 0
    mov     qword [abs g_ata_sectors], 0

    ; A floating bus -- no drive, no controller -- reads back all ones.
    mov     dx, ATA_CMD
    in      al, dx
    cmp     al, 0xFF
    je      .none

    mov     dx, ATA_DRIVE
    mov     al, 0xA0                        ; master, CHS-style select for IDENTIFY
    out     dx, al
    call    ata_delay400

    xor     eax, eax
    mov     dx, ATA_COUNT
    out     dx, al
    mov     dx, ATA_LBA0
    out     dx, al
    mov     dx, ATA_LBA1
    out     dx, al
    mov     dx, ATA_LBA2
    out     dx, al

    mov     dx, ATA_CMD
    mov     al, ATA_CMD_IDENT
    out     dx, al
    call    ata_delay400

    in      al, dx
    test    al, al                          ; status 0 means nothing is there
    jz      .none

    call    ata_wait_bsy
    test    eax, eax
    jnz     .none

    ; A non-zero signature in the LBA mid/high registers means the device
    ; speaks ATAPI, not ATA, and IDENTIFY DEVICE will never complete.
    mov     dx, ATA_LBA1
    in      al, dx
    mov     bl, al
    mov     dx, ATA_LBA2
    in      al, dx
    or      bl, al
    jnz     .none

    call    ata_wait_drq
    test    eax, eax
    jnz     .none

    mov     rdi, BUF_IDENTIFY
    mov     dx, ATA_DATA
    mov     ecx, 256
    rep insw

    ; Words 60..61 hold the LBA28 capacity. Words 100..103 hold the LBA48
    ; capacity; this driver only issues LBA28 commands, so the 28-bit count
    ; is the one that bounds it.
    mov     rdi, BUF_IDENTIFY
    mov     eax, [rdi + 60 * 2]
    mov     [abs g_ata_sectors], rax
    test    eax, eax
    jz      .none

    mov     dword [abs g_ata_present], 1
    mov     eax, 1
    jmp     .done
.none:
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; ata_read -- RAX = first LBA, ECX = sector count, RDI = destination.
;
; Returns EAX = 0 on success, 1 on failure. A single READ SECTORS command
; moves at most 256 sectors, so long reads are split into chunks.
; ----------------------------------------------------------------------------
ata_read:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rax                        ; current LBA
    mov     r13d, ecx                       ; sectors still wanted

    test    r13d, r13d
    jz      .ok
    cmp     dword [abs g_ata_present], 0
    je      .fail

.chunk:
    mov     ebx, r13d
    cmp     ebx, 255
    jbe     .have_chunk
    mov     ebx, 255
.have_chunk:

    call    ata_wait_bsy
    test    eax, eax
    jnz     .fail

    ; Drive/head register: LBA mode, master, and the top four LBA bits.
    mov     rax, r12
    shr     rax, 24
    and     al, 0x0F
    or      al, 0xE0
    mov     dx, ATA_DRIVE
    out     dx, al

    mov     al, bl
    mov     dx, ATA_COUNT
    out     dx, al

    mov     rax, r12
    mov     dx, ATA_LBA0
    out     dx, al
    mov     rax, r12
    shr     rax, 8
    mov     dx, ATA_LBA1
    out     dx, al
    mov     rax, r12
    shr     rax, 16
    mov     dx, ATA_LBA2
    out     dx, al

    mov     dx, ATA_CMD
    mov     al, ATA_CMD_READ
    out     dx, al
    call    ata_delay400

    ; Each sector has to be waited for individually: the drive raises DRQ
    ; once per sector, not once per command.
    mov     r14d, ebx
.sector:
    call    ata_wait_drq
    test    eax, eax
    jnz     .fail
    mov     dx, ATA_DATA
    mov     ecx, SECTOR_SIZE / 2
    rep insw
    call    ata_delay400
    dec     r14d
    jnz     .sector

    add     r12, rbx
    sub     r13d, ebx
    jnz     .chunk

.ok:
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

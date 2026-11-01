; ============================================================================
; kata.asm -- ATA PIO, because the firmware's block driver went away
;
; Polled, one sector at a time, primary master only. ATA interrupts are turned
; off rather than handled: this runs once at boot with the PIC carrying only
; the timer, and a driver that waits on a status bit needs no vector.
; ============================================================================

bits 64

ATA_DATA            equ 0x1F0
ATA_SECCOUNT        equ 0x1F2
ATA_LBA_LOW         equ 0x1F3
ATA_LBA_MID         equ 0x1F4
ATA_LBA_HIGH        equ 0x1F5
ATA_DRIVE           equ 0x1F6
ATA_STATUS          equ 0x1F7
ATA_COMMAND         equ 0x1F7
ATA_CONTROL         equ 0x3F6

ATA_SR_ERR          equ 0x01
ATA_SR_DRQ          equ 0x08
ATA_SR_DF           equ 0x20
ATA_SR_BSY          equ 0x80

ATA_CMD_READ_PIO    equ 0x20
ATA_CMD_IDENTIFY    equ 0xEC

ATA_LBA_MASTER      equ 0xE0
ATA_CTRL_NIEN       equ 0x02
ATA_SELECT_MASTER   equ 0xA0

SECTOR_SIZE         equ 512
SECTOR_WORDS        equ SECTOR_SIZE / 2
ATA_TIMEOUT         equ 2000000
ATA_IDENT_SECTORS   equ 60                  ; word 60: LBA28 capacity

; ----------------------------------------------------------------------------
; kata_init -- does anything answer on the primary master?
; Returns EAX = 1, with the sector count in g_ata_sectors.
; ----------------------------------------------------------------------------
kata_init:
    push    rcx
    push    rdx
    push    rdi

    mov     qword [rel g_ata_sectors], 0

    mov     dx, ATA_CONTROL
    mov     al, ATA_CTRL_NIEN
    out     dx, al

    mov     dx, ATA_DRIVE
    mov     al, ATA_SELECT_MASTER
    out     dx, al
    call    kata_settle

    xor     al, al
    mov     dx, ATA_SECCOUNT
    out     dx, al
    mov     dx, ATA_LBA_LOW
    out     dx, al
    mov     dx, ATA_LBA_MID
    out     dx, al
    mov     dx, ATA_LBA_HIGH
    out     dx, al

    mov     dx, ATA_COMMAND
    mov     al, ATA_CMD_IDENTIFY
    out     dx, al

    ; A status of zero means nothing is there at all, which is not the same
    ; as a drive that answers and refuses.
    mov     dx, ATA_STATUS
    in      al, dx
    test    al, al
    jz      .absent

    call    kata_wait_drq
    test    eax, eax
    jz      .absent

    lea rdi, [rel kbuf_sector]
    mov     dx, ATA_DATA
    mov     ecx, SECTOR_WORDS
    rep     insw

    mov     eax, [rel kbuf_sector + ATA_IDENT_SECTORS * 2]
    mov     [rel g_ata_sectors], rax
    mov     eax, 1
    jmp     .done
.absent:
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; kata_read -- RAX = first LBA, RDI = destination, ECX = sector count.
; Returns EAX = 1 on success.
; ----------------------------------------------------------------------------
kata_read:
    push    rbx
    push    rcx
    push    rdi
    mov     rbx, rax
    test    ecx, ecx
    jz      .ok
.next:
    push    rcx
    mov     rax, rbx
    call    kata_read_one
    pop     rcx
    test    eax, eax
    jz      .fail
    inc     rbx
    add     rdi, SECTOR_SIZE
    dec     ecx
    jnz     .next
.ok:
    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     rdi
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kata_read_one -- RAX = LBA, RDI = destination. Returns EAX = 1.
; ----------------------------------------------------------------------------
kata_read_one:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    mov     rbx, rax

    call    kata_wait_idle
    test    eax, eax
    jz      .fail

    mov     dx, ATA_DRIVE
    mov     rax, rbx
    shr     rax, 24
    and     al, 0x0F
    or      al, ATA_LBA_MASTER
    out     dx, al

    mov     dx, ATA_SECCOUNT
    mov     al, 1
    out     dx, al

    mov     dx, ATA_LBA_LOW
    mov     al, bl
    out     dx, al
    mov     dx, ATA_LBA_MID
    mov     rax, rbx
    shr     rax, 8
    out     dx, al
    mov     dx, ATA_LBA_HIGH
    mov     rax, rbx
    shr     rax, 16
    out     dx, al

    mov     dx, ATA_COMMAND
    mov     al, ATA_CMD_READ_PIO
    out     dx, al

    call    kata_wait_drq
    test    eax, eax
    jz      .fail

    mov     dx, ATA_DATA
    mov     ecx, SECTOR_WORDS
    rep     insw
    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kata_wait_idle -- spin until BSY clears. Returns EAX = 1 if it did.
; ----------------------------------------------------------------------------
kata_wait_idle:
    push    rcx
    push    rdx
    mov     ecx, ATA_TIMEOUT
    mov     dx, ATA_STATUS
.poll:
    in      al, dx
    test    al, ATA_SR_BSY
    jz      .idle
    dec     ecx
    jnz     .poll
    xor     eax, eax
    jmp     .done
.idle:
    mov     eax, 1
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; kata_wait_drq -- spin until the drive has data, or admits it will not.
; Returns EAX = 1 if there is a sector waiting.
; ----------------------------------------------------------------------------
kata_wait_drq:
    push    rcx
    push    rdx
    mov     ecx, ATA_TIMEOUT
    mov     dx, ATA_STATUS
.poll:
    in      al, dx
    test    al, ATA_SR_BSY
    jnz     .again
    test    al, ATA_SR_ERR | ATA_SR_DF
    jnz     .bad
    test    al, ATA_SR_DRQ
    jnz     .ready
.again:
    dec     ecx
    jnz     .poll
.bad:
    xor     eax, eax
    jmp     .done
.ready:
    mov     eax, 1
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; kata_settle -- four status reads, the conventional 400 ns after a select
; ----------------------------------------------------------------------------
kata_settle:
    push    rax
    push    rcx
    push    rdx
    mov     dx, ATA_CONTROL
    mov     ecx, 4
.tick:
    in      al, dx
    dec     ecx
    jnz     .tick
    pop     rdx
    pop     rcx
    pop     rax
    ret

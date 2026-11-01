; ============================================================================
; gpt.asm -- find the EFI system partition
;
; GPT is tried first, because that is what a UEFI machine is supposed to have.
; A plain MBR with a type 0xEF partition is accepted as a fallback, which is
; what most hand-made USB sticks turn out to be.
; ============================================================================

bits 64

GPT_SIG_LO      equ 0x20494645                  ; "EFI "
GPT_SIG_HI      equ 0x54524150                  ; "PART"

GPT_MY_LBA      equ 24
GPT_ENT_LBA     equ 72
GPT_ENT_COUNT   equ 80
GPT_ENT_SIZE    equ 84

GPT_E_TYPE      equ 0
GPT_E_FIRST     equ 32
GPT_E_LAST      equ 40

MBR_PART_TABLE  equ 446
MBR_P_TYPE      equ 4
MBR_P_LBA       equ 8
MBR_P_COUNT     equ 12
MBR_TYPE_ESP    equ 0xEF

; ----------------------------------------------------------------------------
; part_find_esp -- locate the EFI system partition on the primary master.
;
; On success sets g_esp_lba / g_esp_sectors and returns EAX = 1.
; ----------------------------------------------------------------------------
part_find_esp:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     qword [abs g_esp_lba], 0
    mov     qword [abs g_esp_sectors], 0

    ; --- GPT header lives at LBA 1 ----------------------------------------
    mov     rax, 1
    mov     ecx, 1
    mov     rdi, BUF_GPT_HDR
    call    ata_read
    test    eax, eax
    jnz     .fail

    mov     rsi, BUF_GPT_HDR
    cmp     dword [rsi], GPT_SIG_LO
    jne     .try_mbr
    cmp     dword [rsi + 4], GPT_SIG_HI
    jne     .try_mbr

    ; --- read the partition entry array -----------------------------------
    mov     r8d, [rsi + GPT_ENT_COUNT]
    mov     r9d, [rsi + GPT_ENT_SIZE]
    test    r8d, r8d
    jz      .try_mbr
    test    r9d, r9d
    jz      .try_mbr

    ; Cap the read at the scratch buffer: 128 entries of 128 bytes is what
    ; every real table uses, and a larger one only means more entries to
    ; ignore.
    mov     eax, r8d
    imul    eax, r9d
    add     eax, SECTOR_SIZE - 1
    shr     eax, 9                              ; -> sectors
    cmp     eax, 32
    jbe     .have_count
    mov     eax, 32
    mov     r8d, 128
.have_count:
    mov     ecx, eax
    mov     rax, [rsi + GPT_ENT_LBA]
    mov     rdi, BUF_GPT_ENT
    call    ata_read
    test    eax, eax
    jnz     .fail

    ; --- scan for the EFI system partition type ---------------------------
    mov     rbx, BUF_GPT_ENT
.entry:
    mov     rsi, rbx
    lea     rdi, [rel esp_type_guid]
    mov     ecx, 16
    call    mem_cmp
    jne     .next_entry

    mov     rax, [rbx + GPT_E_FIRST]
    mov     [abs g_esp_lba], rax
    mov     rdx, [rbx + GPT_E_LAST]
    sub     rdx, rax
    inc     rdx
    mov     [abs g_esp_sectors], rdx
    jmp     .found

.next_entry:
    movzx   rax, r9w
    add     rbx, rax
    dec     r8d
    jnz     .entry
    ; A valid GPT with no ESP in it: an MBR scan would only find the
    ; protective entry, so stop here.
    jmp     .fail

    ; --- MBR fallback ------------------------------------------------------
.try_mbr:
    mov     rax, 0
    mov     ecx, 1
    mov     rdi, BUF_SECTOR
    call    ata_read
    test    eax, eax
    jnz     .fail

    mov     rsi, BUF_SECTOR
    cmp     word [rsi + 510], 0xAA55
    jne     .fail

    lea     rbx, [rsi + MBR_PART_TABLE]
    mov     ecx, 4
.mbr_entry:
    cmp     byte [rbx + MBR_P_TYPE], MBR_TYPE_ESP
    jne     .mbr_next
    mov     eax, [rbx + MBR_P_LBA]
    mov     [abs g_esp_lba], rax
    mov     eax, [rbx + MBR_P_COUNT]
    mov     [abs g_esp_sectors], rax
    jmp     .found
.mbr_next:
    add     rbx, 16
    dec     ecx
    jnz     .mbr_entry
    jmp     .fail

.found:
    cmp     qword [abs g_esp_sectors], 0
    je      .fail
    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; C12A7328-F81F-11D2-BA4B-00A0C93EC93B, in the mixed-endian form GPT stores:
; the first three fields little-endian, the last two as written.
; ----------------------------------------------------------------------------
align 8
esp_type_guid:
    dd 0xC12A7328
    dw 0xF81F
    dw 0x11D2
    db 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B

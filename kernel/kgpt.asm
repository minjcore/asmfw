; ============================================================================
; kgpt.asm -- find the EFI system partition
;
; Only GPT, and only the type GUID. The firmware also accepts an MBR with a
; type 0xEF partition; this kernel boots one disk, and that disk is a GPT one.
; ============================================================================

bits 64

GPT_HEADER_LBA      equ 1
GPT_ENTRIES_LBA     equ 0x48                ; UINT64, into the header
GPT_ENTRY_COUNT     equ 0x50                ; UINT32
GPT_ENTRY_SIZE      equ 0x54                ; UINT32

GPT_ENT_TYPE        equ 0x00                ; the type GUID
GPT_ENT_FIRST_LBA   equ 0x20
GPT_ENT_LAST_LBA    equ 0x28

GPT_MAX_ENTRIES     equ 128
GPT_MAX_ENTRY_BYTES equ 128

; ----------------------------------------------------------------------------
; kgpt_find_esp -- Returns EAX = 1 with g_esp_lba and g_esp_sectors set.
; ----------------------------------------------------------------------------
kgpt_find_esp:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     qword [rel g_esp_lba], 0

    mov     rax, GPT_HEADER_LBA
    lea rdi, [rel kbuf_sector]
    mov     ecx, 1
    call    kata_read
    test    eax, eax
    jz      .fail

    lea     rsi, [rel gpt_signature]
    lea rdi, [rel kbuf_sector]
    mov     ecx, 8
    repe cmpsb
    jne     .fail

    mov     r8d, [rel kbuf_sector + GPT_ENTRY_COUNT]
    cmp     r8d, GPT_MAX_ENTRIES
    jbe     .count_ok
    mov     r8d, GPT_MAX_ENTRIES
.count_ok:
    test    r8d, r8d
    jz      .fail

    mov     r9d, [rel kbuf_sector + GPT_ENTRY_SIZE]
    cmp     r9d, GPT_MAX_ENTRY_BYTES
    jb      .fail                           ; smaller than the spec allows

    ; How many sectors that array occupies, rounded up
    mov     eax, r8d
    imul    eax, r9d
    add     eax, SECTOR_SIZE - 1
    shr     eax, 9
    mov     ecx, eax
    mov     rax, [rel kbuf_sector + GPT_ENTRIES_LBA]
    lea rdi, [rel kbuf_gpt]
    call    kata_read
    test    eax, eax
    jz      .fail

    lea rbx, [rel kbuf_gpt]
.entry:
    lea     rsi, [rel guid_esp_type]
    lea     rdi, [rbx + GPT_ENT_TYPE]
    mov     ecx, GUID_SIZE
    repe cmpsb
    je      .found
    movzx   rax, r9w
    add     rbx, rax
    dec     r8d
    jnz     .entry
.fail:
    xor     eax, eax
    jmp     .done

.found:
    mov     rax, [rbx + GPT_ENT_FIRST_LBA]
    mov     [rel g_esp_lba], rax
    mov     rdx, [rbx + GPT_ENT_LAST_LBA]
    sub     rdx, rax
    inc     rdx
    mov     [rel g_esp_sectors], rdx
    mov     eax, 1
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
gpt_signature:  db "EFI PART"

guid_esp_type:                              ; C12A7328-F81F-11D2-BA4B-00A0C93EC93B
    dd 0xC12A7328
    dw 0xF81F
    dw 0x11D2
    db 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B

align 8
g_esp_lba:      dq 0
g_esp_sectors:  dq 0
g_ata_sectors:  dq 0

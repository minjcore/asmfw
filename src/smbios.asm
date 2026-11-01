; ============================================================================
; smbios.asm -- the SMBIOS tables QEMU describes through fw_cfg
;
; QEMU builds the whole structure table itself and offers it as two fw_cfg
; files: etc/smbios/smbios-tables, the structures, and etc/smbios/smbios-anchor,
; the entry point that says where they are. The anchor arrives with that
; address left at zero, because only firmware knows where the tables will
; land. So the job is: place both, write the address in, redo the checksums
; the address invalidated, and publish the anchor in the configuration table.
;
; There is no loader script here, unlike ACPI: one pointer, one or two
; checksums, and which ones depends only on the anchor's signature.
; ============================================================================

bits 64

; ---------------------------------------------------------------------------
; The 64-bit entry point, SMBIOS 3.x: "_SM3_"
; ---------------------------------------------------------------------------
SM3_CHECKSUM        equ 0x05                    ; UINT8, over SM3_LENGTH bytes
SM3_LENGTH          equ 0x06                    ; UINT8
SM3_MAJOR           equ 0x07
SM3_MINOR           equ 0x08
SM3_TABLE_MAX       equ 0x0C                    ; UINT32, the table's size bound
SM3_TABLE_ADDR      equ 0x10                    ; UINT64

; ---------------------------------------------------------------------------
; The 32-bit entry point, SMBIOS 2.1+: "_SM_", with "_DMI_" inside it.
; Two checksums: one over the whole structure, and one over the legacy DMI
; part starting at 0x10, which a DMI-era reader checks on its own.
; ---------------------------------------------------------------------------
SM2_CHECKSUM        equ 0x04                    ; UINT8, over SM2_LENGTH bytes
SM2_LENGTH          equ 0x05                    ; UINT8
SM2_MAJOR           equ 0x06
SM2_MINOR           equ 0x07
SM2_DMI             equ 0x10                    ; start of the "_DMI_" part
SM2_DMI_CHECKSUM    equ 0x15                    ; UINT8, over SM2_DMI_LENGTH
SM2_DMI_LENGTH      equ 15
SM2_TABLE_LEN       equ 0x16                    ; UINT16
SM2_TABLE_ADDR      equ 0x18                    ; UINT32
SM2_COUNT           equ 0x1C                    ; UINT16, structures

SMBIOS_ANCHOR_MAX   equ 0x20                    ; both kinds fit in 32 bytes
SMBIOS_TABLES_OFF   equ 0x40                    ; where the tables go, past it

; A structure: type, formatted length, handle, then a string set ended by a
; double NUL. Type 127 is the end-of-table marker.
SMS_TYPE            equ 0
SMS_LENGTH          equ 1
SMS_HEADER_SIZE     equ 4
SMS_TYPE_END        equ 127

; ----------------------------------------------------------------------------
; smbios_init -- place QEMU's SMBIOS tables and publish the entry point.
; Returns EAX = 1 if a configuration table was installed, 0 otherwise.
;
; Must run after acpi_init, which is what reads the fw_cfg directory; this
; only looks names up in it. Must run after efi_init for the same reason
; acpi_init must: installing a table rewrites the system table header.
; ----------------------------------------------------------------------------
smbios_init:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    cmp     dword [abs g_fwcfg_files], 0
    je      .absent

    lea     rsi, [rel name_smbios_anchor]
    call    fwcfg_find
    test    eax, eax
    jz      .absent
    test    edx, edx
    jz      .absent
    cmp     edx, SMBIOS_ANCHOR_MAX
    ja      .bad
    mov     r12d, eax                           ; anchor selector
    mov     r13d, edx                           ; anchor size

    lea     rsi, [rel name_smbios_tables]
    call    fwcfg_find
    test    eax, eax
    jz      .absent
    test    edx, edx
    jz      .absent
    mov     r14d, eax                           ; tables selector
    mov     r15d, edx                           ; tables size

    ; One allocation for both: the anchor at the front, page aligned (more
    ; than the 16 bytes a legacy scan would want), and the tables after it.
    ; Runtime services data, as the UEFI spec asks of SMBIOS: an OS may read
    ; these after ExitBootServices, so they must not be reclaimed.
    mov     ecx, r15d
    add     ecx, SMBIOS_TABLES_OFF + 0xFFF
    shr     ecx, 12
    mov     edx, EfiRuntimeServicesData
    call    mem_alloc_pages
    test    rax, rax
    jz      .bad
    mov     rbx, rax                            ; the anchor

    mov     rdi, rbx
    mov     ecx, SMBIOS_TABLES_OFF
    xor     eax, eax
    rep     stosb

    mov     eax, r12d
    call    fwcfg_select
    mov     rdi, rbx
    mov     ecx, r13d
    call    fwcfg_read

    mov     eax, r14d
    call    fwcfg_select
    lea     rdi, [rbx + SMBIOS_TABLES_OFF]
    mov     ecx, r15d
    call    fwcfg_read

    lea     rdx, [rbx + SMBIOS_TABLES_OFF]      ; where the tables now are

    cmp     dword [rbx], '_SM3'
    jne     .not3
    cmp     byte [rbx + 4], '_'
    jne     .not3

    ; --- 3.x: a 64-bit address, one checksum ----------------------------------
    movzx   ecx, byte [rbx + SM3_LENGTH]
    cmp     ecx, r13d
    ja      .bad
    mov     [rbx + SM3_TABLE_ADDR], rdx
    lea     rsi, [rbx + SM3_CHECKSUM]
    mov     rdi, rbx
    call    smbios_fix_sum
    lea     rcx, [rel guid_smbios3]
    movzx   r12d, byte [rbx + SM3_MAJOR]
    movzx   r13d, byte [rbx + SM3_MINOR]
    jmp     .publish

.not3:
    cmp     dword [rbx], '_SM_'
    jne     .bad

    ; --- 2.x: a 32-bit address, and two checksums -------------------------
    ; The DMI part first: the outer checksum covers it, so it has to be final
    ; before the outer one is computed.
    movzx   ecx, byte [rbx + SM2_LENGTH]
    cmp     ecx, r13d
    ja      .bad
    mov     rax, rdx
    shr     rax, 32
    jnz     .bad                                ; a 2.x reader cannot reach it
    mov     [rbx + SM2_TABLE_ADDR], edx
    push    rcx
    lea     rsi, [rbx + SM2_DMI_CHECKSUM]
    lea     rdi, [rbx + SM2_DMI]
    mov     ecx, SM2_DMI_LENGTH
    call    smbios_fix_sum
    pop     rcx
    lea     rsi, [rbx + SM2_CHECKSUM]
    mov     rdi, rbx
    call    smbios_fix_sum
    lea     rcx, [rel guid_smbios]
    movzx   r12d, byte [rbx + SM2_MAJOR]
    movzx   r13d, byte [rbx + SM2_MINOR]

.publish:
    mov     rdx, rbx
    call    bs_install_configuration_table

    ; The log line counts the structures by walking them. Every one of them
    ; has to be stepped over by its own length and its own strings, so a
    ; count that comes out right is evidence the table arrived whole.
    lea     rsi, [rbx + SMBIOS_TABLES_OFF]
    mov     ecx, r15d
    call    smbios_count
    mov     r14d, eax

    puts    msg_smbios
    mov     eax, r12d
    call    con_putdec
    mov     al, '.'
    call    con_putc
    mov     eax, r13d
    call    con_putdec
    putsi   ", "
    mov     eax, r14d
    call    con_putdec
    putsi   " structures, entry point at "
    mov     rax, rbx
    call    con_puthex64
    mov     al, 10
    call    con_putc

    mov     eax, 1
    jmp     .done

.absent:
    puts    msg_no_smbios
    jmp     .fail
.bad:
    puts    msg_smbios_bad
.fail:
    xor     eax, eax
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; smbios_fix_sum -- RDI = start, ECX = length, RSI = the checksum byte, which
; lies inside the range. Makes the range sum to zero modulo 256.
; ----------------------------------------------------------------------------
smbios_fix_sum:
    push    rax
    push    rcx
    push    rdi
    mov     byte [rsi], 0
    xor     eax, eax
.sum:
    add     al, [rdi]
    inc     rdi
    dec     ecx
    jnz     .sum
    neg     al
    mov     [rsi], al
    pop     rdi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; smbios_count -- RSI = the structure table, ECX = its size in bytes.
; Returns EAX = structures up to and including the end marker, or 0 if the
; walk runs off the end before it finds one.
; ----------------------------------------------------------------------------
smbios_count:
    push    rcx
    push    rdx
    push    rsi
    push    r8
    lea     rdx, [rsi + rcx]                    ; one past the end
    xor     eax, eax
.structure:
    lea     rcx, [rsi + SMS_HEADER_SIZE]
    cmp     rcx, rdx
    ja      .torn
    inc     eax
    mov     cl, [rsi + SMS_TYPE]
    movzx   r8d, byte [rsi + SMS_LENGTH]
    cmp     r8d, SMS_HEADER_SIZE
    jb      .torn
    add     rsi, r8                             ; the strings start here
.strings:
    lea     r8, [rsi + 1]
    cmp     r8, rdx
    jae     .torn
    cmp     word [rsi], 0
    je      .ended
    inc     rsi
    jmp     .strings
.ended:
    add     rsi, 2
    cmp     cl, SMS_TYPE_END
    jne     .structure
    jmp     .done
.torn:
    xor     eax, eax
.done:
    pop     r8
    pop     rsi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
align 8
guid_smbios:                                    ; EB9D2D31-2D88-11D3-9A16-0090273FC14D
    dd 0xEB9D2D31
    dw 0x2D88
    dw 0x11D3
    db 0x9A, 0x16, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D

guid_smbios3:                                   ; F2FD1544-9794-4A2C-992E-E5BBCF20E394
    dd 0xF2FD1544
    dw 0x9794
    dw 0x4A2C
    db 0x99, 0x2E, 0xE5, 0xBB, 0xCF, 0x20, 0xE3, 0x94

name_smbios_anchor: db "etc/smbios/smbios-anchor", 0
name_smbios_tables: db "etc/smbios/smbios-tables", 0

CSTR msg_smbios,     "[DXE] SMBIOS "
CSTR msg_no_smbios,  "[DXE] fw_cfg offers no SMBIOS tables", 10
CSTR msg_smbios_bad, "[DXE] the SMBIOS anchor is not one this firmware understands", 10

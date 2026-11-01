; ============================================================================
; efi_var.asm -- UEFI variables, kept in RAM
;
; GetVariable, SetVariable, GetNextVariableName and QueryVariableInfo over a
; fixed array of records. Nothing here is persistent: the flash this firmware
; runs from is read-only to it, so a variable lives until the machine resets.
; That is exactly right for a volatile variable, and for a non-volatile one it
; is what OVMF itself does when it is built without a variable store (its
; "emulated variables" mode): the write is accepted and kept for the life of
; the boot. A loader that writes a variable and reads it back -- which is the
; common case -- cannot tell the difference.
;
; The store is allocated as runtime services data, since an OS may call these
; after ExitBootServices. After that call, a variable without the runtime
; access attribute becomes invisible, as the specification requires.
; ============================================================================

bits 64

; ---------------------------------------------------------------------------
; A record. Fixed size, so a slot is either free or one whole variable.
; ---------------------------------------------------------------------------
VR_USED         equ 0x000                       ; UINT32, nonzero if in use
VR_ATTR         equ 0x004                       ; UINT32
VR_DSIZE        equ 0x008                       ; UINT32, bytes of data
VR_NSIZE        equ 0x00C                       ; UINT32, bytes of name, NUL included
VR_GUID         equ 0x010
VR_NAME         equ 0x020
VR_DATA         equ 0x120
VAR_NAME_MAX    equ VR_DATA - VR_NAME           ; 256 bytes: 127 CHAR16 and a NUL
VAR_REC_SIZE    equ 0x800
VAR_DATA_MAX    equ VAR_REC_SIZE - VR_DATA      ; 1760 bytes
VAR_SLOTS       equ 32
VAR_STORE_PAGES equ (VAR_SLOTS * VAR_REC_SIZE) / 4096

EFI_VARIABLE_NON_VOLATILE       equ 0x01
EFI_VARIABLE_BOOTSERVICE_ACCESS equ 0x02
EFI_VARIABLE_RUNTIME_ACCESS     equ 0x04
EFI_VARIABLE_HW_ERROR_RECORD    equ 0x08
EFI_VARIABLE_AUTH_WRITE         equ 0x10
EFI_VARIABLE_TIME_AUTH_WRITE    equ 0x20
EFI_VARIABLE_APPEND_WRITE       equ 0x40

; What this store does not offer: authenticated writes need the Secure Boot
; key machinery, and hardware error records a reserved region of their own.
VAR_ATTR_REFUSED equ EFI_VARIABLE_HW_ERROR_RECORD | EFI_VARIABLE_AUTH_WRITE \
                     | EFI_VARIABLE_TIME_AUTH_WRITE

; ----------------------------------------------------------------------------
; var_init -- allocate the store and empty it.
; Returns EAX = 1 if there is one.
; ----------------------------------------------------------------------------
var_init:
    push    rcx
    push    rdx
    push    rdi
    mov     ecx, VAR_STORE_PAGES
    mov     edx, EfiRuntimeServicesData
    call    mem_alloc_pages
    mov     [abs g_var_store], rax
    test    rax, rax
    jz      .none
    mov     rdi, rax
    mov     ecx, VAR_SLOTS * VAR_REC_SIZE / 8
    xor     eax, eax
    rep     stosq
    puts    msg_var
    mov     eax, 1
    jmp     .done
.none:
    puts    msg_no_var
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; var_name_size -- RSI = a CHAR16 name. Returns RAX = its size in bytes with
; the NUL, or 0 if it does not fit a record.
; ----------------------------------------------------------------------------
var_name_size:
    push    rcx
    xor     ecx, ecx
.next:
    cmp     word [rsi + rcx], 0
    je      .end
    add     ecx, 2
    cmp     ecx, VAR_NAME_MAX
    jb      .next
    xor     eax, eax
    pop     rcx
    ret
.end:
    lea     eax, [rcx + 2]
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; var_find -- RSI = a CHAR16 name, RDI = a GUID.
; Returns RAX = the record holding that variable, or 0. Finds hidden
; variables too; var_visible is the separate question.
; ----------------------------------------------------------------------------
var_find:
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, [abs g_var_store]
    test    rbx, rbx
    jz      .miss
    mov     edx, VAR_SLOTS
.slot:
    cmp     dword [rbx + VR_USED], 0
    je      .next
    ; GUID: two qwords.
    mov     rax, [rdi]
    cmp     rax, [rbx + VR_GUID]
    jne     .next
    mov     rax, [rdi + 8]
    cmp     rax, [rbx + VR_GUID + 8]
    jne     .next
    ; Name: CHAR16 by CHAR16, case sensitive, as the specification has it.
    xor     ecx, ecx
.char:
    mov     ax, [rsi + rcx]
    cmp     ax, [rbx + VR_NAME + rcx]
    jne     .next
    test    ax, ax
    jz      .hit
    add     ecx, 2
    cmp     ecx, VAR_NAME_MAX
    jb      .char
.next:
    add     rbx, VAR_REC_SIZE
    dec     edx
    jnz     .slot
.miss:
    xor     eax, eax
    jmp     .done
.hit:
    mov     rax, rbx
.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; var_visible -- RAX = a record. ZF clear if the caller may see it: always
; before ExitBootServices, and afterwards only with runtime access.
; ----------------------------------------------------------------------------
var_visible:
    cmp     dword [abs g_bs_exited], 0
    je      .yes
    test    dword [rax + VR_ATTR], EFI_VARIABLE_RUNTIME_ACCESS
    ret
.yes:
    test    rax, rax                            ; a record address is nonzero
    ret

; ----------------------------------------------------------------------------
; rt_get_variable -- GetVariable(Name, Guid, Attributes OPTIONAL, DataSize,
; Data OPTIONAL).
; ----------------------------------------------------------------------------
rt_get_variable:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    mov     r12, [rsp + 0x28 + 4*8]             ; Data, the fifth argument

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    test    r9, r9
    jz      .bad

    mov     rsi, rcx
    mov     rdi, rdx
    call    var_find
    test    rax, rax
    jz      .absent
    call    var_visible
    jz      .absent
    mov     rbx, rax

    test    r8, r8
    jz      .no_attr
    mov     eax, [rbx + VR_ATTR]
    mov     [r8], eax
.no_attr:
    mov     ecx, [rbx + VR_DSIZE]
    cmp     [r9], rcx
    jb      .small
    test    r12, r12
    jz      .bad
    mov     [r9], rcx
    lea     rsi, [rbx + VR_DATA]
    mov     rdi, r12
    rep     movsb
    xor     eax, eax
    jmp     .done
.small:
    mov     [r9], rcx                           ; how much it would take
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done
.absent:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; rt_set_variable -- SetVariable(Name, Guid, Attributes, DataSize, Data).
;
; Attributes of zero, or a DataSize of zero without APPEND_WRITE, deletes.
; An existing variable can only be rewritten with the attributes it has; the
; one exception is APPEND_WRITE, which is a request rather than an attribute.
; ----------------------------------------------------------------------------
rt_set_variable:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, [rsp + 0x28 + 7*8]             ; Data, the fifth argument
    mov     r13, r9                             ; DataSize
    mov     r14d, r8d                           ; Attributes
    mov     r15, rdx                            ; Guid

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    cmp     word [rcx], 0
    je      .bad
    test    r14d, VAR_ATTR_REFUSED
    jnz     .unsupported

    mov     rsi, rcx
    mov     rdi, r15
    call    var_find
    mov     rbx, rax                            ; the record, or 0

    ; --- delete ---------------------------------------------------------------
    mov     eax, r14d
    and     eax, ~EFI_VARIABLE_APPEND_WRITE
    jz      .delete
    test    r13, r13
    jnz     .write
    test    r14d, EFI_VARIABLE_APPEND_WRITE
    jnz     .append_nothing
.delete:
    test    rbx, rbx
    jz      .absent
    mov     rax, rbx
    call    var_visible
    jz      .absent
    mov     dword [rbx + VR_USED], 0
    jmp     .ok

    ; Appending nothing changes nothing, but the variable has to exist.
.append_nothing:
    test    rbx, rbx
    jz      .absent
    jmp     .ok

    ; --- write ----------------------------------------------------------------
.write:
    test    r12, r12
    jz      .bad
    ; Runtime access without boot service access is not a combination the
    ; specification allows; after ExitBootServices, only runtime variables
    ; may be written at all.
    test    r14d, EFI_VARIABLE_RUNTIME_ACCESS
    jz      .bs_only
    test    r14d, EFI_VARIABLE_BOOTSERVICE_ACCESS
    jz      .bad
    jmp     .access_ok
.bs_only:
    cmp     dword [abs g_bs_exited], 0
    jne     .bad
.access_ok:
    test    rbx, rbx
    jz      .create

    ; An existing variable: the attributes must match, APPEND aside.
    mov     eax, [rbx + VR_ATTR]
    mov     edx, r14d
    and     edx, ~EFI_VARIABLE_APPEND_WRITE
    cmp     eax, edx
    jne     .bad
    mov     ecx, [rbx + VR_DSIZE]               ; where the new bytes go
    test    r14d, EFI_VARIABLE_APPEND_WRITE
    jnz     .store
    xor     ecx, ecx                            ; a replacement starts at zero
    jmp     .store

.create:
    ; RSI is still the name: var_find preserves it, and nothing since has
    ; touched it.
    call    var_name_size
    test    eax, eax
    jz      .full
    mov     edx, eax                            ; name bytes
    ; A free slot.
    mov     rbx, [abs g_var_store]
    test    rbx, rbx
    jz      .full
    mov     ecx, VAR_SLOTS
.slot:
    cmp     dword [rbx + VR_USED], 0
    je      .have_slot
    add     rbx, VAR_REC_SIZE
    dec     ecx
    jnz     .slot
    jmp     .full
.have_slot:
    cmp     r13, VAR_DATA_MAX
    ja      .full
    mov     [rbx + VR_NSIZE], edx
    mov     eax, r14d
    and     eax, ~EFI_VARIABLE_APPEND_WRITE
    mov     [rbx + VR_ATTR], eax
    mov     rax, [r15]
    mov     [rbx + VR_GUID], rax
    mov     rax, [r15 + 8]
    mov     [rbx + VR_GUID + 8], rax
    lea     rdi, [rbx + VR_NAME]
    mov     ecx, edx
    rep     movsb
    xor     ecx, ecx

    ; RBX = the record, ECX = the offset in its data to write at.
.store:
    mov     rax, rcx
    add     rax, r13
    cmp     rax, VAR_DATA_MAX
    ja      .full
    mov     [rbx + VR_DSIZE], eax
    lea     rdi, [rbx + VR_DATA + rcx]
    mov     rsi, r12
    mov     rcx, r13
    rep     movsb
    mov     dword [rbx + VR_USED], 1
.ok:
    xor     eax, eax
    jmp     .done
.absent:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.full:
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; rt_get_next_variable_name -- GetNextVariableName(NameSize, Name, Guid).
;
; An empty Name starts the walk; otherwise Name and Guid say where it got to,
; and are overwritten with the variable after that one.
; ----------------------------------------------------------------------------
rt_get_next_variable_name:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad
    mov     r12, rcx                            ; NameSize
    mov     r13, rdx                            ; Name

    mov     rbx, [abs g_var_store]
    test    rbx, rbx
    jz      .end
    cmp     word [r13], 0
    je      .scan_from_rbx

    ; Where the caller got to. A name that is not there is a caller error,
    ; not the end of the walk.
    mov     rsi, r13
    mov     rdi, r8
    call    var_find
    test    rax, rax
    jz      .bad
    call    var_visible
    jz      .bad
    lea     rbx, [rax + VAR_REC_SIZE]

.scan_from_rbx:
    mov     rax, [abs g_var_store]
    add     rax, VAR_SLOTS * VAR_REC_SIZE
.scan:
    cmp     rbx, rax
    jae     .end
    cmp     dword [rbx + VR_USED], 0
    je      .scan_next
    push    rax
    mov     rax, rbx
    call    var_visible
    pop     rax
    jnz     .found
.scan_next:
    add     rbx, VAR_REC_SIZE
    jmp     .scan

.found:
    mov     ecx, [rbx + VR_NSIZE]
    cmp     [r12], rcx
    jb      .small
    mov     [r12], rcx
    lea     rsi, [rbx + VR_NAME]
    mov     rdi, r13
    rep     movsb
    mov     rax, [rbx + VR_GUID]
    mov     [r8], rax
    mov     rax, [rbx + VR_GUID + 8]
    mov     [r8 + 8], rax
    xor     eax, eax
    jmp     .done
.small:
    mov     [r12], rcx
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done
.end:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; rt_query_variable_info -- QueryVariableInfo(Attributes,
; MaximumVariableStorageSize, RemainingVariableStorageSize, MaximumVariableSize).
;
; Counted in whole records, since that is how the store is spent: a one-byte
; variable costs a slot exactly as a full one does.
; ----------------------------------------------------------------------------
rt_query_variable_info:
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad
    test    r9, r9
    jz      .bad
    test    ecx, VAR_ATTR_REFUSED
    jnz     .unsupported

    mov     qword [rdx], VAR_SLOTS * (VAR_NAME_MAX + VAR_DATA_MAX)
    mov     qword [r9], VAR_NAME_MAX + VAR_DATA_MAX

    push    rbx
    xor     eax, eax
    mov     rbx, [abs g_var_store]
    test    rbx, rbx
    jz      .counted
    mov     ecx, VAR_SLOTS
.slot:
    cmp     dword [rbx + VR_USED], 0
    jne     .used
    inc     eax
.used:
    add     rbx, VAR_REC_SIZE
    dec     ecx
    jnz     .slot
.counted:
    imul    rax, VAR_NAME_MAX + VAR_DATA_MAX
    mov     [r8], rax
    pop     rbx
    xor     eax, eax
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    ret

CSTR msg_var,    "[DXE] variables: 32 slots of 1760 bytes, in RAM", 10
CSTR msg_no_var, "[DXE] no memory for a variable store", 10

; ============================================================================
; ulib.inc -- the whole of userspace's library
;
; Assembled into each program rather than shared at run time: there is no
; loader that could resolve a call between two images, and no second image to
; resolve it against.
; ============================================================================

; ----------------------------------------------------------------------------
; u_write -- RDI = buffer, RSI = length. Returns RAX.
; ----------------------------------------------------------------------------
u_write:
    mov     eax, SYS_WRITE
    syscall
    ret

; ----------------------------------------------------------------------------
; u_read -- RDI = buffer, RSI = length, RDX = milliseconds to wait, 0 = forever.
; Returns RAX = how many bytes arrived, 0 if the wait ran out.
; ----------------------------------------------------------------------------
u_read:
    mov     eax, SYS_READ
    syscall
    ret

; ----------------------------------------------------------------------------
; u_exit -- RDI = status. Does not return.
; ----------------------------------------------------------------------------
u_exit:
    mov     eax, SYS_EXIT
    syscall
.stuck:
    jmp     .stuck

; ----------------------------------------------------------------------------
; u_hex -- RAX = value, RDI = where to write, ECX = how many digits.
; Most significant first, in place, over the placeholder in a message.
; ----------------------------------------------------------------------------
u_hex:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    mov     edx, ecx
.digit:
    dec     edx
    mov     rbx, rax
    mov     ecx, edx
    shl     ecx, 2
    shr     rbx, cl
    and     ebx, 0x0F
    cmp     bl, 10
    jb      .decimal
    add     bl, 'a' - 10
    jmp     .emit
.decimal:
    add     bl, '0'
.emit:
    mov     [rdi], bl
    inc     rdi
    test    edx, edx
    jnz     .digit
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; u_dec -- RAX = value, RDI = where to write, ECX = how many digits.
; Filled from the right, so the field is fixed width.
; ----------------------------------------------------------------------------
u_dec:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    add     rdi, rcx
    dec     rdi
    mov     ebx, 10
.digit:
    xor     edx, edx
    div     rbx
    add     dl, '0'
    mov     [rdi], dl
    dec     rdi
    dec     ecx
    jnz     .digit
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

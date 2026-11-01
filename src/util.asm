; ============================================================================
; util.asm -- console output primitives and memory helpers
;
; Internal calling convention (not the EFI one): arguments in registers as
; documented per routine, and every routine preserves everything it touches.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; con_putc -- emit AL to every console the firmware currently has
; ----------------------------------------------------------------------------
con_putc:
    push    rax
    cmp     al, 10                          ; LF -> CRLF for the serial log
    jne     .raw
    mov     al, 13
    call    ser_putc
    mov     al, 10
.raw:
    call    ser_putc
    pop     rax
    push    rax
    cmp     dword [abs g_fb_ok], 0
    je      .done
    call    fb_putc
.done:
    pop     rax
    ret

; ----------------------------------------------------------------------------
; con_puts -- print the NUL-terminated string at RSI
; ----------------------------------------------------------------------------
con_puts:
    push    rax
    push    rsi
.next:
    lodsb
    test    al, al
    jz      .done
    call    con_putc
    jmp     .next
.done:
    pop     rsi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; con_puthex -- print RAX as CL hex digits (CL = 2, 4, 8 or 16)
; ----------------------------------------------------------------------------
con_puthex:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    movzx   rdx, cl
    shl     rdx, 2                          ; digits -> bit position of the top nibble
    mov     rbx, rax
.digit:
    sub     rdx, 4
    mov     rcx, rdx
    mov     rax, rbx
    shr     rax, cl
    and     al, 0x0F
    cmp     al, 10
    jb      .num
    add     al, 'A' - 10 - '0'
.num:
    add     al, '0'
    push    rdx
    call    con_putc
    pop     rdx
    test    rdx, rdx
    jnz     .digit
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

con_puthex8:
    push    rcx
    mov     cl, 2
    call    con_puthex
    pop     rcx
    ret

con_puthex16:
    push    rcx
    mov     cl, 4
    call    con_puthex
    pop     rcx
    ret

con_puthex32:
    push    rcx
    mov     cl, 8
    call    con_puthex
    pop     rcx
    ret

con_puthex64:
    push    rcx
    mov     cl, 16
    call    con_puthex
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; con_putdec -- print RAX in decimal
; ----------------------------------------------------------------------------
con_putdec:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    mov     rcx, 10
    xor     rbx, rbx                        ; digit count
    test    rax, rax
    jnz     .split
    mov     al, '0'
    call    con_putc
    jmp     .done
.split:
    xor     rdx, rdx
    div     rcx
    push    rdx                             ; remainder, least significant first
    inc     rbx
    test    rax, rax
    jnz     .split
.emit:
    pop     rax
    add     al, '0'
    call    con_putc
    dec     rbx
    jnz     .emit
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; mem_set -- fill RCX bytes at RDI with AL
; ----------------------------------------------------------------------------
mem_set:
    push    rdi
    push    rcx
    push    rax
    rep stosb
    pop     rax
    pop     rcx
    pop     rdi
    ret

; ----------------------------------------------------------------------------
; mem_copy -- copy RCX bytes from RSI to RDI
; ----------------------------------------------------------------------------
mem_copy:
    push    rdi
    push    rsi
    push    rcx
    rep movsb
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ----------------------------------------------------------------------------
; mem_cmp -- compare RCX bytes at RSI and RDI; ZF set if equal
; ----------------------------------------------------------------------------
mem_cmp:
    push    rdi
    push    rsi
    push    rcx
    repe cmpsb
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ----------------------------------------------------------------------------
; panic -- print RSI and stop. Never returns.
; ----------------------------------------------------------------------------
panic:
    push    rsi
    lea     rsi, [rel .banner]
    call    con_puts
    pop     rsi
    call    con_puts
    mov     al, 10
    call    con_putc
.halt:
    cli
    hlt
    jmp     .halt
.banner:
    db 10, "!! PANIC: ", 0

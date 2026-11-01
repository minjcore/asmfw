; ============================================================================
; kcon.asm -- the kernel's own console
;
; It exists because the firmware's does not survive ExitBootServices. ConOut
; is a boot service; the framebuffer behind it is just memory, and memory is
; still there afterwards. So the kernel keeps the address and the geometry,
; and re-implements the part that turns bytes into pixels.
;
; Everything is written twice, to COM1 and to the framebuffer, for the same
; reason the firmware does it: one of the two is always the one you can read.
; ============================================================================

bits 64

%include "font.inc"

; ----------------------------------------------------------------------------
; kc_init -- derive the text grid from the mode that was saved before exit
; ----------------------------------------------------------------------------
kc_init:
    push    rax
    push    rcx
    push    rdx
    push    rdi

    call    kser_init

    mov     dword [rel kc_x], 0
    mov     dword [rel kc_y], 0
    mov     dword [rel kc_fg], KC_FG
    mov     dword [rel kc_bg], KC_BG

    cmp     dword [rel kc_fb_ok], 0
    je      .done

    mov     eax, [rel kc_w]
    sub     eax, KC_MARGIN_X * 2
    xor     edx, edx
    mov     ecx, FONT_W
    div     ecx
    mov     [rel kc_cols], eax

    mov     eax, [rel kc_h]
    sub     eax, KC_MARGIN_Y * 2
    xor     edx, edx
    mov     ecx, FONT_H
    div     ecx
    mov     [rel kc_rows], eax

    call    kc_clear
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kc_clear -- paint the whole framebuffer in the background colour
; ----------------------------------------------------------------------------
kc_clear:
    push    rax
    push    rcx
    push    rdi
    cmp     dword [rel kc_fb_ok], 0
    je      .done
    mov     eax, [rel kc_pitch]
    imul    eax, dword [rel kc_h]
    mov     ecx, eax
    shr     ecx, 2
    mov     rdi, [rel kc_fb]
    mov     eax, [rel kc_bg]
    rep     stosd
    mov     dword [rel kc_x], 0
    mov     dword [rel kc_y], 0
.done:
    pop     rdi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kc_putc -- AL. A line feed is expanded for the serial side only; the
; framebuffer treats it as the cursor move it is.
; ----------------------------------------------------------------------------
kc_putc:
    push    rax
    cmp     al, CHAR_LF
    jne     .serial
    mov     al, CHAR_CR
    call    kser_putc
    mov     al, CHAR_LF
.serial:
    call    kser_putc
    cmp     dword [rel kc_fb_ok], 0
    je      .done
    call    kfb_putc
.done:
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kc_puts -- RSI = a NUL-terminated string
; ----------------------------------------------------------------------------
kc_puts:
    push    rax
    push    rsi
.next:
    lodsb
    test    al, al
    jz      .done
    call    kc_putc
    jmp     .next
.done:
    pop     rsi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kc_puthex -- RAX = value, ECX = how many hex digits to show
; ----------------------------------------------------------------------------
kc_puthex:
    push    rax
    push    rbx
    push    rcx
    push    rdx
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
    push    rax
    mov     al, bl
    call    kc_putc
    pop     rax
    test    edx, edx
    jnz     .digit
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

kc_puthex8:
    push    rcx
    mov     ecx, 2
    call    kc_puthex
    pop     rcx
    ret

kc_puthex16:
    push    rcx
    mov     ecx, 4
    call    kc_puthex
    pop     rcx
    ret

kc_puthex64:
    push    rcx
    mov     ecx, 16
    call    kc_puthex
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; kc_putdec -- RAX, unsigned
; ----------------------------------------------------------------------------
kc_putdec:
    push    rax
    push    rbx
    push    rdx
    push    rsi
    lea     rsi, [rel kc_numbuf]
    add     rsi, KC_NUMBUF_SIZE - 1
    mov     byte [rsi], 0
    mov     rbx, 10
.next:
    dec     rsi
    xor     edx, edx
    div     rbx
    add     dl, '0'
    mov     [rsi], dl
    test    rax, rax
    jnz     .next
    call    kc_puts
    pop     rsi
    pop     rdx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kfb_putc -- AL, straight into the framebuffer
; ----------------------------------------------------------------------------
kfb_putc:
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

    cmp     al, CHAR_CR
    je      .carriage
    cmp     al, CHAR_LF
    je      .newline
    cmp     al, CHAR_BS
    je      .backspace
    cmp     al, FONT_FIRST
    jb      .done
    cmp     al, FONT_LAST
    ja      .substitute
    jmp     .draw
.substitute:
    mov     al, '?'
.draw:
    movzx   esi, al
    sub     esi, FONT_FIRST
    shl     esi, 4                          ; FONT_H bytes per glyph
    lea     rbx, [rel font8x16]
    add     rsi, rbx

    mov     eax, [rel kc_y]
    imul    eax, FONT_H
    add     eax, KC_MARGIN_Y
    imul    eax, dword [rel kc_pitch]
    mov     r8d, [rel kc_x]
    imul    r8d, FONT_W * 4
    add     eax, r8d
    add     eax, KC_MARGIN_X * 4
    mov     rdi, [rel kc_fb]
    add     rdi, rax

    mov     r10d, [rel kc_fg]
    mov     r11d, [rel kc_bg]
    mov     edx, [rel kc_pitch]
    mov     ecx, FONT_H
.row:
    push    rdi
    lodsb                                   ; one scanline of the glyph
    mov     bl, al
    mov     r9d, FONT_W
.column:
    mov     eax, r11d
    test    bl, 0x80                        ; bit 7 is the leftmost pixel
    jz      .plot
    mov     eax, r10d
.plot:
    mov     [rdi], eax
    add     rdi, 4
    shl     bl, 1
    dec     r9d
    jnz     .column
    pop     rdi
    add     rdi, rdx
    dec     ecx
    jnz     .row

    inc     dword [rel kc_x]
    mov     eax, [rel kc_x]
    cmp     eax, [rel kc_cols]
    jb      .done
.newline:
    mov     dword [rel kc_x], 0
    inc     dword [rel kc_y]
    mov     eax, [rel kc_y]
    cmp     eax, [rel kc_rows]
    jb      .done
    call    kfb_scroll
    mov     eax, [rel kc_rows]
    dec     eax
    mov     [rel kc_y], eax
    jmp     .done
.carriage:
    mov     dword [rel kc_x], 0
    jmp     .done
    ; Back one cell, never past the start of the line; what was there stays
    ; until something is drawn over it, so erasing is BS, space, BS.
.backspace:
    cmp     dword [rel kc_x], 0
    je      .done
    dec     dword [rel kc_x]
.done:
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

; ----------------------------------------------------------------------------
; kfb_scroll -- shift the picture up by one glyph row and clear what it left
; ----------------------------------------------------------------------------
kfb_scroll:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     edx, [rel kc_pitch]
    mov     eax, [rel kc_h]
    sub     eax, FONT_H
    imul    eax, edx
    mov     ecx, eax
    mov     rdi, [rel kc_fb]
    mov     rsi, rdi
    mov     eax, FONT_H
    imul    eax, edx
    add     rsi, rax
    rep     movsb

    ; RDI stopped exactly at the band the copy vacated.
    mov     ecx, eax
    shr     ecx, 2
    mov     eax, [rel kc_bg]
    rep     stosd

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; The 16550 on COM1. Re-initialised rather than inherited: what the firmware
; left behind is not the kernel's to assume.
; ----------------------------------------------------------------------------
kser_init:
    push    rax
    push    rdx
    mov     dx, KCOM1 + UART_IER
    xor     al, al
    out     dx, al
    mov     dx, KCOM1 + UART_LCR
    mov     al, UART_LCR_DLAB
    out     dx, al
    mov     dx, KCOM1
    mov     al, UART_DIV_115200
    out     dx, al
    mov     dx, KCOM1 + UART_IER
    xor     al, al
    out     dx, al
    mov     dx, KCOM1 + UART_LCR
    mov     al, UART_LCR_8N1
    out     dx, al
    mov     dx, KCOM1 + UART_FCR
    mov     al, UART_FCR_ON
    out     dx, al
    mov     dx, KCOM1 + UART_MCR
    mov     al, UART_MCR_ON
    out     dx, al
    pop     rdx
    pop     rax
    ret

kser_putc:
    push    rax
    push    rdx
    mov     ah, al
.wait:
    mov     dx, KCOM1 + UART_LSR
    in      al, dx
    test    al, UART_LSR_THRE
    jz      .wait
    mov     al, ah
    mov     dx, KCOM1
    out     dx, al
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
align 8
kc_fb:      dq 0
kc_pitch:   dd 0
kc_w:       dd 0
kc_h:       dd 0
kc_fb_ok:   dd 0
kc_x:       dd 0
kc_y:       dd 0
kc_cols:    dd 0
kc_rows:    dd 0
kc_fg:      dd 0
kc_bg:      dd 0
kc_numbuf:  times KC_NUMBUF_SIZE db 0

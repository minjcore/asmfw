; ============================================================================
; console.asm -- a text console painted directly into the framebuffer
;
; 32 bpp only, which is all gfx_init ever programs. Pixels are little-endian
; 0x00RRGGBB dwords, so a colour constant reads the way it looks.
; ============================================================================

bits 64

; The default colours are the EFI text attribute 0x07 -- light grey on black
; -- taken from the same palette SetAttribute uses. Picking anything else here
; would make the firmware's own output disagree with an image's the moment it
; set an attribute, and the seam shows up as mismatched cell backgrounds.
CON_ATTR_DEFAULT equ 0x07

CON_MARGIN_X    equ 8                       ; left/right inset, in pixels
CON_MARGIN_Y    equ 8

%include "font.inc"

; ----------------------------------------------------------------------------
; fb_console_init -- derive the text grid from the mode and clear the screen
; ----------------------------------------------------------------------------
fb_console_init:
    push    rax
    push    rcx
    push    rdx
    push    rsi

    mov     dword [abs g_con_x], 0
    mov     dword [abs g_con_y], 0
    lea     rsi, [rel efi_palette]
    mov     eax, [rsi + (CON_ATTR_DEFAULT & 0x0F) * 4]
    mov     [abs g_con_fg], eax
    mov     eax, [rsi + ((CON_ATTR_DEFAULT >> 4) & 0x07) * 4]
    mov     [abs g_con_bg], eax
    mov     dword [abs g_con_attr], CON_ATTR_DEFAULT

    mov     eax, [abs g_fb_w]
    sub     eax, CON_MARGIN_X * 2
    xor     edx, edx
    mov     ecx, FONT_W
    div     ecx
    mov     [abs g_con_cols], eax

    mov     eax, [abs g_fb_h]
    sub     eax, CON_MARGIN_Y * 2
    xor     edx, edx
    mov     ecx, FONT_H
    div     ecx
    mov     [abs g_con_rows], eax

    call    fb_clear

    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; fb_clear -- paint the whole framebuffer with the background colour
; ----------------------------------------------------------------------------
fb_clear:
    push    rax
    push    rcx
    push    rdi
    mov     rdi, [abs g_fb_base]
    mov     eax, [abs g_con_bg]
    mov     rcx, [abs g_fb_size]
    shr     rcx, 2
    rep stosd
    pop     rdi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; fb_scroll -- shift the picture up by one character cell
; ----------------------------------------------------------------------------
fb_scroll:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     edx, [abs g_fb_pitch]

    ; move rows [1..n) up over row 0
    mov     rdi, [abs g_fb_base]
    mov     rsi, rdi
    mov     eax, edx
    imul    eax, FONT_H
    add     rsi, rax

    mov     eax, [abs g_fb_h]
    sub     eax, FONT_H
    imul    eax, edx
    mov     ecx, eax
    shr     ecx, 3
    rep movsq

    ; blank the row that scrolled in at the bottom
    mov     eax, edx
    imul    eax, FONT_H
    mov     ecx, eax
    shr     ecx, 2
    mov     eax, [abs g_con_bg]
    rep stosd

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; fb_newline -- carriage return plus line feed, scrolling if needed
; ----------------------------------------------------------------------------
fb_newline:
    push    rax
    mov     dword [abs g_con_x], 0
    mov     eax, [abs g_con_y]
    inc     eax
    mov     [abs g_con_y], eax
    cmp     eax, [abs g_con_rows]
    jb      .done
    call    fb_scroll
    mov     eax, [abs g_con_rows]
    dec     eax
    mov     [abs g_con_y], eax
.done:
    pop     rax
    ret

; ----------------------------------------------------------------------------
; fb_putc -- draw AL at the cursor and advance it.
;
; Called from con_putc, which only guarantees RAX; everything else is saved
; here so callers never have to think about it.
; ----------------------------------------------------------------------------
fb_putc:
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

    cmp     al, 10
    je      .lf
    cmp     al, 13
    je      .cr
    cmp     al, 8
    je      .bs
    cmp     al, 9
    je      .tab
    cmp     al, FONT_FIRST
    jb      .done
    cmp     al, FONT_LAST
    ja      .subst
    jmp     .draw
.subst:
    mov     al, '?'

.draw:
    ; RSI <- glyph bitmap
    movzx   rsi, al
    sub     rsi, FONT_FIRST
    shl     rsi, 4                          ; 16 bytes per glyph
    lea     rbx, [rel font8x16]
    add     rsi, rbx

    ; RDI <- top-left pixel of the cell
    mov     eax, [abs g_con_y]
    imul    eax, FONT_H
    add     eax, CON_MARGIN_Y
    imul    eax, [abs g_fb_pitch]
    mov     r8d, [abs g_con_x]
    imul    r8d, FONT_W * 4
    add     eax, r8d
    add     eax, CON_MARGIN_X * 4
    mov     rdi, [abs g_fb_base]
    add     rdi, rax

    mov     r10d, [abs g_con_fg]
    mov     r11d, [abs g_con_bg]
    mov     edx, [abs g_fb_pitch]
    mov     ecx, FONT_H
.row:
    push    rdi
    lodsb                                   ; one row of the glyph
    mov     bl, al
    mov     r9d, FONT_W
.col:
    mov     eax, r11d
    test    bl, 0x80
    jz      .put
    mov     eax, r10d
.put:
    mov     [rdi], eax
    add     rdi, 4
    shl     bl, 1
    dec     r9d
    jnz     .col
    pop     rdi
    add     rdi, rdx
    dec     ecx
    jnz     .row

    ; advance the cursor, wrapping at the right margin
    mov     eax, [abs g_con_x]
    inc     eax
    mov     [abs g_con_x], eax
    cmp     eax, [abs g_con_cols]
    jb      .done
    call    fb_newline
    jmp     .done

.lf:
    call    fb_newline
    jmp     .done
.cr:
    mov     dword [abs g_con_x], 0
    jmp     .done
.bs:
    mov     eax, [abs g_con_x]
    test    eax, eax
    jz      .done
    dec     eax
    mov     [abs g_con_x], eax
    mov     al, ' '
    call    fb_putc_raw
    jmp     .done
.tab:
    mov     eax, [abs g_con_x]
    add     eax, 8
    and     eax, 0xFFFFFFF8
    cmp     eax, [abs g_con_cols]
    jae     .tab_wrap
    mov     [abs g_con_x], eax
    jmp     .done
.tab_wrap:
    call    fb_newline

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
; fb_putc_raw -- draw AL without moving the cursor (used by backspace)
; ----------------------------------------------------------------------------
fb_putc_raw:
    push    rax
    push    rbx
    call    fb_putc
    mov     eax, [abs g_con_x]
    dec     eax
    mov     [abs g_con_x], eax
    pop     rbx
    pop     rax
    ret

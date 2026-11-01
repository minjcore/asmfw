; ============================================================================
; efi_proto.asm -- the protocols an image actually touches
;
; Simple Text Output, Simple Text Input and Graphics Output. All entry points
; use the Microsoft x64 calling convention: arguments in RCX, RDX, R8, R9 and
; then on the stack from [RSP+0x28]; RBX, RBP, RSI, RDI and R12-R15 belong to
; the caller and are saved here.
; ============================================================================

bits 64

; ============================================================================
; EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
; ============================================================================

; ----------------------------------------------------------------------------
; Reset(This, ExtendedVerification)
; ----------------------------------------------------------------------------
to_reset:
    push    rbx
    call    to_do_clear
    xor     eax, eax
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; OutputString(This, CHAR16 *String)
;
; Carriage returns are dropped: the console does its own line handling, and
; passing both halves of a CRLF through would double-space the serial log.
; Anything outside printable ASCII becomes '?', which is what TestString
; promises by returning success unconditionally.
; ----------------------------------------------------------------------------
to_output_string:
    push    rbx
    push    rsi
    push    rdi
    mov     rsi, rdx
    test    rsi, rsi
    jz      .done
.next:
    movzx   eax, word [rsi]
    add     rsi, 2
    test    ax, ax
    jz      .done
    cmp     ax, 13
    je      .next
    cmp     ax, 10
    je      .emit
    cmp     ax, 9
    je      .emit
    cmp     ax, 0x20
    jb      .next                               ; other control codes: ignore
    cmp     ax, 0x7E
    jbe     .emit
    mov     al, '?'
.emit:
    call    con_putc
    jmp     .next
.done:
    call    to_sync_cursor
    xor     eax, eax
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; TestString(This, String) -- every string is printable, one way or another
; ----------------------------------------------------------------------------
to_test_string:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; QueryMode(This, ModeNumber, UINTN *Columns, UINTN *Rows)
; ----------------------------------------------------------------------------
to_query_mode:
    test    rdx, rdx
    jnz     .bad
    test    r8, r8
    jz      .bad
    test    r9, r9
    jz      .bad
    mov     eax, [abs g_con_cols]
    mov     [r8], rax
    mov     eax, [abs g_con_rows]
    mov     [r9], rax
    xor     eax, eax
    ret
.bad:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; SetMode(This, ModeNumber) -- there is only one mode
; ----------------------------------------------------------------------------
to_set_mode:
    test    rdx, rdx
    jnz     .bad
    push    rbx
    call    to_do_clear
    pop     rbx
    xor     eax, eax
    ret
.bad:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; SetAttribute(This, Attribute)
;
; The low nibble is the foreground colour, bits 4-6 the background. They are
; translated through the standard 16-colour palette into the RGB values the
; framebuffer console paints with.
; ----------------------------------------------------------------------------
to_set_attribute:
    push    rbx
    push    rsi

    mov     eax, edx
    and     eax, 0x7F
    mov     [abs g_con_attr], eax
    mov     rbx, EFI_CONOUT_MODE
    mov     [rbx + TOM_ATTRIBUTE], eax

    lea     rsi, [rel efi_palette]
    mov     ecx, eax
    and     ecx, 0x0F
    mov     eax, [rsi + rcx * 4]
    mov     [abs g_con_fg], eax

    mov     ecx, [abs g_con_attr]
    shr     ecx, 4
    and     ecx, 0x07
    mov     eax, [rsi + rcx * 4]
    mov     [abs g_con_bg], eax

    xor     eax, eax
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; ClearScreen(This)
; ----------------------------------------------------------------------------
to_clear_screen:
    push    rbx
    call    to_do_clear
    xor     eax, eax
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; SetCursorPosition(This, Column, Row)
; ----------------------------------------------------------------------------
to_set_cursor_position:
    cmp     edx, [abs g_con_cols]
    jae     .bad
    cmp     r8d, [abs g_con_rows]
    jae     .bad
    mov     [abs g_con_x], edx
    mov     [abs g_con_y], r8d
    call    to_sync_cursor
    xor     eax, eax
    ret
.bad:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; EnableCursor(This, Visible) -- accepted, but nothing is drawn either way
; ----------------------------------------------------------------------------
to_enable_cursor:
    push    rbx
    mov     rbx, EFI_CONOUT_MODE
    mov     eax, edx
    and     eax, 1
    mov     [rbx + TOM_CURSORVISIBLE], eax
    xor     eax, eax
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; to_do_clear -- clear both consoles and home the cursor
; ----------------------------------------------------------------------------
to_do_clear:
    push    rax
    push    rsi
    ; A terminal on the other end of the serial line gets the ANSI form; the
    ; bytes go straight to the UART so the framebuffer never sees them.
    lea     rsi, [rel ansi_clear]
.ansi:
    lodsb
    test    al, al
    jz      .fb
    call    ser_putc
    jmp     .ansi
.fb:
    mov     dword [abs g_con_x], 0
    mov     dword [abs g_con_y], 0
    cmp     dword [abs g_fb_ok], 0
    je      .sync
    call    fb_clear
.sync:
    call    to_sync_cursor
    pop     rsi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; to_sync_cursor -- publish the console cursor through the protocol's Mode
; ----------------------------------------------------------------------------
to_sync_cursor:
    push    rax
    push    rbx
    mov     rbx, EFI_CONOUT_MODE
    mov     eax, [abs g_con_x]
    mov     [rbx + TOM_CURSORCOLUMN], eax
    mov     eax, [abs g_con_y]
    mov     [rbx + TOM_CURSORROW], eax
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; The 16 EFI text colours, as 0x00RRGGBB
; ----------------------------------------------------------------------------
align 4
efi_palette:
    dd 0x00000000       ; black
    dd 0x000000A8       ; blue
    dd 0x0000A800       ; green
    dd 0x0000A8A8       ; cyan
    dd 0x00A80000       ; red
    dd 0x00A800A8       ; magenta
    dd 0x00A85400       ; brown
    dd 0x00A8A8A8       ; light grey
    dd 0x00545454       ; dark grey
    dd 0x005454FC       ; light blue
    dd 0x0054FC54       ; light green
    dd 0x0054FCFC       ; light cyan
    dd 0x00FC5454       ; light red
    dd 0x00FC54FC       ; light magenta
    dd 0x00FCFC54       ; yellow
    dd 0x00FCFCFC       ; white

ansi_clear:
    db 27, "[2J", 27, "[H", 0

; ============================================================================
; EFI_SIMPLE_TEXT_INPUT_PROTOCOL -- polled i8042, no interrupts
; ============================================================================

KBD_DATA        equ 0x60
KBD_STATUS      equ 0x64
KBD_STATUS_OBF  equ 0x01                            ; a byte is waiting
KBD_STATUS_IBF  equ 0x02                            ; do not write yet
KBD_BREAK       equ 0x80                            ; the code is a release
KBD_PREFIX_EXT  equ 0xE0                            ; and the next byte is it

; The controller's command byte, and the bit in it that decides which codes
; the table below is reading.
KBD_CMD_READ_MODE   equ 0x20
KBD_CMD_WRITE_MODE  equ 0x60
KBD_MODE_XLAT       equ 0x40
KBD_WAIT_SPIN       equ 100000

; ----------------------------------------------------------------------------
; kbd_init -- make the codes be the ones this file decodes.
;
; A PS/2 keyboard's own default is scan code set 2, and the controller's
; translation bit -- which is what turns those into the set 1 codes every
; table in every PC operating system is written against -- comes out of reset
; clear. On a normal PC the BIOS sets it during its own keyboard bring-up.
;
; This firmware published EFI_SIMPLE_TEXT_INPUT_PROTOCOL for a long time
; without doing it, and the reason that went unnoticed is worth recording: no
; payload here ever read a key. A set 2 code in a set 1 table is not rejected,
; it is decoded -- into a different key. The protocol looked implemented, and
; would have answered every call, with the wrong letter.
; ----------------------------------------------------------------------------
kbd_init:
    push    rax
    push    rcx
    push    rdx

    call    kbd_wait_write
    mov     al, KBD_CMD_READ_MODE
    mov     dx, KBD_STATUS
    out     dx, al

    call    kbd_wait_read
    test    eax, eax
    jz      .done                                   ; no controller answering
    mov     dx, KBD_DATA
    in      al, dx

    or      al, KBD_MODE_XLAT
    mov     cl, al

    call    kbd_wait_write
    mov     al, KBD_CMD_WRITE_MODE
    mov     dx, KBD_STATUS
    out     dx, al

    call    kbd_wait_write
    mov     al, cl
    mov     dx, KBD_DATA
    out     dx, al

    ; Whatever is in the buffer now was typed, or answered, before the codes
    ; meant what they mean from here on.
    call    ti_reset
.done:
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kbd_wait_write -- the input buffer has to be empty before a write, or the
; write is lost. kbd_wait_read -- EAX = 1 if a byte turned up to be read.
;
; Both give up rather than spin forever: a controller that never answers is a
; keyboard that does not work, which is not a reason for firmware to stop.
; ----------------------------------------------------------------------------
kbd_wait_write:
    push    rcx
    push    rdx
    mov     ecx, KBD_WAIT_SPIN
.spin:
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_IBF
    jz      .clear
    dec     ecx
    jnz     .spin
.clear:
    pop     rdx
    pop     rcx
    ret

kbd_wait_read:
    push    rcx
    push    rdx
    mov     ecx, KBD_WAIT_SPIN
.spin:
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF
    jnz     .ready
    dec     ecx
    jnz     .spin
    xor     eax, eax
    jmp     .done
.ready:
    mov     eax, 1
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; Reset(This, ExtendedVerification) -- drain whatever is queued
; ----------------------------------------------------------------------------
ti_reset:
    push    rcx
    mov     ecx, 64
.drain:
    call    kbd_poll
    test    eax, eax
    jz      .done
    dec     ecx
    jnz     .drain
.done:
    xor     eax, eax
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; ReadKeyStroke(This, EFI_INPUT_KEY *Key)
; Returns EFI_NOT_READY when nothing has been typed.
; ----------------------------------------------------------------------------
ti_read_key_stroke:
    push    rbx
    push    rsi
    test    rdx, rdx
    jz      .bad
    mov     rbx, rdx

    call    kbd_poll
    test    eax, eax
    jz      .empty

    mov     [rbx + KEY_SCANCODE], cx
    mov     [rbx + KEY_UNICODECHAR], ax
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.empty:
    mov     rax, EFI_NOT_READY
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kbd_poll -- take one key from the controller.
;
; Returns EAX = the Unicode character (0 if the key has none) and CX = the EFI
; scan code, or EAX = 0 and CX = 0 when nothing was pending. Break codes and
; the modifier keys are swallowed here.
; ----------------------------------------------------------------------------
kbd_poll:
    push    rbx
    push    rdx
    push    rsi

    xor     ecx, ecx

    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF                  ; output buffer full?
    jz      .none

    mov     dx, KBD_DATA
    in      al, dx
    movzx   ebx, al

    ; The 0xE0 prefix introduces an extended key; take the next byte if it is
    ; already there, and treat the arrows specially.
    cmp     bl, KBD_PREFIX_EXT
    jne     .not_extended
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF
    jz      .none
    mov     dx, KBD_DATA
    in      al, dx
    test    al, KBD_BREAK
    jnz     .none                               ; break code
    movzx   ebx, al
    cmp     bl, 0x48
    je      .k_up
    cmp     bl, 0x50
    je      .k_down
    cmp     bl, 0x4B
    je      .k_left
    cmp     bl, 0x4D
    je      .k_right
    jmp     .none

.not_extended:
    test    bl, KBD_BREAK
    jnz     .none                               ; key release
    cmp     bl, 0x01
    je      .k_esc
    cmp     bl, 0x39
    ja      .none

    lea     rsi, [rel scancode_ascii]
    movzx   eax, byte [rsi + rbx]
    test    al, al
    jz      .none                               ; a modifier or an unmapped key
    jmp     .done

.k_esc:
    mov     cx, SCAN_ESC
    xor     eax, eax
    jmp     .done
.k_up:
    mov     cx, SCAN_UP
    xor     eax, eax
    jmp     .done
.k_down:
    mov     cx, SCAN_DOWN
    xor     eax, eax
    jmp     .done
.k_left:
    mov     cx, SCAN_LEFT
    xor     eax, eax
    jmp     .done
.k_right:
    mov     cx, SCAN_RIGHT
    xor     eax, eax
    jmp     .done

.none:
    xor     eax, eax
    xor     ecx, ecx
.done:
    pop     rsi
    pop     rdx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; Scan code set 1, unshifted, up to the space bar. Zero means "no character":
; either a modifier, or a key this table does not bother with.
; ----------------------------------------------------------------------------
scancode_ascii:
    db 0,   0,  '1', '2', '3', '4', '5', '6'    ; 0x00
    db '7', '8', '9', '0', '-', '=', 8,   9     ; 0x08
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'   ; 0x10
    db 'o', 'p', '[', ']', 13,  0,   'a', 's'   ; 0x18
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';'   ; 0x20
    db 39,  '`', 0,   92,  'z', 'x', 'c', 'v'   ; 0x28
    db 'b', 'n', 'm', ',', '.', '/', 0,   '*'   ; 0x30
    db 0,   ' '                                 ; 0x38

; ============================================================================
; EFI_GRAPHICS_OUTPUT_PROTOCOL
; ============================================================================

EfiBltVideoFill         equ 0
EfiBltVideoToBltBuffer  equ 1
EfiBltBufferToVideo     equ 2
EfiBltVideoToVideo      equ 3

; ----------------------------------------------------------------------------
; QueryMode(This, ModeNumber, UINTN *SizeOfInfo, EFI_..._INFORMATION **Info)
;
; The returned block is allocated from pool, as the spec requires: the caller
; owns it and is expected to FreePool it.
; ----------------------------------------------------------------------------
gop_query_mode:
    push    rbx
    push    rsi
    push    rdi
    test    rdx, rdx
    jnz     .bad
    test    r8, r8
    jz      .bad
    test    r9, r9
    jz      .bad
    mov     rbx, r8
    mov     rsi, r9

    mov     rcx, GOPI_SIZE
    mov     edx, EfiBootServicesData
    call    mem_alloc_pool
    test    rax, rax
    jz      .oom

    mov     rdi, rax
    push    rdi
    mov     rsi, EFI_GOP_INFO
    mov     ecx, GOPI_SIZE
    call    mem_copy
    pop     rdi

    mov     qword [rbx], GOPI_SIZE
    mov     rsi, r9
    mov     [rsi], rdi
    xor     eax, eax
    jmp     .done
.oom:
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; SetMode(This, ModeNumber) -- one mode, already set
; ----------------------------------------------------------------------------
gop_set_mode:
    test    rdx, rdx
    jnz     .bad
    xor     eax, eax
    ret
.bad:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; Blt(This, BltBuffer, Operation, SourceX, SourceY,
;     DestinationX, DestinationY, Width, Height, Delta)
;
; Four arguments arrive in registers and six on the stack. Delta of zero means
; the buffer is exactly Width pixels wide.
; ----------------------------------------------------------------------------
gop_blt:
    ; Read the stack arguments before touching RSP.
    mov     rax, [rsp + 0x28]                   ; SourceY
    mov     r10, [rsp + 0x30]                   ; DestinationX
    mov     r11, [rsp + 0x38]                   ; DestinationY

    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, [rsp + 0x40 + 0x40]            ; Width
    mov     r13, [rsp + 0x40 + 0x48]            ; Height
    mov     r14, [rsp + 0x40 + 0x50]            ; Delta

    mov     r15, rax                            ; SourceY
    mov     rbp, r9                             ; SourceX

    test    r12, r12
    jz      .ok
    test    r13, r13
    jz      .ok

    ; Delta defaults to a tightly packed buffer.
    test    r14, r14
    jnz     .have_delta
    mov     r14, r12
    shl     r14, 2
.have_delta:

    mov     ebx, [abs g_fb_pitch]               ; framebuffer stride
    mov     rsi, [abs g_fb_base]

    cmp     r8d, EfiBltVideoFill
    je      .fill
    cmp     r8d, EfiBltBufferToVideo
    je      .to_video
    cmp     r8d, EfiBltVideoToBltBuffer
    je      .to_buffer
    cmp     r8d, EfiBltVideoToVideo
    je      .video_to_video
    mov     rax, EFI_INVALID_PARAMETER
    jmp     .done

    ; --- fill a rectangle with the single pixel at BltBuffer --------------
.fill:
    test    rdx, rdx
    jz      .bad
    mov     r9d, [rdx]                          ; the colour
    mov     rdi, rsi
    mov     rax, r11
    imul    rax, rbx
    add     rdi, rax
    mov     rax, r10
    shl     rax, 2
    add     rdi, rax
.fill_row:
    mov     rcx, r12
    push    rdi
    mov     eax, r9d
    rep stosd
    pop     rdi
    add     rdi, rbx
    dec     r13
    jnz     .fill_row
    jmp     .ok

    ; --- caller's buffer -> screen ----------------------------------------
.to_video:
    test    rdx, rdx
    jz      .bad
    ; source = BltBuffer + SourceY*Delta + SourceX*4
    mov     rax, r15
    imul    rax, r14
    add     rax, rdx
    mov     rcx, rbp
    shl     rcx, 2
    add     rax, rcx
    mov     r9, rax
    ; dest = fb + DestY*pitch + DestX*4
    mov     rdi, rsi
    mov     rax, r11
    imul    rax, rbx
    add     rdi, rax
    mov     rax, r10
    shl     rax, 2
    add     rdi, rax
.to_video_row:
    push    rdi
    push    r9
    mov     rcx, r12
    mov     rsi, r9
    rep movsd
    pop     r9
    pop     rdi
    add     r9, r14
    add     rdi, rbx
    dec     r13
    jnz     .to_video_row
    jmp     .ok

    ; --- screen -> caller's buffer ----------------------------------------
.to_buffer:
    test    rdx, rdx
    jz      .bad
    mov     rax, r15
    imul    rax, r14
    add     rax, rdx
    mov     rcx, rbp
    shl     rcx, 2
    add     rax, rcx
    mov     r9, rax                             ; destination in the buffer
    mov     rax, r11
    imul    rax, rbx
    add     rsi, rax
    mov     rax, r10
    shl     rax, 2
    add     rsi, rax
.to_buffer_row:
    push    rsi
    push    r9
    mov     rdi, r9
    mov     rcx, r12
    rep movsd
    pop     r9
    pop     rsi
    add     r9, r14
    add     rsi, rbx
    dec     r13
    jnz     .to_buffer_row
    jmp     .ok

    ; --- screen -> screen --------------------------------------------------
    ; Rows are copied bottom-up when the destination is below the source, so
    ; an overlapping downward scroll does not smear.
.video_to_video:
    mov     rdi, rsi
    mov     rax, r15
    imul    rax, rbx
    add     rsi, rax
    mov     rax, rbp
    shl     rax, 2
    add     rsi, rax
    mov     rax, r11
    imul    rax, rbx
    add     rdi, rax
    mov     rax, r10
    shl     rax, 2
    add     rdi, rax

    cmp     r11, r15
    jbe     .v2v_row
    ; walk backwards
    mov     rax, r13
    dec     rax
    imul    rax, rbx
    add     rsi, rax
    add     rdi, rax
    neg     rbx
.v2v_row:
    push    rsi
    push    rdi
    mov     rcx, r12
    rep movsd
    pop     rdi
    pop     rsi
    add     rsi, rbx
    add     rdi, rbx
    dec     r13
    jnz     .v2v_row
    jmp     .ok

.bad:
    mov     rax, EFI_INVALID_PARAMETER
    jmp     .done
.ok:
    xor     eax, eax
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    ret

; ============================================================================
; macros.inc -- small assembly conveniences
; ============================================================================

; Emit a NUL-terminated string and give it a label.
%macro CSTR 2-*
%1: db %{2:-1}, 0
%endmacro

; puts <label> -- print a ROM string through the console.
%macro puts 1
    lea     rsi, [rel %1]
    call    con_puts
%endmacro

; putsi "literal" -- print an inline literal, jumping over the bytes.
%macro putsi 1-*
    ; `strict near` keeps the jump a fixed five bytes. Left to itself the
    ; assembler shortens it once the string settles, which moves every label
    ; after it and stops the passes converging.
    jmp     strict near %%past
%%str:  db %{1:-1}, 0
%%past:
    lea     rsi, [rel %%str]
    call    con_puts
%endmacro

; Align the current output position, padding ROM with 0xFF.
%macro ROMALIGN 1
    times (($$ - $) & (%1 - 1)) db 0xFF
%endmacro

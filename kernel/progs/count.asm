; ============================================================================
; count.asm -- a program: print a line, burn time, repeat
;
; The counter it prints is its own. The time stamp beside it comes from the
; kernel, and the gaps between consecutive values are the other tasks running
; while this one was not.
;
; It ends by executing an instruction ring 3 does not have, to show that a
; task can be removed without the machine noticing.
;
;   nasm -f bin -I ../ -I . -o COUNT.BIN count.asm
; ============================================================================

bits 64
default rel
org 0

%include "uabi.inc"

U_DEC_DIGITS    equ 4
U_LINES         equ 8
U_SLEEP_MS      equ 120
U_EXIT_ESCAPED  equ 1

_start:
    mov     [rel u_id], rdi
    mov     [rel u_window], rsi
    mov     [rel u_sibling], rdx

    lea     rdi, [rel u_hello]
    mov     esi, u_hello_len
    call    u_write

    xor     ebx, ebx
.line:
    mov     rax, rbx
    lea     rdi, [rel u_nvalue]
    mov     ecx, U_DEC_DIGITS
    call    u_dec

    mov     eax, SYS_UPTIME
    syscall
    lea     rdi, [rel u_upvalue]
    mov     ecx, U_DEC_DIGITS
    call    u_dec

    lea     rdi, [rel u_line]
    mov     esi, u_line_len
    call    u_write

    ; Asleep rather than spinning: the CPU goes to whoever else wants it, and
    ; if nobody does it goes to the halt instruction.
    mov     edi, U_SLEEP_MS
    mov     eax, SYS_SLEEP
    syscall

    inc     ebx
    cmp     ebx, U_LINES
    jb      .line

    lea     rdi, [rel u_trap]
    mov     esi, u_trap_len
    call    u_write

    cli

    lea     rdi, [rel u_escaped]
    mov     esi, u_escaped_len
    call    u_write
    mov     edi, U_EXIT_ESCAPED
    call    u_exit

%include "ulib.inc"

; ----------------------------------------------------------------------------
u_hello:
    db "task 1   loaded from \PROGS\COUNT.BIN; sleeping between lines", 10
u_hello_len     equ $ - u_hello

u_line:
    db "task 1   line "
u_nvalue:
    db "0000"
    db "   uptime "
u_upvalue:
    db "0000"
    db " ticks   (slept in between, not spun)", 10
u_line_len      equ $ - u_line

u_trap:
    db "task 1   done counting; now executing cli, which ring 3 may not do", 10
u_trap_len      equ $ - u_trap

u_escaped:
    db "task 1   cli SUCCEEDED -- ring 3 is not actually ring 3", 10
u_escaped_len   equ $ - u_escaped

align 8
u_id:       dq 0
u_window:   dq 0
u_sibling:  dq 0

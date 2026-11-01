; ============================================================================
; rogue.asm -- a program that goes looking for memory that is not its own
;
; It is told its neighbour's window address at entry, so this is not a
; guessing game: the window really is there, and in the kernel's address space
; it is readable. In this task's address space that 2 MiB page carries no user
; mapping, so the read faults and the task is gone. Separate page tables are
; the whole of the difference.
;
;   nasm -f bin -I ../ -I . -o ROGUE.BIN rogue.asm
; ============================================================================

bits 64
default rel
org 0

%include "uabi.inc"

U_HEX64_DIGITS  equ 16
U_PROBE_LEN     equ 8
U_EXIT_ESCAPED  equ 1

_start:
    mov     [rel u_id], rdi
    mov     [rel u_window], rsi
    mov     [rel u_sibling], rdx

    lea     rdi, [rel u_hello]
    mov     esi, u_hello_len
    call    u_write

    ; First the softer boundary: a pointer the kernel is asked to trust.
    xor     edi, edi
    mov     esi, U_PROBE_LEN
    call    u_write
    cmp     rax, SYS_EBADPTR
    jne     .no_guard
    lea     rdi, [rel u_guard_ok]
    mov     esi, u_guard_ok_len
    jmp     .guard_say
.no_guard:
    lea     rdi, [rel u_guard_bad]
    mov     esi, u_guard_bad_len
.guard_say:
    call    u_write

    ; Then the hard one, which no system call is involved in at all.
    mov     rax, [rel u_sibling]
    lea     rdi, [rel u_addrvalue]
    mov     ecx, U_HEX64_DIGITS
    call    u_hex
    lea     rdi, [rel u_reach]
    mov     esi, u_reach_len
    call    u_write

    mov     rax, [rel u_sibling]
    mov     al, [rax]

    lea     rdi, [rel u_escaped]
    mov     esi, u_escaped_len
    call    u_write
    mov     edi, U_EXIT_ESCAPED
    call    u_exit

%include "ulib.inc"

; ----------------------------------------------------------------------------
u_hello:
    db "task 2   loaded from \PROGS\ROGUE.BIN; looking for memory that is not mine", 10
u_hello_len     equ $ - u_hello

u_guard_ok:
    db "task 2   a write to address zero was refused: the window is the whole world", 10
u_guard_ok_len  equ $ - u_guard_ok

u_guard_bad:
    db "task 2   a write to address zero was ACCEPTED, which it must not have been", 10
u_guard_bad_len equ $ - u_guard_bad

u_reach:
    db "task 2   reading my neighbour's window at "
u_addrvalue:
    db "0000000000000000"
    db " -- the kernel can, and I am not the kernel", 10
u_reach_len     equ $ - u_reach

u_escaped:
    db "task 2   THAT READ SUCCEEDED, which means the windows are not separate", 10
u_escaped_len   equ $ - u_escaped

align 8
u_id:       dq 0
u_window:   dq 0
u_sibling:  dq 0

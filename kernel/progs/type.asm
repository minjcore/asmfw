; ============================================================================
; type.asm -- a program that waits for something the machine cannot produce
;
; The other three tasks are driven by the clock, one way or another: the maze
; never yields and is taken away, the counter sleeps against the tick, the
; rogue faults immediately. All three would run identically on a machine with
; nobody at it.
;
; This one blocks on a device. Once the others have ended there is nothing for
; the scheduler to run, so the kernel parks on hlt -- and what starts it again
; comes from outside the machine entirely.
;
; It gives up after U_WAIT_MS with nothing typed, which is what happens under
; `make serialk`: with no display, QEMU has no keyboard to give it. Under
; `make runk` the window does, and the timeout is the thing you have to beat.
;
;   nasm -f bin -I ../ -I . -o TYPE.BIN type.asm
; ============================================================================

bits 64
default rel
org 0

%include "uabi.inc"

U_DEC_DIGITS    equ 4
U_HEX_DIGITS    equ 2
U_KEYS_MAX      equ 8               ; taken from one read; the rest waits
U_KEYS_TOTAL    equ 16              ; before this program has seen enough
U_WAIT_MS       equ 3000

U_CHAR_ENTER    equ 13
U_CHAR_ESC      equ 27
U_CHAR_LOW      equ 32              ; below this there is nothing to look at
U_CHAR_HIGH     equ 126

U_EXIT_QUIET    equ 0
U_EXIT_TYPED    equ 0

_start:
    mov     [rel u_id], rdi
    mov     [rel u_window], rsi
    mov     [rel u_sibling], rdx

    lea     rdi, [rel u_hello]
    mov     esi, u_hello_len
    call    u_write

    xor     r12d, r12d                          ; keys seen, over all reads
.round:
    lea     rdi, [rel u_keys]
    mov     esi, U_KEYS_MAX
    mov     edx, U_WAIT_MS
    call    u_read
    test    rax, rax
    jz      .quiet

    mov     r13, rax                            ; how many this read produced
    xor     r14d, r14d
.each:
    lea     rsi, [rel u_keys]
    add     rsi, r14
    movzx   ebx, byte [rsi]

    mov     rax, rbx
    lea     rdi, [rel u_kcode]
    mov     ecx, U_HEX_DIGITS
    call    u_hex

    mov     eax, SYS_UPTIME
    syscall
    lea     rdi, [rel u_kwhen]
    mov     ecx, U_DEC_DIGITS
    call    u_dec

    ; The byte as a character, where it has one worth putting on a console.
    ; The code beside it is the honest version of the answer either way.
    mov     al, bl
    cmp     al, U_CHAR_LOW
    jb      .unprintable
    cmp     al, U_CHAR_HIGH
    ja      .unprintable
    jmp     .have_char
.unprintable:
    mov     al, '.'
.have_char:
    mov     [rel u_kchar], al

    lea     rdi, [rel u_kline]
    mov     esi, u_kline_len
    call    u_write

    inc     r12
    cmp     bl, U_CHAR_ENTER
    je      .enter
    cmp     bl, U_CHAR_ESC
    je      .enter

    inc     r14
    cmp     r14, r13
    jb      .each

    cmp     r12, U_KEYS_TOTAL
    jb      .round

    lea     rdi, [rel u_full]
    mov     esi, u_full_len
    call    u_write
    mov     edi, U_EXIT_TYPED
    call    u_exit

.enter:
    lea     rdi, [rel u_done]
    mov     esi, u_done_len
    call    u_write
    mov     edi, U_EXIT_TYPED
    call    u_exit

.quiet:
    lea     rdi, [rel u_quiet]
    mov     esi, u_quiet_len
    call    u_write
    mov     edi, U_EXIT_QUIET
    call    u_exit

%include "ulib.inc"

; ----------------------------------------------------------------------------
u_hello:
    db "task 3   loaded from \PROGS\TYPE.BIN; type something, enter ends it", 10
u_hello_len     equ $ - u_hello

u_kline:
    db "task 3   key '"
u_kchar:
    db "?"
    db "' code 0x"
u_kcode:
    db "00"
    db " at "
u_kwhen:
    db "0000"
    db " ticks", 10
u_kline_len     equ $ - u_kline

u_done:
    db "task 3   that was the end of the line; nothing left to wait for", 10
u_done_len      equ $ - u_done

u_full:
    db "task 3   enough typing; the point was the waiting, not the letters", 10
u_full_len      equ $ - u_full

u_quiet:
    db "task 3   nothing typed for 3 s -- with no display there is no keyboard", 10
u_quiet_len     equ $ - u_quiet

align 8
u_id:       dq 0
u_window:   dq 0
u_sibling:  dq 0

u_keys:     times U_KEYS_MAX db 0

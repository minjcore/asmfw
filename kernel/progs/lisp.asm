; ============================================================================
; lisp.asm -- a Lisp, in ring 3, with a garbage collector
;
; A small Scheme-flavoured Lisp: integers, symbols, conses, closures, and the
; special forms quote, if, define, lambda, let, begin, set!, cond, and, or.
; It runs a demo script embedded below, prints what each expression evaluates
; to, and then reads expressions from the keyboard until nobody types.
;
; Values are 64-bit words. An odd word is an integer, shifted left one bit
; with the low bit set; an even word is the address of a 32-byte object whose
; first byte says what it is. Nil and t are ordinary interned symbols that
; evaluate to themselves; nil is the empty list and the only false value.
;
; Memory is one 2 MiB window, the only one this program can touch:
;
;   +0x000000  this image
;   +0x040000  symbol names, bump allocated and never freed
;   +0x060000  the keyboard line
;   +0x080000  the heap: 32768 objects of 32 bytes
;   +0x180000  the stack, growing down from +0x200000, with a floor eval
;              checks so that recursion runs out as an error, not over the heap
;
; The collector is mark and sweep, and conservative about the stack: any word
; on it that happens to be the address of a live-looking object keeps that
; object alive. That is what lets the evaluator be ordinary assembly, keeping
; values in registers and on the stack without telling anyone, rather than
; maintaining a root list by hand. The price is the occasional object kept a
; collection longer than it needed to be, which is no price at all here.
;
;   nasm -f bin -I ../ -I . -o LISP.BIN lisp.asm
; ============================================================================

bits 64
default rel
org 0

%include "uabi.inc"

; --- the window ---------------------------------------------------------------
L_NAMES         equ 0x040000
L_NAMES_END     equ 0x060000
L_LINE          equ 0x060000
LINE_MAX        equ 2048
L_HEAP          equ 0x080000
L_HEAP_END      equ 0x180000
L_STACK_FLOOR   equ 0x190000
L_STACK_TOP     equ 0x200000

; --- objects ------------------------------------------------------------------
OBJ_SIZE        equ 32
HEAP_CELLS      equ (L_HEAP_END - L_HEAP) / OBJ_SIZE
O_TAG           equ 0                   ; UINT8
O_MARK          equ 1                   ; UINT8, set only during a collection
O_A             equ 8
O_B             equ 16
O_C             equ 24

T_CONS          equ 1                   ; A = car, B = cdr
T_SYM           equ 2                   ; A = name, B = global value or 0
T_PRIM          equ 3                   ; A = code, B = name
T_LAMBDA        equ 4                   ; A = parameters, B = body, C = env
T_FREE          equ 5                   ; A = next free object

; --- the console and the keyboard ----------------------------------------------
OUT_MAX         equ 1024
U_IDLE_MS       equ 5000
CH_BS           equ 8
CH_LF           equ 10
CH_CR           equ 13
CH_ESC          equ 27
CH_QUOTE        equ 39

; JNCONS reg, label -- jump unless reg holds a cons.
%macro JNCONS 2
    test    %1, 1
    jnz     %2
    cmp     byte [%1 + O_TAG], T_CONS
    jne     %2
%endmacro

; OUTS "text" -- append a literal to the output line.
%macro OUTS 1
    jmp     %%after
%%text: db %1, 0
%%after:
    push    rsi
    lea     rsi, [rel %%text]
    call    out_str
    pop     rsi
%endmacro

; ERROR "message", value-register-or-0
%macro ERROR 2
    jmp     %%after
%%text: db %1, 0
%%after:
    mov     rdi, %2
    lea     rsi, [rel %%text]
    jmp     lisp_error
%endmacro

; ----------------------------------------------------------------------------
; _start -- RDI = task id, RSI = this window. Lays the window out, interns the
; special forms and primitives, and runs the demo and then the REPL.
; ----------------------------------------------------------------------------
_start:
    mov     [rel u_window], rsi
    lea     rax, [rsi + L_NAMES]
    mov     [rel u_names], rax
    lea     rax, [rsi + L_NAMES_END]
    mov     [rel u_names_end], rax
    lea     rax, [rsi + L_HEAP]
    mov     [rel u_heap_lo], rax
    mov     [rel u_bump], rax
    lea     rax, [rsi + L_HEAP_END]
    mov     [rel u_heap_hi], rax
    lea     rax, [rsi + L_STACK_FLOOR]
    mov     [rel u_stack_floor], rax
    lea     rax, [rsi + L_STACK_TOP]
    mov     [rel u_stack_top], rax

    ; An error before the REPL exists has nowhere to go back to.
    mov     [rel u_top_rsp], rsp
    lea     rax, [rel fatal]
    mov     [rel u_resume], rax

    ; --- nil and t first: everything else is built out of them --------------
    lea     rsi, [rel n_nil]
    call    intern_cstr
    mov     [rel u_nil], rax
    mov     [rax + O_B], rax
    lea     rsi, [rel n_t]
    call    intern_cstr
    mov     [rel u_t], rax
    mov     [rax + O_B], rax

    ; --- the special forms' symbols, kept where eval can compare them -------
    lea     rbx, [rel special_table]
    mov     r12d, SPECIAL_COUNT
.special:
    mov     rsi, [rbx]
    add     rsi, [rel u_window]
    call    intern_cstr
    mov     rdi, [rbx + 8]
    add     rdi, [rel u_window]
    mov     [rdi], rax
    add     rbx, 16
    dec     r12d
    jnz     .special

    ; --- the primitives, each bound globally to its symbol ------------------
    lea     rbx, [rel prim_table]
    mov     r12d, PRIM_COUNT
.prim:
    mov     rsi, [rbx]
    add     rsi, [rel u_window]
    call    intern_cstr
    mov     rdi, rax                            ; the symbol, kept live
    mov     al, T_PRIM
    call    alloc
    mov     rdx, [rbx + 8]
    add     rdx, [rel u_window]
    mov     [rax + O_A], rdx
    mov     [rax + O_B], rsi
    mov     [rdi + O_B], rax
    add     rbx, 16
    dec     r12d
    jnz     .prim

    call    out_reset
    OUTS    "task 4   lisp: "
    mov     eax, PRIM_COUNT
    call    out_dec
    OUTS    " primitives, a heap of "
    mov     eax, HEAP_CELLS
    call    out_dec
    OUTS    " cells; running the demo"
    call    out_line

    ; --- the demo -------------------------------------------------------------
    lea     rax, [rel demo_src]
    mov     [rel u_rp], rax
    add     rax, DEMO_LEN
    mov     [rel u_rend], rax
; demo_next -- evaluate the next demo expression; where an error in one resumes.
demo_next:
    lea     rax, [rel demo_next]
    mov     [rel u_resume], rax
    mov     [rel u_top_rsp], rsp
    call    skip_ws
    test    al, al
    jz      .done
    mov     rax, [rel u_rp]
    mov     [rel u_src], rax
    call    read_expr
    mov     [rel u_expr], rax

    call    out_reset
    OUTS    "task 4   > "
    mov     rsi, [rel u_src]
    mov     rcx, [rel u_rp]
    sub     rcx, rsi
    call    out_src
    call    out_line

    mov     rdi, [rel u_expr]
    mov     rsi, [rel u_nil]
    call    eval
    call    show_result
    jmp     demo_next
.done:
    call    out_reset
    OUTS    "task 4   demo done; the collector ran "
    mov     rax, [rel u_gc_runs]
    call    out_dec
    OUTS    " times, freeing "
    mov     rax, [rel u_gc_freed]
    call    out_dec
    OUTS    " cells the last time"
    call    out_line

    call    out_reset
    OUTS    "task 4   type at lisp> once task 3 has given up; esc or 5 s of silence ends it"
    call    out_line

; ----------------------------------------------------------------------------
; The REPL. Its state lives in memory rather than registers because an error
; anywhere comes back here with the stack thrown away.
; ----------------------------------------------------------------------------
; repl -- prompt, read a balanced line, evaluate it; where an error resumes.
repl:
    lea     rax, [rel repl]
    mov     [rel u_resume], rax
    mov     [rel u_top_rsp], rsp
    call    out_reset
    OUTS    "task 4   lisp> "
    call    out_flush
    mov     qword [rel u_len], 0
    mov     qword [rel u_depth], 0
.key:
    lea     rdi, [rel u_key]
    mov     esi, 1
    mov     edx, U_IDLE_MS
    call    u_read
    test    rax, rax
    jz      .idle
    movzx   eax, byte [rel u_key]
    cmp     al, CH_ESC
    je      .esc
    cmp     al, CH_CR
    je      .enter
    cmp     al, CH_BS
    je      .backspace
    cmp     al, ' '
    jb      .key
    cmp     al, '~'
    ja      .key
    mov     rcx, [rel u_len]
    cmp     rcx, LINE_MAX - 2
    jae     .key
    mov     rdx, [rel u_window]
    mov     [rdx + L_LINE + rcx], al
    inc     qword [rel u_len]
    cmp     al, '('
    jne     .not_open
    inc     qword [rel u_depth]
.not_open:
    cmp     al, ')'
    jne     .echo
    dec     qword [rel u_depth]
.echo:
    lea     rsi, [rel u_key]
    mov     ecx, 1
    call    write_bytes
    jmp     .key

.backspace:
    mov     rcx, [rel u_len]
    test    rcx, rcx
    jz      .key
    dec     rcx
    mov     [rel u_len], rcx
    mov     rdx, [rel u_window]
    mov     al, [rdx + L_LINE + rcx]
    cmp     al, '('
    jne     .bs_open
    dec     qword [rel u_depth]
.bs_open:
    cmp     al, ')'
    jne     .bs_echo
    inc     qword [rel u_depth]
.bs_echo:
    lea     rsi, [rel s_rubout]
    mov     ecx, 3
    call    write_bytes
    jmp     .key

.enter:
    lea     rsi, [rel s_newline]
    mov     ecx, 1
    call    write_bytes
    cmp     qword [rel u_depth], 0
    jle     .run
    ; Unbalanced: the line break becomes a space and the reading goes on.
    mov     rcx, [rel u_len]
    mov     rdx, [rel u_window]
    mov     byte [rdx + L_LINE + rcx], ' '
    inc     qword [rel u_len]
    call    out_reset
    OUTS    "task 4   ...   "
    call    out_flush
    jmp     .key

.run:
    mov     rax, [rel u_window]
    add     rax, L_LINE
    mov     [rel u_rp], rax
    add     rax, [rel u_len]
    mov     [rel u_rend], rax
.expr:
    call    skip_ws
    test    al, al
    jz      repl
    call    read_expr
    mov     [rel u_expr], rax
    mov     rdi, rax
    mov     rsi, [rel u_nil]
    call    eval
    call    show_result
    jmp     .expr

.idle:
    lea     rsi, [rel s_newline]
    mov     ecx, 1
    call    write_bytes
    call    out_reset
    OUTS    "task 4   nothing typed for 5 s; the REPL is closing"
    call    out_line
    xor     edi, edi
    call    u_exit
.esc:
    lea     rsi, [rel s_newline]
    mov     ecx, 1
    call    write_bytes
    call    out_reset
    OUTS    "task 4   escape; the REPL is closing"
    call    out_line
    xor     edi, edi
    call    u_exit

; ----------------------------------------------------------------------------
; fatal -- where an error goes before there is a REPL to return to.
; ----------------------------------------------------------------------------
fatal:
    mov     edi, 1
    call    u_exit

; ----------------------------------------------------------------------------
; show_result -- RAX = a value. Prints it as "task 4   = value".
; ----------------------------------------------------------------------------
show_result:
    push    rdi
    mov     [rel u_expr], rax
    call    out_reset
    OUTS    "task 4   = "
    mov     rdi, [rel u_expr]
    call    print
    call    out_line
    pop     rdi
    ret

; ----------------------------------------------------------------------------
; lisp_error -- RSI = message, RDI = the offending value or 0. Does not
; return: it prints, throws the stack away, and resumes the top level.
; ----------------------------------------------------------------------------
lisp_error:
    mov     rsp, [rel u_top_rsp]
    mov     rbx, rdi
    call    out_reset
    OUTS    "task 4   error: "
    call    out_str
    test    rbx, rbx
    jz      .say
    mov     al, ' '
    call    out_char
    mov     rdi, rbx
    call    print
.say:
    call    out_line
    jmp     [rel u_resume]

; ============================================================================
; The evaluator
; ============================================================================

; ----------------------------------------------------------------------------
; eval -- RDI = an expression, RSI = an environment. Returns RAX.
;
; An environment is an association list of (symbol . value) pairs, searched
; before the symbol's global value. Every form whose last step is to evaluate
; something else -- if, begin, a lambda body, let, cond, and, or -- does it by
; replacing the expression and jumping back to the top rather than calling,
; so a loop written as tail recursion runs in constant stack.
; ----------------------------------------------------------------------------
eval:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
.top:
    cmp     rsp, [rel u_stack_floor]
    jb      .deep
    test    r12, 1
    jnz     .self
    movzx   eax, byte [r12 + O_TAG]
    cmp     al, T_SYM
    je      .symbol
    cmp     al, T_CONS
    je      .form
.self:
    mov     rax, r12
    jmp     .ret

.symbol:
    mov     rdi, r12
    mov     rsi, r13
    call    lookup_pair
    test    rax, rax
    jz      .global
    mov     rax, [rax + O_B]
    jmp     .ret
.global:
    mov     rax, [r12 + O_B]
    test    rax, rax
    jnz     .ret
    ERROR   "unbound symbol", r12

.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.deep:
    ERROR   "recursion too deep", 0

.form:
    mov     rbx, [r12 + O_A]                    ; the head
    mov     r14, [r12 + O_B]                    ; the rest
    test    rbx, 1
    jnz     .apply
    cmp     byte [rbx + O_TAG], T_SYM
    jne     .apply
    cmp     rbx, [rel u_quote]
    je      .quote
    cmp     rbx, [rel u_if]
    je      .if
    cmp     rbx, [rel u_define]
    je      .define
    cmp     rbx, [rel u_lambda]
    je      .lambda
    cmp     rbx, [rel u_let]
    je      .let
    cmp     rbx, [rel u_begin]
    je      .begin
    cmp     rbx, [rel u_set]
    je      .set
    cmp     rbx, [rel u_cond]
    je      .cond
    cmp     rbx, [rel u_and]
    je      .and
    cmp     rbx, [rel u_or]
    je      .or

    ; --- application -----------------------------------------------------
.apply:
    mov     rdi, rbx
    mov     rsi, r13
    call    eval
    mov     r15, rax                            ; the function
    mov     rdi, r14
    mov     rsi, r13
    call    evlis
    mov     r14, rax                            ; its arguments
    test    r15, 1
    jnz     .not_fn
    movzx   eax, byte [r15 + O_TAG]
    cmp     al, T_PRIM
    je      .prim
    cmp     al, T_LAMBDA
    jne     .not_fn
    mov     rdi, [r15 + O_A]
    mov     rsi, r14
    mov     rdx, [r15 + O_C]
    call    bind
    mov     r13, rax
    mov     r15, [r15 + O_B]
    jmp     .seq
.prim:
    mov     rdi, r14
    call    [r15 + O_A]
    jmp     .ret
.not_fn:
    ERROR   "not a function:", r15

    ; --- (quote x) ---------------------------------------------------------
.quote:
    mov     rdi, r14
    call    scar
    jmp     .ret

    ; --- (if test then else) ---------------------------------------------
.if:
    mov     rdi, r14
    call    scar
    mov     rdi, rax
    mov     rsi, r13
    call    eval
    cmp     rax, [rel u_nil]
    je      .if_else
    mov     rdi, r14
    call    scdr
    mov     rdi, rax
    call    scar
    mov     r12, rax
    jmp     .top
.if_else:
    mov     rdi, r14
    call    scdr
    mov     rdi, rax
    call    scdr
    mov     rdi, rax
    call    scar
    mov     r12, rax
    jmp     .top

    ; --- (define name value) or (define (name . params) body...) --------
.define:
    mov     rdi, r14
    call    scar
    mov     rbx, rax
    test    rbx, 1
    jnz     .bad_define
    cmp     byte [rbx + O_TAG], T_CONS
    jne     .define_plain
    mov     rdi, r14
    call    scdr
    mov     rsi, rax                            ; the body
    mov     rdi, [rbx + O_B]                    ; the parameters
    mov     rdx, r13
    call    make_lambda
    mov     rbx, [rbx + O_A]                    ; the name
    jmp     .define_set
.define_plain:
    mov     rdi, r14
    call    scdr
    mov     rdi, rax
    call    scar
    mov     rdi, rax
    mov     rsi, r13
    call    eval
.define_set:
    test    rbx, 1
    jnz     .bad_define
    cmp     byte [rbx + O_TAG], T_SYM
    jne     .bad_define
    mov     [rbx + O_B], rax
    mov     rax, rbx
    jmp     .ret
.bad_define:
    ERROR   "define wants a symbol, not", rbx

    ; --- (lambda params body...) -----------------------------------------
.lambda:
    mov     rdi, r14
    call    scar
    mov     rbx, rax
    mov     rdi, r14
    call    scdr
    mov     rsi, rax
    mov     rdi, rbx
    mov     rdx, r13
    call    make_lambda
    jmp     .ret

    ; --- (begin e...) and every body: all but the last for effect --------
.begin:
    mov     r15, r14
.seq:
    JNCONS  r15, .nil
.seq_next:
    mov     rax, [r15 + O_B]
    JNCONS  rax, .seq_last
    mov     rdi, [r15 + O_A]
    mov     rsi, r13
    call    eval
    mov     r15, [r15 + O_B]
    jmp     .seq_next
.seq_last:
    mov     r12, [r15 + O_A]
    jmp     .top
.nil:
    mov     rax, [rel u_nil]
    jmp     .ret

    ; --- (let ((name value)...) body...) ---------------------------------
    ; Every value is evaluated in the outer environment, as let requires.
.let:
    mov     rdi, r14
    call    scar
    mov     rbx, rax                            ; the bindings
    mov     r15, r13                            ; the environment being built
.let_binding:
    JNCONS  rbx, .let_body
    mov     rdi, [rbx + O_A]
    call    scdr
    mov     rdi, rax
    call    scar
    mov     rdi, rax
    mov     rsi, r13
    call    eval
    mov     rsi, rax                            ; the value
    mov     rdi, [rbx + O_A]
    call    scar
    mov     rdi, rax                            ; the name
    call    cons
    mov     rdi, rax
    mov     rsi, r15
    call    cons
    mov     r15, rax
    mov     rbx, [rbx + O_B]
    jmp     .let_binding
.let_body:
    mov     r13, r15
    mov     rdi, r14
    call    scdr
    mov     r15, rax
    jmp     .seq

    ; --- (set! name value) -------------------------------------------------
.set:
    mov     rdi, r14
    call    scar
    mov     rbx, rax
    mov     rdi, r14
    call    scdr
    mov     rdi, rax
    call    scar
    mov     rdi, rax
    mov     rsi, r13
    call    eval
    mov     r15, rax
    mov     rdi, rbx
    mov     rsi, r13
    call    lookup_pair
    test    rax, rax
    jz      .set_global
    mov     [rax + O_B], r15
    mov     rax, r15
    jmp     .ret
.set_global:
    test    rbx, 1
    jnz     .set_unbound
    cmp     byte [rbx + O_TAG], T_SYM
    jne     .set_unbound
    cmp     qword [rbx + O_B], 0
    je      .set_unbound
    mov     [rbx + O_B], r15
    mov     rax, r15
    jmp     .ret
.set_unbound:
    ERROR   "set! of an unbound symbol", rbx

    ; --- (cond (test body...)... (else body...)) -------------------------
.cond:
    mov     rbx, r14
.cond_clause:
    JNCONS  rbx, .nil
    mov     r15, [rbx + O_A]
    mov     rdi, r15
    call    scar
    cmp     rax, [rel u_else]
    je      .cond_body
    mov     rdi, rax
    mov     rsi, r13
    call    eval
    cmp     rax, [rel u_nil]
    jne     .cond_hit
    mov     rbx, [rbx + O_B]
    jmp     .cond_clause
.cond_hit:
    mov     r12, rax
    mov     rdi, r15
    call    scdr
    mov     r15, rax
    cmp     r15, [rel u_nil]
    jne     .seq
    mov     rax, r12                            ; (cond (x)) is x
    jmp     .ret
.cond_body:
    mov     rdi, r15
    call    scdr
    mov     r15, rax
    jmp     .seq

    ; --- (and e...) and (or e...) -------------------------------------------
.and:
    mov     rbx, r14
    mov     rax, [rel u_t]
.and_next:
    JNCONS  rbx, .ret
    mov     rcx, [rbx + O_B]
    JNCONS  rcx, .and_last
    mov     rdi, [rbx + O_A]
    mov     rsi, r13
    call    eval
    cmp     rax, [rel u_nil]
    je      .ret
    mov     rbx, [rbx + O_B]
    jmp     .and_next
.and_last:
    mov     r12, [rbx + O_A]
    jmp     .top

.or:
    mov     rbx, r14
    mov     rax, [rel u_nil]
.or_next:
    JNCONS  rbx, .ret
    mov     rcx, [rbx + O_B]
    JNCONS  rcx, .or_last
    mov     rdi, [rbx + O_A]
    mov     rsi, r13
    call    eval
    cmp     rax, [rel u_nil]
    jne     .ret
    mov     rbx, [rbx + O_B]
    jmp     .or_next
.or_last:
    mov     r12, [rbx + O_A]
    jmp     .top

; ----------------------------------------------------------------------------
; evlis -- RDI = a list of expressions, RSI = an environment.
; Returns RAX = a fresh list of their values, in order.
; ----------------------------------------------------------------------------
evlis:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r14, rsi
    mov     r12, [rel u_nil]                    ; the head
    xor     r13d, r13d                          ; the last cell, once there is one
.next:
    JNCONS  rbx, .done
    mov     rdi, [rbx + O_A]
    mov     rsi, r14
    call    eval
    mov     rdi, rax
    mov     rsi, [rel u_nil]
    call    cons
    test    r13, r13
    jnz     .link
    mov     r12, rax
    jmp     .linked
.link:
    mov     [r13 + O_B], rax
.linked:
    mov     r13, rax
    mov     rbx, [rbx + O_B]
    jmp     .next
.done:
    mov     rax, r12
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; bind -- RDI = parameters, RSI = arguments, RDX = the closure's environment.
; Returns RAX = that environment extended with one pair per parameter. A
; parameter list ending in a symbol rather than nil -- (a b . rest), or a lone
; symbol as the whole list -- binds that symbol to whatever arguments are left.
; ----------------------------------------------------------------------------
bind:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
.next:
    JNCONS  rbx, .rest
    JNCONS  r12, .few
    mov     rdi, [rbx + O_A]
    mov     rsi, [r12 + O_A]
    call    cons
    mov     rdi, rax
    mov     rsi, r13
    call    cons
    mov     r13, rax
    mov     rbx, [rbx + O_B]
    mov     r12, [r12 + O_B]
    jmp     .next
.rest:
    cmp     rbx, [rel u_nil]
    je      .exact
    test    rbx, 1
    jnz     .bad
    cmp     byte [rbx + O_TAG], T_SYM
    jne     .bad
    mov     rdi, rbx
    mov     rsi, r12
    call    cons
    mov     rdi, rax
    mov     rsi, r13
    call    cons
    mov     r13, rax
    jmp     .done
.exact:
    cmp     r12, [rel u_nil]
    jne     .many
.done:
    mov     rax, r13
    pop     r13
    pop     r12
    pop     rbx
    ret
.few:
    ERROR   "too few arguments", 0
.many:
    ERROR   "too many arguments:", r12
.bad:
    ERROR   "a parameter list cannot end in", rbx

; ----------------------------------------------------------------------------
; lookup_pair -- RDI = a symbol, RSI = an environment.
; Returns RAX = its (symbol . value) pair, or 0 if only the global applies.
; ----------------------------------------------------------------------------
lookup_pair:
    push    rsi
.next:
    JNCONS  rsi, .miss
    mov     rax, [rsi + O_A]
    cmp     [rax + O_A], rdi
    je      .hit
    mov     rsi, [rsi + O_B]
    jmp     .next
.miss:
    xor     eax, eax
.hit:
    pop     rsi
    ret

; ----------------------------------------------------------------------------
; make_lambda -- RDI = parameters, RSI = body, RDX = environment.
; ----------------------------------------------------------------------------
make_lambda:
    mov     al, T_LAMBDA
    call    alloc
    mov     [rax + O_A], rdi
    mov     [rax + O_B], rsi
    mov     [rax + O_C], rdx
    ret

; ----------------------------------------------------------------------------
; cons -- RDI = car, RSI = cdr. Returns RAX. Preserves everything else.
; ----------------------------------------------------------------------------
cons:
    mov     al, T_CONS
    call    alloc
    mov     [rax + O_A], rdi
    mov     [rax + O_B], rsi
    ret

; ----------------------------------------------------------------------------
; scar -- RDI = anything. Its car if it is a cons, nil if it is anything else,
; so that a malformed form reads as one with nils in it.
; ----------------------------------------------------------------------------
scar:
    JNCONS  rdi, .nil
    mov     rax, [rdi + O_A]
    ret
.nil:
    mov     rax, [rel u_nil]
    ret

; scdr -- RDI = anything. Its cdr if it is a cons, nil otherwise.
scdr:
    JNCONS  rdi, .nil
    mov     rax, [rdi + O_B]
    ret
.nil:
    mov     rax, [rel u_nil]
    ret

; ============================================================================
; Memory
; ============================================================================

; ----------------------------------------------------------------------------
; alloc -- AL = a tag. Returns RAX = an object with that tag and its fields
; zeroed. Preserves every other register, which is what makes it safe to
; collect from inside: whatever the caller is holding is still in a register,
; and gc pushes them all before it scans the stack.
; ----------------------------------------------------------------------------
alloc:
    push    rcx
    movzx   ecx, al
    mov     rax, [rel u_free]
    test    rax, rax
    jnz     .take
    mov     rax, [rel u_bump]
    cmp     rax, [rel u_heap_hi]
    jae     .collect
    add     qword [rel u_bump], OBJ_SIZE
    jmp     .init
.collect:
    call    gc
    mov     rax, [rel u_free]
    test    rax, rax
    jz      .full
.take:
    push    rdx
    mov     rdx, [rax + O_A]
    mov     [rel u_free], rdx
    pop     rdx
.init:
    mov     [rax], rcx                          ; the tag, and a clear mark
    mov     qword [rax + O_A], 0
    mov     qword [rax + O_B], 0
    mov     qword [rax + O_C], 0
    pop     rcx
    ret
.full:
    pop     rcx
    ERROR   "out of memory", 0

; ----------------------------------------------------------------------------
; gc -- mark from the roots and the stack, then sweep the heap into a free list.
; ----------------------------------------------------------------------------
gc:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rbp
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    lea     rbx, [rel u_nil]                    ; the first root
.root:
    lea     rax, [rel ROOTS_END]
    cmp     rbx, rax
    jae     .stack
    mov     rdi, [rbx]
    call    mark
    add     rbx, 8
    jmp     .root

    ; Every word from here to the top of the stack, registers included,
    ; since they were pushed just above.
.stack:
    mov     rbx, rsp
.word:
    cmp     rbx, [rel u_stack_top]
    jae     .sweep
    mov     rdi, [rbx]
    call    mark
    add     rbx, 8
    jmp     .word

.sweep:
    mov     rbx, [rel u_heap_lo]
    xor     edx, edx                            ; the free list
    xor     ecx, ecx                            ; how many went on it
.cell:
    cmp     rbx, [rel u_bump]
    jae     .swept
    cmp     byte [rbx + O_MARK], 0
    je      .dead
    mov     byte [rbx + O_MARK], 0
    jmp     .advance
.dead:
    mov     byte [rbx + O_TAG], T_FREE
    mov     [rbx + O_A], rdx
    mov     rdx, rbx
    inc     rcx
.advance:
    add     rbx, OBJ_SIZE
    jmp     .cell
.swept:
    mov     [rel u_free], rdx
    mov     [rel u_gc_freed], rcx
    inc     qword [rel u_gc_runs]

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; mark -- RDI = any word. If it is the address of an object in the heap, mark
; it and everything it reaches. Anything else -- an integer, a return address,
; a stale value -- is ignored, which is all conservatism means. Clobbers RAX
; and RDI. Recurses on cars and loops on cdrs, so a long list costs no stack.
; ----------------------------------------------------------------------------
mark:
    test    rdi, 1
    jnz     .done
    cmp     rdi, [rel u_heap_lo]
    jb      .done
    cmp     rdi, [rel u_bump]
    jae     .done
    mov     rax, rdi
    sub     rax, [rel u_heap_lo]
    test    eax, OBJ_SIZE - 1
    jnz     .done
    cmp     byte [rdi + O_MARK], 0
    jne     .done
    movzx   eax, byte [rdi + O_TAG]
    cmp     al, T_FREE
    je      .done
    mov     byte [rdi + O_MARK], 1
    cmp     al, T_CONS
    je      .cons
    cmp     al, T_SYM
    je      .sym
    cmp     al, T_LAMBDA
    je      .lambda
.done:
    ret
.cons:
    push    rdi
    mov     rdi, [rdi + O_A]
    call    mark
    pop     rdi
    mov     rdi, [rdi + O_B]
    jmp     mark
.sym:
    mov     rdi, [rdi + O_B]
    jmp     mark
.lambda:
    push    rdi
    mov     rdi, [rdi + O_A]
    call    mark
    mov     rdi, [rsp]
    mov     rdi, [rdi + O_B]
    call    mark
    pop     rdi
    mov     rdi, [rdi + O_C]
    jmp     mark

; ----------------------------------------------------------------------------
; intern -- RSI = a name, RCX = its length. Returns RAX = the one symbol with
; that name, made if there was none.
; ----------------------------------------------------------------------------
intern:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    mov     rbx, [rel u_symbols]
.walk:
    test    rbx, rbx                            ; the list ends in 0 until nil exists
    jz      .new
    JNCONS  rbx, .new
    mov     rdx, [rbx + O_A]                    ; a symbol
    mov     rdi, [rdx + O_A]                    ; its name
    push    rcx
    push    rsi
    push    rdi
    repe    cmpsb
    pop     rdi
    pop     rsi
    pop     rcx
    jne     .skip
    cmp     byte [rdi + rcx], 0
    jne     .skip
    mov     rax, rdx
    jmp     .done
.skip:
    mov     rbx, [rbx + O_B]
    jmp     .walk
.new:
    mov     rdi, [rel u_names]
    lea     rax, [rdi + rcx + 1]
    cmp     rax, [rel u_names_end]
    ja      .full
    mov     [rel u_names], rax
    mov     r8, rdi
    rep     movsb
    mov     byte [rdi], 0
    mov     al, T_SYM
    call    alloc
    mov     [rax + O_A], r8
    mov     rdi, rax
    mov     rsi, [rel u_symbols]
    call    cons
    mov     [rel u_symbols], rax
    mov     rax, rdi
.done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
.full:
    ERROR   "no room left for symbol names", 0

; ----------------------------------------------------------------------------
; intern_cstr -- RSI = a NUL-terminated name. Returns RAX = its symbol.
; ----------------------------------------------------------------------------
intern_cstr:
    push    rcx
    xor     ecx, ecx
.len:
    cmp     byte [rsi + rcx], 0
    je      .have
    inc     ecx
    jmp     .len
.have:
    call    intern
    pop     rcx
    ret

; ============================================================================
; The reader. Input is [u_rp, u_rend), consumed from the front.
; ============================================================================

; ----------------------------------------------------------------------------
; skip_ws -- step over blanks and ; comments. Returns AL = the next character,
; not consumed, or 0 at the end.
; ----------------------------------------------------------------------------
skip_ws:
    push    rsi
    mov     rsi, [rel u_rp]
.next:
    cmp     rsi, [rel u_rend]
    jae     .end
    mov     al, [rsi]
    cmp     al, ';'
    je      .comment
    cmp     al, ' '
    ja      .found
    inc     rsi
    jmp     .next
.comment:
    inc     rsi
    cmp     rsi, [rel u_rend]
    jae     .end
    cmp     byte [rsi], CH_LF
    jne     .comment
    jmp     .next
.end:
    xor     eax, eax
.found:
    mov     [rel u_rp], rsi
    pop     rsi
    ret

; ----------------------------------------------------------------------------
; is_delim -- AL = a character. ZF set if it ends a token.
; ----------------------------------------------------------------------------
is_delim:
    cmp     al, ' '
    jbe     .yes
    cmp     al, '('
    je      .done
    cmp     al, ')'
    je      .done
    cmp     al, CH_QUOTE
    je      .done
    cmp     al, ';'
.done:
    ret
.yes:
    cmp     al, al
    ret

; ----------------------------------------------------------------------------
; read_expr -- read one expression. Returns RAX.
; ----------------------------------------------------------------------------
read_expr:
    push    rbx
    push    rcx
    push    rsi
    push    rdi
    call    skip_ws
    test    al, al
    jz      .eof
    mov     rsi, [rel u_rp]
    cmp     al, '('
    je      .list
    cmp     al, ')'
    je      .close
    cmp     al, CH_QUOTE
    je      .quote

    mov     rbx, rsi                            ; a token: a number or a symbol
.token:
    inc     rsi
    cmp     rsi, [rel u_rend]
    jae     .token_end
    mov     al, [rsi]
    call    is_delim
    jnz     .token
.token_end:
    mov     [rel u_rp], rsi
    mov     rcx, rsi
    sub     rcx, rbx
    mov     rsi, rbx
    call    parse_int
    jnc     .done
    call    intern
    jmp     .done

.list:
    inc     rsi
    mov     [rel u_rp], rsi
    call    read_list
    jmp     .done

.quote:
    inc     rsi
    mov     [rel u_rp], rsi
    call    read_expr
    mov     rdi, rax
    mov     rsi, [rel u_nil]
    call    cons
    mov     rsi, rax
    mov     rdi, [rel u_quote]
    call    cons
.done:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    ret

.close:
    inc     rsi
    mov     [rel u_rp], rsi
    ERROR   "unexpected )", 0
.eof:
    ERROR   "unexpected end of input", 0

; ----------------------------------------------------------------------------
; read_list -- after the "(". Returns RAX = the list, having eaten the ")".
; ----------------------------------------------------------------------------
read_list:
    push    rbx
    push    r12
    push    r13
    push    rsi
    push    rdi
    mov     r12, [rel u_nil]                    ; the head
    xor     r13d, r13d                          ; the last cell
.next:
    call    skip_ws
    test    al, al
    jz      .eof
    cmp     al, ')'
    je      .end
    cmp     al, '.'
    jne     .element
    mov     rsi, [rel u_rp]
    lea     rax, [rsi + 1]
    cmp     rax, [rel u_rend]
    jae     .element
    mov     al, [rsi + 1]
    call    is_delim
    jnz     .element
    ; A lone dot: what follows is the cdr of the last cell.
    test    r13, r13
    jz      .bad_dot
    inc     rsi
    mov     [rel u_rp], rsi
    call    read_expr
    mov     [r13 + O_B], rax
    call    skip_ws
    cmp     al, ')'
    jne     .bad_dot
.end:
    inc     qword [rel u_rp]
    mov     rax, r12
    pop     rdi
    pop     rsi
    pop     r13
    pop     r12
    pop     rbx
    ret
.element:
    call    read_expr
    mov     rdi, rax
    mov     rsi, [rel u_nil]
    call    cons
    test    r13, r13
    jnz     .link
    mov     r12, rax
    jmp     .linked
.link:
    mov     [r13 + O_B], rax
.linked:
    mov     r13, rax
    jmp     .next
.eof:
    ERROR   "unexpected end of input inside a list", 0
.bad_dot:
    ERROR   "a dot belongs between the last two things in a list", 0

; ----------------------------------------------------------------------------
; parse_int -- RSI = a token, RCX = its length. CF clear and RAX = the
; integer as a value if the token is one; CF set if it is not.
; ----------------------------------------------------------------------------
parse_int:
    push    rcx
    push    rdx
    push    rsi
    push    r8
    xor     r8d, r8d
    mov     al, [rsi]
    cmp     al, '-'
    je      .signed
    cmp     al, '+'
    jne     .digits
.signed:
    cmp     rcx, 1
    je      .no                                 ; "-" alone is a symbol
    cmp     al, '-'
    sete    r8b
    inc     rsi
    dec     rcx
.digits:
    xor     eax, eax
.digit:
    movzx   edx, byte [rsi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .no
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    dec     rcx
    jnz     .digit
    test    r8d, r8d
    jz      .positive
    neg     rax
.positive:
    lea     rax, [rax * 2 + 1]
    clc
    jmp     .done
.no:
    stc
.done:
    pop     r8
    pop     rsi
    pop     rdx
    pop     rcx
    ret

; ============================================================================
; The printer, and the output line it fills
; ============================================================================

; ----------------------------------------------------------------------------
; print -- RDI = a value, appended to the output line.
; ----------------------------------------------------------------------------
print:
    push    rax
    push    rbx
    push    rsi
    push    rdi
    test    rdi, 1
    jnz     .integer
    test    rdi, rdi
    jz      .unbound
    movzx   eax, byte [rdi + O_TAG]
    cmp     al, T_SYM
    je      .symbol
    cmp     al, T_CONS
    je      .list
    cmp     al, T_PRIM
    je      .prim
    cmp     al, T_LAMBDA
    je      .lambda
    OUTS    "#<?>"
    jmp     .done
.integer:
    mov     rax, rdi
    sar     rax, 1
    call    out_dec
    jmp     .done
.unbound:
    OUTS    "#<unbound>"
    jmp     .done
.symbol:
    mov     rsi, [rdi + O_A]
    call    out_str
    jmp     .done
.prim:
    OUTS    "#<primitive "
    mov     rsi, [rdi + O_B]
    call    out_str
    mov     al, '>'
    call    out_char
    jmp     .done
.lambda:
    OUTS    "#<lambda>"
    jmp     .done
.list:
    mov     al, '('
    call    out_char
    mov     rbx, rdi
.element:
    mov     rdi, [rbx + O_A]
    call    print
    mov     rbx, [rbx + O_B]
    cmp     rbx, [rel u_nil]
    je      .close
    JNCONS  rbx, .dotted
    mov     al, ' '
    call    out_char
    jmp     .element
.dotted:
    OUTS    " . "
    mov     rdi, rbx
    call    print
.close:
    mov     al, ')'
    call    out_char
.done:
    pop     rdi
    pop     rsi
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; The output line: everything printed is gathered here and written in one
; system call, so another task's output cannot land in the middle of it. A
; line longer than OUT_MAX is cut short.
; ----------------------------------------------------------------------------

; out_reset -- start a new, empty line.
out_reset:
    mov     qword [rel u_out_len], 0
    ret

; out_char -- AL = a character, appended.
out_char:
    push    rcx
    push    rdx
    mov     rcx, [rel u_out_len]
    cmp     rcx, OUT_MAX
    jae     .full
    lea     rdx, [rel u_out]
    mov     [rdx + rcx], al
    inc     qword [rel u_out_len]
.full:
    pop     rdx
    pop     rcx
    ret

; out_str -- RSI = a NUL-terminated string, appended.
out_str:
    push    rax
    push    rsi
.next:
    lodsb
    test    al, al
    jz      .done
    call    out_char
    jmp     .next
.done:
    pop     rsi
    pop     rax
    ret

; out_src -- RSI = source text, RCX = its length; line breaks become spaces.
out_src:
    push    rax
    push    rcx
    push    rsi
    test    rcx, rcx
    jz      .done
.next:
    lodsb
    cmp     al, ' '
    jae     .put
    mov     al, ' '
.put:
    call    out_char
    dec     rcx
    jnz     .next
.done:
    pop     rsi
    pop     rcx
    pop     rax
    ret

; out_dec -- RAX = a signed integer, appended in decimal.
out_dec:
    push    rax
    push    rcx
    push    rdx
    push    rdi
    test    rax, rax
    jns     .positive
    push    rax
    mov     al, '-'
    call    out_char
    pop     rax
    neg     rax
.positive:
    sub     rsp, 32
    lea     rdi, [rsp + 32]
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    rax, rax
    jnz     .digit
.emit:
    lea     rax, [rsp + 32]
    cmp     rdi, rax
    jae     .done
    mov     al, [rdi]
    call    out_char
    inc     rdi
    jmp     .emit
.done:
    add     rsp, 32
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; out_flush -- write the line as it stands, without ending it, and empty it.
out_flush:
    push    rsi
    push    rcx
    lea     rsi, [rel u_out]
    mov     rcx, [rel u_out_len]
    call    write_bytes
    mov     qword [rel u_out_len], 0
    pop     rcx
    pop     rsi
    ret

; out_line -- end the line and write it.
out_line:
    push    rax
    mov     al, CH_LF
    call    out_char
    call    out_flush
    pop     rax
    ret

; ----------------------------------------------------------------------------
; write_bytes -- RSI = bytes, RCX = how many. Preserves every register; the
; system call takes RCX, R11 and R10, so they are saved here instead of at
; every caller.
; ----------------------------------------------------------------------------
write_bytes:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r10
    push    r11
    mov     rdi, rsi
    mov     rsi, rcx
    call    u_write
    pop     r11
    pop     r10
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ============================================================================
; Primitives. Each takes RDI = its evaluated argument list, returns RAX, and
; may keep anything it likes in RBX: the caller does not.
; ============================================================================

; next_int -- RBX = an argument list. Returns RAX = its first element as a
; plain integer, and advances RBX past it.
next_int:
    JNCONS  rbx, .few
    mov     rax, [rbx + O_A]
    test    rax, 1
    jz      .nan
    sar     rax, 1
    mov     rbx, [rbx + O_B]
    ret
.few:
    ERROR   "too few arguments", 0
.nan:
    ERROR   "not a number:", rax

; truth_if_zf -- ZF set means true. Returns RAX = t or nil.
truth_if_zf:
    mov     rax, [rel u_nil]
    jnz     .done
    mov     rax, [rel u_t]
.done:
    ret

; p_add -- (+ n...): the sum, 0 for none.
p_add:
    push    rbx
    push    r8
    mov     rbx, rdi
    xor     r8d, r8d
.next:
    JNCONS  rbx, .done
    call    next_int
    add     r8, rax
    jmp     .next
.done:
    lea     rax, [r8 * 2 + 1]
    pop     r8
    pop     rbx
    ret

; p_mul -- (* n...): the product, 1 for none.
p_mul:
    push    rbx
    push    r8
    mov     rbx, rdi
    mov     r8d, 1
.next:
    JNCONS  rbx, .done
    call    next_int
    imul    r8, rax
    jmp     .next
.done:
    lea     rax, [r8 * 2 + 1]
    pop     r8
    pop     rbx
    ret

; p_sub -- (- n) negates; (- n m...) subtracts the rest from the first.
p_sub:
    push    rbx
    push    r8
    mov     rbx, rdi
    call    next_int
    mov     r8, rax
    JNCONS  rbx, .negate
.next:
    JNCONS  rbx, .done
    call    next_int
    sub     r8, rax
    jmp     .next
.negate:
    neg     r8
.done:
    lea     rax, [r8 * 2 + 1]
    pop     r8
    pop     rbx
    ret

; p_quotient -- (quotient n m): truncated toward zero.
p_quotient:
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, rdi
    call    next_int
    mov     rcx, rax
    call    next_int
    test    rax, rax
    jz      divide_by_zero
    xchg    rax, rcx
    cqo
    idiv    rcx
    lea     rax, [rax * 2 + 1]
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; p_remainder -- (remainder n m): with the sign of n, as idiv leaves it.
p_remainder:
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, rdi
    call    next_int
    mov     rcx, rax
    call    next_int
    test    rax, rax
    jz      divide_by_zero
    xchg    rax, rcx
    cqo
    idiv    rcx
    lea     rax, [rdx * 2 + 1]
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; divide_by_zero -- the error both divisions share. Does not return.
divide_by_zero:
    ERROR   "division by zero", 0

; Comparisons: two integers, t or nil.
%macro COMPARE 2                            ; name, setcc
%1:
    push    rbx
    push    rcx
    mov     rbx, rdi
    call    next_int
    mov     rcx, rax
    call    next_int
    cmp     rcx, rax
    %2      al
    movzx   ecx, al
    mov     rax, [rel u_nil]
    test    ecx, ecx
    jz      %%done
    mov     rax, [rel u_t]
%%done:
    pop     rcx
    pop     rbx
    ret
%endmacro

COMPARE p_lt, setl
COMPARE p_gt, setg
COMPARE p_le, setle
COMPARE p_ge, setge
COMPARE p_num_eq, sete

; p_eq -- (eq? a b): the same object, or the same integer.
p_eq:
    push    rdi
    push    rsi
    call    scar
    mov     rsi, rax
    call    scdr
    mov     rdi, rax
    call    scar
    cmp     rax, rsi
    call    truth_if_zf
    pop     rsi
    pop     rdi
    ret

; p_cons -- (cons a b): a fresh pair.
p_cons:
    push    rdi
    push    rsi
    call    scdr
    mov     rsi, rax
    mov     rdi, rsi
    call    scar
    mov     rsi, rax                            ; the second argument
    mov     rdi, [rsp + 8]
    call    scar
    mov     rdi, rax                            ; the first
    call    cons
    pop     rsi
    pop     rdi
    ret

; p_car -- (car l): the first element; (car nil) is nil.
p_car:
    call    scar
    cmp     rax, [rel u_nil]
    je      .done
    JNCONS  rax, not_a_list
    mov     rax, [rax + O_A]
.done:
    ret

; p_cdr -- (cdr l): the rest; (cdr nil) is nil.
p_cdr:
    call    scar
    cmp     rax, [rel u_nil]
    je      .done
    JNCONS  rax, not_a_list
    mov     rax, [rax + O_B]
.done:
    ret

; not_a_list -- RAX = the offender. Does not return.
not_a_list:
    ERROR   "not a list:", rax

; p_list -- (list x...): the argument list itself, which evlis made fresh.
p_list:
    mov     rax, rdi
    ret

; p_null -- (null? x) and (not x): t for nil, nil for anything else.
p_null:
    call    scar
    cmp     rax, [rel u_nil]
    jmp     truth_if_zf

; p_pair -- (pair? x): t for a cons.
p_pair:
    call    scar
    JNCONS  rax, .no
    cmp     eax, eax
    jmp     truth_if_zf
.no:
    mov     rax, [rel u_nil]
    ret

; p_number -- (number? x): t for an integer.
p_number:
    call    scar
    test    rax, 1
    jz      .no
    cmp     eax, eax
    jmp     truth_if_zf
.no:
    mov     rax, [rel u_nil]
    ret

; p_symbol -- (symbol? x): t for a symbol.
p_symbol:
    call    scar
    test    rax, 1
    jnz     .no
    cmp     byte [rax + O_TAG], T_SYM
    jmp     truth_if_zf
.no:
    mov     rax, [rel u_nil]
    ret

; p_display -- (display x...): print the arguments on a line of their own. Returns nil.
p_display:
    push    rbx
    push    rdi
    mov     rbx, rdi
    call    out_reset
    OUTS    "task 4   "
.next:
    JNCONS  rbx, .done
    mov     rdi, [rbx + O_A]
    call    print
    mov     rbx, [rbx + O_B]
    JNCONS  rbx, .done
    mov     al, ' '
    call    out_char
    jmp     .next
.done:
    call    out_line
    mov     rax, [rel u_nil]
    pop     rdi
    pop     rbx
    ret

; p_gc -- (gc): collect now. Returns how many cells are free.
p_gc:
    call    gc
    mov     rax, [rel u_gc_freed]
    lea     rax, [rax * 2 + 1]
    ret

%include "ulib.inc"

; ============================================================================
; Data
; ============================================================================

n_nil:      db "nil", 0
n_t:        db "t", 0
n_quote:    db "quote", 0
n_if:       db "if", 0
n_define:   db "define", 0
n_lambda:   db "lambda", 0
n_let:      db "let", 0
n_begin:    db "begin", 0
n_set:      db "set!", 0
n_cond:     db "cond", 0
n_and:      db "and", 0
n_or:       db "or", 0
n_else:     db "else", 0

n_add:      db "+", 0
n_sub:      db "-", 0
n_mul:      db "*", 0
n_quotient: db "quotient", 0
n_remainder: db "remainder", 0
n_lt:       db "<", 0
n_gt:       db ">", 0
n_le:       db "<=", 0
n_ge:       db ">=", 0
n_num_eq:   db "=", 0
n_eq:       db "eq?", 0
n_cons:     db "cons", 0
n_car:      db "car", 0
n_cdr:      db "cdr", 0
n_list:     db "list", 0
n_null:     db "null?", 0
n_not:      db "not", 0
n_pair:     db "pair?", 0
n_number:   db "number?", 0
n_symbol:   db "symbol?", 0
n_display:  db "display", 0
n_gc:       db "gc", 0

s_newline:  db CH_LF
s_rubout:   db CH_BS, ' ', CH_BS

; The demo. Each line's result is printed; the last line is an error on
; purpose, to show the REPL surviving one.
demo_src:
    db "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))", 10
    db "(fact 20)", 10
    db "(define (map f l) (if (null? l) nil (cons (f (car l)) (map f (cdr l)))))", 10
    db "(map (lambda (x) (* x x)) '(1 2 3 4 5))", 10
    db "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))", 10
    db "(fib 20)", 10
    db "(let ((x 3) (y 4)) (+ (* x x) (* y y)))", 10
    db "(define (make-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n)))", 10
    db "(define tick (make-counter))", 10
    db "(tick)", 10
    db "(tick)", 10
    db "; a million-ish allocations, and a loop no stack could hold without tail calls", 10
    db "(define (sum-to i acc) (if (= i 0) acc (sum-to (- i 1) (+ acc i))))", 10
    db "(sum-to 100000 0)", 10
    db "(no-such-function 1 2)", 10
DEMO_LEN        equ $ - demo_src

align 8
; Tables of (name, where) pairs. Labels are offsets from the start of the
; image, since it is assembled at 0; adding the window turns them into
; addresses.
special_table:
    dq n_quote,  u_quote
    dq n_if,     u_if
    dq n_define, u_define
    dq n_lambda, u_lambda
    dq n_let,    u_let
    dq n_begin,  u_begin
    dq n_set,    u_set
    dq n_cond,   u_cond
    dq n_and,    u_and
    dq n_or,     u_or
    dq n_else,   u_else
SPECIAL_COUNT   equ ($ - special_table) / 16

prim_table:
    dq n_add,       p_add
    dq n_sub,       p_sub
    dq n_mul,       p_mul
    dq n_quotient,  p_quotient
    dq n_remainder, p_remainder
    dq n_lt,        p_lt
    dq n_gt,        p_gt
    dq n_le,        p_le
    dq n_ge,        p_ge
    dq n_num_eq,    p_num_eq
    dq n_eq,        p_eq
    dq n_cons,      p_cons
    dq n_car,       p_car
    dq n_cdr,       p_cdr
    dq n_list,      p_list
    dq n_null,      p_null
    dq n_not,       p_null
    dq n_pair,      p_pair
    dq n_number,    p_number
    dq n_symbol,    p_symbol
    dq n_display,   p_display
    dq n_gc,        p_gc
PRIM_COUNT      equ ($ - prim_table) / 16

; --- roots: every word from u_nil to ROOTS_END is marked at each collection ---
u_nil:      dq 0
u_t:        dq 0
u_symbols:  dq 0
u_quote:    dq 0
u_if:       dq 0
u_define:   dq 0
u_lambda:   dq 0
u_let:      dq 0
u_begin:    dq 0
u_set:      dq 0
u_cond:     dq 0
u_and:      dq 0
u_or:       dq 0
u_else:     dq 0
u_expr:     dq 0
ROOTS_END       equ $

; --- everything else ----------------------------------------------------------
u_window:       dq 0
u_names:        dq 0
u_names_end:    dq 0
u_heap_lo:      dq 0
u_heap_hi:      dq 0
u_bump:         dq 0
u_free:         dq 0
u_stack_floor:  dq 0
u_stack_top:    dq 0
u_top_rsp:      dq 0
u_resume:       dq 0
u_gc_runs:      dq 0
u_gc_freed:     dq 0
u_rp:           dq 0
u_rend:         dq 0
u_src:          dq 0
u_len:          dq 0
u_depth:        dq 0
u_out_len:      dq 0
u_key:          db 0
u_out:          times OUT_MAX db 0

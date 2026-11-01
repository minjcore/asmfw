; ============================================================================
; idt.asm -- traps
;
; Every vector gets a stub, and the stubs are one fixed size each, so the
; address of vector N is isr_stubs + N * ISR_STUB_SIZE. That is not a
; micro-optimisation: this image is assembled at `org 0` and loaded wherever
; the firmware decides, so a table of `dq isr_n` would hold file offsets, not
; addresses. Arithmetic on a RIP-relative label needs no such fixing up.
;
; A trap taken from ring 3 kills the task. A trap taken from ring 0 is the
; kernel having gone wrong, and there is nothing left to hand off to.
; ============================================================================

bits 64

; The frame as isr_common sees it: the stub's two words and the CPU's five,
; above the register file this handler pushes on top of them.
TRAP_VECTOR     equ GPR_BYTES + 0x00
TRAP_ERROR      equ GPR_BYTES + 0x08
TRAP_RIP        equ GPR_BYTES + 0x10
TRAP_CS         equ GPR_BYTES + 0x18
TRAP_RFLAGS     equ GPR_BYTES + 0x20
TRAP_RSP        equ GPR_BYTES + 0x28
TRAP_SS         equ GPR_BYTES + 0x30

CPL_MASK        equ 3
CPL_USER        equ 3

; ----------------------------------------------------------------------------
; idt_init -- point every gate at its stub and load the table
; ----------------------------------------------------------------------------
idt_init:
    push    rax
    push    rbx
    push    rcx
    push    rdi

    lea     rbx, [rel isr_stubs]
    lea     rdi, [rel idt]
    xor     ecx, ecx
.gate:
    mov     rax, rcx
    imul    rax, ISR_STUB_SIZE
    add     rax, rbx

    mov     [rdi + 0], ax
    mov     word [rdi + 2], KSEL_CODE
    mov     byte [rdi + 4], 0                   ; no IST: RSP0 is stack enough
    mov     byte [rdi + 5], IDT_TYPE_INT
    shr     rax, 16
    mov     [rdi + 6], ax
    shr     rax, 16
    mov     [rdi + 8], eax
    mov     dword [rdi + 12], 0

    add     rdi, IDT_ENTRY_SIZE
    inc     ecx
    cmp     ecx, IDT_ENTRIES
    jb      .gate

    lea     rax, [rel idt]
    mov     [rel idt_ptr + 2], rax
    lidt    [rel idt_ptr]

    pop     rdi
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; isr_common -- every vector arrives here.
;
; The register file goes down first and unconditionally, because the timer
; needs it saved and a fault wants it reported, and because a task resumed
; later must find it exactly where the switch left it.
;
; RBP addresses the frame rather than RSP, so the console calls below cannot
; move it out from under the reads.
; ----------------------------------------------------------------------------
isr_common:
    PUSH_GPRS
    mov     rbp, rsp

    cmp     qword [rbp + TRAP_VECTOR], VEC_TIMER
    je      isr_timer
    cmp     qword [rbp + TRAP_VECTOR], VEC_KBD
    je      isr_kbd
    cmp     qword [rbp + TRAP_VECTOR], VEC_SCHED
    je      isr_resched

    mov     dword [rel kc_fg], KC_ERR
    kputsi  10, "trap "
    mov     rax, [rbp + TRAP_VECTOR]
    call    kc_putdec
    kputsi  " ("
    mov     rax, [rbp + TRAP_VECTOR]
    call    trap_put_name
    kputsi  "), error "
    mov     rax, [rbp + TRAP_ERROR]
    call    kc_puthex16
    kputsi  10, "     rip "
    mov     rax, [rbp + TRAP_RIP]
    call    kc_puthex64
    kputsi  "  cs "
    mov     rax, [rbp + TRAP_CS]
    call    kc_puthex16
    kputsi  "  rsp "
    mov     rax, [rbp + TRAP_RSP]
    call    kc_puthex64
    kputsi  "  rflags "
    mov     rax, [rbp + TRAP_RFLAGS]
    call    kc_puthex16
    kputsi  "  ticks "
    mov     rax, [rel g_ticks]
    call    kc_putdec
    mov     al, CHAR_LF
    call    kc_putc
    mov     dword [rel kc_fg], KC_FG

    mov     rax, [rbp + TRAP_CS]
    and     eax, CPL_MASK
    cmp     eax, CPL_USER
    je      task_faulted

    ; The kernel faulted. There is no lower layer to fall back on.
    kputsi  "the fault was in ring 0, which leaves nowhere to return to", 10
.halt:
    cli
    hlt
    jmp     .halt

; ----------------------------------------------------------------------------
; isr_timer -- the tick. Acknowledge it, put the current task down, pick the
; next one up.
;
; The end of interrupt goes out before the switch rather than after, because
; after it there is no "after": sched_run leaves through iretq on somebody
; else's stack and this code is not returned to.
; ----------------------------------------------------------------------------
isr_timer:
    inc     qword [rel g_ticks]

    mov     al, PIC_EOI
    mov     dx, PIC1_CMD
    out     dx, al

    call    sched_wake_due

    ; The tick that proves the timer works arrives before there is anything to
    ; schedule, and the idle loop runs with no current task by design, so this
    ; path has to cope with there being nobody to put down.
    mov     r10, [rel g_current]
    test    r10, r10
    jz      .nobody_running
    mov     [r10 + T_RSP], rsp
.nobody_running:
    call    sched_next
    test    rax, rax
    jz      .stay_parked
    jmp     sched_run
.stay_parked:
    cmp     qword [rel g_current], 0
    jne     sched_park
    POP_GPRS
    add     rsp, 16                     ; already idling; go back to it
    iretq

; ----------------------------------------------------------------------------
; isr_resched -- the kernel asking itself for a context switch.
;
; No end of interrupt: nothing in hardware raised this. The caller is inside
; a system call, and this is what turns its half-finished stack frame into
; something the switch knows how to resume.
; ----------------------------------------------------------------------------
isr_resched:
    mov     r10, [rel g_current]
    test    r10, r10
    jz      .nobody_running
    mov     [r10 + T_RSP], rsp
.nobody_running:
    call    sched_next
    test    rax, rax
    jz      sched_park
    jmp     sched_run

; ----------------------------------------------------------------------------
; task_faulted -- a trap that came from ring 3. The task is over; the machine
; is not. This is the difference the whole arrangement exists to produce.
; ----------------------------------------------------------------------------
task_faulted:
    mov     rax, [rel g_current]
    mov     qword [rax + T_STATE], TASK_DEAD
    call    con_release_if_owned

    kputsi  "kernel   task "
    mov     rax, [rel g_current]
    mov     rax, [rax + T_ID]
    call    kc_putdec
    kputsi  " killed; the others keep running", 10

    call    sched_next
    test    rax, rax
    jz      sched_park
    jmp     sched_run

; ----------------------------------------------------------------------------
; trap_put_name -- RAX = vector. Names are fixed width so that the lookup is
; an index rather than a pointer, for the same `org 0` reason as the stubs.
; ----------------------------------------------------------------------------
trap_put_name:
    push    rax
    push    rcx
    push    rsi
    cmp     rax, VEC_NAMED
    jae     .unnamed
    imul    rax, VEC_NAME_LEN
    lea     rsi, [rel trap_names]
    add     rsi, rax
    mov     ecx, VEC_NAME_LEN
.emit:
    lodsb
    call    kc_putc
    dec     ecx
    jnz     .emit
    jmp     .done
.unnamed:
    kputsi  "int "
.done:
    pop     rsi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; The stubs. A vector the CPU pushes an error code for must not push a second
; one, or every field above it is off by eight.
; ----------------------------------------------------------------------------
%macro ISR_STUB 1
    %%start:
    %if ((ISR_ERR_MASK >> %1) & 1) == 0
        push    strict dword 0
    %endif
        push    strict dword %1
        jmp     strict near isr_common
        times ISR_STUB_SIZE - ($ - %%start) db 0xCC
%endmacro

align 16
isr_stubs:
%assign isr_vector 0
%rep IDT_ENTRIES
    ISR_STUB isr_vector
%assign isr_vector isr_vector + 1
%endrep

; ----------------------------------------------------------------------------
trap_names:
    db "#DE ", "#DB ", "NMI ", "#BP ", "#OF ", "#BR ", "#UD ", "#NM "
    db "#DF ", "res ", "#TS ", "#NP ", "#SS ", "#GP ", "#PF ", "res "
    db "#MF ", "#AC ", "#MC ", "#XM ", "#VE ", "#CP ", "res ", "res "
    db "res ", "res ", "res ", "res ", "#HV ", "#VC ", "#SX ", "res "

align 8
idt_ptr:
    dw  IDT_ENTRIES * IDT_ENTRY_SIZE - 1
    dq  0                                       ; base, filled in by idt_init

align 16
idt:
    times IDT_ENTRIES * IDT_ENTRY_SIZE db 0

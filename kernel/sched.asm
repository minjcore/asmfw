; ============================================================================
; sched.asm -- more than one thing at a time
;
; The switch is deliberately small. A task's registers live on its own kernel
; stack, so saving it is one store of RSP and restoring it is one load; the
; task structure holds no register file at all. What that buys is that a task
; which has never run and a task which was interrupted mid-instruction are the
; same shape, and one code path starts both -- task_create simply writes the
; frame the interrupt would have left.
;
; Scheduling happens on the 8254's tick and nowhere else, except when a task
; removes itself by exiting or by faulting.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; lapic_init -- virtual wire mode.
;
; Software-enable the local APIC, then tell it that whatever arrives on LINT0
; is an external interrupt to be taken from the 8259 and that LINT1 is NMI.
; Until this runs the PIC is programmed correctly and connected to nothing.
; ----------------------------------------------------------------------------
lapic_init:
    push    rax
    mov     rax, LAPIC_BASE
    mov     dword [rax + LAPIC_SVR], LAPIC_SPURIOUS | LAPIC_SVR_ENABLE
    mov     dword [rax + LAPIC_LVT_LINT0], LVT_MODE_EXTINT
    mov     dword [rax + LAPIC_LVT_LINT1], LVT_MODE_NMI
    pop     rax
    ret

; ----------------------------------------------------------------------------
; pic_init -- move the hardware interrupts off the exception vectors and let
; only the timer through. The firmware leaves IRQ0 arriving as vector 8, which
; is #DF: indistinguishable from the CPU giving up.
;
; Only the timer, because at this point only the timer has a handler that does
; anything. kbd_init opens IRQ1 for itself once it has one, and nothing else
; is ever opened at all.
; ----------------------------------------------------------------------------
pic_init:
    push    rax
    push    rdx

    mov     al, PIC_ICW1_INIT
    mov     dx, PIC1_CMD
    out     dx, al
    call    io_wait
    mov     dx, PIC2_CMD
    out     dx, al
    call    io_wait

    mov     al, PIC1_VECTOR
    mov     dx, PIC1_DATA
    out     dx, al
    call    io_wait
    mov     al, PIC2_VECTOR
    mov     dx, PIC2_DATA
    out     dx, al
    call    io_wait

    mov     al, PIC1_CASCADE
    mov     dx, PIC1_DATA
    out     dx, al
    call    io_wait
    mov     al, PIC2_IDENTITY
    mov     dx, PIC2_DATA
    out     dx, al
    call    io_wait

    mov     al, PIC_ICW4_8086
    mov     dx, PIC1_DATA
    out     dx, al
    call    io_wait
    mov     dx, PIC2_DATA
    out     dx, al
    call    io_wait

    mov     al, PIC1_TIMER_ONLY
    mov     dx, PIC1_DATA
    out     dx, al
    mov     al, PIC_MASK_ALL
    mov     dx, PIC2_DATA
    out     dx, al

    pop     rdx
    pop     rax
    ret

io_wait:
    push    rax
    push    rdx
    xor     al, al
    mov     dx, PORT_IO_WAIT
    out     dx, al
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; pit_init -- channel 0 as a rate generator, so IRQ0 arrives TICK_HZ times a
; second whether or not anybody is listening.
; ----------------------------------------------------------------------------
pit_init:
    push    rax
    push    rdx
    mov     al, PIT_RATE_GEN
    mov     dx, PIT_CMD
    out     dx, al
    mov     ax, PIT_DIVISOR
    mov     dx, PIT_CH0
    out     dx, al                              ; low byte
    mov     al, ah
    out     dx, al                              ; then high
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; timer_check -- prove the tick arrives before anything depends on it.
;
; A scheduler whose timer never fires looks exactly like a scheduler that
; works and is simply never asked to switch, so this asks once, in ring 0,
; where the answer is unambiguous.
; ----------------------------------------------------------------------------
timer_check:
    push    rdx
    push    rcx
    mov     rax, [rel g_ticks]
    mov     [rel g_tick_mark], rax
    sti
    mov     rcx, TIMER_CHECK_SPIN
.wait:
    mov     rax, [rel g_ticks]
    cmp     rax, [rel g_tick_mark]
    jne     .ticking
    dec     rcx
    jnz     .wait
    cli
    xor     eax, eax
    jmp     .done
.ticking:
    cli
    mov     eax, 1
.done:
    pop     rcx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; task_create -- RDI = id, RSI = its window, RDX = its PML4,
;                RCX = the window belonging to the next task along.
;
; The program is already in the window: whoever called this read it off the
; disk. What is built here is the stack frame an interrupt return will consume
; to start it, with the three argument registers already in place, because a
; flat binary loaded at an address it was not assembled for has no other way
; of learning anything.
; ----------------------------------------------------------------------------
task_create:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11

    mov     r8, rdi                             ; id
    mov     r9, rsi                             ; window
    mov     r10, rdx                            ; pml4
    mov     r11, rcx                            ; the neighbour's window

    ; --- its kernel stack -------------------------------------------------
    mov     rax, r8
    inc     rax
    imul    rax, KSTACK_SIZE
    lea     rbx, [rel tstacks]
    add     rbx, rax                            ; top of this task's stack
    mov     rdi, rbx

    ; The frame an interrupt from ring 3 would have left, written by hand.
    sub     rdi, 8
    mov     qword [rdi], USEL_DATA              ; SS
    sub     rdi, 8
    mov     rax, r9
    add     rax, USER_WINDOW_SIZE
    mov     [rdi], rax                          ; RSP, the top of its window
    sub     rdi, 8
    mov     qword [rdi], RFLAGS_USER            ; IF set: it starts preemptible
    sub     rdi, 8
    mov     qword [rdi], USEL_CODE              ; CS
    sub     rdi, 8
    mov     [rdi], r9                           ; RIP: a flat binary starts at
                                                ; the base of its window
    sub     rdi, 8
    mov     qword [rdi], 0                      ; the error code the stub pushes
    sub     rdi, 8
    mov     qword [rdi], 0                      ; and the vector
    mov     ecx, GPR_COUNT
.zero:
    sub     rdi, 8
    mov     qword [rdi], 0
    dec     ecx
    jnz     .zero

    mov     [rdi + FRAME_RDI], r8
    mov     [rdi + FRAME_RSI], r9
    mov     [rdi + FRAME_RDX], r11

    ; --- the structure ----------------------------------------------------
    mov     rax, r8
    imul    rax, T_SIZE
    lea     rcx, [rel tasks]
    add     rax, rcx
    mov     qword [rax + T_STATE], TASK_READY
    mov     [rax + T_PML4], r10
    mov     [rax + T_USER_BASE], r9
    mov     [rax + T_KSTACK], rbx
    mov     [rax + T_RSP], rdi
    mov     qword [rax + T_URSP], 0
    mov     [rax + T_ID], r8
    mov     qword [rax + T_STATUS], 0

    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; sched_next -- the task after the current one that is still willing to run.
; Returns RAX = a task, or 0 if there is nothing left.
;
; Round robin, and it can legitimately return the current task: being the only
; one left is not a reason to stop running.
; ----------------------------------------------------------------------------
sched_next:
    push    rcx
    push    rdx
    push    rsi
    mov     rax, [rel g_current]
    test    rax, rax
    jz      .from_the_top               ; nothing was running: start at zero
    mov     rdx, [rax + T_ID]
    jmp     .have_start
.from_the_top:
    mov     rdx, -1
.have_start:
    mov     ecx, TASK_COUNT
.probe:
    inc     rdx
    cmp     rdx, TASK_COUNT
    jb      .index
    xor     edx, edx
.index:
    mov     rax, rdx
    imul    rax, T_SIZE
    lea     rsi, [rel tasks]
    add     rax, rsi
    cmp     qword [rax + T_STATE], TASK_READY
    je      .found
    dec     ecx
    jnz     .probe
    xor     eax, eax
.found:
    pop     rsi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; sched_run -- RAX = the task to run. Never returns.
;
; CR3 changes before RSP does, which is safe only because every address space
; identity maps the kernel: the stack being switched away from and the stack
; being switched to are both present in both spaces.
; ----------------------------------------------------------------------------
sched_run:
    mov     [rel g_current], rax
    mov     rcx, [rax + T_KSTACK]
    lea     rdx, [rel tss]
    mov     [rdx + TSS_RSP0], rcx               ; where its next trap will land
    mov     rcx, [rax + T_PML4]
    mov     cr3, rcx
    mov     rsp, [rax + T_RSP]
    POP_GPRS
    add     rsp, 16                             ; the vector and error code
    iretq

; ----------------------------------------------------------------------------
; sched_park -- nothing can run at this instant.
;
; That is not the same as nothing ever running again: a sleeping task is not
; a dead one. If anything is still alive the CPU waits for the interrupt that
; will wake it, and waits in the only honest way -- halted, not spinning.
;
; That interrupt used to be the tick and nothing else, which made the wait a
; matter of arithmetic: something was going to become runnable at a tick that
; could be named in advance. A task waiting on the keyboard breaks that. The
; machine can now be genuinely idle with work outstanding, and stay idle for
; as long as nobody types.
;
; Entered from inside an interrupt handler, whose frame is abandoned. The idle
; loop has no state worth keeping, which is what makes that safe.
; ----------------------------------------------------------------------------
sched_park:
    call    sched_any_alive
    test    eax, eax
    jz      sched_finished

    mov     qword [rel g_current], 0
    lea     rsp, [rel kstack_top]
.idle:
    ; STI does not take effect until after the next instruction, so nothing
    ; can arrive in the gap and leave the CPU halted with work waiting.
    sti
    hlt
    jmp     .idle

sched_finished:
    lea     rsp, [rel kstack_top]
    kputsi  10, "kernel   every task has ended after "
    mov     rax, [rel g_ticks]
    call    kc_putdec
    kputsi  " timer ticks", 10
    jmp     khalt

; ----------------------------------------------------------------------------
; sched_any_alive -- EAX = 1 if any task could still run, now or later
; ----------------------------------------------------------------------------
sched_any_alive:
    push    rcx
    push    rdx
    lea     rdx, [rel tasks]
    mov     ecx, TASK_COUNT
.next:
    cmp     qword [rdx + T_STATE], TASK_DEAD
    je      .advance
    cmp     qword [rdx + T_STATE], TASK_FREE
    je      .advance
    mov     eax, 1
    jmp     .done
.advance:
    add     rdx, T_SIZE
    dec     ecx
    jnz     .next
    xor     eax, eax
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; sched_wake_due -- promote every sleeper whose tick has arrived
;
; A task waiting for a keystroke with a deadline is blocked for two reasons at
; once, and this is one of the two things that can end that wait. So the
; keyboard reason is cleared here as well: the wait is over however it ended,
; and leaving the flag set would offer the task a wake it has stopped wanting.
; ----------------------------------------------------------------------------
sched_wake_due:
    push    rax
    push    rcx
    push    rdx
    lea     rax, [rel tasks]
    mov     ecx, TASK_COUNT
.next:
    cmp     qword [rax + T_STATE], TASK_BLOCKED
    jne     .advance
    mov     rdx, [rax + T_WAKE]
    test    rdx, rdx
    jz      .advance                    ; on a lock or a key, not on the clock
    cmp     rdx, [rel g_ticks]
    ja      .advance
    mov     qword [rax + T_STATE], TASK_READY
    mov     qword [rax + T_WAKE], 0
    mov     qword [rax + T_WAITKEY], 0
.advance:
    add     rax, T_SIZE
    dec     ecx
    jnz     .next
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kbd_wake_waiters -- a key has arrived, so nobody is still waiting for one.
;
; Called from the keyboard interrupt, and the mirror image of sched_wake_due:
; the same two reasons cleared, from the other side. Every waiter is woken
; rather than one, because the buffer holds bytes and not a turn -- they
; re-test it in sys_read, and one that finds it emptied by somebody faster
; blocks again, which costs a trip round the loop and nothing else.
; ----------------------------------------------------------------------------
kbd_wake_waiters:
    push    rax
    push    rcx
    lea     rax, [rel tasks]
    mov     ecx, TASK_COUNT
.next:
    cmp     qword [rax + T_WAITKEY], 0
    je      .advance
    mov     qword [rax + T_WAITKEY], 0
    mov     qword [rax + T_WAKE], 0
    cmp     qword [rax + T_STATE], TASK_BLOCKED
    jne     .advance
    mov     qword [rax + T_STATE], TASK_READY
.advance:
    add     rax, T_SIZE
    dec     ecx
    jnz     .next
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; The console lock.
;
; Interrupts are on inside a system call now, so two tasks can be part way
; through writing at once. Rather than making that impossible by masking the
; timer -- which is what the kernel used to do, and what made a three kilobyte
; write hold the machine for a quarter of a second -- the second writer waits,
; and waits by blocking rather than by spinning.
;
; The test and set runs with interrupts off. Everything else does not.
; ----------------------------------------------------------------------------
con_acquire:
    push    rax
    push    rdx
.attempt:
    cli
    mov     rdx, [rel g_current]
    mov     rax, [rel g_con_owner]
    test    rax, rax
    jz      .take
    cmp     rax, rdx
    je      .held                       ; already ours

    mov     qword [rdx + T_WAITCON], 1
    mov     qword [rdx + T_STATE], TASK_BLOCKED
    int     VEC_SCHED                   ; comes back when the lock was let go
    jmp     .attempt
.take:
    mov     [rel g_con_owner], rdx
.held:
    sti
    pop     rdx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; con_release -- let it go, and make every waiter runnable again.
;
; Waking all of them rather than one is deliberate: they re-test the lock on
; the way through con_acquire, so a wake that turns out to be premature costs
; a trip round the loop and nothing else.
; ----------------------------------------------------------------------------
con_release:
    push    rax
    push    rcx
    pushfq
    cli
    mov     qword [rel g_con_owner], 0
    lea     rax, [rel tasks]
    mov     ecx, TASK_COUNT
.next:
    cmp     qword [rax + T_WAITCON], 0
    je      .advance
    mov     qword [rax + T_WAITCON], 0
    cmp     qword [rax + T_STATE], TASK_BLOCKED
    jne     .advance
    mov     qword [rax + T_STATE], TASK_READY
.advance:
    add     rax, T_SIZE
    dec     ecx
    jnz     .next
    popfq
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; con_release_if_owned -- RAX = a task that is about to stop existing.
;
; A task that dies holding the console would leave every other task blocked on
; it forever, which is the sort of thing that only shows up once.
; ----------------------------------------------------------------------------
con_release_if_owned:
    cmp     [rel g_con_owner], rax
    jne     .not_ours
    call    con_release
.not_ours:
    ret

; ----------------------------------------------------------------------------
align 8
g_current:  dq 0
g_ticks:    dq 0
g_con_owner: dq 0
g_tick_mark: dq 0
tasks:      times TASK_COUNT * T_SIZE db 0

; One kernel stack per task, plus a guard slot at the bottom that is simply
; never handed out: a task's stack is the region above its index.
align 16
tstacks:    times (TASK_COUNT + 1) * KSTACK_SIZE db 0

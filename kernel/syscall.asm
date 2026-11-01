; ============================================================================
; syscall.asm -- the door between the rings
;
; SYSCALL is deliberately cheap: no stack switch, no descriptor loads, no
; memory reads. The CPU puts the return address in RCX and the caller's flags
; in R11, masks the flags FMASK names, loads CS and SS from STAR, and jumps to
; LSTAR. Everything else is the kernel's problem -- starting with the fact
; that RSP still points into user memory on the first instruction here.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; syscall_init -- arm the four MSRs that make SYSCALL work
; ----------------------------------------------------------------------------
syscall_init:
    push    rax
    push    rcx
    push    rdx

    mov     ecx, MSR_EFER
    rdmsr
    or      eax, EFER_SCE
    wrmsr

    ; STAR[47:32] is what SYSCALL loads CS from, and SS from eight above it.
    ; STAR[63:48] is what SYSRET counts from. Both live in EDX.
    mov     ecx, MSR_STAR
    xor     eax, eax
    mov     edx, (USEL_CODE32 << 16) | KSEL_CODE
    wrmsr

    lea     rax, [rel syscall_entry]
    mov     rdx, rax
    shr     rdx, 32
    mov     ecx, MSR_LSTAR
    wrmsr

    mov     ecx, MSR_FMASK
    mov     eax, SYSCALL_FMASK
    xor     edx, edx
    wrmsr

    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; syscall_entry -- EAX selects, RDI/RSI/RDX carry, RAX returns.
;
; The dispatch is a chain of comparisons rather than a jump table on purpose:
; a table in this image would hold file offsets, not addresses, and a handful
; of calls does not justify relocating one at run time.
; ----------------------------------------------------------------------------
syscall_entry:
    ; RSP is still the user's. Saving it has to happen without pushing, which
    ; is why this is a RIP-relative store and not a stack operation -- and it
    ; goes into the task, not a global, because there is more than one task.
    ;
    ; FMASK clears IF, so nothing arrives between here and the stack being the
    ; kernel's. A timer tick in that window would push an interrupt frame onto
    ; a ring 3 stack while running in ring 0, which is exactly the hole the
    ; mask exists to close.
    ;
    ; It closes only that window. Once the stack is the kernel's, interrupts
    ; go back on and the rest of the call is preemptible like anything else;
    ; what keeps two writers apart is a lock, not a masked timer.
    mov     r10, [rel g_current]
    mov     [r10 + T_URSP], rsp
    mov     rsp, [r10 + T_KSTACK]
    push    rcx                                 ; the user's RIP
    push    r11                                 ; and flags
    sti

    cmp     eax, SYS_WRITE
    je      .write
    cmp     eax, SYS_EXIT
    je      .exit
    cmp     eax, SYS_TICKS
    je      .ticks
    cmp     eax, SYS_YIELD
    je      .yield
    cmp     eax, SYS_SLEEP
    je      .sleep
    cmp     eax, SYS_UPTIME
    je      .uptime
    cmp     eax, SYS_READ
    je      .read
    mov     rax, SYS_ENOSYS
    jmp     .return
.write:
    call    sys_write
    jmp     .return
.ticks:
    call    sys_ticks
    jmp     .return
.yield:
    call    sys_yield
    jmp     .return
.sleep:
    call    sys_sleep
    jmp     .return
.uptime:
    call    sys_uptime
    jmp     .return
.read:
    call    sys_read
    jmp     .return
.exit:
    call    sys_exit                            ; does not come back
.return:
    cli
    pop     r11
    pop     rcx
    mov     r10, [rel g_current]
    mov     rsp, [r10 + T_URSP]
    o64 sysret

; ----------------------------------------------------------------------------
; sys_write(RDI = buffer, RSI = length) -> bytes written
;
; The bounds check is the only one on this path, and it is here rather than in
; the loop below because the contract is checked once at the boundary and
; trusted after. A user pointer is the one thing the kernel cannot take on
; faith: the window is the whole of what ring 3 can name.
; ----------------------------------------------------------------------------
sys_write:
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    mov     rax, [rel g_current]
    mov     rax, [rax + T_USER_BASE]
    cmp     rdi, rax
    jb      .bad
    mov     rbx, rdi
    add     rbx, rsi
    jc      .bad                                ; length wrapped the address
    add     rax, USER_WINDOW_SIZE
    cmp     rbx, rax
    ja      .bad

    mov     rcx, rsi
    mov     rbx, rsi
    mov     rsi, rdi
    test    rcx, rcx
    jz      .done

    ; Held across the whole buffer, not per character: the point of the lock
    ; is that a line arrives whole, and the point of taking it here rather
    ; than masking interrupts is that everything else stays preemptible.
    call    con_acquire
.next:
    lodsb
    call    kc_putc
    dec     rcx
    jnz     .next
    call    con_release
.done:
    mov     rax, rbx
    jmp     .out
.bad:
    mov     rax, SYS_EBADPTR
.out:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; sys_read(RDI = buffer, RSI = length, RDX = timeout in ms) -> bytes read
;
; The first call in this kernel that waits for something the machine cannot
; produce on its own. Everything else a task can block on is the clock, one
; way or another, and the clock always arrives.
;
; The bounds check is the same one sys_write makes, and it is made here for a
; sharper reason: on that path a bad pointer would have printed somebody
; else's memory, and on this one the kernel is the writer, so it would have
; overwritten it.
; ----------------------------------------------------------------------------
sys_read:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r10

    mov     rax, [rel g_current]
    mov     rax, [rax + T_USER_BASE]
    cmp     rdi, rax
    jb      .bad
    mov     rbx, rdi
    add     rbx, rsi
    jc      .bad                                ; length wrapped the address
    add     rax, USER_WINDOW_SIZE
    cmp     rbx, rax
    ja      .bad

    test    rsi, rsi
    jz      .nothing                            ; asking for no bytes is not a
                                                ; way of asking to wait

    ; The deadline is computed once, from the call, and not renewed by whatever
    ; wakes the task -- otherwise a stream of keys nobody asked for could hold
    ; a bounded wait open indefinitely.
    xor     r10d, r10d
    test    rdx, rdx
    jz      .waiting
    mov     rax, rdx
    add     rax, MS_PER_TICK - 1
    xor     edx, edx
    mov     rcx, MS_PER_TICK
    div     rcx
    test    rax, rax
    jnz     .whole_ticks
    mov     eax, 1                              ; a timeout is never no wait
.whole_ticks:
    add     rax, [rel g_ticks]
    mov     r10, rax

.waiting:
    ; The test and the decision to block have to be one indivisible thing: a
    ; key that arrived between finding the buffer empty and recording that this
    ; task wants one would be a wake delivered to a task that was not yet
    ; waiting, and the wait that followed it would never end.
    cli
    call    kbd_dequeue
    test    rax, rax
    jnz     .have

    test    r10, r10
    jz      .block
    mov     rbx, [rel g_ticks]
    cmp     rbx, r10
    jae     .expired
.block:
    mov     rbx, [rel g_current]
    mov     qword [rbx + T_WAITKEY], 1
    mov     [rbx + T_WAKE], r10                 ; zero when there is no
                                                ; deadline, which is exactly
                                                ; what the tick's wake ignores
    mov     qword [rbx + T_STATE], TASK_BLOCKED
    int     VEC_SCHED                           ; comes back on a key, on the
                                                ; deadline, or not at all
    jmp     .waiting

.expired:
    xor     eax, eax
.have:
    sti
    jmp     .out
.bad:
    mov     rax, SYS_EBADPTR
    jmp     .out
.nothing:
    xor     eax, eax
.out:
    pop     r10
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; sys_ticks() -> the time stamp counter
; ----------------------------------------------------------------------------
sys_ticks:
    push    rdx
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; sys_yield() -- give the rest of the slice away. Returns 0.
; ----------------------------------------------------------------------------
sys_yield:
    int     VEC_SCHED
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; sys_sleep(RDI = milliseconds) -- block until that many have gone by.
; Returns 0. Rounded up to a whole tick, because a sleep that returns early
; is a bug and a sleep that returns late is a scheduler.
; ----------------------------------------------------------------------------
sys_sleep:
    push    rcx
    push    rdx
    push    r10

    mov     rax, rdi
    add     rax, MS_PER_TICK - 1
    xor     edx, edx
    mov     rcx, MS_PER_TICK
    div     rcx
    test    rax, rax
    jnz     .have_ticks
    mov     eax, 1                              ; never a no-op
.have_ticks:
    cli
    add     rax, [rel g_ticks]
    mov     r10, [rel g_current]
    mov     [r10 + T_WAKE], rax
    mov     qword [r10 + T_STATE], TASK_BLOCKED
    int     VEC_SCHED
    sti

    xor     eax, eax
    pop     r10
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; sys_uptime() -- timer ticks since boot
; ----------------------------------------------------------------------------
sys_uptime:
    mov     rax, [rel g_ticks]
    ret

; ----------------------------------------------------------------------------
; sys_exit(RDI = status). Never returns: the task is over, so the kernel stack
; it was called on is over with it, half-used frame and all.
; ----------------------------------------------------------------------------
sys_exit:
    cli
    mov     r10, [rel g_current]
    mov     [r10 + T_STATUS], rdi
    mov     qword [r10 + T_STATE], TASK_DEAD
    mov     rax, r10
    call    con_release_if_owned

    kputsi  "kernel   task "
    mov     rax, [rel g_current]
    mov     rax, [rax + T_ID]
    call    kc_putdec
    kputsi  " exited, status "
    mov     rax, [rel g_current]
    mov     rax, [rax + T_STATUS]
    call    kc_putdec
    mov     al, CHAR_LF
    call    kc_putc

    call    sched_next
    test    rax, rax
    jz      sched_park
    jmp     sched_run

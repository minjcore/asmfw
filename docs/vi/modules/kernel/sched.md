# sched.asm
[`kernel/sched.asm`](../../../../kernel/sched.asm) — 516 dòng, 16 entry point.

More than one thing at a time.

The switch is deliberately small. A task's registers live on its own kernel stack, so saving it is one store of RSP and restoring it is one load; the task structure holds no register file at all.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `lapic_init` | [24](../../../../kernel/sched.asm#L24) | virtual wire mode. Software-enable the local APIC, then tell it that whatever arrives on LINT0 is an external interrupt to be taken from the 8259 and that LINT1 is NMI. Until this runs the PIC is programmed correctly and connected to nothing. |
| `pic_init` | [42](../../../../kernel/sched.asm#L42) | move the hardware interrupts off the exception vectors and let only the timer through. The firmware leaves IRQ0 arriving as vector 8, which is #DF: indistinguishable from the CPU giving up. Only the timer, because at this point only the timer has a handler that does anything. kbd_init opens IRQ1 for itself once it has one, and nothing else is ever opened at all. |
| `io_wait` | [91](../../../../kernel/sched.asm#L91) | — |
| `pit_init` | [105](../../../../kernel/sched.asm#L105) | channel 0 as a rate generator, so IRQ0 arrives TICK_HZ times a second whether or not anybody is listening. |
| `timer_check` | [127](../../../../kernel/sched.asm#L127) | prove the tick arrives before anything depends on it. A scheduler whose timer never fires looks exactly like a scheduler that works and is simply never asked to switch, so this asks once, in ring 0, where the answer is unambiguous. |
| `task_create` | [161](../../../../kernel/sched.asm#L161) | RDI = id, RSI = its window, RDX = its PML4, RCX = the window belonging to the next task along. The program is already in the window: whoever called this read it off the disk. What is built here is the stack frame an interrupt return will consume to start it, with the three argument registers already in place, because a flat binary loaded at an address it was not assembled for has no other way of learning anything. |
| `sched_next` | [246](../../../../kernel/sched.asm#L246) | the task after the current one that is still willing to run. Returns RAX = a task, or 0 if there is nothing left. Round robin, and it can legitimately return the current task: being the only one left is not a reason to stop running. |
| `sched_run` | [287](../../../../kernel/sched.asm#L287) | RAX = the task to run. Never returns. CR3 changes before RSP does, which is safe only because every address space identity maps the kernel: the stack being switched away from and the stack being switched to are both present in both spaces. |
| `sched_park` | [315](../../../../kernel/sched.asm#L315) | nothing can run at this instant. That is not the same as nothing ever running again: a sleeping task is not a dead one. If anything is still alive the CPU waits for the interrupt that will wake it, and waits in the only honest way — halted, not spinning. That interrupt used to be the tick and nothing else, which made the wait a matter of arithmetic: something was going to become runnable at a tick that could be named in advance. A task waiting on the keyboard breaks that. The machine can now be genuinely idle with work outstanding, and stay idle for as long as nobody types. Entered from inside an interrupt handler, whose frame is abandoned. The idle loop has no state worth keeping, which is what makes that safe. |
| `sched_finished` | [329](../../../../kernel/sched.asm#L329) | — |
| `sched_any_alive` | [340](../../../../kernel/sched.asm#L340) | EAX = 1 if any task could still run, now or later |
| `sched_wake_due` | [370](../../../../kernel/sched.asm#L370) | promote every sleeper whose tick has arrived A task waiting for a keystroke with a deadline is blocked for two reasons at once, and this is one of the two things that can end that wait. So the keyboard reason is cleared here as well: the wait is over however it ended, and leaving the flag set would offer the task a wake it has stopped wanting. |
| `kbd_wake_waiters` | [405](../../../../kernel/sched.asm#L405) | a key has arrived, so nobody is still waiting for one. Called from the keyboard interrupt, and the mirror image of sched_wake_due: the same two reasons cleared, from the other side. Every waiter is woken rather than one, because the buffer holds bytes and not a turn — they re-test it in sys_read, and one that finds it emptied by somebody faster blocks again, which costs a trip round the loop and nothing else. |
| `con_acquire` | [437](../../../../kernel/sched.asm#L437) | — |
| `con_release` | [468](../../../../kernel/sched.asm#L468) | let it go, and make every waiter runnable again. Waking all of them rather than one is deliberate: they re-test the lock on the way through con_acquire, so a wake that turns out to be premature costs a trip round the loop and nothing else. |
| `con_release_if_owned` | [498](../../../../kernel/sched.asm#L498) | RAX = a task that is about to stop existing. A task that dies holding the console would leave every other task blocked on it forever, which is the sort of thing that only shows up once. |

## Định nghĩa

Dữ liệu và state: `g_current`, `g_ticks`, `g_con_owner`, `g_tick_mark`, `tasks`, `tstacks`

## Phụ thuộc

Gọi vào:

- [kcon.asm](kcon.md) — `kc_putdec`
- [kernel.asm](kernel.md) — `khalt`

Bị gọi bởi:

- [idt.asm](idt.md) — `con_release_if_owned`, `sched_next`, `sched_run`, `sched_wake_due`
- [kbd.asm](kbd.md) — `kbd_wake_waiters`
- [kernel.asm](kernel.md) — `lapic_init`, `pic_init`, `pit_init`, `sched_run`, `task_create`, `timer_check`
- [syscall.asm](syscall.md) — `con_acquire`, `con_release`, `con_release_if_owned`, `sched_next`, `sched_run`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

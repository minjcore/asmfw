# idt.asm
[`kernel/idt.asm`](../../../../kernel/idt.asm) — 271 dòng, 7 entry point.

Traps.

Every vector gets a stub, and the stubs are one fixed size each, so the address of vector N is isr_stubs + N * ISR_STUB_SIZE. That is not a micro-optimisation: this image is assembled at `org 0` and loaded wherever the firmware decides, so a table of `dq isr_n` would hold file offsets, not addresses.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `idt_init` | [32](../../../../kernel/idt.asm#L32) | point every gate at its stub and load the table |
| `isr_common` | [81](../../../../kernel/idt.asm#L81) | every vector arrives here. The register file goes down first and unconditionally, because the timer needs it saved and a fault wants it reported, and because a task resumed later must find it exactly where the switch left it. RBP addresses the frame rather than RSP, so the console calls below cannot move it out from under the reads. |
| `isr_timer` | [141](../../../../kernel/idt.asm#L141) | the tick. Acknowledge it, put the current task down, pick the next one up. The end of interrupt goes out before the switch rather than after, because after it there is no "after": sched_run leaves through iretq on somebody else's stack and this code is not returned to. |
| `isr_resched` | [176](../../../../kernel/idt.asm#L176) | the kernel asking itself for a context switch. No end of interrupt: nothing in hardware raised this. The caller is inside a system call, and this is what turns its half-finished stack frame into something the switch knows how to resume. |
| `task_faulted` | [191](../../../../kernel/idt.asm#L191) | a trap that came from ring 3. The task is over; the machine is not. This is the difference the whole arrangement exists to produce. |
| `trap_put_name` | [211](../../../../kernel/idt.asm#L211) | RAX = vector. Names are fixed width so that the lookup is an index rather than a pointer, for the same `org 0` reason as the stubs. |
| `isr_stubs` | [250](../../../../kernel/idt.asm#L250) | — |

## Định nghĩa

Macro: `ISR_STUB`

Hằng số: 9.

Dữ liệu và state: `trap_names`, `idt_ptr`, `idt`

## Phụ thuộc

Gọi vào:

- [kcon.asm](kcon.md) — `kc_putc`, `kc_putdec`, `kc_puthex16`, `kc_puthex64`
- [sched.asm](sched.md) — `con_release_if_owned`, `sched_next`, `sched_run`, `sched_wake_due`

Bị gọi bởi:

- [kernel.asm](kernel.md) — `idt_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

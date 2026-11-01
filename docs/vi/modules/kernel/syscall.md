# syscall.asm
[`kernel/syscall.asm`](../../../../kernel/syscall.asm) — 356 dòng, 9 entry point.

The door between the rings.

SYSCALL is deliberately cheap: no stack switch, no descriptor loads, no memory reads. The CPU puts the return address in RCX and the caller's flags in R11, masks the flags FMASK names, loads CS and SS from STAR, and jumps to LSTAR.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `syscall_init` | [16](../../../../kernel/syscall.asm#L16) | arm the four MSRs that make SYSCALL work |
| `syscall_entry` | [56](../../../../kernel/syscall.asm#L56) | EAX selects, RDI/RSI/RDX carry, RAX returns. The dispatch is a chain of comparisons rather than a jump table on purpose: a table in this image would hold file offsets, not addresses, and a handful of calls does not justify relocating one at run time. |
| `sys_write` | [128](../../../../kernel/syscall.asm#L128) | — |
| `sys_read` | [185](../../../../kernel/syscall.asm#L185) | — |
| `sys_ticks` | [274](../../../../kernel/syscall.asm#L274) | — |
| `sys_yield` | [285](../../../../kernel/syscall.asm#L285) | — |
| `sys_sleep` | [295](../../../../kernel/syscall.asm#L295) | — |
| `sys_uptime` | [326](../../../../kernel/syscall.asm#L326) | — |
| `sys_exit` | [334](../../../../kernel/syscall.asm#L334) | — |

## Phụ thuộc

Gọi vào:

- [kbd.asm](kbd.md) — `kbd_dequeue`
- [kcon.asm](kcon.md) — `kc_putc`, `kc_putdec`
- [sched.asm](sched.md) — `con_acquire`, `con_release`, `con_release_if_owned`, `sched_next`, `sched_run`

Bị gọi bởi:

- [kernel.asm](kernel.md) — `syscall_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

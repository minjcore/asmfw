# gdt.asm
[`kernel/gdt.asm`](../../../../kernel/gdt.asm) — 97 dòng, 2 entry point.

Descriptors, and the task state segment behind them.

Two things here are not optional. The descriptor order is fixed by SYSRET's selector arithmetic, which kconst.inc spells out. And the TSS is what makes a fault in ring 3 survivable: without RSP0 the CPU has no stack to push the exception frame onto, and a #GP becomes a #DF becomes a reset.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `gdt_init` | [16](../../../../kernel/gdt.asm#L16) | fill in the TSS descriptor, load the table, and reload every selector so the CPU is running on the kernel's own descriptors. |
| `gdt_end` | [88](../../../../kernel/gdt.asm#L88) | — |

## Định nghĩa

Dữ liệu và state: `gdt`, `gdt_tss`, `gdt_ptr`, `tss`

## Phụ thuộc

Bị gọi bởi:

- [kernel.asm](kernel.md) — `gdt_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

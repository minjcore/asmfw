# count.asm
[`kernel/progs/count.asm`](../../../../../kernel/progs/count.asm) — 101 dòng, 1 entry point.

A program: print a line, burn time, repeat.

The counter it prints is its own. The time stamp beside it comes from the kernel, and the gaps between consecutive values are the other tasks running while this one was not. It ends by executing an instruction ring 3 does not have, to show that a task can be removed without the machine noticing. nasm -f bin -I ../ -I .

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `_start` | [25](../../../../../kernel/progs/count.asm#L25) | — |

## Định nghĩa

Hằng số: 4.

Dữ liệu và state: `u_hello`, `u_line`, `u_nvalue`, `u_upvalue`, `u_trap`, `u_escaped`, `u_id`, `u_window`, `u_sibling`

## Phụ thuộc

Gọi vào:

- [ulib.inc](ulib.md) — `u_dec`, `u_exit`, `u_write`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

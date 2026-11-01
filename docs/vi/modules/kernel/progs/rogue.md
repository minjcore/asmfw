# rogue.asm
[`kernel/progs/rogue.asm`](../../../../../kernel/progs/rogue.asm) — 94 dòng, 1 entry point.

A program that goes looking for memory that is not its own.

It is told its neighbour's window address at entry, so this is not a guessing game: the window really is there, and in the kernel's address space it is readable. In this task's address space that 2 MiB page carries no user mapping, so the read faults and the task is gone. Separate page tables are the whole of the difference.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `_start` | [23](../../../../../kernel/progs/rogue.asm#L23) | — |

## Định nghĩa

Hằng số: 3.

Dữ liệu và state: `u_hello`, `u_guard_ok`, `u_guard_bad`, `u_reach`, `u_addrvalue`, `u_escaped`, `u_id`, `u_window`, `u_sibling`

## Phụ thuộc

Gọi vào:

- [ulib.inc](ulib.md) — `u_exit`, `u_hex`, `u_write`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# type.asm
[`kernel/progs/type.asm`](../../../../../kernel/progs/type.asm) — 163 dòng, 1 entry point.

A program that waits for something the machine cannot produce.

The other three tasks are driven by the clock, one way or another: the maze never yields and is taken away, the counter sleeps against the tick, the rogue faults immediately. All three would run identically on a machine with nobody at it. This one blocks on a device.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `_start` | [40](../../../../../kernel/progs/type.asm#L40) | — |

## Định nghĩa

Hằng số: 11.

Dữ liệu và state: `u_hello`, `u_kline`, `u_kchar`, `u_kcode`, `u_kwhen`, `u_done`, `u_full`, `u_quiet`, `u_id`, `u_window`, `u_sibling`, `u_keys`

## Phụ thuộc

Gọi vào:

- [ulib.inc](ulib.md) — `u_dec`, `u_exit`, `u_hex`, `u_read`, `u_write`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

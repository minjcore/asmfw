# init16.asm
[`src/init16.asm`](../../../../src/init16.asm) — 66 dòng, 2 entry point.

SEC phase, part 1.

Everything here must sit in the last 64 KiB of the flash volume, because at reset the only thing addressable is CS.base = 0xFFFF0000 with a 64 KiB limit. The job is deliberately tiny: turn on A20, load a flat GDT, switch to 32-bit protected mode, and get out of real mode forever.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `sec_entry16` | [12](../../../../src/init16.asm#L12) | — |
| `gdt32_end` | [62](../../../../src/init16.asm#L62) | — |

## Định nghĩa

Dữ liệu và state: `gdt32`, `gdt32_ptr`

## Phụ thuộc

Bị gọi bởi:

- [fw.asm](fw.md) — `sec_entry16`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

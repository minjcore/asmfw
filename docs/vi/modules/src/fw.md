# fw.asm
[`src/fw.asm`](../../../../src/fw.asm) — 71 dòng, 1 entry point.

The flash volume.

One flat binary, assembled at its final address. The layout is fixed by the architecture at both ends: 0xFFF00000  start of the volume        <- 32/64-bit firmware body 0xFFFF0000  last 64 KiB                <- everything real mode can reach 0xFFFFFFF0  reset vector               <- 16 bytes, where the CPU starts Build with:  na.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `reset_vector` | [69](../../../../src/fw.asm#L69) | — |

## Phụ thuộc

Gọi vào:

- [init16.asm](init16.md) — `sec_entry16`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

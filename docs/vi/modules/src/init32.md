# init32.asm
[`src/init32.asm`](../../../../src/init32.asm) — 74 dòng, 1 entry point.

SEC phase, part 2.

Build a flat identity map of the low 4 GiB out of 2 MiB pages, then enter long mode. 2 MiB pages rather than 1 GiB so this does not depend on CPUID.80000001:EDX.PDPE1GB, which plain -cpu qemu64 does not advertise.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `sec_entry32` | [11](../../../../src/init32.asm#L11) | — |

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# efi_rt.asm
[`src/efi_rt.asm`](../../../../src/efi_rt.asm) — 194 dòng, 4 entry point.

Runtime services.

These are the services that outlive ExitBootServices. This firmware keeps them honest but small: a real clock, a reset that actually resets, and the variable services, which live in efi_var.asm. SetVirtualAddressMap is not supported, so the table stays valid only at its physical address.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `rt_unsupported` | [16](../../../../src/efi_rt.asm#L16) | — |
| `rt_get_time` | [37](../../../../src/efi_rt.asm#L37) | — |
| `rtc_decode` | [139](../../../../src/efi_rt.asm#L139) | EDI = raw CMOS byte, ESI = status register B. Returns AL as a binary value, converting from BCD when bit 2 says to. |
| `rt_reset_system` | [160](../../../../src/efi_rt.asm#L160) | — |

## Định nghĩa

Hằng số: 12.

## Phụ thuộc

Gọi vào:

- [init64.asm](init64.md) — `cmos_read`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

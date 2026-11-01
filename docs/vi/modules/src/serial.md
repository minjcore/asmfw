# serial.asm
[`src/serial.asm`](../../../../src/serial.asm) — 59 dòng, 2 entry point.

16550 UART on COM1, the firmware's debug spine.

Serial comes up before anything else so that a failure in PCI enumeration or mode setting still has somewhere to complain to.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `ser_init` | [13](../../../../src/serial.asm#L13) | 115200 8N1, FIFOs on, interrupts off |
| `ser_putc` | [45](../../../../src/serial.asm#L45) | write AL, blocking until the transmit holding register is free |

## Phụ thuộc

Bị gọi bởi:

- [efi_proto.asm](efi_proto.md) — `ser_putc`
- [init64.asm](init64.md) — `ser_init`
- [util.asm](util.md) — `ser_putc`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

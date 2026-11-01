# timer.asm
[`src/timer.asm`](../../../../src/timer.asm) — 109 dòng, 2 entry point.

Delays, measured against the 8254.

The PIT is the one clock on a PC that runs at a known rate without being configured first: 1.193182 MHz, derived from the ancient NTSC colourburst divisor. Channel 2 is used because it is the only one whose output can be polled directly, through bit 5 of port 0x61, without an interrupt.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `stall_us` | [22](../../../../src/timer.asm#L22) | busy-wait RCX microseconds |
| `pit_wait_ticks` | [65](../../../../src/timer.asm#L65) | BX = tick count (1..65535), wait for channel 2 to run out |

## Định nghĩa

Hằng số: 5.

## Phụ thuộc

Bị gọi bởi:

- [efi_bs.asm](efi_bs.md) — `stall_us`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# kata.asm
[`kernel/kata.asm`](../../../../kernel/kata.asm) — 261 dòng, 6 entry point.

ATA PIO, because the firmware's block driver went away.

Polled, one sector at a time, primary master only. ATA interrupts are turned off rather than handled: this runs once at boot with the PIC carrying only the timer, and a driver that waits on a status bit needs no vector.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kata_init` | [42](../../../../kernel/kata.asm#L42) | does anything answer on the primary master? Returns EAX = 1, with the sector count in g_ata_sectors. |
| `kata_read` | [104](../../../../kernel/kata.asm#L104) | RAX = first LBA, RDI = destination, ECX = sector count. Returns EAX = 1 on success. |
| `kata_read_one` | [136](../../../../kernel/kata.asm#L136) | RAX = LBA, RDI = destination. Returns EAX = 1. |
| `kata_wait_idle` | [195](../../../../kernel/kata.asm#L195) | spin until BSY clears. Returns EAX = 1 if it did. |
| `kata_wait_drq` | [219](../../../../kernel/kata.asm#L219) | spin until the drive has data, or admits it will not. Returns EAX = 1 if there is a sector waiting. |
| `kata_settle` | [248](../../../../kernel/kata.asm#L248) | four status reads, the conventional 400 ns after a select |

## Định nghĩa

Hằng số: 22.

## Phụ thuộc

Bị gọi bởi:

- [kernel.asm](kernel.md) — `kata_init`
- [kfat.asm](kfat.md) — `kata_read`
- [kgpt.asm](kgpt.md) — `kata_read`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

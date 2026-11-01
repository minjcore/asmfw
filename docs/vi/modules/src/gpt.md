# gpt.asm
[`src/gpt.asm`](../../../../src/gpt.asm) — 168 dòng, 1 entry point.

Find the EFI system partition.

GPT is tried first, because that is what a UEFI machine is supposed to have. A plain MBR with a type 0xEF partition is accepted as a fallback, which is what most hand-made USB sticks turn out to be.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `part_find_esp` | [34](../../../../src/gpt.asm#L34) | locate the EFI system partition on the primary master. On success sets g_esp_lba / g_esp_sectors and returns EAX = 1. |

## Định nghĩa

Hằng số: 14.

Dữ liệu và state: `esp_type_guid`

## Phụ thuộc

Gọi vào:

- [ata.asm](ata.md) — `ata_read`
- [util.asm](util.md) — `mem_cmp`

Bị gọi bởi:

- [init64.asm](init64.md) — `part_find_esp`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

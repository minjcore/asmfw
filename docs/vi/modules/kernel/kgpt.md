# kgpt.asm
[`kernel/kgpt.asm`](../../../../kernel/kgpt.asm) — 118 dòng, 1 entry point.

Find the EFI system partition.

Only GPT, and only the type GUID. The firmware also accepts an MBR with a type 0xEF partition; this kernel boots one disk, and that disk is a GPT one.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kgpt_find_esp` | [25](../../../../kernel/kgpt.asm#L25) | Returns EAX = 1 with g_esp_lba and g_esp_sectors set. |

## Định nghĩa

Hằng số: 9.

Dữ liệu và state: `gpt_signature`, `guid_esp_type`, `g_esp_lba`, `g_esp_sectors`, `g_ata_sectors`

## Phụ thuộc

Gọi vào:

- [kata.asm](kata.md) — `kata_read`

Bị gọi bởi:

- [kernel.asm](kernel.md) — `kgpt_find_esp`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

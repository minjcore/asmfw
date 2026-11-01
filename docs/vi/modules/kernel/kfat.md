# kfat.asm
[`kernel/kfat.asm`](../../../../kernel/kfat.asm) — 310 dòng, 5 entry point.

Reading FAT32, again.

The firmware has a reader and the kernel cannot call it, which is the whole point of the exercise: after ExitBootServices the only code that runs is code in this image. Read only, short names only, one cluster in flight at a time.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kfat_mount` | [45](../../../../kernel/kfat.asm#L45) | read the BPB at the start of the ESP. Returns EAX = 1. |
| `kfat_cluster_lba` | [103](../../../../kernel/kfat.asm#L103) | EAX = cluster. Returns RAX = its first sector. |
| `kfat_next` | [119](../../../../kernel/kfat.asm#L119) | EAX = cluster. Returns EAX = the next one, or >= FAT_EOC. One FAT sector is kept, because a chain walked forward asks for the same sector many times running. |
| `kfat_lookup` | [163](../../../../kernel/kfat.asm#L163) | EAX = the directory's first cluster, RSI = an eleven byte 8.3 name, space padded. Returns EAX = the entry's first cluster, RDX = its size, CL = its attribute. EAX = 0 if there is no such name. |
| `kfat_read_file` | [245](../../../../kernel/kfat.asm#L245) | EAX = first cluster, RDX = size in bytes, RDI = where. Returns EAX = 1. Reads whole clusters, so the destination must have room for the size rounded up to one. |

## Định nghĩa

Hằng số: 23.

Dữ liệu và state: `kbuf_sector`, `kbuf_fat`, `kbuf_gpt`, `kbuf_cluster`, `g_fat_fat_lba`, `g_fat_data_lba`, `g_fat_cached`, `g_fat_spc`, `g_fat_root`

## Phụ thuộc

Gọi vào:

- [kata.asm](kata.md) — `kata_read`

Bị gọi bởi:

- [kernel.asm](kernel.md) — `kfat_lookup`, `kfat_mount`, `kfat_read_file`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

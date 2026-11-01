# fat.asm
[`src/fat.asm`](../../../../src/fat.asm) — 456 dòng, 8 entry point.

Enough FAT32 to find and read one file.

Read-only, short names only. Long-name entries are skipped rather than decoded: every path this firmware needs — \EFI\BOOT\BOOTX64.EFI — fits 8.3 exactly, and a boot loader has no business writing to the volume.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `fat_mount` | [35](../../../../src/fat.asm#L35) | read the BPB of the partition at g_esp_lba and work out where the FAT, the data area and the root directory live. Returns EAX = 1 on a volume this driver can read. |
| `fat_clus_lba` | [106](../../../../src/fat.asm#L106) | EAX = cluster number, returns RAX = its first LBA |
| `fat_next_clus` | [122](../../../../src/fat.asm#L122) | EAX = cluster, returns EAX = the next one in the chain. One FAT sector is cached, which is all the locality a sequential file read needs: 128 consecutive clusters share a sector. |
| `fat_lookup` | [166](../../../../src/fat.asm#L166) | find an 8.3 name in a directory. EAX = first cluster of the directory RSI = pointer to the 11-byte padded name, e.g. "BOOTX64 EFI" Returns EAX = the entry's first cluster (0 if not found), EDX = its size in bytes, CL = its attribute byte. |
| `fat_read_file` | [258](../../../../src/fat.asm#L258) | walk a cluster chain into memory. EAX = first cluster RDX = number of bytes to read RDI = destination Returns EAX = 0 on success. Reads whole clusters, so the destination must have room for the file rounded up to the cluster size. |
| `fat_read_cluster` | [321](../../../../src/fat.asm#L321) | EAX = cluster, RDI = destination. EAX = 0 on success. |
| `fat_seek` | [337](../../../../src/fat.asm#L337) | EAX = first cluster, RDX = byte offset into the file. Returns EAX = the cluster covering that offset and EDX = the offset within it, or EAX = 0 if the chain ends first. Walking from the start on every seek is O(n) in the offset; a sequential reader pays it once per cluster, which is the only access pattern here. |
| `fat_dir_nth` | [388](../../../../src/fat.asm#L388) | EAX = directory cluster, EDX = ordinal of the wanted entry. Returns RAX = a pointer to the 32-byte directory entry inside BUF_DIR, or 0 when the directory has fewer entries than that. The pointer is only valid until the next call, which is all any caller here needs. Long-name fragments and deleted slots are skipped; "." and ".." are not, because a FAT directory really does contain them and callers expect to see them listed. |

## Định nghĩa

Hằng số: 15.

## Phụ thuộc

Gọi vào:

- [ata.asm](ata.md) — `ata_read`
- [util.asm](util.md) — `mem_cmp`

Bị gọi bởi:

- [efi_file.asm](efi_file.md) — `fat_dir_nth`, `fat_lookup`, `fat_read_cluster`, `fat_seek`
- [init64.asm](init64.md) — `fat_lookup`, `fat_mount`, `fat_read_file`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

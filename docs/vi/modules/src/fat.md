# fat.asm
[`src/fat.asm`](../../../../src/fat.asm) — 691 dòng, 15 entry point.

Enough FAT32 to find and read one file.

Read-only. Long names are decoded, so a volume someone else made — with a \vmlinuz-linux on it, say — can be opened by the names it shows.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `fat_mount` | [50](../../../../src/fat.asm#L50) | read the BPB of the partition at g_esp_lba and work out where the FAT, the data area and the root directory live. Returns EAX = 1 on a volume this driver can read. |
| `fat_clus_lba` | [121](../../../../src/fat.asm#L121) | EAX = cluster number, returns RAX = its first LBA |
| `fat_next_clus` | [137](../../../../src/fat.asm#L137) | EAX = cluster, returns EAX = the next one in the chain. One FAT sector is cached, which is all the locality a sequential file read needs: 128 consecutive clusters share a sector. |
| `fat_lookup_long` | [182](../../../../src/fat.asm#L182) | find a path component by its long name or its short one. EAX = first cluster of the directory RSI = the 11-byte short form of the component, as name_to_83 made it RDI = the component itself, CHAR16, ECX = its length in characters Returns as fat_lookup. The long name is compared without regard to case, as FAT has always done. |
| `fat_lookup` | [198](../../../../src/fat.asm#L198) | find an 8.3 name in a directory. EAX = first cluster of the directory RSI = pointer to the 11-byte padded name, e.g. "BOOTX64 EFI" Returns EAX = the entry's first cluster (0 if not found), EDX = its size in bytes, CL = its attribute byte. |
| `lfn_reset` | [303](../../../../src/fat.asm#L303) | forget any long name being gathered. |
| `lfn_feed` | [313](../../../../src/fat.asm#L313) | RBX = a long-name fragment. Adds its 13 characters to BUF_LFN at the place its sequence number says, or abandons the name if the run is broken. Fragments arrive last first, so the first one seen fixes the length. |
| `lfn_owns` | [373](../../../../src/fat.asm#L373) | RBX = a short entry. ZF set if a complete long name was gathered just before it and its checksum is this short name's. |
| `lfn_equals` | [406](../../../../src/fat.asm#L406) | ZF set if BUF_LFN is the component at g_want_long, of g_want_len characters, ignoring the case of ASCII letters. |
| `lfn_upcase_pair` | [438](../../../../src/fat.asm#L438) | EAX and EDX = CHAR16 each, both folded to upper case. |
| `lfn_length` | [456](../../../../src/fat.asm#L456) | RAX = how many characters BUF_LFN holds before its NUL. |
| `fat_read_file` | [477](../../../../src/fat.asm#L477) | walk a cluster chain into memory. EAX = first cluster RDX = number of bytes to read RDI = destination Returns EAX = 0 on success. Reads whole clusters, so the destination must have room for the file rounded up to the cluster size. |
| `fat_read_cluster` | [540](../../../../src/fat.asm#L540) | EAX = cluster, RDI = destination. EAX = 0 on success. |
| `fat_seek` | [556](../../../../src/fat.asm#L556) | EAX = first cluster, RDX = byte offset into the file. Returns EAX = the cluster covering that offset and EDX = the offset within it, or EAX = 0 if the chain ends first. Walking from the start on every seek is O(n) in the offset; a sequential reader pays it once per cluster, which is the only access pattern here. |
| `fat_dir_nth` | [609](../../../../src/fat.asm#L609) | EAX = directory cluster, EDX = ordinal of the wanted entry. Returns RAX = a pointer to the 32-byte directory entry inside BUF_DIR, or 0 when the directory has fewer entries than that. The pointer is only valid until the next call, which is all any caller here needs. Long-name fragments are gathered rather than counted: g_lfn_hit says whether the entry returned has a long name, which is then in BUF_LFN. Deleted slots are skipped; "." and ".." are not, because a FAT directory really does contain them and callers expect to see them listed. |

## Định nghĩa

Hằng số: 24.

## Phụ thuộc

Gọi vào:

- [ata.asm](ata.md) — `ata_read`
- [util.asm](util.md) — `mem_cmp`

Bị gọi bởi:

- [efi_file.asm](efi_file.md) — `fat_dir_nth`, `fat_lookup_long`, `fat_read_cluster`, `fat_seek`, `lfn_length`
- [init64.asm](init64.md) — `fat_lookup`, `fat_mount`, `fat_read_file`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

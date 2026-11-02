# efi_file.asm
[`src/efi_file.asm`](../../../../src/efi_file.asm) — 955 dòng, 19 entry point.

Simple File System and File protocols over the FAT32 reader.

Read-only. Every call that would change the volume returns EFI_WRITE_PROTECTED rather than pretending to succeed, because a loader that believes it wrote something and then reads it back is worse off than one told plainly that it cannot.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `sfs_open_volume` | [20](../../../../src/efi_file.asm#L20) | — |
| `file_new` | [55](../../../../src/efi_file.asm#L55) | EAX = first cluster, RDX = size, CL = FAT attributes, RSI = the 11-byte 8.3 name. Returns RAX = the new object, or 0. |
| `file_open` | [115](../../../../src/efi_file.asm#L115) | — |
| `file_close` | [271](../../../../src/efi_file.asm#L271) | — |
| `file_delete` | [275](../../../../src/efi_file.asm#L275) | — |
| `file_write` | [279](../../../../src/efi_file.asm#L279) | — |
| `file_set_info` | [283](../../../../src/efi_file.asm#L283) | — |
| `file_flush` | [287](../../../../src/efi_file.asm#L287) | — |
| `file_get_position` | [297](../../../../src/efi_file.asm#L297) | — |
| `file_set_position` | [313](../../../../src/efi_file.asm#L313) | — |
| `file_read` | [339](../../../../src/efi_file.asm#L339) | — |
| `file_get_info` | [521](../../../../src/efi_file.asm#L521) | — |
| `name_to_83` | [615](../../../../src/efi_file.asm#L615) | RSI = a CHAR16 path component, ECX = its length in characters, RDI = an 11-byte output buffer. Folded to upper case and split at the last dot, which is how FAT has always stored a short name. "." and ".." are passed through as themselves, because that is literally how they appear on disk. |
| `upcase` | [730](../../../../src/efi_file.asm#L730) | EAX = a character, returns AL folded to upper case. Non-ASCII becomes '_': FAT short names have no way to spell it. |
| `name_from_83` | [749](../../../../src/efi_file.asm#L749) | RSI = an 11-byte 8.3 name, RDI = a CHAR16 buffer. Writes "STEM.EXT" with the padding removed and a NUL, and returns ECX = the number of characters written, not counting the NUL. |
| `bio_reset` | [830](../../../../src/efi_file.asm#L830) | — |
| `bio_read_blocks` | [837](../../../../src/efi_file.asm#L837) | — |
| `bio_write_blocks` | [895](../../../../src/efi_file.asm#L895) | — |
| `bio_flush_blocks` | [899](../../../../src/efi_file.asm#L899) | — |

## Định nghĩa

Dữ liệu và state: `file_template`, `sfs_template`, `bio_template`, `guid_simple_fs`, `guid_block_io`, `guid_file_info`, `name_root`

## Phụ thuộc

Gọi vào:

- [ata.asm](ata.md) — `ata_read`
- [fat.asm](fat.md) — `fat_dir_nth`, `fat_lookup_long`, `fat_read_cluster`, `fat_seek`, `lfn_length`
- [mem.asm](mem.md) — `mem_alloc_pool`
- [util.asm](util.md) — `mem_cmp`, `mem_copy`, `mem_set`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

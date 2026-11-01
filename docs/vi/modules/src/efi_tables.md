# efi_tables.asm
[`src/efi_tables.asm`](../../../../src/efi_tables.asm) — 539 dòng, 8 entry point.

Build the structures an EFI image is handed.

The tables are laid out as templates in the flash volume and copied into RAM at DXE time.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `efi_init` | [16](../../../../src/efi_tables.asm#L16) | populate the RAM structures and register the protocols |
| `efi_publish_volume` | [176](../../../../src/efi_tables.asm#L176) | register Simple File System on the disk handle. Separate from efi_init because it can only happen once the volume has been mounted, and mounting is a BDS decision: which partition to look at is a boot policy question, not a device one. |
| `efi_fix_crc` | [202](../../../../src/efi_tables.asm#L202) | RDI = a table with an EFI_TABLE_HEADER. The CRC is taken over HeaderSize bytes with the CRC field itself zeroed. |
| `crc32` | [222](../../../../src/efi_tables.asm#L222) | RSI = data, ECX = length, returns EAX. The reflected CRC-32 the UEFI spec calls for. Computed a bit at a time: a 1 KiB lookup table would be faster and this runs a few hundred bytes, once. |
| `proto_add` | [259](../../../../src/efi_tables.asm#L259) | RAX = handle, RSI = GUID, RDI = interface pointer |
| `proto_find` | [282](../../../../src/efi_tables.asm#L282) | RSI = GUID, RAX = handle to match, or 0 for "any handle". Returns RAX = interface pointer, or 0. |
| `vendor_string_end` | [487](../../../../src/efi_tables.asm#L487) | — |
| `rt_shadow` | [505](../../../../src/efi_tables.asm#L505) | copy the flash volume into runtime services code, and point the runtime services table at the copy. The runtime services have to keep working after ExitBootServices, from wherever the OS can execute them. An OS maps EfiRuntimeServicesCode executable and maps memory-mapped I/O — which is what the flash is — as data only; Linux calls SetVirtualAddressMap through this table before anything else, so a pointer into the flash is an instruction fetch from a no-execute page, and the kernel dies there. The whole volume is copied, at the same layout, so every relative call and RIP-relative reference inside it still lands where it should. The runtime functions use nothing else: their state is in RAM globals, at absolute addresses that do not move. |

## Định nghĩa

Dữ liệu và state: `st_template`, `bs_template`, `rt_template`, `conout_template`, `conin_template`, `gop_template`, `guid_text_output`, `guid_text_input`, `guid_gop`, `guid_loaded_image`, `vendor_string`

## Phụ thuộc

Gọi vào:

- [mem.asm](mem.md) — `mem_alloc_pages`
- [util.asm](util.md) — `mem_cmp`, `mem_copy`

Bị gọi bởi:

- [efi_bs.asm](efi_bs.md) — `crc32`, `efi_fix_crc`, `proto_find`
- [efi_image.asm](efi_image.md) — `proto_add`
- [efi_rt.asm](efi_rt.md) — `efi_fix_crc`
- [init64.asm](init64.md) — `efi_init`, `efi_publish_volume`, `proto_add`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# efi_bs.asm
[`src/efi_bs.asm`](../../../../src/efi_bs.asm) — 882 dòng, 29 entry point.

Boot services.

What is implemented is what a boot loader actually calls. The rest return EFI_UNSUPPORTED through bs_unsupported rather than being left as null pointers, so a caller that tries one gets a status code instead of a fault.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `bs_unsupported` | [20](../../../../src/efi_bs.asm#L20) | — |
| `bs_raise_tpl` | [31](../../../../src/efi_bs.asm#L31) | — |
| `bs_restore_tpl` | [36](../../../../src/efi_bs.asm#L36) | — |
| `bs_allocate_pages` | [43](../../../../src/efi_bs.asm#L43) | — |
| `bs_free_pages` | [150](../../../../src/efi_bs.asm#L150) | — |
| `bs_free_pool` | [154](../../../../src/efi_bs.asm#L154) | — |
| `bs_allocate_pool` | [161](../../../../src/efi_bs.asm#L161) | — |
| `bs_get_memory_map` | [190](../../../../src/efi_bs.asm#L190) | — |
| `bs_handle_protocol` | [247](../../../../src/efi_bs.asm#L247) | — |
| `bs_locate_protocol` | [280](../../../../src/efi_bs.asm#L280) | — |
| `bs_open_protocol` | [318](../../../../src/efi_bs.asm#L318) | — |
| `bs_close_protocol` | [352](../../../../src/efi_bs.asm#L352) | — |
| `proto_collect` | [361](../../../../src/efi_bs.asm#L361) | RSI = GUID to match, or 0 for every handle. RDI = where to write the handles, or 0 to only count them. Returns EAX = the number of distinct handles. |
| `bs_locate_handle` | [432](../../../../src/efi_bs.asm#L432) | — |
| `bs_locate_handle_buffer` | [495](../../../../src/efi_bs.asm#L495) | — |
| `bs_install_configuration_table` | [570](../../../../src/efi_bs.asm#L570) | — |
| `bs_exit_boot_services` | [660](../../../../src/efi_bs.asm#L660) | — |
| `bs_exit` | [679](../../../../src/efi_bs.asm#L679) | — |
| `bs_get_next_monotonic_count` | [706](../../../../src/efi_bs.asm#L706) | — |
| `bs_stall` | [722](../../../../src/efi_bs.asm#L722) | — |
| `bs_set_watchdog_timer` | [731](../../../../src/efi_bs.asm#L731) | — |
| `bs_connect_controller` | [738](../../../../src/efi_bs.asm#L738) | — |
| `bs_wait_for_event` | [748](../../../../src/efi_bs.asm#L748) | — |
| `bs_check_event` | [788](../../../../src/efi_bs.asm#L788) | — |
| `bs_close_event` | [803](../../../../src/efi_bs.asm#L803) | — |
| `kbd_peek` | [810](../../../../src/efi_bs.asm#L810) | EAX non-zero if the keyboard controller has a byte waiting |
| `bs_calculate_crc32` | [821](../../../../src/efi_bs.asm#L821) | — |
| `bs_copy_mem` | [848](../../../../src/efi_bs.asm#L848) | — |
| `bs_set_mem` | [875](../../../../src/efi_bs.asm#L875) | — |

## Định nghĩa

Hằng số: 2.

## Phụ thuộc

Gọi vào:

- [efi_image.asm](efi_image.md) — `image_record`
- [efi_tables.asm](efi_tables.md) — `crc32`, `efi_fix_crc`, `proto_find`
- [init64.asm](init64.md) — `image_exit_resume`
- [mem.asm](mem.md) — `mem_alloc_pages`, `mem_alloc_pool`, `mem_build_map`
- [timer.asm](timer.md) — `stall_us`
- [util.asm](util.md) — `mem_cmp`, `mem_copy`

Bị gọi bởi:

- [acpi.asm](acpi.md) — `bs_install_configuration_table`
- [smbios.asm](smbios.md) — `bs_install_configuration_table`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

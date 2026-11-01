# efi_bs.asm
[`src/efi_bs.asm`](../../../../src/efi_bs.asm) — 863 dòng, 29 entry point.

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
| `bs_get_next_monotonic_count` | [687](../../../../src/efi_bs.asm#L687) | — |
| `bs_stall` | [703](../../../../src/efi_bs.asm#L703) | — |
| `bs_set_watchdog_timer` | [712](../../../../src/efi_bs.asm#L712) | — |
| `bs_connect_controller` | [719](../../../../src/efi_bs.asm#L719) | — |
| `bs_wait_for_event` | [729](../../../../src/efi_bs.asm#L729) | — |
| `bs_check_event` | [769](../../../../src/efi_bs.asm#L769) | — |
| `bs_close_event` | [784](../../../../src/efi_bs.asm#L784) | — |
| `kbd_peek` | [791](../../../../src/efi_bs.asm#L791) | EAX non-zero if the keyboard controller has a byte waiting |
| `bs_calculate_crc32` | [802](../../../../src/efi_bs.asm#L802) | — |
| `bs_copy_mem` | [829](../../../../src/efi_bs.asm#L829) | — |
| `bs_set_mem` | [856](../../../../src/efi_bs.asm#L856) | — |

## Định nghĩa

Hằng số: 2.

## Phụ thuộc

Gọi vào:

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

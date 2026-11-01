# init64.asm
[`src/init64.asm`](../../../../src/init64.asm) — 477 dòng, 17 entry point.

The firmware's phase sequence once long mode is live.

SEC  establish a C-like environment: stack, zeroed globals, serial PEI  size RAM and stand up the page allocator DXE  bring up the display and the storage stack, publish EFI protocols BDS  find a boot device and hand control to \EFI\BOOT\BOOTX64.EFI

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `sec_entry64` | [17](../../../../src/init64.asm#L17) | — |
| `pei_main` | [78](../../../../src/init64.asm#L78) | — |
| `mem_size_ram` | [112](../../../../src/init64.asm#L112) | highest usable byte below 4 GiB, from the CMOS size fields QEMU (and every PC BIOS since) publishes. |
| `cmos_read` | [158](../../../../src/init64.asm#L158) | AL = register index, returns AL. NMI stays masked for the duration of the access, which is what every other CMOS user expects. |
| `dxe_main` | [171](../../../../src/init64.asm#L171) | — |
| `bds_main` | [240](../../../../src/init64.asm#L240) | — |
| `image_exit_resume` | [361](../../../../src/init64.asm#L361) | — |
| `bds_err_no_media` | [373](../../../../src/init64.asm#L373) | — |
| `bds_err_no_esp` | [375](../../../../src/init64.asm#L375) | — |
| `bds_err_no_fs` | [377](../../../../src/init64.asm#L377) | — |
| `bds_err_no_file` | [379](../../../../src/init64.asm#L379) | — |
| `bds_err_no_mem` | [381](../../../../src/init64.asm#L381) | — |
| `bds_err_read_error` | [383](../../../../src/init64.asm#L383) | — |
| `bds_err_pe_error` | [385](../../../../src/init64.asm#L385) | — |
| `bds_failed` | [391](../../../../src/init64.asm#L391) | — |
| `bds_done` | [393](../../../../src/init64.asm#L393) | — |
| `bds_publish_image` | [406](../../../../src/init64.asm#L406) | fill in EFI_LOADED_IMAGE_PROTOCOL and register it |

## Định nghĩa

Hằng số: 1.

Dữ liệu và state: `name_efi`, `name_boot`, `name_bootx64`

## Phụ thuộc

Gọi vào:

- [acpi.asm](acpi.md) — `acpi_init`
- [ata.asm](ata.md) — `ata_init`
- [efi_proto.asm](efi_proto.md) — `kbd_init`
- [efi_tables.asm](efi_tables.md) — `efi_init`, `efi_publish_volume`, `proto_add`
- [efi_var.asm](efi_var.md) — `var_init`
- [fat.asm](fat.md) — `fat_lookup`, `fat_mount`, `fat_read_file`
- [gpt.asm](gpt.md) — `part_find_esp`
- [mem.asm](mem.md) — `mem_alloc_pages`
- [pci.asm](pci.md) — `pci_assign_resources`
- [pe.asm](pe.md) — `pe_error_string`, `pe_load`
- [serial.asm](serial.md) — `ser_init`
- [smbios.asm](smbios.md) — `smbios_init`
- [util.asm](util.md) — `con_putc`, `con_putdec`, `con_puthex64`, `con_puts`, `panic`
- [vbe.asm](vbe.md) — `gfx_init`

Bị gọi bởi:

- [efi_bs.asm](efi_bs.md) — `image_exit_resume`
- [efi_rt.asm](efi_rt.md) — `cmos_read`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# smbios.asm
[`src/smbios.asm`](../../../../src/smbios.asm) — 307 dòng, 3 entry point.

The SMBIOS tables QEMU describes through fw_cfg.

QEMU builds the whole structure table itself and offers it as two fw_cfg files: etc/smbios/smbios-tables, the structures, and etc/smbios/smbios-anchor, the entry point that says where they are. The anchor arrives with that address left at zero, because only firmware knows where the tables will land.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `smbios_init` | [61](../../../../src/smbios.asm#L61) | place QEMU's SMBIOS tables and publish the entry point. Returns EAX = 1 if a configuration table was installed, 0 otherwise. Must run after acpi_init, which is what reads the fw_cfg directory; this only looks names up in it. Must run after efi_init for the same reason acpi_init must: installing a table rewrites the system table header. |
| `smbios_fix_sum` | [226](../../../../src/smbios.asm#L226) | RDI = start, ECX = length, RSI = the checksum byte, which lies inside the range. Makes the range sum to zero modulo 256. |
| `smbios_count` | [249](../../../../src/smbios.asm#L249) | RSI = the structure table, ECX = its size in bytes. Returns EAX = structures up to and including the end marker, or 0 if the walk runs off the end before it finds one. |

## Định nghĩa

Hằng số: 22.

Dữ liệu và state: `guid_smbios`, `guid_smbios3`, `name_smbios_anchor`, `name_smbios_tables`

## Phụ thuộc

Gọi vào:

- [acpi.asm](acpi.md) — `fwcfg_find`, `fwcfg_read`, `fwcfg_select`
- [efi_bs.asm](efi_bs.md) — `bs_install_configuration_table`
- [mem.asm](mem.md) — `mem_alloc_pages`
- [util.asm](util.md) — `con_putc`, `con_putdec`, `con_puthex64`

Bị gọi bởi:

- [init64.asm](init64.md) — `smbios_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

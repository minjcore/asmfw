# efi_rt.asm
[`src/efi_rt.asm`](../../../../src/efi_rt.asm) — 349 dòng, 7 entry point.

Runtime services.

These are the services that outlive ExitBootServices. This firmware keeps them honest but small: a real clock, a reset that actually resets, and the variable services, which live in efi_var.asm. SetVirtualAddressMap is not supported, so the table stays valid only at its physical address.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `rt_unsupported` | [16](../../../../src/efi_rt.asm#L16) | — |
| `rt_get_time` | [37](../../../../src/efi_rt.asm#L37) | — |
| `rtc_decode` | [139](../../../../src/efi_rt.asm#L139) | EDI = raw CMOS byte, ESI = status register B. Returns AL as a binary value, converting from BCD when bit 2 says to. |
| `rt_reset_system` | [160](../../../../src/efi_rt.asm#L160) | — |
| `rt_set_virtual_address_map` | [214](../../../../src/efi_rt.asm#L214) | SetVirtualAddressMap(MemoryMapSize, DescriptorSize, DescriptorVersion, VirtualMap). The OS has chosen a virtual address for every runtime range and says which in VirtualMap. Every pointer the firmware will follow from now on, and every pointer it hands out, is rewritten to match: the runtime services table's entries, the system table's RuntimeServices, ConfigurationTable and FirmwareVendor, and the variable store. Then the two tables' CRCs are taken again. It may be called once, and only after ExitBootServices. What is not rewritten is code: the runtime functions reach their globals through absolute physical addresses, assembled in. Those keep working only because the globals' pages are runtime memory and an OS that maps them at a new address keeps the identity mapping too — which Linux does, on purpose, for exactly this kind of firmware. An OS that dropped the identity mapping would find the variable services faulting. |
| `rt_convert` | [295](../../../../src/efi_rt.asm#L295) | RAX = a physical address. Returns RAX = its virtual address under the map SetVirtualAddressMap was given, CF clear; or CF set and RAX unchanged if no runtime range in the map covers it. Zero stays zero. |
| `rt_convert_at` | [341](../../../../src/efi_rt.asm#L341) | RDI = where a pointer is kept. Converts it in place; one that no runtime range covers is left as it was. |

## Định nghĩa

Hằng số: 12.

## Phụ thuộc

Gọi vào:

- [efi_tables.asm](efi_tables.md) — `efi_fix_crc`
- [init64.asm](init64.md) — `cmos_read`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

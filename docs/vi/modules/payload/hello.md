# hello.asm
[`payload/hello.asm`](../../../../payload/hello.asm) — 1312 dòng, 15 entry point.

A UEFI application, PE32+ headers and all, in one flat binary.

This exists to test the firmware, so it is deliberately not built with a linker: the headers below are exactly what the firmware's PE loader has to understand, spelled out where they can be read.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `efi_main` | [209](../../../../payload/hello.asm#L209) | — |
| `draw_bar` | [395](../../../../payload/hello.asm#L395) | paint a horizontal gradient across the bottom of the screen, straight into the framebuffer the GOP handed over. |
| `show_acpi` | [464](../../../../payload/hello.asm#L464) | find the ACPI tables through the configuration table, name each one, and check that it still checksums to zero. This is the part of the payload that tests the firmware hardest. QEMU hands firmware ACPI blobs whose cross-references are offsets, not addresses, and a script saying which ones to patch and which checksums to redo afterwards. Firmware that runs the script produces tables that sum to zero and point at each other; firmware that skips it produces tables that do neither. Walking the XSDT here reads every pointer the script was supposed to fix. |
| `show_smbios` | [593](../../../../payload/hello.asm#L593) | find the SMBIOS entry point through the configuration table, check its checksums, walk every structure to the end marker, and name the system from the type 1 structure. The firmware's part is small but every piece of it is checkable from here: the entry point's table address is the one field QEMU leaves for firmware to fill in, and filling it in invalidates the checksums. A firmware that skips either step leaves a pointer to nothing, or a sum that is not zero. The 3.x anchor is preferred where both exist, as a 64-bit reader would. |
| `show_vars` | [751](../../../../payload/hello.asm#L751) | the variable services, end to end: set one, read it back with a buffer too small and then with one large enough, find it by enumerating every variable, delete it, and confirm it is gone. Each step has a wrong answer that would look right on its own. A store that ignored DataSize would pass the full read and fail the short one; a walk that never reached the end would never report EFI_NOT_FOUND; a delete that did nothing would leave the last read succeeding. |
| `smbios_string` | [952](../../../../payload/hello.asm#L952) | RSI = a structure, AL = a 1-based string number. Returns RSI = that string, or a pointer to an empty one if it is absent. |
| `find_config` | [981](../../../../payload/hello.asm#L981) | RSI = a GUID. Returns RAX = the configuration table entry's pointer, or 0 if the firmware published no table under that GUID. |
| `sum_bytes` | [1008](../../../../payload/hello.asm#L1008) | RSI = start, ECX = length. Returns AL = their sum. |
| `out_w` | [1028](../../../../payload/hello.asm#L1028) | RDX = a CHAR16 string, written through ConOut. Preserves every register, so a caller can print between steps without saving its own. |
| `out_ascii` | [1054](../../../../payload/hello.asm#L1054) | RSI = a NUL-terminated byte string. Widened into g_strbuf, cut at STRBUF_CHARS, and written. |
| `out_dec` | [1081](../../../../payload/hello.asm#L1081) | EAX = an unsigned value, written in decimal. |
| `sig_to_str` | [1109](../../../../payload/hello.asm#L1109) | RSI = a table. Spells its four signature bytes, and a trailing space, into g_sigbuf as CHAR16. |
| `sum_table` | [1132](../../../../payload/hello.asm#L1132) | RSI = a table. Returns AL = the sum of its bytes, which the specification requires to be zero. |
| `hex_to_str` | [1154](../../../../payload/hello.asm#L1154) | RAX = value, RDI = where to write it as CHAR16, ECX = digits. Most significant first, over the placeholder in a message. |
| `guid_eq` | [1189](../../../../payload/hello.asm#L1189) | RSI and RDI point at GUIDs. ZF set if they match. |

## Định nghĩa

Macro: `WSTR`

Hằng số: 84.

Dữ liệu và state: `pe_signature`, `opt_start`, `opt_end`, `acpi20_guid`, `smbios_guid`, `smbios3_guid`, `var_guid`, `var_data`, `var_tail`, `gop_guid`, `sfs_guid`, `g_image`, `g_st`, `g_gop`, `g_sfs`, `g_root`, `g_file`, `g_readlen`, và 18 nữa

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

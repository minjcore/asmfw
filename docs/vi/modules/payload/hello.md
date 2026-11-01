# hello.asm
[`payload/hello.asm`](../../../../payload/hello.asm) — 1496 dòng, 18 entry point.

A UEFI application, PE32+ headers and all, in one flat binary.

This exists to test the firmware, so it is deliberately not built with a linker: the headers below are exactly what the firmware's PE loader has to understand, spelled out where they can be read.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `efi_main` | [224](../../../../payload/hello.asm#L224) | — |
| `draw_bar` | [411](../../../../payload/hello.asm#L411) | paint a horizontal gradient across the bottom of the screen, straight into the framebuffer the GOP handed over. |
| `show_acpi` | [480](../../../../payload/hello.asm#L480) | find the ACPI tables through the configuration table, name each one, and check that it still checksums to zero. This is the part of the payload that tests the firmware hardest. QEMU hands firmware ACPI blobs whose cross-references are offsets, not addresses, and a script saying which ones to patch and which checksums to redo afterwards. Firmware that runs the script produces tables that sum to zero and point at each other; firmware that skips it produces tables that do neither. Walking the XSDT here reads every pointer the script was supposed to fix. |
| `show_smbios` | [609](../../../../payload/hello.asm#L609) | find the SMBIOS entry point through the configuration table, check its checksums, walk every structure to the end marker, and name the system from the type 1 structure. The firmware's part is small but every piece of it is checkable from here: the entry point's table address is the one field QEMU leaves for firmware to fill in, and filling it in invalidates the checksums. A firmware that skips either step leaves a pointer to nothing, or a sum that is not zero. The 3.x anchor is preferred where both exist, as a 64-bit reader would. |
| `show_vars` | [767](../../../../payload/hello.asm#L767) | the variable services, end to end: set one, read it back with a buffer too small and then with one large enough, find it by enumerating every variable, delete it, and confirm it is gone. Each step has a wrong answer that would look right on its own. A store that ignored DataSize would pass the full read and fail the short one; a walk that never reached the end would never report EFI_NOT_FOUND; a delete that did nothing would leave the last read succeeding. |
| `show_memmap` | [972](../../../../payload/hello.asm#L972) | ask for the memory map, and check that what an OS will still need after ExitBootServices is described as runtime memory: the system table, the runtime services table, and the code behind one of its entries. Described any other way, an OS is entitled to reuse the memory, and nothing would go wrong until the first runtime call after it had. |
| `find_desc` | [1069](../../../../payload/hello.asm#L1069) | RAX = an address. Returns RAX = the memory map descriptor that covers it, or 0. Walks g_mm by the descriptor size the firmware reported. |
| `is_runtime_data` | [1108](../../../../payload/hello.asm#L1108) | RAX = a descriptor or 0. ZF set if it is runtime services data carrying the runtime attribute. |
| `smbios_string` | [1123](../../../../payload/hello.asm#L1123) | RSI = a structure, AL = a 1-based string number. Returns RSI = that string, or a pointer to an empty one if it is absent. |
| `find_config` | [1152](../../../../payload/hello.asm#L1152) | RSI = a GUID. Returns RAX = the configuration table entry's pointer, or 0 if the firmware published no table under that GUID. |
| `sum_bytes` | [1179](../../../../payload/hello.asm#L1179) | RSI = start, ECX = length. Returns AL = their sum. |
| `out_w` | [1199](../../../../payload/hello.asm#L1199) | RDX = a CHAR16 string, written through ConOut. Preserves every register, so a caller can print between steps without saving its own. |
| `out_ascii` | [1225](../../../../payload/hello.asm#L1225) | RSI = a NUL-terminated byte string. Widened into g_strbuf, cut at STRBUF_CHARS, and written. |
| `out_dec` | [1252](../../../../payload/hello.asm#L1252) | EAX = an unsigned value, written in decimal. |
| `sig_to_str` | [1280](../../../../payload/hello.asm#L1280) | RSI = a table. Spells its four signature bytes, and a trailing space, into g_sigbuf as CHAR16. |
| `sum_table` | [1303](../../../../payload/hello.asm#L1303) | RSI = a table. Returns AL = the sum of its bytes, which the specification requires to be zero. |
| `hex_to_str` | [1325](../../../../payload/hello.asm#L1325) | RAX = value, RDI = where to write it as CHAR16, ECX = digits. Most significant first, over the placeholder in a message. |
| `guid_eq` | [1360](../../../../payload/hello.asm#L1360) | RSI and RDI point at GUIDs. ZF set if they match. |

## Định nghĩa

Macro: `WSTR`

Hằng số: 94.

Dữ liệu và state: `pe_signature`, `opt_start`, `opt_end`, `acpi20_guid`, `smbios_guid`, `smbios3_guid`, `var_guid`, `var_data`, `var_tail`, `gop_guid`, `sfs_guid`, `g_image`, `g_st`, `g_gop`, `g_sfs`, `g_root`, `g_file`, `g_readlen`, và 23 nữa

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

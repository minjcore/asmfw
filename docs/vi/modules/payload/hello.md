# hello.asm
[`payload/hello.asm`](../../../../payload/hello.asm) — 1864 dòng, 21 entry point.

A UEFI application, PE32+ headers and all, in one flat binary.

This exists to test the firmware, so it is deliberately not built with a linker: the headers below are exactly what the firmware's PE loader has to understand, spelled out where they can be read.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `efi_main` | [236](../../../../payload/hello.asm#L236) | — |
| `draw_bar` | [430](../../../../payload/hello.asm#L430) | paint a horizontal gradient across the bottom of the screen, straight into the framebuffer the GOP handed over. |
| `show_acpi` | [499](../../../../payload/hello.asm#L499) | find the ACPI tables through the configuration table, name each one, and check that it still checksums to zero. This is the part of the payload that tests the firmware hardest. QEMU hands firmware ACPI blobs whose cross-references are offsets, not addresses, and a script saying which ones to patch and which checksums to redo afterwards. Firmware that runs the script produces tables that sum to zero and point at each other; firmware that skips it produces tables that do neither. Walking the XSDT here reads every pointer the script was supposed to fix. |
| `show_smbios` | [628](../../../../payload/hello.asm#L628) | find the SMBIOS entry point through the configuration table, check its checksums, walk every structure to the end marker, and name the system from the type 1 structure. The firmware's part is small but every piece of it is checkable from here: the entry point's table address is the one field QEMU leaves for firmware to fill in, and filling it in invalidates the checksums. A firmware that skips either step leaves a pointer to nothing, or a sum that is not zero. The 3.x anchor is preferred where both exist, as a 64-bit reader would. |
| `show_vars` | [786](../../../../payload/hello.asm#L786) | the variable services, end to end: set one, read it back with a buffer too small and then with one large enough, find it by enumerating every variable, delete it, and confirm it is gone. Each step has a wrong answer that would look right on its own. A store that ignored DataSize would pass the full read and fail the short one; a walk that never reached the end would never report EFI_NOT_FOUND; a delete that did nothing would leave the last read succeeding. |
| `show_memmap` | [991](../../../../payload/hello.asm#L991) | ask for the memory map, and check that what an OS will still need after ExitBootServices is described as runtime memory: the system table, the runtime services table, and the code behind one of its entries. Described any other way, an OS is entitled to reuse the memory, and nothing would go wrong until the first runtime call after it had. |
| `find_desc` | [1086](../../../../payload/hello.asm#L1086) | RAX = an address. Returns RAX = the memory map descriptor that covers it, or 0. Walks g_mm by the descriptor size the firmware reported. |
| `is_runtime_data` | [1125](../../../../payload/hello.asm#L1125) | RAX = a descriptor or 0. ZF set if it is runtime services data carrying the runtime attribute. |
| `child_check` | [1146](../../../../payload/hello.asm#L1146) | if this image was started by its own parent copy, which says so through LoadOptions, print one line and Exit() with CHILD_STATUS. Returns only if it was not. Exit rather than a return, because Exit is the harder of the two for the firmware: it is called from inside a function, two frames deep, and has to come out of the StartImage that started this image with every register the parent trusted put back. |
| `show_chain` | [1204](../../../../payload/hello.asm#L1204) | LoadImage a copy of this program from its own file, hand it load options, StartImage it, and check what comes back: the status it gave Exit(), and every callee-saved register exactly as it was. |
| `show_lfn` | [1367](../../../../payload/hello.asm#L1367) | a file whose name does not fit 8.3: open it by that name, open it again with the case changed, and find it in a listing of the root under its long name, exactly as written. The short name is a mangled alias (LONGFI~1.TXT or similar) that the volume's writer chose; a firmware that ignores long names can only offer that, and every one of these steps fails against it. |
| `smbios_string` | [1465](../../../../payload/hello.asm#L1465) | RSI = a structure, AL = a 1-based string number. Returns RSI = that string, or a pointer to an empty one if it is absent. |
| `find_config` | [1494](../../../../payload/hello.asm#L1494) | RSI = a GUID. Returns RAX = the configuration table entry's pointer, or 0 if the firmware published no table under that GUID. |
| `sum_bytes` | [1521](../../../../payload/hello.asm#L1521) | RSI = start, ECX = length. Returns AL = their sum. |
| `out_w` | [1541](../../../../payload/hello.asm#L1541) | RDX = a CHAR16 string, written through ConOut. Preserves every register, so a caller can print between steps without saving its own. |
| `out_ascii` | [1567](../../../../payload/hello.asm#L1567) | RSI = a NUL-terminated byte string. Widened into g_strbuf, cut at STRBUF_CHARS, and written. |
| `out_dec` | [1594](../../../../payload/hello.asm#L1594) | EAX = an unsigned value, written in decimal. |
| `sig_to_str` | [1622](../../../../payload/hello.asm#L1622) | RSI = a table. Spells its four signature bytes, and a trailing space, into g_sigbuf as CHAR16. |
| `sum_table` | [1645](../../../../payload/hello.asm#L1645) | RSI = a table. Returns AL = the sum of its bytes, which the specification requires to be zero. |
| `hex_to_str` | [1667](../../../../payload/hello.asm#L1667) | RAX = value, RDI = where to write it as CHAR16, ECX = digits. Most significant first, over the placeholder in a message. |
| `guid_eq` | [1702](../../../../payload/hello.asm#L1702) | RSI and RDI point at GUIDs. ZF set if they match. |

## Định nghĩa

Macro: `WSTR`

Hằng số: 107.

Dữ liệu và state: `pe_signature`, `opt_start`, `opt_end`, `acpi20_guid`, `smbios_guid`, `smbios3_guid`, `var_guid`, `var_data`, `var_tail`, `lfn_text`, `li_guid`, `gop_guid`, `sfs_guid`, `g_image`, `g_st`, `g_gop`, `g_sfs`, `g_root`, và 34 nữa

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

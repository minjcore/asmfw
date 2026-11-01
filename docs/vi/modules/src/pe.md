# pe.asm
[`src/pe.asm`](../../../../src/pe.asm) — 322 dòng, 2 entry point.

The PE32+ loader.

An .efi file is a PE image: headers, a section table, and a base relocation directory.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `pe_load` | [60](../../../../src/pe.asm#L60) | RSI = the file image in memory, RDX = its length in bytes. On success sets g_img_base, g_img_pages and g_img_entry, and returns EAX = 0. A non-zero EAX is an index into pe_errors, printed by the caller. |
| `pe_error_string` | [296](../../../../src/pe.asm#L296) | EAX = the code pe_load returned, RSI = its message |

## Định nghĩa

Hằng số: 33.

Dữ liệu và state: `pe_errors`

## Phụ thuộc

Gọi vào:

- [mem.asm](mem.md) — `mem_alloc_pages`
- [util.asm](util.md) — `mem_copy`, `mem_set`

Bị gọi bởi:

- [init64.asm](init64.md) — `pe_error_string`, `pe_load`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

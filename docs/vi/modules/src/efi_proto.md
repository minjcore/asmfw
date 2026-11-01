# efi_proto.asm
[`src/efi_proto.asm`](../../../../src/efi_proto.asm) — 783 dòng, 20 entry point.

The protocols an image actually touches.

Simple Text Output, Simple Text Input and Graphics Output. All entry points use the Microsoft x64 calling convention: arguments in RCX, RDX, R8, R9 and then on the stack from [RSP+0x28]; RBX, RBP, RSI, RDI and R12-R15 belong to the caller and are saved here.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `to_reset` | [19](../../../../src/efi_proto.asm#L19) | — |
| `to_output_string` | [34](../../../../src/efi_proto.asm#L34) | — |
| `to_test_string` | [71](../../../../src/efi_proto.asm#L71) | — |
| `to_query_mode` | [78](../../../../src/efi_proto.asm#L78) | — |
| `to_set_mode` | [98](../../../../src/efi_proto.asm#L98) | — |
| `to_set_attribute` | [117](../../../../src/efi_proto.asm#L117) | — |
| `to_clear_screen` | [147](../../../../src/efi_proto.asm#L147) | — |
| `to_set_cursor_position` | [157](../../../../src/efi_proto.asm#L157) | — |
| `to_enable_cursor` | [174](../../../../src/efi_proto.asm#L174) | — |
| `to_do_clear` | [187](../../../../src/efi_proto.asm#L187) | clear both consoles and home the cursor |
| `to_sync_cursor` | [214](../../../../src/efi_proto.asm#L214) | publish the console cursor through the protocol's Mode |
| `kbd_init` | [283](../../../../src/efi_proto.asm#L283) | make the codes be the ones this file decodes. A PS/2 keyboard's own default is scan code set 2, and the controller's translation bit — which is what turns those into the set 1 codes every table in every PC operating system is written against — comes out of reset clear. On a normal PC the BIOS sets it during its own keyboard bring-up. This firmware published EFI_SIMPLE_TEXT_INPUT_PROTOCOL for a long time without doing it, and the reason that went unnoticed is worth recording: no payload here ever read a key. A set 2 code in a set 1 table is not rejected, it is decoded — into a different key. The protocol looked implemented, and would have answered every call, with the wrong letter. |
| `kbd_wait_write` | [328](../../../../src/efi_proto.asm#L328) | the input buffer has to be empty before a write, or the write is lost. kbd_wait_read — EAX = 1 if a byte turned up to be read. Both give up rather than spin forever: a controller that never answers is a keyboard that does not work, which is not a reason for firmware to stop. |
| `kbd_wait_read` | [344](../../../../src/efi_proto.asm#L344) | — |
| `ti_reset` | [367](../../../../src/efi_proto.asm#L367) | — |
| `ti_read_key_stroke` | [385](../../../../src/efi_proto.asm#L385) | — |
| `kbd_poll` | [420](../../../../src/efi_proto.asm#L420) | take one key from the controller. Returns EAX = the Unicode character (0 if the key has none) and CX = the EFI scan code, or EAX = 0 and CX = 0 when nothing was pending. Break codes and the modifier keys are swallowed here. |
| `gop_query_mode` | [532](../../../../src/efi_proto.asm#L532) | — |
| `gop_set_mode` | [577](../../../../src/efi_proto.asm#L577) | — |
| `gop_blt` | [593](../../../../src/efi_proto.asm#L593) | — |

## Định nghĩa

Hằng số: 10.

Dữ liệu và state: `efi_palette`, `ansi_clear`, `scancode_ascii`

## Phụ thuộc

Gọi vào:

- [console.asm](console.md) — `fb_clear`
- [mem.asm](mem.md) — `mem_alloc_pool`
- [serial.asm](serial.md) — `ser_putc`
- [util.asm](util.md) — `con_putc`, `mem_copy`

Bị gọi bởi:

- [init64.asm](init64.md) — `kbd_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

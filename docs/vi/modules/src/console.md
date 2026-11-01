# console.asm
[`src/console.asm`](../../../../src/console.asm) — 277 dòng, 6 entry point.

A text console painted directly into the framebuffer.

32 bpp only, which is all gfx_init ever programs. Pixels are little-endian 0x00RRGGBB dwords, so a colour constant reads the way it looks.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `fb_console_init` | [24](../../../../src/console.asm#L24) | derive the text grid from the mode and clear the screen |
| `fb_clear` | [64](../../../../src/console.asm#L64) | paint the whole framebuffer with the background colour |
| `fb_scroll` | [81](../../../../src/console.asm#L81) | shift the picture up by one character cell |
| `fb_newline` | [122](../../../../src/console.asm#L122) | carriage return plus line feed, scrolling if needed |
| `fb_putc` | [144](../../../../src/console.asm#L144) | draw AL at the cursor and advance it. Called from con_putc, which only guarantees RAX; everything else is saved here so callers never have to think about it. |
| `fb_putc_raw` | [268](../../../../src/console.asm#L268) | draw AL without moving the cursor (used by backspace) |

## Định nghĩa

Hằng số: 3.

## Phụ thuộc

Bị gọi bởi:

- [efi_proto.asm](efi_proto.md) — `fb_clear`
- [util.asm](util.md) — `fb_putc`
- [vbe.asm](vbe.md) — `fb_console_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

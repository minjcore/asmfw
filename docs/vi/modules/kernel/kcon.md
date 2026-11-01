# kcon.asm
[`kernel/kcon.asm`](../../../../kernel/kcon.asm) — 406 dòng, 13 entry point.

The kernel's own console.

It exists because the firmware's does not survive ExitBootServices. ConOut is a boot service; the framebuffer behind it is just memory, and memory is still there afterwards. So the kernel keeps the address and the geometry, and re-implements the part that turns bytes into pixels.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kc_init` | [20](../../../../kernel/kcon.asm#L20) | derive the text grid from the mode that was saved before exit |
| `kc_clear` | [61](../../../../kernel/kcon.asm#L61) | paint the whole framebuffer in the background colour |
| `kc_putc` | [86](../../../../kernel/kcon.asm#L86) | AL. A line feed is expanded for the serial side only; the framebuffer treats it as the cursor move it is. |
| `kc_puts` | [105](../../../../kernel/kcon.asm#L105) | RSI = a NUL-terminated string |
| `kc_puthex` | [122](../../../../kernel/kcon.asm#L122) | RAX = value, ECX = how many hex digits to show |
| `kc_puthex8` | [154](../../../../kernel/kcon.asm#L154) | — |
| `kc_puthex16` | [161](../../../../kernel/kcon.asm#L161) | — |
| `kc_puthex64` | [168](../../../../kernel/kcon.asm#L168) | — |
| `kc_putdec` | [178](../../../../kernel/kcon.asm#L178) | RAX, unsigned |
| `kfb_putc` | [205](../../../../kernel/kcon.asm#L205) | AL, straight into the framebuffer |
| `kfb_scroll` | [313](../../../../kernel/kcon.asm#L313) | shift the picture up by one glyph row and clear what it left |
| `kser_init` | [349](../../../../kernel/kcon.asm#L349) | — |
| `kser_putc` | [377](../../../../kernel/kcon.asm#L377) | — |

## Định nghĩa

Dữ liệu và state: `kc_fb`, `kc_pitch`, `kc_w`, `kc_h`, `kc_fb_ok`, `kc_x`, `kc_y`, `kc_cols`, `kc_rows`, `kc_fg`, `kc_bg`, `kc_numbuf`

## Phụ thuộc

Bị gọi bởi:

- [idt.asm](idt.md) — `kc_putc`, `kc_putdec`, `kc_puthex16`, `kc_puthex64`
- [kconst.inc](kconst.md) — `kc_puts`
- [kernel.asm](kernel.md) — `kc_init`, `kc_putc`, `kc_putdec`, `kc_puthex16`, `kc_puthex64`
- [sched.asm](sched.md) — `kc_putdec`
- [syscall.asm](syscall.md) — `kc_putc`, `kc_putdec`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

# kbd.asm
[`kernel/kbd.asm`](../../../../kernel/kbd.asm) — 359 dòng, 7 entry point.

The keyboard, on an interrupt.

The firmware has an i8042 driver of its own, in efi_proto.asm, and this is not a copy of it for the same reason kata.asm is not a copy of ata.asm: ExitBootServices is the moment ConIn stops existing. But these two are not even the same design, which makes the duplication easier to defend than the disk stack's.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kbd_init` | [42](../../../../kernel/kbd.asm#L42) | turn translation on, take whatever was left in the buffer, and only then let IRQ1 through. The order is the whole of it. Translation first, because the codes are the wrong ones until it is on. Draining second, because the controller asserts its interrupt when a byte arrives and not while one is waiting, so a byte already in the output buffer — including the reply to the command below — would be delivered to nobody and would hold up every byte behind it. IRQ1 last, because until this point there is no handler that would know what to do with one. The bit that has to be set was the second reset-clear bit in this project to cost a working device: the first was the attribute controller's palette-address-source, which gates the display no matter how correct the VBE mode is. A set 1 table reading set 2 codes is worse than a blank screen, because it produces plausible characters instead of nothing. |
| `kbd_wait_write` | [115](../../../../kernel/kbd.asm#L115) | — |
| `kbd_wait_read` | [134](../../../../kernel/kbd.asm#L134) | wait for a byte to answer. EAX = 1 if one did. |
| `isr_kbd` | [164](../../../../kernel/kbd.asm#L164) | vector 0x21, reached from the dispatch in isr_common. No context switch. A task woken here becomes runnable and waits for the tick to pick it up, which is at most one tick away and cannot be perceived by whoever is doing the typing. The timer switches because its whole job is to take the CPU away from somebody; this interrupt has no such mandate, and borrowing one would mean a keystroke could preempt a task that never asked the keyboard for anything. |
| `kbd_take` | [185](../../../../kernel/kbd.asm#L185) | one byte from the controller, translated and queued if it turns out to name a character. The order of the tests is not free: the extended prefix has bit 7 set, so it has to be recognised before the test that discards releases, or every extended key would be read as one. |
| `kbd_enqueue` | [261](../../../../kernel/kbd.asm#L261) | AL = a character. A full buffer drops the new byte rather than the oldest. Nobody typing has ever meant the last thirty-two characters and not the first, and dropping the oldest would corrupt a line that was already half read. |
| `kbd_dequeue` | [290](../../../../kernel/kbd.asm#L290) | RDI = where to put them, RSI = how many at most. Returns RAX = how many there were, which may be zero. The caller has already established that RDI names memory the current task is allowed to be given, and this does not re-establish it. It must be called with interrupts off: the head moves in an interrupt. |

## Định nghĩa

Dữ liệu và state: `kbd_lower`, `kbd_upper`, `g_kbd_head`, `g_kbd_tail`, `g_kbd_ext`, `g_kbd_shift`, `g_kbd_mode_in`, `g_kbd_mode_out`, `kbd_buf`

## Phụ thuộc

Gọi vào:

- [sched.asm](sched.md) — `kbd_wake_waiters`

Bị gọi bởi:

- [kernel.asm](kernel.md) — `kbd_init`
- [syscall.asm](syscall.md) — `kbd_dequeue`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

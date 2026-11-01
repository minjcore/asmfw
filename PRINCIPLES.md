# Principles

These were not decided in advance. Each one is the shape of a specific
mistake, written down so it does not have to be made twice, and each one is
kept because it costs something — a principle that has never been expensive
is not a principle, it is a preference.

## 1. Nothing on the machine is already set up

The default assumption is *absent*, not *present*. Every table the CPU
consults is one this code built, and every device that appears to work does so
because something here made it work.

- At reset `CS.base` is `0xFFFF0000` while `CS` reads `0xF000` — a hidden state
  no far jump can reproduce. The first instruction is a near jump for that
  reason alone.
- Every PCI BAR on the machine reads back zero. The framebuffer did not exist
  until `pci_assign_resources` was written.
- A VBE mode is not enough to get a picture: the attribute controller's
  palette-address-source bit still gates the display and comes out of reset
  clear. On a normal PC the video option ROM sets it. There is no option ROM.
- The local APIC's `LINT0` is masked out of reset, so a correctly programmed
  8259 is connected to nothing.
- The i8042's translation bit is clear out of reset and a PS/2 keyboard
  defaults to scan code set 2, so the codes that arrive are not the codes any
  set 1 table decodes. This one is worse than the other two: an unset display
  bit shows nothing and is obviously wrong, while an unset translation bit
  produces a different letter and looks like a working keyboard.

The cost: every subsystem needs a bring-up path, and bring-up is most of the
code.

## 2. Anything that can be wrong needs an independent control

A single implementation of a thing can only be compared against your beliefs
about it. Two can be compared against each other.

`payload/hello.asm` is a genuine UEFI application, not a private format, so it
runs under OVMF as well as under asmfw. If it works there and not here the
firmware is at fault; if it works under neither the payload is. `make ovmf`
runs exactly that comparison, and it caught a truncated GPT partition array
and a path parser that restarted at the root on every separator — two bugs
that were invisible from inside.

A control only covers what it exercises. `ConIn` was published, and answered,
and wrong, for as long as it existed — because no payload had ever read a key,
and a wrong letter is not distinguishable from a right one until somebody asks
for a particular one. The kernel's own keyboard driver is what found it. The
payload polls `ConIn` now, and prints the character it got, so the two
firmwares can be compared on that too.

The cost: the payload has to stay honest. The moment it uses something only
this firmware provides, it stops being a control. And every protocol it does
not touch is one whose implementation has never been run.

## 3. Check at the boundary once, and trust the contract inside it

There is exactly one place where a value is doubted. Past it, nothing re-tests
what has already been established.

`sys_write` checks that the user's buffer lies inside the window, once, before
the loop. The loop behind it does not re-check per byte. That is not an
optimisation dressed up as a rule: it is what makes the boundary meaningful,
because a check repeated everywhere is a check nobody owns.

The cost: the boundary has to be found and defended deliberately. Nothing
warns you when a new entry point quietly becomes a second one.

## 4. Let the physical constraint dictate the style

Where the machine forbids something, the code changes shape rather than
working around it.

- These images are assembled at `org 0` and loaded wherever the firmware
  decides, so a stored `dq isr_n` holds a file offset and not an address. The
  IDT therefore addresses vector *N* as `isr_stubs + N * ISR_STUB_SIZE`, the
  syscall dispatch is a chain of comparisons rather than a jump table, and
  file names are a fixed-width table indexed rather than a table of pointers.
- The flash volume is assembled at `0xFFF00000`, where a 64-bit absolute
  `disp32` sign-extends to `0xFFFFFFFFFFF00000`. `default rel` is not a style
  choice; the handful of genuinely low absolute addresses are written
  `[abs ...]` so they stand out.
- The kernel's disk buffers began as fixed physical addresses, copied from the
  firmware, which is wrong for an image whose load address is not its own to
  choose. They are labels now.

The cost: idioms that look eccentric out of context, and need the comment
explaining which constraint produced them.

## 5. One save format, one way back in

Two ways to represent the same state is two ways to get it wrong.

A task's registers live on its own kernel stack, so a switch is one store of
RSP and one load of the next task's, and the task structure holds no register
file at all. What that buys is that a task which has never run and one that
was interrupted mid-instruction are the same shape: `task_create` writes down
the frame an interrupt would have left, and one code path starts both.

When a task gives up the CPU inside a system call its state is spread across a
frame the switch cannot resume. Rather than teach the switch a second format,
the kernel raises an interrupt against itself — `int 0x81`, on a gate ring 3
cannot reach — and turns the one into the other.

The cost: a layer of indirection that looks gratuitous until you count the
alternative's edge cases.

## 6. Use the mechanism the problem actually calls for

Masking interrupts is not a lock. It is a way of making a lock unnecessary,
which is not the same thing, and the difference shows up as a cost somewhere
else.

The console was first protected by leaving `IF` clear for the whole of a
system call. It worked, in that output arrived whole — and a three kilobyte
write held the entire machine for a quarter of a second. Replacing it with a
mutex, where the second writer *blocks* rather than spins, made everything
else in a system call preemptible and left the output exactly as whole as it
was before.

The cost: a lock has an owner, and an owner can die. A task that faults while
holding the console has to release it, or every other task waits forever.

## 7. Ask the silent state directly

A component that is not working often looks identical to one that is working
and has not been asked to do anything.

The scheduler's timer did not fire, and every visible thing checked out: PIC
remapped, IRQ0 unmasked, the 8254 loaded, `IF` set in the faulting task's
saved flags. A scheduler whose timer never fires looks exactly like one that
works and is simply never asked to switch. `timer_check` now runs in ring 0
before anything depends on the tick, and says so either way.

The cost: diagnostics that only ever report success, until the one time they
do not.

## 8. What cannot be borrowed gets rewritten, and the reason gets written down

The firmware has an ATA driver, a GPT parser and a FAT32 reader. The kernel
reimplements all three, because `ExitBootServices` is precisely the moment
those stop existing. Two readers sit in this tree, solve the same problem, and
cannot share a line of code.

Duplication that has a reason is not a defect, but it is indistinguishable
from one unless the reason is recorded next to it.

The cost: two implementations to keep correct, and the discipline to say why
in a comment rather than leaving the next reader to assume carelessness.

## 9. A number in the code is a number nobody can search for

Every constant is named and declared where it belongs — `const.inc` for the
firmware's physical memory map, `kconst.inc` for the kernel's, `uabi.inc` for
the contract the two sides of the ring boundary share. `0`, `1` and `-1` as
indices or steps are the only exceptions.

`uabi.inc` is the sharpest case: it is included by both the kernel and the
programs, so the system call numbers physically cannot drift apart.

The cost: a layer of names between the code and the specification it
implements, which is worth it exactly as long as the names match the
specification's own.

## 10. State the limits plainly

The limitations section of the README is not an apology. It is the part that
makes the rest of it trustworthy.

This firmware is QEMU-only, and the reason is stated: on real hardware the
memory controller has to be trained first, and on any Intel platform after Ivy
Bridge that code exists only inside Intel's closed FSP binary. Nothing is ever
freed. FAT32 short names only. `make ovmfk` uses the i440fx machine because
the kernel drives the legacy ATA ports itself and has no AHCI driver, and does
not pretend otherwise.

The cost: it is less impressive to read. It is also the only version anybody
can build on.

---

## Where each of these came from

| Principle | The mistake that produced it |
| --- | --- |
| 1, 7 | The timer that would not fire: a correctly programmed 8259 with `LINT0` still masked |
| 2 | A truncated GPT partition array and a path parser that restarted at the root |
| 1, 2 | `EFI_SIMPLE_TEXT_INPUT_PROTOCOL`, published and decoding set 2 codes with a set 1 table, because nothing had ever read a key from it |
| 4 | Disk buffers at fixed physical addresses, inside an image that does not choose its own load address |
| 6 | `IF` used as a console lock, and a 3 KiB write holding the machine for 250 ms |
| 8 | Reaching for the firmware's FAT32 reader after `ExitBootServices` had removed it |

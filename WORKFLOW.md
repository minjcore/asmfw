# Workflow

There is no test framework here, and there cannot be one in the usual sense:
the unit under test is a machine at reset, and the only thing that can observe
it is the code being tested. What replaces a test suite is a loop — build,
boot, read the log, run the control, write down what changed — and the
discipline is in running all five parts of it rather than the first two.

Every step below exists because skipping it hid something once.

## The toolchain this was verified against

```
nasm 3.02                    -f bin only; no linker is involved anywhere
qemu-system-x86_64 11.0.2    the only machine this firmware runs on
python3                      tools/mkfont.py, tools/mkesp.py
gtimeout                     coreutils; nothing here exits QEMU by itself
sips                         macOS, for `make screenshot` only
/opt/homebrew/share/qemu/edk2-x86_64-code.fd    OVMF, the control
```

`OVMF_CODE` and `OVMF_VARS` are overridable on the make line if that path is
not yours. Everything else is `?=` in the Makefile too.

`make check` runs the whole of §3 and §4 below and needs all of it.

## 1. Decide where the change goes, and what that obliges you to run

The firmware boots two different things, and they are not equally demanding.
The payload borrows the machine for a moment; the kernel takes it away
permanently. A change to `src/` has to be checked against both.

| Touched | Rebuild | Boot | Control |
| --- | --- | --- | --- |
| `src/*.asm` | `make` | `make serial` **and** `make serialk` | `make ovmf` |
| `src/const.inc`, `src/efi.inc`, `src/macros.inc` | `make clean && make && make kernel` | both | both |
| `kernel/*.asm`, `kernel/kconst.inc` | `make kernel` | `make serialk` | `make ovmfk` |
| `kernel/uabi.inc` | `make kernel` — rebuilds the kernel *and* all four programs | `make serialk` | `make ovmfk` |
| `kernel/progs/*` | `make kernel` | `make serialk` | `make ovmfk` |
| `payload/hello.asm` | `make` | `make serial` | `make ovmf` — mandatory; the payload *is* the control |
| `tools/mkesp.py` | `make clean && make && make kernel` | both | both |
| `tools/mkfont.py` | regenerate `src/font.inc`, then everything | both | — |

The one that is easy to get wrong is `src/`: the kernel is a client of the
firmware too, and a considerably harsher one — it reads its own image back off
the file system, walks the memory map, and calls `ExitBootServices`. A
firmware change that leaves `make serial` happy and breaks `make serialk` is
the normal case, not the surprising one.

## 2. The build is the first test

`make` is not just a build. Three of this project's invariants are enforced
there, and each failure means something specific:

- **`TIMES value is negative` at `src/fw.asm:54`** — the firmware body no
  longer fits underneath `0xFFFF0000`. Not a padding bug: the real-mode anchor
  has been overrun.
- **`TIMES value is negative` at `src/fw.asm:65`** — `init16.asm` outgrew the
  last 64 KiB, which is every byte the reset vector's *near* jump can reach.
- **`error: build/FIRMWARE.fd is N bytes, expected 1048576`** — the volume is
  not 1 MiB. QEMU maps the top of flash at the top of the address space, so a
  wrong size does not truncate the image, it moves the reset vector.
- **`TIMES value is negative` at `kernel/kernel.asm:102` or `:553`** — the
  kernel image no longer matches the section sizes its hand-written PE headers
  declare.

Warnings are on (`-w+all`) minus exactly three, and those three are named in
the Makefile with the reason. A new warning class is a real signal. Do not add
a fourth `-w-` without a comment saying which absolute-reference idiom
produced it and why it is correct.

## 3. Boot it, and check the log

```
make check          both disks, then the same two under OVMF   -- 47 assertions
make check-fw       the firmware and the payload it boots
make check-kernel   the kernel only
```

The assertions live in `tools/smoke.sh`, and they are landmark lines: fixed
strings the transcript must contain, in one case a string it must **not**
contain — `cs 0008`, a trap taken in ring 0, which means the kernel itself
went wrong and there was nothing left to hand off to. A failure names the
missing line and leaves every transcript in `build/logs/`, so the next step is
reading one, not reproducing anything.

That is a smoke test and nothing more. It proves the machine still gets as far
as it got before and still says the same things on the way; it cannot prove
the maze is a maze. What it buys is that the boring regressions — a phase that
stopped finishing, a task that took the machine with it — are caught by
something other than your memory of what the log used to look like.

So read the log too, whenever something changed on purpose. Everything is
printed twice, to COM1 and to the framebuffer, so the serial transcript is
complete; use it in preference to the window.

Nothing here terminates QEMU. The firmware halts, the kernel halts — both by
design — so `make serial` will sit there forever, and anything automated
around it needs a timeout on QEMU itself. This is what `tools/smoke.sh` does,
and what to do by hand:

```sh
gtimeout 25 qemu-system-x86_64 -machine pc -m 256 -bios build/FIRMWARE.fd \
  -drive file=build/esp.img,format=raw,if=ide -no-reboot -display none -serial stdio

gtimeout 30 qemu-system-x86_64 -machine pc -m 256 -bios build/FIRMWARE.fd \
  -drive file=build/kernel.img,format=raw,if=ide -no-reboot -display none -serial stdio
```

### What a good firmware boot looks like

```
[SEC] long mode entered, 4 GiB identity mapped
[PEI] RAM: 256 MiB usable below 4 GiB
[PEI] page allocator armed
[DXE] PCI: BARs assigned
                                    <- banner repeats here: the framebuffer
                                       console has come up. Expected.
[DXE] GOP: 1024x768x32 @ 00000000C0000000
[DXE] ATA: 64 MiB on the primary master
kbd   i8042 translation on, set 1 codes
[DXE] EFI tables built, protocols published
[DXE] ACPI: 4 tables, RSDP at 0000000001000000
[DXE] done
[BDS] searching for a boot device
[BDS] EFI system partition at LBA 2048, 62 MiB
[BDS] FAT32 volume mounted
[BDS] \EFI\BOOT\BOOTX64.EFI, 12288 bytes
[BDS] image at 0000000001026000, entry 0000000001027000
[BDS] starting image
```

then the payload's own lines, ending `every one of them checksums to zero`,
and `[BDS] image returned, status 0000000000000000`.

Read it as a sequence, not as a set. **The last marker names the phase that
did not finish** — that is what the markers are for, and it is worth more than
any guess about the phase after it.

### What a good kernel boot looks like

The landmarks, in order: the bring-up lines (`gdt`, the tick check, the four
`task N ... window ...` lines), the maze drawn by task 0 and `solved: NNNN
cells`, task 1's eight numbered lines with rising tick counts, `trap 13
(#GP )` killing task 1 for its `cli`, task 2's two refusals (once at the
boundary, once by `#PF` error 5), task 3 giving up after three seconds of
silence, then:

```
kernel   every task has ended after NNN timer ticks
kernel   nothing left to run; halted
```

Four tasks end four different ways, and **none of them takes the machine
with it**. That is the assertion. If a task's ending changes, or the machine
goes down with one, or the tick counts stop rising, something in the scheduler
or the trap path regressed — regardless of what else still works.

Tick counts and the maze differ run to run; the *order* and the endings do
not. Diff on those.

### The landmarks are part of the change

The transcript is the only test surface this project has. So a change that
makes the machine say something new adds that line to `tools/smoke.sh`, and a
change that makes it say something different updates the line it broke — in
the same commit, not afterwards.

A landmark nobody added is a behaviour nothing checks, which is the same
failure mode as a protocol no payload ever calls: it will look like it works
for exactly as long as nobody asks.

Tick counts, the maze, and load addresses differ run to run, so nothing
asserts on them. The *order* of the phases and the four endings do not differ,
and that is what is asserted.

## 4. Run the control

A single implementation can only be compared against your beliefs about it
(PRINCIPLES §2). `make ovmf` and `make ovmfk` boot the same disks under real
OVMF:

- works under OVMF, not here → **the firmware** is at fault
- works under neither → **the payload or kernel** is at fault
- works under both, printing the same thing → the only result that means
  anything

Two rules keep this worth running:

1. **The payload must stay honest.** The moment `payload/hello.asm` uses
   something only asmfw provides, it stops being a control and becomes a
   second opinion from the same head.
2. **A protocol nothing exercises has never been tested.** `ConIn` was
   published, answered, and wrong for as long as it existed, because no
   payload had ever read a key. So a change that adds or edits a protocol
   includes a change to the payload that calls it and prints what came back —
   otherwise the control does not cover the thing you just changed.

`make ovmfk` uses the i440fx machine deliberately: the kernel drives the
legacy ATA ports itself and has no AHCI driver. Do not "fix" it to q35.

`make check` runs both controls at the end of its pass, and skips them with a
line saying so if OVMF is not installed at `OVMF_CODE`. A skipped control is
not a passed one.

## 5. When it does not work

In this order. Each rung is cheaper than the one below it.

**1. Read the last marker.** The phase named is the phase to look at.

**2. Ask the silent state directly** (PRINCIPLES §7). A subsystem that is not
working looks identical to one that works and has not been asked to do
anything. The pattern is `timer_check`: a check that runs in the owning phase,
before anything depends on the answer, and reports either way. Add one rather
than reasoning about registers you have not read.

**3. Turn an address into a line.**

```sh
# firmware — build/fw.lst is written by every build, at final addresses
grep -n 'FFF0ABCD' build/fw.lst

# kernel — no listing is built; make one. org 0, so subtract the load base
# the firmware printed ("[BDS] image at ...") from the faulting RIP.
nasm -f bin -I kernel/ -I src/ -o /dev/null -l build/kernel.lst kernel/kernel.asm

# a program — subtract the window base the kernel printed for that task
nasm -f bin -I kernel/ -I kernel/progs/ -o /dev/null -l build/maze.lst kernel/progs/maze.asm
```

`cs 002b` in a trap frame is ring 3: the RIP belongs to a program, and the
offset is `rip - window`. `cs 0008` is the kernel itself, and the offset is
`rip - image base`.

**4. Ask QEMU.** `-d int,cpu_reset -D build/qemu.log` for a triple fault or an
interrupt that never arrived. Under `-serial mon:stdio`, `Ctrl-A c` reaches
the monitor: `info registers`, `info mem`, `info pci`, `xp/16xw <addr>`.

**5. Bisect with output.** There is no debugger worth having here. The only
state you can trust is state that got printed, so move a `puts` down through
the phase until it stops appearing.

## 6. Recipes

### A system call

1. `kernel/uabi.inc` — a number, and bump `SYS_COUNT`. Both sides include
   this file, which is why the numbers physically cannot drift apart.
2. `kernel/syscall.asm` — one more `cmp eax, SYS_x` in the dispatch chain, and
   the handler. It is a chain and not a jump table because this image is
   assembled at `org 0` (PRINCIPLES §4).
3. Check any user pointer **once**, at the top, the way `sys_write` does. The
   loop behind it does not re-check (PRINCIPLES §3).
4. Decide preemption deliberately. The call runs with `IF` set. Shared state
   takes a lock; it does not clear `IF` (PRINCIPLES §6). Blocking goes through
   the scheduler, so the CPU goes to somebody else.
5. `kernel/progs/ulib.inc` — a wrapper. `RCX`, `R11` and `R10` are the only
   registers it may clobber.
6. A program that actually calls it — a call nothing makes has never run.
7. A landmark in `tools/smoke.sh` for whatever that program prints, and a line
   in the README's limitations for what the call does not handle.

### A program, and the task that runs it

1. `kernel/progs/x.asm` — flat binary, entry at offset zero, RIP-relative
   throughout, at most `PROG_MAX_BYTES`. At entry `RDI` is the task id, `RSI`
   its window, `RDX` its neighbour's; that is all it is told.
2. `Makefile` — add to `PROGS` **and** give it a rule of its own. The names
   are the 8.3 ones FAT stores, and make's patterns are case sensitive.
3. `kernel/kernel.asm`, `prog_names` — one eleven-byte space-padded entry, in
   task order.
4. `kernel/kconst.inc`, `TASK_COUNT` — the window allocation and the kernel
   stacks follow from it.
5. `tools/smoke.sh` — a landmark for how it ends, in `check_kernel`. Four
   endings that differ is the point of having four, and each one is asserted.
6. README — what the task demonstrates, and how it ends.

### A firmware subsystem or protocol

1. A file in `src/`, included in `fw.asm`'s body list.
2. Constants in `const.inc`; ABI offsets and status codes in `efi.inc`.
3. Bring it up from *absent* (PRINCIPLES §1). Assume no option ROM has run,
   no BAR has an address, and every enable bit is clear.
4. Register it in `efi_tables.asm`. Unimplemented members return
   `EFI_UNSUPPORTED` from a real function — never a null pointer, so a caller
   gets a status code instead of a fault.
5. Exercise it from the payload, print what came back, and add that line to
   `check_fw` in `tools/smoke.sh` — then compare under `make ovmf`.

### A constant

`const.inc` for the firmware, `kconst.inc` for the kernel, `uabi.inc` for what
they share. Never a literal in the code: a number in the code is a number
nobody can search for (PRINCIPLES §9). `0`, `1` and `-1` as indices or steps
are the only exceptions.

## 7. Close the loop in the documentation

The change is not finished when it boots.

- **README, "Limitations, stated plainly"** — a line for every edge the change
  does not handle. This section is what makes the rest of the README
  trustworthy (PRINCIPLES §10).
- **README, "Notes on the parts that were not obvious"** — for anything that
  took a day and will take the next reader another day.
- **PRINCIPLES.md** — only when a mistake taught something that *cost*
  something, and then also a row in the table at the end mapping the principle
  to the mistake that produced it. A principle that has never been expensive
  is a preference.
- **REFERENCE.md** — if the change moved an address, added a structure offset,
  changed a register value or altered the system call table. That file is the
  one place those numbers are written down away from the code, so a stale entry
  there is worse than no entry.
- **A comment next to duplicated code** saying why it could not be shared
  (PRINCIPLES §8). The kernel's second FAT32 reader is not a defect, but it is
  indistinguishable from one without the reason written down.

## 8. Commits

The repository is initialised and has no commits yet. `.gitignore` covers
`build/`, `.DS_Store` and `.mygit/`: the images and the transcripts are
reproducible from source, and nothing under `build/` belongs in history — a
1 MiB flash volume least of all.

Subject lines name the subsystem, then what changed, in the voice the comments
use: `vbe: unblank the attribute controller`, `sched: turn a syscall frame
into an interrupt frame`. The body says what was wrong and how it was
observed, because the serial transcript that proved it will not survive
anywhere else.

## 9. Done means

- [ ] builds clean, no new warning class, `FIRMWARE.fd` exactly 1048576 bytes
- [ ] `make check` passes, with the OVMF controls run and not skipped
- [ ] anything the change made the machine say is a landmark in
      `tools/smoke.sh`; anything it made the machine stop saying is a landmark
      that was updated, on purpose, in this commit
- [ ] the log read by eye at least once, not only by `grep`
- [ ] no new numeric literal; no new absolute reference in 64-bit code that is
      not written `[abs ...]` with a reason
- [ ] every user pointer checked once, at a boundary that owns it
- [ ] README and, if it was earned, PRINCIPLES.md updated
- [ ] committed with `build/` excluded

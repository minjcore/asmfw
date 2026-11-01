# docs

Generated documentation: one entry per file in the tree, what it exports, what
it calls, and who calls it. Derived from the sources rather than written beside
them, so it is complete by construction and stale the moment a label moves —
which is what `verify.py` is for.

The four documents at the repository root are the hand-written ones and are not
duplicated here. They answer different questions:

| Document | Answers |
| --- | --- |
| [../README.md](../README.md) | what this is, and what it cannot do |
| [../REFERENCE.md](../REFERENCE.md) | where a number lives, and what standard fixes it |
| [../WORKFLOW.md](../WORKFLOW.md) | what to run after a change |
| [../PRINCIPLES.md](../PRINCIPLES.md) | why the code is shaped the way it is |

## What is here

| File | Covers |
| --- | --- |
| [modules/](modules/README.md) | one file per source file — 44 of them, mirroring the source tree |
| [vi/modules/](vi/modules/README.md) | the same 44, with Vietnamese labels |
| [generate.py](generate.py) | regenerates both trees above from the sources |
| [verify.py](verify.py) | checks all 882 claims in both trees against the sources |
| [vi/](vi/README.md) | tài liệu tiếng Việt — the same system, explained rather than tabulated |

Each module file carries the source file's own banner comment, a table of entry
points with the header comment above each one as its contract, the data and state
it owns, and its dependency edges in both directions — with the edges as links,
so the call graph is walkable. Nothing is paraphrased: the contract column is what
the code says about itself, which is why it stays English in the Vietnamese tree
too.

## verify.py

```
python3 docs/verify.py
```

Every row names a symbol and the line it is defined on, and a line number is the
one kind of documentation that rots without any sign of it — a label moves, the
link still resolves, the row still looks right. `verify.py` re-derives all 856
claims and names the ones that have drifted:

```
docs/modules/kernel/paging.md:12  paging_build: documented at kernel/paging.asm:23, now at line 22
docs/modules/kernel/paging.md:2   kernel/paging.asm: documented as 999 lines, is 84
```

Exit status is 0 when the documentation matches the code and 1 when it does not,
so it belongs anywhere `make check` belongs. It checks three things: that the
line in the table text and the line in the link agree, that the symbol really is
defined at that line, and that each file is as long as it is claimed to be.

What it cannot check is whether a *contract* is still true. A function whose
register convention changed keeps its label, its line and its stale comment, and
only reading it will say so.

## The dependency shape

Both trees are layered, and the layering is visible in the "Calls into" lines:

```
firmware        init64.asm            the phase sequence, calls everything
                efi_*.asm             the EFI surface
                acpi pe fat gpt       formats
                pci vbe ata timer     devices
                util.asm              console and memory primitives
                serial console        the two output paths

kernel          kernel.asm            kmain, kmain64, and the failure paths
                syscall idt sched      the ring boundary and the switch
                kbd kcon               input and output
                kfat kgpt kata         the disk stack
```

Nothing in either tree calls upward, with one deliberate exception each:
`efi_bs.asm` calls `image_exit_resume` in `init64.asm`, because `Exit()` has to
unwind to whoever started the image, and `sched.asm` calls `khalt` in
`kernel.asm`, because the scheduler running out of work is how the machine stops.

`util.asm` and `kcon.asm` are the leaves everything reaches: eleven firmware
files call `util.asm` and five kernel files call `kcon.asm`. One caller on each
list is a header rather than a module — `macros.inc` expands `puts` into a call
to `con_puts`, and `kconst.inc` expands `kputs` into a call to `kc_puts` — which
is why a grep for callers of the console finds two files that contain no code.

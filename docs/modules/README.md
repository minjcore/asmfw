# Module documentation

One file per source file: what it exports, the contract of every entry
point, the data it owns, and its dependency edges in both directions.

Everything here is **derived from the sources**. Each file's description is
its own banner comment; the contract column is the header comment above that
function. Nothing is paraphrased.

```
python3 docs/generate.py
python3 docs/verify.py
```

## Firmware

The firmware in flash ROM. Narrative: REFERENCE.md §3.

| File | Lines | Entry points | Purpose |
| --- | --- | --- | --- |
| [acpi.asm](src/acpi.md) | 664 | 12 | QEMU's fw_cfg interface, and the ACPI tables behind it |
| [ata.asm](src/ata.md) | 295 | 5 | ATA PIO on the primary channel |
| [console.asm](src/console.md) | 277 | 6 | A text console painted directly into the framebuffer |
| [efi_bs.asm](src/efi_bs.md) | 863 | 29 | Boot services |
| [efi_file.asm](src/efi_file.md) | 938 | 19 | Simple File System and File protocols over the FAT32 reader |
| [efi_proto.asm](src/efi_proto.md) | 783 | 20 | The protocols an image actually touches |
| [efi_rt.asm](src/efi_rt.md) | 194 | 4 | Runtime services |
| [efi_tables.asm](src/efi_tables.md) | 486 | 7 | Build the structures an EFI image is handed |
| [efi_var.asm](src/efi_var.md) | 515 | 8 | UEFI variables, kept in RAM |
| [fat.asm](src/fat.md) | 456 | 8 | Enough FAT32 to find and read one file |
| [fw.asm](src/fw.md) | 71 | 1 | The flash volume |
| [gpt.asm](src/gpt.md) | 168 | 1 | Find the EFI system partition |
| [init16.asm](src/init16.md) | 66 | 2 | SEC phase, part 1 |
| [init32.asm](src/init32.md) | 74 | 1 | SEC phase, part 2 |
| [init64.asm](src/init64.md) | 455 | 17 | The firmware's phase sequence once long mode is live |
| [mem.asm](src/mem.md) | 210 | 3 | The page allocator behind AllocatePages, and the memory map |
| [pci.asm](src/pci.md) | 345 | 7 | Type 1 PCI configuration access and a minimal device scan |
| [pe.asm](src/pe.md) | 322 | 2 | The PE32+ loader |
| [serial.asm](src/serial.md) | 59 | 2 | 16550 UART on COM1, the firmware's debug spine |
| [smbios.asm](src/smbios.md) | 307 | 3 | The SMBIOS tables QEMU describes through fw_cfg |
| [timer.asm](src/timer.md) | 109 | 2 | Delays, measured against the 8254 |
| [util.asm](src/util.md) | 201 | 12 | Console output primitives and memory helpers |
| [vbe.asm](src/vbe.md) | 219 | 4 | Bring up a linear framebuffer without a VGA option ROM |
| [const.inc](src/const.md) | 142 | 0 | Build-wide constants and the firmware's physical memory map |
| [efi.inc](src/efi.md) | 348 | 0 | The UEFI ABI as this firmware implements it |
| [font.inc](src/font.md) | 109 | 0 | The console font, one 8x16 cell per printable ASCII character |
| [macros.inc](src/macros.md) | 31 | 0 | Small assembly conveniences |


## Kernel

The kernel the firmware boots. Narrative: REFERENCE.md §7.

| File | Lines | Entry points | Purpose |
| --- | --- | --- | --- |
| [gdt.asm](kernel/gdt.md) | 97 | 2 | Descriptors, and the task state segment behind them |
| [idt.asm](kernel/idt.md) | 271 | 7 | Traps |
| [kata.asm](kernel/kata.md) | 261 | 6 | ATA PIO, because the firmware's block driver went away |
| [kbd.asm](kernel/kbd.md) | 359 | 7 | The keyboard, on an interrupt |
| [kcon.asm](kernel/kcon.md) | 406 | 13 | The kernel's own console |
| [kernel.asm](kernel/kernel.md) | 554 | 3 | A kernel that asmfw boots, and that gets to ring 3 |
| [kfat.asm](kernel/kfat.md) | 310 | 5 | Reading FAT32, again |
| [kgpt.asm](kernel/kgpt.md) | 118 | 1 | Find the EFI system partition |
| [paging.asm](kernel/paging.md) | 84 | 1 | Address spaces |
| [sched.asm](kernel/sched.md) | 516 | 16 | More than one thing at a time |
| [syscall.asm](kernel/syscall.md) | 356 | 9 | The door between the rings |
| [kconst.inc](kernel/kconst.md) | 380 | 0 | What the kernel is built out of |
| [uabi.inc](kernel/uabi.md) | 30 | 0 | The contract between the kernel and a program |


## Programs

The four ring 3 programs and their shared library. Narrative: REFERENCE.md §8.

| File | Lines | Entry points | Purpose |
| --- | --- | --- | --- |
| [count.asm](kernel/progs/count.md) | 101 | 1 | A program: print a line, burn time, repeat |
| [lisp.asm](kernel/progs/lisp.md) | 2053 | 53 | A Lisp, in ring 3, with a garbage collector |
| [maze.asm](kernel/progs/maze.md) | 462 | 10 | A program: generate a maze, solve it, draw it |
| [rogue.asm](kernel/progs/rogue.md) | 94 | 1 | A program that goes looking for memory that is not its own |
| [type.asm](kernel/progs/type.md) | 163 | 1 | A program that waits for something the machine cannot produce |
| [ulib.inc](kernel/progs/ulib.md) | 97 | 5 | The whole of userspace's library |


## Payload

The UEFI application the firmware boots to test itself. Narrative: REFERENCE.md §10.

| File | Lines | Entry points | Purpose |
| --- | --- | --- | --- |
| [hello.asm](payload/hello.md) | 1312 | 15 | A UEFI application, PE32+ headers and all, in one flat binary |

---

47 modules. The narrative documentation is in `REFERENCE.md`; the same tables in Vietnamese are in [../vi/modules/](../vi/modules/README.md).

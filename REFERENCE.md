# Reference

The mechanical half of the documentation: addresses, offsets, register values,
call conventions, and the specification each of them comes from.

The other three documents answer different questions, and this one deliberately
does not repeat them. [README.md](README.md) says what the two programs do and
what they cannot do. [WORKFLOW.md](WORKFLOW.md) says what to run after a change.
[PRINCIPLES.md](PRINCIPLES.md) says why the code is shaped the way it is. This
file says *where a number lives and what standard fixes it*, so that a value
found in the source can be checked against something other than the comment
next to it.

Everything here was read out of the source, and every external claim is linked
to the document that makes it. Where the code deviates from the specification —
and it does, in a handful of places — the deviation is called out rather than
smoothed over.

## Contents

1. [Build](#1-build)
2. [Address maps](#2-address-maps)
3. [Firmware phases and modules](#3-firmware-phases-and-modules)
4. [The EFI surface](#4-the-efi-surface)
5. [Device programming](#5-device-programming)
6. [Formats consumed](#6-formats-consumed)
7. [Kernel](#7-kernel)
8. [The user ABI](#8-the-user-abi)
9. [Disk layout](#9-disk-layout)
10. [The payload](#10-the-payload)
11. [The build tools](#11-the-build-tools)
12. [Transcript landmarks](#12-transcript-landmarks)
13. [Conventions](#13-conventions)
14. [External references](#14-external-references)

---

## 1. Build

One assembler, no linker, no C. Each artifact is one `nasm -f bin` invocation.

| Artifact | Source | Command | Notes |
| --- | --- | --- | --- |
| `build/FIRMWARE.fd` | [src/fw.asm](src/fw.asm) | `nasm -f bin -I src/ -w+all -w-reloc-abs-{dword,word,qword}` | must be exactly 1048576 bytes |
| `build/fw.lst` | same | `-l` on the same invocation | listing at final addresses; the only symbol map there is |
| `build/payload/BOOTX64.EFI` | [payload/hello.asm](payload/hello.asm) | `nasm -f bin` | hand-written PE32+ |
| `build/kernel/BOOTX64.EFI` | [kernel/kernel.asm](kernel/kernel.asm) | `nasm -f bin -I kernel/ -I src/` | hand-written PE32+, `org 0` |
| `build/kernel/*.BIN` | [kernel/progs/](kernel/progs/) | `nasm -f bin -I kernel/ -I kernel/progs/` | flat, no headers |
| `build/esp.img` | payload stage | `tools/mkesp.py <img> <dir> 64` | GPT + FAT32, 64 MiB |
| `build/kernel.img` | kernel stage | same | a second disk, because the kernel takes the machine |

Include paths matter: the kernel is assembled with both `kernel/` and `src/` on
the path, because it takes [src/font.inc](src/font.inc) — the 8x16 glyph table —
and nothing else, from the firmware's tree.

### Build-time invariants

Three of this project's invariants are checked by the assembler and one by the
`Makefile`. Each failure means one specific thing; see
[WORKFLOW.md §2](WORKFLOW.md) for what to do about it.

| Check | Where | Fires when |
| --- | --- | --- |
| `TIMES value is negative` | [src/fw.asm:54](src/fw.asm#L54) | the firmware body overran `0xFFFF0000` |
| `TIMES value is negative` | [src/fw.asm:65](src/fw.asm#L65) | `init16.asm` outgrew the last 64 KiB |
| `TIMES value is negative` | [kernel/kernel.asm:102](kernel/kernel.asm#L102), [:553](kernel/kernel.asm#L553) | the image no longer matches its declared section sizes |
| size assertion | [Makefile](Makefile) | `FIRMWARE.fd` is not 1 MiB — which moves the reset vector rather than truncating the image |

### Toolchain verified against

`nasm 3.02`, `qemu-system-x86_64 11.0.2`, `python3`, GNU `timeout` (as
`gtimeout` on macOS), `mtools` (`mformat`/`mmd`/`mcopy`, called by
`tools/mkesp.py`), and OVMF at `edk2-x86_64-code.fd` for the control.

---

## 2. Address maps

### 2.1 The flash volume

Fixed at both ends by the architecture. QEMU's `-bios` maps the image so its
last byte is at `0xFFFFFFFF`.

```
0xFFF00000  FV_BASE        start of the volume; 32/64-bit body
0xFFFF0000  RM_BASE        last 64 KiB: everything real mode can address
0xFFFFFFF0  reset vector   16 bytes, a near jump to sec_entry16
0xFFFFFFFF  last byte
```

At reset `CS.base` is `0xFFFF0000` while `CS` reads `0xF000`, a hidden state no
far jump can reproduce — hence the near jump, and hence `rm()` in
[src/const.inc](src/const.inc) converting a linear label to a CS-relative
offset. Padding is `0xFF`, the erased state of flash.

### 2.2 Firmware physical memory

From [src/const.inc](src/const.inc). All of it is picked, not discovered: the
firmware runs from ROM, so every mutable byte is at an address it chose.

| Base | Size | Contents |
| --- | --- | --- |
| `0x00070000` | 4 KiB | `PT_PML4` |
| `0x00071000` | 4 KiB | `PT_PDPT` |
| `0x00072000` | 16 KiB | `PT_PD0..3` — 2048 entries of 2 MiB = the low 4 GiB |
| `0x00100000` | ~1 MiB | `G_BASE`, the `GVAR` globals |
| `0x00200000` | — | firmware stack, growing down from `FW_STACK_TOP` |
| `0x00300000` | 1 MiB | `FW_TABLES`: EFI structures, scratch buffers |
| `0x01000000` | to top of RAM | `FW_HEAP_BASE`, the `AllocatePages` bump heap |

`FW_HEAP_MIN` is `0x04000000`: under 64 MiB of RAM the firmware panics in PEI
rather than failing later.

Scratch buffers, all inside `FW_TABLES`:

| Address | Symbol | Holds |
| --- | --- | --- |
| `0x00380000` | `BUF_SECTOR` | one sector, general purpose |
| `0x00380200` | `BUF_IDENTIFY` | ATA `IDENTIFY DEVICE` result |
| `0x00380400` | `BUF_GPT_HDR` | GPT header |
| `0x00381000` | `BUF_GPT_ENT` | GPT partition array, 16 KiB |
| `0x00385000` | `BUF_FAT` | one FAT sector |
| `0x00386000` | `BUF_DIR` | one directory cluster, max 64 KiB |
| `0x00396000` | `BUF_FILE` | one file cluster, for `File->Read` |
| `0x003A6000` | `BUF_NAME83` | one 8.3 name being assembled |
| `0x003A6020` | `BUF_NAME16` | one name as CHAR16 |
| `0x003B0000` | `BUF_FWCFG_DIR` | the fw_cfg file directory, 16 KiB |
| `0x003B4000` | `BUF_ACPI_LOADER` | `etc/table-loader`, up to 64 KiB |
| `0x003C4000` | `ACPI_BLOB_TABLE` | where each ACPI blob was placed |

`MMIO_BELOW_4G` is `0xC0000000`: page-directory entries at or above it are
mapped `PCD|PWT` (uncached), because the PCI hole and the flash itself live
there.

### 2.3 EFI runtime structures

From [src/efi.inc](src/efi.inc), all relative to `FW_TABLES` (`0x00300000`).
They cannot live in the volume: `InstallConfigurationTable` writes into the
system table, and the CRC fields are computed after the tables are built.

| Offset | Symbol | Structure |
| --- | --- | --- |
| `+0x0000` | `EFI_ST` | `EFI_SYSTEM_TABLE` |
| `+0x0100` | `EFI_BS` | `EFI_BOOT_SERVICES` |
| `+0x0300` | `EFI_RT` | `EFI_RUNTIME_SERVICES` |
| `+0x0400` | `EFI_CONOUT` | text output protocol |
| `+0x0460` | `EFI_CONOUT_MODE` | `SIMPLE_TEXT_OUTPUT_MODE` |
| `+0x0480` | `EFI_CONIN` | text input protocol |
| `+0x0500` | `EFI_GOP` | graphics output protocol |
| `+0x0530` | `EFI_GOP_MODE` | its mode |
| `+0x0560` | `EFI_GOP_INFO` | its mode information |
| `+0x0600` | `EFI_LOADED_IMG` | `EFI_LOADED_IMAGE_PROTOCOL` |
| `+0x0700` | `EFI_CFG_TABLE` | configuration table, `CFG_MAX` = 16 entries |
| `+0x0800` | `EFI_VENDOR_STR` | `"asmfw"` as CHAR16 |
| `+0x0880` | `EFI_WAITKEY_EVENT` | an opaque non-null token for `WaitForKey` |
| `+0x0900` | `PROTO_DB` | protocol records, `PROTO_MAX` = 32 × 24 bytes |
| `+0x0A00` | `EFI_SFS` | simple file system protocol |
| `+0x0A40` | `EFI_BLOCKIO` | block I/O protocol |
| `+0x0A80` | `EFI_BLOCKIO_MEDIA` | its media descriptor |
| `+0x0B00` | `EFI_ROOT_FILE` | the root directory `EFI_FILE_PROTOCOL` object |
| `+0x8000` | `ALLOC_TABLE` | allocation records, `ALLOC_MAX` = 128 × 24 bytes |
| `+0xC000` | `MEMMAP_SCRATCH` | the memory map `GetMemoryMap` copies from |

One thing about that table is worth knowing before adding a protocol:
`PROTO_DB` sits at `+0x0900` and `PROTO_MAX` × `PROTO_REC_SIZE` is 768 bytes, so
its declared capacity runs to `+0x0C00` — across `EFI_SFS`, `EFI_BLOCKIO` and
`EFI_ROOT_FILE`. Six `proto_add` calls exist in the tree (five in `efi_init`,
one in `bds_publish_image`), which is 144 bytes, so nothing collides as the code
stands. There are 256 bytes before `EFI_SFS`, so ten records fit: records seven
through ten are free, and the eleventh is the one that would land on top of
`EFI_SFS` — well before `PROTO_MAX` refuses anything.

Handles are tokens, not objects: each protocol instance stands in for its own
handle (`H_CONOUT`, `H_CONIN`, `H_GOP`, `H_IMAGE`), and `H_DISK` is `EFI_SFS` —
one handle carrying both Simple File System and Block I/O, which is what makes
it usable as `LoadedImage->DeviceHandle`.

### 2.4 Kernel memory

Nothing fixed. The kernel is `org 0`, loaded wherever the firmware puts it, and
everything it owns is either inside its own image or allocated through
`AllocatePages` before `ExitBootServices`:

| Allocation | Pages | Why through boot services |
| --- | --- | --- |
| page tables | `PT_ALLOC_PAGES` = 6 × (`TASK_COUNT`+1) = 36 | so the inherited memory map already accounts for them |
| user windows | `USER_ALLOC_PAGES` = 2 MiB × 6 / 4 KiB = 3072 | one window per task plus one, so a 2 MiB-aligned run fits wherever it lands |

Inside the image: `kstack` (`KSTACK_SIZE` = 16 KiB), `tstacks`
(`TASK_COUNT`+1 of them — the extra one is a guard slot never handed out),
`g_memmap` (`MEMMAP_BUF_SIZE` = 16 KiB), and the disk buffers in
[kernel/kfat.asm](kernel/kfat.asm). Buffers are labels, not fixed addresses,
precisely because this image does not choose where it loads
([PRINCIPLES §4](PRINCIPLES.md)).

---

## 3. Firmware phases and modules

### 3.1 The call sequence

```
reset_vector                      fw.asm:67       near jump only
└─ sec_entry16                    init16.asm:12   A20 via port 0x92, flat GDT, CR0.PE
   └─ sec_entry32                 init32.asm:11   PAE, 4 GiB of 2 MiB pages, EFER.LME, CR0.PG
      └─ sec_entry64              init64.asm:15   segments, stack, zero G_BASE, ser_init
         ├─ pei_main              init64.asm:57
         │  └─ mem_size_ram                       CMOS 0x34/0x35, else 0x30/0x31
         ├─ dxe_main              init64.asm:150
         │  ├─ pci_assign_resources               every BAR on bus 0
         │  ├─ gfx_init                           Bochs VBE + fb_console_init
         │  ├─ ata_init                           IDENTIFY the primary master
         │  ├─ kbd_init                           i8042 translation on
         │  ├─ efi_init                           tables, protocols, CRCs
         │  └─ acpi_init                          fw_cfg loader script, publish RSDP
         └─ bds_main              init64.asm:216
            ├─ part_find_esp                      GPT, then MBR type 0xEF
            ├─ fat_mount, efi_publish_volume
            ├─ fat_lookup ×3                      EFI, BOOT, BOOTX64.EFI
            ├─ mem_alloc_pages, fat_read_file
            ├─ pe_load                            PE32+ into EfiLoaderCode
            ├─ bds_publish_image                  LoadedImage on H_IMAGE
            └─ call [g_img_entry]                 RCX = ImageHandle, RDX = SystemTable
               └─ image_exit_resume               a return, or Exit(), lands here
```

Ordering constraints that are not free:

- `kbd_init` before `efi_init`, so `ConIn` is never published claiming to offer
  input the controller has not been configured to produce.
- `acpi_init` after `efi_init`, because installing a configuration table
  rewrites the system table, which does not exist yet.
- `efi_publish_volume` is separate from `efi_init` and runs in BDS: which
  partition to mount is a boot policy decision, not a device one.
- Long mode is entered before anything else happens, so `init16.asm` and
  `init32.asm` are the only 16- and 32-bit code in the tree.

### 3.2 Module index

Register conventions are given as they appear in the file headers. Every
function preserves what it uses unless noted.

**Bring-up**

| File | Entry points |
| --- | --- |
| [init16.asm](src/init16.asm) | `sec_entry16`; `gdt32`, `gdt32_ptr` |
| [init32.asm](src/init32.asm) | `sec_entry32` |
| [init64.asm](src/init64.asm) | `sec_entry64`, `pei_main`, `dxe_main`, `bds_main`, `bds_publish_image`, `mem_size_ram`, `cmos_read` (AL = index → AL) |

**Output and utility**

| File | Entry points |
| --- | --- |
| [serial.asm](src/serial.asm) | `ser_init`, `ser_putc` (AL) |
| [console.asm](src/console.asm) | `fb_console_init`, `fb_clear`, `fb_scroll`, `fb_newline`, `fb_putc` (AL), `fb_putc_raw` |
| [util.asm](src/util.asm) | `con_putc` (AL → both consoles), `con_puts` (RSI), `con_puthex{8,16,32,64}` (RAX), `con_putdec` (RAX), `mem_set` (RDI, RCX, AL), `mem_copy` (RSI→RDI, RCX), `mem_cmp` (→ ZF), `panic` (RSI, never returns) |
| [timer.asm](src/timer.asm) | `stall_us` (RCX), `pit_wait_ticks` (BX) |
| [macros.inc](src/macros.inc) | `CSTR`, `puts`, `putsi`, `ROMALIGN` |

**Devices**

| File | Entry points |
| --- | --- |
| [pci.asm](src/pci.asm) | `pci_read32`/`pci_write32` (EDI = config address), `pci_find_class` (AL), `pci_bar_addr`, `pci_bar_size`, `pci_enable`, `pci_assign_resources` |
| [vbe.asm](src/vbe.asm) | `dispi_read`/`dispi_write` (AX = index, DX = value), `vga_unblank`, `gfx_init` |
| [ata.asm](src/ata.asm) | `ata_init`, `ata_read` (RAX = LBA, ECX = count, RDI = dest), `ata_wait_bsy`, `ata_wait_drq`, `ata_delay400` |

**Storage and images**

| File | Entry points |
| --- | --- |
| [gpt.asm](src/gpt.asm) | `part_find_esp` |
| [fat.asm](src/fat.asm) | `fat_mount`, `fat_lookup` (EAX = dir cluster, RSI = 8.3 name → EAX = cluster, RDX = size, CL = attributes), `fat_read_file`, `fat_read_cluster`, `fat_next_clus`, `fat_clus_lba`, `fat_seek`, `fat_dir_nth` |
| [pe.asm](src/pe.asm) | `pe_load` (RSI = image, RDX = length → EAX = 0 or an error index), `pe_error_string` |
| [mem.asm](src/mem.asm) | `mem_alloc_pages` (RCX = pages, EDX = type → RAX), `mem_alloc_pool` (RCX = bytes), `mem_build_map` (→ EAX = descriptors) |
| [acpi.asm](src/acpi.asm) | `acpi_init`, `acpi_cmd_{allocate,add_pointer,add_checksum}`, `acpi_count_tables`, `acpi_blob_{add,find}`, `fwcfg_{init,find,select,read}`, `str_eq` |

**The EFI implementation**

| File | Entry points |
| --- | --- |
| [efi_tables.asm](src/efi_tables.asm) | `efi_init`, `efi_publish_volume`, `efi_fix_crc`, `crc32` (RSI, ECX → EAX), `proto_add` (RAX = handle, RSI = GUID, RDI = interface), `proto_find`; the templates and GUIDs |
| [efi_bs.asm](src/efi_bs.asm) | every boot service, `proto_collect`, `kbd_peek`, `bs_unsupported` |
| [efi_rt.asm](src/efi_rt.asm) | `rt_get_time`, `rtc_decode`, `rt_reset_system`, `rt_unsupported` |
| [efi_proto.asm](src/efi_proto.asm) | `to_*` (text output), `ti_*` (text input), `kbd_init`, `kbd_poll`, `gop_*`, `efi_palette`, `scancode_ascii` |
| [efi_file.asm](src/efi_file.asm) | `sfs_open_volume`, `file_new`, `file_open`, `file_read`, `file_get_info`, `file_set_position`, `name_to_83`, `name_from_83`, `bio_*` |

### 3.3 Firmware globals

`GVAR` in [src/const.inc](src/const.inc) carves `G_BASE` up at assembly time;
`GOFF_TOTAL` is the byte count `sec_entry64` zeroes. Groups, in order:
framebuffer geometry (`g_fb_*`), console state (`g_con_*`), memory
(`g_ram_top`, `g_heap_next`, `g_heap_end`), display (`g_vga_bdf`, `g_vbe_id`),
disk (`g_ata_present`, `g_ata_sectors`), partition (`g_esp_lba`,
`g_esp_sectors`), filesystem (`g_fat_*`), the loaded image (`g_img_base`,
`g_img_pages`, `g_img_entry`), ACPI (`g_fwcfg_files`, `g_acpi_*`), and boot
services bookkeeping (`g_alloc_count`, `g_map_key`, `g_proto_count`,
`g_cfg_count`, `g_tpl`, `g_mono_count`, `g_bs_exited`, `g_exit_rsp`,
`g_exit_status`).

---

## 4. The EFI surface

Structure offsets are written out as constants in
[src/efi.inc](src/efi.inc) rather than built with a struct macro, because the
numbers are fixed by the specification and having them visible is what lets
them be checked against it. They match
[UEFI 2.10 §4](https://uefi.org/specs/UEFI/2.10/04_EFI_System_Table.html).

### 4.1 Table headers

`EFI_TABLE_HEADER` is signature (8), revision (4), header size (4), CRC32 (4),
reserved (4) — `TH_SIZE` = 0x18. The CRC is taken over `HeaderSize` bytes with
the CRC field zeroed, which is what `efi_fix_crc` does after `efi_init` has
filled the tables in.

| Table | Signature | Value |
| --- | --- | --- |
| System | `"IBI SYST"` | `0x5453595320494249` |
| Boot services | `"BOOTSERV"` | `0x56524553544F4F42` |
| Runtime services | `"RUNTSERV"` | `0x56524553544E5552` |

Revision reported is `EFI_2_70_REVISION` — `(2 << 16) | 70` — with a firmware
revision of `0x00010000`. Sizes: `ST_SIZE` 0x78, `BS_SIZE` 0x178,
`RT_SIZE` 0x88.

### 4.2 Boot services

Implemented, from the template at [src/efi_tables.asm:354](src/efi_tables.asm#L354):

| Group | Members |
| --- | --- |
| memory | `AllocatePages` (all three allocation types), `AllocatePool`, `GetMemoryMap`, `FreePages`, `FreePool` |
| protocols | `HandleProtocol`, `LocateProtocol`, `OpenProtocol`, `CloseProtocol`, `LocateHandle`, `LocateHandleBuffer` |
| events | `WaitForEvent`, `CheckEvent`, `CloseEvent` — the three `ConIn` needs |
| misc | `RaiseTPL`, `RestoreTPL`, `InstallConfigurationTable`, `Exit`, `ExitBootServices`, `GetNextMonotonicCount`, `Stall`, `SetWatchdogTimer`, `ConnectController`, `CalculateCrc32`, `CopyMem`, `SetMem` |

`FreePages` and `FreePool` return `EFI_SUCCESS` and do nothing: the allocator is
a bump pointer. Everything else — `CreateEvent`, `SetTimer`, `SignalEvent`, the
`InstallProtocolInterface` family, `RegisterProtocolNotify`,
`LocateDevicePath`, `LoadImage`, `StartImage`, `UnloadImage`,
`DisconnectController`, `OpenProtocolInformation`, `ProtocolsPerHandle`, the
`Multiple` variants, `CreateEventEx` — is `bs_unsupported`, a real function
returning `EFI_UNSUPPORTED`. Never a null pointer, so a caller gets a status
code instead of a fault.

### 4.3 Runtime services

`GetTime` (off the RTC, via `rtc_decode`) and `ResetSystem` are real. The
variable services are in `efi_var.asm`: 32 fixed records of 2 KiB in runtime
services data, each a GUID, attributes, a CHAR16 name of up to 256 bytes and
up to 1760 bytes of data. Deletion is `Attributes` = 0 or `DataSize` = 0
without `APPEND_WRITE`; an existing variable keeps its attributes, and a write
with different ones is `EFI_INVALID_PARAMETER`; after `ExitBootServices` a
variable without `RUNTIME_ACCESS` is invisible.
Everything else, `SetVirtualAddressMap` included, is `rt_unsupported`, so
runtime services remain valid only at their physical addresses.

### 4.4 Protocols

| GUID | Protocol | Handle | Notes |
| --- | --- | --- | --- |
| `387477C2-69C7-11D2-8E39-00A0C969723B` | Simple Text Output | `H_CONOUT` | full, including `SetAttribute` against the 16-colour palette |
| `387477C1-69C7-11D2-8E39-00A0C969723B` | Simple Text Input | `H_CONIN` | polled i8042, set 1, unshifted only |
| `9042A9DE-23DC-4A38-96FB-7ADED080516A` | Graphics Output | `H_GOP` | one mode; `Blt` implements all four operations |
| `964E5B22-6459-11D2-8E39-00A0C969723B` | Simple File System | `H_DISK` | read-only FAT32 |
| `964E5B21-6459-11D2-8E39-00A0C969723B` | Block I/O | `H_DISK` | whole disk, read-only |
| `5B1B31A1-9562-11D2-8E3F-00A0C969723B` | Loaded Image | `H_IMAGE` | published by `bds_publish_image` |
| `09576E92-6D3F-11D2-8E39-00A0C969723B` | File Info | — | the `GetInfo` type, not a published interface |

Configuration table entries, installed by `acpi_init`:
`8868E871-E4F1-11D3-BC22-0080C73C8881` (ACPI 2.0) and
`EB9D2D30-2D88-11D3-9A16-0090273FC14D` (ACPI 1.0), both pointing at the same
RSDP — an ACPI 2.0 RSDP begins with a byte-for-byte 1.0 one.

`EFI_FILE_PROTOCOL` objects are 0x80 bytes: the eleven revision-1 members up to
`F_PUBLIC_SIZE` (0x58), then this firmware's own bookkeeping — cluster,
attributes, size, position, and the 8.3 name — which the caller never sees,
because the object is handed out as a pointer to its first member.

### 4.5 Memory types and descriptors

`EFI_MEMORY_DESCRIPTOR` is 40 bytes of fields, but `MD_SIZE` is 48 and 48 is
what `GetMemoryMap` reports as the descriptor size, matching what other
firmware reports; consumers must stride by the reported size.

`mem_build_map` emits, in ascending address order: the first 640 KiB as
`EfiBootServicesData`; `0xA0000..0x100000` as `EfiReservedMemoryType`, uncached;
`G_BASE` to `FW_HEAP_BASE` in four pieces — the pages holding the globals and
the first page of `FW_TABLES` (system table, runtime services, configuration
table) as `EfiRuntimeServicesData` with `EFI_MEMORY_RUNTIME`, the stack and the
rest of `FW_TABLES` as `EfiBootServicesData`; then one descriptor per
allocation record, with the type the caller asked for and `EFI_MEMORY_RUNTIME`
on the runtime types; then the unallocated tail as `EfiConventionalMemory`;
then the flash as `EfiMemoryMappedIO`, uncached, with `EFI_MEMORY_RUNTIME`,
because the runtime services' code executes from it in place. Recording the requested type matters: an OS may
reuse `EfiBootServicesData` after `ExitBootServices`, so an image handed back
under the wrong type would be freed out from under itself.

---

## 5. Device programming

Every subsystem here is brought up from *absent*
([PRINCIPLES §1](PRINCIPLES.md)). The values below are the ones the code
writes, with the reason where the reason is not obvious.

### 5.1 PCI configuration and BAR assignment

Ports `0x0CF8` (address) and `0x0CFC` (data). Bus 0 only, devices 0–31,
functions 0–7; header type is masked with `0x7F` and anything non-zero is
skipped, since these QEMU machines have no bridges unless one is asked for.

`pci_assign_resources` sizes each BAR by writing all ones and reading back,
then places it at its natural alignment: MMIO from `0xC0000000` upward, I/O from
`0xC000`. Decoding is turned **off** (command `AND 0xFFFFFFFC`) while the BARs
move, so a half-written address cannot briefly claim somebody else's window, and
turned back on with `OR 0x07` — I/O, memory, and bus mastering. A 64-bit BAR
consumes the next slot too, and its upper half is written zero; an empty BAR is
written zero, because leaving the probe value behind would have the device
decode all of memory.

Every BAR on a QEMU machine reads back zero at reset. Assigning them is
firmware's job and nobody else's, which is why the framebuffer did not exist
until this function did.

### 5.2 Display: Bochs VBE, then the VGA core

Index `0x01CE`, data `0x01CF`, per the
[Bochs VBE extensions](https://wiki.osdev.org/Bochs_VBE_Extensions). `gfx_init`
finds the display by PCI class `0x03`, enables memory decode, checks the ID
register reads `0xB0Cx`, takes the framebuffer address from BAR0, then writes
geometry **while disabled** — XRES, YRES, BPP, VIRT_WIDTH, X/Y offset, bank —
and finally `ENABLE = VBE_DISPI_ENABLED | VBE_DISPI_LFB_ENABLED` (`0x41`). The
mode is confirmed by reading XRES back before anything depends on it.

Mode: 1024×768×32, pitch 4096, 3 MiB of framebuffer.

A VBE mode is not enough to get a picture. `vga_unblank` writes `0xE3` to the
miscellaneous output register (`0x3C2`), reads the input status register
(`0x3DA`) to put the attribute controller's shared index/data port back into
index phase, and writes `0x20` to `0x3C0` — palette-address-source set. That bit
comes out of reset clear and gates the display; on a normal PC the video option
ROM sets it during INT 10h mode setting, and there is no option ROM here.

### 5.3 Serial

COM1 at `0x3F8`, divisor 1 for 115200, 8N1 (`LCR = 0x03`), FIFOs on
(`FCR = 0xC7`), `MCR = 0x0B`, interrupts off. `ser_putc` blocks on
`LSR.THRE` (`0x20`). Everything the firmware prints goes to both consoles
through `con_putc`, so the serial transcript is complete and is what
`tools/smoke.sh` reads.

### 5.4 The 8254, as a delay source

The firmware uses channel 2, gated by port `0x61` bit 0 with OUT2 readable at
bit 5, in the counting mode `stall_us` and `pit_wait_ticks` expect. Input
frequency `1193182` Hz; `PIT_MAX_TICKS` is 60000, about 50 ms, comfortably
inside a 16-bit count. The kernel uses channel 0 instead, for a different
purpose — see §7.5.

### 5.5 ATA PIO

Primary channel: `0x1F0` data, `0x1F1` error, `0x1F2` count, `0x1F3..0x1F5`
LBA, `0x1F6` drive/head, `0x1F7` command on write and status on read, with
`0x3F6` as the alternate status that does not clear the interrupt. Commands:
`IDENTIFY DEVICE` (`0xEC`) and `READ SECTORS` (`0x20`), LBA28, 512-byte
sectors, polled. Status bits used: BSY `0x80`, DF `0x20`, RDY `0x40`,
DRQ `0x08`, ERR `0x01`. `ata_delay400` is the conventional 400 ns settle after
a drive select, spent on four alternate-status reads.

### 5.6 The i8042

Data `0x60`, status `0x64`; OBF `0x01` says a byte is waiting, IBF `0x02` says
do not write yet. `kbd_init` reads the command byte (`0x20`), sets the
translation bit `0x40`, and writes it back (`0x60`).

That bit is the whole difference between working and plausibly wrong. A PS/2
keyboard's own default is
[scan code set 2](https://wiki.osdev.org/PS/2_Keyboard), what every OS decodes
is set 1, and
[bit 6 of the controller command byte](https://wiki.osdev.org/%228042%22_PS/2_Controller)
is what translates one into the other. It comes out of reset clear under QEMU;
on a normal PC the BIOS sets it. A set 1 table reading set 2 codes does not
fail — it returns a different, plausible letter.

The firmware's `ConIn` polls, so it never sees a break code and cannot know
whether shift is held; it reports the unshifted character. The kernel's driver
is interrupt-driven and does track shift (§7.7).

---

## 6. Formats consumed

### 6.1 GPT, and the MBR fallback

`part_find_esp` reads LBA 1, checks the signature `"EFI PART"`, and walks the
partition array described by the header — entries LBA at +72, count at +80,
entry size at +84 — looking for type GUID
`C12A7328-F81F-11D2-BA4B-00A0C93EC93B`, the EFI system partition, per
[UEFI 2.10 §5](https://uefi.org/specs/UEFI/2.10/05_GUID_Partition_Table_Format.html).
Entry fields used: type at 0, first LBA at +32, last at +40.

If the GPT header does not validate at all, it falls back to the MBR partition
table at offset 446 and takes the first of the four entries with type `0xEF`. A
*valid* GPT with no ESP in it is not a fallback case and stops there, because an
MBR scan of that disk would only find the protective entry.

`BUF_GPT_ENT` holds 16 KiB — 128 entries of 128 bytes,
which is what the spec's minimum reserved array size comes to, and what a
truncated read of got caught by the OVMF control
([PRINCIPLES §2](PRINCIPLES.md)).

### 6.2 FAT32

BPB fields read: bytes per sector `0x0B`, sectors per cluster `0x0D`, reserved
sectors `0x0E`, number of FATs `0x10`, FAT size `0x24`, root cluster `0x2C`.
Directory entries are 32 bytes: name at 0 (eleven bytes, space padded),
attributes at `0x0B`, cluster high at `0x14`, low at `0x1A`, size at `0x1C`.
`ATTR_LFN` (`0x0F`) entries are skipped, not decoded — short names only.
End of chain is `>= 0x0FFFFFF8`.

The reader is read-only and appears twice, once in
[src/fat.asm](src/fat.asm) and once in [kernel/kfat.asm](kernel/kfat.asm),
because `ExitBootServices` is exactly when the first one stops existing
([PRINCIPLES §8](PRINCIPLES.md)).

### 6.3 PE32+

`pe_load` implements the loader
[UEFI images require](https://uefi.org/specs/UEFI/2.10/02_Overview.html):
`MZ` at 0, `e_lfanew` at `0x3C`, `PE\0\0`, machine `0x8664`, optional header
magic `0x020B`. It allocates `SizeOfImage` (`+0x38`) rounded to pages as
`EfiLoaderCode`, **zeroes it** — sections need not cover the image and the gaps
must read as zero, which is where `.bss` lives — copies `SizeOfHeaders`
(`+0x3C`), then each section, refusing any whose file range runs past the end of
the file or whose virtual range runs past the end of the image.

Relocations are applied when the load address differs from `ImageBase`
(`+0x18`), from data directory 5. Block header is page RVA, block size, then
16-bit entries whose top 4 bits are the type: `IMAGE_REL_BASED_ABSOLUTE` (0) is
padding, `HIGHLOW` (3) patches a dword, `DIR64` (10) patches a qword. A
mismatched image with no relocation directory is accepted unless it sets
`IMAGE_FILE_RELOCS_STRIPPED` (`0x0001`) — because a position-independent image
with every reference RIP-relative is exactly what running it where it lies was
built for, and both images in this tree are that.

`pe_load` returns 0, or an index into `pe_errors`: 1 short, 2 not PE, 3 wrong
machine, 4 not PE32+, 5 allocation failed, 6 a range outside the image,
7 an unknown relocation type, 8 stripped relocations at the wrong base,
9 a bad entry point.

### 6.4 fw_cfg and the ACPI loader script

Selector `0x510`, data `0x511`; signature key `0x0000` reads `"QEMU"`, and the
file directory is key `0x0019`, per the
[fw_cfg specification](https://www.qemu.org/docs/master/specs/fw_cfg.html).
Directory entries are 64 bytes: size (big-endian u32), selector (big-endian
u16), reserved, then a 56-byte NUL-padded name. Selecting a key rewinds it to
offset zero; the data is then read a byte at a time.

QEMU does not hand over finished ACPI tables. It hands over blobs plus
`etc/table-loader`, a script of 128-byte commands
([QEMU's linker/loader](https://www.qemu.org/docs/master/specs/acpi_hw_reduced.html)):

| Command | Value | What `acpi_init` does |
| --- | --- | --- |
| `ALLOCATE` | 1 | download the named blob into fresh memory at the requested alignment, record where it landed. The zone field is ignored: it distinguishes the legacy F-segment, which only a BIOS scanning for the RSDP cares about |
| `ADD_POINTER` | 2 | turn an offset inside one blob into the absolute address of another |
| `ADD_CHECKSUM` | 3 | re-sum a range and store the byte, after the pointers have been patched |
| `WRITE_POINTER` | 4 | skipped — it writes back into fw_cfg, which only matters to features this firmware does not expose |

The script is ordered, so one pass suffices. `etc/acpi/rsdp` is then located and
installed under both ACPI GUIDs, and `acpi_count_tables` walks the XSDT for the
diagnostic count. Every cross-reference in those blobs is an offset until
firmware makes it an address, and every checksum is wrong until firmware redoes
it — which is why the payload sums each table rather than reporting that one
exists.

RSDP fields used: revision at 15, RSDT at 16, XSDT at 24. SDT header is 36
bytes with the length at offset 4.

---

## 7. Kernel

Two phases, and it is worth keeping them straight while reading
[kernel/kernel.asm](kernel/kernel.asm): before `ExitBootServices` the kernel is
a UEFI application using boot services to find the framebuffer and take the
memory it will still need; after it, nothing exists but the machine. The call
sequence is in §7.10 and the module index in §7.11, mirroring §3.1 and §3.2 on
the firmware side.

### 7.1 The boot-services phase

`kmain(RCX = ImageHandle, RDX = SystemTable)` — Microsoft x64 calling
convention, so 32 bytes of shadow space plus one slot, because `GetMemoryMap`
takes five arguments.

1. Save the system table, ConOut and boot services; clear the screen; print.
2. `LocateProtocol(GOP)` and copy out framebuffer base, resolution and pitch —
   the framebuffer outlives the protocol describing it.
3. Walk the configuration table for the ACPI 2.0 GUID and keep the RSDP, while
   there is still a table listing it.
4. `AllocatePages` twice: page tables, then user windows.
5. Align the window run up to 2 MiB. `AllocatePages` promises page alignment and
   nothing stronger, which is why the request was one window larger than needed.
6. `GetMemoryMap`, then `ExitBootServices` with the key, up to `MAP_RETRIES`
   times. Taking the map can itself change the map, so a refusal is normal and
   the answer is to look again.

Nothing is asked of the firmware after that. `kmain64` replaces CR3, the GDT,
the TSS, the IDT and the SYSCALL MSRs before anything else happens.

### 7.2 GDT and TSS

The order is fixed by SYSRET's selector arithmetic, not by taste. With REX.W,
SYSRET loads CS from `IA32_STAR[63:48] + 16` and SS from `+ 8`, forcing RPL 3
into both ([Intel SDM, SYSCALL/SYSRET](https://hjlebbink.github.io/x86doc/html/SYSCALL.html)).
The 32-bit user code slot exists only to be that base.

| Selector | Symbol | Descriptor |
| --- | --- | --- |
| `0x00` | `KSEL_NULL` | — |
| `0x08` | `KSEL_CODE` | `0x00AF9A000000FFFF` — ring 0, 64-bit |
| `0x10` | `KSEL_DATA` | `0x00CF92000000FFFF` — ring 0 |
| `0x18\|3` | `USEL_CODE32` | `0x00CFFA000000FFFF` — SYSRET's base |
| `0x20\|3` | `USEL_DATA` | `0x00CFF2000000FFFF` |
| `0x28\|3` | `USEL_CODE` | `0x00AFFA000000FFFF` — ring 3, 64-bit |
| `0x30` | `KSEL_TSS` | built at run time; 16 bytes, so it takes two slots |

`0x2B` is the selector the boot log prints as `sysret will enter cs 002b`, and
it is `USEL_CODE32 + 16` — the arithmetic checking out is the assertion.

The TSS is 104 bytes with `RSP0` at `+0x04` and the I/O map base at `+0x66` set
to `TSS_SIZE`, which is how "no I/O permission bitmap" is said. Descriptor type
`0x89`: present, DPL 0, available 64-bit TSS. Without `RSP0` the CPU has no
stack to push a ring 3 exception frame onto, and a `#GP` becomes a `#DF`
becomes a reset. `gdt_init` reloads CS with a far return, because CS cannot be
assigned to, then `ltr`.

### 7.3 IDT

256 gates of 16 bytes, type `0x8E` — present, DPL 0, 64-bit interrupt gate — and
no IST, since `RSP0` is stack enough. Every gate points at its own stub, and
stubs are a fixed `ISR_STUB_SIZE` of 16 bytes so that vector *N* is
`isr_stubs + N * 16`: in an `org 0` image a stored `dq isr_n` would hold a file
offset, not an address ([PRINCIPLES §4](PRINCIPLES.md)). Unused stub bytes are
`0xCC`.

`ISR_ERR_MASK` is `0x60227D00` — vectors 8, 10, 11, 12, 13, 14, 17, 21, 29, 30,
the ones for which the CPU pushes an error code. Their stubs must not push a
second one, or every field above it is off by eight.

The frame `isr_common` sees, above the 15 pushed GPRs (`GPR_BYTES` = 120):

| Offset | Field |
| --- | --- |
| `+0x00` | vector, pushed by the stub |
| `+0x08` | error code, the CPU's or the stub's zero |
| `+0x10` | RIP |
| `+0x18` | CS |
| `+0x20` | RFLAGS |
| `+0x28` | RSP |
| `+0x30` | SS |

`isr_common` dispatches the timer, the keyboard and `VEC_SCHED` before anything
else, then prints the frame and decides by `CS & 3`: ring 3 goes to
`task_faulted` and the task is over; ring 0 means the kernel itself went wrong
and there is nothing left to hand off to, so it halts. `cs 0008` in a transcript
is that case, and `tools/smoke.sh` denies it outright.

### 7.4 Paging

`paging_build(RDI = a 6-page region, RSI = the window to expose)` returns a PML4
without loading it. Every space is identical except one entry: the low 4 GiB
identity mapped in 2 MiB pages as **supervisor**, so the kernel is reachable
whichever space is loaded, plus exactly one 2 MiB page carrying `U/S` — that
task's window.

`U/S` is set on PML4[0] and PDPT[0..3] and left to the leaf to decide, because
access is granted only where every level agrees. That single differing entry is
the whole of the isolation: a task cannot name another task's window, because in
its own space that window has no user mapping to walk. Task 2 demonstrates
exactly this, and dies of `#PF` error 5.

`PT_PAGE_COUNT` is 6 (PML4, PDPT, four PDs); the directories are contiguous, so
the 2 MiB index alone addresses the right one.

### 7.5 Interrupt controllers and the tick

| Vector | Source | Handler |
| --- | --- | --- |
| `0x20` | IRQ0, the 8254 | `isr_timer` |
| `0x21` | IRQ1, the i8042 | `isr_kbd` |
| `0x81` | the kernel, against itself | `isr_resched` |

Three things happen in order, and the order is the point.

**`lapic_init`** — base `0xFEE00000`: spurious vector register (`0x0F0`) written
`0x1FF` to software-enable the APIC, `LVT LINT0` (`0x350`) set to delivery mode
ExtINT (`0x700`), `LVT LINT1` (`0x360`) to NMI (`0x400`). QEMU delivers a PIC
interrupt to the CPU only when the local APIC is hardware-disabled or has LINT0
unmasked, and out of reset every LVT entry is masked — so without this, a
correctly programmed 8259 is
[connected to nothing](https://wiki.osdev.org/APIC). A BIOS calls this virtual
wire mode; asmfw never does it, because nothing had ever needed an interrupt.

**`pic_init`** — ICW1 `0x11`, vector bases `0x20` and `0x28`, cascade on IRQ2
(`0x04` / `0x02`), ICW4 `0x01`, then mask everything except IRQ0 (`0xFE`, and
`0xFF` on the slave). Left where the firmware puts it, IRQ0 would arrive as
vector 8 — `#DF`, indistinguishable from the CPU giving up. Only the timer is
unmasked because only the timer has a handler yet; `kbd_init` ANDs out
`0xFD` for itself later.

**`pit_init`** — control word `0x34` to port `0x43`: channel 0, lo/hi byte,
[mode 2 rate generator](https://wiki.osdev.org/Programmable_Interval_Timer),
binary. Divisor `1193182 / 100`, so `TICK_HZ` = 100 and `MS_PER_TICK` = 10.

**`timer_check`** then proves the tick arrives before anything depends on it, by
watching `g_ticks` change with interrupts on for a bounded spin, in ring 0 where
the answer is unambiguous. A scheduler whose timer never fires looks exactly
like one that works and is never asked to switch
([PRINCIPLES §7](PRINCIPLES.md)).

### 7.6 Tasks and the scheduler

`TASK_COUNT` is 4. The structure is `T_SIZE` = 0x58 bytes:

| Offset | Field | Meaning |
| --- | --- | --- |
| `0x00` | `T_STATE` | free / ready / dead / blocked |
| `0x08` | `T_PML4` | its address space |
| `0x10` | `T_USER_BASE` | its window — the bound `sys_write` and `sys_read` check |
| `0x18` | `T_KSTACK` | top of its kernel stack; also what goes in `TSS.RSP0` |
| `0x20` | `T_RSP` | where that stack was left: the whole of a saved context |
| `0x28` | `T_URSP` | its user stack, held across a syscall |
| `0x30` | `T_ID` | 0..3 |
| `0x38` | `T_STATUS` | what it passed to `sys_exit` |
| `0x40` | `T_WAKE` | the tick it sleeps until; 0 means no deadline |
| `0x48` | `T_WAITCON` | set while it wants the console |
| `0x50` | `T_WAITKEY` | set while it wants a keystroke |

States are `TASK_FREE` 0, `TASK_READY` 1, `TASK_DEAD` 2, `TASK_BLOCKED` 3.
Blocked is one state and three reasons, and they are not exclusive: a task in
`sys_read` with a timeout waits on the keyboard and the clock at once. Whichever
arrives first clears both and the task re-tests to learn which it was.

There is no register save area, because a task's registers live on its own
kernel stack. A switch is one store of RSP and one load
([PRINCIPLES §5](PRINCIPLES.md)):

| Function | Contract |
| --- | --- |
| `task_create` | RDI = id, RSI = window, RDX = PML4, RCX = the neighbour's window. Writes the interrupt frame `iretq` will consume — SS, RSP at the top of the window, RFLAGS with IF set, CS, RIP at the window base — then a zeroed register file with RDI/RSI/RDX filled in at `FRAME_RDI`/`RSI`/`RDX` |
| `sched_next` | → RAX = the next `TASK_READY` task after the current one, or 0. It may legitimately return the current task |
| `sched_run` | RAX = a task. Sets `TSS.RSP0`, loads CR3, loads RSP, pops the GPRs, discards the vector and error code, `iretq`. Never returns |
| `sched_park` | nothing runnable now. If anything is alive: `sti; hlt` on the kernel stack, with `g_current` cleared. Otherwise `sched_finished` |
| `sched_wake_due` | promote every sleeper whose `T_WAKE` has arrived, clearing `T_WAITKEY` too |
| `kbd_wake_waiters` | the mirror image, from the keyboard interrupt: wake every `T_WAITKEY` waiter, because the buffer holds bytes and not a turn |

CR3 changes before RSP in `sched_run`, which is safe only because every address
space identity maps the kernel — both stacks are present in both spaces.

`isr_timer` sends the EOI **before** the switch, because after the switch there
is no "after": `sched_run` leaves through `iretq` on another task's stack.

`isr_resched` sends no EOI: nothing in hardware raised it. It exists so that a
task giving up the CPU inside a system call — whose state is spread across a
frame the switch cannot resume — becomes an interrupt frame like any other.
`VEC_SCHED` is `0x81` on a DPL 0 gate, so ring 3 asking for it directly gets
`#GP`.

Round robin, no priorities. The next runnable task after the current one wins.

### 7.7 The console, and its lock

`kcon.asm` is a second console: the firmware's went away with
`ExitBootServices`. Serial at `0x3F8` again, plus the framebuffer whose geometry
was copied out of GOP before the handover, at `KC_FG` `0x00C8C8C8` on `KC_BG`
black, with `KC_HI` and `KC_ERR` for bring-up lines and traps.

System calls run with interrupts on, so two tasks can be part-way through
writing at once. What keeps them apart is a mutex, not a masked timer:

- `con_acquire` — test and set with interrupts off. If the lock is held by
  somebody else, set `T_WAITCON`, block, and `int VEC_SCHED`; on the way back,
  re-test. Re-entrant for the owner.
- `con_release` — clear the owner, wake **every** waiter. A premature wake costs
  one trip round `con_acquire` and nothing else.
- `con_release_if_owned` — called from `sys_exit` and `task_faulted`, because a
  task that dies holding the console would leave the others blocked forever.

The lock is held across a whole buffer, not per character: the point is that a
line arrives whole. This replaced a version that cleared `IF` for the whole
system call, where a three kilobyte write held the entire machine for a quarter
of a second ([PRINCIPLES §6](PRINCIPLES.md)).

### 7.8 The keyboard driver

Interrupt-driven, unlike the firmware's poller, and that is what lets it see
break codes and therefore track shift.

`kbd_init` does three things, and the order is the whole of it. It
read-modify-writes the command byte — setting translation (`0x40`) and the
keyboard interrupt (`0x01`), clearing the interface-off bit (`AND 0xEF`), and
touching nothing else, since a byte written from scratch would be a guess about
the mouse, the clock and the self-test. Then it drains whatever is already in
the output buffer, up to `KBD_DRAIN_MAX` = 64 bytes, because the controller
asserts its interrupt when a byte *arrives* and not while one is waiting — so a
byte already sitting there, the reply to that command included, would be
delivered to nobody and hold up everything behind it. Only then is IRQ1
unmasked.

`isr_kbd` → `kbd_take` reads one byte, handles the `0xE0` extended prefix
by consuming and dropping the key, tracks `0x2A`/`0x36` press and release, and
enqueues a character from `kbd_lower`/`kbd_upper` — set 1, indexed up to
`KBD_TABLE_LEN` = `0x3A`, the space bar; nothing above that has a character.

The queue is 32 bytes with a mask for the wrap, deep enough to survive a burst
of typing while a task holds the console and no deeper: a queue that outlives
interest in its contents is a queue of stale keys. What does not fit is dropped.
`kbd_wait_write`/`kbd_wait_read` spin at most `KBD_WAIT_SPIN` = 100000 — a dead
controller must be a keyboard that never works, not a kernel that never boots.

A keystroke is delivered on the next tick, not immediately: the interrupt
queues the byte and makes the waiter runnable, then returns to whoever was
running. Up to 10 ms, which is invisible to a typist.

### 7.9 The kernel's own disk stack

Three drivers reimplemented because the firmware's went away with it
([PRINCIPLES §8](PRINCIPLES.md)).

| File | Scope | Notes |
| --- | --- | --- |
| [kata.asm](kernel/kata.asm) | primary master, polled PIO, LBA28, read only | drive select `0xE0`, `nIEN` set (`0x02`) so it never asks for an interrupt, `ATA_TIMEOUT` 2,000,000 spins, capacity from IDENTIFY word 60 |
| [kgpt.asm](kernel/kgpt.asm) | GPT only, no MBR fallback | header at LBA 1, up to 128 entries of 128 bytes, ESP type GUID as in §6.1 |
| [kfat.asm](kernel/kfat.asm) | FAT32, short names, read only | `kbuf_cluster` holds `KFAT_MAX_CLUS_SEC` = 64 sectors |

This is why `make ovmfk` uses the i440fx machine and not q35: the kernel drives
the legacy ATA ports itself, and q35's disk is behind AHCI.

### 7.10 The call sequence

The counterpart to §3.1, and it divides at the same place the kernel does.

```
kmain                             kernel.asm:118  RCX = ImageHandle, RDX = SystemTable
├─ LocateProtocol(GOP)                            framebuffer base, resolution, pitch
├─ configuration table walk                       the ACPI 2.0 GUID, kept as g_rsdp
├─ AllocatePages ×2                               page tables, then user windows
└─ ExitBootServices                               retried up to MAP_RETRIES times
   └─ kmain64                     kernel.asm:270  nothing exists but the machine
      ├─ kc_init                                  from the geometry saved above
      ├─ paging_build, then CR3                   the kernel's own space
      ├─ gdt_init                                 descriptors, TSS, RSP0
      ├─ idt_init                                 256 gates
      ├─ lapic_init, pic_init, pit_init           in that order — §7.5
      ├─ timer_check                              the tick is proved, not assumed
      ├─ kbd_init                                 translate, drain, unmask IRQ1
      ├─ syscall_init                             EFER.SCE, STAR, LSTAR, FMASK
      ├─ kata_init                                the primary master
      ├─ kgpt_find_esp                            GPT only, no MBR fallback
      ├─ kfat_mount
      ├─ kfat_lookup ×2                           \PROGS, then the program
      ├─ kfat_read_file                           straight into the window
      ├─ paging_build, task_create                once per task, in a loop
      └─ sched_run(tasks)                         iretq into task 0; never returns
```

Neither phase ever returns to the firmware, and they fail differently only in
which console is left to say so. Before the handover — no GOP, no memory map,
no memory, or `ExitBootServices` refusing `MAP_RETRIES` times — the message goes
out through the firmware's `ConOut` and the CPU halts where it stands. After it,
every failure prints on the kernel's own console and jumps to `khalt`: no disk,
no ESP, no filesystem, a program that does not fit its window, a program that
will not read. `khalt` is also where the scheduler ends up once every task has
ended, which is why `nothing left to run; halted` is the last line of a good
boot and not an error.

### 7.11 Module index

Register conventions are as the file headers give them. `kconst.inc` also
carries the macros the kernel is written in — `KSTR`, `kputs`, `kputsi`,
`PUSH_GPRS`, `POP_GPRS` — and includes `uabi.inc`, so the syscall numbers
arrive with the constants (§8).

**Bring-up**

| File | Entry points |
| --- | --- |
| [kernel.asm](kernel/kernel.asm) | `kmain`, `kmain64`, `khalt`; the PE headers, `WSTR`, `prog_names`, `g_st`/`g_bs`/`g_gop`/`g_rsdp`, `g_memmap`, `kstack` |
| [paging.asm](kernel/paging.asm) | `paging_build` (RDI = a `PT_PAGE_COUNT`-page region, RSI = the window to expose or 0 → RAX = a PML4, not loaded) |
| [gdt.asm](kernel/gdt.asm) | `gdt_init`; `gdt`, `gdt_ptr`, `tss` |
| [idt.asm](kernel/idt.asm) | `idt_init`, `isr_common`, `isr_timer`, `isr_resched`, `task_faulted`, `trap_put_name` (RAX = vector), `ISR_STUB`, `isr_stubs`, `trap_names` |
| [syscall.asm](kernel/syscall.asm) | `syscall_init`, `syscall_entry`, and `sys_write`, `sys_read`, `sys_ticks`, `sys_yield`, `sys_sleep`, `sys_uptime`, `sys_exit` — contracts in §8.2 |

**The console**

| File | Entry points |
| --- | --- |
| [kcon.asm](kernel/kcon.asm) | `kc_init`, `kc_clear`, `kc_putc` (AL → both sides), `kc_puts` (RSI), `kc_puthex` (RAX, ECX = digits) and `kc_puthex{8,16,64}`, `kc_putdec` (RAX, unsigned), `kfb_putc`, `kfb_scroll`, `kser_init`, `kser_putc`; the grid state `kc_x`/`kc_y`/`kc_cols`/`kc_rows` |

The console *lock* is not here: `con_acquire`, `con_release` and
`con_release_if_owned` live in `sched.asm` with the blocking they do (§7.7).

**Scheduling, and the hardware it runs on**

| File | Entry points |
| --- | --- |
| [sched.asm](kernel/sched.asm) | `lapic_init`, `pic_init`, `pit_init`, `io_wait`, `timer_check`; `task_create` (RDI = id, RSI = window, RDX = PML4, RCX = the neighbour's window), `sched_next` (→ RAX), `sched_run` (RAX = a task; never returns), `sched_park`, `sched_finished`, `sched_any_alive` (→ EAX), `sched_wake_due`, `kbd_wake_waiters`, `con_acquire`, `con_release`, `con_release_if_owned` (RAX = a task about to stop existing); the state `g_current`, `g_ticks`, `g_con_owner`, `tasks`, `tstacks` |

**Input**

| File | Entry points |
| --- | --- |
| [kbd.asm](kernel/kbd.asm) | `kbd_init`, `kbd_wait_write`, `kbd_wait_read` (→ EAX), `isr_kbd`, `kbd_take`, `kbd_enqueue` (AL), `kbd_dequeue` (RDI = destination, RSI = at most → RAX = how many; interrupts must be off, and the caller has already checked the buffer); `kbd_lower`/`kbd_upper`, `kbd_buf` |

**Storage** — scope and quirks in §7.9

| File | Entry points |
| --- | --- |
| [kata.asm](kernel/kata.asm) | `kata_init`, `kata_read` (RAX = first LBA, RDI = destination, ECX = sectors), `kata_read_one`, `kata_wait_idle`, `kata_wait_drq`, `kata_settle` |
| [kgpt.asm](kernel/kgpt.asm) | `kgpt_find_esp` (→ EAX = 1, with `g_esp_lba` and `g_esp_sectors` set) |
| [kfat.asm](kernel/kfat.asm) | `kfat_mount`, `kfat_lookup` (EAX = directory cluster, RSI = an eleven-byte 8.3 name → EAX = cluster or 0, RDX = size, CL = attributes), `kfat_read_file` (EAX = cluster, RDX = size, RDI = destination — whole clusters, so the destination must have room for the size rounded up to one), `kfat_cluster_lba`, `kfat_next`; `kbuf_sector`, `kbuf_fat`, `kbuf_gpt`, `kbuf_cluster` |

The `k` prefix is load-bearing as documentation and nothing else: the two images
are assembled separately, so `kfat_lookup` and `fat_lookup` could have shared a
name. They do not, because for the length of one boot both readers exist and
only one of them survives `ExitBootServices`, and a stack trace should say which
one is being read ([PRINCIPLES §8](PRINCIPLES.md)).

The keyboard is the exception, and it is worth knowing before grepping: `kbd_init`,
`kbd_wait_read` and `kbd_wait_write` are defined **twice in the tree** — once in
[src/efi_proto.asm](src/efi_proto.asm) and once in [kernel/kbd.asm](kernel/kbd.asm),
with different designs behind the same names (§7.8). Nothing breaks, since neither
image sees the other's source, but a search for `kbd_init` returns two unrelated
functions and only the line number says which.

---

## 8. The user ABI

[kernel/uabi.inc](kernel/uabi.inc) is included by the kernel **and** by every
program, so the numbers physically cannot drift apart
([PRINCIPLES §9](PRINCIPLES.md)).

### 8.1 Entry

A program is a flat binary: no headers, no relocations, entry at offset zero,
read straight into the window it will run in. So every reference in it must be
RIP-relative, and everything it knows about the machine it is told at entry:

| Register | At entry |
| --- | --- |
| `RDI` | its task id |
| `RSI` | its window base |
| `RDX` | its neighbour's window base — an address it is told and cannot reach |

`RSP` starts at the top of the window. `PROG_MAX_BYTES` is half the window
(1 MiB), because the program has to leave room for its own stack.

### 8.2 The call convention

Number in `EAX`, arguments in `RDI`, `RSI`, `RDX`, result in `RAX`. Clobbered:
`RCX` and `R11`, which `SYSCALL` itself takes, and `R10`, which the kernel uses
to find itself before it has a stack.

`FMASK` clears IF, TF and DF (`0x700`), so only the window between the first
instruction of `syscall_entry` and the stack becoming the kernel's is
uninterruptible. After `sti`, the rest of the call is preemptible like anything
else.

| # | Call | Arguments | Returns |
| --- | --- | --- | --- |
| 0 | `SYS_WRITE` | RDI = buffer, RSI = length | bytes written, or `SYS_EBADPTR` |
| 1 | `SYS_EXIT` | RDI = status | does not return |
| 2 | `SYS_TICKS` | — | the time stamp counter |
| 3 | `SYS_YIELD` | — | 0, after the rest of the slice is given away |
| 4 | `SYS_SLEEP` | RDI = milliseconds | 0. Rounded **up** to a whole tick, never zero ticks |
| 5 | `SYS_UPTIME` | — | timer ticks since boot |
| 6 | `SYS_READ` | RDI = buffer, RSI = length, RDX = timeout in ms, 0 = forever | bytes read; 0 if the wait ran out; `SYS_EBADPTR` |

`SYS_COUNT` is 7. Errors: `SYS_EBADPTR` = -1, `SYS_ENOSYS` = -2.

A read returns at least one byte unless the wait ran out, and never more than
were typed: it is not a promise to fill the buffer. Its deadline is computed
once, from the call, and not renewed by whatever wakes the task — otherwise a
stream of keys nobody asked for could hold a bounded wait open indefinitely.

Both pointer-taking calls check the buffer **once**, at the top, against
`[T_USER_BASE, T_USER_BASE + 2 MiB)` including the wrap case, and the loop
behind that check does not re-test per byte
([PRINCIPLES §3](PRINCIPLES.md)).

Dispatch is a chain of `cmp`s rather than a jump table, for the `org 0` reason
in §7.3.

### 8.3 ulib

[kernel/progs/ulib.inc](kernel/progs/ulib.inc) is assembled into each program:
there is no loader that could resolve a call between two images.

| Function | Contract |
| --- | --- |
| `u_write` | RDI = buffer, RSI = length → RAX |
| `u_read` | RDI = buffer, RSI = length, RDX = ms (0 = forever) → RAX |
| `u_exit` | RDI = status; spins if it somehow returns |
| `u_hex` | RAX = value, RDI = destination, ECX = digits — in place, over a placeholder in a message |
| `u_dec` | RAX = value, RDI = destination, ECX = digits — filled from the right, fixed width |

### 8.4 The five programs

| Task | Program | Ends by |
| --- | --- | --- |
| 0 | `\PROGS\MAZE.BIN` | `sys_exit` — never yields; every gap in its output is the timer taking it away mid-instruction |
| 1 | `\PROGS\COUNT.BIN` | executing `cli`, and being killed by the `#GP` that follows |
| 2 | `\PROGS\ROGUE.BIN` | `#PF` error 5, reading a neighbour's window directly, after being refused at the syscall boundary first |
| 3 | `\PROGS\TYPE.BIN` | `sys_exit`, after a keystroke or three seconds of silence |
| 4 | `\PROGS\LISP.BIN` | `sys_exit`, after its demo and a REPL that closes on Esc or five seconds of silence |

Adding one means touching `PROGS` and a rule in the `Makefile`, `prog_names` in
[kernel/kernel.asm](kernel/kernel.asm), `TASK_COUNT` in
[kernel/kconst.inc](kernel/kconst.inc), and a landmark in `tools/smoke.sh` —
the checklist is in [WORKFLOW.md §6](WORKFLOW.md).

---

## 9. Disk layout

`tools/mkesp.py` writes the partition table itself and leaves the filesystem to
`mtools`, pointed at the partition with its `@@offset` syntax.

```
LBA 0        protective MBR, one 0xEE entry
LBA 1        GPT header, revision 1.0, 92 bytes, CRC over itself zeroed
LBA 2..33    128 partition entries of 128 bytes
LBA 2048     the EFI system partition begins (1 MiB in)
...          FAT32, formatted by mformat -F, volume label ASMFW
last-33..-2  backup entry array
last         backup GPT header
```

Disk and partition GUIDs are fixed constants, so rebuilds are byte-identical
and diffing two images while debugging a reader is actually useful.

Files are placed by extension: `.efi` into `/EFI/BOOT/`, `.bin` into `/PROGS/`.
`\EFI\BOOT\BOOTX64.EFI` is
[the default boot path](https://wiki.osdev.org/UEFI) firmware looks for on
removable media, which is why both disks carry one under that exact name — the
payload on `esp.img`, the kernel on `kernel.img`.

---
## 10. The payload

[payload/hello.asm](payload/hello.asm) is a real UEFI application, and the only
functional test the firmware has. Everything else checks that a phase finished;
this checks that the protocols it published answer.

It is built by one `nasm -f bin` with **no include path**, so it cannot see
[src/efi.inc](src/efi.inc). The offsets it needs — `ST_CONOUT` `0x40`,
`ST_BOOTSERVICES` `0x60`, `ST_CONFIGTABLE` `0x70`, `TO_OUTPUTSTRING` `0x08`,
and the rest — are written out a second time at the top of its code section.
That duplication is the point: a payload that read the firmware's own header
would agree with the firmware about the ABI no matter what either of them got
wrong ([PRINCIPLES §2](PRINCIPLES.md)).

### 10.1 Its PE headers

Written by hand, and readable as the specification for what
[src/pe.asm](src/pe.asm) has to understand (§6.3).

| Field | Value | Why |
| --- | --- | --- |
| `Machine` | `0x8664` | |
| `NumberOfSections` | 1 | one `.text`, `0xE0000020` — code, read, write |
| `Characteristics` | `0x002E` | executable, symbols stripped, large address aware |
| `Magic` | `0x020B` | PE32+ |
| `AddressOfEntryPoint` | `efi_main` | an RVA, and with `org 0` also a file offset |
| `ImageBase` | `0x0000000140000000` | never where it lands, which is the interesting case |
| `SectionAlignment` | `0x1000` | |
| `FileAlignment` | `0x1000` | **equal** to `SectionAlignment` |
| `SizeOfImage` | `0x3000` | `TEXT_RVA` `0x1000` + `TEXT_SIZE` `0x2000` |
| `SizeOfHeaders` | `0x1000` | |
| `Subsystem` | 10 | EFI application |
| `NumberOfRvaAndSizes` | 16 | all sixteen directories zero — **no `.reloc`** |

The two decisions worth copying: file alignment equal to section alignment makes
file offset and RVA the same number, so one `org 0` describes both the file and
the loaded image and there is no offset arithmetic to get wrong. And there is no
relocation directory at all, because every reference is RIP-relative — which is
why `pe_load` accepts an image with no relocations at the wrong base unless it
sets `IMAGE_FILE_RELOCS_STRIPPED` (§6.3). Both images in this tree rely on that.

### 10.2 What it exercises, in order

Each step is a question with a wrong answer that would otherwise look fine.

| Step | Call | The assertion |
| --- | --- | --- |
| console | `ClearScreen`, `SetAttribute` `0x0E` then `0x07`, `OutputString` | the banner arrives at all; `SetAttribute` is exercised, though only the window shows whether it did anything — the transcript cannot carry colour |
| storage | `LocateProtocol(SFS)`, `OpenVolume`, `Open(\EFI\BOOT\BOOTX64.EFI)` | the path parser walks a real path, one separator at a time |
| storage | `Read` two bytes, compare against `0x5A4D` | **it reads itself back and finds `MZ`** — proof the read landed on the right cluster, not merely that it returned success |
| ACPI | the configuration table, then the XSDT | §10.3 |
| graphics | `LocateProtocol(GOP)`, then `draw_bar` | the framebuffer address in `Mode->FrameBufferBase` is one the CPU can actually write |
| input | `ReadKeyStroke`, polled | a *particular* key comes back, not merely a key |

Every one of them has a failure string as well as a success string — `no simple
file system protocol on this firmware`, `the file system is there but would not
read the file`, `no graphics output protocol on this firmware` — and the program
carries on to the next step rather than stopping. A run that fails one check
still reports the other five, which is what makes the transcript worth reading
after a change (§12).

It returns `EFI_SUCCESS` normally, landing in `image_exit_resume` (§3.1) and
producing `[BDS] image returned, status 0000000000000000`.

### 10.3 The ACPI walk

`show_acpi` is the part that tests the firmware hardest, because QEMU does not
hand over finished tables (§6.4): the cross-references are offsets and the
checksums are wrong until firmware runs `etc/table-loader`. Tables that were
never patched still look plausible.

1. Walk `SystemTable->ConfigurationTable`, `NumberOfTableEntries` of them at
   `CFG_ENTRY_SIZE` = 24 bytes, comparing GUIDs against ACPI 2.0
   `8868E871-E4F1-11D3-BC22-0080C73C8881`; the pointer is at `+16`.
2. Choose the root table: revision at `+15` ≥ 2 and a non-zero XSDT at `+24`
   means eight-byte entries, otherwise the RSDT at `+16` and four-byte ones.
   The XSDT wins where it exists, because it is the one that can describe a
   table above 4 GiB.
3. Entry count is `(length - SDT_HEADER_SIZE) / entry width`, the length read
   from `+4` of the root table's own header.
4. For each entry: `sig_to_str` prints the four signature bytes, and
   `sum_table` adds up `length` bytes and must get zero. A non-zero sum
   increments `g_acpi_bad`.

The verdict is one line: `every one of them checksums to zero`, or `at least one
of them has a bad checksum`. Reading every entry is what makes it an assertion
about the *pointers* too — an unpatched `ADD_POINTER` (§6.4) leaves an offset
where an address should be, and summing the table it points at faults or
returns nonsense rather than zero.

### 10.4 draw_bar, and the ConIn poll

`draw_bar` takes `FrameBufferBase`, `HorizontalResolution`,
`VerticalResolution` and `PixelsPerScanLine` out of `GOP->Mode`, multiplies the
last by four for a byte pitch, and paints `BAR_HEIGHT` = 48 rows sitting
`BAR_HEIGHT + 16` rows up from the bottom edge. The colour is
`x * 256 / width`, red climbing and blue falling with a constant `0x4000` of
green — a gradient rather than a fill, because a fill would look identical
whether the pitch was right or wrong.

The input step polls `ReadKeyStroke` `KEY_POLL_ROUNDS` = 300 times with
`Stall(KEY_POLL_US = 10000)` between them: three seconds, and then it gives up
by itself, so an unattended run still terminates. This replaced a three-second
stall that existed only for the look of it.

Two details in what it reports:

- A key with a zero `UnicodeChar` is a **real answer**, not a failure. The
  arrows and Esc report a scan code and no character (§4.4), so it prints `.`
  for the character and the scan code in hex beside it.
- Nothing typed at all prints `ConIn said EFI_NOT_READY throughout`, which is
  the assertion `tools/smoke.sh` actually makes — under `make check` there is no
  display, so QEMU has no keyboard to give it.

This was the last protocol nothing exercised, and it was wrong for a long time
because of it: a firmware that hands back the wrong letter is indistinguishable
from one that works until somebody asks for a particular key
([PRINCIPLES §7](PRINCIPLES.md)).

### 10.5 The strings are the interface

The payload has no return value anybody reads and no log of its own. Its output
*is* its result, so the `WSTR` table at the bottom of the file is effectively
its API, and six of those strings are assertions in `tools/smoke.sh`:

| String | Means |
| --- | --- |
| `hello from a hand-assembled UEFI application` | the image was loaded, relocated if needed, and entered |
| `read myself back off the file system; still a PE image` | SFS, File, and the path parser all work |
| `ACPI tables: ` + signatures | the XSDT was walkable |
| `every one of them checksums to zero` | the loader script ran |
| `graphics output protocol located; drawing` | GOP answers |
| `ConIn` (either branch) | text input answers |

`s_key` is built out by hand rather than with `WSTR`, because two fields inside
it — the character and four hex digits of scan code — are written at run time
and a label has to be able to name them.

---

## 11. The build tools

Two generators, both Python, both run by the `Makefile`. Neither is on the boot
path, which is why they are allowed to be in Python at all.

### 11.1 mkesp.py

`mkesp.py <image> <payload-dir> [size-mib]`, default 64 MiB. It writes the
partition table itself and leaves the filesystem to `mtools`, pointed at the
partition with `@@offset` (§9).

| Constant | Value |
| --- | --- |
| `SECTOR` | 512 |
| `ENTRY_SIZE` × `ENTRY_COUNT` | 128 × 128, so `ENTRY_SECTORS` = 32 |
| `PART_START` | 2048, one MiB in |
| `ESP_TYPE` | `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` |

Derived: `first_usable` = 34, `last_usable` = `total - 34`, and the partition
runs from `PART_START` to `last_usable` inclusive.

What it writes, in order: the protective MBR at LBA 0 (one `0xEE` entry, CHS
fields cosmetic, `0x55AA`), the primary GPT header at LBA 1, the entry array at
LBA 2, a second copy of the array at `total - 33`, and the backup header at
`total - 1`. Both headers are the same 92 bytes with `MyLBA` and `AlternateLBA`
swapped, the header CRC taken last over the header with its own CRC field
zeroed.

Then `mformat -F -v ASMFW -T <sectors> -h 64 -s 32`, three `mmd` calls for
`/EFI`, `/EFI/BOOT` and `/PROGS`, and one `mcopy` per file — routed by
extension, `.efi` to `/EFI/BOOT/` and `.bin` to `/PROGS/`, anything else
ignored. `MTOOLS_SKIP_CHECK=1` is set for all of them, because mtools objects to
a geometry it did not choose.

Three things in it are load-bearing and easy to undo:

- **The GUIDs are fixed constants**, not `uuid4()`. Rebuilds are byte-identical,
  so diffing two images while debugging a reader is actually useful.
- **`e[56:56 + len(name)] = name`** — slice assignment on a `bytearray` *resizes*
  it when the lengths differ, so the end index has to come from the data and not
  from the field width. Written as `e[56:128]` the entry would silently shrink.
- **Copying nothing is a warning, not an error.** An empty disk builds fine and
  fails at boot, which is a worse place to find out; the warning goes to stderr
  and the summary line names the file count.

### 11.2 mkfont.py

Generates [src/font.inc](src/font.inc) on stdout. Note which way round the
dependency goes: `font.inc` is a source file, matched by the `src/*.inc` wildcard
in `FW_SRCS`, so touching it rebuilds the firmware — but no rule *produces* it
from `mkfont.py`. A change to the art means running the tool by hand, redirecting
it over `font.inc`, and rebuilding everything ([WORKFLOW §1](WORKFLOW.md)).

Each glyph is written as slash-separated rows of `#` and `.`, exactly `W` = 6
wide, starting at cell row `BODY_TOP` = 1. The tool places them at columns 1..6
of an 8-wide cell, so adjacent glyphs never touch and column 0 and 7 are the
letter spacing. The 16-row cell is divided:

| Rows | Use |
| --- | --- |
| 0 | blank — line spacing |
| 1..11 | cap height, baseline at 11 |
| 5..11 | x-height |
| 12..14 | descenders |
| 15 | blank |

Output is `FONT_W` 8, `FONT_H` 16, `FONT_FIRST` `0x20`, `FONT_LAST` `0x7E`, and
`font8x16`: 95 cells of 16 bytes, bit 7 the leftmost pixel, one `db` line per
character with the character named in a trailing comment. Both consoles index it
the same way — `(c - FONT_FIRST) * FONT_H` — and the kernel's `kcon.asm` takes
this one file from the firmware's tree and nothing else (§1).

`mkfont.py show [chars]` prints the rendered cells to the terminal, sixteen to a
row, defaulting to the whole printable range. That is the only way to look at a
glyph without booting, and the reason the art lives in the tool rather than in
`font.inc`: a hand-edited hex table cannot be proofread.

---

## 12. Transcript landmarks

The serial transcript is the only test surface here, so the landmarks are the
assertions. `tools/smoke.sh` makes 47: 20 for the firmware and its payload, 22
for the kernel (21 required strings and one forbidden one), 5 for the OVMF
controls.

They are fixed strings, and the sequence matters more than the set: **the last
marker present names the phase that did not finish**. A change that makes the
machine say something new adds a landmark; a change that makes it say something
different updates the one it broke, in the same commit
([WORKFLOW.md §3](WORKFLOW.md)).

Firmware, in order: `[SEC]`, `[PEI]`, `[DXE] PCI`, `[DXE] GOP: 1024x768x32`,
`[DXE] ATA:`, `kbd   i8042 translation on, set 1 codes`,
`[DXE] EFI tables built`, `[DXE] ACPI: 4 tables`, `[DXE] done`, `[BDS]` ×4,
then the payload's own lines and `[BDS] image returned, status 0000000000000000`.

Kernel, in order: `paging`, `gdt`, `idt      256 vectors`,
`timer    8254 at 100 Hz on vector 32, ticking`, `kbd      i8042 on vector 33`,
`syscall  lstar armed; sysret will enter cs 002b`, four `task N  window` lines,
then the four endings — `solved:` and task 0's exit, task 1's eight lines and
`trap 13 (#GP )`, task 2's two refusals, task 3's keystroke or silence — and
`every task has ended` / `nothing left to run; halted`.

Denied outright: `cs 0008`, a trap taken in ring 0.

Not asserted, because they differ run to run: tick counts, the maze itself, and
load addresses.

---

## 13. Conventions

**`default rel`, everywhere.** The volume is assembled at `0xFFF00000`, and a
64-bit absolute `disp32` sign-extends — `[label]` would address
`0xFFFFFFFFFFF00000`. Every 64-bit reference is RIP-relative; the handful that
genuinely are low absolute addresses are written `[abs ...]` so they stand out.
The three `-w-reloc-abs-*` suppressions in the `Makefile` exist for exactly
this, and a fourth needs a comment saying which idiom produced it.

**`org 0` in the kernel and the programs.** A stored label is a file offset,
not an address. Hence: the IDT addressing vector *N* by arithmetic, the syscall
dispatch as a chain of comparisons, trap names as a fixed-width table indexed
rather than a table of pointers, and program names as eleven-byte records.

**Fixed-size jumps in the string macros.** `putsi` and `kputsi` pin their jump
to five bytes with `strict near`. Left to shrink, it moves every label behind it
and the assembler's passes stop converging.

**No numeric literals.** `const.inc` for the firmware, `kconst.inc` for the
kernel, `uabi.inc` for what they share; `0`, `1` and `-1` as indices or steps
are the only exceptions.

**Unimplemented means a function.** Never a null pointer. A caller gets
`EFI_UNSUPPORTED` instead of a fault.

**Turning an address back into a line.** `build/fw.lst` is written by every
firmware build, at final addresses. The kernel has no listing by default; make
one and subtract the load base the firmware printed. `cs 002b` in a trap frame
is ring 3, so the offset is `rip - window`; `cs 0008` is the kernel, so it is
`rip - image base`. Commands in [WORKFLOW.md §5](WORKFLOW.md).

---

## 14. External references

**UEFI**

- [UEFI Specification 2.10 §4, EFI System Table](https://uefi.org/specs/UEFI/2.10/04_EFI_System_Table.html) — table headers, signatures, the CRC32 rule, boot and runtime service prototypes
- [UEFI Specification 2.10 §5, GPT disk layout](https://uefi.org/specs/UEFI/2.10/05_GUID_Partition_Table_Format.html) — header fields, entry array, the ESP type GUID
- [UEFI Specification 2.10, full PDF](https://uefi.org/sites/default/files/resources/UEFI_Spec_2_10_Aug29.pdf)
- [UEFI booting and the default path](https://wiki.osdev.org/UEFI) — `\EFI\BOOT\BOOTX64.EFI`
- [PE base relocations](https://0xrick.github.io/win-internals/pe7/) — block format, `IMAGE_REL_BASED_DIR64`
- [shim's pe-relocate.c](https://github.com/rhboot/shim/blob/main/pe-relocate.c) — a second implementation of the same loop, worth comparing against

**x86**

- [SYSCALL — Fast System Call](https://hjlebbink.github.io/x86doc/html/SYSCALL.html) — `IA32_STAR`/`LSTAR`/`FMASK`, and the selector arithmetic the GDT order obeys
- [Intel SDM Vol. 3, fast system calls](https://xem.github.io/minix86/manual/intel-x86-and-64-manual-vol3/o_fe12b1e2a880e0ce-1226.html)
- [APIC](https://wiki.osdev.org/APIC) — the LVT, LINT0 as ExtINT, virtual wire mode, the spurious vector enable bit
- [QEMU's apic.c](https://github.com/qemu/qemu/blob/master/hw/intc/apic.c) — `apic_accept_pic_intr`, which is where the LINT0 requirement is actually decided
- [Programmable Interval Timer](https://wiki.osdev.org/Programmable_Interval_Timer) — control word `0x34`, mode 2, the 1193182 Hz input
- [8042 PS/2 controller](https://wiki.osdev.org/%228042%22_PS/2_Controller) — the command byte, and bit 6 as translation
- [PS/2 keyboard](https://wiki.osdev.org/PS/2_Keyboard) — scan code sets, and why set 2 is what actually arrives

**QEMU**

- [fw_cfg device](https://www.qemu.org/docs/master/specs/fw_cfg.html) — ports `0x510`/`0x511`, the signature key, `FW_CFG_FILE_DIR` at `0x19`, the `FWCfgFile` layout
- [Bochs VBE extensions](https://wiki.osdev.org/Bochs_VBE_Extensions) — the `0x1CE`/`0x1CF` register pair, the ID values, `VBE_DISPI_LFB_ENABLED`
- [bochs-vbe.h](https://github.com/qemu/qemu/blob/master/include/hw/display/bochs-vbe.h) — the same constants as QEMU defines them

**ACPI**

- [ACPI Specification](https://uefi.org/specs/ACPI/6.5/) — the RSDP, XSDT, and the SDT header this firmware re-checksums

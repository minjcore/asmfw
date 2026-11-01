# kernel.asm
[`kernel/kernel.asm`](../../../../kernel/kernel.asm) — 554 dòng, 3 entry point.

A kernel that asmfw boots, and that gets to ring 3.

It is a UEFI application in the same sense payload/hello.asm is: hand-written PE32+ headers, one flat binary, no linker.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `kmain` | [118](../../../../kernel/kernel.asm#L118) | — |
| `kmain64` | [270](../../../../kernel/kernel.asm#L270) | — |
| `khalt` | [479](../../../../kernel/kernel.asm#L479) | — |

## Định nghĩa

Macro: `WSTR`

Hằng số: 6.

Dữ liệu và state: `pe_signature`, `opt_start`, `opt_end`, `name_progs`, `prog_names`, `gop_guid`, `acpi20_guid`, `g_image`, `g_st`, `g_bs`, `g_conout`, `g_gop`, `g_rsdp`, `g_pt_base`, `g_user_raw`, `g_user_base`, `g_map_size`, `g_map_key`, và 6 nữa

## Phụ thuộc

Gọi vào:

- [gdt.asm](gdt.md) — `gdt_init`
- [idt.asm](idt.md) — `idt_init`
- [kata.asm](kata.md) — `kata_init`
- [kbd.asm](kbd.md) — `kbd_init`
- [kcon.asm](kcon.md) — `kc_init`, `kc_putc`, `kc_putdec`, `kc_puthex16`, `kc_puthex64`
- [kfat.asm](kfat.md) — `kfat_lookup`, `kfat_mount`, `kfat_read_file`
- [kgpt.asm](kgpt.md) — `kgpt_find_esp`
- [paging.asm](paging.md) — `paging_build`
- [sched.asm](sched.md) — `lapic_init`, `pic_init`, `pit_init`, `sched_run`, `task_create`, `timer_check`
- [syscall.asm](syscall.md) — `syscall_init`

Bị gọi bởi:

- [sched.asm](sched.md) — `khalt`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

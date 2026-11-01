# mem.asm
[`src/mem.asm`](../../../../src/mem.asm) — 258 dòng, 3 entry point.

The page allocator behind AllocatePages, and the memory map.

A bump allocator. Nothing is ever freed, which is a real limitation and a deliberate one: this firmware allocates a handful of times, loads one image and leaves. A free list would be more code with no user. Every allocation is recorded so that GetMemoryMap can describe it with the memory type the caller asked for.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `mem_alloc_pages` | [59](../../../../src/mem.asm#L59) | RCX = page count, EDX = EFI memory type. Returns RAX = base address, or 0 if the heap is exhausted. |
| `mem_alloc_pool` | [112](../../../../src/mem.asm#L112) | RCX = byte count, EDX = EFI memory type. Returns RAX = base, or 0. Pool allocations come out of the same bump heap rounded to whole pages. Wasteful per call, and irrelevant at the handful of calls this sees. |
| `mem_build_map` | [127](../../../../src/mem.asm#L127) | write the current memory map into MEMMAP_SCRATCH. Returns EAX = number of descriptors written. The descriptors come out in ascending address order, which the spec does not require but every consumer is happier with. |

## Định nghĩa

Hằng số: 13.

## Phụ thuộc

Bị gọi bởi:

- [acpi.asm](acpi.md) — `mem_alloc_pages`
- [efi_bs.asm](efi_bs.md) — `mem_alloc_pages`, `mem_alloc_pool`, `mem_build_map`
- [efi_file.asm](efi_file.md) — `mem_alloc_pool`
- [efi_proto.asm](efi_proto.md) — `mem_alloc_pool`
- [efi_var.asm](efi_var.md) — `mem_alloc_pages`
- [init64.asm](init64.md) — `mem_alloc_pages`
- [pe.asm](pe.md) — `mem_alloc_pages`
- [smbios.asm](smbios.md) — `mem_alloc_pages`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

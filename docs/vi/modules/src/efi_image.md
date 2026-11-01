# efi_image.asm
[`src/efi_image.asm`](../../../../src/efi_image.asm) — 274 dòng, 6 entry point.

LoadImage, StartImage, UnloadImage, and where Exit returns.

An image loaded by another image. BDS starts the first one itself; these are how that one starts the next — a boot manager starting a loader, a shim starting GRUB.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `image_record` | [44](../../../../src/efi_image.asm#L44) | RCX = a handle. Returns RAX = its record if it is one of IMAGE_TABLE's and in use, otherwise 0. |
| `bs_load_image` | [69](../../../../src/efi_image.asm#L69) | LoadImage(BootPolicy, ParentImageHandle, DevicePath, SourceBuffer, SourceSize, ImageHandle). Only from a buffer. Loading by device path alone would mean resolving the path to a file on a device, and this firmware has one device and loaders that read their own files; with no buffer the answer is EFI_NOT_FOUND, which is what the specification says when there is nothing to load. |
| `bs_start_image` | [167](../../../../src/efi_image.asm#L167) | StartImage(ImageHandle, ExitDataSize, ExitData). Returns whatever the image returned, or passed to Exit(). |
| `image_start_resume` | [219](../../../../src/efi_image.asm#L219) | RAX = the status. Where a return from the entry point and a call to Exit() both arrive. Nothing is assumed of the registers: the record comes from g_current_image, and the stack from the record. |
| `start_image_bad` | [248](../../../../src/efi_image.asm#L248) | StartImage's answer to a handle it cannot start. |
| `bs_unload_image` | [260](../../../../src/efi_image.asm#L260) | UnloadImage(ImageHandle). An image that is loaded and not running, or has finished, is retired. Its memory is not given back — nothing in this allocator ever is — and the record stays allocated so a stale handle cannot alias a new image. A running image would need its own Unload function, which none here registers. |

## Định nghĩa

Hằng số: 13.

## Phụ thuộc

Gọi vào:

- [efi_tables.asm](efi_tables.md) — `proto_add`
- [pe.asm](pe.md) — `pe_load`

Bị gọi bởi:

- [efi_bs.asm](efi_bs.md) — `image_record`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.

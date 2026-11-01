# Firmware: từ reset vector đến khi giao máy

File này giải thích firmware trong `src/` làm gì, theo đúng thứ tự nó làm, và vì
sao từng bước lại phải làm như vậy. Con số cụ thể (offset, giá trị thanh ghi) nằm
trong `REFERENCE.md`; ở đây là *lý do*.

## Flash volume: hai đầu bị kiến trúc ghim chặt

Firmware là một file phẳng 1 MiB, được assemble tại đúng địa chỉ cuối cùng của nó.
QEMU map file này sao cho **byte cuối nằm ở `0xFFFFFFFF`**:

```
0xFFF00000   đầu volume            — phần thân 32/64-bit
0xFFFF0000   64 KiB cuối           — tất cả những gì real mode với tới được
0xFFFFFFF0   reset vector          — 16 byte, nơi CPU bắt đầu
0xFFFFFFFF   byte cuối
```

Hai đầu này không phải lựa chọn thiết kế, mà là ràng buộc của x86. Từ đó suy ra
hai hệ quả chi phối cả file `fw.asm`:

**Kích thước phải đúng 1048576 byte.** Không phải "ít nhất". Vì QEMU neo *đuôi*
file vào đỉnh không gian địa chỉ, một file sai kích thước không bị cắt cụt — nó
làm **reset vector dịch chỗ**, và CPU nhảy vào giữa hư không. `Makefile` kiểm tra
kích thước này và fail build nếu sai.

**Lệnh đầu tiên phải là jump near.** Lúc reset, `CS.base` = `0xFFFF0000` nhưng
thanh ghi `CS` đọc ra `0xF000` — một trạng thái ẩn không lệnh nào tái tạo lại
được. Một lệnh far jump sẽ nạp lại `CS` và **phá huỷ** cái base ẩn đó, tức là phá
luôn thứ duy nhất đang làm cho code này có địa chỉ. Đây cũng là lý do có macro
`rm()` trong `const.inc`: nó đổi một label tuyến tính thành offset tương đối so
với `CS`.

Phần đệm của volume là `0xFF` — trạng thái đã xoá của flash thật.

## Bốn phase

Tên phase lấy theo chuẩn UEFI, và chúng in ra log đúng như vậy.

### SEC — thoát khỏi real mode càng nhanh càng tốt

Hai file, và chúng là **toàn bộ** code 16-bit và 32-bit trong dự án:

- `init16.asm` — bật A20 qua port `0x92`, nạp một GDT phẳng, bật `CR0.PE`. File
  này buộc phải nằm trong 64 KiB cuối, vì đó là tất cả những gì lệnh jump near
  của reset vector với tới. Assembler kiểm tra điều này bằng một lệnh `times`, và
  nếu file phình ra quá thì build fail với `TIMES value is negative`.
- `init32.asm` — dựng identity map cho 4 GiB thấp bằng page 2 MiB, bật `EFER.LME`
  và `CR0.PG`.

Dùng page 2 MiB thay vì 1 GiB là có chủ ý: page 1 GiB phụ thuộc
`CPUID.80000001:EDX.PDPE1GB`, mà `-cpu qemu64` mặc định không quảng cáo bit đó.

Vào long mode xong thì mọi thứ còn lại là 64-bit. Đó là quyết định đơn giản hoá
lớn nhất của dự án.

### PEI — biết máy có bao nhiêu RAM

`pei_main` đọc dung lượng RAM từ CMOS (`0x34`/`0x35`, nếu không có thì
`0x30`/`0x31`) rồi dựng page allocator.

Allocator là một **con trỏ bump**, bắt đầu từ `0x01000000`. Nếu máy có dưới 64
MiB, firmware panic ngay ở PEI thay vì chết mơ hồ ở đâu đó về sau. Thà fail sớm
và nói rõ lý do.

Vì firmware chạy từ ROM, **mọi byte có thể ghi đều phải ở RAM**, tại một địa chỉ
mà chính nó tự chọn. Macro `GVAR` trong `const.inc` chia khu vực `0x00100000` ra
thành các biến toàn cục ngay lúc assemble. Đây là lý do file `const.inc` trông
giống một bản đồ bộ nhớ hơn là một file hằng số.

### DXE — biến máy trần thành máy dùng được

Đây là phase dài nhất. Thứ tự các bước **không tuỳ ý**:

```
pci_assign_resources    gán địa chỉ cho mọi BAR trên bus 0
gfx_init                Bochs VBE + dựng text console trên framebuffer
ata_init                IDENTIFY ổ primary master
kbd_init                bật translation của i8042
efi_init                dựng các bảng, công bố protocol, tính CRC
acpi_init               chạy script table-loader, công bố RSDP
```

Ba ràng buộc thứ tự đáng nhớ:

- **`kbd_init` trước `efi_init`**, để `ConIn` không bao giờ được công bố khi
  controller chưa được cấu hình để sinh ra thứ mà nó hứa cung cấp.
- **`acpi_init` sau `efi_init`**, vì cài một configuration table là ghi vào
  System Table — mà bảng đó chưa tồn tại trước `efi_init`.
- **`pci_assign_resources` trước mọi thứ khác**, vì trước nó thì không thiết bị
  nào có địa chỉ.

#### Ba chỗ đáng kể ở DXE

**PCI: BAR đọc ra bằng 0.** Trên QEMU, mọi BAR đều rỗng lúc reset. Gán chúng là
việc của firmware và không của ai khác. `pci_assign_resources` đo kích thước từng
BAR bằng cách ghi toàn bit 1 rồi đọc lại, rồi đặt nó ở địa chỉ đúng alignment —
MMIO từ `0xC0000000` lên, I/O từ `0xC000`. Trong lúc BAR đang dịch chỗ, firmware
**tắt decode** của thiết bị, để một địa chỉ ghi nửa vời không thể chiếm mất cửa
sổ của thiết bị khác.

**Đồ hoạ: mode không đủ để có hình.** Không có INT 10h để gọi, nên mode được
lập trình trực tiếp qua cặp thanh ghi "dispi" của Bochs VBE (`0x1CE`/`0x1CF`).
Nhưng sau khi đặt mode xong màn hình **vẫn tối**: bit palette-address-source của
VGA attribute controller mặc định bằng 0 và nó chặn hiển thị. `vga_unblank` ghi
`0xE3` vào `0x3C2`, đọc `0x3DA` để đưa attribute controller về pha index, rồi ghi
`0x20` vào `0x3C0`. Trên PC thường, video option ROM làm việc này; ở đây không có
option ROM.

**ACPI: QEMU không đưa bảng hoàn chỉnh.** Nó đưa các blob, cộng thêm một script
`etc/table-loader` gồm các lệnh 128 byte nói: nạp blob nào vào đâu, con trỏ nào
bên trong cần patch khi đã biết địa chỉ, và checksum nào cần tính lại sau đó.

| Lệnh | Firmware làm gì |
| --- | --- |
| `ALLOCATE` | tải blob vào bộ nhớ mới đúng alignment, ghi lại nó nằm ở đâu |
| `ADD_POINTER` | biến một offset bên trong blob thành địa chỉ tuyệt đối của blob khác |
| `ADD_CHECKSUM` | tính lại tổng của một vùng *sau khi* các con trỏ đã được patch |
| `WRITE_POINTER` | bỏ qua — nó ghi trở lại vào fw_cfg, chỉ liên quan tới tính năng firmware này không có |

Điểm quan trọng: firmware **tải blob mà bỏ qua script** vẫn tạo ra được các bảng
trông rất hợp lý — chỉ có điều mọi cross-reference bằng 0 và mọi checksum sai.
Đây chính là lý do payload không chỉ báo "có bảng ACPI" mà đi **tính tổng từng
bảng**. Xem [chuong-trinh.md](chuong-trinh.md).

### BDS — tìm cái gì để boot, rồi boot nó

```
part_find_esp        GPT, rồi mới tới MBR type 0xEF
fat_mount            + efi_publish_volume
fat_lookup ×3        EFI, BOOT, BOOTX64.EFI
mem_alloc_pages      + fat_read_file
pe_load              nạp PE32+ vào EfiLoaderCode
bds_publish_image    công bố LoadedImage
call [g_img_entry]   RCX = ImageHandle, RDX = SystemTable
```

`efi_publish_volume` được tách riêng khỏi `efi_init` và chạy ở BDS, vì **mount
partition nào là quyết định về chính sách boot, không phải về thiết bị**.

Nếu GPT header không hợp lệ, firmware lùi về đọc bảng MBR ở offset 446 và lấy
partition đầu tiên có type `0xEF`. Nhưng một GPT **hợp lệ mà không có ESP** thì
*không* phải trường hợp fallback — nó dừng luôn, vì quét MBR trên đĩa đó chỉ tìm
thấy đúng cái protective entry.

Khi image trả về (hoặc gọi `Exit()`), luồng rơi vào `image_exit_resume`, và
firmware in `[BDS] image returned, status ...` rồi halt.

## Lớp EFI

Firmware này hiện thực **những gì một boot loader thật sự gọi**, không hơn.

- **Boot Services**: cấp phát bộ nhớ (`AllocatePages` với cả ba loại allocation,
  `AllocatePool`, `GetMemoryMap`), tra protocol (`HandleProtocol`,
  `LocateProtocol`, `OpenProtocol`, `LocateHandle`, `LocateHandleBuffer`), ba lệnh
  event mà `ConIn` cần, cộng `InstallConfigurationTable`, `Stall`, `CopyMem`,
  `SetMem`, `CalculateCrc32`, `Exit`, `ExitBootServices`.
- **Runtime Services**: `GetTime` đọc RTC thật, `ResetSystem` reset thật. Variable
  store báo rỗng, vì không có store nào.
- **Protocol công bố**: Simple Text Output (đầy đủ, kể cả `SetAttribute`), Simple
  Text Input, Graphics Output (một mode, `Blt` đủ bốn phép), Simple File System,
  File, Block I/O, Loaded Image.

Một quy ước xuyên suốt, và nó đáng để bắt chước:

> **"Chưa hiện thực" là một hàm, không bao giờ là con trỏ null.**

Mọi service chưa làm đều trỏ tới `bs_unsupported` — một hàm thật, trả về
`EFI_UNSUPPORTED`. Người gọi nhận được một status code, không phải một cú fault.
Khác biệt giữa hai điều đó là khác biệt giữa "loader báo lỗi và thoát đẹp" và
"máy chết không rõ tại sao".

## Vài quy ước trong code khiến người mới bối rối

**`default rel`, ở khắp mọi nơi.** Volume được assemble tại `0xFFF00000`, và một
`disp32` tuyệt đối trong chế độ 64-bit sẽ được **sign-extend** — nghĩa là
`[label]` sẽ trỏ tới `0xFFFFFFFFFFF00000`. Nên mọi tham chiếu 64-bit đều
RIP-relative; những chỗ *thật sự* là địa chỉ tuyệt đối thấp thì viết rõ
`[abs ...]` cho nổi bật. Ba flag `-w-reloc-abs-*` trong `Makefile` tồn tại chính
vì chuyện này.

**Không có số trần trong code.** `const.inc` cho firmware, `kconst.inc` cho
kernel, `uabi.inc` cho phần dùng chung. Ngoại lệ duy nhất là `0`, `1` và `-1` khi
dùng làm chỉ số hoặc bước nhảy. Lý do đơn giản: một con số viết trực tiếp trong
code là một con số **không ai grep được**.

**Jump cố định kích thước trong macro chuỗi.** `putsi` ghim lệnh jump của nó ở
đúng 5 byte bằng `strict near`. Nếu để assembler tự co lại, nó làm dịch mọi label
phía sau, và các pass của assembler không hội tụ.

## Bản đồ file

Chi tiết từng entry point, kèm số dòng và ai gọi ai, nằm ở
[modules/](modules/README.md) — một file cho mỗi module, sinh tự động từ source.
Ở đây chỉ là hình dung tổng thể theo lớp:

```
init64.asm            chuỗi phase, gọi mọi thứ
efi_*.asm             bề mặt EFI (bảng, boot/runtime services, protocol, file)
acpi pe fat gpt       các định dạng phải đọc
pci vbe ata timer     các thiết bị
util.asm              nguyên thuỷ console + bộ nhớ  ← 11 file gọi tới đây
serial console        hai đường ra
```

Không có gì gọi lên trên, trừ đúng một ngoại lệ có chủ ý: `efi_bs.asm` gọi
`image_exit_resume` trong `init64.asm`, vì `Exit()` buộc phải unwind về chỗ đã
khởi động image.

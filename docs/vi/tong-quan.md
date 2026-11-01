# Tổng quan: dự án này là gì

`asmfw` là một **UEFI firmware viết hoàn toàn bằng assembly**, cộng thêm một
**kernel** mà chính firmware đó boot lên. Không C, không linker, không EDK II.
Một lệnh `nasm` duy nhất tạo ra file flash 1 MiB.

Nói cho dễ hình dung: khi bạn bấm nút nguồn một chiếc máy tính, thứ chạy đầu tiên
không phải Windows hay Linux — mà là firmware (ngày xưa gọi là BIOS). Nó có nhiệm
vụ biến một khối silicon chưa được cấu hình gì thành một cái máy dùng được, rồi
mới giao lại cho hệ điều hành. Dự án này viết lại phần firmware đó từ số không,
và để chứng minh nó thật sự hoạt động, viết thêm một kernel nhỏ chạy trên nó.

## Hai nửa của dự án

Đây là chỗ dễ nhầm nhất khi mới đọc, nên nói rõ ngay:

| | `src/` — firmware | `kernel/` — kernel |
| --- | --- | --- |
| Nó là gì | firmware, nằm trong flash ROM | một ứng dụng UEFI, nằm trên đĩa |
| Ai chạy nó | CPU, ngay khi reset | firmware boot nó lên |
| Chạy ở đâu | `0xFFF00000`, địa chỉ cố định | bất cứ đâu firmware nạp nó vào |
| Tồn tại bao lâu | đến khi tắt máy | chiếm luôn cả cái máy |
| Sản phẩm | `build/FIRMWARE.fd` | `build/kernel.img` |

Firmware và kernel **không chia sẻ code** với nhau (trừ đúng một file font). Đây
không phải sự trùng lặp do cẩu thả — mà là điều bắt buộc, và [phần kernel](kernel.md)
sẽ giải thích tại sao.

## Chạy thử

```
make          # build firmware + đĩa test
make run      # boot trong QEMU, có cửa sổ đồ hoạ
make serial   # boot không màn hình, chỉ log qua serial
make ovmf     # boot cùng cái đĩa đó bằng OVMF thật, để đối chiếu

make kernel   # build kernel + đĩa riêng của nó
make runk     # boot kernel, có cửa sổ
make serialk  # boot kernel, chỉ serial

make check    # boot cả hai đĩa + hai control, rồi assert log
```

Lưu ý: **không có gì tự thoát QEMU**. Firmware halt, kernel halt — đều là cố ý —
nên `make serial` sẽ treo ở đó mãi. Xem [kiem-thu.md](kiem-thu.md) để biết cách
chạy có timeout.

## Luồng boot, từ đầu đến cuối

Đây là toàn bộ câu chuyện. Chi tiết từng phần ở [firmware.md](firmware.md) và
[kernel.md](kernel.md).

```
CPU reset
   │  CS.base = 0xFFFF0000, chỉ 64 KiB cuối của flash là đọc được
   ▼
0xFFFFFFF0  reset vector — 16 byte, một lệnh jump near
   │
   ▼
SEC   real mode:  bật A20, nạp một GDT phẳng, vào protected mode
      32-bit:     map identity 4 GiB thấp bằng page 2 MiB, vào long mode
   │
   ▼
PEI   đo dung lượng RAM từ CMOS, dựng page allocator
   │
   ▼
DXE   gán địa chỉ cho mọi PCI BAR trên máy
      đặt mode 1024x768x32, vẽ một text console vào framebuffer
      dò ổ ATA primary master
      bảo keyboard controller dịch scan code sang set 1
      dựng EFI System Table, Boot Services, Runtime Services
      chạy script ACPI của QEMU rồi công bố RSDP
   │
   ▼
BDS   tìm EFI system partition (GPT, hoặc MBR type 0xEF)
      mount FAT32, đi tới \EFI\BOOT\BOOTX64.EFI
      nạp file PE32+, áp base relocation
      gọi entry point với (ImageHandle, SystemTable)
   │
   ├──▶ payload/hello.asm    — một ứng dụng UEFI, chạy rồi trả về
   │
   └──▶ kernel/kernel.asm    — gọi ExitBootServices và không bao giờ quay lại
              │
              ▼
        tự dựng page table, GDT, TSS, IDT, PIC, PIT, keyboard, SYSCALL
        đọc 4 program từ đĩa bằng driver ATA/GPT/FAT32 của chính nó
        iretq vào ring 3 — năm task chạy round robin
```

Bốn cụm chữ `SEC`, `PEI`, `DXE`, `BDS` là tên các phase theo chuẩn UEFI. Chúng
xuất hiện đúng như vậy trong log serial, nên khi có lỗi, **cái nhãn cuối cùng bạn
thấy chính là phase không hoàn thành**.

## Tại sao "không có gì sẵn sàng cả"

Nguyên tắc số một của dự án (xem `PRINCIPLES.md`) là: mặc định mọi thứ trên máy
đều **chưa** được cấu hình. Vài ví dụ cụ thể, vì chúng giải thích rất nhiều đoạn
code trông có vẻ lạ:

- Ngay lúc reset, `CS.base` là `0xFFFF0000` nhưng thanh ghi `CS` lại đọc ra
  `0xF000`. Đây là một trạng thái ẩn mà **không lệnh far jump nào tái tạo được**.
  Vì thế lệnh đầu tiên buộc phải là jump near — dùng far jump là mất địa chỉ và
  chết ngay.
- Mọi **PCI BAR** trên máy đọc ra đều bằng 0. Framebuffer *không tồn tại* cho đến
  khi hàm `pci_assign_resources` được viết ra và gán địa chỉ cho nó.
- Đặt được VBE mode vẫn **chưa đủ để có hình**. Bit "palette address source" của
  VGA attribute controller vẫn đang chặn màn hình, và nó mặc định bằng 0. Trên PC
  thường thì video option ROM bật bit này; ở đây không có option ROM nào cả.
- Keyboard controller mặc định **không** dịch scan code. Bàn phím PS/2 gửi set 2,
  mọi OS lại giải mã set 1, và bit 6 trong command byte của i8042 là thứ dịch cái
  này sang cái kia. Thiếu nó, code không crash — nó chỉ trả về **sai chữ**, mà
  vẫn hợp lý.

Điểm chung: những lỗi này không làm máy chết. Chúng làm máy chạy *gần đúng*, và
đó là loại lỗi khó tìm nhất.

## Giới hạn — nói thẳng

Phần này quan trọng, vì nó là thứ làm cho những phần còn lại đáng tin.

- **Chỉ chạy trên QEMU.** Firmware giả định RAM hoạt động ngay lúc reset. Trên
  máy thật thì không: memory controller phải được "train" trước, và trên mọi nền
  tảng Intel sau Ivy Bridge, code làm việc đó chỉ tồn tại dưới dạng blob FSP đóng
  của Intel. Đây chính là lý do coreboot tồn tại, và cũng là lý do coreboot vẫn
  phải kèm blob. Muốn chạy trên bo mạch thật thì phải trở thành một coreboot
  payload, không phải flash trực tiếp cái này vào.
- **Không bao giờ giải phóng bộ nhớ.** `AllocatePages` là một con trỏ bump;
  `FreePages` và `FreePool` trả về thành công rồi không làm gì. Firmware cấp phát
  vài lần rồi giao máy đi, nên free list sẽ là thêm code mà không có ai dùng.
- **ACPI và SMBIOS đều lấy nguyên từ QEMU.** SMBIOS được đặt vào bộ nhớ, anchor
  được điền địa chỉ và tính lại checksum, rồi công bố dưới GUID SMBIOS hoặc
  SMBIOS3 tuỳ chữ ký. Không thêm structure nào: OVMF tự thêm type 0 khi QEMU
  không cấp, firmware này thì không, nên ít hơn OVMF một structure.
- **Không có `SetVirtualAddressMap`** — runtime services chỉ còn hợp lệ ở địa chỉ
  vật lý.
- **FAT32 chỉ đọc, chỉ tên ngắn 8.3.**
- **Không `LoadImage`/`StartImage`** — BDS nạp đúng một image mà nó boot.
- **Một ổ ATA duy nhất**, primary master, PIO, LBA28.
- **Biến UEFI nằm trong RAM** — 32 ô, mất khi reset; không có ghi có xác thực.
- **Không Secure Boot**, không setup UI.
- Phía kernel: round robin không ưu tiên, console chỉ text, một keystroke được
  giao ở tick tiếp theo chứ không tức thì (tối đa 10 ms).

Danh sách đầy đủ và chi tiết hơn nằm trong `README.md` ở gốc repo, mục
"Limitations, stated plainly".

## Đọc tiếp

| Muốn biết | Đọc |
| --- | --- |
| firmware làm gì ở từng phase | [firmware.md](firmware.md) |
| kernel làm gì sau `ExitBootServices` | [kernel.md](kernel.md) |
| payload và 4 program để làm gì | [chuong-trinh.md](chuong-trinh.md) |
| kiểm thử một cái máy đang reset bằng cách nào | [kiem-thu.md](kiem-thu.md) |
| con số cụ thể, offset, giá trị thanh ghi | `REFERENCE.md` (tiếng Anh) |

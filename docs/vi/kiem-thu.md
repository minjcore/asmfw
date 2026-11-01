# Kiểm thử một cái máy đang reset

Ở đây không có test framework, và **không thể có** theo nghĩa thông thường: đối
tượng đang được test là một cái máy ở trạng thái reset, và thứ duy nhất ở vị trí
quan sát được nó lại chính là code đang bị test.

Thứ thay thế test suite là **transcript serial**.

## Ý tưởng: landmark là assertion

Firmware và kernel in ra một chuỗi dòng cố định trên đường boot. `tools/smoke.sh`
boot máy dưới một timeout rồi kiểm tra transcript vẫn chứa đúng những dòng đó.

Điều quan trọng hơn cả tập hợp các dòng là **thứ tự** của chúng:

> **Landmark cuối cùng còn xuất hiện chính là tên của phase không hoàn thành.**

Nghĩa là khi có lỗi, bạn không phải đoán. Log dừng ở `[DXE] ATA:` thì mọi thứ
trước đó đã chạy xong và vấn đề nằm ở bước ngay sau.

## 51 assertion

```
make check          cả hai đĩa, rồi cả hai control        — 51 assertion
make check-fw       chỉ firmware và payload nó boot
make check-kernel   chỉ kernel
make check-docs     chỉ số dòng trong tài liệu module — `check` chạy nó đầu tiên
```

| Nhóm | Số assertion |
| --- | --- |
| firmware + payload | 23 |
| kernel | 22 (21 dòng bắt buộc có + 1 dòng bắt buộc **không** được có) |
| control OVMF | 6 |

Một assertion là **phủ định**: `cs 0008` trong một trap frame nghĩa là trap xảy
ra ở ring 0 — kernel tự sai, và không còn gì để giao lại. Nếu dòng đó xuất hiện
thì fail ngay, bất kể mọi dòng khác có đủ.

## Control: cách duy nhất phân biệt lỗi firmware với lỗi payload

Đây là phần đáng học nhất trong cách dự án này kiểm thử.

Một hiện thực đơn lẻ chỉ có thể so với **niềm tin của bạn về nó**. Hai hiện thực
thì so được với nhau.

Vì `payload/hello.asm` là ứng dụng UEFI thật, nó chạy được dưới OVMF — firmware
UEFI thật của EDK II. Từ đó:

| Chạy dưới OVMF | Chạy dưới asmfw | Kết luận |
| --- | --- | --- |
| ✅ | ❌ | lỗi ở **firmware** |
| ❌ | ❌ | lỗi ở **payload** |
| ✅ | ✅ | cả hai đồng ý — đây là điều ta muốn |

`make ovmf` chạy đúng phép so sánh đó cho payload, `make ovmfk` cho kernel. Cơ
chế này đã bắt được hai lỗi thật: một mảng partition GPT bị đọc thiếu, và một bộ
phân tích đường dẫn khởi động lại từ root ở mỗi dấu phân cách.

Và một câu cần nhớ: **một control bị skip không phải là một control đã pass.**
Nếu OVMF không có trên máy, `smoke.sh` in `skipped` — đó là thiếu thông tin, chứ
không phải tin tốt.

## Không có gì tự thoát QEMU

Firmware halt, kernel halt — **cả hai đều là cố ý**. Nên `make serial` sẽ ngồi đó
mãi, và bất cứ thứ gì tự động hoá quanh nó đều cần một timeout đặt lên chính
QEMU. Đây là điều `smoke.sh` làm, và làm bằng tay thì:

```sh
gtimeout 25 qemu-system-x86_64 -machine pc -m 256 -bios build/FIRMWARE.fd \
  -drive file=build/esp.img,format=raw,if=ide -no-reboot -display none -serial stdio

gtimeout 30 qemu-system-x86_64 -machine pc -m 256 -bios build/FIRMWARE.fd \
  -drive file=build/kernel.img,format=raw,if=ide -no-reboot -display none -serial stdio
```

(Trên macOS, GNU `timeout` được cài dưới tên `gtimeout` qua `brew install coreutils`.)

Một lần boot bị **giết trước khi landmark cuối cùng tới** là một lần fail.

## Build là bài test đầu tiên

`make` không chỉ là build. Ba invariant của dự án được assembler kiểm tra ở đó, và
mỗi lỗi có nghĩa rất cụ thể:

| Lỗi | Nghĩa là |
| --- | --- |
| `TIMES value is negative` tại `fw.asm:54` | phần thân firmware không còn nằm dưới `0xFFFF0000` — real-mode anchor đã bị tràn qua |
| `TIMES value is negative` tại `fw.asm:65` | `init16.asm` phình quá 64 KiB cuối, tức quá tầm với của lệnh jump near |
| `TIMES value is negative` tại `kernel.asm:102` hoặc `:553` | image kernel không còn khớp với kích thước section mà PE header viết tay của nó khai |
| `error: build/FIRMWARE.fd is N bytes, expected 1048576` | volume không đúng 1 MiB — và điều này **làm dịch reset vector**, không phải cắt cụt image |

Cảnh báo được bật hết (`-w+all`) trừ đúng ba cái, và ba cái đó được nêu tên trong
`Makefile` kèm lý do. Một lớp cảnh báo mới là một tín hiệu thật. Đừng thêm cái
`-w-` thứ tư mà không kèm comment nói rõ idiom nào sinh ra nó và vì sao nó đúng.

## Đọc log: một lần boot tốt trông thế nào

**Firmware**, theo thứ tự: `[SEC]`, `[PEI]`, `[DXE] PCI`,
`[DXE] GOP: 1024x768x32`, `[DXE] ATA:`, dòng bàn phím,
`[DXE] EFI tables built`, `[DXE] ACPI: 4 tables`, `[DXE] done`, bốn dòng `[BDS]`,
rồi các dòng của chính payload, và cuối cùng
`[BDS] image returned, status 0000000000000000`.

Có một chi tiết dễ tưởng là lỗi: **banner bị in lặp lại** sau `[DXE] PCI`. Đó là
bình thường và đúng — framebuffer console vừa mới lên, và từ giờ mọi thứ được in
ra hai nơi.

**Kernel**, theo thứ tự: `paging`, `gdt`, `idt 256 vectors`,
`timer 8254 at 100 Hz on vector 32, ticking`, `kbd i8042 on vector 33`,
`syscall lstar armed; sysret will enter cs 002b`, bốn dòng `task N window`, rồi
bốn cái kết — `solved:` và task 0 thoát, tám dòng của task 1 rồi `trap 13 (#GP)`,
hai lần bị từ chối của task 2, task 3 với phím hoặc im lặng — và cuối cùng
`every task has ended` / `nothing left to run; halted`.

Những gì **không** được assert, vì chúng khác nhau mỗi lần chạy: số tick cụ thể,
bản thân mê cung, và địa chỉ nạp.

## Landmark là một phần của thay đổi

Đây là quy tắc quan trọng nhất trong quy trình:

- Một thay đổi làm máy nói ra điều **mới** thì **thêm** một landmark.
- Một thay đổi làm máy nói ra điều **khác** thì **sửa** landmark nó vừa làm sai —
  trong **cùng commit đó**.

Nếu không, `smoke.sh` sẽ dần trở thành một tập assertion về một cái máy đã không
còn tồn tại.

## Biến một `RIP` bị fault thành một dòng source

Khi trap frame in ra một địa chỉ, cách quay lại dòng code:

- **Firmware** — `build/fw.lst` được ghi ra ở **mọi** lần build, tại địa chỉ cuối
  cùng. Đó là bản đồ symbol duy nhất tồn tại. Tra trực tiếp.
- **Kernel** — `build/kernel.lst` được ghi ra ở mọi lần build kernel (`make lstk`
  để gọi đích danh). Vì kernel là `org 0`, phải **trừ đi** địa chỉ nạp mà firmware đã in ra (`[BDS] image at ...`) khỏi
  `RIP` bị fault.
- **Program** — `build/maze.lst`, `count.lst`, `rogue.lst`, `type.lst`, cùng lần
  build đó. Trừ đi địa chỉ base của window mà kernel đã in cho task đó.

Và `CS` trong frame nói cho bạn biết đang ở đâu: `cs 002b` là ring 3 (nên offset
là `rip - window`), `cs 0008` là chính kernel (nên là `rip - image base`).

## Kiểm tra tài liệu

`make check` còn kiểm một thứ nữa, trước cả khi boot — chính tài liệu:

```
make check-docs        # tức là python3 docs/verify.py
```

Các file trong `docs/modules/` và `docs/vi/modules/` được sinh từ source — một
file cho mỗi file source — và mỗi dòng nêu tên một symbol kèm số dòng nó được
định nghĩa. Số dòng là loại tài liệu **mục âm thầm**: một label dịch chỗ, link vẫn
resolve được, dòng vẫn trông đúng. `verify.py` tính lại toàn bộ 722 khẳng định đó
và nêu tên những cái đã lệch.

Nó **không** kiểm tra được một hợp đồng có còn đúng hay không. Một hàm bị đổi quy
ước thanh ghi vẫn giữ nguyên label, nguyên số dòng và nguyên cái comment đã cũ —
chỉ có đọc code mới biết.

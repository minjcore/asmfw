# Kế hoạch nâng cấp

Xếp theo tỉ lệ *giá trị / công sức*, không theo mức độ thú vị. Mỗi việc ghi rõ:
**code đã có gì** (vì phần lớn công sức nằm ở chỗ chưa có), và **control nào
chứng minh nó đúng** — vì theo `PRINCIPLES.md` §2, một nâng cấp không có cách
kiểm độc lập thì không tính là xong.

Trạng thái hiện tại được xác nhận từ source, không phải từ trí nhớ.

---

## Tầng 0 — Rẻ, làm ngay — ✅ đã xong (2026-11-01)

Ba việc dưới đây mỗi việc dưới một giờ, và cả ba đều gỡ một chỗ đau đã tồn tại.
Cả ba đã làm; mỗi mục ghi kết quả control ở dòng **Đã làm**.

### 0.1 Nối `verify.py` vào `make check`

**Đã có:** `docs/verify.py` chạy được, exit code đúng chuẩn, 305 khẳng định.
**Cần thêm:** một dòng trong target `check` của `Makefile`.
**Vì sao:** một bộ kiểm tra chỉ chạy khi có người nhớ ra thì sẽ không được chạy.
**Control:** chính nó — sửa lệch một số dòng rồi xem `make check` có fail không
(đã thử, có fail).
**Đã làm:** target `check-docs`, là prerequisite đầu tiên của `check`. Chèn một
dòng vào đầu `kernel/paging.asm` → `make check` dừng ở `check-docs`, nêu đúng 4
khẳng định lệch, trước khi boot.

### 0.2 Target sinh listing cho kernel

**Đã có:** firmware sinh `build/fw.lst` ở **mọi** lần build, và đó là bản đồ
symbol duy nhất tồn tại.
**Chưa có:** kernel không có listing. `WORKFLOW.md` §5 hướng dẫn *"tự tạo một
cái"* bằng tay, mỗi lần debug.
**Cần thêm:** một target `lstk` chạy `nasm -l build/kernel.lst`.
**Vì sao:** biến một `RIP` bị fault thành một dòng source là việc làm thường
xuyên nhất khi sửa kernel, và hiện nó là việc thủ công.
**Control:** cố tình gây fault trong một task, rồi kiểm tra dòng tra ra từ
listing đúng là dòng đã sửa.
**Đã làm:** mọi lần build kernel giờ ghi `build/kernel.lst` và một listing cho
mỗi program (`maze/count/rogue/type.lst`); `make lstk` sinh lại cái nào thiếu.
Control dùng hai fault cố ý sẵn có: `#PF` của task 2 tại `rip 1600087`, trừ
window `1600000` = `0x87` → `rogue.lst` dòng 57 `mov al, [rax]`; `#GP` của task 1
tại `0x89` → `count.lst` dòng 65 `cli`. Cả hai đúng.

### 0.3 Báo cáo độ phủ comment header

**Đã có:** `generate.py` in `—` vào cột hợp đồng khi một entry point không có
comment header.
**Cần thêm:** đếm và in ra tổng số — *"12 trong 214 entry point chưa có hợp
đồng"*.
**Vì sao:** biến một khoảng trống vô hình thành một con số giảm dần được.
**Control:** không cần — nó là phép đếm.
**Đã làm:** `generate.py` in *"111 trong 261 entry point chưa có hợp đồng"*, kèm
số theo từng file, nhiều nhất trước: `src/efi_bs.asm` 27, `efi_file.asm` 15,
`efi_proto.asm` 15, `init64.asm` 14.

---

## Tầng 1 — Gỡ giới hạn, hạ tầng đã có sẵn

Đây là nhóm có tỉ lệ tốt nhất: mỗi việc gỡ một dòng trong mục "Limitations", và
phần khó nhất của mỗi việc **đã được viết rồi**.

### 1.1 SMBIOS entry point — ✅ đã xong (2026-11-01)

**Đã có:** toàn bộ client fw_cfg (`fwcfg_init/find/select/read`), và cơ chế cài
configuration table (`bs_install_configuration_table`) — cả hai đang được dùng
cho ACPI.
**Chưa có:** không đọc `etc/smbios` (đã kiểm: không có tham chiếu nào trong
`src/`).
**Cần thêm:** đọc hai file `etc/smbios/smbios-anchor` và `smbios-tables`, cài
anchor vào configuration table dưới GUID SMBIOS3.
**Công sức:** nhỏ — cùng khuôn với `acpi_init`, không có script nào phải chạy.
**Control:** OVMF cũng công bố SMBIOS; cho payload in ra vài field và so hai bên.
**Đã làm:** `src/smbios.asm` — đặt anchor và bảng vào một vùng
`EfiRuntimeServicesData`, điền địa chỉ, tính lại checksum (một cái cho `_SM3_`,
hai cái cho `_SM_` vì phần `_DMI_` có checksum riêng), cài dưới GUID tương ứng.
QEMU 11 với `-machine pc` cấp anchor 2.8; đã thử cả nhánh 3.0 bằng
`smbios-entry-point-type=64`. Payload kiểm checksum anchor, đi hết các structure
tới type 127, và in hãng + sản phẩm từ type 1. Dưới OVMF: cùng các dòng đó, 9
structure thay vì 8 — OVMF tự thêm type 0. Control còn bắt được một lỗi thật
trong chính payload: một chuỗi byte lẻ chèn trước các chuỗi CHAR16 làm chúng lệch
căn 2 byte; asmfw không để ý, OVMF treo trong `Open()`.

### 1.2 FAT32 tên dài (LFN)

**Đã có:** cả hai reader đã **nhận diện** entry LFN (`ATTR_LFN` = `0x0F`) và bỏ
qua chúng.
**Cần thêm:** giải mã chuỗi UCS-2 rải trong các entry LFN, ghép theo thứ tự
ngược, so khớp không phân biệt hoa thường.
**Công sức:** vừa, và phải làm **hai lần** — `src/fat.asm` và `kernel/kfat.asm`.
Đây là cái giá của việc trùng lặp có chủ ý, và nó nên được ghi vào tài liệu như
một lần "trả nợ".
**Vì sao:** đây là giới hạn duy nhất khiến firmware này không đọc được một ESP
do người khác tạo.
**Control:** tạo một đĩa có tên dài bằng `mtools`, mount dưới OVMF và dưới asmfw,
so danh sách file.

### 1.3 `LoadImage` / `StartImage` — ✅ đã xong (2026-11-01)

**Đã có:** `pe_load` đầy đủ — nạp section, áp base relocation, kiểm biên. BDS
đang dùng nó.
**Chưa có:** hai ô trong `bs_template` vẫn trỏ `bs_unsupported`.
**Cần thêm:** cấp một handle mới cho image con, một `EFI_LOADED_IMAGE_PROTOCOL`
riêng cho nó, và một chỗ để `Exit()` unwind về (`image_exit_resume` hiện chỉ có
một mức).
**Công sức:** vừa. Phần khó là **lồng nhau**: `Exit()` phải quay về đúng cha, nên
`g_exit_rsp` phải thành một stack chứ không phải một biến.
**Vì sao:** đây là thứ cho phép boot theo chuỗi — một loader gọi loader khác.
**Control:** cho payload `LoadImage` một bản copy của chính nó và chạy; nó phải
in banner hai lần rồi trả về sạch.
**Đã làm:** `src/efi_image.asm`. Mỗi image một record trong `IMAGE_TABLE`, mở
đầu bằng `EFI_LOADED_IMAGE_PROTOCOL` của nó nên địa chỉ record là handle; record
giữ stack để `Exit()` unwind về và image hiện hành trước nó — lồng nhau là một
chuỗi record. `StartImage` lưu và khôi phục mọi thanh ghi callee-saved của ABI
Microsoft x64, kể cả `XMM6`–`XMM15`. Payload đọc lại chính file của mình,
`LoadImage`, gắn `LoadOptions` cho con, `StartImage`; con nhận ra mình qua
`LoadOptions`, cố ý phá mọi thanh ghi callee-saved rồi `Exit(0x2A)`; cha kiểm
status và từng thanh ghi. Dưới OVMF: y hệt. Bỏ thử dòng khôi phục `XMM15` thì
cha báo đúng bước hỏng.
**Control còn bắt được hai lỗi có sẵn:**
- **SSE chưa từng được bật.** Lệnh SSE đầu tiên của payload là `#UD` dưới asmfw,
  chạy bình thường dưới OVMF. Spec UEFI bắt buộc x64 phải có CR0.EM=0,
  CR4.OSFXSR/OSXMMEXCPT=1, FCW `0x037F`, MXCSR `0x1F80` trước khi chạy image —
  và mọi compiler nhắm UEFI đều sinh lệnh SSE. Nghĩa là trước đây asmfw không
  chạy được *bất kỳ* image nào viết bằng C. Đã sửa ở SEC.
- **`SignalEvent` và `CloseEvent` đổi chỗ** trong bảng Boot Services và trong
  `efi.inc`. Đã sửa theo đúng thứ tự spec.
- Kèm theo: `PROTO_DB` ở `+0x900` chỉ có 256 byte trước khi đè lên `EFI_SFS` mà
  khai báo 32 record — đã dời sang `+0x1000`, 64 record.

### 1.4 Variable store trong RAM — ✅ đã xong (2026-11-01)

**Đã có:** `GetVariable` và `GetNextVariableName` — nhưng chỉ báo store rỗng.
**Chưa có:** `SetVariable` (đã kiểm: không tồn tại), và không có nơi lưu.
**Cần thêm:** một mảng cố định trong `FW_TABLES` chứa (GUID, tên, thuộc tính,
dữ liệu), cộng ba hàm. **Không** cần lưu bền — biến bay khi tắt máy là hợp lệ với
biến không có `NON_VOLATILE`.
**Công sức:** nhỏ đến vừa.
**Vì sao:** rất nhiều loader thật ghi rồi đọc lại biến của chính mình; hiện chúng
nhận `EFI_UNSUPPORTED` và có thể bỏ cuộc.
**Control:** payload ghi một biến, đọc lại, so sánh — và chạy y hệt dưới OVMF.
**Đã làm:** `src/efi_var.asm` — 32 record 2 KiB trong `EfiRuntimeServicesData`;
`GetVariable`, `SetVariable` (tạo, thay, append, xoá; đổi thuộc tính bị từ chối;
ghi có xác thực trả `EFI_UNSUPPORTED`), `GetNextVariableName`,
`QueryVariableInfo`; sau `ExitBootServices` biến không có `RUNTIME_ACCESS` bị
ẩn. Payload chạy bảy bước: ghi, đọc với buffer thiếu (phải trả
`EFI_BUFFER_TOO_SMALL` kèm kích thước cần), đọc đủ, ghi với thuộc tính khác (phải
bị từ chối), append một byte, liệt kê tới hết và tìm thấy biến của mình, xoá rồi
đọc lại phải `EFI_NOT_FOUND`. Dưới OVMF: y hệt, liệt kê ra 25 biến thay vì 1.

---

## Tầng 2 — Năng lực mới

### 2.1 Driver AHCI, để chạy được q35

**Đã có:** enumeration PCI đầy đủ, gán BAR đầy đủ, và một driver ATA PIO polled.
**Vì sao:** hiện `make ovmfk` **buộc** phải dùng máy i440fx, vì kernel tự điều
khiển cổng ATA legacy còn đĩa của q35 nằm sau AHCI. Nghĩa là control cho kernel
đang chạy trên một cấu hình máy khác với thứ ta muốn hỗ trợ.
**Cần thêm:** command list / FIS, và bộ nhớ DMA thật.
**Công sức:** lớn — đây là driver đầu tiên trong dự án cần DMA.
**Control:** cùng một đĩa, đọc bằng cả hai driver, so từng byte.

### 2.2 Ghi đĩa (ATA write + FAT write)

**Đã có:** đường đọc hoàn chỉnh; `efi_file.asm` trả `EFI_WRITE_PROTECTED` một
cách trung thực ở mọi chỗ cần.
**Cần thêm:** `WRITE SECTORS` (`0x30`), cấp cluster, cập nhật FAT và directory
entry, và cẩn thận với thứ tự ghi.
**Công sức:** lớn, và **rủi ro cao** — một reader sai thì báo lỗi, một writer sai
thì phá đĩa.
**Khuyến nghị:** chỉ làm khi có nhu cầu thật. Hiện chưa có gì cần ghi.

### 2.3 Kernel tự đọc MADT

**Đã có:** firmware trao RSDP cho kernel, và kernel **in nó ra** — đã kiểm:
`kernel.asm` chỉ dùng `g_rsdp` để in, không parse gì.
**Cần thêm:** đi XSDT tìm bảng `APIC` (MADT), đọc danh sách local APIC ID.
**Công sức:** nhỏ.
**Vì sao:** đây là bước bắt buộc trước SMP, và nó **tự có giá trị**: in ra số CPU
mà máy thật sự có là một landmark mới có ý nghĩa.
**Control:** đối chiếu với `-smp N` truyền cho QEMU.

### 2.4 Scheduler có ưu tiên và tính thời gian

**Đã có:** round robin, `sched_next` trả về task ready tiếp theo.
**Cần thêm:** một trường ưu tiên trong struct task (`T_SIZE` hiện `0x58`, còn
chỗ), và cộng dồn tick cho mỗi task.
**Công sức:** nhỏ.
**Vì sao:** *"round robin, không ưu tiên"* là một giới hạn đã ghi; và số tick mỗi
task tiêu thụ là thứ hiện không ai đo được.
**Control:** một task ưu tiên cao chạy vòng lặp bận phải làm task thấp chậm đi
theo tỉ lệ đo được, không phải theo cảm nhận.

---

## Tầng 3 — Mốc lớn

### 3.1 Boot một kernel Linux thật — ✅ đã xong (2026-11-01)

**Kết quả:** Alpine Linux 6.18.58 (kernel nguyên bản, `vmlinuz-virt`) boot qua
EFI stub của chính nó, tới tận userspace — init của Alpine chạy, không tìm thấy
gì để boot, rơi vào emergency shell `~ #`. Dưới OVMF, cùng kernel, initrd và
command line cho đúng kết quả đó. `make linux-fetch` tải cặp file đã ghim theo
URL và sha256; `make check` boot cả hai khi file có mặt (79 assertion).

**Bốn lỗi thật tìm ra trên đường đi** — không lỗi nào payload thấy được, vì
payload do cùng một người viết với firmware:
1. **SSE chưa từng được bật** (đã sửa ở 1.3, nhưng chính Linux là lý do nó quan
   trọng).
2. **Runtime services chạy từ flash.** Linux gọi `SetVirtualAddressMap` qua bảng
   RT ngay đầu tiên, và map MMIO (chính là flash) với NX → oops. Giờ cả firmware
   volume được chép vào `EfiRuntimeServicesCode` lúc boot (`rt_shadow`) và bảng
   RT trỏ vào bản chép; payload giờ đòi code runtime phải là loại đó, và OVMF
   cũng đạt.
3. **`LocateDevicePath` trả `EFI_UNSUPPORTED`.** Stub hỏi nó tìm initrd qua
   LoadFile2 và chỉ chuyển sang `initrd=` khi nhận `EFI_NOT_FOUND`.
4. **Memory map báo bảng runtime là boot services data** (đã sửa trước đó).

**`SetVirtualAddressMap` — ✅ đã làm:** đổi mọi con trỏ firmware trao ra hoặc tự
đi theo (bảng RT, `ST->RuntimeServices/ConfigurationTable/FirmwareVendor`, kho
biến), tính lại CRC, chỉ cho gọi một lần sau `ExitBootServices`. Linux giữ
runtime services; từ shell, phép kiểm nạp `efivarfs` (lấy từ modloop cùng bản
phát hành, gắn như ổ virtio) rồi đọc biến `AsmfwVersion` firmware đặt sẵn, ghi
một biến, đọc lại, xoá. OVMF chạy y hệt. Giới hạn: code runtime đọc globals qua
địa chỉ vật lý ghi cứng — chạy được vì Linux cố ý giữ map 1:1 cho vùng runtime. Load options lấy từ file
`\EFI\BOOT\CMDLINE` vì không có biến `Boot####` bền.

#### Kế hoạch ban đầu

Đây là **bài test tối hậu** cho firmware, và nó đúng với triết lý của dự án hơn
mọi việc khác trong danh sách này: payload là control do chính ta viết, còn Linux
là một client ta **không** kiểm soát và **không** thể vô tình viết cho khớp với
lỗi của mình.

Linux EFI stub *chính là* một image PE32+, nên BDS hiện tại đã nạp được nó.
Những gì còn thiếu, cụ thể và không nhiều:

| Thiếu gì | Trạng thái hiện tại (đã kiểm) |
| --- | --- |
| `LoadedImage->LoadOptions` = cmdline | đang gán `0`, cùng `LoadOptionsSize = 0` |
| `LoadedImage->FilePath` | đang gán `0` — stub dùng nó để tìm initrd cùng thư mục |
| bảng Runtime Services và biến toàn cục phải sống sau `ExitBootServices` | ✅ đã sửa: trang globals và trang đầu `FW_TABLES` báo là `EfiRuntimeServicesData` có `EFI_MEMORY_RUNTIME`; allocation loại runtime giờ mang cờ đó; flash có descriptor `EfiMemoryMappedIO` + runtime. Payload kiểm cả ba qua `GetMemoryMap`, pass dưới OVMF và asmfw; với code cũ thì báo đúng chỗ sai. Lưu ý: Linux chỉ dùng runtime services nếu `SetVirtualAddressMap` thành công, mà hàm đó vẫn `EFI_UNSUPPORTED` — nên Linux sẽ boot nhưng tự tắt runtime services |
| memory map phải thật chính xác | `mem_build_map` đã ghi đúng loại theo yêu cầu của người gọi |
| RSDP trong configuration table | đã có, dưới cả GUID 1.0 và 2.0 |
| GOP | đã có, một mode |

**Công sức:** vừa cho lần "khởi động được", lớn cho lần "khởi động đến userspace".
**Vì sao đây là mốc:** một firmware boot được Linux thì không còn là đồ chơi nữa.
Và mọi lỗi nó phát hiện đều là lỗi thật, vì Linux không biết gì về asmfw.
**Control:** chính Linux — nếu nó boot dưới OVMF mà không boot ở đây, lỗi ở
firmware. Cùng một logic đã dùng cho payload, áp lên một client khó tính hơn nhiều.
**Landmark mới:** dòng đầu tiên của `EFI stub: ...` xuất hiện trong transcript.

### 3.2 SMP

**Cần:** 2.3 trước (MADT), rồi trình tự INIT–SIPI–SIPI để khởi động AP, GDT/TSS
riêng cho mỗi CPU, và **khoá thật** cho scheduler.
**Công sức:** lớn nhất trong danh sách. Nó chạm vào mọi giả định của kernel hiện
tại — nhất là `g_current` là một biến đơn, và khoá console là mutex một chủ.
**Khuyến nghị:** làm sau 3.1. Boot Linux xong sẽ hiểu rõ hơn cái gì thật sự cần.

### 3.3 Chạy trên máy thật, qua coreboot

**Rào cản không phải code mà là vật lý:** firmware này giả định RAM hoạt động
ngay lúc reset. Trên máy thật, memory controller phải được train trước, và trên
mọi nền tảng Intel sau Ivy Bridge, code làm việc đó chỉ tồn tại dưới dạng blob
FSP đóng.
**Nghĩa là:** đường đi là trở thành một **coreboot payload**, không phải flash
trực tiếp. Khi đó coreboot lo train RAM, asmfw lo phần UEFI.
**Công sức:** vừa về code (bỏ SEC/PEI, nhận sẵn máy đã có RAM), nhưng cần phần
cứng và một programmer flash.

---

## Không nên làm

- **Secure Boot** — cần RSA, SHA-256, phân tích X.509 và một cơ sở dữ liệu khoá.
  Rất nhiều code crypto, và nó không dạy thêm gì về firmware.
- **Free list cho allocator** — `AllocatePages` là con trỏ bump và điều đó **đúng**
  cho một firmware cấp phát vài lần rồi giao máy đi. Một free list là thêm code
  không có người dùng.
- **Mạng (PXE, TCP/IP)** — một dự án riêng, không phải một nâng cấp.
- **Tách `REFERENCE.md`** — nghe hấp dẫn nhưng khoảng 20 tham chiếu nội bộ dạng
  chữ (`§7.5`, `§6.1`, không phải link) sẽ **âm thầm** thành con trỏ chết. Chỉ làm
  nếu viết lại từng cái, và khi đó nên thêm một bộ kiểm tham chiếu vào
  `verify.py` trước.

---

## Thứ tự đề nghị

```
Tầng 0 (0.1, 0.2, 0.3)        một buổi — dọn đường
   │
1.4 variable store             ─┐
1.3 LoadImage/StartImage        ├─ ba việc này là thứ Linux sẽ cần
1.1 SMBIOS                     ─┘   (và mỗi việc tự có giá trị)
   │
3.1 BOOT LINUX  ⭐              mốc lớn — sau đây dự án đổi tính chất
   │
2.3 MADT → 2.4 scheduler       nhỏ, mở đường cho SMP
   │
1.2 LFN                        khi cần đọc đĩa của người khác
2.1 AHCI                       khi muốn control chạy trên q35
   │
3.2 SMP                        sau khi đã biết cái gì thật sự cần
```

Một quy tắc áp cho mọi việc trong danh sách, lấy từ `WORKFLOW.md` §3:

> Một thay đổi làm máy nói ra điều **mới** thì **thêm** một landmark. Một thay đổi
> làm máy nói ra điều **khác** thì **sửa** landmark nó vừa làm sai, trong cùng
> commit đó.

Nghĩa là mỗi việc trong kế hoạch này đều kết thúc bằng một dòng mới trong
`tools/smoke.sh`, không phải bằng một lần chạy thử thành công.

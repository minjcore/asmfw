# Hệ thống tài liệu: cái gì sinh tự động, cái gì viết tay

Dự án này có ba loại tài liệu, và loại nào cũng có một cách hỏng riêng. File này
nói rõ loại nào là loại nào, cách sinh lại và kiểm tra chúng, và ghi lại những lỗi
mà đợt rà soát vừa rồi tìm ra — vì bản thân danh sách lỗi đó là bằng chứng cho
thấy quy trình có tác dụng.

## Ba loại

| Loại | Ở đâu | Sinh ra bằng | Hỏng như thế nào |
| --- | --- | --- | --- |
| **Viết tay, tiếng Anh** | `README.md`, `REFERENCE.md`, `WORKFLOW.md`, `PRINCIPLES.md` | người viết | một con số dịch chỗ trong code mà tài liệu không đổi theo |
| **Sinh từ code** | `docs/*.md` | `docs/generate.py` | một label dịch dòng — link vẫn resolve, dòng vẫn trông đúng |
| **Viết tay, tiếng Việt** | `docs/vi/*.md` | người viết | giải thích một cơ chế đã bị thay đổi |

Điểm chung: **không loại nào tự báo khi nó sai**. Đó là lý do có `docs/verify.py`,
và cũng là lý do loại thứ hai được cố tình thiết kế để kiểm tra được bằng máy.

## Loại sinh tự động

```
python3 docs/generate.py      # sinh lại ba file bảng
python3 docs/verify.py        # đối chiếu 305 khẳng định với source
```

`generate.py` đọc toàn bộ `src/`, `kernel/`, `kernel/progs/` và `payload/`, rồi
ghi ra:

| File | Bao gồm |
| --- | --- |
| `docs/firmware-modules.md` | 25 file trong `src/` |
| `docs/kernel-modules.md` | 13 file trong `kernel/` |
| `docs/programs.md` | 4 program, `ulib.inc`, và `payload/hello.asm` |

Nguyên tắc quan trọng nhất của ba file này:

> Không có gì trong đó được diễn giải lại. Phần mô tả mỗi file là **banner comment
> của chính file đó**; cột hợp đồng của mỗi entry point là **comment header ngay
> phía trên hàm đó** trong source.

Nhờ vậy tài liệu **đầy đủ theo cấu trúc**, không phải đầy đủ theo phán đoán của
người viết về việc gì đáng ghi. Nếu một hàm có comment header, nó xuất hiện. Nếu
không có, nó vẫn xuất hiện với hợp đồng là `—`, và cái dấu gạch đó là một lời nhắc
rằng source thiếu comment.

Ngoài ra mỗi mục còn có: dữ liệu và state file đó sở hữu, số hằng số nó định
nghĩa, macro nó cung cấp, và **cạnh phụ thuộc theo cả hai chiều** — nó gọi vào
đâu, và ai gọi nó.

### `verify.py` kiểm tra cái gì

Mỗi dòng trong ba file trên nêu tên một symbol kèm số dòng nó được định nghĩa, và
số dòng là loại tài liệu **mục âm thầm nhất**: label dịch chỗ, link vẫn resolve
được, dòng vẫn trông hợp lý. Không có gì báo.

`verify.py` tính lại và kiểm ba điều:

1. Số dòng trong phần chữ và số dòng trong link có khớp nhau không.
2. Symbol đó có **thật sự** được định nghĩa ở dòng đó không.
3. Mỗi file có đúng số dòng như đã ghi không.

Ví dụ khi có lệch:

```
kernel-modules.md:208  paging_build: documented at kernel/paging.asm:23, now at line 22
kernel-modules.md:23   kernel/sched.asm: documented as 999 lines, is 517
```

Exit code là 0 khi khớp, 1 khi không — và `make check` chạy nó đầu tiên (target
`check-docs`), nên tài liệu lệch thì cả lần kiểm fail trước khi kịp boot.

**Điều nó không kiểm được:** một *hợp đồng* có còn đúng hay không. Một hàm bị đổi
quy ước thanh ghi vẫn giữ nguyên label, nguyên số dòng, và nguyên cái comment đã
cũ. Chỉ có đọc code mới biết. Đây là giới hạn thật, không phải thiếu sót tạm thời.

### Quy trình khi sửa code

```
sửa code
python3 docs/generate.py      # nếu có thêm/bớt/dịch chỗ hàm
python3 docs/verify.py        # phải in OK
```

Nếu `generate.py` làm ba file đổi nội dung, đó là bình thường — commit chúng cùng
với thay đổi code. Nếu `verify.py` fail mà bạn **chưa** chạy `generate.py`, đó
chính là tín hiệu nó tồn tại để phát ra.

## Đợt rà soát vừa rồi: những gì đã tìm ra

Phần này ghi lại kết quả, vì một danh sách lỗi cụ thể có ích hơn một lời khẳng
định rằng tài liệu đã được kiểm tra.

### Đã kiểm và đúng

Trước khi sửa gì, mọi khẳng định kiểm được bằng máy trong `REFERENCE.md` đều được
đối chiếu với source:

- **Mọi tham chiếu có số dòng** — `fw.asm:54` và `:65`, `kernel.asm:102` và `:553`,
  `efi_tables.asm:354`, cùng toàn bộ chuỗi phase ở §3.1 (`init16.asm:12`,
  `init32.asm:11`, `init64.asm:15/57/150/216`) — đều trỏ đúng chỗ.
- **Mọi hằng số** trong bản đồ bộ nhớ, offset EFI, selector, descriptor, struct
  task, và ABI system call.
- `ISR_ERR_MASK` = `0x60227D00` giải mã ra đúng các vector 8, 10–14, 17, 21, 29,
  30 như tài liệu nói.
- **47 assertion** của `smoke.sh` = 20 firmware + 22 kernel (21 dương + 1 âm) + 5
  control, đúng như đã ghi.
- Mọi symbol trong bảng module index đều tồn tại, và **không** entry point liên
  file nào trong `src/` bị bỏ sót.
- `python3 tools/mkfont.py` sinh lại `src/font.inc` **giống hệt từng byte**.

### Lỗi đã sửa

| Ở đâu | Sai gì | Đã sửa thành |
| --- | --- | --- |
| `REFERENCE.md` §2.3 | nói record protocol **thứ 13** mới đè lên `EFI_SFS` | giữa `PROTO_DB` và `EFI_SFS` có 256 byte, mỗi record 24 byte → vừa 10 record, cái **thứ 11** mới đè |
| `REFERENCE.md` §7.11 | nói tiền tố `k` đảm bảo luôn phân biệt được hai tầng | thêm ngoại lệ: `kbd_init`, `kbd_wait_read`, `kbd_wait_write` **trùng tên ở cả hai cây** |
| `README.md` mục Layout | thiếu `src/util.asm`, `src/macros.inc`, `tools/smoke.sh` | đã thêm |
| `kernel/kfat.asm:40` | comment ghi `KBUF_CLUSTER`, symbol thật là `kbuf_cluster` | đã sửa |
| `tools/mkfont.py` | docstring nói "emit it as C", thực tế sinh ra NASM | đã sửa |
| `generate.py` + `verify.py` | đếm dòng bằng `split('\n')`, lệch **+1** so với `wc -l` | đổi sang đếm ký tự newline; sinh lại ba file; sửa hai con số viết tay trong `docs/vi/` |

Lỗi cuối đáng nói riêng, vì nó là dạng lỗi tệ nhất: `generate.py` và `verify.py`
dùng **cùng một** phương pháp đếm sai, nên chúng nhất quán với nhau và `verify.py`
báo OK. Một bộ kiểm tra dùng chung giả định với thứ nó đang kiểm thì không kiểm
được cái giả định đó. Chỉ khi đối chiếu với `wc -l` — một hiện thực **độc lập** —
sai lệch mới lộ ra. Đúng như `PRINCIPLES.md` §2 nói: *thứ gì có thể sai thì cần
một control độc lập.*

### Phần đã viết thêm

| Ở đâu | Nội dung |
| --- | --- |
| `REFERENCE.md` §7.10, §7.11 | chuỗi lệnh gọi và module index cho **kernel** — trước đó firmware có, kernel không, và 16 entry point liên file chưa từng được nêu tên ở đâu |
| `REFERENCE.md` §10 | **payload** — 698 dòng và là bài test chức năng duy nhất của firmware, trước đó chỉ có một dòng trong bảng |
| `REFERENCE.md` §11 | `mkesp.py` và `mkfont.py` — trước đó `mkfont.py` được mô tả bằng đúng ba chữ "font generator" |
| `docs/*.md` | ba bảng module sinh tự động, cộng `generate.py` và `verify.py` |
| `docs/vi/*.md` | sáu file giải thích bằng tiếng Việt |

Đánh số các mục §10–§12 cũ được dịch thành §12–§14. Việc này an toàn vì đã kiểm
trước: **không có tài liệu nào tham chiếu tới ba mục đó**.

## Hai điều tự sửa trong lúc viết

Ghi lại vì chúng cho thấy chỗ nào dễ sai:

**"`make` không phụ thuộc `font.inc`"** — sai. `FW_SRCS` trong `Makefile` là
`wildcard src/*.inc`, nên `font.inc` **là** một prerequisite. Điều thật sự thiếu
là *không có rule nào sinh ra nó* từ `mkfont.py`. Hai chuyện khác nhau.

**"`SetAttribute` chứng minh màu hoạt động"** — sai. Transcript serial không mang
được màu; chỉ cửa sổ đồ hoạ thấy được. Điều assert được chỉ là hàm đó được gọi mà
không fault.

**`kmain` trả về status khi `ExitBootServices` thất bại** — cũng sai. Nó in qua
`ConOut` của firmware rồi `cli; hlt` tại chỗ. Không phase nào của kernel trả về
firmware cả.

Cả ba đều là suy đoán hợp lý về code, và cả ba đều sai. Đó là lý do mọi khẳng định
trong bộ tài liệu này đều được đối chiếu source trước khi viết ra, chứ không viết
theo trí nhớ.

## Còn thiếu gì

- `REFERENCE.md` dài 1359 dòng. Tách nó ra thành nhiều file là hợp lý, nhưng khoảng
  20 tham chiếu nội bộ dạng chữ (`§7.5`, `§6.1` — không phải link) sẽ **âm thầm**
  thành con trỏ chết nếu tách mà không viết lại từng cái.
- Tài liệu tiếng Việt là viết tay nên không có gì kiểm được nó. Nếu bạn thấy một
  điểm không khớp: **code đúng, tài liệu sai.**

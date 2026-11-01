# Tài liệu tiếng Việt

Bộ tài liệu này **giải thích** dự án: nó là gì, từng phần hoạt động ra sao, và vì
sao code lại có hình dạng như vậy. Nó không phải bản dịch của tài liệu tiếng Anh
ở gốc repo, mà là một cách trình bày khác — nhắm vào người đọc codebase này lần
đầu.

## Đọc theo thứ tự này

| # | File | Nội dung |
| --- | --- | --- |
| 1 | [tong-quan.md](tong-quan.md) | Dự án này là gì, hai nửa firmware/kernel, luồng boot từ đầu đến cuối, và các giới hạn |
| 2 | [firmware.md](firmware.md) | Firmware: flash volume, bốn phase SEC/PEI/DXE/BDS, lớp EFI, các quy ước trong code |
| 3 | [kernel.md](kernel.md) | Kernel: ranh giới `ExitBootServices`, cô lập task bằng page table, scheduler, khoá console, virtual wire |
| 4 | [chuong-trinh.md](chuong-trinh.md) | Payload và bốn program — mỗi cái chứng minh điều gì; ABI và bảy system call |
| 5 | [kiem-thu.md](kiem-thu.md) | Kiểm thử một cái máy đang reset: landmark, control OVMF, đọc log, tìm dòng source từ `RIP` |
| 6 | [he-thong-tai-lieu.md](he-thong-tai-lieu.md) | Bản thân hệ thống tài liệu: cái gì sinh tự động, cách sinh lại và kiểm tra, và những lỗi đợt rà soát vừa rồi tìm ra |
| 7 | [ke-hoach-nang-cap.md](ke-hoach-nang-cap.md) | Kế hoạch nâng cấp, xếp theo giá trị / công sức — mỗi việc kèm code đã có gì và control nào chứng minh nó đúng |

Nếu chỉ có mười phút, đọc [tong-quan.md](tong-quan.md) là đủ để hiểu dự án làm gì
và tại sao nó khó.

## Quan hệ với tài liệu tiếng Anh

Bảy file ở đây **không thay thế** tài liệu gốc. Chúng trả lời câu hỏi khác:

| Tài liệu | Trả lời câu hỏi | Ngôn ngữ |
| --- | --- | --- |
| `docs/vi/` (chỗ này) | *cái này hoạt động thế nào, và vì sao?* | tiếng Việt |
| [../../README.md](../../README.md) | *đây là gì, và nó không làm được gì?* | tiếng Anh |
| [../../REFERENCE.md](../../REFERENCE.md) | *con số này nằm ở đâu, chuẩn nào quy định nó?* | tiếng Anh |
| [../../WORKFLOW.md](../../WORKFLOW.md) | *sửa xong rồi thì phải chạy gì?* | tiếng Anh |
| [../../PRINCIPLES.md](../../PRINCIPLES.md) | *vì sao code có hình dạng này?* | tiếng Anh |
| [modules/](modules/README.md) | *file này export gì, ai gọi nó?* | nhãn tiếng Việt, sinh từ code |

Khi cần một con số cụ thể — offset của một trường trong struct, giá trị ghi vào
một thanh ghi thiết bị, kích thước một bảng — hãy tra `REFERENCE.md`. Tài liệu
tiếng Việt cố ý **không** nhắc lại những con số đó, vì hai chỗ cùng ghi một con số
là hai chỗ có thể lệch nhau.

## Quy ước về thuật ngữ

Các thuật ngữ kỹ thuật được **giữ nguyên tiếng Anh**, vì đó là dạng bạn sẽ thấy
trong code, trong log, và trong các tài liệu chuẩn (UEFI spec, Intel SDM,
OSDev wiki). Dịch chúng ra tiếng Việt sẽ làm việc tra cứu khó hơn, không dễ hơn.

Cụ thể, những từ này để nguyên: *reset vector, real mode, protected mode, long
mode, page table, framebuffer, boot services, runtime services, protocol, handle,
scheduler, task, ring 0/ring 3, trap, interrupt, syscall, scan code, landmark,
payload, control.*

Phần được giải thích bằng tiếng Việt là **ý nghĩa và lý do**, không phải tên gọi.

## Một lưu ý về độ chính xác

Mọi con số và mọi khẳng định trong năm file này đều được đối chiếu với source lúc
viết. Nhưng khác với `docs/*.md` (sinh tự động và kiểm tra được bằng
`docs/verify.py`), các file tiếng Việt là **viết tay** — nên chúng có thể lệch khỏi
code mà không có gì báo.

Nếu bạn thấy một điểm không khớp, code đúng và tài liệu sai.

# Payload và năm program: mỗi cái tồn tại để chứng minh một điều

Dự án này có năm chương trình không thuộc firmware và cũng không thuộc kernel.
Mỗi cái tồn tại để chứng minh một điều cụ thể, và cái điều đó là lý do duy nhất
nó tồn tại.

## `payload/hello.asm` — bài test thật sự của firmware

698 dòng, và nó là **bài kiểm thử chức năng duy nhất** của firmware. Mọi thứ khác
chỉ kiểm tra rằng một phase đã chạy xong; cái này kiểm tra rằng những protocol đã
công bố **thật sự trả lời**.

Nó được build bằng đúng một lệnh `nasm -f bin`, **không có include path**, nên nó
không thể thấy `src/efi.inc`. Các offset nó cần được viết lại lần thứ hai ở đầu
phần code. Sự trùng lặp đó chính là điểm chính:

> Một payload đọc header của chính firmware sẽ **đồng ý với firmware về ABI bất
> kể cả hai cùng sai thế nào**.

Nó cũng là một ứng dụng UEFI thật, chạy được dưới OVMF. Đó là điều làm nó thành
một **control**: nếu nó chạy dưới OVMF mà không chạy ở đây, lỗi ở firmware; nếu
không chạy dưới cả hai, lỗi ở payload. `make ovmf` chạy đúng phép so sánh đó, và
nó đã bắt được hai lỗi thật trong quá trình phát triển — một mảng partition GPT
bị đọc thiếu, và một bộ phân tích đường dẫn khởi động lại từ root ở mỗi dấu phân
cách.

### PE header viết tay

Header được viết ra bằng tay, và đọc được như bản đặc tả cho những gì
`src/pe.asm` phải hiểu. Hai quyết định đáng bắt chước:

**`FileAlignment` bằng `SectionAlignment`** (cả hai `0x1000`). Nhờ vậy offset
trong file và RVA là **cùng một con số**, nên một chỉ thị `org 0` mô tả được cả
file lẫn image đã nạp, và không còn phép tính offset nào có thể sai.

**Không có relocation directory nào cả.** Mọi tham chiếu đều RIP-relative, nên
image chạy đúng ở bất cứ đâu loader đặt nó. `ImageBase` khai `0x140000000` —
không bao giờ là chỗ nó thật sự nằm, mà đó chính là trường hợp thú vị. Đây cũng
là lý do `pe_load` chấp nhận một image không có relocation ở địa chỉ khác, trừ khi
image đó bật cờ `IMAGE_FILE_RELOCS_STRIPPED`.

### Nó kiểm tra gì, theo thứ tự

Mỗi bước là một câu hỏi mà **câu trả lời sai vẫn trông có vẻ đúng**.

| Bước | Gọi gì | Khẳng định điều gì |
| --- | --- | --- |
| console | `ClearScreen`, `SetAttribute`, `OutputString` | banner tới được; `SetAttribute` được gọi thật (nhưng chỉ cửa sổ đồ hoạ thấy được kết quả — transcript không mang màu) |
| storage | `LocateProtocol(SFS)`, `OpenVolume`, `Open` | bộ phân tích đường dẫn đi được một đường dẫn thật, từng dấu phân cách một |
| storage | `Read` 2 byte, so với `0x5A4D` | **nó đọc lại chính mình và thấy `MZ`** — bằng chứng là lệnh đọc rơi đúng cluster, không chỉ là "trả về thành công" |
| ACPI | configuration table, rồi XSDT | xem bên dưới |
| đồ hoạ | `LocateProtocol(GOP)`, rồi vẽ | địa chỉ framebuffer trong `Mode->FrameBufferBase` là địa chỉ CPU ghi được thật |
| input | `ReadKeyStroke`, polling | một **phím cụ thể** trả về, không chỉ là "có phím nào đó" |

Mỗi bước đều có chuỗi thông báo cho cả trường hợp thành công và thất bại, và
chương trình **đi tiếp sang bước sau** thay vì dừng. Một lần chạy fail một bước
vẫn báo cáo năm bước còn lại — đó là điều làm transcript đáng đọc sau khi sửa
code.

### Phần ACPI, và vì sao nó là bài test khó nhất

`show_acpi` là phần thử firmware nặng nhất, vì QEMU **không** đưa bảng hoàn
chỉnh: cross-reference là offset, checksum sai, cho đến khi firmware chạy
`etc/table-loader`. Bảng chưa được patch **vẫn trông hợp lý**.

Nó làm bốn bước: duyệt configuration table tìm GUID ACPI 2.0; chọn bảng gốc (XSDT
nếu revision ≥ 2 và có, vì đó là bảng mô tả được địa chỉ trên 4 GiB, không thì
RSDT); tính số entry từ độ dài; rồi với **từng** entry, in bốn byte signature và
cộng tổng toàn bảng — phải bằng 0.

Kết luận là một dòng: `every one of them checksums to zero`, hoặc `at least one of
them has a bad checksum`. Việc đọc **mọi** entry cũng chính là điều biến nó thành
một khẳng định về **con trỏ**: một lệnh `ADD_POINTER` chưa được thực hiện sẽ để
lại một offset ở chỗ cần một địa chỉ, và cộng tổng cái bảng mà nó trỏ tới sẽ
fault hoặc ra số vô nghĩa, chứ không ra 0.

### Phần bàn phím

Nó polling `ReadKeyStroke` 300 lần, mỗi lần `Stall(10000)` — tổng đúng ba giây,
rồi **tự bỏ cuộc**, nên một lần chạy không có người ngồi vẫn kết thúc. Đoạn này
thay thế một lệnh stall ba giây trước đó chỉ tồn tại cho có.

Hai chi tiết trong cách nó báo cáo:

- Một phím có `UnicodeChar` bằng 0 là **câu trả lời thật**, không phải lỗi: các
  phím mũi tên và Esc báo scan code mà không có ký tự. Nó in `.` cho ký tự và
  scan code hex bên cạnh.
- Không ai bấm gì thì in `ConIn said EFI_NOT_READY throughout` — và đây chính là
  khẳng định mà `smoke.sh` kiểm tra, vì dưới `make check` không có màn hình nên
  QEMU không có bàn phím nào để đưa.

Đây là protocol cuối cùng chưa ai thử tới, và nó **sai trong một thời gian dài
chính vì vậy**: một firmware trả về sai chữ thì không phân biệt được với một
firmware hoạt động đúng, cho tới khi có người hỏi một phím cụ thể.

## Năm program của kernel

Một program là **binary phẳng**: không header, không relocation, entry point ở
offset 0. Kernel đọc nó thẳng vào window mà nó sẽ chạy trong đó rồi khởi động —
nên mọi tham chiếu trong nó phải RIP-relative, và mọi thứ nó biết về cái máy đều
được **nói cho nó lúc vào**:

| Thanh ghi | Lúc vào |
| --- | --- |
| `RDI` | task id của nó |
| `RSI` | địa chỉ window của nó |
| `RDX` | window của task láng giềng — một địa chỉ nó được cho biết mà **không** với tới được |

`RSP` bắt đầu ở đỉnh window. Đó là toàn bộ cái loader.

Bốn program đầu kết thúc bằng **bốn cách khác nhau**, và đó mới là điểm chính; cái thứ năm là một Lisp:

| Task | Program | Kết thúc bằng |
| --- | --- | --- |
| 0 | `MAZE.BIN` | `sys_exit`, sau khi sinh và giải một mê cung 39×19 |
| 1 | `COUNT.BIN` | thực thi `cli` và bị `#GP` giết |
| 2 | `ROGUE.BIN` | `#PF` error 5, đọc window của láng giềng |
| 3 | `TYPE.BIN` | `sys_exit`, sau một phím bấm hoặc ba giây im lặng |
| 4 | `LISP.BIN` | `sys_exit`, sau demo và một REPL đóng khi bấm Esc hoặc im lặng năm giây |

**Task 0 — mê cung.** Sinh mê cung 39×19 bằng DFS ngẫu nhiên, giải nó, vẽ ra. Nó
**không bao giờ yield**, nên mỗi lần nó biến mất khỏi output một lúc là vì timer
đã lấy CPU đi giữa lệnh rồi trả lại mà nó không hề biết. Đây là bằng chứng của
preemption.

**Task 1 — đếm.** In một dòng có số rồi ngủ 120 ms, tám lần. Uptime bên cạnh mỗi
dòng là phần đáng xem: khoảng cách đều 12 tick là lệnh ngủ, còn **một** khoảng
dài là task 0 đang giữ console để vẽ mê cung. Rồi nó thực thi `cli` — một lệnh
ring 3 không có quyền — và bị `#GP` giết. Đây là bằng chứng một task chết được mà
máy không chết theo.

**Task 2 — kẻ đi lạc.** Trước tiên nó đưa kernel một con trỏ ngoài window của
mình và **bị từ chối** — `sys_write` kiểm tra biên đúng một lần, ở biên, và vòng
lặp phía sau tin vào lần kiểm tra đó. Sau đó nó đọc window của task 0 **trực
tiếp**, ở địa chỉ chính kernel đã nói cho nó, không qua system call nào. Địa chỉ
đó có mapping thật, và kernel đọc được; nhưng trong không gian địa chỉ của task 2,
cái page 2 MiB đó không có mapping user, nên lệnh đọc fault với `#PF` error 5.
Đây là bằng chứng của sự cô lập — và nó chứng minh cả hai lớp: biên system call
*và* page table.

**Task 3 — chờ phím.** Gọi `sys_read` và chờ một phím bấm, thứ duy nhất trên cái
máy này mà **không đồng hồ nào rồi cũng sinh ra được**. Ba task kia sẽ chạy giống
hệt nhau dù không có ai ở bàn phím; task này là lý do đường idle của kernel phải
trở nên trung thực. Mọi lần block khác đều kết thúc ở một tick có thể gọi tên
trước — deadline của người ngủ, thời điểm nhả khoá — nên `hlt` luôn chỉ là chờ
một phép tính đã làm xong. Một task block trên thiết bị có thể để cái máy **thật
sự rảnh trong khi vẫn còn việc chưa xong**, chừng nào chưa ai bấm gì.

**Task 4 — Lisp.** Một trình thông dịch Lisp hoàn chỉnh trong 9 KB: số nguyên,
symbol, cons, closure; các special form `quote` `if` `define` `lambda` `let`
`begin` `set!` `cond` `and` `or`; 22 primitive. Nó chạy một script demo nhúng
sẵn — in từng biểu thức và giá trị — rồi mở dấu nhắc `lisp>` đọc từ bàn phím
(ngoặc chưa cân thì đọc tiếp dòng sau, có backspace) cho tới khi bấm Esc hoặc im
lặng năm giây.

Hai chỗ đáng đọc. **Tail call**: mọi vị trí đuôi — `if`, dạng cuối của một
body, `cond`, `and`, `or` — được xử lý bằng *nhảy* thay vì *gọi*, nên
`(sum-to 100000 0)` chạy với stack không đổi. **Bộ thu gom rác** mark-and-sweep
trên heap 32768 ô 32 byte, *bảo thủ* với stack: bất kỳ word nào trên stack trông
giống địa chỉ một object còn sống thì giữ object đó lại. Nhờ vậy evaluator chỉ là
assembly bình thường — giữ giá trị trong thanh ghi, push như mọi thứ khác — không
phải tự tay duy trì danh sách root. Demo cấp phát hơn một triệu ô qua 32768 ô đó,
và dòng ngay sau nó cho biết GC đã chạy bao nhiêu lần.

Không có task nào trong năm cái mang cái máy đi theo nó. Đó là điều cả cái sắp
đặt này tồn tại để chứng minh.

## `ulib.inc` — toàn bộ thư viện của userspace

97 dòng, và nó được **assemble vào từng program** chứ không chia sẻ lúc chạy: ở
đây không có loader nào có thể resolve một lệnh gọi giữa hai image, và cũng không
có image thứ hai để resolve tới.

| Hàm | Hợp đồng |
| --- | --- |
| `u_write` | RDI = buffer, RSI = độ dài → RAX |
| `u_read` | RDI = buffer, RSI = độ dài, RDX = ms (0 = chờ mãi) → RAX |
| `u_exit` | RDI = status; quay vòng nếu vì lý do gì nó trả về |
| `u_hex` | RAX = giá trị, RDI = đích, ECX = số chữ số — ghi tại chỗ, lên một placeholder trong thông điệp |
| `u_dec` | RAX = giá trị, RDI = đích, ECX = số chữ số — điền từ phải sang, độ rộng cố định |

`u_hex` và `u_dec` ghi **tại chỗ** lên một chỗ trống trong chuỗi đã dựng sẵn, thay
vì dựng chuỗi mới. Lý do: một program là binary phẳng không có heap, và một lệnh
`sys_write` cho cả dòng thì rẻ hơn nhiều lệnh cho từng phần.

## Bảy system call

`kernel/uabi.inc` được include bởi **cả kernel và mọi program**, nên các con số
này về mặt vật lý không thể lệch nhau.

Số hiệu trong `EAX`, tham số trong `RDI`/`RSI`/`RDX`, kết quả trong `RAX`. Bị
phá: `RCX` và `R11` (do chính lệnh `SYSCALL` lấy), và `R10` (kernel dùng để tự
tìm mình trước khi có stack).

| # | Call | Tham số | Trả về |
| --- | --- | --- | --- |
| 0 | `SYS_WRITE` | RDI = buffer, RSI = độ dài | số byte đã ghi, hoặc `SYS_EBADPTR` |
| 1 | `SYS_EXIT` | RDI = status | không trả về |
| 2 | `SYS_TICKS` | — | time stamp counter |
| 3 | `SYS_YIELD` | — | 0, sau khi nhường phần còn lại của lượt |
| 4 | `SYS_SLEEP` | RDI = milli giây | 0. Làm tròn **lên** một tick, không bao giờ 0 tick |
| 5 | `SYS_UPTIME` | — | số tick từ lúc boot |
| 6 | `SYS_READ` | RDI = buffer, RSI = độ dài, RDX = timeout ms (0 = mãi) | số byte đọc được; 0 nếu hết thời gian |

Hai điều đáng biết về `SYS_READ`: nó trả về **ít nhất một byte** trừ khi hết thời
gian, và không bao giờ nhiều hơn số byte đã được gõ — nó không phải lời hứa lấp
đầy buffer. Và deadline của nó được tính **một lần**, từ lúc gọi, không được gia
hạn bởi thứ đánh thức task — nếu không, một dòng phím không ai yêu cầu có thể giữ
một lần chờ có giới hạn mở vô hạn.

Cả hai call nhận con trỏ đều kiểm tra buffer **đúng một lần**, ở đầu, đối chiếu
với `[window, window + 2 MiB)` kể cả trường hợp tràn số, và vòng lặp phía sau
lần kiểm tra đó **không** test lại từng byte. Kiểm tra ở biên một lần, rồi tin
vào hợp đồng bên trong.

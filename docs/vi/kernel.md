# Kernel: sau `ExitBootServices` thì chỉ còn cái máy

`kernel/` là một thứ khác hẳn firmware: **không phải firmware, mà là thứ firmware
boot lên**. Nó tới dưới dạng `\EFI\BOOT\BOOTX64.EFI` trên đĩa riêng của nó, dùng
boot services đúng vừa đủ lâu để tìm framebuffer và giữ lại bộ nhớ nó sẽ còn cần,
rồi gọi `ExitBootServices` và **không bao giờ nói chuyện với firmware nữa**.

Cái ranh giới đó là toàn bộ ý nghĩa của phần này. Trước nó, kernel là một ứng
dụng UEFI bình thường. Sau nó, mọi bảng mà CPU tra cứu đều là bảng do chính image
này dựng.

## Hai phase, và tại sao phải phân biệt rõ

### Phase 1: `kmain` — còn boot services

```
kmain(RCX = ImageHandle, RDX = SystemTable)
```

Theo quy ước gọi Microsoft x64, nên phải chừa 32 byte shadow space cộng thêm một
slot, vì `GetMemoryMap` nhận năm tham số.

Nó làm đúng sáu việc:

1. Lưu system table, ConOut, boot services; xoá màn hình; in banner.
2. `LocateProtocol(GOP)` rồi **copy ra** địa chỉ framebuffer, độ phân giải, pitch
   — vì framebuffer sống lâu hơn cái protocol mô tả nó.
3. Duyệt configuration table tìm GUID ACPI 2.0, giữ lại RSDP — trong khi vẫn còn
   một cái bảng liệt kê nó.
4. `AllocatePages` hai lần: page table, rồi user window.
5. Căn khối window lên biên 2 MiB. `AllocatePages` chỉ hứa alignment theo page và
   không hơn, nên bước 4 đã cố tình xin **nhiều hơn một window** để chắc chắn có
   một khoảng liên tục căn 2 MiB nằm gọn trong đó.
6. `GetMemoryMap`, rồi `ExitBootServices` với cái key vừa lấy, thử tối đa
   `MAP_RETRIES` = 3 lần. **Lấy bản đồ có thể tự làm bản đồ thay đổi**, nên bị từ
   chối là chuyện bình thường, và cách xử lý là đi hỏi lại.

Ý số 2 và số 3 là cùng một bài học: những gì boot services *nói* cho bạn phải
được copy ra trước khi boot services biến mất.

### Phase 2: `kmain64` — không còn gì cả

Ngay sau `ExitBootServices`, kernel thay CR3, GDT, TSS, IDT và các MSR của
SYSCALL, theo thứ tự đó, trước khi làm bất cứ việc gì khác:

```
kc_init                console riêng, dựng từ geometry đã lưu ở phase 1
paging_build → CR3     không gian địa chỉ của chính kernel
gdt_init               descriptor, TSS, RSP0
idt_init               256 gate
lapic_init             ─┐
pic_init                ├─ thứ tự này là điểm chính, xem bên dưới
pit_init               ─┘
timer_check            chứng minh tick có tới thật
kbd_init               bật translation, dọn buffer, mở IRQ1
syscall_init           EFER.SCE, STAR, LSTAR, FMASK
kata_init              ổ primary master
kgpt_find_esp          chỉ GPT, không fallback MBR
kfat_mount
kfat_lookup ×2         \PROGS, rồi tên program
kfat_read_file         đọc thẳng vào window
paging_build + task_create   mỗi task một lần
sched_run(tasks)       iretq vào task 0 — không bao giờ trả về
```

Không phase nào trả về firmware. Trước ranh giới, lỗi được in qua `ConOut` của
firmware rồi CPU halt tại chỗ. Sau ranh giới, lỗi in trên console của chính kernel
rồi nhảy `khalt`. `khalt` cũng là nơi scheduler kết thúc khi mọi task đã xong —
nên `nothing left to run; halted` là **dòng cuối của một lần boot thành công**,
không phải lỗi.

## Vì sao kernel phải viết lại driver

Kernel có driver ATA, GPT và FAT32 riêng, trùng chức năng với firmware. Đây không
phải cẩu thả:

> `ExitBootServices` chính là thời điểm driver của firmware **ngừng tồn tại**.

Sau lệnh đó, code duy nhất còn chạy là code trong image này. Muốn đọc 4 program
từ đĩa thì phải có driver của mình. Ba file `kata.asm`, `kgpt.asm`, `kfat.asm` là
bản tối thiểu vừa đủ để boot: chỉ primary master, PIO polled, LBA28, chỉ đọc; chỉ
GPT; FAT32 tên ngắn.

Đây cũng là lý do `make ovmfk` dùng máy i440fx chứ không phải q35 — kernel tự
điều khiển các cổng ATA legacy, còn đĩa của q35 nằm sau AHCI.

Bàn phím thì khác một chút: nó **không** phải bản copy. Firmware polling, còn
kernel dùng interrupt — và một cái poller thì không bao giờ thấy break code, nên
nó không thể biết Shift có đang được giữ hay không. Hai thiết kế khác nhau cho
cùng một thiết bị.

> **Lưu ý khi grep:** `kbd_init`, `kbd_wait_read`, `kbd_wait_write` được định
> nghĩa **hai lần trong cây** — một lần ở `src/efi_proto.asm`, một lần ở
> `kernel/kbd.asm`. Disk stack tránh được nhờ tiền tố `k`; bàn phím thì không.
> Không có gì hỏng, vì hai image không thấy source của nhau, nhưng grep sẽ trả về
> hai hàm không liên quan và chỉ số dòng phân biệt được chúng.

## Cô lập task: chỉ một entry khác nhau

Đây là phần đẹp nhất của kernel, và nó đơn giản hơn nhiều người tưởng.

Mỗi task có một không gian địa chỉ riêng. Mọi không gian **giống nhau y hệt** trừ
đúng một entry:

- 4 GiB thấp được identity map bằng page 2 MiB, đánh dấu **supervisor**. Nhờ vậy
  kernel với tới được từ bất kỳ không gian nào đang nạp.
- Cộng thêm **đúng một page 2 MiB** có bit `U/S` — chính là window của task đó.

Bit `U/S` được đặt ở PML4[0] và PDPT[0..3], rồi để cho leaf quyết định, vì quyền
truy cập chỉ được cấp khi **mọi cấp đều đồng ý**. Một entry khác nhau duy nhất đó
chính là toàn bộ sự cô lập: một task không thể gọi tên window của task khác, vì
trong không gian của nó, cái window đó **không có mapping user nào để đi qua**.

Task 2 (`ROGUE.BIN`) tồn tại để chứng minh đúng điều này, và nó chết vì `#PF`
error code 5.

## Ngữ cảnh task nằm trên stack, không trong struct

Struct task **không có vùng lưu thanh ghi nào cả**. Thanh ghi của một task nằm
trên kernel stack của chính nó, nên:

- lưu ngữ cảnh = **một** lệnh store `RSP`
- phục hồi = **một** lệnh load

Cái này mua được một thứ quan trọng: **một task chưa từng chạy và một task bị
ngắt giữa lệnh có cùng hình dạng**, nên một đường code khởi động được cả hai.
`task_create` chỉ đơn giản là viết ra cái frame mà một interrupt sẽ để lại.

Từ đó nảy ra một vấn đề thú vị: nếu một task nhường CPU **bên trong một system
call** thì sao? Lúc đó trạng thái của nó rải trên một stack frame mà bộ switch
không hiểu — bộ switch chỉ hiểu interrupt frame. Giải pháp:

> Kernel tự raise một interrupt vào chính nó — `int 0x81`, trên một gate mà ring
> 3 không chạm tới được — để biến cái này thành cái kia.

Một định dạng lưu, một đường quay lại.

## Khoá console, không phải chặn interrupt

System call chạy với interrupt **đang bật**, nên hai task có thể đang ghi cùng
lúc. Thứ giữ chúng không trộn vào nhau là một **mutex**, không phải việc mask
timer:

- `con_acquire` — test-and-set với interrupt tắt. Nếu khoá đang do người khác
  giữ: đặt `T_WAITCON`, block, và `int VEC_SCHED`; khi quay lại thì test lại.
  Re-entrant với chủ khoá.
- `con_release` — xoá chủ, đánh thức **mọi** waiter. Một lần đánh thức sớm chỉ
  tốn thêm một vòng `con_acquire` và không gì khác.
- `con_release_if_owned` — gọi từ `sys_exit` và `task_faulted`, vì một task chết
  khi đang giữ console sẽ làm những task khác block mãi mãi.

Khoá được giữ trên **cả buffer**, không phải từng ký tự: mục đích là một dòng
phải tới nguyên vẹn.

Phiên bản trước của đoạn này xoá `IF` cho cả system call, và một lệnh ghi 3 KB
giữ nguyên cả cái máy trong một phần tư giây. Đó là lý do nó được đổi.

## Virtual wire: 8259 lập trình đúng mà nối vào hư không

Ba bước theo thứ tự, và thứ tự là điểm chính:

**`lapic_init`** — base `0xFEE00000`: ghi `0x1FF` vào spurious vector register để
software-enable APIC, đặt `LVT LINT0` sang chế độ ExtINT, `LVT LINT1` sang NMI.

Lý do bước này tồn tại: QEMU chỉ chuyển một interrupt của PIC tới CPU khi local
APIC bị hardware-disable **hoặc** LINT0 đang không bị mask — và lúc reset thì mọi
LVT entry đều bị mask. Nghĩa là nếu thiếu bước này, một 8259 được lập trình hoàn
toàn đúng sẽ **nối vào hư không**. BIOS gọi đây là virtual wire mode; asmfw không
bao giờ làm việc này, vì chưa từng có gì cần tới interrupt.

**`pic_init`** — ICW1, đặt vector base `0x20` và `0x28`, cascade trên IRQ2, ICW4,
rồi mask tất cả trừ IRQ0. Nếu để nguyên như firmware để lại, IRQ0 sẽ tới dưới
dạng vector 8 — tức `#DF`, không phân biệt được với việc CPU bỏ cuộc.

**`pit_init`** — channel 0, mode 2 (rate generator), divisor `1193182 / 100`, cho
`TICK_HZ` = 100 và `MS_PER_TICK` = 10.

**`timer_check`** — rồi *chứng minh* tick thật sự tới, trước khi có gì phụ thuộc
vào nó: quay một vòng có giới hạn với interrupt bật, xem `g_ticks` có đổi không,
ở ring 0 nơi câu trả lời không mơ hồ.

Lý do bước cuối tồn tại đáng ghi nhớ:

> Một scheduler mà timer không bao giờ chạy **trông giống hệt** một scheduler
> hoạt động tốt nhưng chưa bao giờ được yêu cầu switch.

## Bảng tra nhanh

| Thứ | Giá trị |
| --- | --- |
| Số task | 4 |
| Tick | 100 Hz, tức 10 ms |
| Kích thước struct task | `0x58` byte |
| Trạng thái task | free 0, ready 1, dead 2, blocked 3 |
| Window mỗi task | 2 MiB, program tối đa 1 MiB (nửa còn lại là stack) |
| Vector | `0x20` timer, `0x21` bàn phím, `0x81` kernel tự gọi |
| Selector ring 3 | `0x2B` code, và log in ra `sysret will enter cs 002b` |
| Queue bàn phím | 32 byte, tràn thì bỏ |

Blocked là **một** trạng thái nhưng **ba** lý do, và chúng không loại trừ nhau:
một task trong `sys_read` có timeout thì đang chờ bàn phím *và* đồng hồ cùng lúc.
Cái nào tới trước cũng xoá cả hai, rồi task tự test lại để biết đó là cái nào.

Chi tiết từng hàm, số dòng, ai gọi ai: [modules/](modules/README.md).

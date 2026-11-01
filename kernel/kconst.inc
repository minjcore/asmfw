; ============================================================================
; kconst.inc -- what the kernel is built out of
; ============================================================================

; ---------------------------------------------------------------------------
; The GDT.
;
; The order is not free. SYSRET computes its selectors by arithmetic on one
; base: with REX.W it loads CS from base+16 and SS from base+8, and forces
; RPL 3 into both. So user data must sit one slot above the base and user
; code64 two slots above it, or SYSRET lands on the wrong descriptors. The
; 32-bit user code slot exists only to be that base.
; ---------------------------------------------------------------------------
KSEL_NULL       equ 0x00
KSEL_CODE       equ 0x08                    ; ring 0, 64-bit
KSEL_DATA       equ 0x10                    ; ring 0
USEL_CODE32     equ 0x18 | 3                ; the base SYSRET counts from
USEL_DATA       equ 0x20 | 3
USEL_CODE       equ 0x28 | 3                ; ring 3, 64-bit
KSEL_TSS        equ 0x30                    ; a system descriptor: 16 bytes

GDT_ENTRIES     equ 8                       ; the TSS takes the last two

; Long-mode descriptors, spelled out. G=1, and the limit is ignored for
; 64-bit code and data, but a limit of 0xFFFFF keeps the 32-bit slot honest.
DESC_KCODE      equ 0x00AF9A000000FFFF
DESC_KDATA      equ 0x00CF92000000FFFF
DESC_UCODE32    equ 0x00CFFA000000FFFF
DESC_UDATA      equ 0x00CFF2000000FFFF
DESC_UCODE      equ 0x00AFFA000000FFFF

TSS_SIZE        equ 104
TSS_RSP0        equ 0x04
TSS_IOMAP       equ 0x66
TSS_DESC_TYPE   equ 0x89                    ; present, DPL 0, available 64-bit TSS

; ---------------------------------------------------------------------------
; The IDT. Every vector gets a stub, and the stubs are a fixed size so that
; the address of vector N is arithmetic rather than a table of pointers --
; which matters in a `org 0` image, where a stored label is a file offset and
; not the address the code will run at.
; ---------------------------------------------------------------------------
IDT_ENTRIES     equ 256
IDT_ENTRY_SIZE  equ 16
IDT_TYPE_INT    equ 0x8E                    ; present, DPL 0, 64-bit interrupt gate

ISR_STUB_SIZE   equ 16

; Vectors the CPU pushes an error code for: 8, 10..14, 17, 21, 29, 30. Their
; stubs must not push a second one, or every frame after it is off by eight.
ISR_ERR_MASK    equ 0x60227D00

VEC_NAME_LEN    equ 4
VEC_NAMED       equ 32

; ---------------------------------------------------------------------------
; Paging. One 4 GiB identity map in 2 MiB pages, plus a single 2 MiB window
; the user task is allowed to touch.
; ---------------------------------------------------------------------------
PTE_P           equ 0x001
PTE_RW          equ 0x002
PTE_US          equ 0x004
PTE_PS          equ 0x080

PAGE_SIZE       equ 0x1000
BIG_PAGE_SIZE   equ 0x200000
BIG_PAGE_SHIFT  equ 21
PT_ENTRIES      equ 512
PT_PDPT_USED    equ 4                       ; four PDs: the low 4 GiB
PT_PAGE_COUNT   equ 1 + 1 + PT_PDPT_USED    ; PML4, PDPT, and those PDs

; The window is one 2 MiB page, so it has to be 2 MiB aligned. Boot services
; hand out page-aligned memory and nothing stronger, so the request is large
; enough to contain an aligned window wherever it lands.
USER_WINDOW_SIZE  equ BIG_PAGE_SIZE
USER_ALLOC_PAGES  equ (USER_WINDOW_SIZE * (TASK_COUNT + 1)) / PAGE_SIZE
PT_ALLOC_PAGES    equ PT_PAGE_COUNT * (TASK_COUNT + 1)

; ---------------------------------------------------------------------------
; MSRs behind SYSCALL/SYSRET
; ---------------------------------------------------------------------------
MSR_EFER        equ 0xC0000080
MSR_STAR        equ 0xC0000081
MSR_LSTAR       equ 0xC0000082
MSR_FMASK       equ 0xC0000084
EFER_SCE        equ 0x001

; Flags cleared on entry to the kernel. IF matters most: it makes the syscall
; path uninterruptible without the kernel having to say so.
RFLAGS_IF       equ 0x0200
RFLAGS_TF       equ 0x0100
RFLAGS_DF       equ 0x0400
RFLAGS_RESERVED equ 0x0002
SYSCALL_FMASK   equ RFLAGS_IF | RFLAGS_TF | RFLAGS_DF
RFLAGS_USER     equ RFLAGS_RESERVED | RFLAGS_IF

; The system call ABI, shared verbatim with the programs so the two cannot
; drift apart.
%include "uabi.inc"

; ---------------------------------------------------------------------------
; Kernel sizes
; ---------------------------------------------------------------------------
KSTACK_SIZE     equ 0x4000
MEMMAP_BUF_SIZE equ 0x4000
MAP_RETRIES     equ 3

; ---------------------------------------------------------------------------
; The local APIC, in the one role this kernel needs from it.
;
; QEMU only hands a PIC interrupt to the CPU when the local APIC is either
; hardware-disabled or has LINT0 unmasked. Out of reset every LVT entry is
; masked, and asmfw never touches the APIC, so the 8259's output reaches
; nothing at all. Programming LINT0 as ExtINT is what a BIOS calls virtual
; wire mode, and without it the timer below is silent.
; ---------------------------------------------------------------------------
LAPIC_BASE      equ 0xFEE00000
LAPIC_SVR       equ 0x0F0
LAPIC_LVT_LINT0 equ 0x350
LAPIC_LVT_LINT1 equ 0x360
LAPIC_SVR_ENABLE equ 0x100
LAPIC_SPURIOUS  equ 0x0FF
LVT_MODE_EXTINT equ 0x700
LVT_MODE_NMI    equ 0x400

; ---------------------------------------------------------------------------
; The legacy PIC, remapped off the vectors the CPU reserves for exceptions.
; Left where the firmware puts it, IRQ0 would arrive as #DF.
; ---------------------------------------------------------------------------
PIC1_CMD        equ 0x20
PIC1_DATA       equ 0x21
PIC2_CMD        equ 0xA0
PIC2_DATA       equ 0xA1
PIC_EOI         equ 0x20
PIC_ICW1_INIT   equ 0x11                    ; edge triggered, cascade, want ICW4
PIC_ICW4_8086   equ 0x01
PIC1_VECTOR     equ 0x20
PIC2_VECTOR     equ 0x28
PIC1_CASCADE    equ 0x04                    ; the slave hangs off IRQ2
PIC2_IDENTITY   equ 0x02
PIC_MASK_ALL    equ 0xFF
PIC1_TIMER_ONLY equ 0xFE
PIC_IRQ1_BIT    equ 0x02                    ; the keyboard opens its own gate
PIC_IRQ1_ALLOW  equ 0xFD                    ; and this is that bit, ANDed out
PORT_IO_WAIT    equ 0x80                    ; a write here costs a bus cycle

VEC_TIMER       equ PIC1_VECTOR
VEC_KBD         equ PIC1_VECTOR + 1

; The vector the kernel raises against itself to reschedule.
;
; A task that gives up the CPU inside a system call has its state spread
; across a stack frame that sched_run cannot resume: the switch understands
; interrupt frames and nothing else. Raising an interrupt turns the one into
; the other, so there is a single save format and a single way back in. The
; gate is DPL 0, so ring 3 asking for it directly gets #GP.
VEC_SCHED       equ 0x81

; ---------------------------------------------------------------------------
; The 8254, as the thing that takes the CPU away from a task
; ---------------------------------------------------------------------------
PIT_CH0         equ 0x40
PIT_CMD         equ 0x43
PIT_RATE_GEN    equ 0x34                    ; channel 0, lo/hi, mode 2, binary
PIT_INPUT_HZ    equ 1193182
TICK_HZ         equ 100
PIT_DIVISOR     equ PIT_INPUT_HZ / TICK_HZ
TIMER_CHECK_SPIN equ 200000000              ; far longer than one tick

; ---------------------------------------------------------------------------
; The i8042, as the one thing on this machine that nothing here can produce.
;
; The firmware polls this controller; the kernel takes it on IRQ1 instead, and
; the difference is not a preference. A poller sees the controller only at the
; instant it looks, so it discards every break code and cannot know whether
; shift is still down. An interrupt sees every transition.
; ---------------------------------------------------------------------------
KBD_DATA        equ 0x60
KBD_STATUS      equ 0x64
KBD_STATUS_OBF  equ 0x01                    ; output buffer full: a byte to read
KBD_STATUS_IBF  equ 0x02                    ; input buffer full: do not write

; The controller's command byte, and the two bits of it that matter here.
;
; Out of reset QEMU sets the interrupt bit and leaves translation clear, and a
; PS/2 keyboard's own default is scan code set 2. So the codes that arrive are
; set 2 codes, and a set 1 table decodes them into other keys entirely --
; quietly, because most of them are still valid indices. On a normal PC the
; BIOS turns translation on. There is no BIOS here that has done it.
KBD_CMD_READ_MODE   equ 0x20
KBD_CMD_WRITE_MODE  equ 0x60
KBD_MODE_KBD_INT    equ 0x01                ; IRQ1 on a byte from the keyboard
KBD_MODE_KBD_OFF    equ 0x10                ; the interface, switched off
KBD_MODE_KBD_ON     equ 0xEF                ; and that bit, ANDed back out
KBD_MODE_XLAT       equ 0x40                ; translate set 2 down to set 1
KBD_WAIT_SPIN       equ 100000              ; bounded: a dead controller is a
                                            ; keyboard that never works, not a
                                            ; kernel that never boots
KBD_BREAK       equ 0x80                    ; set in the code for a release
KBD_CODE_MASK   equ 0x7F                    ; and the code with it taken off
KBD_PREFIX_EXT  equ 0xE0                    ; and the byte after it is the key
KBD_LSHIFT      equ 0x2A
KBD_RSHIFT      equ 0x36
KBD_DRAIN_MAX   equ 64                      ; bytes tolerated before giving up

; Scan code set 1, up to the space bar. Nothing above that has a character.
KBD_TABLE_LEN   equ 0x3A

; A power of two, so the wrap is a mask. Deep enough that a burst of typing
; survives a task holding the console, and no deeper: a queue that outlives
; the interest in its contents is a queue of stale keys.
KBD_BUF_SIZE    equ 32
KBD_BUF_MASK    equ KBD_BUF_SIZE - 1

; ---------------------------------------------------------------------------
; Tasks.
;
; Each one owns an address space, a window inside it, and a kernel stack. The
; kernel stack is where its registers live while it is not running: a switch
; is a store of RSP into T_RSP and a load of the next task's, which is why
; there is no register save area in the structure.
; ---------------------------------------------------------------------------
TASK_COUNT      equ 5

T_STATE         equ 0x00
T_PML4          equ 0x08
T_USER_BASE     equ 0x10
T_KSTACK        equ 0x18                    ; top of its kernel stack
T_RSP           equ 0x20                    ; where that stack was left
T_URSP          equ 0x28                    ; the user stack, across a syscall
T_ID            equ 0x30
T_STATUS        equ 0x38                    ; what it passed to sys_exit
T_WAKE          equ 0x40                    ; the tick it is sleeping until
T_WAITCON       equ 0x48                    ; set while it wants the console
T_WAITKEY       equ 0x50                    ; set while it wants a keystroke
T_SIZE          equ 0x58

TASK_FREE       equ 0
TASK_READY      equ 1
TASK_DEAD       equ 2

; Blocked is one state and three reasons, and the reasons are not exclusive: a
; task in sys_read with a timeout is waiting on the keyboard and on the clock
; at once. Whichever arrives first makes it runnable and cancels the other,
; and the task re-tests on the way through to learn which it was.
TASK_BLOCKED    equ 3

MS_PER_TICK     equ 1000 / TICK_HZ

; The register file, in the order the switch depends on. An interrupted task
; and a task that has never run look identical from here down, which is what
; lets one code path start both.
GPR_COUNT       equ 15
GPR_BYTES       equ GPR_COUNT * 8

; Where the argument registers sit in a fabricated frame, counted in the order
; POP_GPRS consumes them. This is how a task is told what it is.
FRAME_RDI       equ 8 * 8
FRAME_RSI       equ 9 * 8
FRAME_RDX       equ 12 * 8

; A program is read straight into the window it will run in, so it has to
; leave room for its own stack at the top of that window.
PROG_MAX_BYTES  equ USER_WINDOW_SIZE / 2
PROG_NAME_LEN   equ 11

%macro PUSH_GPRS 0
    push    rax
    push    rcx
    push    rdx
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
%endmacro

%macro POP_GPRS 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    pop     rdx
    pop     rcx
    pop     rax
%endmacro

; ---------------------------------------------------------------------------
; Console
; ---------------------------------------------------------------------------
KCOM1           equ 0x3F8
UART_IER        equ 1
UART_FCR        equ 2
UART_LCR        equ 3
UART_MCR        equ 4
UART_LSR        equ 5
UART_LCR_DLAB   equ 0x80
UART_LCR_8N1    equ 0x03
UART_FCR_ON     equ 0xC7
UART_MCR_ON     equ 0x0B
UART_LSR_THRE   equ 0x20
UART_DIV_115200 equ 1

KC_MARGIN_X     equ 8
KC_MARGIN_Y     equ 8
KC_FG           equ 0x00C8C8C8
KC_BG           equ 0x00000000
KC_HI           equ 0x00F0D060
KC_ERR          equ 0x00F06060
KC_NUMBUF_SIZE  equ 24

CHAR_LF         equ 10
CHAR_CR         equ 13
CHAR_BS         equ 8

; ---------------------------------------------------------------------------
; The parts of the UEFI ABI the kernel uses before it stops using any of it
; ---------------------------------------------------------------------------
ST_CONOUT           equ 0x40
ST_BOOTSERVICES     equ 0x60
ST_NUMTABLEENTRIES  equ 0x68
ST_CONFIGTABLE      equ 0x70

TO_OUTPUTSTRING     equ 0x08
TO_CLEARSCREEN      equ 0x30

BS_ALLOCATEPAGES    equ 0x28
BS_GETMEMORYMAP     equ 0x38
BS_EXITBOOTSERVICES equ 0xE8
BS_LOCATEPROTOCOL   equ 0x140

GOP_MODE            equ 0x18
MODE_INFO           equ 0x08
MODE_FBBASE         equ 0x18
INFO_HRES           equ 0x04
INFO_VRES           equ 0x08
INFO_PPSL           equ 0x20

AllocateAnyPages    equ 0
EfiLoaderData       equ 2

GUID_SIZE           equ 16
CFG_TABLE_PTR       equ 16
CFG_ENTRY_SIZE      equ 24

; ---------------------------------------------------------------------------
%macro KSTR 2-*
%1: db %{2:-1}, 0
%endmacro

%macro kputs 1
    lea     rsi, [rel %1]
    call    kc_puts
%endmacro

; An inline literal. The jump is pinned to five bytes for the same reason the
; firmware pins its own: left to shrink, it moves every label behind it and
; the assembler's passes stop converging.
%macro kputsi 1-*
    jmp     strict near %%past
%%str:  db %{1:-1}, 0
%%past:
    lea     rsi, [rel %%str]
    call    kc_puts
%endmacro

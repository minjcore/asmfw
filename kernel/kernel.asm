; ============================================================================
; kernel.asm -- a kernel that asmfw boots, and that gets to ring 3
;
; It is a UEFI application in the same sense payload/hello.asm is: hand-written
; PE32+ headers, one flat binary, no linker. What makes it a kernel rather
; than an application is what it does after ExitBootServices -- from that call
; onwards there is no firmware left to ask for anything, and every table the
; CPU consults is one this image built.
;
;   nasm -f bin -I ../src/ -I . -o BOOTX64.EFI kernel.asm
;
; The two phases are worth keeping straight while reading:
;
;   before ExitBootServices   boot services exist; the kernel uses them to
;                             find the framebuffer and to take the memory it
;                             will still need afterwards
;   after                     nothing exists but the machine. CR3, GDT, TSS,
;                             IDT and the SYSCALL MSRs are all replaced before
;                             anything else happens.
; ============================================================================

bits 64
default rel
org 0

IMAGE_BASE      equ 0x0000000140000000
SECT_ALIGN      equ 0x1000
FILE_ALIGN      equ 0x1000
TEXT_RVA        equ 0x1000
TEXT_SIZE       equ 0x60000
IMAGE_SIZE      equ TEXT_RVA + TEXT_SIZE

%macro WSTR 2
%1: dw __utf16le__(%2), 0
%endmacro

; ----------------------------------------------------------------------------
; DOS header
; ----------------------------------------------------------------------------
            db 'MZ'
            times 0x3A db 0
            dd pe_signature                 ; e_lfanew, at offset 0x3C

; ----------------------------------------------------------------------------
; COFF header
; ----------------------------------------------------------------------------
pe_signature:
            db 'PE', 0, 0
            dw 0x8664                       ; Machine: x86-64
            dw 1                            ; NumberOfSections
            dd 0                            ; TimeDateStamp
            dd 0                            ; PointerToSymbolTable
            dd 0                            ; NumberOfSymbols
            dw opt_end - opt_start          ; SizeOfOptionalHeader
            dw 0x002E                       ; executable, symbols stripped,
                                            ; large address aware

; ----------------------------------------------------------------------------
; Optional header, PE32+ form
; ----------------------------------------------------------------------------
opt_start:
            dw 0x020B                       ; PE32+
            db 0, 0                         ; linker version
            dd TEXT_SIZE                    ; SizeOfCode
            dd 0                            ; SizeOfInitializedData
            dd 0                            ; SizeOfUninitializedData
            dd kmain                        ; AddressOfEntryPoint
            dd TEXT_RVA                     ; BaseOfCode
            dq IMAGE_BASE
            dd SECT_ALIGN
            dd FILE_ALIGN
            dw 0, 0                         ; OS version
            dw 0, 0                         ; image version
            dw 0, 0                         ; subsystem version
            dd 0                            ; Win32VersionValue
            dd IMAGE_SIZE
            dd FILE_ALIGN                   ; SizeOfHeaders
            dd 0                            ; CheckSum: unused for EFI
            dw 10                           ; Subsystem: EFI application
            dw 0                            ; DllCharacteristics
            dq 0x10000, 0x10000             ; stack reserve, commit
            dq 0x10000, 0x10000             ; heap reserve, commit
            dd 0                            ; LoaderFlags
            dd 16                           ; NumberOfRvaAndSizes
            times 16 dq 0                   ; no data directories, no .reloc
opt_end:

; ----------------------------------------------------------------------------
; Section table
; ----------------------------------------------------------------------------
            db '.text', 0, 0, 0
            dd TEXT_SIZE                    ; VirtualSize
            dd TEXT_RVA                     ; VirtualAddress
            dd TEXT_SIZE                    ; SizeOfRawData
            dd TEXT_RVA                     ; PointerToRawData
            dd 0                            ; PointerToRelocations
            dd 0                            ; PointerToLinenumbers
            dw 0                            ; NumberOfRelocations
            dw 0                            ; NumberOfLinenumbers
            dd 0xE0000020                   ; code, readable, writable

            times TEXT_RVA - ($ - $$) db 0

; ============================================================================
%include "kconst.inc"

; ============================================================================
; Phase one: boot services are alive
; ============================================================================

; ----------------------------------------------------------------------------
; kmain(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
;
; Never returns. The forty bytes of stack reserved below are the Microsoft
; x64 shadow space plus one slot, because GetMemoryMap takes five arguments
; and the fifth goes on the stack.
; ----------------------------------------------------------------------------
kmain:
            push    rbp
            push    rbx
            push    rsi
            push    rdi
            sub     rsp, 40

            mov     [rel g_image], rcx
            mov     [rel g_st], rdx
            mov     rax, [rdx + ST_CONOUT]
            mov     [rel g_conout], rax
            mov     rax, [rdx + ST_BOOTSERVICES]
            mov     [rel g_bs], rax

            mov     rbx, [rel g_conout]
            mov     rcx, rbx
            call    [rbx + TO_CLEARSCREEN]
            mov     rcx, rbx
            lea     rdx, [rel w_banner]
            call    [rbx + TO_OUTPUTSTRING]

            ; --- the framebuffer, which outlives the protocol describing it --
            mov     rbx, [rel g_bs]
            lea     rcx, [rel gop_guid]
            xor     rdx, rdx
            lea     r8, [rel g_gop]
            call    [rbx + BS_LOCATEPROTOCOL]
            test    rax, rax
            jnz     .no_gop

            mov     rax, [rel g_gop]
            mov     rax, [rax + GOP_MODE]
            mov     rcx, [rax + MODE_FBBASE]
            mov     [rel kc_fb], rcx
            mov     rcx, [rax + MODE_INFO]
            mov     edx, [rcx + INFO_HRES]
            mov     [rel kc_w], edx
            mov     edx, [rcx + INFO_VRES]
            mov     [rel kc_h], edx
            mov     edx, [rcx + INFO_PPSL]
            shl     edx, 2                  ; pixels per scanline -> bytes
            mov     [rel kc_pitch], edx
            mov     dword [rel kc_fb_ok], 1
.no_gop:

            ; --- the RSDP, while there is still a table listing it -----------
            mov     rax, [rel g_st]
            mov     r8, [rax + ST_NUMTABLEENTRIES]
            mov     r9, [rax + ST_CONFIGTABLE]
.config:
            test    r8, r8
            jz      .config_done
            lea     rsi, [rel acpi20_guid]
            mov     rdi, r9
            mov     ecx, GUID_SIZE
            repe cmpsb
            jne     .config_next
            mov     rax, [r9 + CFG_TABLE_PTR]
            mov     [rel g_rsdp], rax
            jmp     .config_done
.config_next:
            add     r9, CFG_ENTRY_SIZE
            dec     r8
            jmp     .config
.config_done:

            ; --- memory that has to survive the handover --------------------
            ; Taken through boot services rather than picked out of the map,
            ; so that the map the kernel inherits already accounts for it.
            mov     rbx, [rel g_bs]
            mov     rcx, AllocateAnyPages
            mov     rdx, EfiLoaderData
            mov     r8, PT_ALLOC_PAGES
            lea     r9, [rel g_pt_base]
            call    [rbx + BS_ALLOCATEPAGES]
            test    rax, rax
            jnz     .no_memory

            mov     rcx, AllocateAnyPages
            mov     rdx, EfiLoaderData
            mov     r8, USER_ALLOC_PAGES
            lea     r9, [rel g_user_raw]
            call    [rbx + BS_ALLOCATEPAGES]
            test    rax, rax
            jnz     .no_memory

            ; The windows are 2 MiB pages, so they need 2 MiB alignment that
            ; AllocatePages does not promise. The request was one window
            ; larger than needed, so an aligned run of them fits wherever it
            ; landed.
            mov     rax, [rel g_user_raw]
            add     rax, USER_WINDOW_SIZE - 1
            and     rax, -USER_WINDOW_SIZE
            mov     [rel g_user_base], rax

            mov     rbx, [rel g_conout]
            mov     rcx, rbx
            lea     rdx, [rel w_leaving]
            call    [rbx + TO_OUTPUTSTRING]

            ; --- ExitBootServices -------------------------------------------
            ; The map key proves the caller has seen the current map. Taking
            ; the map can itself change it, so a refusal is normal and the
            ; answer is to look again rather than to give up.
            mov     dword [rel g_retries], MAP_RETRIES
.attempt:
            mov     rbx, [rel g_bs]
            mov     qword [rel g_map_size], MEMMAP_BUF_SIZE
            lea     rcx, [rel g_map_size]
            lea     rdx, [rel g_memmap]
            lea     r8, [rel g_map_key]
            lea     r9, [rel g_desc_size]
            lea     rax, [rel g_desc_ver]
            mov     [rsp + 32], rax
            call    [rbx + BS_GETMEMORYMAP]
            test    rax, rax
            jnz     .no_map

            cli
            mov     rcx, [rel g_image]
            mov     rdx, [rel g_map_key]
            call    [rbx + BS_EXITBOOTSERVICES]
            test    rax, rax
            jz      kmain64

            sti
            dec     dword [rel g_retries]
            jnz     .attempt

.no_exit:
            lea     rdx, [rel w_no_exit]
            jmp     .give_up
.no_map:
            lea     rdx, [rel w_no_map]
            jmp     .give_up
.no_memory:
            lea     rdx, [rel w_no_memory]
            jmp     .give_up
.no_gop_fatal:
            lea     rdx, [rel w_no_gop]
.give_up:
            mov     rbx, [rel g_conout]
            mov     rcx, rbx
            call    [rbx + TO_OUTPUTSTRING]
.halt:
            cli
            hlt
            jmp     .halt

; ============================================================================
; Phase two: the machine, and nothing else
; ============================================================================
kmain64:
            lea     rsp, [rel kstack_top]
            xor     rbp, rbp

            call    kc_init
            mov     dword [rel kc_fg], KC_HI
            kputsi  10, "asmfw kernel", 10
            mov     dword [rel kc_fg], KC_FG
            kputsi  "boot services are gone; this console is the kernel's own", 10, 10

            ; The kernel's own address space has no user pages at all. Each
            ; task gets one of its own further down.
            mov     rdi, [rel g_pt_base]
            xor     rsi, rsi
            call    paging_build
            mov     cr3, rax
            kputsi  "paging   4 GiB identity mapped, "
            mov     eax, TASK_COUNT
            call    kc_putdec
            kputsi  " address spaces to follow", 10

            call    gdt_init
            kputsi  "gdt      kernel and user descriptors loaded, tss rsp0 armed", 10

            call    idt_init
            kputsi  "idt      "
            mov     eax, IDT_ENTRIES
            call    kc_putdec
            kputsi  " vectors, every one of them landing somewhere", 10

            call    lapic_init
            call    pic_init
            call    pit_init
            kputsi  "timer    8254 at "
            mov     eax, TICK_HZ
            call    kc_putdec
            kputsi  " Hz on vector "
            mov     eax, VEC_TIMER
            call    kc_putdec
            call    timer_check
            test    eax, eax
            jnz     .timer_ok
            kputsi  " -- NOT ARRIVING", 10
            jmp     .timer_done
.timer_ok:
            kputsi  ", ticking", 10
.timer_done:

            ; The keyboard after the timer, and not before it: a key that
            ; arrives while there is nobody to hand it to only has to be
            ; queued, and there is nowhere for it to go until the tick that
            ; would deliver it is known to arrive.
            call    kbd_init
            kputsi  "kbd      i8042 on vector "
            mov     eax, VEC_KBD
            call    kc_putdec
            kputsi  ", irq1 open, mode "
            movzx   eax, byte [rel g_kbd_mode_in]
            call    kc_puthex16
            kputsi  " -> "
            movzx   eax, byte [rel g_kbd_mode_out]
            call    kc_puthex16
            mov     al, CHAR_LF
            call    kc_putc

            call    syscall_init
            kputsi  "syscall  lstar armed; sysret will enter cs "
            mov     eax, USEL_CODE
            call    kc_puthex16
            mov     al, CHAR_LF
            call    kc_putc

            mov     rax, [rel g_rsdp]
            test    rax, rax
            jz      .no_acpi
            kputsi  "acpi     rsdp handed over by the firmware at "
            mov     rax, [rel g_rsdp]
            call    kc_puthex64
            mov     al, CHAR_LF
            call    kc_putc
.no_acpi:

            ; --- the disk, this time without any help ----------------------
            call    kata_init
            test    eax, eax
            jz      .no_disk
            kputsi  "ata      primary master, "
            mov     rax, [rel g_ata_sectors]
            shr     rax, 11
            call    kc_putdec
            kputsi  " MiB, polled", 10

            call    kgpt_find_esp
            test    eax, eax
            jz      .no_esp
            kputsi  "gpt      EFI system partition at LBA "
            mov     rax, [rel g_esp_lba]
            call    kc_putdec
            mov     al, CHAR_LF
            call    kc_putc

            call    kfat_mount
            test    eax, eax
            jz      .no_fs
            kputsi  "fat32    mounted, "
            mov     rax, [rel g_fat_spc]
            call    kc_putdec
            kputsi  " sectors per cluster", 10

            ; --- the tasks --------------------------------------------------
            xor     r12d, r12d
.create:
            mov     rax, r12
            imul    rax, USER_WINDOW_SIZE
            add     rax, [rel g_user_base]
            mov     r13, rax                    ; this task's window

            ; \PROGS\<name>, read straight into the window it will run in
            mov     eax, [rel g_fat_root]
            lea     rsi, [rel name_progs]
            call    kfat_lookup
            test    eax, eax
            jz      .no_prog
            test    cl, ATTR_DIRECTORY
            jz      .no_prog

            lea     rsi, [rel prog_names]
            mov     rcx, r12
            imul    rcx, PROG_NAME_LEN
            add     rsi, rcx
            call    kfat_lookup
            test    eax, eax
            jz      .no_prog
            test    cl, ATTR_DIRECTORY
            jnz     .no_prog
            test    rdx, rdx
            jz      .no_prog
            cmp     rdx, PROG_MAX_BYTES
            ja      .prog_too_big
            mov     r14, rdx                    ; its size

            mov     rdi, r13
            call    kfat_read_file
            test    eax, eax
            jz      .no_prog

            ; --- its address space ------------------------------------------
            mov     rdi, r12
            inc     rdi                         ; region 0 is the kernel's
            imul    rdi, PT_PAGE_COUNT * PAGE_SIZE
            add     rdi, [rel g_pt_base]
            mov     rsi, r13
            call    paging_build

            ; The neighbour it will be told about, and cannot reach.
            mov     rcx, r12
            inc     rcx
            cmp     rcx, TASK_COUNT
            jb      .have_sibling
            xor     ecx, ecx
.have_sibling:
            imul    rcx, USER_WINDOW_SIZE
            add     rcx, [rel g_user_base]

            mov     rdi, r12
            mov     rsi, r13
            mov     rdx, rax
            call    task_create

            kputsi  "task     "
            mov     rax, r12
            call    kc_putdec
            kputsi  "  window "
            mov     rax, r13
            call    kc_puthex64
            kputsi  "  "
            mov     rax, r14
            call    kc_putdec
            kputsi  " bytes from disk", 10

            inc     r12d
            cmp     r12d, TASK_COUNT
            jb      .create

            kputsi  10
            lea     rax, [rel tasks]
            jmp     sched_run

.no_disk:
            kputsi  "ata      nothing answers on the primary master", 10
            jmp     khalt
.no_esp:
            kputsi  "gpt      no EFI system partition on the disk", 10
            jmp     khalt
.no_fs:
            kputsi  "fat32    the partition is not readable FAT32", 10
            jmp     khalt
.prog_too_big:
            kputsi  "task     the program does not fit its window", 10
            jmp     khalt
.no_prog:
            kputsi  "task     could not read the program for task "
            mov     rax, r12
            call    kc_putdec
            mov     al, CHAR_LF
            call    kc_putc
            jmp     khalt

; ----------------------------------------------------------------------------
khalt:
            kputsi  10, "kernel   nothing left to run; halted", 10
.halt:
            cli
            hlt
            jmp     .halt

; ============================================================================
%include "kcon.asm"
%include "paging.asm"
%include "gdt.asm"
%include "idt.asm"
%include "syscall.asm"
%include "sched.asm"
%include "kbd.asm"
%include "kata.asm"
%include "kgpt.asm"
%include "kfat.asm"

; ----------------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------------
; The programs, and where they live. Eleven byte 8.3 names, space padded,
; exactly as FAT stores them; indexed rather than pointed at, for the same
; `org 0` reason as everything else in this image.
name_progs:     db "PROGS      "
prog_names:     db "MAZE    BIN"
                db "COUNT   BIN"
                db "ROGUE   BIN"
                db "TYPE    BIN"

align 8
gop_guid:                                   ; 9042A9DE-23DC-4A38-96FB-7ADED080516A
            dd 0x9042A9DE
            dw 0x23DC
            dw 0x4A38
            db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

acpi20_guid:                                ; 8868E871-E4F1-11D3-BC22-0080C73C8881
            dd 0x8868E871
            dw 0xE4F1
            dw 0x11D3
            db 0xBC, 0x22, 0x00, 0x80, 0xC7, 0x3C, 0x88, 0x81

WSTR w_banner,     `\r\n  asmfw kernel: starting, boot services still alive\r\n`
WSTR w_leaving,    `  taking the machine over; output continues on the kernel console\r\n`
WSTR w_no_map,     `  GetMemoryMap failed; cannot leave boot services\r\n`
WSTR w_no_exit,    `  ExitBootServices refused every attempt\r\n`
WSTR w_no_memory,  `  not enough memory to build an address space\r\n`
WSTR w_no_gop,     `  no graphics output protocol\r\n`

align 8
g_image:        dq 0
g_st:           dq 0
g_bs:           dq 0
g_conout:       dq 0
g_gop:          dq 0
g_rsdp:         dq 0
g_pt_base:      dq 0
g_user_raw:     dq 0
g_user_base:    dq 0
g_map_size:     dq 0
g_map_key:      dq 0
g_desc_size:    dq 0
g_desc_ver:     dd 0
g_retries:      dd 0

align 16
g_memmap:       times MEMMAP_BUF_SIZE db 0

align 16
kstack:         times KSTACK_SIZE db 0
kstack_top:

            times TEXT_RVA + TEXT_SIZE - ($ - $$) db 0

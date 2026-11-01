; ============================================================================
; hello.asm -- a UEFI application, PE32+ headers and all, in one flat binary
;
; This exists to test the firmware, so it is deliberately not built with a
; linker: the headers below are exactly what the firmware's PE loader has to
; understand, spelled out where they can be read.
;
; It is a real UEFI application, not a private format -- it runs under OVMF
; too, which is what makes it a useful control when the firmware misbehaves.
;
;   nasm -f bin -o BOOTX64.EFI hello.asm
;
; File offsets and RVAs are made equal by setting FileAlignment equal to
; SectionAlignment, so one `org 0` describes both the file and the loaded
; image and there is no offset arithmetic to get wrong.
; ============================================================================

bits 64
default rel
org 0

IMAGE_BASE      equ 0x0000000140000000
SECT_ALIGN      equ 0x1000
FILE_ALIGN      equ 0x1000
TEXT_RVA        equ 0x1000
TEXT_SIZE       equ 0x2000
IMAGE_SIZE      equ TEXT_RVA + TEXT_SIZE

%macro WSTR 2
%1: dw __utf16le__(%2), 0
%endmacro

; ----------------------------------------------------------------------------
; DOS header -- vestigial, but the PE signature is found through it.
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
            dd efi_main                     ; AddressOfEntryPoint
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
            ; No data directories are used. In particular there is no .reloc:
            ; every reference below is RIP-relative, so the image runs
            ; correctly wherever the loader decides to put it.
            times 16 dq 0
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
; Code
; ============================================================================

; EFI structure offsets, spelled out rather than pulled from a header.
ST_CONIN            equ 0x30
ST_CONOUT           equ 0x40
ST_BOOTSERVICES     equ 0x60
ST_NUMTABLEENTRIES  equ 0x68
ST_CONFIGTABLE      equ 0x70
ST_RUNTIMESERVICES  equ 0x58

; Runtime services, the variable calls.
RT_GETVARIABLE      equ 0x48
RT_GETNEXTVARNAME   equ 0x50
RT_SETVARIABLE      equ 0x58
VAR_BS_RT           equ 0x06            ; boot service and runtime access
VAR_BS_ONLY         equ 0x02
VAR_APPEND          equ 0x40
EFI_INVALID_PARAMETER equ 0x8000000000000002
VBUF_SIZE           equ 64
NBUF_SIZE           equ 512
EFI_BUFFER_TOO_SMALL equ 0x8000000000000005
EFI_NOT_FOUND       equ 0x800000000000000E

; EFI_CONFIGURATION_TABLE: a GUID, then the address it stands for.
GUID_SIZE           equ 16
CFG_TABLE_PTR       equ 16
CFG_ENTRY_SIZE      equ 24

; The RSDP, and the header every other ACPI table starts with.
RSDP_REVISION       equ 15
RSDP_RSDT           equ 16
RSDP_XSDT           equ 24
ACPI_REVISION_2     equ 2
SDT_SIGNATURE       equ 0
SDT_LENGTH          equ 4
SDT_HEADER_SIZE     equ 36
SIG_LENGTH          equ 4
RSDT_ENTRY_SIZE     equ 4
XSDT_ENTRY_SIZE     equ 8

; SMBIOS entry points, both kinds, and the structures they point at.
SM2_LENGTH          equ 0x05
SM2_MAJOR           equ 0x06
SM2_MINOR           equ 0x07
SM2_DMI             equ 0x10
SM2_DMI_LENGTH      equ 15
SM2_TABLE_LEN       equ 0x16
SM2_TABLE_ADDR      equ 0x18
SM3_LENGTH          equ 0x06
SM3_MAJOR           equ 0x07
SM3_MINOR           equ 0x08
SM3_TABLE_MAX       equ 0x0C
SM3_TABLE_ADDR      equ 0x10
SMS_TYPE            equ 0
SMS_LENGTH          equ 1
SMS_HEADER_SIZE     equ 4
SMS_TYPE_SYSTEM     equ 1
SMS_TYPE_END        equ 127
SMS1_MANUFACTURER   equ 4                   ; string numbers, in type 1
SMS1_PRODUCT        equ 5
STRBUF_CHARS        equ 80

TO_OUTPUTSTRING     equ 0x08
TO_SETATTRIBUTE     equ 0x28
TO_CLEARSCREEN      equ 0x30

TI_READKEYSTROKE    equ 0x08
KEY_SCANCODE        equ 0x00                ; UINT16
KEY_UNICODECHAR     equ 0x02                ; CHAR16
KEY_SCAN_DIGITS     equ 4
KEY_POLL_US         equ 10000               ; and 300 of them is three seconds
KEY_POLL_ROUNDS     equ 300

BS_STALL            equ 0xF8
BS_HANDLEPROTOCOL   equ 0x98
BS_LOCATEPROTOCOL   equ 0x140

LI_DEVICEHANDLE     equ 0x18

SFS_OPENVOLUME      equ 0x08

F_OPEN              equ 0x08
F_CLOSE             equ 0x10
F_READ              equ 0x20
F_GETINFO           equ 0x40

FI_FILESIZE         equ 0x08

EFI_FILE_MODE_READ  equ 1

GOP_MODE            equ 0x18
MODE_INFO           equ 0x08
MODE_FBBASE         equ 0x18
INFO_HRES           equ 0x04
INFO_VRES           equ 0x08
INFO_PPSL           equ 0x20

; ----------------------------------------------------------------------------
; efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
;
; Microsoft x64: arguments in RCX, RDX, R8, R9; the caller owns 32 bytes of
; shadow space above the return address; RSP must be 16-byte aligned at the
; point of the CALL; RBX, RBP, RSI, RDI and R12-R15 belong to the caller.
; ----------------------------------------------------------------------------
efi_main:
            push    rbp
            push    rbx
            push    rsi
            push    rdi
            sub     rsp, 40                 ; shadow space, and realigns RSP

            mov     [rel g_image], rcx
            mov     [rel g_st], rdx

            mov     rbx, [rdx + ST_CONOUT]
            mov     rsi, [rdx + ST_BOOTSERVICES]

            mov     rcx, rbx
            call    [rbx + TO_CLEARSCREEN]

            mov     rcx, rbx
            mov     rdx, 0x0E               ; yellow on black
            call    [rbx + TO_SETATTRIBUTE]

            mov     rcx, rbx
            lea     rdx, [rel s_banner]
            call    [rbx + TO_OUTPUTSTRING]

            mov     rcx, rbx
            mov     rdx, 0x07               ; light grey on black
            call    [rbx + TO_SETATTRIBUTE]

            mov     rcx, rbx
            lea     rdx, [rel s_running]
            call    [rbx + TO_OUTPUTSTRING]

            ; --- storage ----------------------------------------------------
            ; Reach the volume the way a real loader does: locate the file
            ; system, open the root, then open a path under it.
            lea     rcx, [rel sfs_guid]
            xor     rdx, rdx
            lea     r8, [rel g_sfs]
            call    [rsi + BS_LOCATEPROTOCOL]
            test    rax, rax
            jnz     .no_fs

            mov     rcx, [rel g_sfs]
            lea     rdx, [rel g_root]
            call    [rcx + SFS_OPENVOLUME]
            test    rax, rax
            jnz     .no_fs

            mov     rcx, [rel g_root]
            lea     rdx, [rel g_file]
            lea     r8, [rel s_selfpath]
            mov     r9, EFI_FILE_MODE_READ
            sub     rsp, 8
            push    0                           ; Attributes, on the stack
            sub     rsp, 32                     ; shadow space for the callee
            mov     rax, [rel g_root]
            call    [rax + F_OPEN]
            add     rsp, 48
            test    rax, rax
            jnz     .no_file

            ; Read the first two bytes back and check they are still "MZ" --
            ; proof the read path landed on the right cluster.
            mov     rcx, [rel g_file]
            lea     rdx, [rel g_readlen]
            mov     qword [rdx], 2
            lea     r8, [rel g_readbuf]
            mov     rax, [rel g_file]
            call    [rax + F_READ]
            test    rax, rax
            jnz     .no_file
            cmp     word [rel g_readbuf], 0x5A4D
            jne     .no_file

            mov     rcx, rbx
            lea     rdx, [rel s_fs_ok]
            call    [rbx + TO_OUTPUTSTRING]
            jmp     .acpi
.no_fs:
            mov     rcx, rbx
            lea     rdx, [rel s_fs_none]
            call    [rbx + TO_OUTPUTSTRING]
            jmp     .acpi
.no_file:
            mov     rcx, rbx
            lea     rdx, [rel s_fs_bad]
            call    [rbx + TO_OUTPUTSTRING]

.acpi:
            call    show_acpi
            call    show_smbios
            call    show_vars

.graphics:
            ; --- graphics ---------------------------------------------------
            lea     rcx, [rel gop_guid]
            xor     rdx, rdx
            lea     r8, [rel g_gop]
            call    [rsi + BS_LOCATEPROTOCOL]
            test    rax, rax
            jnz     .no_gop

            mov     rcx, rbx
            lea     rdx, [rel s_gop]
            call    [rbx + TO_OUTPUTSTRING]
            call    draw_bar
            jmp     .wait

.no_gop:
            mov     rcx, rbx
            lea     rdx, [rel s_nogop]
            call    [rbx + TO_OUTPUTSTRING]

.wait:
            ; --- input ------------------------------------------------------
            ; The last protocol nothing here exercised, which is why it was
            ; wrong for so long: a firmware that hands back the wrong letter
            ; is indistinguishable from one that works until somebody types.
            ;
            ; Polled rather than waited on, and over exactly the three seconds
            ; this program used to spend stalling for the look of it, so a run
            ; with nobody at the machine still ends by itself.
            mov     rdi, [rel g_st]
            mov     rdi, [rdi + ST_CONIN]
            test    rdi, rdi
            jz      .no_conin
            mov     r12d, KEY_POLL_ROUNDS
.poll:
            mov     rcx, rdi
            lea     rdx, [rel g_key]
            call    [rdi + TI_READKEYSTROKE]
            test    rax, rax
            jz      .got_key
            mov     rcx, KEY_POLL_US
            call    [rsi + BS_STALL]
            dec     r12d
            jnz     .poll

            mov     rcx, rbx
            lea     rdx, [rel s_no_key]
            call    [rbx + TO_OUTPUTSTRING]
            jmp     .bye

.got_key:
            ; A key with no character is a real answer, not a failure: the
            ; arrows and Esc report a scan code and leave UnicodeChar zero.
            movzx   eax, word [rel g_key + KEY_UNICODECHAR]
            test    ax, ax
            jnz     .have_char
            mov     ax, '.'
.have_char:
            mov     [rel s_key_char], ax
            movzx   eax, word [rel g_key + KEY_SCANCODE]
            lea     rdi, [rel s_key_scan]
            mov     ecx, KEY_SCAN_DIGITS
            call    hex_to_str

            mov     rcx, rbx
            lea     rdx, [rel s_key]
            call    [rbx + TO_OUTPUTSTRING]
            jmp     .bye

.no_conin:
            mov     rcx, rbx
            lea     rdx, [rel s_no_conin]
            call    [rbx + TO_OUTPUTSTRING]

.bye:
            mov     rcx, rbx
            lea     rdx, [rel s_bye]
            call    [rbx + TO_OUTPUTSTRING]

            xor     eax, eax                ; EFI_SUCCESS
            add     rsp, 40
            pop     rdi
            pop     rsi
            pop     rbx
            pop     rbp
            ret

; ----------------------------------------------------------------------------
; draw_bar -- paint a horizontal gradient across the bottom of the screen,
; straight into the framebuffer the GOP handed over.
; ----------------------------------------------------------------------------
BAR_HEIGHT  equ 48

draw_bar:
            push    rbx
            push    rsi
            push    rdi
            push    r12
            push    r13

            mov     rax, [rel g_gop]
            mov     rax, [rax + GOP_MODE]
            mov     rdi, [rax + MODE_FBBASE]
            mov     rsi, [rax + MODE_INFO]
            mov     r10d, [rsi + INFO_HRES]
            mov     r11d, [rsi + INFO_VRES]
            mov     r12d, [rsi + INFO_PPSL]
            shl     r12d, 2                 ; pixels per scanline -> bytes

            ; The bar sits BAR_HEIGHT + 16 rows up from the bottom edge.
            mov     eax, r11d
            sub     eax, BAR_HEIGHT + 16
            jbe     .done
            imul    eax, r12d
            add     rdi, rax

            mov     ecx, BAR_HEIGHT
.row:
            mov     rbx, rdi                ; start of this row
            xor     r9d, r9d                ; x
.col:
            ; ramp = x * 256 / width, so red climbs and blue falls across it
            mov     eax, r9d
            shl     eax, 8
            xor     edx, edx
            div     r10d
            mov     r13d, eax               ; 0..255

            shl     eax, 16                 ; red
            mov     edx, 255
            sub     edx, r13d
            or      eax, edx                ; blue
            or      eax, 0x00004000         ; a constant touch of green

            mov     [rbx], eax
            add     rbx, 4
            inc     r9d
            cmp     r9d, r10d
            jb      .col

            add     rdi, r12
            dec     ecx
            jnz     .row
.done:
            pop     r13
            pop     r12
            pop     rdi
            pop     rsi
            pop     rbx
            ret

; ----------------------------------------------------------------------------
; show_acpi -- find the ACPI tables through the configuration table, name each
; one, and check that it still checksums to zero.
;
; This is the part of the payload that tests the firmware hardest. QEMU hands
; firmware ACPI blobs whose cross-references are offsets, not addresses, and a
; script saying which ones to patch and which checksums to redo afterwards.
; Firmware that runs the script produces tables that sum to zero and point at
; each other; firmware that skips it produces tables that do neither. Walking
; the XSDT here reads every pointer the script was supposed to fix.
; ----------------------------------------------------------------------------
show_acpi:
            push    rbx
            push    rsi
            push    rdi
            push    r12
            push    r13
            push    rbp
            sub     rsp, 40

            mov     rbx, [rel g_st]
            mov     rbx, [rbx + ST_CONOUT]

            ; --- the ACPI 2.0 entry in the configuration table ---------------
            mov     rax, [rel g_st]
            mov     r12, [rax + ST_NUMTABLEENTRIES]
            mov     r13, [rax + ST_CONFIGTABLE]
            xor     ebp, ebp                    ; the RSDP, once found
.scan:
            test    r12, r12
            jz      .scanned
            lea     rsi, [rel acpi20_guid]
            mov     rdi, r13
            call    guid_eq
            jne     .scan_next
            mov     rbp, [r13 + CFG_TABLE_PTR]
            jmp     .scanned
.scan_next:
            add     r13, CFG_ENTRY_SIZE
            dec     r12
            jmp     .scan
.scanned:
            test    rbp, rbp
            jz      .none

            ; --- the root table, and how wide its entries are ----------------
            ; An ACPI 2.0 RSDP carries both; the XSDT is the one that can
            ; describe a table above 4 GiB, so it wins where it exists.
            cmp     byte [rbp + RSDP_REVISION], ACPI_REVISION_2
            jb      .use_rsdt
            mov     r13, [rbp + RSDP_XSDT]
            test    r13, r13
            jz      .use_rsdt
            mov     edi, XSDT_ENTRY_SIZE
            jmp     .have_root
.use_rsdt:
            mov     r13d, [rbp + RSDP_RSDT]
            test    r13, r13
            jz      .none
            mov     edi, RSDT_ENTRY_SIZE
.have_root:
            mov     eax, [r13 + SDT_LENGTH]
            cmp     eax, SDT_HEADER_SIZE
            jbe     .none
            sub     eax, SDT_HEADER_SIZE
            xor     edx, edx
            div     edi
            mov     r12d, eax                   ; how many tables it lists
            test    r12d, r12d
            jz      .none

            mov     rcx, rbx
            lea     rdx, [rel s_acpi]
            call    [rbx + TO_OUTPUTSTRING]

            mov     qword [rel g_acpi_bad], 0
            lea     rbp, [r13 + SDT_HEADER_SIZE]
.table:
            cmp     edi, XSDT_ENTRY_SIZE
            je      .wide
            mov     eax, [rbp]
            jmp     .have_table
.wide:
            mov     rax, [rbp]
.have_table:
            test    rax, rax
            jz      .table_next
            mov     rsi, rax

            call    sig_to_str
            mov     rcx, rbx
            lea     rdx, [rel g_sigbuf]
            call    [rbx + TO_OUTPUTSTRING]

            call    sum_table
            test    al, al
            jz      .table_next
            inc     qword [rel g_acpi_bad]
.table_next:
            add     rbp, rdi
            dec     r12d
            jnz     .table

            mov     rcx, rbx
            lea     rdx, [rel s_crlf]
            call    [rbx + TO_OUTPUTSTRING]

            mov     rcx, rbx
            lea     rdx, [rel s_acpi_ok]
            cmp     qword [rel g_acpi_bad], 0
            je      .verdict
            lea     rdx, [rel s_acpi_bad]
.verdict:
            call    [rbx + TO_OUTPUTSTRING]
            jmp     .done
.none:
            mov     rcx, rbx
            lea     rdx, [rel s_acpi_none]
            call    [rbx + TO_OUTPUTSTRING]
.done:
            add     rsp, 40
            pop     rbp
            pop     r13
            pop     r12
            pop     rdi
            pop     rsi
            pop     rbx
            ret

; ----------------------------------------------------------------------------
; show_smbios -- find the SMBIOS entry point through the configuration table,
; check its checksums, walk every structure to the end marker, and name the
; system from the type 1 structure.
;
; The firmware's part is small but every piece of it is checkable from here:
; the entry point's table address is the one field QEMU leaves for firmware
; to fill in, and filling it in invalidates the checksums. A firmware that
; skips either step leaves a pointer to nothing, or a sum that is not zero.
; The 3.x anchor is preferred where both exist, as a 64-bit reader would.
; ----------------------------------------------------------------------------
show_smbios:
            push    rbx
            push    rsi
            push    rdi
            push    r12
            push    r13
            push    rbp
            sub     rsp, 40

            lea     rsi, [rel smbios3_guid]
            call    find_config
            test    rax, rax
            jnz     .v3
            lea     rsi, [rel smbios_guid]
            call    find_config
            test    rax, rax
            jz      .none

            ; --- 2.x: "_SM_", two checksums, a 32-bit address and a length ----
            mov     rbp, rax
            cmp     dword [rbp], '_SM_'
            jne     .malformed
            mov     rsi, rbp
            movzx   ecx, byte [rbp + SM2_LENGTH]
            call    sum_bytes
            test    al, al
            jnz     .bad_sum
            lea     rsi, [rbp + SM2_DMI]
            mov     ecx, SM2_DMI_LENGTH
            call    sum_bytes
            test    al, al
            jnz     .bad_sum
            mov     r12d, [rbp + SM2_TABLE_ADDR]
            movzx   r13d, word [rbp + SM2_TABLE_LEN]
            movzx   eax, byte [rbp + SM2_MAJOR]
            movzx   edx, byte [rbp + SM2_MINOR]
            jmp     .walk

            ; --- 3.x: "_SM3_", one checksum, a 64-bit address and a bound ---
.v3:
            mov     rbp, rax
            cmp     dword [rbp], '_SM3'
            jne     .malformed
            cmp     byte [rbp + 4], '_'
            jne     .malformed
            mov     rsi, rbp
            movzx   ecx, byte [rbp + SM3_LENGTH]
            call    sum_bytes
            test    al, al
            jnz     .bad_sum
            mov     r12, [rbp + SM3_TABLE_ADDR]
            mov     r13d, [rbp + SM3_TABLE_MAX]
            movzx   eax, byte [rbp + SM3_MAJOR]
            movzx   edx, byte [rbp + SM3_MINOR]

.walk:
            mov     [rel g_smb_major], eax
            mov     [rel g_smb_minor], edx
            test    r12, r12
            jz      .torn
            add     r13, r12                    ; one past the end
            xor     ebx, ebx                    ; structures seen
            mov     qword [rel g_smb_sys], 0
.structure:
            lea     rax, [r12 + SMS_HEADER_SIZE]
            cmp     rax, r13
            ja      .torn
            inc     ebx
            mov     dil, [r12 + SMS_TYPE]
            cmp     dil, SMS_TYPE_SYSTEM
            jne     .not_system
            mov     [rel g_smb_sys], r12
.not_system:
            movzx   eax, byte [r12 + SMS_LENGTH]
            cmp     eax, SMS_HEADER_SIZE
            jb      .torn
            add     r12, rax
.strings:
            lea     rax, [r12 + 1]
            cmp     rax, r13
            jae     .torn
            cmp     word [r12], 0
            je      .strings_end
            inc     r12
            jmp     .strings
.strings_end:
            add     r12, 2
            cmp     dil, SMS_TYPE_END
            jne     .structure

            ; --- the verdict ------------------------------------------------
            lea     rdx, [rel s_smb]
            call    out_w
            mov     eax, [rel g_smb_major]
            call    out_dec
            lea     rdx, [rel s_dot]
            call    out_w
            mov     eax, [rel g_smb_minor]
            call    out_dec
            lea     rdx, [rel s_colon]
            call    out_w
            mov     eax, ebx
            call    out_dec
            lea     rdx, [rel s_smb_ok]
            call    out_w

            mov     rbp, [rel g_smb_sys]
            test    rbp, rbp
            jz      .done
            lea     rdx, [rel s_smb_sys]
            call    out_w
            mov     rsi, rbp
            mov     al, [rbp + SMS1_MANUFACTURER]
            call    smbios_string
            call    out_ascii
            lea     rdx, [rel s_space]
            call    out_w
            mov     rsi, rbp
            mov     al, [rbp + SMS1_PRODUCT]
            call    smbios_string
            call    out_ascii
            lea     rdx, [rel s_crlf]
            call    out_w
            jmp     .done

.none:
            lea     rdx, [rel s_smb_none]
            jmp     .say
.malformed:
            lea     rdx, [rel s_smb_malformed]
            jmp     .say
.bad_sum:
            lea     rdx, [rel s_smb_bad_sum]
            jmp     .say
.torn:
            lea     rdx, [rel s_smb_torn]
.say:
            call    out_w
.done:
            add     rsp, 40
            pop     rbp
            pop     r13
            pop     r12
            pop     rdi
            pop     rsi
            pop     rbx
            ret

; ----------------------------------------------------------------------------
; show_vars -- the variable services, end to end: set one, read it back with a
; buffer too small and then with one large enough, find it by enumerating
; every variable, delete it, and confirm it is gone.
;
; Each step has a wrong answer that would look right on its own. A store that
; ignored DataSize would pass the full read and fail the short one; a walk
; that never reached the end would never report EFI_NOT_FOUND; a delete that
; did nothing would leave the last read succeeding.
; ----------------------------------------------------------------------------
show_vars:
            push    rbx
            push    rsi
            push    rdi
            push    r12
            push    r13
            push    rbp
            sub     rsp, 40                     ; shadow space, and a fifth argument

            mov     rbx, [rel g_st]
            mov     rbx, [rbx + ST_RUNTIMESERVICES]
            mov     ebp, 1                      ; the step, for the failure message

            ; --- 1: set -----------------------------------------------------
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            mov     r8d, VAR_BS_RT
            mov     r9d, VAR_DATA_LEN
            lea     rax, [rel var_data]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_SETVARIABLE]
            test    rax, rax
            jnz     .fail

            ; --- 2: a read that cannot fit, which must say how much it needs --
            inc     ebp
            mov     qword [rel g_vsize], 1
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            lea     r8, [rel g_vattr]
            lea     r9, [rel g_vsize]
            lea     rax, [rel g_vbuf]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_GETVARIABLE]
            mov     rcx, EFI_BUFFER_TOO_SMALL
            cmp     rax, rcx
            jne     .fail
            cmp     qword [rel g_vsize], VAR_DATA_LEN
            jne     .fail

            ; --- 3: the real read -------------------------------------------
            inc     ebp
            mov     qword [rel g_vsize], VBUF_SIZE
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            lea     r8, [rel g_vattr]
            lea     r9, [rel g_vsize]
            lea     rax, [rel g_vbuf]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_GETVARIABLE]
            test    rax, rax
            jnz     .fail
            cmp     qword [rel g_vsize], VAR_DATA_LEN
            jne     .fail
            cmp     dword [rel g_vattr], VAR_BS_RT
            jne     .fail
            lea     rsi, [rel var_data]
            lea     rdi, [rel g_vbuf]
            mov     ecx, VAR_DATA_LEN
            repe    cmpsb
            jne     .fail

            ; --- 4: other attributes on the same variable must be refused ------
            inc     ebp
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            mov     r8d, VAR_BS_ONLY
            mov     r9d, VAR_DATA_LEN
            lea     rax, [rel var_data]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_SETVARIABLE]
            mov     rcx, EFI_INVALID_PARAMETER
            cmp     rax, rcx
            jne     .fail

            ; --- 5: append one byte, and read the longer value back -----------
            inc     ebp
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            mov     r8d, VAR_BS_RT | VAR_APPEND
            mov     r9d, 1
            lea     rax, [rel var_tail]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_SETVARIABLE]
            test    rax, rax
            jnz     .fail
            mov     qword [rel g_vsize], VBUF_SIZE
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            xor     r8d, r8d
            lea     r9, [rel g_vsize]
            lea     rax, [rel g_vbuf]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_GETVARIABLE]
            test    rax, rax
            jnz     .fail
            cmp     qword [rel g_vsize], VAR_DATA_LEN + 1
            jne     .fail
            mov     al, [rel var_tail]
            cmp     [rel g_vbuf + VAR_DATA_LEN], al
            jne     .fail

            ; --- 6: enumerate, to the end, and find it on the way ---------------
            inc     ebp
            mov     word [rel g_nbuf], 0
            xor     r12d, r12d                  ; how many variables
            xor     r13d, r13d                  ; whether ours was among them
.walk:
            mov     qword [rel g_nsize], NBUF_SIZE
            lea     rcx, [rel g_nsize]
            lea     rdx, [rel g_nbuf]
            lea     r8, [rel g_nguid]
            call    [rbx + RT_GETNEXTVARNAME]
            mov     rcx, EFI_NOT_FOUND
            cmp     rax, rcx
            je      .walked
            test    rax, rax
            jnz     .fail
            inc     r12d
            lea     rsi, [rel var_guid]
            lea     rdi, [rel g_nguid]
            call    guid_eq
            jne     .walk
            lea     rsi, [rel s_var_name]
            lea     rdi, [rel g_nbuf]
.name:
            mov     ax, [rsi]
            cmp     ax, [rdi]
            jne     .walk
            add     rsi, 2
            add     rdi, 2
            test    ax, ax
            jnz     .name
            inc     r13d
            jmp     .walk
.walked:
            test    r13d, r13d
            jz      .fail

            ; --- 7: delete, and see it gone -----------------------------------
            inc     ebp
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            mov     r8d, VAR_BS_RT
            xor     r9d, r9d
            mov     qword [rsp + 0x20], 0
            call    [rbx + RT_SETVARIABLE]
            test    rax, rax
            jnz     .fail
            inc     ebp
            mov     qword [rel g_vsize], VBUF_SIZE
            lea     rcx, [rel s_var_name]
            lea     rdx, [rel var_guid]
            xor     r8d, r8d
            lea     r9, [rel g_vsize]
            lea     rax, [rel g_vbuf]
            mov     [rsp + 0x20], rax
            call    [rbx + RT_GETVARIABLE]
            mov     rcx, EFI_NOT_FOUND
            cmp     rax, rcx
            jne     .fail

            lea     rdx, [rel s_var_ok]
            call    out_w
            mov     eax, r12d
            call    out_dec
            lea     rdx, [rel s_var_ok2]
            call    out_w
            jmp     .done

.fail:
            mov     r12, rax                    ; the status, whatever it was
            lea     rdx, [rel s_var_fail]
            call    out_w
            mov     eax, ebp
            call    out_dec
            lea     rdx, [rel s_var_status]
            call    out_w
            mov     rax, r12
            lea     rdi, [rel g_strbuf]
            mov     ecx, 16
            call    hex_to_str
            mov     word [rdi + 32], 0
            mov     rdx, rdi
            call    out_w
            lea     rdx, [rel s_crlf]
            call    out_w
.done:
            add     rsp, 40
            pop     rbp
            pop     r13
            pop     r12
            pop     rdi
            pop     rsi
            pop     rbx
            ret

; ----------------------------------------------------------------------------
; smbios_string -- RSI = a structure, AL = a 1-based string number.
; Returns RSI = that string, or a pointer to an empty one if it is absent.
; ----------------------------------------------------------------------------
smbios_string:
            push    rax
            push    rcx
            movzx   ecx, al
            test    ecx, ecx
            jz      .absent
            movzx   eax, byte [rsi + SMS_LENGTH]
            add     rsi, rax
.find:
            cmp     byte [rsi], 0
            je      .absent                     ; the set ended first
            dec     ecx
            jz      .found
.skip:
            inc     rsi
            cmp     byte [rsi - 1], 0
            jne     .skip
            jmp     .find
.absent:
            lea     rsi, [rel s_empty_a]
.found:
            pop     rcx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; find_config -- RSI = a GUID. Returns RAX = the configuration table entry's
; pointer, or 0 if the firmware published no table under that GUID.
; ----------------------------------------------------------------------------
find_config:
            push    rcx
            push    rdi
            mov     rax, [rel g_st]
            mov     rcx, [rax + ST_NUMTABLEENTRIES]
            mov     rdi, [rax + ST_CONFIGTABLE]
.next:
            test    rcx, rcx
            jz      .miss
            call    guid_eq
            je      .hit
            add     rdi, CFG_ENTRY_SIZE
            dec     rcx
            jmp     .next
.hit:
            mov     rax, [rdi + CFG_TABLE_PTR]
            jmp     .done
.miss:
            xor     eax, eax
.done:
            pop     rdi
            pop     rcx
            ret

; ----------------------------------------------------------------------------
; sum_bytes -- RSI = start, ECX = length. Returns AL = their sum.
; ----------------------------------------------------------------------------
sum_bytes:
            push    rcx
            push    rsi
            xor     eax, eax
            test    ecx, ecx
            jz      .done
.byte:
            add     al, [rsi]
            inc     rsi
            dec     ecx
            jnz     .byte
.done:
            pop     rsi
            pop     rcx
            ret

; ----------------------------------------------------------------------------
; out_w -- RDX = a CHAR16 string, written through ConOut. Preserves every
; register, so a caller can print between steps without saving its own.
; ----------------------------------------------------------------------------
out_w:
            push    rax
            push    rcx
            push    rdx
            push    r8
            push    r9
            push    r10
            push    r11
            sub     rsp, 32
            mov     rcx, [rel g_st]
            mov     rcx, [rcx + ST_CONOUT]
            call    [rcx + TO_OUTPUTSTRING]
            add     rsp, 32
            pop     r11
            pop     r10
            pop     r9
            pop     r8
            pop     rdx
            pop     rcx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; out_ascii -- RSI = a NUL-terminated byte string. Widened into g_strbuf, cut
; at STRBUF_CHARS, and written.
; ----------------------------------------------------------------------------
out_ascii:
            push    rax
            push    rcx
            push    rdx
            push    rsi
            lea     rdx, [rel g_strbuf]
            xor     ecx, ecx
.next:
            movzx   eax, byte [rsi + rcx]
            test    eax, eax
            jz      .end
            mov     [rdx + rcx*2], ax
            inc     ecx
            cmp     ecx, STRBUF_CHARS
            jb      .next
.end:
            mov     word [rdx + rcx*2], 0
            call    out_w
            pop     rsi
            pop     rdx
            pop     rcx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; out_dec -- EAX = an unsigned value, written in decimal.
; ----------------------------------------------------------------------------
out_dec:
            push    rax
            push    rcx
            push    rdx
            push    rdi
            lea     rdi, [rel g_strbuf + STRBUF_CHARS*2]
            mov     word [rdi], 0
            mov     ecx, 10
.digit:
            xor     edx, edx
            div     ecx
            add     edx, '0'
            sub     rdi, 2
            mov     [rdi], dx
            test    eax, eax
            jnz     .digit
            mov     rdx, rdi
            call    out_w
            pop     rdi
            pop     rdx
            pop     rcx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; sig_to_str -- RSI = a table. Spells its four signature bytes, and a trailing
; space, into g_sigbuf as CHAR16.
; ----------------------------------------------------------------------------
sig_to_str:
            push    rax
            push    rcx
            push    rdx
            lea     rax, [rel g_sigbuf]
            xor     ecx, ecx
.next:
            movzx   edx, byte [rsi + rcx + SDT_SIGNATURE]
            mov     [rax + rcx*2], dx
            inc     ecx
            cmp     ecx, SIG_LENGTH
            jb      .next
            mov     word [rax + SIG_LENGTH*2], ' '
            mov     word [rax + SIG_LENGTH*2 + 2], 0
            pop     rdx
            pop     rcx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; sum_table -- RSI = a table. Returns AL = the sum of its bytes, which the
; specification requires to be zero.
; ----------------------------------------------------------------------------
sum_table:
            push    rcx
            push    rdx
            xor     eax, eax
            mov     ecx, [rsi + SDT_LENGTH]
            test    ecx, ecx
            jz      .done
            xor     edx, edx
.byte:
            add     al, [rsi + rdx]
            inc     rdx
            dec     ecx
            jnz     .byte
.done:
            pop     rdx
            pop     rcx
            ret

; ----------------------------------------------------------------------------
; hex_to_str -- RAX = value, RDI = where to write it as CHAR16, ECX = digits.
; Most significant first, over the placeholder in a message.
; ----------------------------------------------------------------------------
hex_to_str:
            push    rax
            push    rbx
            push    rcx
            push    rdx
            push    rdi
            mov     edx, ecx
.digit:
            dec     edx
            mov     rbx, rax
            mov     ecx, edx
            shl     ecx, 2
            shr     rbx, cl
            and     ebx, 0x0F
            cmp     bl, 10
            jb      .decimal
            add     bl, 'a' - 10
            jmp     .emit
.decimal:
            add     bl, '0'
.emit:
            mov     [rdi], bx                   ; one CHAR16, not one byte
            add     rdi, 2
            test    edx, edx
            jnz     .digit
            pop     rdi
            pop     rdx
            pop     rcx
            pop     rbx
            pop     rax
            ret

; ----------------------------------------------------------------------------
; guid_eq -- RSI and RDI point at GUIDs. ZF set if they match.
; ----------------------------------------------------------------------------
guid_eq:
            push    rcx
            push    rsi
            push    rdi
            mov     ecx, GUID_SIZE
            repe cmpsb
            pop     rdi
            pop     rsi
            pop     rcx
            ret

; ----------------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------------
align 8
acpi20_guid:                                ; 8868E871-E4F1-11D3-BC22-0080C73C8881
            dd 0x8868E871
            dw 0xE4F1
            dw 0x11D3
            db 0xBC, 0x22, 0x00, 0x80, 0xC7, 0x3C, 0x88, 0x81

smbios_guid:                                ; EB9D2D31-2D88-11D3-9A16-0090273FC14D
            dd 0xEB9D2D31
            dw 0x2D88
            dw 0x11D3
            db 0x9A, 0x16, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D

smbios3_guid:                               ; F2FD1544-9794-4A2C-992E-E5BBCF20E394
            dd 0xF2FD1544
            dw 0x9794
            dw 0x4A2C
            db 0x99, 0x2E, 0xE5, 0xBB, 0xCF, 0x20, 0xE3, 0x94

var_guid:                                   ; a GUID of this payload's own
            dd 0x6A5F1D2E
            dw 0x3B4C
            dw 0x4D5E
            db 0x8F, 0x90, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6

var_data:   db "asmfw keeps this in RAM"
VAR_DATA_LEN equ $ - var_data
var_tail:   db "!"
            align 8

gop_guid:
            dd 0x9042A9DE
            dw 0x23DC
            dw 0x4A38
            db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

sfs_guid:
            dd 0x964E5B22
            dw 0x6459
            dw 0x11D2
            db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

g_image:    dq 0
g_st:       dq 0
g_gop:      dq 0
g_sfs:      dq 0
g_root:     dq 0
g_file:     dq 0
g_readlen:  dq 0
g_readbuf:  dq 0
g_acpi_bad: dq 0
g_sigbuf:   times SIG_LENGTH + 2 dw 0
g_smb_sys:  dq 0
g_smb_major: dd 0
g_smb_minor: dd 0
g_strbuf:   times STRBUF_CHARS + 1 dw 0
            align 8
g_vsize:    dq 0
g_nsize:    dq 0
g_vattr:    dd 0, 0
g_nguid:    times 16 db 0
g_vbuf:     times VBUF_SIZE db 0
g_nbuf:     times NBUF_SIZE db 0
s_empty_a:  dw 0                            ; read as a byte string; a word,
                                            ; so the CHAR16 strings after it
                                            ; stay 2-byte aligned, as UEFI
                                            ; requires and OVMF enforces
g_key:      dw 0, 0                         ; one EFI_INPUT_KEY

WSTR s_banner,  `\r\n  hello from a hand-assembled UEFI application\r\n\r\n`
WSTR s_running, `  loaded and started by asmfw\r\n`
WSTR s_gop,     `  graphics output protocol located; drawing\r\n`
WSTR s_nogop,   `  no graphics output protocol on this firmware\r\n`
WSTR s_bye,     `\r\n  returning to the firmware\r\n`
WSTR s_fs_ok,   `  read myself back off the file system; still a PE image\r\n`
WSTR s_fs_none, `  no simple file system protocol on this firmware\r\n`
WSTR s_fs_bad,  `  the file system is there but would not read the file\r\n`
WSTR s_selfpath, `\\EFI\\BOOT\\BOOTX64.EFI`
WSTR s_acpi,     `  ACPI tables: `
WSTR s_acpi_ok,  `  every one of them checksums to zero\r\n`
WSTR s_acpi_bad, `  at least one of them has a bad checksum\r\n`
WSTR s_acpi_none, `  no ACPI configuration table on this firmware\r\n`
WSTR s_crlf,     `\r\n`
WSTR s_smb,      `  SMBIOS `
WSTR s_var_name, `AsmfwPayloadTest`
WSTR s_var_ok,   `  variables: set, read back short and whole, refused a change of attributes, appended to, found among `
WSTR s_var_ok2,  ` by enumeration, deleted\r\n`
WSTR s_var_fail, `  variables: step `
WSTR s_var_status, ` went wrong, status 0x`
WSTR s_dot,      `.`
WSTR s_colon,    `: `
WSTR s_space,    ` `
WSTR s_smb_ok,   ` structures walked to the end marker; entry point checksums to zero\r\n`
WSTR s_smb_sys,  `  system: `
WSTR s_smb_none, `  no SMBIOS configuration table on this firmware\r\n`
WSTR s_smb_malformed, `  the SMBIOS entry point has no signature it should have\r\n`
WSTR s_smb_bad_sum,   `  the SMBIOS entry point has a bad checksum\r\n`
WSTR s_smb_torn, `  the SMBIOS structures run off the end of their table\r\n`
WSTR s_no_key,   `  nothing typed in three seconds; ConIn said EFI_NOT_READY throughout\r\n`
WSTR s_no_conin, `  no simple text input protocol on this firmware\r\n`

; Built out rather than declared with WSTR, because two fields in it are
; written at run time and a label has to be able to name them.
s_key:      dw __utf16le__(`  typed: '`)
s_key_char: dw '?'
            dw __utf16le__(`' scan 0x`)
s_key_scan: dw '0', '0', '0', '0'
            dw __utf16le__(`, through EFI_SIMPLE_TEXT_INPUT_PROTOCOL`), 13, 10, 0

            times TEXT_RVA + TEXT_SIZE - ($ - $$) db 0

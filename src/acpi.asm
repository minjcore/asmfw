; ============================================================================
; acpi.asm -- QEMU's fw_cfg interface, and the ACPI tables behind it
;
; QEMU does not hand firmware a finished set of ACPI tables. It hands over
; blobs, plus a script -- etc/table-loader -- that says where each blob has to
; be placed, which pointers inside them to patch once the addresses are known,
; and which checksums to recompute afterwards. Firmware that downloads the
; blobs and skips the script gets tables whose every cross-reference is zero.
;
; The script is the reason this file exists. Everything else here is the small
; amount of port I/O needed to fetch what the script names.
; ============================================================================

bits 64

; ---------------------------------------------------------------------------
; fw_cfg, the ISA-style port pair
; ---------------------------------------------------------------------------
FW_CFG_PORT_SEL     equ 0x0510                  ; selector, written as a word
FW_CFG_PORT_DATA    equ 0x0511                  ; data, read a byte at a time

FW_CFG_SIGNATURE    equ 0x0000
FW_CFG_FILE_DIR     equ 0x0019

FW_CFG_SIG_QEMU     equ 0x554D4551              ; "QEMU", as a little-endian dword

; The file directory: a big-endian count, then that many fixed-size records.
; Big-endian is not a mistake -- fw_cfg's directory is specified that way, and
; only that way; the payload of each file is in its own natural order.
FWD_SIZE            equ 0x00                    ; UINT32, big endian
FWD_SELECT          equ 0x04                    ; UINT16, big endian
FWD_NAME            equ 0x08                    ; char[56], NUL padded
FWD_NAME_MAX        equ 56
FWD_ENTRY_SIZE      equ 0x40
FWD_MAX             equ 256                     ; what BUF_FWCFG_DIR holds

; ---------------------------------------------------------------------------
; etc/table-loader: a flat array of fixed-size commands.
;
; Each command is a 32-bit opcode followed by a union. The offsets below are
; that union laid out three ways, one per opcode.
; ---------------------------------------------------------------------------
LDR_ENTRY_SHIFT     equ 7
LDR_ENTRY_SIZE      equ (1 << LDR_ENTRY_SHIFT)  ; 128 bytes

LDR_CMD             equ 0x00                    ; UINT32

LDR_ALLOC_FILE      equ 0x04                    ; char[56]
LDR_ALLOC_ALIGN     equ 0x3C                    ; UINT32, a power of two
LDR_ALLOC_ZONE      equ 0x40                    ; UINT8

LDR_PTR_DEST        equ 0x04                    ; char[56]
LDR_PTR_SRC         equ 0x3C                    ; char[56]
LDR_PTR_OFFSET      equ 0x74                    ; UINT32, into the dest blob
LDR_PTR_SIZE        equ 0x78                    ; UINT8, 1/2/4/8

LDR_CKS_FILE        equ 0x04                    ; char[56]
LDR_CKS_OFFSET      equ 0x3C                    ; UINT32, of the checksum byte
LDR_CKS_START       equ 0x40                    ; UINT32, of the summed range
LDR_CKS_LENGTH      equ 0x44                    ; UINT32

LDR_CMD_ALLOCATE        equ 1
LDR_CMD_ADD_POINTER     equ 2
LDR_CMD_ADD_CHECKSUM    equ 3

; ---------------------------------------------------------------------------
; Where each downloaded blob ended up. Names are compared, not interned, so
; the record carries a copy of the 56-byte field the script uses.
; ---------------------------------------------------------------------------
ABLOB_NAME          equ 0x00
ABLOB_ADDR          equ 0x38
ABLOB_SIZE          equ 0x40
ABLOB_REC_SIZE      equ 0x48
ABLOB_MAX           equ 32

; ---------------------------------------------------------------------------
; The RSDP, and the header every other ACPI table starts with
; ---------------------------------------------------------------------------
RSDP_REVISION       equ 15                      ; UINT8
RSDP_RSDT           equ 16                      ; UINT32
RSDP_XSDT           equ 24                      ; UINT64
ACPI_REVISION_2     equ 2

SDT_LENGTH          equ 4                       ; UINT32
SDT_HEADER_SIZE     equ 36
RSDT_ENTRY_SIZE     equ 4
XSDT_ENTRY_SIZE     equ 8

; ----------------------------------------------------------------------------
; acpi_init -- run the loader script and publish the RSDP.
; Returns EAX = 1 if a configuration table was installed, 0 otherwise.
;
; Must run after efi_init: installing a configuration table rewrites the
; system table header, which does not exist until then.
; ----------------------------------------------------------------------------
acpi_init:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     dword [abs g_acpi_blobs], 0
    mov     qword [abs g_acpi_rsdp], 0
    mov     dword [abs g_acpi_tables], 0

    call    fwcfg_init
    test    eax, eax
    jz      .no_fwcfg

    lea     rsi, [rel name_table_loader]
    call    fwcfg_find
    test    eax, eax
    jz      .no_tables
    test    edx, edx
    jz      .no_tables
    cmp     edx, ACPI_LOADER_MAX
    ja      .too_big

    mov     r12d, edx                           ; the script's length
    call    fwcfg_select
    mov     rdi, BUF_ACPI_LOADER
    mov     ecx, r12d
    call    fwcfg_read

    mov     r13d, r12d
    shr     r13d, LDR_ENTRY_SHIFT
    jz      .no_tables
    mov     rbx, BUF_ACPI_LOADER

    ; The script is ordered: everything a command refers to has been allocated
    ; by an earlier command. So one pass is enough, and a command whose blob
    ; is missing is one this firmware chose not to handle.
.command:
    mov     eax, [rbx + LDR_CMD]
    cmp     eax, LDR_CMD_ALLOCATE
    je      .allocate
    cmp     eax, LDR_CMD_ADD_POINTER
    je      .pointer
    cmp     eax, LDR_CMD_ADD_CHECKSUM
    je      .checksum
    ; WRITE_POINTER writes back into a fw_cfg file, which only matters to
    ; features this firmware does not expose. Skipping it leaves the tables
    ; consistent; acting on it would need a writable fw_cfg path.
    jmp     .next
.allocate:
    call    acpi_cmd_allocate
    jmp     .next
.pointer:
    call    acpi_cmd_add_pointer
    jmp     .next
.checksum:
    call    acpi_cmd_add_checksum
.next:
    add     rbx, LDR_ENTRY_SIZE
    dec     r13d
    jnz     .command

    ; --- publish -----------------------------------------------------------
    lea     rsi, [rel name_acpi_rsdp]
    call    acpi_blob_find
    test    rax, rax
    jz      .no_rsdp
    mov     [abs g_acpi_rsdp], rax

    ; Both GUIDs point at the same structure: an ACPI 2.0 RSDP begins with a
    ; byte-for-byte ACPI 1.0 one, so a consumer that asks for either finds
    ; what it expects at the front.
    mov     rdx, rax
    lea     rcx, [rel guid_acpi_20]
    call    bs_install_configuration_table
    mov     rdx, [abs g_acpi_rsdp]
    lea     rcx, [rel guid_acpi_10]
    call    bs_install_configuration_table

    call    acpi_count_tables
    mov     [abs g_acpi_tables], eax

    puts    msg_acpi
    mov     eax, [abs g_acpi_tables]
    call    con_putdec
    putsi   " tables, RSDP at "
    mov     rax, [abs g_acpi_rsdp]
    call    con_puthex64
    mov     al, 10
    call    con_putc

    mov     eax, 1
    jmp     .done

.no_fwcfg:
    puts    msg_no_fwcfg
    jmp     .fail
.no_tables:
    puts    msg_no_acpi
    jmp     .fail
.too_big:
    puts    msg_acpi_big
    jmp     .fail
.no_rsdp:
    puts    msg_no_rsdp
.fail:
    xor     eax, eax
.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; acpi_cmd_allocate -- RBX = an ALLOCATE command.
;
; Downloads the named file into fresh memory and records where it landed. The
; script's zone field is ignored: it distinguishes the legacy F-segment from
; high memory, a distinction only a BIOS that scans for the RSDP cares about.
; An EFI consumer is handed the address instead.
; ----------------------------------------------------------------------------
acpi_cmd_allocate:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11

    lea     rsi, [rbx + LDR_ALLOC_FILE]
    call    fwcfg_find
    test    eax, eax
    jz      .done
    test    edx, edx
    jz      .done
    mov     r8d, eax                            ; selector
    mov     r9d, edx                            ; size

    mov     r11d, [rbx + LDR_ALLOC_ALIGN]
    test    r11d, r11d
    jnz     .have_align
    mov     r11d, 1
.have_align:
    ; Pages are 4 KiB aligned already, and the tables ask for 16 or 64. The
    ; slack is carried anyway so that a stricter request stays correct.
    mov     rcx, r9
    add     rcx, r11
    add     rcx, 0xFFF
    shr     rcx, 12
    mov     edx, EfiACPIReclaimMemory
    call    mem_alloc_pages
    test    rax, rax
    jz      .done
    add     rax, r11
    dec     rax
    neg     r11
    and     rax, r11
    mov     r10, rax

    mov     eax, r8d
    call    fwcfg_select
    mov     rdi, r10
    mov     ecx, r9d
    call    fwcfg_read

    lea     rsi, [rbx + LDR_ALLOC_FILE]
    mov     rdx, r10
    mov     rcx, r9
    call    acpi_blob_add
.done:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; acpi_cmd_add_pointer -- RBX = an ADD_POINTER command.
;
; The field at dest+offset holds an offset into the source blob; adding the
; blob's base turns it into the address the table is supposed to contain.
; ----------------------------------------------------------------------------
acpi_cmd_add_pointer:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10

    lea     rsi, [rbx + LDR_PTR_DEST]
    call    acpi_blob_find
    test    rax, rax
    jz      .done
    mov     r8, rax                             ; destination base
    mov     r9, rdx                             ; destination size

    lea     rsi, [rbx + LDR_PTR_SRC]
    call    acpi_blob_find
    test    rax, rax
    jz      .done
    mov     r10, rax                            ; source base

    mov     ecx, [rbx + LDR_PTR_OFFSET]
    movzx   edx, byte [rbx + LDR_PTR_SIZE]
    test    edx, edx
    jz      .done
    mov     rax, rcx
    add     rax, rdx
    cmp     rax, r9
    ja      .done                               ; the field runs off the blob

    lea     rdi, [r8 + rcx]

    xor     eax, eax
    mov     ecx, edx
.load:
    shl     rax, 8
    mov     al, [rdi + rcx - 1]
    dec     ecx
    jnz     .load

    add     rax, r10

    mov     ecx, edx
.store:
    mov     [rdi], al
    shr     rax, 8
    inc     rdi
    dec     ecx
    jnz     .store
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; acpi_cmd_add_checksum -- RBX = an ADD_CHECKSUM command.
;
; ACPI's checksum rule is that the bytes of a table sum to zero modulo 256.
; The byte at `offset` is inside the summed range, so subtracting the sum from
; whatever is already there is what makes the total come out zero.
; ----------------------------------------------------------------------------
acpi_cmd_add_checksum:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    r8
    push    r9
    push    r10
    push    r11

    lea     rsi, [rbx + LDR_CKS_FILE]
    call    acpi_blob_find
    test    rax, rax
    jz      .done
    mov     r8, rax                             ; blob base
    mov     r9, rdx                             ; blob size

    mov     ecx, [rbx + LDR_CKS_OFFSET]
    mov     edx, [rbx + LDR_CKS_START]
    mov     r10d, [rbx + LDR_CKS_LENGTH]

    cmp     rcx, r9
    jae     .done
    mov     rax, rdx
    add     rax, r10
    cmp     rax, r9
    ja      .done

    lea     rsi, [r8 + rdx]
    xor     eax, eax
    mov     r11d, r10d
    test    r11d, r11d
    jz      .apply
.sum:
    add     al, [rsi]
    inc     rsi
    dec     r11d
    jnz     .sum
.apply:
    sub     [r8 + rcx], al
.done:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; acpi_count_tables -- how many SDTs the root table lists. Diagnostic only.
; Returns EAX.
; ----------------------------------------------------------------------------
acpi_count_tables:
    push    rbx
    push    rcx
    push    rdx

    mov     rbx, [abs g_acpi_rsdp]
    test    rbx, rbx
    jz      .none

    cmp     byte [rbx + RSDP_REVISION], ACPI_REVISION_2
    jb      .rsdt
    mov     rdx, [rbx + RSDP_XSDT]
    test    rdx, rdx
    jz      .rsdt
    mov     ecx, XSDT_ENTRY_SIZE
    jmp     .have_root
.rsdt:
    mov     edx, [rbx + RSDP_RSDT]
    test    edx, edx
    jz      .none
    mov     ecx, RSDT_ENTRY_SIZE
.have_root:
    mov     eax, [rdx + SDT_LENGTH]
    cmp     eax, SDT_HEADER_SIZE
    jbe     .none
    sub     eax, SDT_HEADER_SIZE
    xor     edx, edx
    div     ecx
    jmp     .done
.none:
    xor     eax, eax
.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; acpi_blob_add -- RSI = the 56-byte name field, RDX = base, RCX = size
; ----------------------------------------------------------------------------
acpi_blob_add:
    push    rax
    push    rdi
    mov     eax, [abs g_acpi_blobs]
    cmp     eax, ABLOB_MAX
    jae     .full
    mov     edi, eax
    imul    edi, ABLOB_REC_SIZE
    add     rdi, ACPI_BLOB_TABLE
    push    rcx
    mov     ecx, FWD_NAME_MAX
    call    mem_copy
    pop     rcx
    mov     [rdi + ABLOB_ADDR], rdx
    mov     [rdi + ABLOB_SIZE], rcx
    inc     eax
    mov     [abs g_acpi_blobs], eax
.full:
    pop     rdi
    pop     rax
    ret

; ----------------------------------------------------------------------------
; acpi_blob_find -- RSI = a name, NUL terminated or NUL padded.
; Returns RAX = base and RDX = size, or RAX = 0.
; ----------------------------------------------------------------------------
acpi_blob_find:
    push    rbx
    push    rcx
    push    rdi
    mov     ecx, [abs g_acpi_blobs]
    test    ecx, ecx
    jz      .miss
    mov     rbx, ACPI_BLOB_TABLE
.next:
    lea     rdi, [rbx + ABLOB_NAME]
    call    str_eq
    je      .hit
    add     rbx, ABLOB_REC_SIZE
    dec     ecx
    jnz     .next
.miss:
    xor     eax, eax
    xor     edx, edx
    jmp     .done
.hit:
    mov     rax, [rbx + ABLOB_ADDR]
    mov     rdx, [rbx + ABLOB_SIZE]
.done:
    pop     rdi
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fwcfg_init -- confirm the interface answers, and cache the file directory.
; Returns EAX = 1 if it did.
; ----------------------------------------------------------------------------
fwcfg_init:
    push    rcx
    push    rdx
    push    rdi

    mov     dword [abs g_fwcfg_files], 0

    mov     eax, FW_CFG_SIGNATURE
    call    fwcfg_select
    mov     rdi, BUF_FWCFG_DIR
    mov     ecx, 4
    call    fwcfg_read
    cmp     dword [abs BUF_FWCFG_DIR], FW_CFG_SIG_QEMU
    jne     .absent

    mov     eax, FW_CFG_FILE_DIR
    call    fwcfg_select
    mov     rdi, BUF_FWCFG_DIR
    mov     ecx, 4
    call    fwcfg_read
    mov     eax, [abs BUF_FWCFG_DIR]
    bswap   eax
    test    eax, eax
    jz      .absent
    cmp     eax, FWD_MAX
    jbe     .fits
    mov     eax, FWD_MAX
.fits:
    mov     [abs g_fwcfg_files], eax

    ; The count is overwritten by the records that follow it; it has already
    ; been read out of the way.
    mov     ecx, eax
    imul    ecx, FWD_ENTRY_SIZE
    mov     rdi, BUF_FWCFG_DIR
    call    fwcfg_read

    mov     eax, 1
    jmp     .done
.absent:
    mov     dword [abs g_fwcfg_files], 0
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; fwcfg_find -- RSI = a NUL-terminated file name.
; Returns EAX = the selector key and EDX = the size, or EAX = 0.
; ----------------------------------------------------------------------------
fwcfg_find:
    push    rbx
    push    rcx
    push    rdi
    mov     ecx, [abs g_fwcfg_files]
    test    ecx, ecx
    jz      .miss
    mov     rbx, BUF_FWCFG_DIR
.next:
    lea     rdi, [rbx + FWD_NAME]
    call    str_eq
    je      .hit
    add     rbx, FWD_ENTRY_SIZE
    dec     ecx
    jnz     .next
.miss:
    xor     eax, eax
    xor     edx, edx
    jmp     .done
.hit:
    movzx   eax, word [rbx + FWD_SELECT]
    xchg    al, ah
    mov     edx, [rbx + FWD_SIZE]
    bswap   edx
.done:
    pop     rdi
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fwcfg_select -- EAX = key. Selecting also rewinds the file to offset zero.
; ----------------------------------------------------------------------------
fwcfg_select:
    push    rdx
    mov     dx, FW_CFG_PORT_SEL
    out     dx, ax
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; fwcfg_read -- RDI = destination, RCX = byte count. Continues from wherever
; the current selection left off.
; ----------------------------------------------------------------------------
fwcfg_read:
    push    rcx
    push    rdi
    push    rdx
    mov     dx, FW_CFG_PORT_DATA
    rep     insb
    pop     rdx
    pop     rdi
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; str_eq -- RSI and RDI, each NUL terminated or NUL padded. ZF set if equal.
; Clobbers AL.
; ----------------------------------------------------------------------------
str_eq:
    push    rsi
    push    rdi
.next:
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     .done
    test    al, al
    jz      .done
    inc     rsi
    inc     rdi
    jmp     .next
.done:
    pop     rdi
    pop     rsi
    ret

; ----------------------------------------------------------------------------
align 8
guid_acpi_20:                                   ; 8868E871-E4F1-11D3-BC22-0080C73C8881
    dd 0x8868E871
    dw 0xE4F1
    dw 0x11D3
    db 0xBC, 0x22, 0x00, 0x80, 0xC7, 0x3C, 0x88, 0x81

guid_acpi_10:                                   ; EB9D2D30-2D88-11D3-9A16-0090273FC14D
    dd 0xEB9D2D30
    dw 0x2D88
    dw 0x11D3
    db 0x9A, 0x16, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D

name_table_loader:  db "etc/table-loader", 0
name_acpi_rsdp:     db "etc/acpi/rsdp", 0

CSTR msg_acpi,      "[DXE] ACPI: "
CSTR msg_no_fwcfg,  "[DXE] no fw_cfg; no ACPI tables", 10
CSTR msg_no_acpi,   "[DXE] fw_cfg has no table loader; no ACPI tables", 10
CSTR msg_acpi_big,  "[DXE] the ACPI table loader is larger than expected", 10
CSTR msg_no_rsdp,   "[DXE] the ACPI tables carry no RSDP", 10

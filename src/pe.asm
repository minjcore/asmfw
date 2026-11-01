; ============================================================================
; pe.asm -- the PE32+ loader
;
; An .efi file is a PE image: headers, a section table, and a base relocation
; directory. Loading it means allocating SizeOfImage bytes, laying the
; sections out at their virtual addresses rather than their file offsets, and
; then patching every absolute address by the difference between where the
; image wanted to be and where it ended up.
; ============================================================================

bits 64

DOS_MAGIC           equ 0x5A4D
DOS_LFANEW          equ 0x3C
PE_MAGIC            equ 0x00004550

COFF_MACHINE        equ 0x04
COFF_NUMSECTIONS    equ 0x06
COFF_OPTHDRSIZE     equ 0x14
COFF_CHARACTERISTICS equ 0x16
COFF_OPTHDR         equ 0x18

MACHINE_X64         equ 0x8664
IMAGE_FILE_RELOCS_STRIPPED equ 0x0001

OPT_MAGIC           equ 0x00
OPT_ENTRY           equ 0x10
OPT_IMAGEBASE       equ 0x18
OPT_SECTALIGN       equ 0x20
OPT_FILEALIGN       equ 0x24
OPT_SUBSYSTEM       equ 0x44
OPT_SIZEOFIMAGE     equ 0x38
OPT_SIZEOFHEADERS   equ 0x3C
OPT_NUMRVA          equ 0x6C
OPT_DATADIR         equ 0x70
OPT_MAGIC_PE32PLUS  equ 0x020B

DIR_BASERELOC       equ 5

SEC_VSIZE           equ 0x08
SEC_VADDR           equ 0x0C
SEC_RAWSIZE         equ 0x10
SEC_RAWPTR          equ 0x14
SEC_SIZE            equ 40

REL_PAGERVA         equ 0x00
REL_BLOCKSIZE       equ 0x04
REL_ENTRIES         equ 0x08

REL_ABSOLUTE        equ 0
REL_HIGHLOW         equ 3
REL_DIR64           equ 10

; ----------------------------------------------------------------------------
; pe_load -- RSI = the file image in memory, RDX = its length in bytes.
;
; On success sets g_img_base, g_img_pages and g_img_entry, and returns EAX = 0.
; A non-zero EAX is an index into pe_errors, printed by the caller.
; ----------------------------------------------------------------------------
pe_load:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rsi                            ; file image
    mov     r13, rdx                            ; file length

    ; --- DOS header -------------------------------------------------------
    cmp     r13, 0x40
    jb      .err_short
    cmp     word [r12], DOS_MAGIC
    jne     .err_notpe

    mov     ebx, [r12 + DOS_LFANEW]
    mov     rax, rbx
    add     rax, COFF_OPTHDR
    cmp     rax, r13
    jae     .err_short
    add     rbx, r12                            ; -> PE signature

    cmp     dword [rbx], PE_MAGIC
    jne     .err_notpe
    cmp     word [rbx + COFF_MACHINE], MACHINE_X64
    jne     .err_machine

    movzx   r14d, word [rbx + COFF_NUMSECTIONS]
    movzx   eax, word [rbx + COFF_OPTHDRSIZE]
    lea     r15, [rbx + COFF_OPTHDR]            ; -> optional header
    lea     rbp, [r15 + rax]                    ; -> section table

    cmp     word [r15 + OPT_MAGIC], OPT_MAGIC_PE32PLUS
    jne     .err_notpe32plus

    ; --- allocate the image ------------------------------------------------
    mov     eax, [r15 + OPT_SIZEOFIMAGE]
    test    eax, eax
    jz      .err_short
    add     eax, 0xFFF
    shr     eax, 12
    mov     rcx, rax
    mov     [abs g_img_pages], rcx
    mov     edx, EfiLoaderCode
    call    mem_alloc_pages
    test    rax, rax
    jz      .err_alloc
    mov     [abs g_img_base], rax
    mov     rdi, rax

    ; Sections do not have to cover the image, and the gaps are required to
    ; read as zero -- .bss lives in one of them.
    mov     rcx, [abs g_img_pages]
    shl     rcx, 12
    xor     al, al
    call    mem_set

    ; --- headers ----------------------------------------------------------
    mov     ecx, [r15 + OPT_SIZEOFHEADERS]
    cmp     rcx, r13
    ja      .err_short
    mov     rdi, [abs g_img_base]
    mov     rsi, r12
    call    mem_copy

    ; --- sections ---------------------------------------------------------
    test    r14d, r14d
    jz      .relocs
.section:
    mov     eax, [rbp + SEC_RAWSIZE]
    test    eax, eax
    jz      .next_section                       ; nothing on disk: already zero

    ; Refuse anything whose file range runs past the end of the file.
    mov     rcx, rax
    mov     edx, [rbp + SEC_RAWPTR]
    mov     rsi, rdx
    add     rsi, rcx
    cmp     rsi, r13
    ja      .err_range

    ; ...or whose virtual range runs past the end of the image.
    mov     r8d, [rbp + SEC_VADDR]
    mov     r9, r8
    add     r9, rcx
    mov     r10, [abs g_img_pages]
    shl     r10, 12
    cmp     r9, r10
    ja      .err_range

    mov     rsi, r12
    add     rsi, rdx
    mov     rdi, [abs g_img_base]
    add     rdi, r8
    call    mem_copy

.next_section:
    add     rbp, SEC_SIZE
    dec     r14d
    jnz     .section

    ; --- base relocations -------------------------------------------------
.relocs:
    mov     rax, [abs g_img_base]
    sub     rax, [r15 + OPT_IMAGEBASE]
    mov     r14, rax                            ; the delta to apply
    test    r14, r14
    jz      .entry                              ; loaded where it asked to be

    mov     eax, [r15 + OPT_NUMRVA]
    cmp     eax, DIR_BASERELOC + 1
    jb      .no_relocs
    mov     ebx, [r15 + OPT_DATADIR + DIR_BASERELOC * 8]        ; RVA
    mov     ecx, [r15 + OPT_DATADIR + DIR_BASERELOC * 8 + 4]    ; size
    test    ebx, ebx
    jz      .no_relocs
    test    ecx, ecx
    jz      .no_relocs

    mov     rsi, [abs g_img_base]
    add     rsi, rbx                            ; -> first relocation block
    mov     r13, rsi
    add     r13, rcx                            ; -> end of the directory

.block:
    cmp     rsi, r13
    jae     .entry
    mov     r8d, [rsi + REL_PAGERVA]
    mov     r9d, [rsi + REL_BLOCKSIZE]
    cmp     r9d, REL_ENTRIES
    jbe     .entry                              ; malformed or terminating block

    lea     rdi, [rsi + REL_ENTRIES]            ; -> entries
    mov     r10, rsi
    add     r10, r9                             ; -> end of this block

.reloc_entry:
    cmp     rdi, r10
    jae     .next_block
    movzx   eax, word [rdi]
    add     rdi, 2

    mov     ecx, eax
    shr     ecx, 12                             ; type
    and     eax, 0x0FFF                         ; offset within the page

    cmp     ecx, REL_ABSOLUTE
    je      .reloc_entry                        ; padding

    mov     rbx, [abs g_img_base]
    add     rbx, r8
    add     rbx, rax                            ; -> the field to patch

    cmp     ecx, REL_DIR64
    je      .fix64
    cmp     ecx, REL_HIGHLOW
    je      .fix32
    jmp     .err_reloc

.fix64:
    add     qword [rbx], r14
    jmp     .reloc_entry
.fix32:
    add     dword [rbx], r14d
    jmp     .reloc_entry

.next_block:
    mov     rsi, r10
    jmp     .block

.no_relocs:
    ; The image landed away from its preferred base and has no relocation
    ; directory. That is only fatal if it claims its relocations were
    ; stripped, which is the image asserting it must load at ImageBase.
    ; Otherwise it is position-independent -- every reference RIP-relative --
    ; and running it where it lies is exactly what it was built for.
    mov     eax, [r12 + DOS_LFANEW]
    add     rax, r12
    movzx   eax, word [rax + COFF_CHARACTERISTICS]
    test    eax, IMAGE_FILE_RELOCS_STRIPPED
    jnz     .err_noreloc
    jmp     .entry

.entry:
    mov     eax, [r15 + OPT_ENTRY]
    test    eax, eax
    jz      .err_entry
    mov     rcx, [abs g_img_pages]
    shl     rcx, 12
    cmp     rax, rcx
    jae     .err_entry
    add     rax, [abs g_img_base]
    mov     [abs g_img_entry], rax

    xor     eax, eax
    jmp     .done

.err_short:     mov eax, 1
                jmp .done
.err_notpe:     mov eax, 2
                jmp .done
.err_machine:   mov eax, 3
                jmp .done
.err_notpe32plus: mov eax, 4
                jmp .done
.err_alloc:     mov eax, 5
                jmp .done
.err_range:     mov eax, 6
                jmp .done
.err_reloc:     mov eax, 7
                jmp .done
.err_noreloc:   mov eax, 8
                jmp .done
.err_entry:     mov eax, 9
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; pe_error_string -- EAX = the code pe_load returned, RSI = its message
; ----------------------------------------------------------------------------
pe_error_string:
    push    rcx
    lea     rsi, [rel pe_errors]
    mov     ecx, eax
    test    ecx, ecx
    jz      .done
.skip:
    lodsb
    test    al, al
    jnz     .skip
    dec     ecx
    jnz     .skip
.done:
    pop     rcx
    ret

pe_errors:
    db "no error", 0
    db "file is too short for its own headers", 0
    db "not a PE image", 0
    db "not an x86-64 image", 0
    db "not PE32+", 0
    db "could not allocate the image", 0
    db "a section lies outside the file or the image", 0
    db "unsupported relocation type", 0
    db "image must load at its preferred base, which is not available", 0
    db "entry point is outside the image", 0

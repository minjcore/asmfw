; ============================================================================
; efi_file.asm -- Simple File System and File protocols over the FAT32 reader
;
; Read-only. Every call that would change the volume returns
; EFI_WRITE_PROTECTED rather than pretending to succeed, because a loader that
; believes it wrote something and then reads it back is worse off than one
; told plainly that it cannot.
;
; A file handle is an object allocated from pool whose first eleven members
; are the protocol; the bookkeeping after them is private. Callers only ever
; see the pointer to the first member, which is exactly what the spec asks
; for.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; OpenVolume(This, EFI_FILE_PROTOCOL **Root)
; ----------------------------------------------------------------------------
sfs_open_volume:
    push    rbx
    push    rsi
    test    rdx, rdx
    jz      .bad
    mov     rbx, rdx

    mov     eax, [abs g_fat_root_clus]
    xor     rdx, rdx                            ; a directory has no length
    mov     cl, ATTR_DIRECTORY
    lea     rsi, [rel name_root]
    call    file_new
    test    rax, rax
    jz      .oom

    mov     [rbx], rax
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.oom:
    mov     rax, EFI_OUT_OF_RESOURCES
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; file_new -- EAX = first cluster, RDX = size, CL = FAT attributes,
; RSI = the 11-byte 8.3 name. Returns RAX = the new object, or 0.
; ----------------------------------------------------------------------------
file_new:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     r8d, eax
    mov     r9, rdx
    movzx   eax, cl
    mov     rbx, rax                            ; attributes

    mov     rcx, F_OBJECT_SIZE
    mov     edx, EfiBootServicesData
    call    mem_alloc_pool
    test    rax, rax
    jz      .done
    mov     rdi, rax

    push    rdi
    push    rsi
    lea     rsi, [rel file_template]
    mov     ecx, F_PUBLIC_SIZE
    call    mem_copy
    pop     rsi
    pop     rdi

    mov     [rdi + F_CLUSTER], r8d
    mov     [rdi + F_ATTR], ebx
    mov     [rdi + F_SIZE], r9
    mov     qword [rdi + F_POS], 0

    push    rdi
    add     rdi, F_NAME
    mov     ecx, 11
    call    mem_copy
    mov     byte [rdi + 11], 0
    pop     rdi

    mov     rax, rdi
.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; Open(This, EFI_FILE_PROTOCOL **NewHandle, CHAR16 *FileName,
;      UINT64 OpenMode, UINT64 Attributes)
;
; The path is walked one component at a time. A leading separator restarts at
; the root; "." and ".." need no special handling, because a FAT directory
; contains real entries for both.
; ----------------------------------------------------------------------------
file_open:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad

    ; Anything but a plain read is refused up front. The mode bits go through
    ; a register: EFI_FILE_MODE_CREATE has bit 63 set, and an immediate that
    ; wide cannot be encoded.
    mov     rax, EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE
    test    r9, rax
    jnz     .readonly

    mov     r12, rdx                            ; where to put the new handle
    mov     r13, r8                             ; the path, as CHAR16
    mov     r14d, [rcx + F_CLUSTER]             ; directory to start from

    ; The starting object must be a directory for a relative path to mean
    ; anything.
    test    dword [rcx + F_ATTR], ATTR_DIRECTORY
    jz      .not_dir

    ; State carried across components: R14 the current directory cluster,
    ; R15 the attributes of whatever was last resolved.
    mov     r15d, ATTR_DIRECTORY
    xor     ebx, ebx                            ; size of whatever was resolved

    ; A separator at the very front makes the path absolute. Only the first
    ; one means that -- the separators between components are just syntax.
    movzx   eax, word [r13]
    cmp     ax, '\'
    je      .from_root
    cmp     ax, '/'
    jne     .component
.from_root:
    mov     r14d, [abs g_fat_root_clus]
    mov     r15d, ATTR_DIRECTORY
    xor     ebx, ebx

.component:
    movzx   eax, word [r13]
    cmp     ax, '\'
    je      .skip_separator
    cmp     ax, '/'
    jne     .gather
.skip_separator:
    add     r13, 2
    jmp     .component

.gather:
    test    ax, ax
    jz      .resolved                           ; the path ended

    ; Measure this component.
    mov     rsi, r13
    xor     ecx, ecx
.measure:
    movzx   eax, word [rsi]
    test    ax, ax
    jz      .measured
    cmp     ax, '\'
    je      .measured
    cmp     ax, '/'
    je      .measured
    add     rsi, 2
    inc     ecx
    jmp     .measure
.measured:
    test    ecx, ecx
    jz      .advance                            ; an empty component: ignore

    ; The previous component has to have been a directory to look inside it.
    test    r15d, ATTR_DIRECTORY
    jz      .not_found

    mov     rdi, BUF_NAME83
    push    rsi
    mov     rsi, r13
    call    name_to_83
    pop     rsi

    mov     eax, r14d
    push    rsi
    mov     rsi, BUF_NAME83
    call    fat_lookup
    pop     rsi
    test    eax, eax
    jz      .not_found

    mov     r14d, eax                           ; cluster of what was found
    mov     ebx, edx                            ; its size
    movzx   r15d, cl                            ; its attributes

.advance:
    mov     r13, rsi
    jmp     .component

.resolved:
    ; R14 is the cluster, EBX the size, R15 the attributes.
    mov     eax, r14d
    mov     rdx, rbx
    mov     cl, r15b
    mov     rsi, BUF_NAME83
    ; A path that resolved to the volume root never went through name_to_83,
    ; so give it a name of its own.
    test    r15d, ATTR_DIRECTORY
    jz      .have_name
    cmp     r14d, [abs g_fat_root_clus]
    jne     .have_name
    lea     rsi, [rel name_root]
.have_name:
    call    file_new
    test    rax, rax
    jz      .oom
    mov     [r12], rax
    xor     eax, eax
    jmp     .done

.not_found:     mov rax, EFI_NOT_FOUND
                jmp .done
.not_dir:       mov rax, EFI_NOT_FOUND
                jmp .done
.readonly:      mov rax, EFI_WRITE_PROTECTED
                jmp .done
.oom:           mov rax, EFI_OUT_OF_RESOURCES
                jmp .done
.bad:           mov rax, EFI_INVALID_PARAMETER
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; Close(This) / Delete(This) / Write(...) / SetInfo(...) / Flush(This)
;
; Close leaks the object: the allocator behind it cannot free anything, and
; pretending otherwise by reusing the memory would be worse than the leak.
; ----------------------------------------------------------------------------
file_close:
    xor     eax, eax
    ret

file_delete:
    mov     rax, EFI_WRITE_PROTECTED
    ret

file_write:
    mov     rax, EFI_WRITE_PROTECTED
    ret

file_set_info:
    mov     rax, EFI_WRITE_PROTECTED
    ret

file_flush:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; GetPosition(This, UINT64 *Position) / SetPosition(This, UINT64 Position)
;
; A position of 0xFFFFFFFFFFFFFFFF means "seek to the end". On a directory
; only a seek back to zero is legal, and it restarts the listing.
; ----------------------------------------------------------------------------
file_get_position:
    test    rdx, rdx
    jz      .bad
    test    dword [rcx + F_ATTR], ATTR_DIRECTORY
    jnz     .unsupported
    mov     rax, [rcx + F_POS]
    mov     [rdx], rax
    xor     eax, eax
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    ret

file_set_position:
    test    dword [rcx + F_ATTR], ATTR_DIRECTORY
    jz      .file
    test    rdx, rdx
    jnz     .unsupported
    mov     qword [rcx + F_POS], 0
    xor     eax, eax
    ret
.file:
    cmp     rdx, -1
    jne     .absolute
    mov     rax, [rcx + F_SIZE]
    mov     [rcx + F_POS], rax
    xor     eax, eax
    ret
.absolute:
    mov     [rcx + F_POS], rdx
    xor     eax, eax
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; Read(This, UINTN *BufferSize, VOID *Buffer)
; ----------------------------------------------------------------------------
file_read:
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad

    mov     r12, rcx                            ; the file object
    mov     r13, rdx                            ; &BufferSize
    mov     r14, r8                             ; the caller's buffer

    test    dword [r12 + F_ATTR], ATTR_DIRECTORY
    jnz     .directory

    ; --- an ordinary file --------------------------------------------------
    mov     rax, [r12 + F_SIZE]
    sub     rax, [r12 + F_POS]
    jbe     .at_eof
    mov     r15, rax                            ; bytes left in the file
    cmp     r15, [r13]
    jbe     .have_count
    mov     r15, [r13]                          ; ...or what was asked for
.have_count:
    test    r15, r15
    jz      .at_eof
    test    r14, r14
    jz      .bad
    mov     rbp, r15                            ; remember what will be moved

    mov     ebx, [abs g_fat_spc]
    shl     ebx, 9                              ; bytes per cluster

.chunk:
    test    r15, r15
    jz      .file_done

    mov     eax, [r12 + F_CLUSTER]
    mov     rdx, [r12 + F_POS]
    call    fat_seek
    test    eax, eax
    jz      .device_error

    push    rdx                                 ; offset within the cluster
    mov     rdi, BUF_FILE
    call    fat_read_cluster
    pop     rdx
    test    eax, eax
    jnz     .device_error

    ; Copy at most to the end of this cluster.
    mov     rcx, rbx
    sub     rcx, rdx
    cmp     rcx, r15
    jbe     .have_chunk
    mov     rcx, r15
.have_chunk:

    mov     rsi, BUF_FILE
    add     rsi, rdx
    mov     rdi, r14
    call    mem_copy

    add     r14, rcx
    sub     r15, rcx
    add     [r12 + F_POS], rcx
    jmp     .chunk

.file_done:
    ; The loop only ends once R15 reaches zero, so the whole of the count
    ; decided up front was transferred.
    mov     [r13], rbp
    xor     eax, eax
    jmp     .done

.at_eof:
    mov     qword [r13], 0
    xor     eax, eax
    jmp     .done

    ; --- a directory: one EFI_FILE_INFO per call ---------------------------
.directory:
    mov     eax, [r12 + F_CLUSTER]
    mov     rdx, [r12 + F_POS]
    call    fat_dir_nth
    test    rax, rax
    jz      .at_eof
    mov     rbx, rax                            ; -> the 32-byte entry

    ; Work out how much room the entry needs, name included.
    mov     rsi, rbx
    mov     rdi, BUF_NAME16
    call    name_from_83                        ; ECX = characters written
    lea     rax, [rcx * 2 + 2]                  ; + the NUL
    add     rax, FI_HEADER_SIZE
    add     rax, 7
    and     rax, -8
    mov     r15, rax                            ; bytes needed

    cmp     [r13], r15
    jb      .too_small
    test    r14, r14
    jz      .bad

    ; Fill it in.
    mov     rdi, r14
    push    rcx
    mov     rcx, r15
    xor     al, al
    call    mem_set
    pop     rcx

    mov     [rdi + FI_SIZE], r15
    mov     eax, [rbx + DIR_SIZE]
    mov     [rdi + FI_FILESIZE], rax
    mov     [rdi + FI_PHYSICALSIZE], rax

    ; The FAT timestamps are not decoded; a zeroed EFI_TIME is the honest
    ; answer, and no caller here reads them.
    movzx   eax, byte [rbx + DIR_ATTR]
    and     eax, EFI_FILE_READ_ONLY | EFI_FILE_HIDDEN | EFI_FILE_SYSTEM | \
                 EFI_FILE_DIRECTORY | EFI_FILE_ARCHIVE
    mov     [rdi + FI_ATTRIBUTE], rax

    lea     rdi, [rdi + FI_FILENAME]
    mov     rsi, BUF_NAME16
    lea     rcx, [rcx * 2 + 2]
    call    mem_copy

    mov     [r13], r15
    inc     qword [r12 + F_POS]
    xor     eax, eax
    jmp     .done

.too_small:
    mov     [r13], r15
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done

.device_error:
    mov     rax, EFI_DEVICE_ERROR
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; GetInfo(This, EFI_GUID *InformationType, UINTN *BufferSize, VOID *Buffer)
;
; Only EFI_FILE_INFO is served. EFI_FILE_SYSTEM_INFO would need free-space
; accounting this read-only driver does not compute.
; ----------------------------------------------------------------------------
file_get_info:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad

    mov     r12, rcx
    mov     r13, r8
    mov     r14, r9

    mov     rsi, rdx
    lea     rdi, [rel guid_file_info]
    push    rcx
    mov     ecx, 16
    call    mem_cmp
    pop     rcx
    jne     .unsupported

    lea     rsi, [r12 + F_NAME]
    mov     rdi, BUF_NAME16
    call    name_from_83
    lea     rax, [rcx * 2 + 2]
    add     rax, FI_HEADER_SIZE
    add     rax, 7
    and     rax, -8
    mov     r15, rax

    cmp     [r13], r15
    jb      .too_small
    test    r14, r14
    jz      .bad

    mov     rdi, r14
    push    rcx
    mov     rcx, r15
    xor     al, al
    call    mem_set
    pop     rcx

    mov     [rdi + FI_SIZE], r15
    mov     rax, [r12 + F_SIZE]
    mov     [rdi + FI_FILESIZE], rax
    mov     [rdi + FI_PHYSICALSIZE], rax
    mov     eax, [r12 + F_ATTR]
    and     eax, EFI_FILE_READ_ONLY | EFI_FILE_HIDDEN | EFI_FILE_SYSTEM | \
                 EFI_FILE_DIRECTORY | EFI_FILE_ARCHIVE
    mov     [rdi + FI_ATTRIBUTE], rax

    lea     rdi, [rdi + FI_FILENAME]
    mov     rsi, BUF_NAME16
    lea     rcx, [rcx * 2 + 2]
    call    mem_copy

    mov     [r13], r15
    xor     eax, eax
    jmp     .done

.too_small:
    mov     [r13], r15
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; name_to_83 -- RSI = a CHAR16 path component, ECX = its length in characters,
; RDI = an 11-byte output buffer.
;
; Folded to upper case and split at the last dot, which is how FAT has always
; stored a short name. "." and ".." are passed through as themselves, because
; that is literally how they appear on disk.
; ----------------------------------------------------------------------------
name_to_83:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     r8, rdi
    mov     r9, rsi

    ; blank the field first
    mov     al, ' '
    push    rcx
    mov     rcx, 11
    call    mem_set
    pop     rcx

    ; "." and ".."
    cmp     ecx, 1
    jne     .not_dot
    cmp     word [r9], '.'
    jne     .not_dot
    mov     byte [r8], '.'
    jmp     .done
.not_dot:
    cmp     ecx, 2
    jne     .split
    cmp     word [r9], '.'
    jne     .split
    cmp     word [r9 + 2], '.'
    jne     .split
    mov     byte [r8], '.'
    mov     byte [r8 + 1], '.'
    jmp     .done

.split:
    ; find the last dot, which separates stem from extension
    mov     edx, -1                             ; index of the dot
    xor     ebx, ebx
.find_dot:
    cmp     ebx, ecx
    jae     .have_dot
    mov     eax, ebx
    movzx   eax, word [r9 + rax * 2]
    cmp     ax, '.'
    jne     .next_char
    mov     edx, ebx
.next_char:
    inc     ebx
    jmp     .find_dot
.have_dot:

    ; the stem: up to eight characters before the dot
    mov     ebx, ecx
    cmp     edx, -1
    je      .stem_len
    mov     ebx, edx
.stem_len:
    cmp     ebx, 8
    jbe     .copy_stem
    mov     ebx, 8
.copy_stem:
    xor     eax, eax
.stem:
    cmp     eax, ebx
    jae     .extension
    movzx   esi, word [r9 + rax * 2]
    push    rax
    mov     eax, esi
    call    upcase
    pop     rsi
    mov     [r8 + rsi], al
    mov     rax, rsi
    inc     eax
    jmp     .stem

.extension:
    cmp     edx, -1
    je      .done
    lea     ebx, [rdx + 1]                      ; first character after the dot
    xor     eax, eax                            ; position in the extension
.ext:
    cmp     eax, 3
    jae     .done
    cmp     ebx, ecx
    jae     .done
    movzx   esi, word [r9 + rbx * 2]
    push    rax
    mov     eax, esi
    call    upcase
    pop     rsi
    mov     [r8 + rsi + 8], al
    mov     rax, rsi
    inc     eax
    inc     ebx
    jmp     .ext

.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; upcase -- EAX = a character, returns AL folded to upper case.
; Non-ASCII becomes '_': FAT short names have no way to spell it.
; ----------------------------------------------------------------------------
upcase:
    cmp     eax, 0x7F
    jae     .foreign
    cmp     al, 'a'
    jb      .done
    cmp     al, 'z'
    ja      .done
    sub     al, 'a' - 'A'
    jmp     .done
.foreign:
    mov     al, '_'
.done:
    ret

; ----------------------------------------------------------------------------
; name_from_83 -- RSI = an 11-byte 8.3 name, RDI = a CHAR16 buffer.
; Writes "STEM.EXT" with the padding removed and a NUL, and returns ECX = the
; number of characters written, not counting the NUL.
; ----------------------------------------------------------------------------
name_from_83:
    push    rax
    push    rbx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    mov     r8, rdi
    xor     ecx, ecx

    ; stem, trailing spaces trimmed
    mov     ebx, 8
.trim_stem:
    test    ebx, ebx
    jz      .stem_done
    mov     eax, ebx
    dec     eax
    cmp     byte [rsi + rax], ' '
    jne     .stem_done
    dec     ebx
    jmp     .trim_stem
.stem_done:

    xor     edx, edx
.stem:
    cmp     edx, ebx
    jae     .extension
    movzx   eax, byte [rsi + rdx]
    mov     [r8], ax
    add     r8, 2
    inc     ecx
    inc     edx
    jmp     .stem

.extension:
    ; extension, likewise trimmed; the dot is only written if one survives
    mov     ebx, 3
.trim_ext:
    test    ebx, ebx
    jz      .finish
    mov     eax, ebx
    dec     eax
    cmp     byte [rsi + rax + 8], ' '
    jne     .ext_done
    dec     ebx
    jmp     .trim_ext
.ext_done:

    mov     word [r8], '.'
    add     r8, 2
    inc     ecx

    xor     edx, edx
.ext:
    cmp     edx, ebx
    jae     .finish
    movzx   eax, byte [rsi + rdx + 8]
    mov     [r8], ax
    add     r8, 2
    inc     ecx
    inc     edx
    jmp     .ext

.finish:
    mov     word [r8], 0
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rbx
    pop     rax
    ret

; ============================================================================
; EFI_BLOCK_IO_PROTOCOL -- the whole disk, unpartitioned
; ============================================================================

; ----------------------------------------------------------------------------
; Reset(This, ExtendedVerification)
; ----------------------------------------------------------------------------
bio_reset:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; ReadBlocks(This, MediaId, LBA, BufferSize, Buffer)
; ----------------------------------------------------------------------------
bio_read_blocks:
    mov     r10, [rsp + 0x28]                   ; Buffer
    push    rbx
    push    rcx
    push    rdi

    mov     rbx, EFI_BLOCKIO_MEDIA
    cmp     edx, [rbx + BIOM_MEDIAID]
    jne     .media_changed

    test    r9, r9
    jz      .ok                                 ; a zero-length read is legal
    test    r10, r10
    jz      .bad

    ; The length has to be a whole number of blocks.
    mov     rax, r9
    and     rax, SECTOR_SIZE - 1
    jnz     .bad_size

    ; ...and the range has to be on the disk.
    mov     rax, r9
    shr     rax, 9                              ; -> block count
    mov     rcx, r8
    add     rcx, rax
    dec     rcx
    cmp     rcx, [rbx + BIOM_LASTBLOCK]
    ja      .bad

    mov     rcx, rax
    mov     rax, r8
    mov     rdi, r10
    call    ata_read
    test    eax, eax
    jnz     .device_error
.ok:
    xor     eax, eax
    jmp     .done
.media_changed:
    mov     rax, EFI_MEDIA_CHANGED
    jmp     .done
.bad_size:
    mov     rax, EFI_BAD_BUFFER_SIZE
    jmp     .done
.device_error:
    mov     rax, EFI_DEVICE_ERROR
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     rdi
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; WriteBlocks / FlushBlocks -- the media is presented read-only
; ----------------------------------------------------------------------------
bio_write_blocks:
    mov     rax, EFI_WRITE_PROTECTED
    ret

bio_flush_blocks:
    xor     eax, eax
    ret

; ============================================================================
; Templates and constants
; ============================================================================
align 8
file_template:
    dq  EFI_FILE_PROTOCOL_REVISION
    dq  file_open
    dq  file_close
    dq  file_delete
    dq  file_read
    dq  file_write
    dq  file_get_position
    dq  file_set_position
    dq  file_get_info
    dq  file_set_info
    dq  file_flush

align 8
sfs_template:
    dq  EFI_SIMPLE_FILE_SYSTEM_REVISION
    dq  sfs_open_volume

align 8
bio_template:
    dq  EFI_BLOCK_IO_PROTOCOL_REVISION
    dq  EFI_BLOCKIO_MEDIA
    dq  bio_reset
    dq  bio_read_blocks
    dq  bio_write_blocks
    dq  bio_flush_blocks

align 8
guid_simple_fs:                                 ; 964E5B22-6459-11D2-8E39-00A0C969723B
    dd 0x964E5B22
    dw 0x6459
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

guid_block_io:                                  ; 964E5B21-6459-11D2-8E39-00A0C969723B
    dd 0x964E5B21
    dw 0x6459
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

guid_file_info:                                 ; 09576E92-6D3F-11D2-8E39-00A0C969723B
    dd 0x09576E92
    dw 0x6D3F
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

; The root directory has no name of its own on disk; FAT's own convention for
; a directory that refers to itself is a single dot.
name_root:  db ".          "

; ============================================================================
; fat.asm -- enough FAT32 to find and read one file
;
; Read-only. Long names are decoded, so a volume someone else made -- with a
; \vmlinuz-linux on it, say -- can be opened by the names it shows. A long
; name is a run of fragments stored before its short entry, last fragment
; first, each carrying a checksum of the short name it belongs to; one whose
; run is broken, or whose checksum does not match, is ignored, and the short
; name stands alone, which is what the specification asks of a reader.
; ============================================================================

bits 64

BPB_BYTES_PER_SEC   equ 0x0B
BPB_SEC_PER_CLUS    equ 0x0D
BPB_RESERVED        equ 0x0E
BPB_NUM_FATS        equ 0x10
BPB_FAT_SZ32        equ 0x24
BPB_ROOT_CLUS       equ 0x2C

DIR_NAME            equ 0x00
DIR_ATTR            equ 0x0B
DIR_CLUS_HI         equ 0x14
DIR_CLUS_LO         equ 0x1A
DIR_SIZE            equ 0x1C
DIR_ENTRY_SIZE      equ 32

ATTR_DIRECTORY      equ 0x10
ATTR_LFN            equ 0x0F

FAT_EOC             equ 0x0FFFFFF8

; A long-name fragment: 13 CHAR16 in three pieces around the short entry's
; fields, so that a reader that knows nothing of them sees a volume label.
LFN_ORD             equ 0x00                    ; sequence number, 0x40 = the last
LFN_NAME1           equ 0x01                    ; 5 CHAR16
LFN_CHECKSUM        equ 0x0D
LFN_NAME2           equ 0x0E                    ; 6 CHAR16
LFN_NAME3           equ 0x1C                    ; 2 CHAR16
LFN_CHARS           equ 13
LFN_LAST            equ 0x40
LFN_SEQ_MASK        equ 0x1F
LFN_MAX_FRAGMENTS   equ 20                      ; 260 characters, the VFAT limit

; ----------------------------------------------------------------------------
; fat_mount -- read the BPB of the partition at g_esp_lba and work out where
; the FAT, the data area and the root directory live. Returns EAX = 1 on a
; volume this driver can read.
; ----------------------------------------------------------------------------
fat_mount:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi

    mov     qword [abs g_fat_cached], -1

    mov     rax, [abs g_esp_lba]
    mov     [abs g_fat_part_lba], rax
    mov     ecx, 1
    mov     rdi, BUF_SECTOR
    call    ata_read
    test    eax, eax
    jnz     .fail

    mov     rsi, BUF_SECTOR

    ; This driver assumes 512-byte sectors throughout; anything else would
    ; need every LBA computation below to carry a sector size.
    cmp     word [rsi + BPB_BYTES_PER_SEC], SECTOR_SIZE
    jne     .fail

    movzx   eax, byte [rsi + BPB_SEC_PER_CLUS]
    test    eax, eax
    jz      .fail
    cmp     eax, 128                            ; a cluster must fit BUF_DIR
    ja      .fail
    mov     [abs g_fat_spc], eax

    ; FAT area begins after the reserved sectors.
    movzx   ebx, word [rsi + BPB_RESERVED]
    test    ebx, ebx
    jz      .fail
    mov     rax, [abs g_fat_part_lba]
    add     rax, rbx
    mov     [abs g_fat_fat_lba], rax

    ; The data area begins after every copy of the FAT.
    movzx   ecx, byte [rsi + BPB_NUM_FATS]
    test    ecx, ecx
    jz      .fail
    mov     edx, [rsi + BPB_FAT_SZ32]
    test    edx, edx
    jz      .fail                               ; zero here means FAT12/FAT16
    mov     eax, edx
    imul    rax, rcx
    add     rax, [abs g_fat_fat_lba]
    mov     [abs g_fat_data_lba], rax

    mov     eax, [rsi + BPB_ROOT_CLUS]
    cmp     eax, 2
    jb      .fail
    mov     [abs g_fat_root_clus], eax

    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fat_clus_lba -- EAX = cluster number, returns RAX = its first LBA
; ----------------------------------------------------------------------------
fat_clus_lba:
    push    rdx
    mov     edx, eax
    sub     rdx, 2                              ; cluster 2 is the first one
    mov     eax, [abs g_fat_spc]
    imul    rax, rdx
    add     rax, [abs g_fat_data_lba]
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; fat_next_clus -- EAX = cluster, returns EAX = the next one in the chain.
;
; One FAT sector is cached, which is all the locality a sequential file read
; needs: 128 consecutive clusters share a sector.
; ----------------------------------------------------------------------------
fat_next_clus:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     ebx, eax
    mov     rax, rbx
    shr     rax, 7                              ; 128 FAT32 entries per sector
    add     rax, [abs g_fat_fat_lba]

    cmp     rax, [abs g_fat_cached]
    je      .cached
    mov     [abs g_fat_cached], rax
    mov     ecx, 1
    mov     rdi, BUF_FAT
    call    ata_read
    test    eax, eax
    jz      .cached
    mov     qword [abs g_fat_cached], -1
    mov     eax, FAT_EOC                        ; unreadable FAT ends the chain
    jmp     .done
.cached:
    and     ebx, 127
    shl     ebx, 2
    mov     rdi, BUF_FAT
    mov     eax, [rdi + rbx]
    and     eax, 0x0FFFFFFF                     ; top four bits are reserved
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fat_lookup_long -- find a path component by its long name or its short one.
;
;   EAX = first cluster of the directory
;   RSI = the 11-byte short form of the component, as name_to_83 made it
;   RDI = the component itself, CHAR16, ECX = its length in characters
;
; Returns as fat_lookup. The long name is compared without regard to case,
; as FAT has always done.
; ----------------------------------------------------------------------------
fat_lookup_long:
    mov     [abs g_want_long], rdi
    mov     [abs g_want_len], ecx
    call    fat_lookup.search
    mov     qword [abs g_want_long], 0
    ret

; ----------------------------------------------------------------------------
; fat_lookup -- find an 8.3 name in a directory.
;
;   EAX = first cluster of the directory
;   RSI = pointer to the 11-byte padded name, e.g. "BOOTX64 EFI"
;
; Returns EAX = the entry's first cluster (0 if not found), EDX = its size in
; bytes, CL = its attribute byte.
; ----------------------------------------------------------------------------
fat_lookup:
    mov     qword [abs g_want_long], 0
.search:
    push    rbx
    push    rdi
    push    rsi
    push    r8
    push    r9
    push    r10
    push    r11

    mov     r10, rsi                            ; wanted name
    mov     r11d, eax                           ; current cluster
    call    lfn_reset

.cluster:
    cmp     r11d, 2
    jb      .missing
    cmp     r11d, FAT_EOC
    jae     .missing

    mov     eax, r11d
    call    fat_clus_lba
    mov     ecx, [abs g_fat_spc]
    mov     rdi, BUF_DIR
    call    ata_read
    test    eax, eax
    jnz     .missing

    ; entries in this cluster
    mov     eax, [abs g_fat_spc]
    shl     eax, 9                              ; sectors -> bytes
    shr     eax, 5                              ; bytes -> 32-byte entries
    mov     r9d, eax
    mov     rbx, BUF_DIR

.entry:
    mov     al, [rbx + DIR_NAME]
    test    al, al
    jz      .missing                            ; first free entry ends the directory
    cmp     al, 0xE5
    je      .deleted
    mov     al, [rbx + DIR_ATTR]
    and     al, ATTR_LFN
    cmp     al, ATTR_LFN
    je      .fragment

    ; A short entry, and perhaps the end of a long name.
    call    lfn_owns
    setz    r8b                                 ; the long name is this entry's
    call    lfn_reset

    mov     rsi, r10
    mov     rdi, rbx
    mov     ecx, 11
    call    mem_cmp
    je      .hit
    test    r8b, r8b
    jz      .next_entry
    cmp     qword [abs g_want_long], 0
    je      .next_entry
    call    lfn_equals
    jne     .next_entry
.hit:

    movzx   eax, word [rbx + DIR_CLUS_HI]
    shl     eax, 16
    movzx   edx, word [rbx + DIR_CLUS_LO]
    or      eax, edx
    mov     edx, [rbx + DIR_SIZE]
    mov     cl, [rbx + DIR_ATTR]
    jmp     .done

.fragment:
    call    lfn_feed
    jmp     .next_entry
.deleted:
    call    lfn_reset
.next_entry:
    add     rbx, DIR_ENTRY_SIZE
    dec     r9d
    jnz     .entry

    mov     eax, r11d
    call    fat_next_clus
    mov     r11d, eax
    jmp     .cluster

.missing:
    xor     eax, eax
    xor     edx, edx
    xor     ecx, ecx
.done:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    pop     rdi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; lfn_reset -- forget any long name being gathered.
; ----------------------------------------------------------------------------
lfn_reset:
    mov     dword [abs g_lfn_next], 0
    mov     dword [abs g_lfn_ok], 0
    ret

; ----------------------------------------------------------------------------
; lfn_feed -- RBX = a long-name fragment. Adds its 13 characters to BUF_LFN
; at the place its sequence number says, or abandons the name if the run is
; broken. Fragments arrive last first, so the first one seen fixes the length.
; ----------------------------------------------------------------------------
lfn_feed:
    push    rax
    push    rcx
    push    rsi
    push    rdi
    movzx   eax, byte [rbx + LFN_ORD]
    test    al, LFN_LAST
    jz      .continue
    ; The start of a run: the last fragment, numbered with the count.
    and     eax, LFN_SEQ_MASK
    jz      .broken
    cmp     eax, LFN_MAX_FRAGMENTS
    ja      .broken
    mov     [abs g_lfn_next], eax
    movzx   ecx, byte [rbx + LFN_CHECKSUM]
    mov     [abs g_lfn_csum], ecx
    mov     dword [abs g_lfn_ok], 1
    ; The name ends where the last fragment's characters end, at the latest.
    imul    ecx, eax, LFN_CHARS * 2
    mov     word [BUF_LFN + rcx], 0
    jmp     .store
.continue:
    cmp     dword [abs g_lfn_ok], 0
    je      .done
    and     eax, LFN_SEQ_MASK
    cmp     eax, [abs g_lfn_next]
    jne     .broken
    movzx   ecx, byte [rbx + LFN_CHECKSUM]
    cmp     ecx, [abs g_lfn_csum]
    jne     .broken
.store:
    ; Fragment N holds characters (N-1)*13 to N*13-1.
    mov     eax, [abs g_lfn_next]
    dec     eax
    imul    eax, LFN_CHARS * 2
    lea     rdi, [BUF_LFN + rax]
    lea     rsi, [rbx + LFN_NAME1]
    mov     ecx, 5 * 2
    rep     movsb
    lea     rsi, [rbx + LFN_NAME2]
    mov     ecx, 6 * 2
    rep     movsb
    lea     rsi, [rbx + LFN_NAME3]
    mov     ecx, 2 * 2
    rep     movsb
    dec     dword [abs g_lfn_next]
    jmp     .done
.broken:
    call    lfn_reset
.done:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; lfn_owns -- RBX = a short entry. ZF set if a complete long name was
; gathered just before it and its checksum is this short name's.
; ----------------------------------------------------------------------------
lfn_owns:
    push    rax
    push    rcx
    push    rsi
    cmp     dword [abs g_lfn_ok], 0
    je      .no
    cmp     dword [abs g_lfn_next], 0
    jne     .no                                 ; fragments missing
    ; The VFAT checksum: rotate right one bit, add the next byte.
    xor     eax, eax
    mov     rsi, rbx
    mov     ecx, 11
.sum:
    ror     al, 1
    add     al, [rsi]
    inc     rsi
    dec     ecx
    jnz     .sum
    movzx   eax, al
    cmp     eax, [abs g_lfn_csum]
    jmp     .done
.no:
    or      eax, 1                              ; clears ZF
.done:
    pop     rsi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; lfn_equals -- ZF set if BUF_LFN is the component at g_want_long, of
; g_want_len characters, ignoring the case of ASCII letters.
; ----------------------------------------------------------------------------
lfn_equals:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    mov     rsi, [abs g_want_long]
    mov     rdi, BUF_LFN
    mov     ecx, [abs g_want_len]
.char:
    test    ecx, ecx
    jz      .end
    movzx   eax, word [rsi]
    movzx   edx, word [rdi]
    call    lfn_upcase_pair
    cmp     eax, edx
    jne     .done
    add     rsi, 2
    add     rdi, 2
    dec     ecx
    jmp     .char
.end:
    cmp     word [rdi], 0                       ; and the long name ends there too
.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; lfn_upcase_pair -- EAX and EDX = CHAR16 each, both folded to upper case.
lfn_upcase_pair:
    cmp     eax, 'a'
    jb      .edx
    cmp     eax, 'z'
    ja      .edx
    sub     eax, 'a' - 'A'
.edx:
    cmp     edx, 'a'
    jb      .done
    cmp     edx, 'z'
    ja      .done
    sub     edx, 'a' - 'A'
.done:
    ret

; ----------------------------------------------------------------------------
; lfn_length -- RAX = how many characters BUF_LFN holds before its NUL.
; ----------------------------------------------------------------------------
lfn_length:
    xor     eax, eax
.next:
    cmp     word [BUF_LFN + rax*2], 0
    je      .done
    inc     eax
    cmp     eax, LFN_MAX_FRAGMENTS * LFN_CHARS
    jb      .next
.done:
    ret

; ----------------------------------------------------------------------------
; fat_read_file -- walk a cluster chain into memory.
;
;   EAX = first cluster
;   RDX = number of bytes to read
;   RDI = destination
;
; Returns EAX = 0 on success. Reads whole clusters, so the destination must
; have room for the file rounded up to the cluster size.
; ----------------------------------------------------------------------------
fat_read_file:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10

    mov     r8d, eax                            ; current cluster
    mov     r9, rdx                             ; bytes remaining
    mov     r10, rdi                            ; destination

    mov     ebx, [abs g_fat_spc]
    shl     ebx, 9                              ; bytes per cluster

.cluster:
    test    r9, r9
    jz      .ok
    cmp     r8d, 2
    jb      .fail
    cmp     r8d, FAT_EOC
    jae     .fail                               ; chain ended before the file did

    mov     eax, r8d
    call    fat_clus_lba
    mov     ecx, [abs g_fat_spc]
    mov     rdi, r10
    call    ata_read
    test    eax, eax
    jnz     .fail

    add     r10, rbx
    sub     r9, rbx
    ja      .advance
    xor     r9, r9                              ; last cluster was partial
    jmp     .ok
.advance:
    mov     eax, r8d
    call    fat_next_clus
    mov     r8d, eax
    jmp     .cluster

.ok:
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fat_read_cluster -- EAX = cluster, RDI = destination. EAX = 0 on success.
; ----------------------------------------------------------------------------
fat_read_cluster:
    push    rcx
    call    fat_clus_lba
    mov     ecx, [abs g_fat_spc]
    call    ata_read
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; fat_seek -- EAX = first cluster, RDX = byte offset into the file.
;
; Returns EAX = the cluster covering that offset and EDX = the offset within
; it, or EAX = 0 if the chain ends first. Walking from the start on every seek
; is O(n) in the offset; a sequential reader pays it once per cluster, which
; is the only access pattern here.
; ----------------------------------------------------------------------------
fat_seek:
    push    rbx
    push    rcx
    push    r8

    mov     r8d, eax                            ; current cluster
    mov     ebx, [abs g_fat_spc]
    shl     ebx, 9                              ; bytes per cluster

    mov     rax, rdx
    xor     rdx, rdx
    div     rbx                                 ; RAX = clusters to skip,
    mov     rcx, rax                            ; RDX = offset inside one

.skip:
    test    rcx, rcx
    jz      .arrived
    mov     eax, r8d
    push    rdx
    call    fat_next_clus
    pop     rdx
    mov     r8d, eax
    cmp     eax, 2
    jb      .past_end
    cmp     eax, FAT_EOC
    jae     .past_end
    dec     rcx
    jmp     .skip

.past_end:
    xor     eax, eax
    jmp     .done
.arrived:
    mov     eax, r8d
.done:
    pop     r8
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; fat_dir_nth -- EAX = directory cluster, EDX = ordinal of the wanted entry.
;
; Returns RAX = a pointer to the 32-byte directory entry inside BUF_DIR, or 0
; when the directory has fewer entries than that. The pointer is only valid
; until the next call, which is all any caller here needs.
;
; Long-name fragments are gathered rather than counted: g_lfn_hit says whether
; the entry returned has a long name, which is then in BUF_LFN. Deleted slots
; are skipped; "." and ".." are not,
; because a FAT directory really does contain them and callers expect to see
; them listed.
; ----------------------------------------------------------------------------
fat_dir_nth:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11

    mov     r11d, eax                           ; current cluster
    mov     r10d, edx                           ; entries still to skip
    call    lfn_reset
    mov     dword [abs g_lfn_hit], 0

.cluster:
    cmp     r11d, 2
    jb      .missing
    cmp     r11d, FAT_EOC
    jae     .missing

    mov     eax, r11d
    mov     rdi, BUF_DIR
    call    fat_read_cluster
    test    eax, eax
    jnz     .missing

    mov     eax, [abs g_fat_spc]
    shl     eax, 9
    shr     eax, 5                              ; 32-byte entries per cluster
    mov     r9d, eax
    mov     rbx, BUF_DIR
.entry:
    mov     al, [rbx + DIR_NAME]
    test    al, al
    jz      .missing                            ; end of the directory
    cmp     al, 0xE5
    je      .deleted
    mov     al, [rbx + DIR_ATTR]
    and     al, ATTR_LFN
    cmp     al, ATTR_LFN
    je      .fragment

    test    r10d, r10d
    jz      .found
    dec     r10d
    call    lfn_reset
    jmp     .next
.fragment:
    call    lfn_feed
    jmp     .next
.deleted:
    call    lfn_reset
.next:
    add     rbx, DIR_ENTRY_SIZE
    dec     r9d
    jnz     .entry

    mov     eax, r11d
    call    fat_next_clus
    mov     r11d, eax
    jmp     .cluster

.found:
    ; Whether BUF_LFN now holds this entry's long name.
    call    lfn_owns
    setz    al
    movzx   eax, al
    mov     [abs g_lfn_hit], eax
    mov     rax, rbx
    jmp     .done
.missing:
    xor     eax, eax
.done:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

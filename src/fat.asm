; ============================================================================
; fat.asm -- enough FAT32 to find and read one file
;
; Read-only, short names only. Long-name entries are skipped rather than
; decoded: every path this firmware needs -- \EFI\BOOT\BOOTX64.EFI -- fits
; 8.3 exactly, and a boot loader has no business writing to the volume.
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
; fat_lookup -- find an 8.3 name in a directory.
;
;   EAX = first cluster of the directory
;   RSI = pointer to the 11-byte padded name, e.g. "BOOTX64 EFI"
;
; Returns EAX = the entry's first cluster (0 if not found), EDX = its size in
; bytes, CL = its attribute byte.
; ----------------------------------------------------------------------------
fat_lookup:
    push    rbx
    push    rdi
    push    rsi
    push    r8
    push    r9
    push    r10
    push    r11

    mov     r10, rsi                            ; wanted name
    mov     r11d, eax                           ; current cluster

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
    je      .next_entry                         ; deleted
    mov     al, [rbx + DIR_ATTR]
    and     al, ATTR_LFN
    cmp     al, ATTR_LFN
    je      .next_entry                         ; long-name fragment

    mov     rsi, r10
    mov     rdi, rbx
    mov     ecx, 11
    call    mem_cmp
    jne     .next_entry

    movzx   eax, word [rbx + DIR_CLUS_HI]
    shl     eax, 16
    movzx   edx, word [rbx + DIR_CLUS_LO]
    or      eax, edx
    mov     edx, [rbx + DIR_SIZE]
    mov     cl, [rbx + DIR_ATTR]
    jmp     .done

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
; Long-name fragments and deleted slots are skipped; "." and ".." are not,
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
    je      .next
    mov     al, [rbx + DIR_ATTR]
    and     al, ATTR_LFN
    cmp     al, ATTR_LFN
    je      .next

    test    r10d, r10d
    jz      .found
    dec     r10d
.next:
    add     rbx, DIR_ENTRY_SIZE
    dec     r9d
    jnz     .entry

    mov     eax, r11d
    call    fat_next_clus
    mov     r11d, eax
    jmp     .cluster

.found:
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

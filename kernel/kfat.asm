; ============================================================================
; kfat.asm -- reading FAT32, again
;
; The firmware has a reader and the kernel cannot call it, which is the whole
; point of the exercise: after ExitBootServices the only code that runs is
; code in this image.
;
; Read only, short names only, one cluster in flight at a time.
; ============================================================================

bits 64

BPB_BYTES_PER_SEC   equ 0x0B                ; UINT16
BPB_SEC_PER_CLUS    equ 0x0D                ; UINT8
BPB_RSVD_SEC        equ 0x0E                ; UINT16
BPB_NUM_FATS        equ 0x10                ; UINT8
BPB_FAT_SZ32        equ 0x24                ; UINT32
BPB_ROOT_CLUS       equ 0x2C                ; UINT32

DIR_NAME            equ 0x00                ; 11 bytes, space padded
DIR_ATTR            equ 0x0B
DIR_CLUS_HI         equ 0x14                ; UINT16
DIR_CLUS_LO         equ 0x1A                ; UINT16
DIR_SIZE            equ 0x1C                ; UINT32
DIR_ENTRY_SIZE      equ 32

ATTR_LFN            equ 0x0F
ATTR_DIRECTORY      equ 0x10
ATTR_VOLUME_ID      equ 0x08

DIR_FREE            equ 0xE5
DIR_END             equ 0x00

FAT_NAME_LEN        equ 11
FAT_EOC             equ 0x0FFFFFF8
FAT_MASK            equ 0x0FFFFFFF
FAT_FIRST_CLUSTER   equ 2
FAT_ENTRY_BYTES     equ 4

KFAT_MAX_CLUS_SEC   equ 64                  ; what kbuf_cluster holds

; ----------------------------------------------------------------------------
; kfat_mount -- read the BPB at the start of the ESP. Returns EAX = 1.
; ----------------------------------------------------------------------------
kfat_mount:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     qword [rel g_fat_cached], -1

    mov     rax, [rel g_esp_lba]
    lea rdi, [rel kbuf_sector]
    mov     ecx, 1
    call    kata_read
    test    eax, eax
    jz      .fail

    movzx   eax, word [rel kbuf_sector + BPB_BYTES_PER_SEC]
    cmp     eax, SECTOR_SIZE
    jne     .fail                           ; anything else is somebody's NAS

    movzx   eax, byte [rel kbuf_sector + BPB_SEC_PER_CLUS]
    test    eax, eax
    jz      .fail
    cmp     eax, KFAT_MAX_CLUS_SEC
    ja      .fail
    mov     [rel g_fat_spc], eax

    movzx   ebx, word [rel kbuf_sector + BPB_RSVD_SEC]
    mov     rax, [rel g_esp_lba]
    add     rax, rbx
    mov     [rel g_fat_fat_lba], rax        ; the first FAT

    movzx   ecx, byte [rel kbuf_sector + BPB_NUM_FATS]
    mov     edx, [rel kbuf_sector + BPB_FAT_SZ32]
    test    edx, edx
    jz      .fail
    imul    rcx, rdx
    add     rax, rcx
    mov     [rel g_fat_data_lba], rax       ; where cluster 2 begins

    mov     eax, [rel kbuf_sector + BPB_ROOT_CLUS]
    cmp     eax, FAT_FIRST_CLUSTER
    jb      .fail
    mov     [rel g_fat_root], eax

    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kfat_cluster_lba -- EAX = cluster. Returns RAX = its first sector.
; ----------------------------------------------------------------------------
kfat_cluster_lba:
    push    rdx
    mov     edx, eax
    sub     rdx, FAT_FIRST_CLUSTER
    imul    rdx, [rel g_fat_spc]
    add     rdx, [rel g_fat_data_lba]
    mov     rax, rdx
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; kfat_next -- EAX = cluster. Returns EAX = the next one, or >= FAT_EOC.
;
; One FAT sector is kept, because a chain walked forward asks for the same
; sector many times running.
; ----------------------------------------------------------------------------
kfat_next:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     ebx, eax
    imul    rax, rbx, FAT_ENTRY_BYTES
    mov     rdx, rax
    shr     rax, 9                          ; which sector of the FAT
    and     edx, SECTOR_SIZE - 1            ; and where in it
    add     rax, [rel g_fat_fat_lba]

    cmp     rax, [rel g_fat_cached]
    je      .cached
    mov     [rel g_fat_cached], rax
    lea rdi, [rel kbuf_fat]
    mov     ecx, 1
    call    kata_read
    test    eax, eax
    jz      .fail
.cached:
    lea rax, [rel kbuf_fat]
    add     rax, rdx
    mov     eax, [rax]
    and     eax, FAT_MASK
    jmp     .done
.fail:
    mov     qword [rel g_fat_cached], -1
    mov     eax, FAT_MASK                   ; looks like an end of chain
.done:
    pop     rdi
    pop     rcx
    pop     rdx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kfat_lookup -- EAX = the directory's first cluster, RSI = an eleven byte
; 8.3 name, space padded.
;
; Returns EAX = the entry's first cluster, RDX = its size, CL = its attribute.
; EAX = 0 if there is no such name.
; ----------------------------------------------------------------------------
kfat_lookup:
    push    rbx
    push    rdi
    push    rsi
    push    r8
    push    r9
    push    r10

    mov     r8d, eax                        ; the cluster being scanned
    mov     r9, rsi                         ; the name wanted
.cluster:
    cmp     r8d, FAT_FIRST_CLUSTER
    jb      .miss
    cmp     r8d, FAT_EOC
    jae     .miss

    mov     eax, r8d
    call    kfat_cluster_lba
    lea rdi, [rel kbuf_cluster]
    mov     ecx, [rel g_fat_spc]
    call    kata_read
    test    eax, eax
    jz      .miss

    lea rbx, [rel kbuf_cluster]
    mov     r10d, [rel g_fat_spc]
    shl     r10d, 9
    shr     r10d, 5                         ; entries in this cluster
.entry:
    mov     al, [rbx + DIR_NAME]
    cmp     al, DIR_END
    je      .miss                           ; nothing is ever past this
    cmp     al, DIR_FREE
    je      .advance
    mov     al, [rbx + DIR_ATTR]
    and     al, ATTR_LFN
    cmp     al, ATTR_LFN
    je      .advance                        ; a long name fragment
    test    byte [rbx + DIR_ATTR], ATTR_VOLUME_ID
    jnz     .advance

    mov     rsi, r9
    lea     rdi, [rbx + DIR_NAME]
    mov     ecx, FAT_NAME_LEN
    repe cmpsb
    je      .found
.advance:
    add     rbx, DIR_ENTRY_SIZE
    dec     r10d
    jnz     .entry

    mov     eax, r8d
    call    kfat_next
    mov     r8d, eax
    jmp     .cluster

.found:
    movzx   eax, word [rbx + DIR_CLUS_HI]
    shl     eax, 16
    movzx   edx, word [rbx + DIR_CLUS_LO]
    or      eax, edx
    mov     edx, [rbx + DIR_SIZE]
    mov     cl, [rbx + DIR_ATTR]
    jmp     .done
.miss:
    xor     eax, eax
    xor     edx, edx
    xor     cl, cl
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    pop     rdi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kfat_read_file -- EAX = first cluster, RDX = size in bytes, RDI = where.
; Returns EAX = 1. Reads whole clusters, so the destination must have room
; for the size rounded up to one.
; ----------------------------------------------------------------------------
kfat_read_file:
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9

    mov     r8d, eax
    mov     r9, rdx
.cluster:
    test    r9, r9
    jz      .ok
    cmp     r8d, FAT_FIRST_CLUSTER
    jb      .fail
    cmp     r8d, FAT_EOC
    jae     .fail

    mov     eax, r8d
    call    kfat_cluster_lba
    mov     ecx, [rel g_fat_spc]
    call    kata_read
    test    eax, eax
    jz      .fail

    mov     rbx, [rel g_fat_spc]
    shl     rbx, 9
    add     rdi, rbx
    sub     r9, rbx
    jbe     .ok

    mov     eax, r8d
    call    kfat_next
    mov     r8d, eax
    jmp     .cluster
.ok:
    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rcx
    pop     rdx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; ----------------------------------------------------------------------------
; The buffers. In the image, because the image is the only memory whose
; address this code can compute without being told one.
; ----------------------------------------------------------------------------
align 16
kbuf_sector:    times SECTOR_SIZE db 0
kbuf_fat:       times SECTOR_SIZE db 0
kbuf_gpt:       times GPT_MAX_ENTRIES * GPT_MAX_ENTRY_BYTES db 0
kbuf_cluster:   times KFAT_MAX_CLUS_SEC * SECTOR_SIZE db 0

align 8
g_fat_fat_lba:  dq 0
g_fat_data_lba: dq 0
g_fat_cached:   dq -1
g_fat_spc:      dq 0
g_fat_root:     dd 0

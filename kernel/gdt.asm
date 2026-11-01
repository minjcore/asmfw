; ============================================================================
; gdt.asm -- descriptors, and the task state segment behind them
;
; Two things here are not optional. The descriptor order is fixed by SYSRET's
; selector arithmetic, which kconst.inc spells out. And the TSS is what makes
; a fault in ring 3 survivable: without RSP0 the CPU has no stack to push the
; exception frame onto, and a #GP becomes a #DF becomes a reset.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; gdt_init -- fill in the TSS descriptor, load the table, and reload every
; selector so the CPU is running on the kernel's own descriptors.
; ----------------------------------------------------------------------------
gdt_init:
    push    rax
    push    rbx
    push    rcx
    push    rdx

    ; The TSS's stack for ring 3 -> ring 0, and no I/O permission bitmap:
    ; pointing the base past the end of the segment is how that is said.
    lea     rax, [rel kstack_top]
    lea     rbx, [rel tss]
    mov     [rbx + TSS_RSP0], rax
    mov     word [rbx + TSS_IOMAP], TSS_SIZE

    ; A system descriptor is sixteen bytes with the base split three ways,
    ; which is why it is assembled here rather than written out above.
    mov     rax, rbx
    mov     rcx, rbx
    shl     rax, 16
    mov     rdx, 0x000000FFFFFF0000             ; base[23:0]
    and     rax, rdx
    or      rax, TSS_SIZE - 1                   ; limit
    mov     rdx, TSS_DESC_TYPE
    shl     rdx, 40
    or      rax, rdx
    mov     rdx, rcx
    shr     rdx, 24
    and     rdx, 0xFF
    shl     rdx, 56                             ; base[31:24]
    or      rax, rdx
    lea     rbx, [rel gdt_tss]
    mov     [rbx], rax
    mov     rax, rcx
    shr     rax, 32                             ; base[63:32]
    mov     [rbx + 8], rax

    lea     rax, [rel gdt]
    mov     [rel gdt_ptr + 2], rax
    lgdt    [rel gdt_ptr]

    ; CS cannot be assigned to. A far return is the way to say it.
    lea     rax, [rel .reloaded]
    push    qword KSEL_CODE
    push    rax
    o64 retf
.reloaded:
    mov     ax, KSEL_DATA
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     fs, ax
    mov     gs, ax

    mov     ax, KSEL_TSS
    ltr     ax

    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
align 16
gdt:
    dq  0                                       ; KSEL_NULL
    dq  DESC_KCODE                              ; KSEL_CODE
    dq  DESC_KDATA                              ; KSEL_DATA
    dq  DESC_UCODE32                            ; USEL_CODE32, SYSRET's base
    dq  DESC_UDATA                              ; USEL_DATA
    dq  DESC_UCODE                              ; USEL_CODE
gdt_tss:
    dq  0, 0                                    ; KSEL_TSS, built at run time
gdt_end:

align 8
gdt_ptr:
    dw  gdt_end - gdt - 1
    dq  0                                       ; base, filled in by gdt_init

align 16
tss:
    times TSS_SIZE db 0

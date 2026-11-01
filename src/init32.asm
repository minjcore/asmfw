; ============================================================================
; init32.asm -- SEC phase, part 2
;
; Build a flat identity map of the low 4 GiB out of 2 MiB pages, then enter
; long mode. 2 MiB pages rather than 1 GiB so this does not depend on
; CPUID.80000001:EDX.PDPE1GB, which plain -cpu qemu64 does not advertise.
; ============================================================================

bits 32

sec_entry32:
    mov     ax, SEL_D32
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     esp, FW_STACK_TOP

    ; --- zero the page-table pages ---------------------------------------
    mov     edi, PT_PML4
    xor     eax, eax
    mov     ecx, (PT_PAGES * 4096) / 4
    rep stosd

    ; --- PML4[0] -> PDPT --------------------------------------------------
    mov     dword [PT_PML4], PT_PDPT | 0x03         ; present, writable

    ; --- PDPT[0..3] -> PD[0..3] ------------------------------------------
    mov     edi, PT_PDPT
    mov     eax, PT_PD0 | 0x03
    mov     ecx, 4
.pdpt:
    mov     [edi], eax
    add     eax, 4096
    add     edi, 8
    loop    .pdpt

    ; --- PD entries: 2048 x 2 MiB = 4 GiB ---------------------------------
    mov     edi, PT_PD0
    xor     eax, eax                                ; physical address
    mov     ecx, 2048
.pd:
    mov     edx, eax
    or      edx, 0x83                               ; present, writable, PS
    cmp     eax, MMIO_BELOW_4G
    jb      .cached
    or      edx, 0x18                               ; PCD|PWT: MMIO is uncached
.cached:
    mov     [edi], edx
    add     edi, 8
    add     eax, 0x200000
    loop    .pd

    ; --- PAE --------------------------------------------------------------
    mov     eax, cr4
    or      eax, 1 << 5                             ; PAE
    mov     cr4, eax

    mov     eax, PT_PML4
    mov     cr3, eax

    ; --- EFER.LME ---------------------------------------------------------
    mov     ecx, 0xC0000080                         ; IA32_EFER
    rdmsr
    or      eax, 1 << 8                             ; LME
    wrmsr

    ; --- paging on: this activates long mode ------------------------------
    mov     eax, cr0
    or      eax, 0x80000001                         ; PG | PE
    mov     cr0, eax

    jmp     SEL_C64:sec_entry64

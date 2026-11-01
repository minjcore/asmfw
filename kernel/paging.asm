; ============================================================================
; paging.asm -- address spaces
;
; Every task gets its own. They agree on everything except one entry: the low
; 4 GiB is identity mapped as supervisor in all of them, so the kernel is
; reachable no matter which one is loaded, and exactly one 2 MiB page carries
; U/S -- the window belonging to whichever task the space was built for.
;
; That single difference is the isolation. A task cannot name another task's
; window, because in its own address space that window has no user mapping to
; walk. U/S is set on PML4[0] and PDPT[0..3] and left to the leaf to decide,
; because access is granted only where every level agrees.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; paging_build -- RDI = a PT_PAGE_COUNT-page region to build in,
;                 RSI = the user window to expose, or 0 for none.
; Returns RAX = the PML4 to load into CR3. Does not load it.
; ----------------------------------------------------------------------------
paging_build:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     rbx, rdi

    mov     ecx, PT_PAGE_COUNT * PAGE_SIZE
    xor     eax, eax
    rep     stosb

    ; PML4[0] -> the PDPT
    lea     rax, [rbx + PAGE_SIZE]
    or      rax, PTE_P | PTE_RW | PTE_US
    mov     [rbx], rax

    ; PDPT[0..3] -> the four page directories, which follow it
    lea     rdi, [rbx + PAGE_SIZE]
    lea     rax, [rbx + PAGE_SIZE * 2]
    or      rax, PTE_P | PTE_RW | PTE_US
    mov     ecx, PT_PDPT_USED
.pdpt:
    mov     [rdi], rax
    add     rdi, 8
    add     rax, PAGE_SIZE
    dec     ecx
    jnz     .pdpt

    ; The directories: one 2 MiB page per entry, supervisor only. They are
    ; contiguous, so a single counter walks all four.
    lea     rdi, [rbx + PAGE_SIZE * 2]
    xor     rax, rax
    mov     ecx, PT_PDPT_USED * PT_ENTRIES
.pd:
    mov     rdx, rax
    or      rdx, PTE_P | PTE_RW | PTE_PS
    mov     [rdi], rdx
    add     rdi, 8
    add     rax, BIG_PAGE_SIZE
    dec     ecx
    jnz     .pd

    ; The one entry that makes this address space somebody's. Being contiguous
    ; is what lets the 2 MiB index address the right directory without picking
    ; it first.
    test    rsi, rsi
    jz      .no_window
    mov     rax, rsi
    mov     rdx, rax
    shr     rdx, BIG_PAGE_SHIFT
    lea     rdi, [rbx + PAGE_SIZE * 2]
    lea     rdi, [rdi + rdx * 8]
    or      rax, PTE_P | PTE_RW | PTE_PS | PTE_US
    mov     [rdi], rax
.no_window:

    mov     rax, rbx
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; mem.asm -- the page allocator behind AllocatePages, and the memory map
;
; A bump allocator. Nothing is ever freed, which is a real limitation and a
; deliberate one: this firmware allocates a handful of times, loads one image
; and leaves. A free list would be more code with no user.
;
; Every allocation is recorded so that GetMemoryMap can describe it with the
; memory type the caller asked for. That matters: an OS is entitled to reuse
; EfiBootServicesData after ExitBootServices, so a kernel image handed back
; under the wrong type would be freed out from under itself.
; ============================================================================

bits 64

ALLOC_REC_SIZE      equ 24                      ; base, pages, type + padding
ALLOC_MAX           equ 128

; EFI memory types
EfiReservedMemoryType   equ 0
EfiLoaderCode           equ 1
EfiLoaderData           equ 2
EfiBootServicesCode     equ 3
EfiBootServicesData     equ 4
EfiRuntimeServicesCode  equ 5
EfiRuntimeServicesData  equ 6
EfiConventionalMemory   equ 7
EfiACPIReclaimMemory    equ 9
EfiACPIMemoryNVS        equ 10
EfiMemoryMappedIO       equ 11

EFI_MEMORY_UC           equ 0x0000000000000001
EFI_MEMORY_WB           equ 0x0000000000000008
EFI_MEMORY_RUNTIME      equ 0x8000000000000000

; EFI_MEMORY_DESCRIPTOR. The structure is 40 bytes, but the size reported
; through GetMemoryMap is 48 to match what every other firmware reports;
; consumers are required to stride by the reported size, not by sizeof.
MD_TYPE             equ 0x00
MD_PHYS             equ 0x08
MD_VIRT             equ 0x10
MD_PAGES            equ 0x18
MD_ATTR             equ 0x20
MD_SIZE             equ 48

; What of the firmware's own fixed region survives ExitBootServices: the pages
; holding the globals, and the first page of FW_TABLES, which holds the system
; table, runtime services, configuration table and vendor string.
MAP_GLOBAL_PAGES    equ (GOFF_TOTAL + 0xFFF) >> 12
MAP_TABLE_PAGES     equ 1
%if EFI_VENDOR_STR + 0x80 > FW_TABLES + MAP_TABLE_PAGES * 4096
  %error "the runtime tables have outgrown the page reported for them"
%endif

; ----------------------------------------------------------------------------
; mem_alloc_pages -- RCX = page count, EDX = EFI memory type.
; Returns RAX = base address, or 0 if the heap is exhausted.
; ----------------------------------------------------------------------------
mem_alloc_pages:
    push    rbx
    push    rsi
    push    rdi
    push    r8

    test    rcx, rcx
    jz      .fail

    mov     rax, [abs g_heap_next]
    add     rax, 0xFFF
    and     rax, -4096

    mov     rbx, rcx
    shl     rbx, 12
    mov     rsi, rax
    add     rsi, rbx
    jc      .fail                               ; page count overflowed
    cmp     rsi, [abs g_heap_end]
    ja      .fail
    mov     [abs g_heap_next], rsi

    ; Record it, so the memory map can report the type that was asked for.
    mov     r8d, [abs g_alloc_count]
    cmp     r8d, ALLOC_MAX
    jae     .no_room
    mov     edi, r8d
    imul    edi, ALLOC_REC_SIZE
    add     rdi, ALLOC_TABLE
    mov     [rdi + 0], rax
    mov     [rdi + 8], rcx
    mov     [rdi + 16], edx
    inc     r8d
    mov     [abs g_alloc_count], r8d
.no_room:
    inc     dword [abs g_map_key]
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; mem_alloc_pool -- RCX = byte count, EDX = EFI memory type.
; Returns RAX = base, or 0.
;
; Pool allocations come out of the same bump heap rounded to whole pages.
; Wasteful per call, and irrelevant at the handful of calls this sees.
; ----------------------------------------------------------------------------
mem_alloc_pool:
    push    rcx
    add     rcx, 0xFFF
    shr     rcx, 12
    call    mem_alloc_pages
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; mem_build_map -- write the current memory map into MEMMAP_SCRATCH.
; Returns EAX = number of descriptors written.
;
; The descriptors come out in ascending address order, which the spec does
; not require but every consumer is happier with.
; ----------------------------------------------------------------------------
mem_build_map:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10

    mov     rdi, MEMMAP_SCRATCH
    xor     r9d, r9d                            ; descriptor count

    ; --- the first 640 KiB: firmware scratch, page tables at 0x70000 -------
    xor     rax, rax
    mov     rcx, 0xA0
    mov     edx, EfiBootServicesData
    mov     r8, EFI_MEMORY_WB
    call    .emit

    ; --- 0xA0000..0x100000: legacy video and option ROM window ------------
    mov     rax, 0x000A0000
    mov     rcx, 0x60
    mov     edx, EfiReservedMemoryType
    mov     r8, EFI_MEMORY_UC
    call    .emit

    ; --- firmware globals, stack and EFI structures -----------------------
    ; Two pieces of this outlive ExitBootServices and must be reported so an
    ; OS keeps them: the globals the runtime services read (g_bs_exited,
    ; g_var_store), and the page holding the system table, the runtime
    ; services table and the configuration table. The stack and the rest of
    ; FW_TABLES are boot services data, and an OS may have them back.
    mov     rax, G_BASE
    mov     rcx, MAP_GLOBAL_PAGES
    mov     edx, EfiRuntimeServicesData
    mov     r8, EFI_MEMORY_WB | EFI_MEMORY_RUNTIME
    call    .emit
    mov     rax, G_BASE + MAP_GLOBAL_PAGES * 4096
    mov     rcx, (FW_TABLES - G_BASE) / 4096 - MAP_GLOBAL_PAGES
    mov     edx, EfiBootServicesData
    mov     r8, EFI_MEMORY_WB
    call    .emit
    mov     rax, FW_TABLES
    mov     rcx, MAP_TABLE_PAGES
    mov     edx, EfiRuntimeServicesData
    mov     r8, EFI_MEMORY_WB | EFI_MEMORY_RUNTIME
    call    .emit
    mov     rax, FW_TABLES + MAP_TABLE_PAGES * 4096
    mov     rcx, (FW_HEAP_BASE - FW_TABLES) / 4096 - MAP_TABLE_PAGES
    mov     edx, EfiBootServicesData
    mov     r8, EFI_MEMORY_WB
    call    .emit

    ; --- everything the allocator has handed out --------------------------
    ; The bump allocator never leaves gaps, so the records are already
    ; contiguous and in order.
    mov     r10d, [abs g_alloc_count]
    test    r10d, r10d
    jz      .free_tail
    mov     rsi, ALLOC_TABLE
.record:
    mov     rax, [rsi + 0]
    mov     rcx, [rsi + 8]
    mov     edx, [rsi + 16]
    mov     r8, EFI_MEMORY_WB
    ; Runtime types carry the runtime attribute, which is what tells an OS
    ; to map the range for runtime calls rather than merely leave it alone.
    cmp     edx, EfiRuntimeServicesCode
    je      .runtime
    cmp     edx, EfiRuntimeServicesData
    jne     .typed
.runtime:
    mov     r8, EFI_MEMORY_WB | EFI_MEMORY_RUNTIME
.typed:
    call    .emit
    add     rsi, ALLOC_REC_SIZE
    dec     r10d
    jnz     .record

.free_tail:
    mov     rax, [abs g_heap_next]
    add     rax, 0xFFF
    and     rax, -4096
    mov     rcx, [abs g_heap_end]
    sub     rcx, rax
    jbe     .flash
    shr     rcx, 12
    jz      .flash
    mov     edx, EfiConventionalMemory
    mov     r8, EFI_MEMORY_WB
    call    .emit

.flash:
    ; The flash is not described: nothing executes from it once the runtime
    ; services run from their copy in RAM (rt_shadow), and an OS has no use
    ; for a description of memory-mapped I/O it will never touch.

.done:
    mov     eax, r9d
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; RAX = physical base, RCX = pages, EDX = type, R8 = attributes.
; Advances RDI and R9. Skips empty ranges so no zero-page descriptor is ever
; emitted, which some consumers treat as the end of the map.
.emit:
    test    rcx, rcx
    jz      .emit_done
    mov     [rdi + MD_TYPE], edx
    mov     dword [rdi + MD_TYPE + 4], 0
    mov     [rdi + MD_PHYS], rax
    mov     qword [rdi + MD_VIRT], 0
    mov     [rdi + MD_PAGES], rcx
    mov     [rdi + MD_ATTR], r8
    mov     qword [rdi + MD_SIZE - 8], 0        ; the padding to MD_SIZE
    add     rdi, MD_SIZE
    inc     r9d
.emit_done:
    ret

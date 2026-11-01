; ============================================================================
; efi_bs.asm -- boot services
;
; What is implemented is what a boot loader actually calls. The rest return
; EFI_UNSUPPORTED through bs_unsupported rather than being left as null
; pointers, so a caller that tries one gets a status code instead of a fault.
; ============================================================================

bits 64

AllocateAnyPages    equ 0
AllocateMaxAddress  equ 1
AllocateAddress     equ 2

AllHandles          equ 0
ByRegisterNotify    equ 1
ByProtocol          equ 2

; ----------------------------------------------------------------------------
bs_unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; RaiseTPL(NewTpl) / RestoreTPL(OldTpl)
;
; There are no interrupts enabled and no event queue, so the level is only
; remembered and handed back. Callers use the pair to bracket critical
; sections; both halves have to agree, and they do.
; ----------------------------------------------------------------------------
bs_raise_tpl:
    mov     rax, [abs g_tpl]
    mov     [abs g_tpl], rcx
    ret

bs_restore_tpl:
    mov     [abs g_tpl], rcx
    ret

; ----------------------------------------------------------------------------
; AllocatePages(Type, MemoryType, Pages, EFI_PHYSICAL_ADDRESS *Memory)
; ----------------------------------------------------------------------------
bs_allocate_pages:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13

    test    r9, r9
    jz      .bad
    test    r8, r8
    jz      .bad
    mov     r12, r9                             ; where to report the result
    mov     r13d, edx                           ; memory type

    cmp     ecx, AllocateAddress
    je      .at_address
    cmp     ecx, AllocateMaxAddress
    je      .below
    cmp     ecx, AllocateAnyPages
    jne     .bad

    mov     rcx, r8
    mov     edx, r13d
    call    mem_alloc_pages
    test    rax, rax
    jz      .oom
    jmp     .ok

    ; --- must land below the address the caller passed in ------------------
.below:
    mov     rbx, [r12]                          ; ceiling
    mov     rcx, r8
    mov     edx, r13d
    call    mem_alloc_pages
    test    rax, rax
    jz      .oom
    mov     rsi, r8
    shl     rsi, 12
    add     rsi, rax
    dec     rsi                                 ; last byte allocated
    cmp     rsi, rbx
    ja      .not_found
    jmp     .ok

    ; --- must land exactly where the caller asked --------------------------
    ; The heap only grows, so an exact placement is possible when the request
    ; is ahead of the cursor. The skipped span is still recorded, as free
    ; memory, so the memory map has no holes in it.
.at_address:
    mov     rbx, [r12]                          ; requested base
    test    bx, 0xFFF
    jnz     .not_found                          ; not page aligned
    mov     rax, [abs g_heap_next]
    add     rax, 0xFFF
    and     rax, -4096
    cmp     rbx, rax
    jb      .not_found
    mov     rsi, r8
    shl     rsi, 12
    mov     rdi, rbx
    add     rdi, rsi
    cmp     rdi, [abs g_heap_end]
    ja      .not_found

    mov     rcx, rbx
    sub     rcx, rax                            ; the gap to skip
    jz      .no_gap
    shr     rcx, 12
    mov     edx, EfiConventionalMemory
    call    mem_alloc_pages
.no_gap:
    mov     rcx, r8
    mov     edx, r13d
    call    mem_alloc_pages
    test    rax, rax
    jz      .oom
    cmp     rax, rbx
    jne     .not_found
    jmp     .ok

.ok:
    mov     [r12], rax
    xor     eax, eax
    jmp     .done
.oom:
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.not_found:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; FreePages(Memory, Pages) / FreePool(Buffer)
;
; Accepted and ignored. The allocator behind them is a bump pointer, and this
; firmware's whole lifetime is one boot: the memory is reclaimed when the
; loaded image takes over, not before.
; ----------------------------------------------------------------------------
bs_free_pages:
    xor     eax, eax
    ret

bs_free_pool:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; AllocatePool(PoolType, Size, VOID **Buffer)
; ----------------------------------------------------------------------------
bs_allocate_pool:
    push    rbx
    test    r8, r8
    jz      .bad
    mov     rbx, r8
    mov     r8d, ecx                            ; pool type
    mov     rcx, rdx                            ; size
    mov     edx, r8d
    call    mem_alloc_pool
    test    rax, rax
    jz      .oom
    mov     [rbx], rax
    xor     eax, eax
    pop     rbx
    ret
.oom:
    mov     qword [rbx], 0
    mov     rax, EFI_OUT_OF_RESOURCES
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; GetMemoryMap(UINTN *MemoryMapSize, EFI_MEMORY_DESCRIPTOR *MemoryMap,
;              UINTN *MapKey, UINTN *DescriptorSize, UINT32 *DescriptorVersion)
; ----------------------------------------------------------------------------
bs_get_memory_map:
    mov     r10, [rsp + 0x28]                   ; DescriptorVersion
    push    rbx
    push    rsi
    push    rdi
    push    r12

    test    rcx, rcx
    jz      .bad
    mov     r12, rcx

    call    mem_build_map
    imul    eax, MD_SIZE
    mov     rbx, rax                            ; bytes the map needs

    test    r9, r9
    jz      .no_descsize
    mov     qword [r9], MD_SIZE
.no_descsize:
    test    r10, r10
    jz      .no_version
    mov     dword [r10], 1
.no_version:
    test    r8, r8
    jz      .no_key
    mov     eax, [abs g_map_key]
    mov     [r8], rax
.no_key:

    mov     rsi, [r12]                          ; the buffer the caller has
    mov     [r12], rbx                          ; the buffer it needs
    cmp     rsi, rbx
    jb      .too_small
    test    rdx, rdx
    jz      .bad

    mov     rdi, rdx
    mov     rsi, MEMMAP_SCRATCH
    mov     rcx, rbx
    call    mem_copy
    xor     eax, eax
    jmp     .done
.too_small:
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; HandleProtocol(Handle, EFI_GUID *Protocol, VOID **Interface)
; ----------------------------------------------------------------------------
bs_handle_protocol:
    push    rbx
    push    rsi
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad
    mov     rbx, r8
    mov     rsi, rdx
    mov     rax, rcx
    call    proto_find
    test    rax, rax
    jz      .missing
    mov     [rbx], rax
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.missing:
    mov     qword [rbx], 0
    mov     rax, EFI_UNSUPPORTED
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; LocateProtocol(EFI_GUID *Protocol, VOID *Registration, VOID **Interface)
; ----------------------------------------------------------------------------
bs_locate_protocol:
    push    rbx
    push    rsi
    test    rcx, rcx
    jz      .bad
    test    r8, r8
    jz      .bad
    mov     rbx, r8
    mov     rsi, rcx
    xor     rax, rax                            ; any handle will do
    call    proto_find
    test    rax, rax
    jz      .missing
    mov     [rbx], rax
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.missing:
    mov     qword [rbx], 0
    mov     rax, EFI_NOT_FOUND
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; OpenProtocol(Handle, Protocol, VOID **Interface, AgentHandle,
;              ControllerHandle, Attributes)
;
; Without a driver model there is nothing to open or reference-count, so this
; is HandleProtocol with the extra arguments ignored. A NULL Interface means
; the caller is only testing for the protocol's presence, which is allowed.
; ----------------------------------------------------------------------------
bs_open_protocol:
    push    rbx
    push    rsi
    test    rdx, rdx
    jz      .bad
    mov     rbx, r8
    mov     rsi, rdx
    mov     rax, rcx
    call    proto_find
    test    rax, rax
    jz      .missing
    test    rbx, rbx
    jz      .ok
    mov     [rbx], rax
.ok:
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.missing:
    test    rbx, rbx
    jz      .missing_out
    mov     qword [rbx], 0
.missing_out:
    mov     rax, EFI_UNSUPPORTED
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

bs_close_protocol:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; proto_collect -- RSI = GUID to match, or 0 for every handle.
; RDI = where to write the handles, or 0 to only count them.
; Returns EAX = the number of distinct handles.
; ----------------------------------------------------------------------------
proto_collect:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11

    mov     r10, rsi
    mov     r11, rdi
    xor     r9d, r9d                            ; handles found
    mov     ecx, [abs g_proto_count]
    test    ecx, ecx
    jz      .done
    mov     rbx, PROTO_DB
.next:
    test    r10, r10
    jz      .matched
    push    rcx
    mov     rsi, r10
    mov     rdi, [rbx + 8]
    mov     ecx, 16
    call    mem_cmp
    pop     rcx
    jne     .advance
.matched:
    ; Skip a handle that has already been recorded: one handle can carry
    ; several protocols, and AllHandles must not repeat it.
    mov     rax, [rbx + 0]
    test    r11, r11
    jz      .store
    mov     edx, r9d
    test    edx, edx
    jz      .store
    mov     r8, r11
.dedupe:
    cmp     [r8], rax
    je      .advance
    add     r8, 8
    dec     edx
    jnz     .dedupe
.store:
    test    r11, r11
    jz      .count
    mov     [r11 + r9 * 8], rax
.count:
    inc     r9d
.advance:
    add     rbx, PROTO_REC_SIZE
    dec     ecx
    jnz     .next
.done:
    mov     eax, r9d
    pop     r11
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
; LocateHandle(SearchType, Protocol, SearchKey, UINTN *BufferSize,
;              EFI_HANDLE *Buffer)
; ----------------------------------------------------------------------------
bs_locate_handle:
    mov     r10, [rsp + 0x28]                   ; Buffer
    push    rbx
    push    rsi
    push    rdi
    push    r12

    test    r9, r9
    jz      .bad
    mov     r12, r9

    xor     rsi, rsi
    cmp     ecx, ByProtocol
    jne     .any
    test    rdx, rdx
    jz      .bad
    mov     rsi, rdx
    jmp     .count
.any:
    cmp     ecx, AllHandles
    jne     .unsupported
.count:
    xor     rdi, rdi
    call    proto_collect
    test    eax, eax
    jz      .none
    mov     ebx, eax
    shl     rbx, 3                              ; handles -> bytes

    mov     rax, [r12]
    mov     [r12], rbx
    cmp     rax, rbx
    jb      .too_small
    test    r10, r10
    jz      .bad

    mov     rdi, r10
    call    proto_collect
    xor     eax, eax
    jmp     .done
.none:
    mov     qword [r12], 0
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.too_small:
    mov     rax, EFI_BUFFER_TOO_SMALL
    jmp     .done
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; LocateHandleBuffer(SearchType, Protocol, SearchKey, UINTN *NoHandles,
;                    EFI_HANDLE **Buffer)
; ----------------------------------------------------------------------------
bs_locate_handle_buffer:
    mov     r10, [rsp + 0x28]                   ; Buffer
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13

    test    r9, r9
    jz      .bad
    test    r10, r10
    jz      .bad
    mov     r12, r9
    mov     r13, r10

    xor     rsi, rsi
    cmp     ecx, ByProtocol
    jne     .any
    test    rdx, rdx
    jz      .bad
    mov     rsi, rdx
    jmp     .count
.any:
    cmp     ecx, AllHandles
    jne     .unsupported
.count:
    xor     rdi, rdi
    call    proto_collect
    test    eax, eax
    jz      .none
    mov     ebx, eax

    mov     rcx, rbx
    shl     rcx, 3
    mov     edx, EfiBootServicesData
    call    mem_alloc_pool
    test    rax, rax
    jz      .oom

    mov     rdi, rax
    mov     [r13], rax
    call    proto_collect
    mov     [r12], rax
    xor     eax, eax
    jmp     .done
.none:
    mov     qword [r12], 0
    mov     qword [r13], 0
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.oom:
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; InstallConfigurationTable(EFI_GUID *Guid, VOID *Table)
;
; A NULL table removes the entry. The system table's CRC covers the entry
; count, so it has to be recomputed afterwards.
; ----------------------------------------------------------------------------
CFG_ENTRY_SIZE  equ 24
CFG_MAX         equ 16

bs_install_configuration_table:
    push    rbx
    push    rsi
    push    rdi
    push    r12

    test    rcx, rcx
    jz      .bad
    mov     r12, rdx                            ; the table pointer

    ; look for an existing entry with this GUID
    mov     ebx, [abs g_cfg_count]
    mov     rdi, EFI_CFG_TABLE
    xor     edx, edx
.scan:
    cmp     edx, ebx
    jae     .not_present
    push    rcx
    push    rdx
    mov     rsi, rcx
    mov     ecx, 16
    call    mem_cmp
    pop     rdx
    pop     rcx
    je      .found
    add     rdi, CFG_ENTRY_SIZE
    inc     edx
    jmp     .scan

.found:
    test    r12, r12
    jz      .remove
    mov     [rdi + 16], r12
    jmp     .ok

.remove:
    ; close the gap by moving the last entry into this slot
    dec     ebx
    mov     [abs g_cfg_count], ebx
    cmp     edx, ebx
    jae     .ok
    mov     esi, ebx
    imul    esi, CFG_ENTRY_SIZE
    add     rsi, EFI_CFG_TABLE
    mov     ecx, CFG_ENTRY_SIZE
    call    mem_copy
    jmp     .ok

.not_present:
    test    r12, r12
    jz      .missing
    cmp     ebx, CFG_MAX
    jae     .oom
    ; RDI already points one past the last entry
    mov     rsi, rcx
    mov     ecx, 16
    call    mem_copy
    mov     [rdi + 16], r12
    inc     ebx
    mov     [abs g_cfg_count], ebx

.ok:
    mov     rdi, EFI_ST
    mov     eax, [abs g_cfg_count]
    mov     [rdi + ST_NUMTABLEENTRIES], rax
    call    efi_fix_crc
    xor     eax, eax
    jmp     .done
.missing:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.oom:
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; ExitBootServices(ImageHandle, MapKey)
;
; The key check is the whole point of the call: it proves the caller's copy of
; the memory map is the current one, and therefore that it knows about every
; allocation before it takes ownership of memory.
; ----------------------------------------------------------------------------
bs_exit_boot_services:
    mov     eax, [abs g_map_key]
    cmp     rdx, rax
    jne     .stale
    mov     dword [abs g_bs_exited], 1
    cli
    xor     eax, eax
    ret
.stale:
    mov     rax, EFI_INVALID_PARAMETER
    ret

; ----------------------------------------------------------------------------
; Exit(ImageHandle, ExitStatus, ExitDataSize, ExitData)
;
; Does not return to its caller. The stack is cut back to what it was just
; before the image was entered and execution resumes at the firmware's return
; path, which is the only way out of an image that never returns normally.
; ----------------------------------------------------------------------------
bs_exit:
    mov     [abs g_exit_status], rdx
    mov     rax, rdx
    jmp     image_exit_resume

; ----------------------------------------------------------------------------
; GetNextMonotonicCount(UINT64 *Count)
; ----------------------------------------------------------------------------
bs_get_next_monotonic_count:
    test    rcx, rcx
    jz      .bad
    mov     rax, [abs g_mono_count]
    inc     rax
    mov     [abs g_mono_count], rax
    mov     [rcx], rax
    xor     eax, eax
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    ret

; ----------------------------------------------------------------------------
; Stall(Microseconds)
; ----------------------------------------------------------------------------
bs_stall:
    call    stall_us
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; SetWatchdogTimer(Timeout, WatchdogCode, DataSize, WatchdogData)
; Accepted: there is no watchdog to arm, so every timeout is honoured exactly.
; ----------------------------------------------------------------------------
bs_set_watchdog_timer:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; ConnectController(...) -- every device this firmware has is already bound
; ----------------------------------------------------------------------------
bs_connect_controller:
    mov     rax, EFI_NOT_FOUND
    ret

; ----------------------------------------------------------------------------
; WaitForEvent(NumberOfEvents, EFI_EVENT *Event, UINTN *Index)
;
; The only event this firmware creates is ConIn's WaitForKey, so waiting means
; polling the keyboard.
; ----------------------------------------------------------------------------
bs_wait_for_event:
    push    rbx
    push    rsi
    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    mov     rax, [rdx]
    cmp     rax, EFI_WAITKEY_EVENT
    jne     .unsupported
    mov     rbx, r8
.poll:
    call    kbd_peek
    test    eax, eax
    jnz     .ready
    pause
    jmp     .poll
.ready:
    test    rbx, rbx
    jz      .ok
    mov     qword [rbx], 0
.ok:
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; CheckEvent(Event)
; ----------------------------------------------------------------------------
bs_check_event:
    cmp     rcx, EFI_WAITKEY_EVENT
    jne     .unsupported
    call    kbd_peek
    test    eax, eax
    jz      .not_ready
    xor     eax, eax
    ret
.not_ready:
    mov     rax, EFI_NOT_READY
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret

bs_close_event:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; kbd_peek -- EAX non-zero if the keyboard controller has a byte waiting
; ----------------------------------------------------------------------------
kbd_peek:
    push    rdx
    mov     dx, KBD_STATUS
    in      al, dx
    and     eax, 0x01
    pop     rdx
    ret

; ----------------------------------------------------------------------------
; CalculateCrc32(Data, DataSize, UINT32 *Crc32)
; ----------------------------------------------------------------------------
bs_calculate_crc32:
    push    rbx
    push    rsi
    test    rcx, rcx
    jz      .bad
    test    rdx, rdx
    jz      .bad
    test    r8, r8
    jz      .bad
    mov     rbx, r8
    mov     rsi, rcx
    mov     ecx, edx
    call    crc32
    mov     [rbx], eax
    xor     eax, eax
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; CopyMem(Destination, Source, Length) -- must handle overlap
; ----------------------------------------------------------------------------
bs_copy_mem:
    push    rsi
    push    rdi
    mov     rdi, rcx
    mov     rsi, rdx
    mov     rcx, r8
    test    rcx, rcx
    jz      .done
    cmp     rdi, rsi
    jbe     .forward
    ; destination overlaps ahead of the source: copy from the top down
    lea     rdi, [rdi + rcx - 1]
    lea     rsi, [rsi + rcx - 1]
    std
    rep movsb
    cld
    jmp     .done
.forward:
    rep movsb
.done:
    pop     rdi
    pop     rsi
    ret

; ----------------------------------------------------------------------------
; SetMem(Buffer, Size, Value)
; ----------------------------------------------------------------------------
bs_set_mem:
    push    rdi
    mov     rdi, rcx
    mov     rcx, rdx
    mov     eax, r8d
    rep stosb
    pop     rdi
    ret

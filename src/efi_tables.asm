; ============================================================================
; efi_tables.asm -- build the structures an EFI image is handed
;
; The tables are laid out as templates in the flash volume and copied into RAM
; at DXE time. Every pointer in them is a link-time constant -- firmware code
; lives at a fixed address in the volume, the runtime structures at a fixed
; address in RAM -- so the templates need no relocation, only a CRC and the
; few fields that depend on what the machine turned out to have.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; efi_init -- populate the RAM structures and register the protocols
; ----------------------------------------------------------------------------
efi_init:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     dword [abs g_proto_count], 0

    ; --- copy the templates ----------------------------------------------
    lea     rsi, [rel st_template]
    mov     rdi, EFI_ST
    mov     ecx, ST_SIZE
    call    mem_copy

    lea     rsi, [rel bs_template]
    mov     rdi, EFI_BS
    mov     ecx, BS_SIZE
    call    mem_copy

    lea     rsi, [rel rt_template]
    mov     rdi, EFI_RT
    mov     ecx, RT_SIZE
    call    mem_copy
    call    rt_shadow

    lea     rsi, [rel conout_template]
    mov     rdi, EFI_CONOUT
    mov     ecx, TO_SIZE
    call    mem_copy

    lea     rsi, [rel conin_template]
    mov     rdi, EFI_CONIN
    mov     ecx, TI_SIZE
    call    mem_copy

    lea     rsi, [rel vendor_string]
    mov     rdi, EFI_VENDOR_STR
    mov     ecx, vendor_string_end - vendor_string
    call    mem_copy

    ; --- text output mode -------------------------------------------------
    mov     rdi, EFI_CONOUT_MODE
    mov     dword [rdi + TOM_MAXMODE], 1
    mov     dword [rdi + TOM_MODE], 0
    mov     dword [rdi + TOM_ATTRIBUTE], 0x07
    mov     dword [rdi + TOM_CURSORCOLUMN], 0
    mov     dword [rdi + TOM_CURSORROW], 0
    mov     dword [rdi + TOM_CURSORVISIBLE], 1

    ; --- an opaque token for ConIn's WaitForKey ---------------------------
    ; Nothing dereferences it; it only has to be unique and non-null.
    mov     rdi, EFI_WAITKEY_EVENT
    mov     rax, 0x5745564B45594E54             ; "WEVKEYNT", byte-reversed
    mov     [rdi], rax

    ; --- register the protocols -------------------------------------------
    mov     rax, H_CONOUT
    lea     rsi, [rel guid_text_output]
    mov     rdi, EFI_CONOUT
    call    proto_add

    mov     rax, H_CONIN
    lea     rsi, [rel guid_text_input]
    mov     rdi, EFI_CONIN
    call    proto_add

    ; --- graphics, if the machine has any ---------------------------------
    cmp     dword [abs g_fb_ok], 0
    je      .no_gop

    lea     rsi, [rel gop_template]
    mov     rdi, EFI_GOP
    mov     ecx, GOP_SIZE
    call    mem_copy

    mov     rdi, EFI_GOP_INFO
    mov     dword [rdi + GOPI_VERSION], 0
    mov     eax, [abs g_fb_w]
    mov     [rdi + GOPI_HRES], eax
    mov     eax, [abs g_fb_h]
    mov     [rdi + GOPI_VRES], eax
    mov     dword [rdi + GOPI_PIXELFORMAT], PixelBlueGreenRedReserved8BitPerColor
    xor     eax, eax
    mov     [rdi + GOPI_PIXELINFO + 0], eax
    mov     [rdi + GOPI_PIXELINFO + 4], eax
    mov     [rdi + GOPI_PIXELINFO + 8], eax
    mov     [rdi + GOPI_PIXELINFO + 12], eax
    mov     eax, [abs g_fb_pitch]
    shr     eax, 2                              ; bytes -> pixels per scanline
    mov     [rdi + GOPI_PPSL], eax

    mov     rdi, EFI_GOP_MODE
    mov     dword [rdi + GOPM_MAXMODE], 1
    mov     dword [rdi + GOPM_MODE], 0
    mov     qword [rdi + GOPM_INFO], EFI_GOP_INFO
    mov     qword [rdi + GOPM_SIZEOFINFO], GOPI_SIZE
    mov     rax, [abs g_fb_base]
    mov     [rdi + GOPM_FRAMEBUFFERBASE], rax
    mov     rax, [abs g_fb_size]
    mov     [rdi + GOPM_FRAMEBUFFERSIZE], rax

    mov     rax, H_GOP
    lea     rsi, [rel guid_gop]
    mov     rdi, EFI_GOP
    call    proto_add
.no_gop:

    ; --- block storage, if a disk answered --------------------------------
    cmp     dword [abs g_ata_present], 0
    je      .no_disk

    lea     rsi, [rel bio_template]
    mov     rdi, EFI_BLOCKIO
    mov     ecx, BIO_SIZE
    call    mem_copy

    mov     rdi, EFI_BLOCKIO_MEDIA
    mov     dword [rdi + BIOM_MEDIAID], 1
    mov     byte  [rdi + BIOM_REMOVABLE], 0
    mov     byte  [rdi + BIOM_PRESENT], 1
    mov     byte  [rdi + BIOM_LOGICALPARTITION], 0
    mov     byte  [rdi + BIOM_READONLY], 1
    mov     byte  [rdi + BIOM_WRITECACHING], 0
    mov     dword [rdi + BIOM_BLOCKSIZE], SECTOR_SIZE
    mov     dword [rdi + BIOM_IOALIGN], 0
    mov     rax, [abs g_ata_sectors]
    dec     rax
    mov     [rdi + BIOM_LASTBLOCK], rax

    mov     rax, H_DISK
    lea     rsi, [rel guid_block_io]
    mov     rdi, EFI_BLOCKIO
    call    proto_add
.no_disk:

    ; --- checksum the three headers ---------------------------------------
    mov     rdi, EFI_ST
    call    efi_fix_crc
    mov     rdi, EFI_BS
    call    efi_fix_crc
    mov     rdi, EFI_RT
    call    efi_fix_crc

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; efi_publish_volume -- register Simple File System on the disk handle.
;
; Separate from efi_init because it can only happen once the volume has been
; mounted, and mounting is a BDS decision: which partition to look at is a
; boot policy question, not a device one.
; ----------------------------------------------------------------------------
efi_publish_volume:
    push    rax
    push    rcx
    push    rsi
    push    rdi

    lea     rsi, [rel sfs_template]
    mov     rdi, EFI_SFS
    mov     ecx, SFS_SIZE
    call    mem_copy

    mov     rax, H_DISK
    lea     rsi, [rel guid_simple_fs]
    mov     rdi, EFI_SFS
    call    proto_add

    pop     rdi
    pop     rsi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; efi_fix_crc -- RDI = a table with an EFI_TABLE_HEADER.
; The CRC is taken over HeaderSize bytes with the CRC field itself zeroed.
; ----------------------------------------------------------------------------
efi_fix_crc:
    push    rax
    push    rcx
    push    rsi
    mov     dword [rdi + TH_CRC32], 0
    mov     ecx, [rdi + TH_HEADERSIZE]
    mov     rsi, rdi
    call    crc32
    mov     [rdi + TH_CRC32], eax
    pop     rsi
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; crc32 -- RSI = data, ECX = length, returns EAX.
;
; The reflected CRC-32 the UEFI spec calls for. Computed a bit at a time: a
; 1 KiB lookup table would be faster and this runs a few hundred bytes, once.
; ----------------------------------------------------------------------------
crc32:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    mov     eax, 0xFFFFFFFF
    test    ecx, ecx
    jz      .done
.byte:
    movzx   ebx, byte [rsi]
    xor     al, bl
    mov     edx, 8
.bit:
    test    eax, 1
    jz      .shift
    shr     eax, 1
    xor     eax, 0xEDB88320
    jmp     .next_bit
.shift:
    shr     eax, 1
.next_bit:
    dec     edx
    jnz     .bit
    inc     rsi
    dec     ecx
    jnz     .byte
.done:
    not     eax
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; proto_add -- RAX = handle, RSI = GUID, RDI = interface pointer
; ----------------------------------------------------------------------------
proto_add:
    push    rbx
    push    rcx
    mov     ecx, [abs g_proto_count]
    cmp     ecx, PROTO_MAX
    jae     .full
    mov     ebx, ecx
    imul    ebx, PROTO_REC_SIZE
    add     rbx, PROTO_DB
    mov     [rbx + 0], rax
    mov     [rbx + 8], rsi
    mov     [rbx + 16], rdi
    inc     ecx
    mov     [abs g_proto_count], ecx
.full:
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; proto_find -- RSI = GUID, RAX = handle to match, or 0 for "any handle".
; Returns RAX = interface pointer, or 0.
; ----------------------------------------------------------------------------
proto_find:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    mov     r8, rax                             ; wanted handle
    mov     r9, rsi                             ; wanted GUID
    mov     ecx, [abs g_proto_count]
    test    ecx, ecx
    jz      .miss
    mov     rbx, PROTO_DB
.next:
    test    r8, r8
    jz      .check_guid
    cmp     [rbx + 0], r8
    jne     .advance
.check_guid:
    mov     rsi, r9
    mov     rdi, [rbx + 8]
    push    rcx
    mov     ecx, 16
    call    mem_cmp
    pop     rcx
    jne     .advance
    mov     rax, [rbx + 16]
    jmp     .done
.advance:
    add     rbx, PROTO_REC_SIZE
    dec     ecx
    jnz     .next
.miss:
    xor     eax, eax
.done:
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================================
; Templates
; ============================================================================

; ----------------------------------------------------------------------------
align 8
st_template:
    dq  SIG_SYSTEM_TABLE
    dd  EFI_SPEC_REVISION
    dd  ST_SIZE
    dd  0                                       ; CRC32, filled in later
    dd  0
    dq  EFI_VENDOR_STR                          ; FirmwareVendor
    dd  FIRMWARE_REVISION                       ; FirmwareRevision
    dd  0                                       ; padding
    dq  H_CONIN                                 ; ConsoleInHandle
    dq  EFI_CONIN
    dq  H_CONOUT                                ; ConsoleOutHandle
    dq  EFI_CONOUT
    dq  H_CONOUT                                ; StandardErrorHandle
    dq  EFI_CONOUT                              ; StdErr shares the console
    dq  EFI_RT
    dq  EFI_BS
    dq  0                                       ; NumberOfTableEntries
    dq  EFI_CFG_TABLE

; ----------------------------------------------------------------------------
align 8
bs_template:
    dq  SIG_BOOT_SERVICES
    dd  EFI_SPEC_REVISION
    dd  BS_SIZE
    dd  0                                       ; CRC32
    dd  0
    dq  bs_raise_tpl
    dq  bs_restore_tpl
    dq  bs_allocate_pages
    dq  bs_free_pages
    dq  bs_get_memory_map
    dq  bs_allocate_pool
    dq  bs_free_pool
    dq  bs_unsupported                          ; CreateEvent
    dq  bs_unsupported                          ; SetTimer
    dq  bs_wait_for_event
    dq  bs_unsupported                          ; SignalEvent
    dq  bs_close_event
    dq  bs_check_event
    dq  bs_unsupported                          ; InstallProtocolInterface
    dq  bs_unsupported                          ; ReinstallProtocolInterface
    dq  bs_unsupported                          ; UninstallProtocolInterface
    dq  bs_handle_protocol
    dq  0                                       ; reserved by the spec
    dq  bs_unsupported                          ; RegisterProtocolNotify
    dq  bs_locate_handle
    dq  bs_locate_device_path
    dq  bs_install_configuration_table
    dq  bs_load_image
    dq  bs_start_image
    dq  bs_exit
    dq  bs_unload_image
    dq  bs_exit_boot_services
    dq  bs_get_next_monotonic_count
    dq  bs_stall
    dq  bs_set_watchdog_timer
    dq  bs_connect_controller
    dq  bs_unsupported                          ; DisconnectController
    dq  bs_open_protocol
    dq  bs_close_protocol
    dq  bs_unsupported                          ; OpenProtocolInformation
    dq  bs_unsupported                          ; ProtocolsPerHandle
    dq  bs_locate_handle_buffer
    dq  bs_locate_protocol
    dq  bs_unsupported                          ; InstallMultipleProtocolInterfaces
    dq  bs_unsupported                          ; UninstallMultipleProtocolInterfaces
    dq  bs_calculate_crc32
    dq  bs_copy_mem
    dq  bs_set_mem
    dq  bs_unsupported                          ; CreateEventEx

; ----------------------------------------------------------------------------
align 8
rt_template:
    dq  SIG_RUNTIME_SERVICES
    dd  EFI_SPEC_REVISION
    dd  RT_SIZE
    dd  0                                       ; CRC32
    dd  0
    dq  rt_get_time
    dq  rt_unsupported                          ; SetTime
    dq  rt_unsupported                          ; GetWakeupTime
    dq  rt_unsupported                          ; SetWakeupTime
    dq  rt_unsupported                          ; SetVirtualAddressMap
    dq  rt_unsupported                          ; ConvertPointer
    dq  rt_get_variable
    dq  rt_get_next_variable_name
    dq  rt_set_variable
    dq  rt_unsupported                          ; GetNextHighMonotonicCount
    dq  rt_reset_system
    dq  rt_unsupported                          ; UpdateCapsule
    dq  rt_unsupported                          ; QueryCapsuleCapabilities
    dq  rt_query_variable_info

; ----------------------------------------------------------------------------
align 8
conout_template:
    dq  to_reset
    dq  to_output_string
    dq  to_test_string
    dq  to_query_mode
    dq  to_set_mode
    dq  to_set_attribute
    dq  to_clear_screen
    dq  to_set_cursor_position
    dq  to_enable_cursor
    dq  EFI_CONOUT_MODE

align 8
conin_template:
    dq  ti_reset
    dq  ti_read_key_stroke
    dq  EFI_WAITKEY_EVENT

align 8
gop_template:
    dq  gop_query_mode
    dq  gop_set_mode
    dq  gop_blt
    dq  EFI_GOP_MODE

; ----------------------------------------------------------------------------
; Protocol GUIDs, in the usual mixed-endian on-disk form
; ----------------------------------------------------------------------------
align 8
guid_text_output:                               ; 387477C2-69C7-11D2-8E39-00A0C969723B
    dd 0x387477C2
    dw 0x69C7
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

guid_text_input:                                ; 387477C1-69C7-11D2-8E39-00A0C969723B
    dd 0x387477C1
    dw 0x69C7
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

guid_gop:                                       ; 9042A9DE-23DC-4A38-96FB-7ADED080516A
    dd 0x9042A9DE
    dw 0x23DC
    dw 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

guid_loaded_image:                              ; 5B1B31A1-9562-11D2-8E3F-00A0C969723B
    dd 0x5B1B31A1
    dw 0x9562
    dw 0x11D2
    db 0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

align 2
vendor_string:
    dw __utf16le__("asmfw"), 0
vendor_string_end:

; ----------------------------------------------------------------------------
; rt_shadow -- copy the flash volume into runtime services code, and point the
; runtime services table at the copy.
;
; The runtime services have to keep working after ExitBootServices, from
; wherever the OS can execute them. An OS maps EfiRuntimeServicesCode
; executable and maps memory-mapped I/O -- which is what the flash is -- as
; data only; Linux calls SetVirtualAddressMap through this table before
; anything else, so a pointer into the flash is an instruction fetch from a
; no-execute page, and the kernel dies there.
;
; The whole volume is copied, at the same layout, so every relative call and
; RIP-relative reference inside it still lands where it should. The runtime
; functions use nothing else: their state is in RAM globals, at absolute
; addresses that do not move.
; ----------------------------------------------------------------------------
rt_shadow:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    mov     ecx, FV_SIZE >> 12
    mov     edx, EfiRuntimeServicesCode
    call    mem_alloc_pages
    test    rax, rax
    jz      .done                               ; the flash copies stay
    mov     [abs g_rt_shadow], rax
    mov     rdi, rax
    mov     rsi, FV_BASE
    mov     ecx, FV_SIZE / 8
    rep     movsq
    ; Every entry after the header is a function in the volume: rebase it.
    mov     rdi, EFI_RT + HDR_SIZE
    mov     ecx, (RT_SIZE - HDR_SIZE) / 8
    mov     rsi, FV_BASE                        ; too wide for an immediate operand
    sub     rax, rsi                            ; RAX = how far the copy moved it
.entry:
    mov     rdx, [rdi]
    add     rdx, rax
    mov     [rdi], rdx
    add     rdi, 8
    dec     ecx
    jnz     .entry
.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

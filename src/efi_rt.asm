; ============================================================================
; efi_rt.asm -- runtime services
;
; These are the services that outlive ExitBootServices. This firmware keeps
; them honest but small: a real clock, a reset that actually resets, and the
; variable services, which live in efi_var.asm.
;
; SetVirtualAddressMap is not supported, so the table stays valid only at its
; physical address. An OS that wants to call these after paging is its own
; must therefore keep them identity-mapped -- which is what Linux does by
; default, and what every other caller here does.
; ============================================================================

bits 64

rt_unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret

; ----------------------------------------------------------------------------
; GetTime(EFI_TIME *Time, EFI_TIME_CAPABILITIES *Capabilities)
; ----------------------------------------------------------------------------
TIME_YEAR       equ 0x00        ; UINT16
TIME_MONTH      equ 0x02
TIME_DAY        equ 0x03
TIME_HOUR       equ 0x04
TIME_MINUTE     equ 0x05
TIME_SECOND     equ 0x06
TIME_PAD1       equ 0x07
TIME_NANOSECOND equ 0x08        ; UINT32
TIME_TIMEZONE   equ 0x0C        ; INT16
TIME_DAYLIGHT   equ 0x0E
TIME_PAD2       equ 0x0F

EFI_UNSPECIFIED_TIMEZONE equ 0x07FF

rt_get_time:
    push    rbx
    push    rsi
    push    rdi
    test    rcx, rcx
    jz      .bad
    mov     rbx, rcx

    ; Wait out any update in progress, so the fields cannot be read across
    ; the RTC's own carry.
    mov     ecx, 0x00100000
.wait:
    mov     al, 0x0A
    call    cmos_read
    test    al, 0x80                            ; UIP
    jz      .stable
    dec     ecx
    jnz     .wait
.stable:

    mov     al, 0x0B
    call    cmos_read
    mov     esi, eax                            ; status register B

    mov     al, 0x00
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    mov     [rbx + TIME_SECOND], al

    mov     al, 0x02
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    mov     [rbx + TIME_MINUTE], al

    mov     al, 0x04
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    mov     [rbx + TIME_HOUR], al

    mov     al, 0x07
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    mov     [rbx + TIME_DAY], al

    mov     al, 0x08
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    mov     [rbx + TIME_MONTH], al

    mov     al, 0x09
    call    cmos_read
    movzx   edi, al
    call    rtc_decode
    movzx   eax, al

    ; The RTC keeps two digits. The century register is not reliable across
    ; machines, so the window is pinned instead: 70..99 is the 20th century,
    ; everything else the 21st.
    cmp     eax, 70
    jb      .twenty_first
    add     eax, 1900
    jmp     .have_year
.twenty_first:
    add     eax, 2000
.have_year:
    mov     [rbx + TIME_YEAR], ax

    mov     byte [rbx + TIME_PAD1], 0
    mov     dword [rbx + TIME_NANOSECOND], 0
    mov     word [rbx + TIME_TIMEZONE], EFI_UNSPECIFIED_TIMEZONE
    mov     byte [rbx + TIME_DAYLIGHT], 0
    mov     byte [rbx + TIME_PAD2], 0

    ; Capabilities, if the caller asked for them: one-second resolution,
    ; one-second accuracy, and the clock does not stop when power is cut.
    test    rdx, rdx
    jz      .ok
    mov     dword [rdx + 0], 1                  ; Resolution, Hz
    mov     dword [rdx + 4], 0                  ; Accuracy, in 1e-6 ppm
    mov     byte [rdx + 8], 1                   ; SetsToZero
.ok:
    xor     eax, eax
    pop     rdi
    pop     rsi
    pop     rbx
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; rtc_decode -- EDI = raw CMOS byte, ESI = status register B.
; Returns AL as a binary value, converting from BCD when bit 2 says to.
; ----------------------------------------------------------------------------
rtc_decode:
    push    rcx
    mov     eax, edi
    test    esi, 0x04                           ; DM: data is already binary
    jnz     .done
    mov     ecx, eax
    and     ecx, 0x0F
    shr     eax, 4
    and     eax, 0x0F
    imul    eax, 10
    add     eax, ecx
.done:
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; ResetSystem(ResetType, ResetStatus, DataSize, ResetData)
;
;   0 EfiResetCold      1 EfiResetWarm
;   2 EfiResetShutdown  3 EfiResetPlatformSpecific
; ----------------------------------------------------------------------------
rt_reset_system:
    cli
    cmp     ecx, 2
    jne     .reset

    ; ACPI soft-off: SLP_TYP 0 with SLP_EN set, in the PM1a control block
    ; QEMU puts at 0x604 on both the i440fx and Q35 machines.
    mov     dx, 0x604
    mov     ax, 0x2000
    out     dx, ax

    ; Older QEMU answered on a different port; try that too before falling
    ; through to a reset.
    mov     dx, 0xB004
    mov     ax, 0x2000
    out     dx, ax

.reset:
    ; The PCI reset control register: bit 1 asserts INIT#, bit 2 makes it a
    ; full reset rather than a soft one.
    mov     dx, 0x0CF9
    mov     al, 0x02
    out     dx, al
    mov     al, 0x06
    out     dx, al

    ; If the chipset ignored that, pulse the CPU reset line the way the
    ; keyboard controller has done since 1984.
    mov     dx, 0x64
    mov     al, 0xFE
    out     dx, al

.hang:
    hlt
    jmp     .hang

; ----------------------------------------------------------------------------
; rt_set_virtual_address_map -- SetVirtualAddressMap(MemoryMapSize,
; DescriptorSize, DescriptorVersion, VirtualMap).
;
; The OS has chosen a virtual address for every runtime range and says which
; in VirtualMap. Every pointer the firmware will follow from now on, and every
; pointer it hands out, is rewritten to match: the runtime services table's
; entries, the system table's RuntimeServices, ConfigurationTable and
; FirmwareVendor, and the variable store. Then the two tables' CRCs are taken
; again. It may be called once, and only after ExitBootServices.
;
; What is not rewritten is code: the runtime functions reach their globals
; through absolute physical addresses, assembled in. Those keep working only
; because the globals' pages are runtime memory and an OS that maps them at a
; new address keeps the identity mapping too -- which Linux does, on purpose,
; for exactly this kind of firmware. An OS that dropped the identity mapping
; would find the variable services faulting.
; ----------------------------------------------------------------------------
rt_set_virtual_address_map:
    push    rbx
    push    rsi
    push    rdi
    cmp     dword [abs g_virtual], 0
    jne     .unsupported
    cmp     dword [abs g_bs_exited], 0
    je      .unsupported
    test    r9, r9
    jz      .bad
    cmp     rdx, MD_ATTR + 8                    ; a descriptor must reach Attribute
    jb      .bad
    cmp     r8d, 1                              ; EFI_MEMORY_DESCRIPTOR_VERSION
    jne     .bad
    mov     [abs g_vmap], r9
    mov     [abs g_vmap_size], rcx
    mov     [abs g_vmap_dsize], rdx

    ; Check every pointer converts before changing any, so a map that leaves
    ; one out fails cleanly instead of leaving the tables half moved.
    mov     rbx, EFI_RT + HDR_SIZE
    mov     ecx, (RT_SIZE - HDR_SIZE) / 8
.check:
    mov     rax, [rbx]
    call    rt_convert
    jc      .not_found
    add     rbx, 8
    dec     ecx
    jnz     .check
    mov     rax, EFI_RT
    call    rt_convert
    jc      .not_found

    mov     rbx, EFI_RT + HDR_SIZE
    mov     ecx, (RT_SIZE - HDR_SIZE) / 8
.entry:
    mov     rax, [rbx]
    call    rt_convert
    mov     [rbx], rax
    add     rbx, 8
    dec     ecx
    jnz     .entry

    mov     rbx, EFI_ST
    lea     rdi, [rbx + ST_RUNTIMESERVICES]
    call    rt_convert_at
    lea     rdi, [rbx + ST_CONFIGTABLE]
    call    rt_convert_at
    lea     rdi, [rbx + ST_FIRMWAREVENDOR]
    call    rt_convert_at
    mov     rdi, g_var_store
    call    rt_convert_at

    mov     rdi, EFI_RT
    call    efi_fix_crc
    mov     rdi, EFI_ST
    call    efi_fix_crc

    mov     dword [abs g_virtual], 1
    xor     eax, eax
    jmp     .done
.not_found:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    mov     qword [abs g_vmap], 0
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; rt_convert -- RAX = a physical address. Returns RAX = its virtual address
; under the map SetVirtualAddressMap was given, CF clear; or CF set and RAX
; unchanged if no runtime range in the map covers it. Zero stays zero.
; ----------------------------------------------------------------------------
rt_convert:
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    test    rax, rax
    jz      .hit_zero
    mov     rsi, [abs g_vmap]
    mov     rdi, rsi
    add     rdi, [abs g_vmap_size]
.next:
    cmp     rsi, rdi
    jae     .miss
    bt      qword [rsi + MD_ATTR], 63           ; EFI_MEMORY_RUNTIME
    jnc     .skip
    mov     rcx, [rsi + MD_PHYS]
    cmp     rax, rcx
    jb      .skip
    mov     rdx, [rsi + MD_PAGES]
    shl     rdx, 12
    add     rdx, rcx
    cmp     rax, rdx
    jae     .skip
    sub     rax, rcx
    add     rax, [rsi + MD_VIRT]
    clc
    jmp     .done
.skip:
    add     rsi, [abs g_vmap_dsize]
    jmp     .next
.miss:
    stc
    jmp     .done
.hit_zero:
    clc
.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; rt_convert_at -- RDI = where a pointer is kept. Converts it in place; one
; that no runtime range covers is left as it was.
; ----------------------------------------------------------------------------
rt_convert_at:
    push    rax
    mov     rax, [rdi]
    call    rt_convert
    jc      .keep
    mov     [rdi], rax
.keep:
    pop     rax
    ret

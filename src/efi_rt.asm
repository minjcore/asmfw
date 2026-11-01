; ============================================================================
; efi_rt.asm -- runtime services
;
; These are the services that outlive ExitBootServices. This firmware keeps
; them honest but small: a real clock, no variable store, and a reset that
; actually resets.
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
; GetVariable / GetNextVariableName
;
; There is no non-volatile store behind this firmware: the flash it runs from
; is read-only to it, and no variable region has been carved out. Reporting
; "not found" is the honest answer, and callers treat it as an empty store.
; ----------------------------------------------------------------------------
rt_get_variable:
    mov     rax, EFI_NOT_FOUND
    ret

rt_get_next_variable_name:
    mov     rax, EFI_NOT_FOUND
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

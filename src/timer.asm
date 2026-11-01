; ============================================================================
; timer.asm -- delays, measured against the 8254
;
; The PIT is the one clock on a PC that runs at a known rate without being
; configured first: 1.193182 MHz, derived from the ancient NTSC colourburst
; divisor. Channel 2 is used because it is the only one whose output can be
; polled directly, through bit 5 of port 0x61, without an interrupt.
; ============================================================================

bits 64

PIT_CH2         equ 0x42
PIT_CMD         equ 0x43
PIT_GATE        equ 0x61           ; bit 0 gates channel 2, bit 5 reads OUT2

PIT_HZ          equ 1193182
PIT_MAX_TICKS   equ 60000          ; ~50 ms, comfortably inside a 16-bit count

; ----------------------------------------------------------------------------
; stall_us -- busy-wait RCX microseconds
; ----------------------------------------------------------------------------
stall_us:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    r8

    test    rcx, rcx
    jz      .done

    ; ticks = us * 1193182 / 1000000, in 64-bit so a long stall does not
    ; overflow on the way in.
    mov     rax, rcx
    mov     rbx, PIT_HZ
    mul     rbx
    mov     rbx, 1000000
    div     rbx
    mov     r8, rax                             ; ticks still to wait
    test    r8, r8
    jz      .done

.chunk:
    mov     rbx, r8
    cmp     rbx, PIT_MAX_TICKS
    jbe     .have
    mov     rbx, PIT_MAX_TICKS
.have:
    sub     r8, rbx
    call    pit_wait_ticks
    test    r8, r8
    jnz     .chunk

.done:
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; pit_wait_ticks -- BX = tick count (1..65535), wait for channel 2 to run out
; ----------------------------------------------------------------------------
pit_wait_ticks:
    push    rax
    push    rcx
    push    rdx

    ; Gate low first: mode 0 starts counting on the rising edge of the gate,
    ; so the count has to be loaded while it is held low.
    mov     dx, PIT_GATE
    in      al, dx
    and     al, 0xFC                            ; gate off, speaker off
    out     dx, al

    mov     dx, PIT_CMD
    mov     al, 0xB0                            ; channel 2, lo/hi byte, mode 0
    out     dx, al

    mov     dx, PIT_CH2
    mov     ax, bx
    out     dx, al                              ; low byte
    mov     al, ah
    out     dx, al                              ; high byte

    mov     dx, PIT_GATE
    in      al, dx
    and     al, 0xFC
    or      al, 0x01                            ; rising edge starts the count
    out     dx, al

    ; OUT2 goes high when the count reaches zero.
    mov     rcx, 0x40000000                     ; bail out rather than hang
.spin:
    in      al, dx
    test    al, 0x20
    jnz     .done
    dec     rcx
    jnz     .spin
.done:
    in      al, dx
    and     al, 0xFC                            ; leave the gate as we found it
    out     dx, al

    pop     rdx
    pop     rcx
    pop     rax
    ret

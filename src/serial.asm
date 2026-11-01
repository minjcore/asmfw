; ============================================================================
; serial.asm -- 16550 UART on COM1, the firmware's debug spine
;
; Serial comes up before anything else so that a failure in PCI enumeration
; or mode setting still has somewhere to complain to.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; ser_init -- 115200 8N1, FIFOs on, interrupts off
; ----------------------------------------------------------------------------
ser_init:
    mov     dx, COM1 + 1
    xor     al, al
    out     dx, al                          ; IER: no interrupts

    mov     dx, COM1 + 3
    mov     al, 0x80
    out     dx, al                          ; LCR: DLAB on

    mov     dx, COM1 + 0
    mov     al, 1                           ; divisor 1 -> 115200 baud
    out     dx, al
    mov     dx, COM1 + 1
    xor     al, al
    out     dx, al

    mov     dx, COM1 + 3
    mov     al, 0x03                        ; 8 data bits, no parity, 1 stop
    out     dx, al

    mov     dx, COM1 + 2
    mov     al, 0xC7                        ; enable FIFO, clear, 14-byte trigger
    out     dx, al

    mov     dx, COM1 + 4
    mov     al, 0x0B                        ; DTR | RTS | OUT2
    out     dx, al
    ret

; ----------------------------------------------------------------------------
; ser_putc -- write AL, blocking until the transmit holding register is free
; ----------------------------------------------------------------------------
ser_putc:
    push    rax
    push    rdx
    mov     ah, al
.wait:
    mov     dx, COM1 + 5
    in      al, dx
    test    al, 0x20                        ; LSR.THRE
    jz      .wait
    mov     dx, COM1
    mov     al, ah
    out     dx, al
    pop     rdx
    pop     rax
    ret

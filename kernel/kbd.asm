; ============================================================================
; kbd.asm -- the keyboard, on an interrupt
;
; The firmware has an i8042 driver of its own, in efi_proto.asm, and this is
; not a copy of it for the same reason kata.asm is not a copy of ata.asm:
; ExitBootServices is the moment ConIn stops existing. But these two are not
; even the same design, which makes the duplication easier to defend than the
; disk stack's. The firmware polls, and a poller only ever sees the state of
; the controller at the instant it looks, so it throws every break code away
; and therefore cannot know whether shift is still down. This one is entered
; on IRQ1 and sees every transition, which is what the second table below is
; made of.
;
; The interrupt is the producer and sys_read is the consumer, and they share a
; ring buffer and nothing else. Neither needs a lock: an interrupt gate clears
; IF, so the producer cannot be interrupted by anything, and the consumer
; drains with interrupts off. That is affordable here for a reason that does
; not generalise -- the drain is bounded by KBD_BUF_SIZE, where the console
; write that made masking unaffordable was bounded by nothing.
; ============================================================================

bits 64

; ----------------------------------------------------------------------------
; kbd_init -- turn translation on, take whatever was left in the buffer, and
; only then let IRQ1 through.
;
; The order is the whole of it. Translation first, because the codes are the
; wrong ones until it is on. Draining second, because the controller asserts
; its interrupt when a byte arrives and not while one is waiting, so a byte
; already in the output buffer -- including the reply to the command below --
; would be delivered to nobody and would hold up every byte behind it. IRQ1
; last, because until this point there is no handler that would know what to
; do with one.
;
; The bit that has to be set was the second reset-clear bit in this project to
; cost a working device: the first was the attribute controller's
; palette-address-source, which gates the display no matter how correct the
; VBE mode is. A set 1 table reading set 2 codes is worse than a blank screen,
; because it produces plausible characters instead of nothing.
; ----------------------------------------------------------------------------
kbd_init:
    push    rax
    push    rcx
    push    rdx

    call    kbd_wait_write
    mov     al, KBD_CMD_READ_MODE
    mov     dx, KBD_STATUS
    out     dx, al

    call    kbd_wait_read
    test    eax, eax
    jz      .no_controller
    mov     dx, KBD_DATA
    in      al, dx
    mov     [rel g_kbd_mode_in], al

    ; Read, modify, write. A byte written from scratch would be a guess about
    ; the mouse, the clock and the self-test, so the three bits that are this
    ; code's business are the only three touched.
    ;
    ; The third of them has never been found set here: neither asmfw nor OVMF
    ; hands over a disabled keyboard interface. It is cleared anyway, because
    ; the kernel's business is to state the state it needs rather than to
    ; inherit whatever the last program to touch the controller preferred --
    ; and one AND is a cheaper way to know that than a diagnostic would be.
    or      al, KBD_MODE_XLAT | KBD_MODE_KBD_INT
    and     al, KBD_MODE_KBD_ON
    mov     cl, al
    mov     [rel g_kbd_mode_out], cl

    call    kbd_wait_write
    mov     al, KBD_CMD_WRITE_MODE
    mov     dx, KBD_STATUS
    out     dx, al

    call    kbd_wait_write
    mov     al, cl
    mov     dx, KBD_DATA
    out     dx, al

.no_controller:
    mov     ecx, KBD_DRAIN_MAX
.drain:
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF
    jz      .drained
    mov     dx, KBD_DATA
    in      al, dx
    dec     ecx
    jnz     .drain
.drained:

    mov     dx, PIC1_DATA
    in      al, dx
    and     al, PIC_IRQ1_ALLOW
    out     dx, al

    pop     rdx
    pop     rcx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kbd_wait_write -- wait for the input buffer to be empty, because writing to
; a full one loses the write.
;
; Both of these spin, and both give up. This runs once, before there is a task
; to schedule or a tick to wait for, so there is nothing else to do with the
; time -- but a controller that never clears its status must not be able to
; stop the machine booting over a keyboard.
; ----------------------------------------------------------------------------
kbd_wait_write:
    push    rcx
    push    rdx
    mov     ecx, KBD_WAIT_SPIN
.spin:
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_IBF
    jz      .clear
    dec     ecx
    jnz     .spin
.clear:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; kbd_wait_read -- wait for a byte to answer. EAX = 1 if one did.
; ----------------------------------------------------------------------------
kbd_wait_read:
    push    rcx
    push    rdx
    mov     ecx, KBD_WAIT_SPIN
.spin:
    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF
    jnz     .ready
    dec     ecx
    jnz     .spin
    xor     eax, eax
    jmp     .done
.ready:
    mov     eax, 1
.done:
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; isr_kbd -- vector 0x21, reached from the dispatch in isr_common.
;
; No context switch. A task woken here becomes runnable and waits for the tick
; to pick it up, which is at most one tick away and cannot be perceived by
; whoever is doing the typing. The timer switches because its whole job is to
; take the CPU away from somebody; this interrupt has no such mandate, and
; borrowing one would mean a keystroke could preempt a task that never asked
; the keyboard for anything.
; ----------------------------------------------------------------------------
isr_kbd:
    call    kbd_take

    mov     al, PIC_EOI
    mov     dx, PIC1_CMD
    out     dx, al

    call    kbd_wake_waiters

    POP_GPRS
    add     rsp, 16                         ; the vector and error code
    iretq

; ----------------------------------------------------------------------------
; kbd_take -- one byte from the controller, translated and queued if it turns
; out to name a character.
;
; The order of the tests is not free: the extended prefix has bit 7 set, so it
; has to be recognised before the test that discards releases, or every
; extended key would be read as one.
; ----------------------------------------------------------------------------
kbd_take:
    push    rax
    push    rbx
    push    rdx
    push    rsi

    mov     dx, KBD_STATUS
    in      al, dx
    test    al, KBD_STATUS_OBF
    jz      .done                           ; nothing there: a spurious IRQ1

    mov     dx, KBD_DATA
    in      al, dx

    cmp     al, KBD_PREFIX_EXT
    jne     .not_prefix
    mov     byte [rel g_kbd_ext], 1
    jmp     .done
.not_prefix:
    ; The byte after a prefix is an extended key -- an arrow, or one of the
    ; duplicated keys on the right of the board. None of them names a
    ; character, and this ABI carries bytes, so the code is consumed and
    ; dropped rather than invented a byte for.
    cmp     byte [rel g_kbd_ext], 0
    je      .not_extended
    mov     byte [rel g_kbd_ext], 0
    jmp     .done

.not_extended:
    ; Shift, both of it, both ways round. This is the part a poller cannot do.
    mov     bl, al
    and     bl, KBD_CODE_MASK
    cmp     bl, KBD_LSHIFT
    je      .shift
    cmp     bl, KBD_RSHIFT
    je      .shift

    test    al, KBD_BREAK
    jnz     .done                           ; some other key, released

    cmp     al, KBD_TABLE_LEN
    jae     .done
    movzx   ebx, al
    lea     rsi, [rel kbd_lower]
    cmp     byte [rel g_kbd_shift], 0
    je      .have_table
    lea     rsi, [rel kbd_upper]
.have_table:
    mov     al, [rsi + rbx]
    test    al, al
    jz      .done                           ; a modifier, or a key with no byte
    call    kbd_enqueue
    jmp     .done

.shift:
    ; Held is the make code without bit 7; released is with it. Recording the
    ; state rather than counting the two shifts means both being down and one
    ; of them coming up reads as shift no longer held, which is what the board
    ; is actually telling us.
    test    al, KBD_BREAK
    setz    byte [rel g_kbd_shift]

.done:
    pop     rsi
    pop     rdx
    pop     rbx
    pop     rax
    ret

; ----------------------------------------------------------------------------
; kbd_enqueue -- AL = a character.
;
; A full buffer drops the new byte rather than the oldest. Nobody typing has
; ever meant the last thirty-two characters and not the first, and dropping
; the oldest would corrupt a line that was already half read.
; ----------------------------------------------------------------------------
kbd_enqueue:
    push    rbx
    push    rcx
    push    rdx

    mov     rbx, [rel g_kbd_head]
    mov     rcx, rbx
    inc     rcx
    and     rcx, KBD_BUF_MASK
    cmp     rcx, [rel g_kbd_tail]
    je      .full

    lea     rdx, [rel kbd_buf]
    mov     [rdx + rbx], al
    mov     [rel g_kbd_head], rcx
.full:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; kbd_dequeue -- RDI = where to put them, RSI = how many at most.
; Returns RAX = how many there were, which may be zero.
;
; The caller has already established that RDI names memory the current task is
; allowed to be given, and this does not re-establish it. It must be called
; with interrupts off: the head moves in an interrupt.
; ----------------------------------------------------------------------------
kbd_dequeue:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    xor     eax, eax
    mov     rbx, [rel g_kbd_tail]
    lea     rdx, [rel kbd_buf]
.next:
    cmp     rax, rsi
    jae     .done
    cmp     rbx, [rel g_kbd_head]
    je      .done                           ; empty
    mov     cl, [rdx + rbx]
    mov     [rdi], cl
    inc     rdi
    inc     rbx
    and     rbx, KBD_BUF_MASK
    inc     rax
    jmp     .next
.done:
    mov     [rel g_kbd_tail], rbx
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; Scan code set 1, unshifted and shifted, as far as the space bar. A zero
; means the key has no byte to contribute: a modifier, or one this table does
; not bother with.
;
; Escape is 27 in both, unlike the firmware's table, which reports it as a
; scan code with no character because EFI_INPUT_KEY has somewhere to put one.
; This ABI carries bytes, and 27 is the byte that key has meant for fifty
; years.
; ----------------------------------------------------------------------------
kbd_lower:
    db 0,   27,  '1', '2', '3', '4', '5', '6'   ; 0x00
    db '7', '8', '9', '0', '-', '=', 8,   9     ; 0x08
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'   ; 0x10
    db 'o', 'p', '[', ']', 13,  0,   'a', 's'   ; 0x18
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';'   ; 0x20
    db 39,  '`', 0,   92,  'z', 'x', 'c', 'v'   ; 0x28
    db 'b', 'n', 'm', ',', '.', '/', 0,   '*'   ; 0x30
    db 0,   ' '                                 ; 0x38

kbd_upper:
    db 0,   27,  '!', '@', '#', '$', '%', '^'   ; 0x00
    db '&', '*', '(', ')', '_', '+', 8,   9     ; 0x08
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I'   ; 0x10
    db 'O', 'P', '{', '}', 13,  0,   'A', 'S'   ; 0x18
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':'   ; 0x20
    db '"', '~', 0,   '|', 'Z', 'X', 'C', 'V'   ; 0x28
    db 'B', 'N', 'M', '<', '>', '?', 0,   '*'   ; 0x30
    db 0,   ' '                                 ; 0x38

; ----------------------------------------------------------------------------
align 8
g_kbd_head:     dq 0
g_kbd_tail:     dq 0
g_kbd_ext:      db 0
g_kbd_shift:    db 0
g_kbd_mode_in:  db 0
g_kbd_mode_out: db 0

align 8
kbd_buf:        times KBD_BUF_SIZE db 0

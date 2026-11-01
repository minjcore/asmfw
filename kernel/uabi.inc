; ============================================================================
; uabi.inc -- the contract between the kernel and a program
;
; Included by both sides. It is the only thing they are allowed to agree on:
; a program is a flat binary loaded at the base of its window with nothing
; resolved for it, so everything else it knows it has to be told at entry.
;
;   entry     RDI = task id, RSI = its window, RDX = its neighbour's window
;   call      number in EAX, arguments in RDI, RSI, RDX, result in RAX
;   clobbers  RCX and R11, which SYSCALL takes, and R10, which the kernel uses
;             to find itself before it has a stack
; ============================================================================

SYS_WRITE       equ 0
SYS_EXIT        equ 1
SYS_TICKS       equ 2                       ; the time stamp counter
SYS_YIELD       equ 3                       ; give up the rest of the slice
SYS_SLEEP       equ 4                       ; RDI = milliseconds
SYS_UPTIME      equ 5                       ; timer ticks since boot

; RDI = buffer, RSI = length, RDX = how long to wait in milliseconds, where 0
; means for as long as it takes. Returns however many bytes were there, which
; is at least one unless the wait ran out, and never more than were typed: a
; read is not a promise to fill the buffer.
SYS_READ        equ 6

SYS_COUNT       equ 7

SYS_EBADPTR     equ -1                      ; the buffer left the user window
SYS_ENOSYS      equ -2                      ; no such call

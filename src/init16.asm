; ============================================================================
; init16.asm -- SEC phase, part 1
;
; Everything here must sit in the last 64 KiB of the flash volume, because at
; reset the only thing addressable is CS.base = 0xFFFF0000 with a 64 KiB limit.
; The job is deliberately tiny: turn on A20, load a flat GDT, switch to
; 32-bit protected mode, and get out of real mode forever.
; ============================================================================

bits 16

sec_entry16:
    cli
    cld

    ; Invalidate anything the CPU may have brought in with an unknown MTRR
    ; state, then start from a known CR0: cache enabled, no paging, no task
    ; switch pending.
    mov     eax, cr0
    and     eax, 0x7FFFFFF1                 ; clear PG, CD, NW, TS/EM/MP
    or      eax, 0x00000002                 ; MP=1
    mov     cr0, eax

    ; --- A20 -------------------------------------------------------------
    ; Fast A20 via the PS/2 system control port. Bit 0 is the CPU reset
    ; line, so mask it off before writing anything back.
    in      al, 0x92
    test    al, 0x02
    jnz     .a20_done
    or      al, 0x02
    and     al, 0xFE
    out     0x92, al
.a20_done:

    ; --- protected mode --------------------------------------------------
    ; The pointer is addressed through BX rather than a literal displacement:
    ; this stub sits high in the segment, and a disp16 that large is outside
    ; the signed range the assembler will encode without complaint.
    ; o32 so the full 32-bit GDT base is loaded, not the real-mode 24-bit form.
    mov     bx, rm(gdt32_ptr)
    o32 lgdt [cs:bx]

    mov     eax, cr0
    or      eax, 1                          ; PE
    mov     cr0, eax

    ; Far jump reloads CS with a 4 GiB flat descriptor and lands in 32-bit
    ; code anywhere in the volume.
    jmp     dword SEL_C32:sec_entry32

; ----------------------------------------------------------------------------
; The GDT. Shared by protected mode and long mode -- the 64-bit descriptors
; simply set L=1 and let the CPU ignore base/limit.
; ----------------------------------------------------------------------------
align 8
gdt32:
    dq 0x0000000000000000                   ; 0x00 null
    dq 0x00CF9A000000FFFF                   ; 0x08 code32  base 0, 4 GiB, D=1
    dq 0x00CF92000000FFFF                   ; 0x10 data32  base 0, 4 GiB
    dq 0x00AF9A000000FFFF                   ; 0x18 code64  L=1
    dq 0x00CF92000000FFFF                   ; 0x20 data64
gdt32_end:

gdt32_ptr:
    dw gdt32_end - gdt32 - 1
    dd gdt32

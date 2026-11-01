; ============================================================================
; fw.asm -- the flash volume
;
; One flat binary, assembled at its final address. The layout is fixed by the
; architecture at both ends:
;
;   0xFFF00000  start of the volume        <- 32/64-bit firmware body
;   0xFFFF0000  last 64 KiB                <- everything real mode can reach
;   0xFFFFFFF0  reset vector               <- 16 bytes, where the CPU starts
;
; Build with:  nasm -f bin -I src/ -o build/FIRMWARE.fd src/fw.asm
; ============================================================================

%include "const.inc"
%include "efi.inc"
%include "macros.inc"

            bits 64
            default rel                     ; keep 64-bit references RIP-relative;
                                            ; an absolute disp32 would sign-extend
            org FV_BASE

; ----------------------------------------------------------------------------
; Firmware body. Order is not architecturally significant here; only the two
; anchors below are.
;
; If the body ever outgrows its window, the first `times` below goes negative
; and NASM stops with "TIMES value is negative" -- that means the code no
; longer fits underneath 0xFFFF0000, not that the padding is wrong.
; ----------------------------------------------------------------------------
%include "init32.asm"
%include "init64.asm"
%include "serial.asm"
%include "util.asm"
%include "timer.asm"
%include "pci.asm"
%include "vbe.asm"
%include "console.asm"
%include "mem.asm"
%include "ata.asm"
%include "gpt.asm"
%include "fat.asm"
%include "pe.asm"
%include "acpi.asm"
%include "smbios.asm"
%include "efi_tables.asm"
%include "efi_bs.asm"
%include "efi_rt.asm"
%include "efi_var.asm"
%include "efi_proto.asm"
%include "efi_file.asm"

; ----------------------------------------------------------------------------
; Real-mode anchor: the last 64 KiB of the volume.
; ----------------------------------------------------------------------------
            times (RM_BASE - FV_BASE) - ($ - $$) db 0xFF

%include "init16.asm"

; ----------------------------------------------------------------------------
; Reset vector: 16 bytes at 0xFFFFFFF0.
;
; The jump must be near. A far jump would reload CS and destroy the hidden
; 0xFFFF0000 base the CPU starts with, which is the only thing making this
; code addressable at all.
; ----------------------------------------------------------------------------
            times (FV_SIZE - 16) - ($ - $$) db 0xFF
            bits 16
reset_vector:
            jmp     strict near sec_entry16
            times (FV_SIZE - ($ - $$)) db 0xFF

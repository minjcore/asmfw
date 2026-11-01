; ============================================================================
; const.inc -- build-wide constants and the firmware's physical memory map
; ============================================================================

; ---------------------------------------------------------------------------
; Flash volume
;
; QEMU's -bios maps the image so that its last byte sits at 0xFFFFFFFF, which
; puts the reset vector (0xFFFFFFF0) 16 bytes from the end of the file.
; ---------------------------------------------------------------------------
FV_SIZE         equ 0x00100000                  ; 1 MiB
FV_BASE         equ 0x100000000 - FV_SIZE       ; 0xFFF00000

; At reset CS.base is 0xFFFF0000, so only the last 64 KiB of the volume is
; reachable in real mode. rm() turns a linear label into a CS-relative offset.
RM_BASE         equ 0xFFFF0000
%define rm(x)   ((x) - RM_BASE)

; ---------------------------------------------------------------------------
; Segment selectors (one GDT serves 32-bit and 64-bit mode)
; ---------------------------------------------------------------------------
SEL_NULL        equ 0x00
SEL_C32         equ 0x08
SEL_D32         equ 0x10
SEL_C64         equ 0x18
SEL_D64         equ 0x20

; ---------------------------------------------------------------------------
; Physical memory layout used by the firmware itself
;
;   0x00070000  PML4
;   0x00071000  PDPT
;   0x00072000  PD[0..3]        identity map of the low 4 GiB, 2 MiB pages
;   0x00100000  firmware globals (G_*)
;   0x00200000  firmware stack   (grows down from FW_STACK_TOP)
;   0x00300000  EFI tables, protocol instances, memory-map scratch
;   0x01000000  page/pool heap handed out by AllocatePages / AllocatePool
; ---------------------------------------------------------------------------
PT_PML4         equ 0x00070000
PT_PDPT         equ 0x00071000
PT_PD0          equ 0x00072000
PT_PAGES        equ 6                           ; PML4 + PDPT + 4 PDs

G_BASE          equ 0x00100000                  ; 1 MiB of globals
FW_STACK_TOP    equ 0x00300000
FW_TABLES       equ 0x00300000                  ; 1 MiB of EFI structures
FW_TABLES_END   equ 0x00400000
FW_HEAP_BASE    equ 0x01000000                  ; 16 MiB
FW_HEAP_MIN     equ 0x04000000                  ; require >= 64 MiB of RAM

; Fixed scratch buffers, all inside the FW_TABLES region.
BUF_SECTOR      equ 0x00380000                  ; one sector, general purpose
BUF_IDENTIFY    equ 0x00380200                  ; ATA IDENTIFY result
BUF_GPT_HDR     equ 0x00380400                  ; GPT header
BUF_GPT_ENT     equ 0x00381000                  ; GPT partition array, 16 KiB
BUF_FAT         equ 0x00385000                  ; one FAT sector
BUF_DIR         equ 0x00386000                  ; one directory cluster, max 64 KiB
BUF_FILE        equ 0x00396000                  ; one file cluster, for File->Read
BUF_NAME83      equ 0x003A6000                  ; one 8.3 name being assembled
BUF_NAME16      equ 0x003A6020                  ; one name being spelled out as CHAR16
BUF_FWCFG_DIR   equ 0x003B0000                  ; the fw_cfg file directory, 16 KiB
BUF_ACPI_LOADER equ 0x003B4000                  ; etc/table-loader, as downloaded
ACPI_BLOB_TABLE equ 0x003C4000                  ; where each ACPI blob was placed

ACPI_LOADER_MAX equ 0x00010000                  ; what BUF_ACPI_LOADER holds

; Uncached above this line: the PCI hole (and the flash itself) lives there.
MMIO_BELOW_4G   equ 0xC0000000

; ---------------------------------------------------------------------------
; Serial debug port
; ---------------------------------------------------------------------------
COM1            equ 0x3F8

; ---------------------------------------------------------------------------
; Global variable allocator.
;
; The firmware runs from ROM, so every mutable byte lives in RAM at G_BASE.
; GVAR carves that region up at assembly time.
; ---------------------------------------------------------------------------
%assign GOFF 0
%macro GVAR 2                                   ; %1 = name, %2 = size in bytes
    %1 equ G_BASE + GOFF
    %assign GOFF GOFF + %2
%endmacro

GVAR g_fb_base,     8       ; linear framebuffer physical address
GVAR g_fb_size,     8       ; framebuffer size in bytes
GVAR g_fb_w,        4       ; horizontal resolution
GVAR g_fb_h,        4       ; vertical resolution
GVAR g_fb_pitch,    4       ; bytes per scanline
GVAR g_fb_ok,       4       ; non-zero once a mode is set

GVAR g_con_x,       4       ; cursor column, in glyphs
GVAR g_con_y,       4       ; cursor row, in glyphs
GVAR g_con_cols,    4
GVAR g_con_rows,    4
GVAR g_con_fg,      4       ; 0x00RRGGBB
GVAR g_con_bg,      4
GVAR g_con_attr,    4       ; EFI text attribute, for SetAttribute

GVAR g_ram_top,     8       ; highest usable byte below 4 GiB
GVAR g_heap_next,   8       ; bump pointer for AllocatePages
GVAR g_heap_end,    8

GVAR g_vga_bdf,     4       ; PCI bus/dev/fn of the display, -1 if none
GVAR g_vbe_id,      4       ; Bochs VBE revision, for diagnostics

GVAR g_ata_present, 4       ; primary master responded to IDENTIFY
GVAR g_ata_sectors, 8       ; its LBA28 capacity

GVAR g_esp_lba,     8       ; first LBA of the EFI system partition
GVAR g_esp_sectors, 8       ; its length

GVAR g_fat_part_lba,  8     ; where the FAT32 volume starts on the disk
GVAR g_fat_fat_lba,   8     ; first sector of the first FAT
GVAR g_fat_data_lba,  8     ; sector holding cluster 2
GVAR g_fat_root_clus, 4     ; first cluster of the root directory
GVAR g_fat_spc,       4     ; sectors per cluster
GVAR g_fat_cached,    8     ; LBA currently in BUF_FAT, -1 when empty

GVAR g_img_base,      8     ; where the loaded image was placed
GVAR g_img_pages,     8     ; how many 4 KiB pages it occupies
GVAR g_img_entry,     8     ; its entry point

GVAR g_fwcfg_files,   4     ; file records cached in BUF_FWCFG_DIR
GVAR g_acpi_blobs,    4     ; records in ACPI_BLOB_TABLE
GVAR g_acpi_rsdp,     8     ; the RSDP's physical address, 0 if there is none
GVAR g_acpi_tables,   4     ; how many SDTs the root table lists

GVAR g_alloc_count,   4     ; records in ALLOC_TABLE
GVAR g_map_key,       4     ; bumped whenever the memory map changes
GVAR g_proto_count,   4     ; records in PROTO_DB
GVAR g_cfg_count,     4     ; entries in the configuration table
GVAR g_tpl,           8     ; current task priority level
GVAR g_mono_count,    8     ; the monotonic counter
GVAR g_bs_exited,     4     ; set once ExitBootServices has been called
GVAR g_var_store,     8     ; the variable records, runtime services data
GVAR g_exit_rsp,      8     ; stack to unwind to when the image calls Exit
GVAR g_current_image, 8     ; the handle of the image running now
GVAR g_rt_shadow,     8     ; the flash volume's copy in runtime code, or 0
GVAR g_boot_dir,      4     ; first cluster of \EFI\BOOT
GVAR g_cmdline,       8     ; the image's load options, CHAR16, or 0
GVAR g_cmdline_size,  4     ; their size in bytes, NUL included
GVAR g_exit_status,   8     ; the status it exited with

GOFF_TOTAL equ GOFF

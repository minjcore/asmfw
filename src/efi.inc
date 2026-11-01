; ============================================================================
; efi.inc -- the UEFI ABI as this firmware implements it
;
; Structure offsets are written out as constants rather than built with a
; struct macro: these numbers are fixed by the specification, and having them
; visible is what lets them be checked against it.
; ============================================================================

; ---------------------------------------------------------------------------
; Status codes. The high bit marks an error; the rest is a small ordinal.
; ---------------------------------------------------------------------------
EFI_SUCCESS             equ 0
EFI_LOAD_ERROR          equ 0x8000000000000001
EFI_INVALID_PARAMETER   equ 0x8000000000000002
EFI_UNSUPPORTED         equ 0x8000000000000003
EFI_BAD_BUFFER_SIZE     equ 0x8000000000000004
EFI_BUFFER_TOO_SMALL    equ 0x8000000000000005
EFI_NOT_READY           equ 0x8000000000000006
EFI_DEVICE_ERROR        equ 0x8000000000000007
EFI_WRITE_PROTECTED     equ 0x8000000000000008
EFI_OUT_OF_RESOURCES    equ 0x8000000000000009
EFI_MEDIA_CHANGED       equ 0x800000000000000D
EFI_NOT_FOUND           equ 0x800000000000000E
EFI_ABORTED             equ 0x8000000000000015
EFI_TIMEOUT             equ 0x8000000000000012

; ---------------------------------------------------------------------------
; Table header, common to the system, boot services and runtime tables
; ---------------------------------------------------------------------------
TH_SIGNATURE            equ 0x00
TH_REVISION             equ 0x08
TH_HEADERSIZE           equ 0x0C
TH_CRC32                equ 0x10
TH_RESERVED             equ 0x14
TH_SIZE                 equ 0x18

SIG_SYSTEM_TABLE        equ 0x5453595320494249       ; "IBI SYST"
SIG_BOOT_SERVICES       equ 0x56524553544F4F42       ; "BOOTSERV"
SIG_RUNTIME_SERVICES    equ 0x56524553544E5552       ; "RUNTSERV"
HDR_SIZE                equ 0x18                     ; EFI_TABLE_HEADER

EFI_2_70_REVISION       equ (2 << 16) | 70
EFI_SPEC_REVISION       equ EFI_2_70_REVISION
FIRMWARE_REVISION       equ 0x00010000

; ---------------------------------------------------------------------------
; EFI_SYSTEM_TABLE
; ---------------------------------------------------------------------------
ST_FIRMWAREVENDOR       equ 0x18
ST_FIRMWAREREVISION     equ 0x20
ST_CONSOLEINHANDLE      equ 0x28
ST_CONIN                equ 0x30
ST_CONSOLEOUTHANDLE     equ 0x38
ST_CONOUT               equ 0x40
ST_STDERRHANDLE         equ 0x48
ST_STDERR               equ 0x50
ST_RUNTIMESERVICES      equ 0x58
ST_BOOTSERVICES         equ 0x60
ST_NUMTABLEENTRIES      equ 0x68
ST_CONFIGTABLE          equ 0x70
ST_SIZE                 equ 0x78

; ---------------------------------------------------------------------------
; EFI_BOOT_SERVICES
; ---------------------------------------------------------------------------
BS_RAISETPL                     equ 0x018
BS_RESTORETPL                   equ 0x020
BS_ALLOCATEPAGES                equ 0x028
BS_FREEPAGES                    equ 0x030
BS_GETMEMORYMAP                 equ 0x038
BS_ALLOCATEPOOL                 equ 0x040
BS_FREEPOOL                     equ 0x048
BS_CREATEEVENT                  equ 0x050
BS_SETTIMER                     equ 0x058
BS_WAITFOREVENT                 equ 0x060
BS_SIGNALEVENT                  equ 0x068
BS_CLOSEEVENT                   equ 0x070
BS_CHECKEVENT                   equ 0x078
BS_INSTALLPROTOCOLINTERFACE     equ 0x080
BS_REINSTALLPROTOCOLINTERFACE   equ 0x088
BS_UNINSTALLPROTOCOLINTERFACE   equ 0x090
BS_HANDLEPROTOCOL               equ 0x098
BS_RESERVED                     equ 0x0A0
BS_REGISTERPROTOCOLNOTIFY       equ 0x0A8
BS_LOCATEHANDLE                 equ 0x0B0
BS_LOCATEDEVICEPATH             equ 0x0B8
BS_INSTALLCONFIGURATIONTABLE    equ 0x0C0
BS_LOADIMAGE                    equ 0x0C8
BS_STARTIMAGE                   equ 0x0D0
BS_EXIT                         equ 0x0D8
BS_UNLOADIMAGE                  equ 0x0E0
BS_EXITBOOTSERVICES             equ 0x0E8
BS_GETNEXTMONOTONICCOUNT        equ 0x0F0
BS_STALL                        equ 0x0F8
BS_SETWATCHDOGTIMER             equ 0x100
BS_CONNECTCONTROLLER            equ 0x108
BS_DISCONNECTCONTROLLER         equ 0x110
BS_OPENPROTOCOL                 equ 0x118
BS_CLOSEPROTOCOL                equ 0x120
BS_OPENPROTOCOLINFORMATION      equ 0x128
BS_PROTOCOLSPERHANDLE           equ 0x130
BS_LOCATEHANDLEBUFFER           equ 0x138
BS_LOCATEPROTOCOL               equ 0x140
BS_INSTALLMULTIPLEPROTOCOL      equ 0x148
BS_UNINSTALLMULTIPLEPROTOCOL    equ 0x150
BS_CALCULATECRC32               equ 0x158
BS_COPYMEM                      equ 0x160
BS_SETMEM                       equ 0x168
BS_CREATEEVENTEX                equ 0x170
BS_SIZE                         equ 0x178

; ---------------------------------------------------------------------------
; EFI_RUNTIME_SERVICES
; ---------------------------------------------------------------------------
RT_GETTIME                      equ 0x18
RT_SETTIME                      equ 0x20
RT_GETWAKEUPTIME                equ 0x28
RT_SETWAKEUPTIME                equ 0x30
RT_SETVIRTUALADDRESSMAP         equ 0x38
RT_CONVERTPOINTER               equ 0x40
RT_GETVARIABLE                  equ 0x48
RT_GETNEXTVARIABLENAME          equ 0x50
RT_SETVARIABLE                  equ 0x58
RT_GETNEXTHIGHMONOCOUNT         equ 0x60
RT_RESETSYSTEM                  equ 0x68
RT_UPDATECAPSULE                equ 0x70
RT_QUERYCAPSULECAPABILITIES     equ 0x78
RT_QUERYVARIABLEINFO            equ 0x80
RT_SIZE                         equ 0x88

; ---------------------------------------------------------------------------
; EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
; ---------------------------------------------------------------------------
TO_RESET                equ 0x00
TO_OUTPUTSTRING         equ 0x08
TO_TESTSTRING           equ 0x10
TO_QUERYMODE            equ 0x18
TO_SETMODE              equ 0x20
TO_SETATTRIBUTE         equ 0x28
TO_CLEARSCREEN          equ 0x30
TO_SETCURSORPOSITION    equ 0x38
TO_ENABLECURSOR         equ 0x40
TO_MODE                 equ 0x48
TO_SIZE                 equ 0x50

; SIMPLE_TEXT_OUTPUT_MODE
TOM_MAXMODE             equ 0x00
TOM_MODE                equ 0x04
TOM_ATTRIBUTE           equ 0x08
TOM_CURSORCOLUMN        equ 0x0C
TOM_CURSORROW           equ 0x10
TOM_CURSORVISIBLE       equ 0x14
TOM_SIZE                equ 0x18

; ---------------------------------------------------------------------------
; EFI_SIMPLE_TEXT_INPUT_PROTOCOL
; ---------------------------------------------------------------------------
TI_RESET                equ 0x00
TI_READKEYSTROKE        equ 0x08
TI_WAITFORKEY           equ 0x10
TI_SIZE                 equ 0x18

; EFI_INPUT_KEY
KEY_SCANCODE            equ 0x00        ; UINT16
KEY_UNICODECHAR         equ 0x02        ; CHAR16
KEY_SIZE                equ 0x04

SCAN_NULL               equ 0x00
SCAN_UP                 equ 0x01
SCAN_DOWN               equ 0x02
SCAN_RIGHT              equ 0x03
SCAN_LEFT               equ 0x04
SCAN_ESC                equ 0x17

; ---------------------------------------------------------------------------
; EFI_GRAPHICS_OUTPUT_PROTOCOL
; ---------------------------------------------------------------------------
GOP_QUERYMODE           equ 0x00
GOP_SETMODE             equ 0x08
GOP_BLT                 equ 0x10
GOP_MODE                equ 0x18
GOP_SIZE                equ 0x20

GOPM_MAXMODE            equ 0x00        ; UINT32
GOPM_MODE               equ 0x04        ; UINT32
GOPM_INFO               equ 0x08        ; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *
GOPM_SIZEOFINFO         equ 0x10        ; UINTN
GOPM_FRAMEBUFFERBASE    equ 0x18
GOPM_FRAMEBUFFERSIZE    equ 0x20
GOPM_SIZE               equ 0x28

GOPI_VERSION            equ 0x00
GOPI_HRES               equ 0x04
GOPI_VRES               equ 0x08
GOPI_PIXELFORMAT        equ 0x0C
GOPI_PIXELINFO          equ 0x10        ; four UINT32 masks
GOPI_PPSL               equ 0x20
GOPI_SIZE               equ 0x24

; PixelBlueGreenRedReserved8BitPerColor -- the layout of a Bochs VBE
; 32 bpp framebuffer, where a little-endian dword reads 0x00RRGGBB.
PixelBlueGreenRedReserved8BitPerColor equ 1

; ---------------------------------------------------------------------------
; EFI_LOADED_IMAGE_PROTOCOL
; ---------------------------------------------------------------------------
LI_REVISION             equ 0x00
LI_PARENTHANDLE         equ 0x08
LI_SYSTEMTABLE          equ 0x10
LI_DEVICEHANDLE         equ 0x18
LI_FILEPATH             equ 0x20
LI_RESERVED             equ 0x28
LI_LOADOPTIONSSIZE      equ 0x30
LI_LOADOPTIONS          equ 0x38
LI_IMAGEBASE            equ 0x40
LI_IMAGESIZE            equ 0x48
LI_IMAGECODETYPE        equ 0x50
LI_IMAGEDATATYPE        equ 0x54
LI_UNLOAD               equ 0x58
LI_SIZE                 equ 0x60

LOADED_IMAGE_REVISION   equ 0x1000

; ---------------------------------------------------------------------------
; EFI_SIMPLE_FILE_SYSTEM_PROTOCOL
; ---------------------------------------------------------------------------
SFS_REVISION            equ 0x00
SFS_OPENVOLUME          equ 0x08
SFS_SIZE                equ 0x10

EFI_SIMPLE_FILE_SYSTEM_REVISION equ 0x00010000

; ---------------------------------------------------------------------------
; EFI_FILE_PROTOCOL
;
; The public half is the eleven revision-1 members. Everything after it is
; this firmware's own bookkeeping, which the caller never sees: the object is
; handed out as a pointer to its first member, exactly as the spec describes.
; ---------------------------------------------------------------------------
F_REVISION              equ 0x00
F_OPEN                  equ 0x08
F_CLOSE                 equ 0x10
F_DELETE                equ 0x18
F_READ                  equ 0x20
F_WRITE                 equ 0x28
F_GETPOSITION           equ 0x30
F_SETPOSITION           equ 0x38
F_GETINFO               equ 0x40
F_SETINFO               equ 0x48
F_FLUSH                 equ 0x50
F_PUBLIC_SIZE           equ 0x58

F_CLUSTER               equ 0x58        ; UINT32, first cluster of the file
F_ATTR                  equ 0x5C        ; UINT32, the FAT attribute byte
F_SIZE                  equ 0x60        ; UINT64, length in bytes
F_POS                   equ 0x68        ; UINT64, byte offset, or entry index
                                        ; when this object is a directory
F_NAME                  equ 0x70        ; the 8.3 name, space padded
F_OBJECT_SIZE           equ 0x80

EFI_FILE_PROTOCOL_REVISION equ 0x00010000

EFI_FILE_MODE_READ      equ 0x0000000000000001
EFI_FILE_MODE_WRITE     equ 0x0000000000000002
EFI_FILE_MODE_CREATE    equ 0x8000000000000000

EFI_FILE_READ_ONLY      equ 0x01
EFI_FILE_HIDDEN         equ 0x02
EFI_FILE_SYSTEM         equ 0x04
EFI_FILE_DIRECTORY      equ 0x10
EFI_FILE_ARCHIVE        equ 0x20

; EFI_FILE_INFO
FI_SIZE                 equ 0x00        ; UINT64, of this whole structure
FI_FILESIZE             equ 0x08
FI_PHYSICALSIZE         equ 0x10
FI_CREATETIME           equ 0x18        ; EFI_TIME
FI_LASTACCESSTIME       equ 0x28
FI_MODIFICATIONTIME     equ 0x38
FI_ATTRIBUTE            equ 0x48
FI_FILENAME             equ 0x50        ; CHAR16[], NUL terminated
FI_HEADER_SIZE          equ 0x50

; ---------------------------------------------------------------------------
; EFI_BLOCK_IO_PROTOCOL
; ---------------------------------------------------------------------------
BIO_REVISION            equ 0x00
BIO_MEDIA               equ 0x08
BIO_RESET               equ 0x10
BIO_READBLOCKS          equ 0x18
BIO_WRITEBLOCKS         equ 0x20
BIO_FLUSHBLOCKS         equ 0x28
BIO_SIZE                equ 0x30

EFI_BLOCK_IO_PROTOCOL_REVISION equ 0x00010000

; EFI_BLOCK_IO_MEDIA
BIOM_MEDIAID            equ 0x00        ; UINT32
BIOM_REMOVABLE          equ 0x04        ; BOOLEAN
BIOM_PRESENT            equ 0x05
BIOM_LOGICALPARTITION   equ 0x06
BIOM_READONLY           equ 0x07
BIOM_WRITECACHING       equ 0x08
BIOM_BLOCKSIZE          equ 0x0C        ; UINT32
BIOM_IOALIGN            equ 0x10        ; UINT32
BIOM_LASTBLOCK          equ 0x18        ; EFI_LBA
BIOM_SIZE               equ 0x20

; ---------------------------------------------------------------------------
; Where the runtime structures live in RAM.
;
; They cannot live in the flash volume: InstallConfigurationTable writes to
; the system table, and the CRC fields have to be filled in at build-of-table
; time rather than at assembly time.
; ---------------------------------------------------------------------------
EFI_ST              equ FW_TABLES + 0x0000
EFI_BS              equ FW_TABLES + 0x0100
EFI_RT              equ FW_TABLES + 0x0300
EFI_CONOUT          equ FW_TABLES + 0x0400
EFI_CONOUT_MODE     equ FW_TABLES + 0x0460
EFI_CONIN           equ FW_TABLES + 0x0480
EFI_GOP             equ FW_TABLES + 0x0500
EFI_GOP_MODE        equ FW_TABLES + 0x0530
EFI_GOP_INFO        equ FW_TABLES + 0x0560
EFI_LOADED_IMG      equ FW_TABLES + 0x0600
EFI_CFG_TABLE       equ FW_TABLES + 0x0700      ; room for 16 entries
EFI_VENDOR_STR      equ FW_TABLES + 0x0800
EFI_WAITKEY_EVENT   equ FW_TABLES + 0x0880      ; an opaque, non-null token
EFI_SFS             equ FW_TABLES + 0x0A00
EFI_BLOCKIO         equ FW_TABLES + 0x0A40
EFI_BLOCKIO_MEDIA   equ FW_TABLES + 0x0A80
EFI_ROOT_FILE       equ FW_TABLES + 0x0B00      ; the root directory object
PROTO_DB            equ FW_TABLES + 0x1000      ; handle/GUID/interface records
IMAGE_TABLE         equ FW_TABLES + 0x2000      ; images started by LoadImage
ALLOC_TABLE         equ FW_TABLES + 0x8000
MEMMAP_SCRATCH      equ FW_TABLES + 0xC000

PROTO_REC_SIZE      equ 24                      ; handle, GUID pointer, interface
PROTO_MAX           equ 64

; Handles. A handle only has to be a unique non-null token, so each protocol
; instance stands in for its own handle.
H_CONOUT            equ EFI_CONOUT
H_CONIN             equ EFI_CONIN
H_GOP               equ EFI_GOP
H_IMAGE             equ EFI_LOADED_IMG
H_DISK              equ EFI_SFS                 ; carries both Block I/O and
                                                ; Simple File System, which is
                                                ; what makes it usable as
                                                ; LoadedImage->DeviceHandle

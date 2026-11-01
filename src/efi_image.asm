; ============================================================================
; efi_image.asm -- LoadImage, StartImage, UnloadImage, and where Exit returns
;
; An image loaded by another image. BDS starts the first one itself; these
; are how that one starts the next -- a boot manager starting a loader, a
; shim starting GRUB.
;
; Each loaded image gets a record in IMAGE_TABLE, and the record begins with
; its EFI_LOADED_IMAGE_PROTOCOL, so the record's address serves as the image
; handle, the same trick H_IMAGE plays for the image BDS starts.
;
; The difficult part is Exit(). An image may call it from any depth of its own
; stack, and it must come back out of the StartImage that started that image
; -- not the outermost one. So each record keeps the stack StartImage left,
; and the image that was current before it; Exit unwinds to the first and
; restores the second. Nesting is just a chain of records.
; ============================================================================

bits 64

IR_LI           equ 0x00                        ; EFI_LOADED_IMAGE_PROTOCOL
IR_ENTRY        equ LI_SIZE                     ; its entry point
IR_STATE        equ LI_SIZE + 0x08              ; UINT32, one of IMG_*
IR_EXIT_RSP     equ LI_SIZE + 0x10              ; what StartImage left, to unwind to
IR_PREV         equ LI_SIZE + 0x18              ; the image current before this one
IMG_REC_SIZE    equ 0x100
IMG_MAX         equ 8

IMG_FREE        equ 0
IMG_LOADED      equ 1
IMG_RUNNING     equ 2
IMG_DONE        equ 3

; The registers StartImage keeps for its caller. An image that leaves through
; Exit() never runs its own epilogue, so the callee-saved registers the
; Microsoft x64 ABI promises -- XMM6 to XMM15 among them -- are put back here.
IMG_XMM_BYTES   equ 10 * 16
IMG_SAVE_PAD    equ 8                           ; realigns after eight pushes

; ----------------------------------------------------------------------------
; image_record -- RCX = a handle. Returns RAX = its record if it is one of
; IMAGE_TABLE's and in use, otherwise 0.
; ----------------------------------------------------------------------------
image_record:
    mov     rax, rcx
    sub     rax, IMAGE_TABLE
    jb      .no
    cmp     rax, IMG_MAX * IMG_REC_SIZE
    jae     .no
    test    eax, IMG_REC_SIZE - 1
    jnz     .no
    mov     rax, rcx
    cmp     dword [rax + IR_STATE], IMG_FREE
    je      .no
    ret
.no:
    xor     eax, eax
    ret

; ----------------------------------------------------------------------------
; bs_load_image -- LoadImage(BootPolicy, ParentImageHandle, DevicePath,
; SourceBuffer, SourceSize, ImageHandle).
;
; Only from a buffer. Loading by device path alone would mean resolving the
; path to a file on a device, and this firmware has one device and loaders
; that read their own files; with no buffer the answer is EFI_NOT_FOUND, which
; is what the specification says when there is nothing to load.
; ----------------------------------------------------------------------------
bs_load_image:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, [rsp + 0x28 + 7*8]             ; SourceSize
    mov     r13, [rsp + 0x30 + 7*8]             ; ImageHandle, out
    mov     r14, rdx                            ; ParentImageHandle
    mov     r15, r8                             ; DevicePath

    test    r13, r13
    jz      .bad
    test    r14, r14
    jz      .bad
    test    r9, r9
    jz      .not_found
    test    r12, r12
    jz      .load_error

    ; A free record.
    mov     rbx, IMAGE_TABLE
    mov     ecx, IMG_MAX
.slot:
    cmp     dword [rbx + IR_STATE], IMG_FREE
    je      .have_slot
    add     rbx, IMG_REC_SIZE
    dec     ecx
    jnz     .slot
    mov     rax, EFI_OUT_OF_RESOURCES
    jmp     .done
.have_slot:

    mov     rsi, r9
    mov     rdx, r12
    call    pe_load
    test    eax, eax
    jnz     .load_error

    mov     dword [rbx + LI_REVISION], LOADED_IMAGE_REVISION
    mov     dword [rbx + LI_REVISION + 4], 0
    mov     [rbx + LI_PARENTHANDLE], r14
    mov     qword [rbx + LI_SYSTEMTABLE], EFI_ST
    ; A device path can only be naming the one device there is.
    xor     eax, eax
    test    r15, r15
    jz      .no_device
    mov     rax, H_DISK
.no_device:
    mov     [rbx + LI_DEVICEHANDLE], rax
    mov     [rbx + LI_FILEPATH], r15
    mov     qword [rbx + LI_RESERVED], 0
    mov     qword [rbx + LI_LOADOPTIONSSIZE], 0
    mov     qword [rbx + LI_LOADOPTIONS], 0
    mov     rax, [abs g_img_base]
    mov     [rbx + LI_IMAGEBASE], rax
    mov     rax, [abs g_img_pages]
    shl     rax, 12
    mov     [rbx + LI_IMAGESIZE], rax
    mov     dword [rbx + LI_IMAGECODETYPE], EfiLoaderCode
    mov     dword [rbx + LI_IMAGEDATATYPE], EfiLoaderData
    mov     qword [rbx + LI_UNLOAD], 0
    mov     rax, [abs g_img_entry]
    mov     [rbx + IR_ENTRY], rax
    mov     dword [rbx + IR_STATE], IMG_LOADED

    mov     rax, rbx
    lea     rsi, [rel guid_loaded_image]
    mov     rdi, rbx
    call    proto_add

    mov     [r13], rbx
    xor     eax, eax
    jmp     .done
.not_found:
    mov     rax, EFI_NOT_FOUND
    jmp     .done
.load_error:
    mov     rax, EFI_LOAD_ERROR
    jmp     .done
.bad:
    mov     rax, EFI_INVALID_PARAMETER
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ----------------------------------------------------------------------------
; bs_start_image -- StartImage(ImageHandle, ExitDataSize, ExitData).
; Returns whatever the image returned, or passed to Exit().
; ----------------------------------------------------------------------------
bs_start_image:
    call    image_record
    test    rax, rax
    jz      start_image_bad
    cmp     dword [rax + IR_STATE], IMG_LOADED
    jne     start_image_bad
    ; No exit data is ever kept, so there is never any to hand back.
    test    rdx, rdx
    jz      .no_size
    mov     qword [rdx], 0
.no_size:
    test    r8, r8
    jz      .no_data
    mov     qword [r8], 0
.no_data:

    push    rbx
    push    rbp
    push    rdi
    push    rsi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, IMG_XMM_BYTES + IMG_SAVE_PAD
    movdqu  [rsp + 0x00], xmm6
    movdqu  [rsp + 0x10], xmm7
    movdqu  [rsp + 0x20], xmm8
    movdqu  [rsp + 0x30], xmm9
    movdqu  [rsp + 0x40], xmm10
    movdqu  [rsp + 0x50], xmm11
    movdqu  [rsp + 0x60], xmm12
    movdqu  [rsp + 0x70], xmm13
    movdqu  [rsp + 0x80], xmm14
    movdqu  [rsp + 0x90], xmm15

    mov     rbx, rax
    mov     rax, [abs g_current_image]
    mov     [rbx + IR_PREV], rax
    mov     [abs g_current_image], rbx
    mov     dword [rbx + IR_STATE], IMG_RUNNING
    mov     [rbx + IR_EXIT_RSP], rsp

    and     rsp, -16
    sub     rsp, 32
    mov     rcx, rbx                            ; ImageHandle
    mov     rdx, EFI_ST                         ; SystemTable
    call    [rbx + IR_ENTRY]

; image_start_resume -- RAX = the status. Where a return from the entry point
; and a call to Exit() both arrive. Nothing is assumed of the registers: the record comes from
; g_current_image, and the stack from the record.
image_start_resume:
    mov     rbx, [abs g_current_image]
    mov     rsp, [rbx + IR_EXIT_RSP]
    mov     dword [rbx + IR_STATE], IMG_DONE
    mov     rcx, [rbx + IR_PREV]
    mov     [abs g_current_image], rcx

    movdqu  xmm6,  [rsp + 0x00]
    movdqu  xmm7,  [rsp + 0x10]
    movdqu  xmm8,  [rsp + 0x20]
    movdqu  xmm9,  [rsp + 0x30]
    movdqu  xmm10, [rsp + 0x40]
    movdqu  xmm11, [rsp + 0x50]
    movdqu  xmm12, [rsp + 0x60]
    movdqu  xmm13, [rsp + 0x70]
    movdqu  xmm14, [rsp + 0x80]
    movdqu  xmm15, [rsp + 0x90]
    add     rsp, IMG_XMM_BYTES + IMG_SAVE_PAD
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rsi
    pop     rdi
    pop     rbp
    pop     rbx
    ret

; start_image_bad -- StartImage's answer to a handle it cannot start.
start_image_bad:
    mov     rax, EFI_INVALID_PARAMETER
    ret

; ----------------------------------------------------------------------------
; bs_unload_image -- UnloadImage(ImageHandle).
;
; An image that is loaded and not running, or has finished, is retired. Its
; memory is not given back -- nothing in this allocator ever is -- and the
; record stays allocated so a stale handle cannot alias a new image. A running
; image would need its own Unload function, which none here registers.
; ----------------------------------------------------------------------------
bs_unload_image:
    call    image_record
    test    rax, rax
    jz      .bad
    cmp     dword [rax + IR_STATE], IMG_RUNNING
    je      .unsupported
    mov     dword [rax + IR_STATE], IMG_DONE
    xor     eax, eax
    ret
.unsupported:
    mov     rax, EFI_UNSUPPORTED
    ret
.bad:
    mov     rax, EFI_INVALID_PARAMETER
    ret

; ============================================================================
; maze.asm -- a program: generate a maze, solve it, draw it
;
; A flat binary, loaded at the base of a task's window with nothing resolved
; for it, so every reference is RIP-relative. It never yields: whenever it
; disappears from the output for a while, the timer took it away.
;
;   nasm -f bin -I ../ -I . -o MAZE.BIN maze.asm
; ============================================================================

bits 64
default rel
org 0

%include "uabi.inc"

; A maze that fits the console: 79 columns by 39 rows of characters, which is
; 39 by 19 cells with walls between and around them.
M_CELLS_X       equ 39
M_CELLS_Y       equ 19
M_W             equ M_CELLS_X * 2 + 1
M_H             equ M_CELLS_Y * 2 + 1
M_CELLS         equ M_CELLS_X * M_CELLS_Y
M_ROW_BYTES     equ M_W + 1                 ; the line feed
M_RENDER_SIZE   equ M_ROW_BYTES * M_H

M_DIRS          equ 4
M_NO_DIR        equ 0xFF                    ; how the first cell was entered

CH_WALL         equ '#'
CH_OPEN         equ ' '
CH_PATH         equ '.'

U_HEX16_DIGITS  equ 4
U_DEC_DIGITS    equ 4
U_SEED_FALLBACK equ 0x2545F4914F6CDD1D      ; if the counter reads zero

_start:
    mov     [rel u_id], rdi
    mov     [rel u_window], rsi
    mov     [rel u_sibling], rdx

    lea     rdi, [rel u_hello]
    mov     esi, u_hello_len
    call    u_write

    mov     ax, cs
    movzx   eax, ax
    lea     rdi, [rel u_csvalue]
    mov     ecx, U_HEX16_DIGITS
    call    u_hex
    lea     rdi, [rel u_csline]
    mov     esi, u_csline_len
    call    u_write

    ; The seed is the one thing this program cannot produce for itself.
    mov     eax, SYS_TICKS
    syscall
    test    rax, rax
    jnz     .seeded
    mov     rax, U_SEED_FALLBACK
.seeded:
    mov     [rel u_seed], rax

    call    maze_generate
    call    maze_solve
    call    maze_render

    mov     rax, [rel m_path_len]
    lea     rdi, [rel u_pathvalue]
    mov     ecx, U_DEC_DIGITS
    call    u_dec
    lea     rdi, [rel u_pathline]
    mov     esi, u_pathline_len
    call    u_write

    xor     edi, edi
    call    u_exit

; ----------------------------------------------------------------------------
; maze_generate -- randomised depth-first search over the cells.
;
; Carving rather than placing: the grid starts solid, and every step knocks
; down the one wall between the current cell and a neighbour that has not been
; reached yet. Because a cell is only ever entered once, what comes out is a
; spanning tree -- a perfect maze, with exactly one route between any two
; points, which is what makes the solver below able to assume it.
; ----------------------------------------------------------------------------
maze_generate:
    lea     rdi, [rel m_grid]
    mov     ecx, M_W * M_H
    mov     al, CH_WALL
    rep     stosb

    xor     ecx, ecx
    xor     edx, edx
    call    m_cell_ptr
    mov     byte [rax], CH_OPEN

    lea     rdi, [rel m_stack]
    mov     word [rdi], 0
    mov     dword [rel m_depth], 1

.step:
    mov     eax, [rel m_depth]
    test    eax, eax
    jz      .done
    dec     eax
    lea     rdi, [rel m_stack]
    movzx   ecx, byte [rdi + rax*2]
    movzx   edx, byte [rdi + rax*2 + 1]
    mov     [rel m_cx], ecx
    mov     [rel m_cy], edx

    ; Which of the four neighbours are still walled in
    xor     r8d, r8d                        ; how many candidates
    xor     r9d, r9d                        ; direction under test
.dir:
    mov     ecx, [rel m_cx]
    mov     edx, [rel m_cy]
    call    m_neighbour
    test    eax, eax
    jz      .dir_next
    call    m_cell_ptr
    cmp     byte [rax], CH_WALL
    jne     .dir_next
    lea     rdi, [rel m_cand]
    mov     [rdi + r8], r9b
    inc     r8d
.dir_next:
    inc     r9d
    cmp     r9d, M_DIRS
    jb      .dir

    test    r8d, r8d
    jz      .backtrack

    mov     ecx, r8d
    call    u_rand_mod
    lea     rdi, [rel m_cand]
    movzx   r9d, byte [rdi + rax]

    mov     ecx, [rel m_cx]
    mov     edx, [rel m_cy]
    call    m_wall_ptr
    mov     byte [rax], CH_OPEN

    mov     ecx, [rel m_cx]
    mov     edx, [rel m_cy]
    call    m_neighbour
    call    m_cell_ptr
    mov     byte [rax], CH_OPEN

    mov     eax, [rel m_depth]
    lea     rdi, [rel m_stack]
    mov     [rdi + rax*2], cl
    mov     [rdi + rax*2 + 1], dl
    inc     eax
    mov     [rel m_depth], eax
    jmp     .step

.backtrack:
    dec     dword [rel m_depth]
    jmp     .step

.done:
    ; A way in at the top left and a way out at the bottom right
    lea     rdi, [rel m_grid]
    mov     byte [rdi + M_W], CH_OPEN
    mov     eax, (M_H - 2) * M_W + M_W - 1
    mov     byte [rdi + rax], CH_OPEN
    ret

; ----------------------------------------------------------------------------
; maze_solve -- depth-first search, marking as it goes and unmarking as it
; backs out. In a perfect maze the cells still marked when the exit is reached
; are exactly the route to it, so no second pass is needed to recover it.
;
; The stack carries four bytes per cell: where it is, which direction to try
; next, and which direction it was entered from -- that last one only so that
; backing out can put the wall's character back the way it found it.
; ----------------------------------------------------------------------------
maze_solve:
    lea     rdi, [rel m_seen]
    mov     ecx, M_CELLS
    xor     al, al
    rep     stosb

    lea     rdi, [rel m_solve]
    mov     byte [rdi + 0], 0
    mov     byte [rdi + 1], 0
    mov     byte [rdi + 2], 0
    mov     byte [rdi + 3], M_NO_DIR
    mov     dword [rel m_depth], 1

    xor     ecx, ecx
    xor     edx, edx
    call    m_seen_ptr
    mov     byte [rax], 1
    call    m_cell_ptr
    mov     byte [rax], CH_PATH

.step:
    mov     eax, [rel m_depth]
    test    eax, eax
    jz      .fail
    dec     eax
    lea     rdi, [rel m_solve]
    lea     rdi, [rdi + rax*4]
    movzx   ecx, byte [rdi + 0]
    movzx   edx, byte [rdi + 1]

    cmp     ecx, M_CELLS_X - 1
    jne     .not_goal
    cmp     edx, M_CELLS_Y - 1
    je      .found
.not_goal:
    movzx   r9d, byte [rdi + 2]
    cmp     r9d, M_DIRS
    jae     .pop
    lea     eax, [r9 + 1]
    mov     [rdi + 2], al

    call    m_wall_ptr
    cmp     byte [rax], CH_WALL
    je      .step                           ; no passage that way
    mov     [rel m_passage], rax

    call    m_neighbour
    test    eax, eax
    jz      .step
    call    m_seen_ptr
    cmp     byte [rax], 0
    jne     .step
    mov     byte [rax], 1

    mov     rax, [rel m_passage]
    mov     byte [rax], CH_PATH
    call    m_cell_ptr
    mov     byte [rax], CH_PATH

    mov     eax, [rel m_depth]
    lea     rdi, [rel m_solve]
    lea     rdi, [rdi + rax*4]
    mov     [rdi + 0], cl
    mov     [rdi + 1], dl
    mov     byte [rdi + 2], 0
    mov     [rdi + 3], r9b
    inc     eax
    mov     [rel m_depth], eax
    jmp     .step

.pop:
    ; This cell led nowhere. Take it, and the passage that reached it, back
    ; off the path. The entry direction reversed is the same wall.
    movzx   r9d, byte [rdi + 3]
    call    m_cell_ptr
    mov     byte [rax], CH_OPEN
    cmp     r9d, M_NO_DIR
    je      .pop_done
    xor     r9d, 1
    call    m_wall_ptr
    mov     byte [rax], CH_OPEN
.pop_done:
    dec     dword [rel m_depth]
    jmp     .step

.found:
    mov     eax, [rel m_depth]
    mov     [rel m_path_len], rax
    ret
.fail:
    mov     qword [rel m_path_len], 0
    ret

; ----------------------------------------------------------------------------
; maze_render -- the whole grid in one system call. Thirty-nine of them would
; work equally well and be thirty-eight more crossings of the ring boundary
; than the picture is worth.
; ----------------------------------------------------------------------------
maze_render:
    lea     rsi, [rel m_grid]
    lea     rdi, [rel m_out]
    mov     r8d, M_H
.row:
    mov     ecx, M_W
    rep     movsb
    mov     byte [rdi], 10
    inc     rdi
    dec     r8d
    jnz     .row

    lea     rdi, [rel m_out]
    mov     esi, M_RENDER_SIZE
    call    u_write
    ret

; ----------------------------------------------------------------------------
; m_cell_ptr -- ECX = cell x, EDX = cell y. Returns RAX = the character.
; Cells sit at odd coordinates; the even ones between them are the walls.
; ----------------------------------------------------------------------------
m_cell_ptr:
    push    rcx
    push    rdx
    lea     ecx, [ecx*2 + 1]
    lea     edx, [edx*2 + 1]
    imul    edx, M_W
    add     ecx, edx
    lea     rax, [rel m_grid]
    add     rax, rcx
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; m_wall_ptr -- ECX = cell x, EDX = cell y, R9D = direction.
; Returns RAX = the character between that cell and its neighbour that way.
; ----------------------------------------------------------------------------
m_wall_ptr:
    push    rcx
    push    rdx
    push    rsi
    lea     ecx, [ecx*2 + 1]
    lea     edx, [edx*2 + 1]
    lea     rsi, [rel u_dx]
    movsx   eax, byte [rsi + r9]
    add     ecx, eax
    lea     rsi, [rel u_dy]
    movsx   eax, byte [rsi + r9]
    add     edx, eax
    imul    edx, M_W
    add     ecx, edx
    lea     rax, [rel m_grid]
    add     rax, rcx
    pop     rsi
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; m_seen_ptr -- ECX = cell x, EDX = cell y. Returns RAX = its visited flag.
; ----------------------------------------------------------------------------
m_seen_ptr:
    push    rcx
    push    rdx
    imul    edx, M_CELLS_X
    add     ecx, edx
    lea     rax, [rel m_seen]
    add     rax, rcx
    pop     rdx
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; m_neighbour -- ECX = cell x, EDX = cell y, R9D = direction.
; Returns EAX = 1 with ECX/EDX moved, or EAX = 0 with them untouched.
; ----------------------------------------------------------------------------
m_neighbour:
    push    rsi
    lea     rsi, [rel u_dx]
    movsx   eax, byte [rsi + r9]
    add     eax, ecx
    js      .outside
    cmp     eax, M_CELLS_X
    jae     .outside
    mov     r11d, eax
    lea     rsi, [rel u_dy]
    movsx   eax, byte [rsi + r9]
    add     eax, edx
    js      .outside
    cmp     eax, M_CELLS_Y
    jae     .outside
    mov     edx, eax
    mov     ecx, r11d
    mov     eax, 1
    pop     rsi
    ret
.outside:
    xor     eax, eax
    pop     rsi
    ret

; ----------------------------------------------------------------------------
; u_rand -- xorshift64. Returns RAX and advances the state.
; ----------------------------------------------------------------------------
u_rand:
    push    rcx
    mov     rax, [rel u_seed]
    mov     rcx, rax
    shl     rcx, 13
    xor     rax, rcx
    mov     rcx, rax
    shr     rcx, 7
    xor     rax, rcx
    mov     rcx, rax
    shl     rcx, 17
    xor     rax, rcx
    mov     [rel u_seed], rax
    pop     rcx
    ret

; ----------------------------------------------------------------------------
; u_rand_mod -- ECX = bound. Returns EAX in [0, bound).
; ----------------------------------------------------------------------------
u_rand_mod:
    push    rbx
    push    rdx
    mov     ebx, ecx
    call    u_rand
    xor     edx, edx
    div     ebx
    mov     eax, edx
    pop     rdx
    pop     rbx
    ret

%include "ulib.inc"

; ----------------------------------------------------------------------------
u_dx:   db 1, -1, 0, 0
u_dy:   db 0, 0, 1, -1

u_hello:
    db "task 0   loaded from \PROGS\MAZE.BIN; generating a maze", 10
u_hello_len     equ $ - u_hello

u_csline:
    db "task 0   cs = "
u_csvalue:
    db "0000"
    db " -- the low two bits are the privilege level", 10
u_csline_len    equ $ - u_csline

u_pathline:
    db 10, "task 0   solved: "
u_pathvalue:
    db "0000"
    db " cells on the only route from one corner to the other", 10
u_pathline_len  equ $ - u_pathline

; ----------------------------------------------------------------------------
; Working memory, inside the image because the image is the only thing whose
; address this program can compute.
; ----------------------------------------------------------------------------
align 8
u_id:           dq 0
u_window:       dq 0
u_sibling:      dq 0
u_seed:         dq 0
m_passage:      dq 0
m_path_len:     dq 0
m_cx:           dd 0
m_cy:           dd 0
m_depth:        dd 0
m_cand:         times M_DIRS db 0

align 8
m_grid:         times M_W * M_H db 0
m_out:          times M_RENDER_SIZE db 0
m_seen:         times M_CELLS db 0
m_stack:        times M_CELLS * 2 db 0
m_solve:        times M_CELLS * 4 db 0

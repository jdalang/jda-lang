; jda0 — Jda Stage 0 Compiler (generated)
; Usage: jda0 <source.jda> <output>
BITS 64
DEFAULT REL

; Syscall numbers
SYS_READ         equ 0
SYS_WRITE        equ 1
SYS_OPEN         equ 2
SYS_CLOSE        equ 3
SYS_MMAP         equ 9
SYS_EXIT         equ 60

; ELF constants
PT_LOAD          equ 1
ET_EXEC          equ 2
EM_X86_64        equ 62
PF_RWX           equ 7
PROT_RW          equ 3
MAP_PA           equ 34

; Table entry sizes
TOK_SZ           equ 32
CST_SZ           equ 32
FLD_SZ           equ 48
STR_SZ           equ 3104
FN_SZ            equ 288
PRM_SZ           equ 32
LOC_SZ           equ 48
GLB_SZ           equ 48
TOK_BUF_CAP      equ 8388608  ; 8MB = 262144 tokens at TOK_SZ=32
CST_TBL_CAP      equ 65536
STT_TBL_CAP      equ 131072   ; 42 struct entries at STR_SZ=3104
FN_TBL_CAP       equ 262144   ; 910 fn entries at FN_SZ=288 (was 131072)
LOC_TBL_CAP      equ 65536
GLB_TBL_CAP      equ 32768
SRC_BUF_CAP      equ 16777216
COD_BUF_CAP      equ 16777216
SDT_BUF_CAP      equ 4194304
FIX_BUF_CAP      equ 4194304
SFX_TBL_CAP      equ 262144

; Token type constants
TOK_FN           equ 0
TOK_LET          equ 1
TOK_IF           equ 2
TOK_ELSE         equ 3
TOK_LOOP         equ 4
TOK_RET          equ 5
TOK_STRUCT       equ 6
TOK_MATCH        equ 7
TOK_PRINT        equ 8
TOK_SYSCALL      equ 9
TOK_IDENT        equ 10
TOK_INT          equ 11
TOK_STR          equ 12
TOK_LPAREN       equ 13
TOK_RPAREN       equ 14
TOK_LBRACE       equ 15
TOK_RBRACE       equ 16
TOK_LBRACK       equ 17
TOK_RBRACK       equ 18
TOK_COMMA        equ 19
TOK_COLON        equ 20
TOK_SEMI         equ 21
TOK_ARROW        equ 22
TOK_EQ           equ 23
TOK_EQEQ         equ 24
TOK_NEQ          equ 25
TOK_LT           equ 26
TOK_GT           equ 27
TOK_PLUS         equ 28
TOK_MINUS        equ 29
TOK_STAR         equ 30
TOK_SLASH        equ 31
TOK_AMP          equ 32
TOK_DOT          equ 33
TOK_FATARROW     equ 34
TOK_EOF          equ 35
TOK_I64          equ 36
TOK_I32          equ 37
TOK_I8           equ 38
TOK_F64          equ 39
TOK_CONST        equ 40
TOK_ASM          equ 41
TOK_BREAK        equ 42
TOK_OR           equ 43
TOK_AND          equ 44
TOK_CHAR         equ 45
TOK_LTEQ         equ 46
TOK_GTEQ         equ 47
TOK_PIPE         equ 48  ; | bitwise or
TOK_SHL          equ 49  ; << left shift
TOK_SHR          equ 50  ; >> right shift
TOK_ALLOC_PAGES  equ 51

; Type kind
TK_SCALAR        equ 0
TK_STRUCT        equ 1
TK_PTR           equ 2
PTR_FLAG         equ 0x8000000000000000

section .bss
    align 8
    src_buf_ptr resb 8
    tok_buf_ptr resb 8
    tok_cnt resb 8
    tok_pos resb 8
    cst_tbl_ptr resb 8
    cst_cnt resb 8
    stt_tbl_ptr resb 8
    stt_cnt resb 8
    fn_tbl_ptr  resb 8
    fn_cnt  resb 8
    loc_tbl_ptr resb 8
    loc_cnt resb 8
    loc_rbp resb 8
    loc_max_rbp resb 8
    lv_sid resb 8
    lv_esz resb 8
    lv_isptr resb 8
    lv_glb resb 8
    p1_glb_tkind resb 8
    p1_glb_sid   resb 8
    p1_glb_esz   resb 8
    ga_from_dot resb 8      ; 1 if last .ga_post_loop entry came from .ga_dot
    ga_acnt     resb 8      ; array count from field; >0 means embedded array
    glb_tbl_ptr resb 8
    glb_cnt resb 8
    glb_r15 resb 8
    fix_cnt resb 8
    cod_buf_ptr resb 8
    cod_len resb 8
    sdt_buf_ptr resb 8
    sdt_len resb 8
    fix_buf_ptr resb 8
    sfx_tbl_ptr resb 8
    sfix_cnt resb 8
    jmp_stk resb 4096
    jmp_top resb 8
    brk_lbl resb 8
    lbl_seq resb 8
    src_len resb 8
    out_fd resb 8
    frm_patch_off resb 8    ; frame size placeholder offset (gen_fn, r15 not safe)
    prm_cnt_bss  resb 8    ; param count during gen_fn loop (all regs clobbered)
    prec_stop    resb 1    ; 0=normal, 1=stop-before-or, 2=stop-before-or-and
    arith_stop   resb 1    ; 0=normal, 1=stop-before-plus-minus
    asm_reglen   resb 8    ; asm handler: register name length (r15 must not be clobbered)

section .data
    m_usage db `Usage: jda0 <src.jda> <out>\n`,0
    m_usage_l equ $-m_usage-1
    m_ok db `[jda0] compiled ok\n`,0
    m_ok_l equ $-m_ok-1
    m_err db `[jda0] parse error\n`,0
    m_err_l equ $-m_err-1
    m_oom db `[jda0] out of memory\n`,0
    m_oom_l equ $-m_oom-1
    
    ; keywords — order matters for classify_kw()
    kw_fn db "fn",0
    kw_let db "let",0
    kw_if db "if",0
    kw_else db "else",0
    kw_loop db "loop",0
    kw_ret db "ret",0
    kw_struct db "struct",0
    kw_match db "match",0
    kw_print db "print",0
    kw_syscall db "syscall",0
    kw_i64 db "i64",0
    kw_i32 db "i32",0
    kw_i8 db "i8",0
    kw_f64 db "f64",0
    kw_const db "const",0
    kw_asm db "asm",0
    kw_break db "break",0
    kw_or db "or",0
    kw_and db "and",0
    kw_alloc_pages db "alloc_pages",0
    kw_ok db "ok",0

    ; register name strings
    rn_rax db "rax",0
    rn_rcx db "rcx",0
    rn_rdx db "rdx",0
    rn_rbx db "rbx",0
    rn_rsp db "rsp",0
    rn_rbp db "rbp",0
    rn_rsi db "rsi",0
    rn_rdi db "rdi",0
    rn_r8 db "r8",0
    rn_r9 db "r9",0
    rn_r10 db "r10",0
    rn_r11 db "r11",0
    rn_r12 db "r12",0
    rn_r13 db "r13",0
    rn_r14 db "r14",0
    rn_r15 db "r15",0
    kw_out db "out",0
    kw_in  db "in",0

; =============================================================================
    ; print_int_code: inline integer→decimal+write bytecode (emitted for print(expr))
    ; At runtime: rax = integer value → writes decimal + newline to fd 1
print_int_code:
    db 0x53                               ; push rbx
    db 0x41, 0x54                         ; push r12
    db 0x41, 0x55                         ; push r13
    db 0x49, 0x89, 0xC4                   ; mov r12, rax     (save value)
    db 0x48, 0x83, 0xEC, 0x20             ; sub rsp, 32      (buffer)
    db 0x4C, 0x8D, 0x6C, 0x24, 0x1F      ; lea r13, [rsp+31] (end of buf)
    db 0x41, 0xC6, 0x45, 0x00, 0x0A      ; mov byte [r13+0], 10 (newline)
    db 0x49, 0xFF, 0xCD                   ; dec r13          (before newline)
    db 0xBB, 0x0A, 0x00, 0x00, 0x00      ; mov ebx, 10      (divisor)
    db 0x4C, 0x89, 0xE0                   ; mov rax, r12     (value into rax)
    ; loop: extract digits right-to-left
    db 0x31, 0xD2                         ; xor edx, edx
    db 0x48, 0xF7, 0xF3                   ; div rbx          (rax/=10, rdx=digit)
    db 0x80, 0xC2, 0x30                   ; add dl, '0'
    db 0x41, 0x88, 0x55, 0x00             ; mov byte [r13+0], dl
    db 0x49, 0xFF, 0xCD                   ; dec r13
    db 0x48, 0x85, 0xC0                   ; test rax, rax
    db 0x75, 0xEC                         ; jnz -20 (back to xor edx,edx)
    ; post-loop: r13 points one before first digit, inc to first digit
    db 0x49, 0xFF, 0xC5                   ; inc r13
    db 0x48, 0x8D, 0x44, 0x24, 0x20      ; lea rax, [rsp+32] (past newline)
    db 0x4C, 0x29, 0xE8                   ; sub rax, r13     (length)
    db 0x89, 0xC2                         ; mov edx, eax
    db 0x4C, 0x89, 0xEE                   ; mov rsi, r13     (buf ptr)
    db 0xBF, 0x01, 0x00, 0x00, 0x00      ; mov edi, 1       (fd=stdout)
    db 0xB8, 0x01, 0x00, 0x00, 0x00      ; mov eax, 1       (SYS_WRITE)
    db 0x0F, 0x05                         ; syscall
    db 0x48, 0x83, 0xC4, 0x20             ; add rsp, 32
    db 0x41, 0x5D                         ; pop r13
    db 0x41, 0x5C                         ; pop r12
    db 0x5B                               ; pop rbx
print_int_code_len equ $-print_int_code

section .text
global _start
_start:
    ; argc=[rsp] argv=[rsp+8..]  — System V ABI for Linux _start
    mov     rdi, [rsp]      ; argc
    lea     rsi, [rsp+8]    ; argv
    cmp     rdi, 3
    jl      .bad_args
    mov     edi, SRC_BUF_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [src_buf_ptr], rax
    mov     edi, TOK_BUF_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [tok_buf_ptr], rax
    mov     edi, CST_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [cst_tbl_ptr], rax
    mov     edi, STT_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [stt_tbl_ptr], rax
    mov     edi, FN_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [fn_tbl_ptr], rax
    mov     edi, LOC_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [loc_tbl_ptr], rax
    mov     edi, GLB_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [glb_tbl_ptr], rax
    mov     edi, COD_BUF_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [cod_buf_ptr], rax
    mov     edi, SDT_BUF_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [sdt_buf_ptr], rax
    mov     edi, FIX_BUF_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [fix_buf_ptr], rax
    mov     edi, SFX_TBL_CAP
    call    mmap_anon
    test    rax, rax
    js      .bad_oom
    mov     [sfx_tbl_ptr], rax
    ; argv[1] = source path
    lea     rsi, [rsp+8]
    mov     rcx, [rsi+8]
    mov     r12, [src_buf_ptr]
    ; open source file
    mov     eax, SYS_OPEN
    mov     rdi, rcx
    xor     esi, esi
    xor     edx, edx
    syscall
    cmp     rax, 0
    jl      .bad_open
    mov     r13, rax            ; r13 = src fd
    ; read source
    mov     eax, SYS_READ
    mov     rdi, r13
    mov     rsi, [src_buf_ptr]
    mov     edx, 1048574
    syscall
    cmp     rax, 0
    jl      .bad_read
    mov     [src_len], rax
    ; zero-terminate
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    mov     byte [rbx], 0
    ; close src
    mov     eax, SYS_CLOSE
    mov     rdi, r13
    syscall
    ; open output file
    lea     rdi, [rsp+8]    ; recompute argv base (rsi may have been clobbered)
    mov     rdi, [rsp]
    lea     rsi, [rsp+8]
    mov     rcx, [rsi+16]   ; argv[2] = output path
    mov     eax, SYS_OPEN
    mov     rdi, rcx
    mov     esi, 0x241      ; O_WRONLY|O_CREAT|O_TRUNC
    mov     edx, 0o755
    syscall
    cmp     rax, 0
    jl      .bad_create
    mov     [out_fd], rax
    ; compile
    call    main_compile
    ; close output
    mov     eax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall
    ; print ok
    mov     eax, SYS_WRITE
    mov     edi, 1
    lea     rsi, [m_ok]
    mov     edx, m_ok_l
    syscall
    ; exit 0
    mov     eax, SYS_EXIT
    xor     edi, edi
    syscall
.bad_args:
    mov     eax, SYS_WRITE
    mov     edi, 2
    lea     rsi, [m_usage]
    mov     edx, m_usage_l
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall
.bad_open:
.bad_read:
.bad_create:
    mov     eax, SYS_WRITE
    mov     edi, 2
    lea     rsi, [m_err]
    mov     edx, m_err_l
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall
.bad_oom:
    mov     eax, SYS_WRITE
    mov     edi, 2
    lea     rsi, [m_oom]
    mov     edx, m_oom_l
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall

; =============================================================================
; die — write msg to stderr and exit(1)
; rdi=ptr, rsi=len
; =============================================================================
die:
    mov     edx, esi
    mov     esi, edi
    mov     edi, 2
    mov     eax, SYS_WRITE
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall

; =============================================================================
; strncmp_src: compare src_buf[rbx..rbx+rcx] with nul-terminated string rdx
; returns: rax=1 if equal, 0 otherwise
; =============================================================================
strncmp_src:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    mov     rsi, rcx        ; len
    mov     r8, [src_buf_ptr]
    add     r8, rbx         ; src ptr
.loop:
    cmp     rsi, 0
    je      .check_end
    mov     al, [r8]
    cmp     al, [rdx]
    jne     .no
    inc     r8
    inc     rdx
    dec     rsi
    jmp     .loop
.check_end:
    cmp     byte [rdx], 0
    jne     .no
    mov     rax, 1
    jmp     .done
.no:
    xor     rax, rax
.done:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    leave
    ret

; =============================================================================
; strncmp_mem: compare [r8..r8+rcx] with nul-term [rdx]
; returns rax=1 if equal
; =============================================================================
strncmp_mem:
    push    rbp
    mov     rbp, rsp
    push    r8
    push    rcx
    push    rdx
    mov     rsi, rcx
.loop:
    cmp     rsi, 0
    je      .chk
    mov     al, [r8]
    cmp     al, [rdx]
    jne     .no
    inc     r8
    inc     rdx
    dec     rsi
    jmp     .loop
.chk:
    cmp     byte [rdx], 0
    jne     .no
    mov     rax, 1
    jmp     .done
.no:
    xor     rax, rax
.done:
    pop     rdx
    pop     rcx
    pop     r8
    leave
    ret

; =============================================================================
; print_rax: print RAX as decimal integer to stderr
print_rax:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    mov     rbx, 10
    lea     rcx, [rbp-1]
    mov     byte [rcx], 0
.pr_loop:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .pr_loop
    ; print it
    mov     rax, SYS_WRITE
    mov     rsi, rcx
    mov     rdi, 2          ; stderr
    ; compute length
    lea     rdx, [rbp-1]
    sub     rdx, rsi
    syscall
    leave
    ret

; mmap_anon: rdi=size -> rax=ptr (PROT_RW MAP_PA fd=-1)
; =============================================================================
mmap_anon:
    mov     r9, 0
    mov     r8, -1
    mov     r10, MAP_PA
    mov     rdx, PROT_RW
    mov     rsi, rdi
    xor     rdi, rdi
    mov     rax, SYS_MMAP
    syscall
    ret

; =============================================================================
; emit1, emit4, emit8 — append bytes to cod_buf
; =============================================================================
emit1:  ; rdi = byte
    mov     rax, [cod_len]
    mov     rbx, [cod_buf_ptr]
    add     rbx, rax
    mov     [rbx], dil
    inc     qword [cod_len]
    ret

emit4:  ; rdi = dword
    mov     rax, [cod_len]
    mov     rbx, [cod_buf_ptr]
    add     rbx, rax
    mov     [rbx], edi
    add     qword [cod_len], 4
    ret

emit8:  ; rdi = qword
    mov     rax, [cod_len]
    mov     rbx, [cod_buf_ptr]
    add     rbx, rax
    mov     [rbx], rdi
    add     qword [cod_len], 8
    ret

; emit_bytes: rdi=src ptr, rsi=count
emit_bytes:
    push    rbp
    mov     rbp, rsp
    push    rdi
    push    rsi
.lp:
    cmp     rsi, 0
    je      .done
    mov     al, [rdi]
    push    rdi
    push    rsi
    movzx   edi, al
    call    emit1
    pop     rsi
    pop     rdi
    inc     rdi
    dec     rsi
    jmp     .lp
.done:
    pop     rsi
    pop     rdi
    leave
    ret

; patch4 — patch a dword at cod_buf[rdi] with value rsi
patch4:
    mov     rbx, [cod_buf_ptr]
    add     rbx, rdi
    mov     [rbx], esi
    ret

; new_label — increment lbl_seq and return new id in rax
new_label:
    mov     rax, [lbl_seq]
    inc     qword [lbl_seq]
    ret

; =============================================================================
; LEX_ALL — lex entire src_buf -> tok_buf, tok_cnt
; =============================================================================
lex_all:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    ; local: pos=[rbp-8], count=[rbp-16]
    mov     qword [rbp-8], 0    ; pos
    mov     qword [rbp-16], 0   ; count
    mov     rax, [src_len]
    mov     [rbp-24], rax       ; src_len local
.main_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .done_lex
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    movsx   rcx, byte [rbx]     ; c = src[pos]

    ; Skip whitespace
    cmp     cl, ' '
    je      .skip1
    cmp     cl, 9               ; \t
    je      .skip1
    cmp     cl, 10              ; \n
    je      .skip1
    cmp     cl, 13              ; \r
    je      .skip1
    jmp     .not_ws
.skip1:
    inc     qword [rbp-8]
    jmp     .main_loop
.not_ws:
    ; Skip ; line comment
    cmp     cl, ';'
    jne     .not_semi
.semi_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .done_lex
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], 10
    je      .main_loop
    inc     qword [rbp-8]
    jmp     .semi_loop
.not_semi:
    ; String literal "..."
    cmp     cl, '"'
    jne     .not_str
    inc     qword [rbp-8]       ; skip opening "
    mov     rax, [rbp-8]        ; start
    mov     [rbp-32], rax       ; save start
.str_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .str_end
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    mov     cl, [rbx]
    cmp     cl, '"'
    je      .str_end
    cmp     cl, '\'
    jne     .str_nc
    inc     qword [rbp-8]       ; skip backslash
.str_nc:
    inc     qword [rbp-8]
    jmp     .str_loop
.str_end:
    ; emit TOK_STR token
    mov     rsi, [rbp-16]       ; count
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     qword [rdi], TOK_STR
    mov     rax, [rbp-32]
    mov     [rdi+8], rax        ; start
    mov     rax, [rbp-8]
    sub     rax, [rbp-32]
    mov     [rdi+16], rax       ; len
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    inc     qword [rbp-8]       ; skip closing "
    jmp     .main_loop
.not_str:
    ; Char literal '.'
    cmp     cl, 39              ; single quote
    jne     .not_char
    inc     qword [rbp-8]       ; skip '
    mov     rax, [rbp-8]
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    movsx   rax, byte [rbx]
    cmp     al, '\'
    jne     .char_plain
    inc     qword [rbp-8]       ; skip backslash
    mov     rbx, [src_buf_ptr]
    add     rbx, [rbp-8]
    movsx   rax, byte [rbx]
    cmp     al, 'n'
    jne     .ce2
    mov     rax, 10
    jmp     .char_val
.ce2:
    cmp     al, 't'
    jne     .ce3
    mov     rax, 9
    jmp     .char_val
.ce3:
    cmp     al, 'r'
    jne     .ce4
    mov     rax, 13
    jmp     .char_val
.ce4:
    cmp     al, '0'
    jne     .char_val_raw
    xor     rax, rax
    jmp     .char_val
.char_val_raw:
    movsx   rax, byte [rbx]
    jmp     .char_val
.char_plain:
    ; already in rax
.char_val:
    mov     [rbp-32], rax       ; char value
    inc     qword [rbp-8]       ; advance past char
    inc     qword [rbp-8]       ; skip closing '
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     qword [rdi], TOK_CHAR
    mov     qword [rdi+8], 0
    mov     qword [rdi+16], 1
    mov     rax, [rbp-32]
    mov     [rdi+24], rax
    inc     qword [rbp-16]
    jmp     .main_loop
.not_char:
    ; Integer literal (decimal or 0x hex)
    cmp     cl, '0'
    jl      .not_int
    cmp     cl, '9'
    jg      .not_int
    ; check hex: 0x...
    cmp     cl, '0'
    jne     .dec_int
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .dec_int
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], 'x'
    je      .hex_int
.dec_int:
    xor     r14, r14            ; accumulator
.dec_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .dec_done
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    movsx   rcx, byte [rbx]
    cmp     cl, '0'
    jl      .dec_done
    cmp     cl, '9'
    jg      .dec_done
    imul    r14, r14, 10
    sub     cl, '0'
    add     r14, rcx
    inc     qword [rbp-8]
    jmp     .dec_loop
.dec_done:
    jmp     .emit_int
.hex_int:
    add     qword [rbp-8], 2    ; skip 0x
    xor     r14, r14
.hex_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .emit_int
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    movsx   rcx, byte [rbx]
    cmp     cl, '0'
    jl      .emit_int
    cmp     cl, '9'
    jle     .hex_dig
    cmp     cl, 'a'
    jl      .hex_au
    cmp     cl, 'f'
    jle     .hex_lc
.hex_au:
    cmp     cl, 'A'
    jl      .emit_int
    cmp     cl, 'F'
    jg      .emit_int
    sub     cl, 'A'
    add     cl, 10
    jmp     .hex_acc
.hex_lc:
    sub     cl, 'a'
    add     cl, 10
    jmp     .hex_acc
.hex_dig:
    sub     cl, '0'
.hex_acc:
    shl     r14, 4
    add     r14, rcx
    inc     qword [rbp-8]
    jmp     .hex_loop
.emit_int:
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     qword [rdi], TOK_INT
    mov     qword [rdi+8], 0
    mov     qword [rdi+16], 0
    mov     [rdi+24], r14
    inc     qword [rbp-16]
    jmp     .main_loop
.not_int:
    ; Identifier or keyword
    cmp     cl, '_'
    je      .ident
    cmp     cl, 'a'
    jl      .not_alpha
    cmp     cl, 'z'
    jle     .ident
.not_alpha:
    cmp     cl, 'A'
    jl      .not_ident
    cmp     cl, 'Z'
    jg      .not_ident
.ident:
    mov     r14, [rbp-8]        ; start
.ident_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .ident_done
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    movsx   rcx, byte [rbx]
    cmp     cl, '_'
    je      .ident_cont
    cmp     cl, 'a'
    jl      .ident_alnum
    cmp     cl, 'z'
    jle     .ident_cont
.ident_alnum:
    cmp     cl, 'A'
    jl      .ident_digit
    cmp     cl, 'Z'
    jle     .ident_cont
.ident_digit:
    cmp     cl, '0'
    jl      .ident_done
    cmp     cl, '9'
    jg      .ident_done
.ident_cont:
    inc     qword [rbp-8]
    jmp     .ident_loop
.ident_done:
    ; len = pos - start
    mov     rax, [rbp-8]
    sub     rax, r14
    ; classify keyword: rbx=start, rcx=len, returns tok type in rax
    push    r14
    mov     rbx, r14
    mov     rcx, rax
    call    classify_kw
    pop     r14
    mov     r15, rax            ; token type
    ; emit token
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     [rdi], r15          ; type
    mov     [rdi+8], r14        ; start
    mov     rax, [rbp-8]
    sub     rax, r14
    mov     [rdi+16], rax       ; len
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    jmp     .main_loop
.not_ident:
    ; Two-char operators
    cmp     cl, '-'
    jne     .not_arrow
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .single_char
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], '>'
    jne     .single_char
    add     qword [rbp-8], 2
    mov     r14, TOK_ARROW
    jmp     .emit_op2
.not_arrow:
    cmp     cl, '='
    jne     .not_eqeq
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .single_char
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .not_fat
    add     qword [rbp-8], 2
    mov     r14, TOK_EQEQ
    jmp     .emit_op2
.not_fat:
    cmp     byte [rbx], '>'
    jne     .single_char
    add     qword [rbp-8], 2
    mov     r14, TOK_FATARROW
    jmp     .emit_op2
.not_eqeq:
    cmp     cl, '!'
    jne     .not_neq
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .single_char
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .single_char
    add     qword [rbp-8], 2
    mov     r14, TOK_NEQ
    jmp     .emit_op2
.not_neq:
    cmp     cl, '<'
    jne     .not_lteq
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .single_char
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], '='
    je      .emit_lteq
    cmp     byte [rbx], '<'
    jne     .single_char
    add     qword [rbp-8], 2
    mov     r14, TOK_SHL
    jmp     .emit_op2
.emit_lteq:
    add     qword [rbp-8], 2
    mov     r14, TOK_LTEQ
    jmp     .emit_op2
.not_lteq:
    cmp     cl, '>'
    jne     .single_char
    mov     rax, [rbp-8]
    inc     rax
    cmp     rax, [rbp-24]
    jge     .single_char
    mov     rbx, [src_buf_ptr]
    add     rbx, rax
    cmp     byte [rbx], '='
    je      .emit_gteq
    cmp     byte [rbx], '>'
    jne     .single_char
    add     qword [rbp-8], 2
    mov     r14, TOK_SHR
    jmp     .emit_op2
.emit_gteq:
    add     qword [rbp-8], 2
    mov     r14, TOK_GTEQ
    jmp     .emit_op2
.emit_op2:
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     [rdi], r14
    mov     qword [rdi+8], 0
    mov     qword [rdi+16], 0
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    jmp     .main_loop
.single_char:
    ; map single char to token
    push    rcx
    call    char_to_tok
    pop     rcx
    mov     r14, rax
    inc     qword [rbp-8]
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     [rdi], r14
    mov     qword [rdi+8], 0
    mov     qword [rdi+16], 0
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    jmp     .main_loop
.done_lex:
    ; emit TOK_EOF
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    mov     rdi, [tok_buf_ptr]
    add     rdi, rsi
    mov     qword [rdi], TOK_EOF
    mov     qword [rdi+8], 0
    mov     qword [rdi+16], 0
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    mov     rax, [rbp-16]
    mov     [tok_cnt], rax
    leave
    ret

; char_to_tok: cl = char -> rax = token type
char_to_tok:
    cmp     cl, '('
    je      .lp
    cmp     cl, ')'
    je      .rp
    cmp     cl, '{'
    je      .lb
    cmp     cl, '}'
    je      .rb
    cmp     cl, '['
    je      .lbk
    cmp     cl, ']'
    je      .rbk
    cmp     cl, ','
    je      .cm
    cmp     cl, ':'
    je      .co
    cmp     cl, '='
    je      .eq
    cmp     cl, '<'
    je      .lt
    cmp     cl, '>'
    je      .gt
    cmp     cl, '+'
    je      .pl
    cmp     cl, '-'
    je      .mi
    cmp     cl, '*'
    je      .st
    cmp     cl, '/'
    je      .sl
    cmp     cl, '&'
    je      .am
    cmp     cl, '.'
    je      .dt
    cmp     cl, '|'
    je      .pp
    mov     eax, TOK_EOF
    ret
.lp:  mov eax, TOK_LPAREN
      ret
.rp:  mov eax, TOK_RPAREN
      ret
.lb:  mov eax, TOK_LBRACE
      ret
.rb:  mov eax, TOK_RBRACE
      ret
.lbk: mov eax, TOK_LBRACK
      ret
.rbk: mov eax, TOK_RBRACK
      ret
.cm:  mov eax, TOK_COMMA
      ret
.co:  mov eax, TOK_COLON
      ret
.eq:  mov eax, TOK_EQ
      ret
.lt:  mov eax, TOK_LT
      ret
.gt:  mov eax, TOK_GT
      ret
.pl:  mov eax, TOK_PLUS
      ret
.mi:  mov eax, TOK_MINUS
      ret
.st:  mov eax, TOK_STAR
      ret
.sl:  mov eax, TOK_SLASH
      ret
.am:  mov eax, TOK_AMP
      ret
.dt:  mov eax, TOK_DOT
      ret
.pp:  mov eax, TOK_PIPE
      ret

; classify_kw: rbx=start, rcx=len -> rax=token type
; tries each keyword
classify_kw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rcx
    push    rdx
    ; Try each keyword
    %macro try_kw 2
    lea     rdx, [kw_%1]
    call    strncmp_src
    cmp     rax, 1
    jne     %%skip
    mov     eax, %2
    jmp     .ck_done
    %%skip:
    %endmacro
    try_kw fn,      TOK_FN
    try_kw let,     TOK_LET
    try_kw if,      TOK_IF
    try_kw else,    TOK_ELSE
    try_kw loop,    TOK_LOOP
    try_kw ret,     TOK_RET
    try_kw struct,  TOK_STRUCT
    try_kw match,   TOK_MATCH
    try_kw print,   TOK_PRINT
    try_kw syscall, TOK_SYSCALL
    try_kw i64,     TOK_I64
    try_kw i32,     TOK_I32
    try_kw i8,      TOK_I8
    try_kw f64,     TOK_F64
    try_kw const,   TOK_CONST
    try_kw asm,     TOK_ASM
    try_kw break,   TOK_BREAK
    try_kw or,      TOK_OR
    try_kw and,     TOK_AND
    try_kw alloc_pages, TOK_ALLOC_PAGES
    try_kw ok,      TOK_IDENT
    mov     eax, TOK_IDENT
.ck_done:
    pop     rdx
    pop     rcx
    pop     rbx
    leave
    ret


; =============================================================================
; Token cursor helpers (use tok_pos global)
; =============================================================================
get_cur_tok_ptr:            ; -> rax = ptr to current token (does NOT clobber rbx)
    mov     rax, [tok_pos]
    imul    rax, rax, TOK_SZ
    mov     r10, [tok_buf_ptr]
    add     rax, r10
    ret

adv_tok:                    ; advance tok_pos by 1
    inc     qword [tok_pos]
    ret

cur_tok_type:               ; -> rax = type of current token
    call    get_cur_tok_ptr
    mov     rax, [rax]
    ret

; expect_tok rdi=type: advance if match, die otherwise
expect_tok:
    push    rdi
    call    get_cur_tok_ptr
    pop     rdi
    cmp     [rax], rdi
    jne     .fail
    inc     qword [tok_pos]
    ret
.fail:
    mov     eax, SYS_WRITE
    mov     edi, 2
    lea     rsi, [m_err]
    mov     edx, m_err_l
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall

; =============================================================================
; src_name_eq: compare src[r8..r8+r9] with src[r10..r10+r11] -> rax 1/0
; =============================================================================
src_name_eq:
    cmp     r9, r11
    jne     .no
    mov     rbx, [src_buf_ptr]
    lea     rdi, [rbx+r8]
    lea     rsi, [rbx+r10]
    xor     rcx, rcx
.lp:
    cmp     rcx, r9
    jge     .yes
    mov     al, [rdi+rcx]
    cmp     al, [rsi+rcx]
    jne     .no
    inc     rcx
    jmp     .lp
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; =============================================================================
; lookup_const: r8=name_start, r9=name_len -> rax=value, rdx=1/0 (found)
; =============================================================================
lookup_const:
    push    rbx
    xor     rcx, rcx
.lc_lp:
    cmp     rcx, [cst_cnt]
    jge     .lc_no
    mov     rax, rcx
    imul    rax, rax, CST_SZ
    mov     rbx, [cst_tbl_ptr]
    add     rax, rbx        ; entry ptr in rax
    mov     r10, [rax]      ; entry.name_start
    mov     r11, [rax+8]    ; entry.name_len
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rbx
    cmp     rax, 1
    jne     .lc_nx
    mov     rax, [rbx+16]   ; value
    mov     edx, 1
    pop     rbx
    ret
.lc_nx:
    inc     rcx
    jmp     .lc_lp
.lc_no:
    xor     eax, eax
    xor     edx, edx
    pop     rbx
    ret

; =============================================================================
; lookup_struct: r8=ns, r9=nl -> rax=struct_index (-1=not found)
; =============================================================================
lookup_struct:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     rcx, rcx
.ls_lp:
    cmp     rcx, [stt_cnt]
    jge     .ls_no
    mov     rax, rcx
    imul    rax, rax, STR_SZ
    mov     rbx, [stt_tbl_ptr]
    add     rax, rbx
    mov     r12, [rax]      ; stored name_start
    mov     r13, [rax+8]    ; stored name_len
    cmp     r9, r13         ; compare lengths first
    jne     .ls_next
    ; compare bytes
    push    r14
    push    r15
    mov     r14, r8         ; src offset for lookup name
    mov     r15, r12        ; src offset for stored name
    mov     r11, [src_buf_ptr]
    add     r14, r11
    add     r15, r11
    xor     rdx, rdx        ; index
.ls_cmp:
    cmp     rdx, r9
    jge     .ls_found
    mov     al, [r14 + rdx]
    mov     bl, [r15 + rdx]
    cmp     al, bl
    jne     .ls_ne
    inc     rdx
    jmp     .ls_cmp
.ls_found:
    pop     r15
    pop     r14
    mov     rax, rcx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.ls_ne:
    pop     r15
    pop     r14
.ls_next:
    inc     rcx
    jmp     .ls_lp
.ls_no:
    mov     rax, -1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; get_elem_sz: rdi=tok_type, rsi=name_start_in_src -> rax=elem_byte_size
; Returns actual element size for arrays (i8->1, i32->4, i64->8, struct->size)
; =============================================================================
get_elem_sz:
    cmp     rdi, TOK_I8
    je      .r1
    cmp     rdi, TOK_I32
    je      .r4
    cmp     rdi, TOK_I64
    je      .r8
    cmp     rdi, TOK_F64
    je      .r8
    cmp     rdi, TOK_IDENT
    jne     .r8
    ; struct type: look up
    mov     r8, rsi
    ; need name len — we don't have it here, use 64 as max to find by start
    ; simplified: scan stt_tbl for entry with name_start == rsi
    xor     rcx, rcx
.gs_lp:
    cmp     rcx, [stt_cnt]
    jge     .r8
    mov     rax, rcx
    imul    rax, rax, STR_SZ
    mov     rbx, [stt_tbl_ptr]
    add     rax, rbx
    cmp     [rax], r8       ; name_start match
    jne     .gs_nx
    mov     rax, [rax+16]   ; total_size
    ret
.gs_nx:
    inc     rcx
    jmp     .gs_lp
.r1:
    mov     eax, 1
    ret
.r4:
    mov     eax, 4
    ret
.r8:
    mov     eax, 8
    ret

; =============================================================================
; P1_SCAN — Pass 1: scan token stream for const, struct, fn declarations
; =============================================================================
p1_scan:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     qword [tok_pos], 0
    mov     qword [cst_cnt], 0
    mov     qword [stt_cnt], 0
    mov     qword [fn_cnt],  0
    mov     qword [rbp-8],   0

.p1_loop:
    call    cur_tok_type
    cmp     rax, TOK_EOF
    je      .p1_done
    cmp     rax, TOK_CONST
    je      .p1_const
    cmp     rax, TOK_STRUCT
    je      .p1_struct
    cmp     rax, TOK_LET
    je      .p1_let
    cmp     rax, TOK_FN
    je      .p1_fn
    ; unknown token, skip
    call    adv_tok
    jmp     .p1_loop

; --- const NAME = VALUE ---
.p1_const:
    call    adv_tok         ; skip 'const'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; name_start
    mov     r13, [rax+16]   ; name_len
    call    adv_tok         ; skip NAME
    call    adv_tok         ; skip '='
    call    get_cur_tok_ptr
    mov     r14, [rax+24]   ; ival (integer value)
    call    adv_tok         ; skip VALUE
    ; store in cst_tbl
    mov     rax, [cst_cnt]
    imul    rax, rax, CST_SZ
    mov     rbx, [cst_tbl_ptr]
    add     rbx, rax
    mov     [rbx],    r12
    mov     [rbx+8],  r13
    mov     [rbx+16], r14
    mov     qword [rbx+24], 0
    inc     qword [cst_cnt]
    jmp     .p1_loop

; --- let NAME = VALUE ---
.p1_let:
    call    adv_tok         ; skip 'let'
    call    get_cur_tok_ptr
    mov     r14, [rax+8]    ; var name_start
    mov     r15, [rax+16]   ; var name_len
    call    adv_tok         ; skip NAME
    mov     qword [p1_glb_tkind], -1 ; type_id / tkind = unknown scalar
    mov     qword [p1_glb_sid], -1   ; sid = unknown
    mov     qword [p1_glb_esz], 8    ; esz = qword by default
    call    cur_tok_type
    cmp     rax, TOK_COLON
    jne     .p1_let_find_eq
    call    adv_tok         ; skip ':'
    xor     ebx, ebx        ; is_ptr = 0
    call    cur_tok_type
    cmp     rax, TOK_AMP
    jne     .p1_let_type_tok
    mov     ebx, 1
    call    adv_tok         ; skip '&'
.p1_let_type_tok:
    call    cur_tok_type
    cmp     rax, TOK_I8
    jne     .p1_let_type_i32
    cmp     ebx, 0
    je      .p1_let_find_eq
    mov     qword [p1_glb_tkind], TK_PTR
    mov     qword [p1_glb_esz], 1
    jmp     .p1_let_find_eq
.p1_let_type_i32:
    cmp     rax, TOK_I32
    jne     .p1_let_type_i64
    cmp     ebx, 0
    je      .p1_let_find_eq
    mov     qword [p1_glb_tkind], TK_PTR
    mov     qword [p1_glb_esz], 4
    jmp     .p1_let_find_eq
.p1_let_type_i64:
    cmp     rax, TOK_I64
    jne     .p1_let_type_f64
    cmp     ebx, 0
    je      .p1_let_find_eq
    mov     qword [p1_glb_tkind], TK_PTR
    mov     qword [p1_glb_esz], 8
    jmp     .p1_let_find_eq
.p1_let_type_f64:
    cmp     rax, TOK_F64
    jne     .p1_let_type_ident
    cmp     ebx, 0
    je      .p1_let_find_eq
    mov     qword [p1_glb_tkind], TK_PTR
    mov     qword [p1_glb_esz], 8
    jmp     .p1_let_find_eq
.p1_let_type_ident:
    cmp     rax, TOK_IDENT
    jne     .p1_let_find_eq
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    call    lookup_struct
    cmp     rax, -1
    je      .p1_let_find_eq
    cmp     ebx, 0
    je      .p1_let_find_eq
    mov     [p1_glb_sid], rax
    mov     qword [p1_glb_tkind], TK_PTR
    imul    rax, rax, STR_SZ
    mov     rdx, [stt_tbl_ptr]
    add     rax, rdx
    mov     rax, [rax+16]
    mov     [p1_glb_esz], rax
.p1_let_find_eq:
    call    cur_tok_type
    cmp     rax, TOK_EQ
    je      .p1_let_got_eq
    cmp     rax, TOK_EOF
    je      .p1_let_store
    call    adv_tok
    jmp     .p1_let_find_eq
.p1_let_got_eq:
    call    adv_tok         ; skip '='
    ; peek at the value token to see if it's a type name
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    push    r8
    push    r9
    call    lookup_struct
    pop     r9
    pop     r8
    cmp     rax, -1
    je      .p1_let_val_scalar
    ; it is a struct type!
    mov     [p1_glb_sid], rax
    mov     qword [p1_glb_tkind], TK_STRUCT
    imul    rax, rax, STR_SZ
    mov     rdx, [stt_tbl_ptr]
    add     rax, rdx
    mov     rax, [rax+16]   ; struct size
    mov     [p1_glb_esz], rax
.p1_let_val_scalar:
    call    adv_tok         ; skip the Type name or Value
    ; handle top-level initializers like Node{} and Node[16]
    call    cur_tok_type
    cmp     rax, TOK_LBRACE
    je      .p1_let_skip_brace_init
    cmp     rax, TOK_LBRACK
    je      .p1_let_skip_brack_init
    jmp     .p1_let_store
.p1_let_skip_brace_init:
    call    adv_tok         ; skip '{'
    mov     rcx, 1
.p1_let_brace_lp:
    call    cur_tok_type
    cmp     rax, TOK_EOF
    je      .p1_let_store
    cmp     rax, TOK_LBRACE
    jne     .p1_let_brace_r
    inc     rcx
    jmp     .p1_let_brace_adv
.p1_let_brace_r:
    cmp     rax, TOK_RBRACE
    jne     .p1_let_brace_adv
    dec     rcx
    cmp     rcx, 0
    je      .p1_let_brace_done
.p1_let_brace_adv:
    call    adv_tok
    jmp     .p1_let_brace_lp
.p1_let_brace_done:
    call    adv_tok         ; skip final '}'
    jmp     .p1_let_store
.p1_let_skip_brack_init:
    call    adv_tok         ; skip '['
    call    get_cur_tok_ptr
    mov     rax, [rax+24]   ; rax = array count (ival)
    imul    rax, qword [p1_glb_esz]
    mov     [p1_glb_esz], rax ; p1_glb_esz now holds total size
    call    adv_tok         ; skip count
    call    cur_tok_type
    cmp     rax, TOK_RBRACK
    jne     .p1_let_store
    call    adv_tok         ; skip ']'
    jmp     .p1_let_store
.p1_let_store:
    mov     r8, r14
    mov     r9, r15
    mov     r10, [p1_glb_tkind]
    mov     r11, [p1_glb_sid]
    mov     r12, [p1_glb_esz]
    call    add_global
    jmp     .p1_loop

; --- struct NAME { field:type ... } ---
.p1_struct:
    call    adv_tok         ; skip 'struct'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; struct name_start
    mov     r13, [rax+16]   ; struct name_len
    call    adv_tok         ; skip NAME
    call    adv_tok         ; skip '{'
    ; allocate struct entry
    mov     rax, [stt_cnt]
    imul    rax, rax, STR_SZ
    mov     r14, [stt_tbl_ptr]
    add     r14, rax        ; r14 = struct entry ptr
    mov     [r14],   r12
    mov     [r14+8], r13
    inc     qword [stt_cnt]
    mov     qword [r14+16], 0   ; total_size
    mov     qword [r14+24], 0   ; field_count
    xor     r15, r15            ; offset = 0
    xor     rbx, rbx            ; field_count = 0
.p1_sfld:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .p1_send
    cmp     rax, TOK_EOF
    je      .p1_send
    ; field name
    call    get_cur_tok_ptr
    mov     r8,  [rax+8]    ; field name_start
    mov     r9,  [rax+16]   ; field name_len
    push    r8
    push    r9
    call    adv_tok
    call    adv_tok         ; skip ':'
    ; possibly &
    xor     r13, r13        ; is_ptr=0
    call    cur_tok_type
    cmp     rax, TOK_AMP
    jne     .p1_no_amp
    mov     r13, 1
    call    adv_tok
.p1_no_amp:
    ; get type token
    call    get_cur_tok_ptr
    mov     r10, [rax]      ; type tok_type
    mov     rdx, [rax+8]    ; type name_start (save in rdx)
    mov     r12, [rax+16]   ; type name_len
    call    adv_tok
    ; compute elem_size (storage size) and type_id
    mov     rdi, -1         ; type_id default
    mov     rsi, 8          ; elem_size default
    cmp     r10, TOK_IDENT
    jne     .p1_type_scalar
    ; struct type: look up id, size (r8/r9 already on stack)
    push    r10             ; save type tok_type (lookup_struct clobbers r10/r11)
    mov     r8, rdx         ; type name_start
    mov     r9, r12         ; type name_len
    call    lookup_struct
    pop     r10             ; restore type tok_type
    mov     rdi, rax        ; struct id (or -1)
    cmp     rdi, -1
    jne     .p1_type_struct_ok
    ; fallback: handle builtin scalar names lexed as identifiers
    cmp     r12, 2
    jne     .p1_type_ident_len3
    mov     r11, [src_buf_ptr]
    mov     al, [r11 + rdx]
    cmp     al, 'i'
    jne     .p1_type_done
    mov     al, [r11 + rdx + 1]
    cmp     al, '8'
    jne     .p1_type_done
    mov     rdi, TOK_I8
    mov     rsi, 1
    jmp     .p1_type_done
.p1_type_ident_len3:
    cmp     r12, 3
    jne     .p1_type_done
    mov     r11, [src_buf_ptr]
    mov     al, [r11 + rdx]
    cmp     al, 'i'
    jne     .p1_type_ident_f64
    mov     al, [r11 + rdx + 1]
    cmp     al, '3'
    jne     .p1_type_ident_i64
    mov     al, [r11 + rdx + 2]
    cmp     al, '2'
    jne     .p1_type_done
    mov     rdi, TOK_I32
    mov     rsi, 4
    jmp     .p1_type_done
.p1_type_ident_i64:
    cmp     al, '6'
    jne     .p1_type_done
    mov     al, [r11 + rdx + 2]
    cmp     al, '4'
    jne     .p1_type_done
    mov     rdi, TOK_I64
    mov     rsi, 8
    jmp     .p1_type_done
.p1_type_ident_f64:
    cmp     al, 'f'
    jne     .p1_type_done
    mov     al, [r11 + rdx + 1]
    cmp     al, '6'
    jne     .p1_type_done
    mov     al, [r11 + rdx + 2]
    cmp     al, '4'
    jne     .p1_type_done
    mov     rdi, TOK_F64
    mov     rsi, 8
    jmp     .p1_type_done
.p1_type_struct_ok:
    mov     rax, rdi
    imul    rax, rax, STR_SZ
    mov     rcx, [stt_tbl_ptr]
    add     rax, rcx
    mov     rsi, [rax+16]   ; struct size
    jmp     .p1_type_done
.p1_type_scalar:
    mov     rdi, r10        ; type_id = scalar token
    cmp     r10, TOK_I8
    jne     .p1_type_i32
    mov     rsi, 1
    jmp     .p1_type_done
.p1_type_i32:
    cmp     r10, TOK_I32
    jne     .p1_type_done
    mov     rsi, 4
.p1_type_done:
    ; pointer field?
    cmp     r13, 0
    je      .p1_ptr_done
    ; pointer storage size = 8
    mov     rsi, 8
    ; mark pointer in type_id (set high bit)
    cmp     r10, TOK_IDENT
    jne     .p1_ptr_scalar
    bts     rdi, 63         ; set bit 63 (PTR_FLAG)
    jmp     .p1_ptr_done
.p1_ptr_scalar:
    mov     rdi, r10
    bts     rdi, 63         ; set bit 63 (PTR_FLAG)
.p1_ptr_done:
    mov     r12, rdi        ; save type_id
    ; check array
    push    rsi
    call    cur_tok_type
    pop     rsi
    xor     rdi, rdi        ; acnt = 0
    cmp     rax, TOK_LBRACK
    jne     .p1_noarr
    call    adv_tok
    call    get_cur_tok_ptr
    mov     rdi, [rax+24]   ; N
    call    adv_tok
    call    adv_tok         ; skip ']'
.p1_noarr:
    ; field size
    cmp     rdi, 0
    jne     .p1_arrsz
    mov     rdx, rsi
    jmp     .p1_got_fsz
.p1_arrsz:
    mov     rdx, rdi
    imul    rdx, rsi
.p1_got_fsz:
    ; write field entry: r14+32+rbx*FLD_SZ
    pop     r9
    pop     r8
    push    rdx
    mov     rax, rbx
    imul    rax, rax, FLD_SZ
    add     rax, 32
    lea     rcx, [r14+rax]  ; field entry ptr in rcx
    mov     [rcx],    r8    ; name_start
    mov     [rcx+8],  r9    ; name_len
    mov     [rcx+16], r15   ; offset
    mov     [rcx+24], rsi   ; elem_size
    mov     [rcx+32], rdi   ; acnt
    mov     [rcx+40], r12   ; type_id (may include PTR_FLAG)
    pop     rdx
    add     r15, rdx
    inc     rbx
    jmp     .p1_sfld
.p1_send:
    mov     [r14+16], r15   ; total_size
    mov     [r14+24], rbx   ; field_count
    call    adv_tok         ; skip '}'
    jmp     .p1_loop

; --- fn NAME(params) -> type { body } ---
.p1_fn:
    call    adv_tok         ; skip 'fn'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; fn name_start
    mov     r13, [rax+16]   ; fn name_len
    call    adv_tok         ; skip NAME
    ; allocate fn entry
    mov     rax, [rbp-8]
    imul    rax, rax, FN_SZ
    mov     r14, [fn_tbl_ptr]
    add     r14, rax
    mov     [r14],    r12   ; name_start
    mov     [r14+8],  r13   ; name_len
    mov     rax, [lbl_seq]
    mov     [r14+16], rax   ; lid
    inc     qword [lbl_seq]
    mov     qword [r14+24], 0   ; pcnt
    mov     qword [r14+32], 0   ; body_tok (fill in later)
    mov     qword [r14+40], -1  ; code_off
    mov     qword [r14+48], 0   ; ret_type
    ; parse params
    call    adv_tok         ; skip '('
    xor     rbx, rbx        ; param count
.p1_param:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .p1_param_done
    cmp     rax, TOK_EOF
    je      .p1_param_done
    ; param: NAME [':' TYPE]  (type annotation optional)
    call    get_cur_tok_ptr
    mov     r8,  [rax+8]
    mov     r9,  [rax+16]
    call    adv_tok         ; skip param name
    ; check for ':' — if not present, treat as untyped i64 scalar
    call    cur_tok_type
    cmp     rax, TOK_COLON
    jne     .p1_p_untyped
    call    adv_tok         ; skip ':'
    jmp     .p1_p_typed
.p1_p_untyped:
    ; untyped param: i64 scalar, size=8, type_id=-1
    xor     r13, r13        ; is_ptr=0
    mov     rdx, -1
    mov     rsi, 8
    jmp     .p1_p_no_ptr
.p1_p_typed:
    ; type (possibly &, then ident/keyword, possibly [N])
    xor     r13, r13        ; is_ptr=0
    call    cur_tok_type
    cmp     rax, TOK_AMP
    jne     .p1_p_no_amp
    mov     r13, 1
    call    adv_tok
.p1_p_no_amp:
    call    get_cur_tok_ptr
    mov     r10, [rax]      ; tok_type
    mov     r11, [rax+8]    ; name_start
    mov     r12, [rax+16]   ; name_len
    call    adv_tok         ; skip type keyword/ident
    ; check array suffix (array params treated as pointer)
    push    r10             ; save tok_type — cur_tok_type clobbers r10 via get_cur_tok_ptr
    call    cur_tok_type
    pop     r10             ; restore tok_type
    cmp     rax, TOK_LBRACK
    jne     .p1_p_no_arr
    mov     r13, 1
    call    adv_tok
    call    adv_tok         ; skip N
    call    adv_tok         ; skip ']'
.p1_p_no_arr:
    ; compute pointee size and type_id
    mov     rdx, -1         ; type_id default
    mov     rsi, 8          ; elem_size default
    cmp     r10, TOK_IDENT
    jne     .p1_p_type_scalar
    ; struct type: always treat params as pointer
    mov     r13, 1
    push    r8              ; save param name_start (r8/r9 clobbered by lookup_struct args)
    push    r9              ; save param name_len
    mov     r8, r11
    mov     r9, r12
    call    lookup_struct
    pop     r9              ; restore param name_len
    pop     r8              ; restore param name_start
    mov     rdx, rax        ; struct id (or -1)
    cmp     rdx, -1
    jne     .p1_p_type_struct_ok
    ; fallback: handle builtin scalar names lexed as identifiers
    cmp     r12, 2
    jne     .p1_p_type_ident_len3
    mov     r8, [src_buf_ptr]
    mov     al, [r8 + r11]
    cmp     al, 'i'
    jne     .p1_p_type_done
    mov     al, [r8 + r11 + 1]
    cmp     al, '8'
    jne     .p1_p_type_done
    mov     rdx, TOK_I8
    mov     rsi, 1
    jmp     .p1_p_type_done
.p1_p_type_ident_len3:
    cmp     r12, 3
    jne     .p1_p_type_done
    mov     r8, [src_buf_ptr]
    mov     al, [r8 + r11]
    cmp     al, 'i'
    jne     .p1_p_type_ident_f64
    mov     al, [r8 + r11 + 1]
    cmp     al, '3'
    jne     .p1_p_type_ident_i64
    mov     al, [r8 + r11 + 2]
    cmp     al, '2'
    jne     .p1_p_type_done
    mov     rdx, TOK_I32
    mov     rsi, 4
    jmp     .p1_p_type_done
.p1_p_type_ident_i64:
    cmp     al, '6'
    jne     .p1_p_type_done
    mov     al, [r8 + r11 + 2]
    cmp     al, '4'
    jne     .p1_p_type_done
    mov     rdx, TOK_I64
    mov     rsi, 8
    jmp     .p1_p_type_done
.p1_p_type_ident_f64:
    cmp     al, 'f'
    jne     .p1_p_type_done
    mov     al, [r8 + r11 + 1]
    cmp     al, '6'
    jne     .p1_p_type_done
    mov     al, [r8 + r11 + 2]
    cmp     al, '4'
    jne     .p1_p_type_done
    mov     rdx, TOK_F64
    mov     rsi, 8
    jmp     .p1_p_type_done
.p1_p_type_struct_ok:
    mov     rax, rdx
    imul    rax, rax, STR_SZ
    mov     rcx, [stt_tbl_ptr]
    add     rax, rcx
    mov     rsi, [rax+16]   ; struct size
    jmp     .p1_p_type_done
.p1_p_type_scalar:
    mov     rdx, r10        ; scalar type_id
    cmp     r10, TOK_I8
    jne     .p1_p_type_i32
    mov     rsi, 1
    jmp     .p1_p_type_done
.p1_p_type_i32:
    cmp     r10, TOK_I32
    jne     .p1_p_type_done
    mov     rsi, 4
.p1_p_type_done:
    ; if pointer, mark type_id (set high bit)
    cmp     r13, 0
    je      .p1_p_no_ptr
    cmp     r10, TOK_IDENT
    jne     .p1_p_ptr_scalar
    bts     rdx, 63         ; set bit 63 (PTR_FLAG)
    jmp     .p1_p_no_ptr
.p1_p_ptr_scalar:
    mov     rdx, r10
    bts     rdx, 63         ; set bit 63 (PTR_FLAG)
.p1_p_no_ptr:
    ; store param
    mov     rax, rbx
    imul    rax, rax, PRM_SZ
    add     rax, 64         ; params start at offset 64 in fn entry
    lea     rcx, [r14+rax]
    mov     [rcx],   r8
    mov     [rcx+8], r9
    mov     [rcx+16], rsi   ; elem_size (pointee for pointers)
    mov     [rcx+24], rdx   ; type_id (may include PTR_FLAG)
    inc     rbx
    ; skip comma
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .p1_param
    call    adv_tok
    jmp     .p1_param
.p1_param_done:
    mov     [r14+24], rbx   ; pcnt
    call    adv_tok         ; skip ')'
    ; optional -> return type: skip '->' then all tokens until '{' (handles '-> &Type')
    call    cur_tok_type
    cmp     rax, TOK_ARROW
    jne     .p1_no_ret
    call    adv_tok         ; skip '->'
.p1_skip_ret:
    call    cur_tok_type
    cmp     rax, TOK_LBRACE
    je      .p1_no_ret      ; found '{', stop
    cmp     rax, TOK_SEMI
    je      .p1_proto       ; forward declaration
    cmp     rax, TOK_EOF
    je      .p1_no_ret
    call    adv_tok
    jmp     .p1_skip_ret
.p1_proto:
    call    adv_tok         ; skip ';'
    inc     qword [rbp-8]   ; must count the prototype too!
    jmp     .p1_loop
.p1_no_ret:
    ; expect '{', record body start
    mov     rax, [tok_pos]
    inc     rax             ; body starts AFTER '{'
    mov     [r14+32], rax   ; body_tok
    call    adv_tok         ; skip '{'
    ; skip body by counting braces
    mov     r15, 1          ; depth
.p1_skip:
    call    cur_tok_type
    cmp     rax, TOK_EOF
    je      .p1_skip_done
    cmp     rax, TOK_LBRACE
    jne     .p1_skip_r
    inc     r15
    jmp     .p1_skip_adv
.p1_skip_r:
    cmp     rax, TOK_RBRACE
    jne     .p1_skip_adv
    dec     r15
    cmp     r15, 0
    je      .p1_skip_done
.p1_skip_adv:
    call    adv_tok
    jmp     .p1_skip
.p1_skip_done:
    call    adv_tok         ; skip final '}'
    inc     qword [rbp-8]
    jmp     .p1_loop

.p1_done:
    mov     rax, [rbp-8]
    mov     [fn_cnt], rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

; =============================================================================
; lookup_fn: r8=ns, r9=nl -> rax=fn entry ptr, or 0 if not found
; =============================================================================
lookup_fn:
    push    rbx
    mov     rcx, [fn_cnt]
    dec     rcx
.lf_lp:
    cmp     rcx, 0
    jl      .lf_no
    mov     rax, rcx
    imul    rax, rax, FN_SZ
    mov     rbx, [fn_tbl_ptr]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rbx
    cmp     rax, 1
    jne     .lf_nx
    mov     rax, rbx
    pop     rbx
    ret
.lf_nx:
    dec     rcx
    jmp     .lf_lp
.lf_no:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; find_field: rdi=struct_idx, r8=fn_start, r9=fn_len -> rax=field_entry ptr (or 0)
; =============================================================================
find_field:
    mov     rax, rdi
    imul    rax, rax, STR_SZ
    mov     rbx, [stt_tbl_ptr]
    add     rax, rbx        ; struct entry ptr
    mov     rcx, [rax+24]   ; field_count
    lea     r12, [rax+32]   ; fields start
    xor     rdx, rdx
.ff_lp:
    cmp     rdx, rcx
    jge     .ff_no
    mov     rax, rdx
    imul    rax, rax, FLD_SZ
    add     rax, r12        ; field entry ptr
    mov     r10, [rax]      ; field name_start
    mov     r11, [rax+8]    ; field name_len
    push    rax
    push    rdx
    push    rcx
    push    r12
    call    src_name_eq
    pop     r12
    pop     rcx
    pop     rdx
    pop     rbx
    cmp     rax, 1
    jne     .ff_nx
    mov     rax, rbx
    ret
.ff_nx:
    inc     rdx
    jmp     .ff_lp
.ff_no:
    xor     eax, eax
    ret

; =============================================================================
; add_local: r8=ns, r9=nl, r10=tkind, r11=sid, r12=esz -> rax=rbp_offset
; Adds to loc_tbl, updates loc_rbp
; =============================================================================
add_local:
    mov     rax, [loc_rbp]
    add     rax, 7
    and     rax, -8         ; align to 8
    ; alloc_size = max(effective_size, 8), but pointer locals always reserve 8 bytes
    mov     rdx, r12
    cmp     r10, TK_PTR
    jne     .al_size_ready
    mov     rdx, 8
.al_size_ready:
    cmp     rdx, 8
    jge     .al_big
    add     rax, 8
    jmp     .al_cont
.al_big:
    add     rax, rdx
.al_cont:
    mov     [loc_rbp], rax
    mov     rax, [loc_rbp]      ; rbp_offset = loc_rbp (positive, use [rbp-rax])
    cmp     rax, [loc_max_rbp]
    jbe     .al_skip_max
    mov     [loc_max_rbp], rax
.al_skip_max:
    mov     rcx, [loc_cnt]
    imul    rcx, rcx, LOC_SZ
    mov     rbx, [loc_tbl_ptr]
    add     rbx, rcx
    mov     [rbx],    r8
    mov     [rbx+8],  r9
    mov     [rbx+16], rax   ; rbp_offset
    mov     [rbx+24], r10   ; tkind
    mov     [rbx+32], r11   ; sid (struct index, or -1)
    mov     [rbx+40], r12   ; esz
    inc     qword [loc_cnt]
    ret

; =============================================================================
; lookup_local: r8=ns, r9=nl -> rax=loc entry ptr, or 0 if not found
; =============================================================================
lookup_local:
    xor     rcx, rcx
.ll_lp:
    cmp     rcx, [loc_cnt]
    jge     .ll_no
    mov     rax, rcx
    imul    rax, rax, LOC_SZ
    mov     rbx, [loc_tbl_ptr]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rbx
    cmp     rax, 1
    jne     .ll_nx
    mov     rax, rbx
    ret
.ll_nx:
    inc     rcx
    jmp     .ll_lp
.ll_no:
    xor     eax, eax
    ret

; =============================================================================
; add_global: r8=ns, r9=nl, r10=tkind, r11=sid, r12=esz -> rax=r15_offset
; =============================================================================
add_global:
    ; Align current offset to 8-byte boundary before allocating
    mov     rax, [glb_r15]
    add     rax, 7
    and     rax, -8
    mov     [glb_r15], rax
    mov     rcx, [glb_cnt]
    imul    rcx, rcx, GLB_SZ
    mov     rbx, [glb_tbl_ptr]
    add     rbx, rcx
    mov     [rbx],    r8
    mov     [rbx+8],  r9
    mov     [rbx+16], rax
    mov     [rbx+24], r10
    mov     [rbx+32], r11
    mov     [rbx+40], r12
    mov     r13, r12
    cmp     r10, TK_PTR
    jne     .ag_not_ptr
    mov     r13, 8          ; all pointers allocate 8 bytes
.ag_not_ptr:
    add     qword [glb_r15], r13
    inc     qword [glb_cnt]
    ret

; =============================================================================
; lookup_global: r8=ns, r9=nl -> rax=glb entry ptr, or 0
; =============================================================================
lookup_global:
    xor     rcx, rcx
.lg_lp:
    cmp     rcx, [glb_cnt]
    jge     .lg_no
    mov     rax, rcx
    imul    rax, rax, GLB_SZ
    mov     rbx, [glb_tbl_ptr]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rbx
    cmp     rax, 1
    jne     .lg_nx
    mov     rax, rbx
    ret
.lg_nx:
    inc     rcx
    jmp     .lg_lp
.lg_no:
    xor     eax, eax
    ret


; =============================================================================
; parse_reg_name: r8=name_start, r9=name_len -> rax=register code (0-15) or -1
; Maps register names (rax, rcx, rdx, rsi, rdi, rbx, rsp, rbp, r8-r15)
; =============================================================================
parse_reg_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rcx
    push    rdx
    cmp     r9, 0
    je      .prn_fail
    mov     al, byte [r8]
    cmp     al, 'r'
    jne     .prn_fail
    cmp     r9, 2
    je      .prn_2char
    cmp     r9, 3
    jge     .prn_3plus
    jmp     .prn_fail
.prn_2char:
    mov     cl, byte [r8+1]
    cmp     cl, 'a'
    je      .prn_set_0
    cmp     cl, 'c'
    je      .prn_set_1
    cmp     cl, 'd'
    je      .prn_set_2
    cmp     cl, 's'
    je      .prn_set_6
    cmp     cl, 'b'
    je      .prn_set_3
    jmp     .prn_fail
.prn_set_0:
    mov     eax, 0
    jmp     .prn_done
.prn_set_1:
    mov     eax, 1
    jmp     .prn_done
.prn_set_2:
    mov     eax, 2
    jmp     .prn_done
.prn_set_3:
    mov     eax, 3
    jmp     .prn_done
.prn_set_6:
    mov     eax, 6
    jmp     .prn_done
.prn_3plus:
    mov     cl, byte [r8+1]
    mov     dl, byte [r8+2]
    cmp     cl, 'd'
    je      .prn_di_or_dx
    cmp     cl, 's'
    je      .prn_si
    cmp     cl, 'b'
    je      .prn_bp_sp
    cmp     cl, '8'
    je      .prn_check_r8
    cmp     cl, '9'
    je      .prn_check_r9
    cmp     cl, '1'
    je      .prn_r1x
    jmp     .prn_fail
.prn_di_or_dx:
    cmp     dl, 'i'
    je      .prn_set_7      ; rdi
    cmp     dl, 'x'
    jne     .prn_fail
    mov     eax, 2          ; rdx
    jmp     .prn_done
.prn_si:
    cmp     dl, 'i'
    jne     .prn_fail
    mov     eax, 6          ; rsi
    jmp     .prn_done
.prn_set_7:
    mov     eax, 7
    jmp     .prn_done
.prn_bp_sp:
    cmp     dl, 'p'
    je      .prn_set_5
    cmp     dl, 's'
    je      .prn_set_4
    jmp     .prn_fail
.prn_set_4:
    mov     eax, 4
    jmp     .prn_done
.prn_set_5:
    mov     eax, 5
    jmp     .prn_done
.prn_check_r8:
    cmp     r9, 2
    jne     .prn_fail
    mov     eax, 8
    jmp     .prn_done
.prn_check_r9:
    cmp     r9, 2
    jne     .prn_fail
    mov     eax, 9
    jmp     .prn_done
.prn_r1x:
    cmp     r9, 3
    jne     .prn_fail
    mov     al, byte [r8+2]
    cmp     al, '0'
    je      .prn_set_10
    cmp     al, '1'
    je      .prn_set_11
    cmp     al, '2'
    je      .prn_set_12
    cmp     al, '3'
    je      .prn_set_13
    cmp     al, '4'
    je      .prn_set_14
    cmp     al, '5'
    je      .prn_set_15
    jmp     .prn_fail
.prn_set_10:
    mov     eax, 10
    jmp     .prn_done
.prn_set_11:
    mov     eax, 11
    jmp     .prn_done
.prn_set_12:
    mov     eax, 12
    jmp     .prn_done
.prn_set_13:
    mov     eax, 13
    jmp     .prn_done
.prn_set_14:
    mov     eax, 14
    jmp     .prn_done
.prn_set_15:
    mov     eax, 15
    jmp     .prn_done
.prn_fail:
    mov     eax, -1
.prn_done:
    pop     rdx
    pop     rcx
    pop     rbx
    leave
    ret

; =============================================================================
; gen_expr — evaluate expression into rax; advances tok_pos
; Handles: INT, CHAR, STR, IDENT (local/global/const/fn-call), unary-, &, binary ops
; Note: complex LHS.field and x[i] are handled by gen_lvalue/gen_field
; =============================================================================
; =============================================================================
; gen_expr — evaluate expression into rax (TOP LEVEL: handles 'or')
; =============================================================================
gen_expr:
    push    rbp
    mov     rbp, rsp
    push    r14
    ; Reset lvalue metadata so callers (e.g. gs_let_expr) don't see stale values
    mov     qword [lv_sid], -1
    mov     qword [lv_esz], 8
    mov     qword [lv_isptr], 0
    mov     qword [lv_glb], 0
    call    gen_expr_and
.lp:
    call    cur_tok_type
    cmp     rax, TOK_OR
    jne     .done
    call    adv_tok
    ; short circuit: if rax!=0 skip rhs
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     r14, [cod_len]
    mov     rdi, 0
    call    emit4  ; placeholder rel32
    call    gen_expr_and
    ; patch
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r14
    mov     [rbx], eax
    ; normalize result to 0/1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x95
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; setnz al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; movzx rax, al
    jmp     .lp
.done:
    pop     r14
    leave
    ret

; =============================================================================
; gen_expr_and — handles 'and'
; =============================================================================
gen_expr_and:
    push    rbp
    mov     rbp, rsp
    push    r14
    call    gen_expr_cmp
.lp:
    call    cur_tok_type
    cmp     rax, TOK_AND
    jne     .done
    call    adv_tok
    ; short circuit: if rax==0 skip rhs
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1
    mov     r14, [cod_len]
    mov     rdi, 0
    call    emit4  ; placeholder rel32
    call    gen_expr_cmp
    ; patch
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r14
    mov     [rbx], eax
    ; normalize result to 0/1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x95
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; setnz al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; movzx rax, al
    jmp     .lp
.done:
    pop     r14
    leave
    ret

; =============================================================================
; gen_expr_cmp — handles ==, !=, <, >, <=, >=
; =============================================================================
gen_expr_cmp:
    push    rbp
    mov     rbp, rsp
    push    r12
    call    gen_expr_base
.lp:
    call    cur_tok_type
    mov     r12, rax        ; operator token
    cmp     rax, TOK_EQEQ
    je      .do_cmp
    cmp     rax, TOK_NEQ
    je      .do_cmp
    cmp     rax, TOK_LT
    je      .do_cmp
    cmp     rax, TOK_GT
    je      .do_cmp
    cmp     rax, TOK_LTEQ
    je      .do_cmp
    cmp     rax, TOK_GTEQ
    je      .do_cmp
    jmp     .done
.do_cmp:
    call    adv_tok
    mov     rdi, 0x50       ; push rax (LHS)
    call    emit1
    call    gen_expr_base   ; RHS -> rax at runtime
    mov     rdi, 0x5B       ; pop rbx (LHS) at runtime
    call    emit1
    ; cmp rbx, rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    ; setCC al based on r12 (operator)
    mov     rax, r12
    cmp     rax, TOK_EQEQ
    je      .eq
    cmp     rax, TOK_NEQ
    je      .ne
    cmp     rax, TOK_LT
    je      .lt
    cmp     rax, TOK_GT
    je      .gt
    cmp     rax, TOK_LTEQ
    je      .le
    cmp     rax, TOK_GTEQ
    je      .ge
.eq: mov rdi, 0x94
jmp .sc
.ne: mov rdi, 0x95
jmp .sc
.lt: mov rdi, 0x9C
jmp .sc
.gt: mov rdi, 0x9F
jmp .sc
.le: mov rdi, 0x9E
jmp .sc
.ge: mov rdi, 0x9D
jmp .sc
.sc:
    push    rdi
    mov     rdi, 0x0F
    call    emit1
    pop     rdi
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    ; movzx rax, al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .lp
.done:
    pop     r12
    leave
    ret

; =============================================================================
; gen_expr_base — handles arithmetic, bitwise, literals, idents, parens, unary
; =============================================================================
gen_expr_base:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8          ; align

    call    cur_tok_type
    ; --- Integer literal ---
    cmp     rax, TOK_INT
    jne     .not_int
    call    get_cur_tok_ptr
    mov     r12, [rax+24]   ; ival
    call    adv_tok
    ; emit: mov rax, imm64
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, r12
    call    emit8
    jmp     .maybe_binary

.not_int:
    ; --- Char literal ---
    cmp     rax, TOK_CHAR
    jne     .not_char
    call    get_cur_tok_ptr
    mov     r12, [rax+24]
    call    adv_tok
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, r12
    call    emit8
    jmp     .maybe_binary

.not_char:
    ; --- String literal ---
    cmp     rax, TOK_STR
    jne     .not_str
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; str_start in src
    mov     r13, [rax+16]   ; str_len
    call    adv_tok
    ; copy string to sdt_buf, get offset
    mov     r14, [sdt_len]  ; r14 = current sdt offset (future rip-relative)
    ; copy src[r12..r12+r13] to sdt_buf[sdt_len..]
    mov     rbx, [src_buf_ptr]
    add     rbx, r12
    mov     rcx, [sdt_buf_ptr]
    add     rcx, [sdt_len]
    push    r13
.sdt_cp:
    cmp     r13, 0
    je      .sdt_cp_done
    ; handle escape sequences
    mov     al, [rbx]
    cmp     al, '\'
    jne     .sdt_plain
    inc     rbx
    dec     r13
    cmp     r13, 0
    je      .sdt_cp_done
    mov     al, [rbx]
    cmp     al, 'n'
    jne     .sdt_esc2
    mov     al, 10
    jmp     .sdt_store
.sdt_esc2:
    cmp     al, 't'
    jne     .sdt_esc3
    mov     al, 9
    jmp     .sdt_store
.sdt_esc3:
    cmp     al, 'r'
    jne     .sdt_esc4
    mov     al, 13
    jmp     .sdt_store
.sdt_esc4:
    cmp     al, '0'
    jne     .sdt_store
    xor     al, al
.sdt_store:
.sdt_plain:
    mov     [rcx], al
    inc     rbx
    inc     rcx
    add     qword [sdt_len], 1
    dec     r13
    jmp     .sdt_cp
.sdt_cp_done:
    ; null-terminate
    mov     byte [rcx], 0
    add     qword [sdt_len], 1
    pop     r13
    ; emit: lea rax, [rip + str_rip_rel]
    ; We'll emit LEA with a placeholder, record as string fixup
    ; emit 48 8D 05 XX XX XX XX (lea rax, [rip+rel32])
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x05
    call    emit1
    ; record fixup: patch_off=cod_len, target=sdt_buf offset r14
    ; For now emit placeholder 0 — we patch at ELF write time
    ; Store as string fixup: {cod_off, sdt_off} in sfx_tbl, indexed by sfix_cnt
    mov     rax, [sfix_cnt]
    imul    rax, rax, 16
    mov     rbx, [sfx_tbl_ptr]
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax      ; code offset of rel32
    mov     [rbx+8], r14    ; sdt offset
    inc     qword [sfix_cnt]
    mov     rdi, 0
    call    emit4           ; placeholder rel32
    jmp     .maybe_binary

.not_str:
    ; --- Unary minus ---
    cmp     rax, TOK_MINUS
    jne     .not_neg
    call    adv_tok
    call    gen_expr_base   ; unary minus binds tighter than binary ops
    ; emit: neg rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xF7
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    jmp     .maybe_binary

.not_neg:
    ; --- Address-of &x ---
    cmp     rax, TOK_AMP
    jne     .not_amp
    call    adv_tok             ; skip '&'
    call    gen_addr
    ; For &scalar (lv_isptr=0): gen_addr emits lea, keep the stack address.
    ; For &ptr (lv_isptr=1): emit mov rax,[rax] to load the heap pointer.
    cmp     qword [lv_isptr], 0
    je      .amp_done
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
.amp_done:
    jmp     .maybe_binary

.not_amp:
    ; --- Dereference *ptr ---
    cmp     rax, TOK_STAR
    jne     .not_deref
    call    adv_tok             ; skip '*'
    call    gen_expr_base       ; evaluate ptr expr → rax
    ; emit: mov rax, [rax]  (load from address)
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    jmp     .maybe_binary

.not_deref:
    ; --- Parenthesized expression (expr) ---
    cmp     rax, TOK_LPAREN
    jne     .not_lparen
    call    adv_tok             ; skip '('
    movzx   r13, byte [prec_stop]
    movzx   r12, byte [arith_stop]
    mov     byte [prec_stop], 0 ; inside parens: allow all ops
    mov     byte [arith_stop], 0
    call    gen_expr            ; evaluate inner expr → rax
    mov     byte [prec_stop], r13b ; restore
    mov     byte [arith_stop], r12b
    call    adv_tok             ; skip ')'
    jmp     .maybe_binary
.not_lparen:
    ; --- Identifier: local, global, const, or function call ---
    cmp     rax, TOK_IDENT
    je      .do_ident
    cmp     rax, TOK_PRINT
    je      .do_ident
    cmp     rax, TOK_SYSCALL
    je      .do_syscall_expr
    cmp     rax, TOK_ALLOC_PAGES
    je      .do_alloc_pages
    jmp     .literal_done

.do_alloc_pages:
    call    adv_tok         ; skip 'alloc_pages'
    call    adv_tok         ; skip '('
    call    gen_expr        ; n -> rax
    call    adv_tok         ; skip ')'
    ; emit: size = n * 4096 (shl rax, 12)
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC1
    call    emit1
    mov     rdi, 0xE0
    call    emit1
    mov     rdi, 0x0C
    call    emit1
    ; mmap(0, size, PROT_READ|PROT_WRITE=3, MAP_PRIVATE|MAP_ANON=0x22, -1, 0)
    ; nr=9, rdi=0, rsi=size, rdx=3, r10=0x22, r8=-1, r9=0
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC6       ; mov rsi, rax
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF       ; xor rdi, rdi
    call    emit1
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 3          ; mov edx, 3
    call    emit4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 0x22       ; mov r10d, 0x22
    call    emit4
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, -1
    call    emit4           ; mov r8, -1 (sign-extended imm32 to 64-bit)
    mov     rdi, 0x45
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9       ; xor r9d, r9d
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 9          ; mov eax, 9
    call    emit4
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05       ; syscall
    call    emit1
    jmp     .maybe_binary

.do_ident:
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; name_start
    mov     r13, [rax+16]   ; name_len
    mov     r14, [tok_pos]
    call    adv_tok
    ; peek: if next is '(', it's a function call
    call    cur_tok_type
    cmp     rax, TOK_LPAREN
    je      .do_call
    ; if next is '.' or '[', parse lvalue chain
    cmp     rax, TOK_DOT
    je      .do_lvalue
    cmp     rax, TOK_LBRACK
    je      .do_lvalue
    ; simple ident: try local/global, else const
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    jne     .do_lvalue
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    jne     .do_lvalue
    mov     r8, r12
    mov     r9, r13
    call    lookup_const
    cmp     rdx, 1
    jne     .try_fn
    ; emit: mov rax, imm64
    mov     r12, rax        ; const value
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, r12
    call    emit8
    jmp     .maybe_binary

.do_lvalue:
    mov     [tok_pos], r14  ; rewind to ident
    call    gen_addr
    ; if pointer value, load it
    cmp     qword [lv_isptr], 0
    jne     .lv_load_ptr
    ; struct value? return address
    mov     rax, [lv_sid]
    cmp     rax, -1
    jne     .maybe_binary
    ; scalar load based on lv_esz
    mov     r15, [lv_esz]
    cmp     r15, 1
    je      .lv_load_u8
    cmp     r15, 4
    je      .lv_load_u32
    ; load 8
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    jmp     .maybe_binary
.lv_load_u8:
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0x00
    call    emit1
    jmp     .maybe_binary
.lv_load_u32:
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    jmp     .maybe_binary
.lv_load_ptr:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    jmp     .maybe_binary

.try_fn:
    ; Unknown ident — just emit 0 (error recovery)
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_call:
    ; fn call: NAME(arg0, arg1, ...) — up to 6 args
    call    adv_tok         ; skip '('
    push    r12
    push    r13
    xor     r14, r14        ; arg count
.call_arg_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .call_done_args
    cmp     rax, TOK_EOF
    je      .call_done_args
    call    gen_expr        ; TOP LEVEL
    mov     rdi, 0x50       ; push rax
    call    emit1
    inc     r14
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .call_arg_loop
    call    adv_tok
    jmp     .call_arg_loop
.call_done_args:
    call    adv_tok         ; skip ')'
    ; --- FIX: Resolve fn target BEFORE popping r8/r9 arg registers ---
    push    r12
    push    r13
    mov     r8, r12
    mov     r9, r13
    call    lookup_fn
    mov     r11, rax        ; save fn entry ptr in r11
    pop     r13
    pop     r12
    ; restore fn name saved by .do_call push r12/r13 (lines 3024-3025)
    pop     r13
    pop     r12
    ; -----------------------------------------------------------------
    ; pop into arg regs (rdi, rsi, rdx, rcx, r8, r9)
    cmp     r14, 6
    jl      .cpop5
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59
    call    emit1 ; pop r9
.cpop5:
    cmp     r14, 5
    jl      .cpop4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58
    call    emit1 ; pop r8
.cpop4:
    cmp     r14, 4
    jl      .cpop3
    mov     rdi, 0x59
    call    emit1 ; pop rcx
.cpop3:
    cmp     r14, 3
    jl      .cpop2
    mov     rdi, 0x5A
    call    emit1 ; pop rdx
.cpop2:
    cmp     r14, 2
    jl      .cpop1
    mov     rdi, 0x5E
    call    emit1 ; pop rsi
.cpop1:
    cmp     r14, 1
    jl      .call_emit_done
    mov     rdi, 0x5F
    call    emit1 ; pop rdi
.call_emit_done:
    ; we already have fn in r11, just need to push/pop name info for the fixup if needed
    push    r12
    push    r13
    push    r14
    mov     rdi, 0xE8
    call    emit1
    cmp     r11, 0
    je      .call_unknown
    mov     rbx, r11
    cmp     qword [rbx+40], -1
    je      .call_unknown
    mov     r15, [rbx+40]
    mov     rax, [cod_len]
    add     rax, 4
    sub     r15, rax
    mov     rdi, r15
    call    emit4
    jmp     .call_emit_ret
.call_unknown:
    mov     rax, [fix_cnt]
    imul    rax, rax, 32
    mov     rbx, [fix_buf_ptr]
    add     rbx, 8192
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    mov     [rbx+8], r12
    mov     [rbx+16], r13
    mov     qword [rbx+24], 1
    inc     qword [fix_cnt]
    mov     rdi, 0
    call    emit4
.call_emit_ret:
    pop     r14
    pop     r13
    pop     r12
    jmp     .maybe_binary

.do_syscall_expr:
    call    gen_syscall
    jmp     .maybe_binary

.literal_done:
    call    adv_tok
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC0
    call    emit1

.maybe_binary:
    call    cur_tok_type
    ; Skip type annotations in expressions
    cmp     rax, TOK_COLON
    jne     .mb_not_type_ann
    call    adv_tok         ; skip ':'
    ; skip possible '&'
    call    cur_tok_type
    cmp     rax, TOK_AMP
    jne     .mb_type_ann_name
    call    adv_tok         ; skip '&'
.mb_type_ann_name:
    call    adv_tok         ; skip TYPE name
    jmp     .maybe_binary

.mb_not_type_ann:
    movzx   r13, byte [arith_stop]
    cmp     r13, 0
    je      .mb_chk_plus_minus
    cmp     rax, TOK_PLUS
    je      .expr_done
    cmp     rax, TOK_MINUS
    je      .expr_done
.mb_chk_plus_minus:
    cmp     rax, TOK_PLUS
    je      .do_add
    cmp     rax, TOK_MINUS
    je      .do_sub
    cmp     rax, TOK_STAR
    je      .do_mul
    cmp     rax, TOK_SLASH
    je      .do_div
    cmp     rax, TOK_PIPE
    je      .do_bitor
    cmp     rax, TOK_AMP
    je      .do_bitand
    cmp     rax, TOK_SHL
    je      .do_shl
    cmp     rax, TOK_SHR
    je      .do_shr
    ; Handle 'as' cast: expr as [&]Type -> update lv_sid/lv_esz/lv_isptr, no code emitted
    cmp     rax, TOK_IDENT
    jne     .expr_done
    call    get_cur_tok_ptr
    cmp     qword [rax+16], 2       ; name_len == 2?
    jne     .expr_done
    mov     rbx, [rax+8]            ; name_start (offset in src_buf)
    mov     rcx, [src_buf_ptr]
    add     rcx, rbx
    cmp     byte [rcx], 'a'
    jne     .expr_done
    cmp     byte [rcx+1], 's'
    jne     .expr_done
    ; confirmed "as" — consume it
    call    adv_tok
    call    cur_tok_type
    mov     r14, 0                  ; is_ptr = 0
    cmp     rax, TOK_AMP
    jne     .as_chk_type
    mov     r14, 1
    call    adv_tok                 ; skip '&'
.as_chk_type:
    call    cur_tok_type
    ; handle scalar primitive types
    cmp     rax, TOK_I64
    jne     .as_chk_i32
    call    adv_tok
    mov     qword [lv_sid], -1
    mov     qword [lv_esz], 8
    jmp     .as_ptr_done
.as_chk_i32:
    cmp     rax, TOK_I32
    jne     .as_chk_i8
    call    adv_tok
    mov     qword [lv_sid], -1
    mov     qword [lv_esz], 4
    jmp     .as_ptr_done
.as_chk_i8:
    cmp     rax, TOK_I8
    jne     .as_chk_struct
    call    adv_tok
    mov     qword [lv_sid], -1
    mov     qword [lv_esz], 1
    jmp     .as_ptr_done
.as_chk_struct:
    cmp     rax, TOK_IDENT
    jne     .as_cast_done
    call    get_cur_tok_ptr
    mov     r8, [rax+8]             ; name_start
    mov     r9, [rax+16]            ; name_len
    call    adv_tok                 ; skip type name
    call    lookup_struct
    cmp     rax, -1
    je      .as_cast_done
    ; struct found: compute struct size from table entry
    mov     r15, rax                ; save struct index
    imul    rax, rax, STR_SZ
    mov     rbx, [stt_tbl_ptr]
    add     rax, rbx
    mov     rax, [rax+16]           ; struct size
    mov     [lv_esz], rax
    mov     [lv_sid], r15
    jmp     .as_ptr_done
.as_ptr_done:
    cmp     r14, 0
    je      .as_cast_done
    mov     qword [lv_isptr], 1
.as_cast_done:
    jmp     .expr_done

.do_add:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x01
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    jmp     .maybe_binary
.do_sub:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x29
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    jmp     .maybe_binary
.do_mul:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [arith_stop]
    mov     byte [arith_stop], 1
    call    gen_expr_base
    mov     byte [arith_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xAF
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    jmp     .maybe_binary
.do_div:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [arith_stop]
    mov     byte [arith_stop], 1
    call    gen_expr_base
    mov     byte [arith_stop], r13b
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC3
    call    emit1 ; mov rbx, rax
    mov     rdi, 0x58
    call    emit1 ; pop rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x99
    call    emit1 ; cqo
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xF7
    call    emit1
    mov     rdi, 0xFB
    call    emit1 ; idiv rbx
    jmp     .maybe_binary
.do_cmp_eq:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2  ; RHS of == must not consume or/and
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    ; cmp rbx, rax; sete al; movzx rax, al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x94
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_cmp_ne:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x95
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_cmp_lt:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    ; cmp rbx, rax; setl al; movzx rax, al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x9C
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_cmp_gt:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    ; cmp rbx, rax; setg al
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x9F
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_cmp_le:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x9E
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_cmp_ge:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2
    call    gen_expr
    mov     byte [prec_stop], r13b
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x39
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x9D
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_and:
    ; short circuit: if rax==0 skip rhs
    call    adv_tok
    ; emit: test rax,rax; jz rel32 skip; eval rhs; skip:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1  ; jz rel32 (2-byte opcode)
    mov     r14, [cod_len]
    mov     rdi, 0
    call    emit4  ; 4-byte placeholder rel32
    push    r14            ; save patch position
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 2  ; RHS of 'and': stop before or/and
    call    gen_expr
    mov     byte [prec_stop], r13b
    pop     r14            ; restore patch position
    ; patch rel32: offset = cod_len - (patch_pos + 4)
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r14
    mov     [rbx], eax     ; store 32-bit offset
    jmp     .maybe_binary

.do_or:
    call    adv_tok
    ; emit: test rax,rax; jnz rel32 skip; eval rhs; skip:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1  ; test rax,rax
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x85
    call    emit1  ; jnz rel32 (2-byte opcode)
    mov     r14, [cod_len]
    mov     rdi, 0
    call    emit4  ; 4-byte placeholder rel32
    push    r14            ; save patch position
    movzx   r13, byte [prec_stop]
    mov     byte [prec_stop], 1  ; RHS of 'or': stop before or, allow and
    call    gen_expr
    mov     byte [prec_stop], r13b
    pop     r14            ; restore patch position
    ; patch rel32: offset = cod_len - (patch_pos + 4)
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r14
    mov     [rbx], eax     ; store 32-bit offset
    jmp     .maybe_binary

.do_bitor:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0B
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    jmp     .maybe_binary
.do_bitand:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x23
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    jmp     .maybe_binary
.do_shl:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC1
    call    emit1 ; mov rcx, rax
    mov     rdi, 0x58
    call    emit1 ; pop rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xD3
    call    emit1
    mov     rdi, 0xE0
    call    emit1 ; shl rax, cl
    jmp     .maybe_binary
.do_shr:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr_base
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC1
    call    emit1 ; mov rcx, rax
    mov     rdi, 0x58
    call    emit1 ; pop rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xD3
    call    emit1
    mov     rdi, 0xE8
    call    emit1 ; shr rax, cl
    jmp     .maybe_binary

.expr_done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    leave
    ret
; =============================================================================
; gen_addr — generate address of next identifier/field into rax
; =============================================================================
gen_addr:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     qword [lv_sid], -1
    mov     qword [lv_esz], 8
    mov     qword [lv_isptr], 0

    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    ; look up local
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    je      .ga_global
    mov     r14, [rax+16]   ; rbp_offset
    mov     r15, [rax+24]   ; tkind
    mov     rdx, [rax+32]   ; sid
    mov     rcx, [rax+40]   ; esz
    mov     [lv_sid], rdx
    mov     [lv_esz], rcx
    cmp     r15, TK_PTR
    jne     .ga_local_addr
    mov     qword [lv_isptr], 1
.ga_local_addr:
    ; emit: lea rax, [rbp - off]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r14
    mov     rdi, r14
    call    emit4
    jmp     .ga_post

.ga_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .ga_done
    mov     [lv_glb], rax
    mov     r14, [rax+16]
    mov     r15, [rax+24]
    mov     rdx, [rax+32]
    mov     rcx, [rax+40]
    mov     [lv_sid], rdx
    mov     [lv_esz], rcx
    cmp     r15, TK_PTR
    jne     .ga_glb_addr
    mov     qword [lv_isptr], 1
.ga_glb_addr:
    ; emit: lea rax, [r15 + off]
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x87
    call    emit1
    mov     rdi, r14        ; actual offset from lookup_global
    call    emit4


.ga_post:
    mov     qword [ga_from_dot], 0
    mov     qword [ga_acnt], 0
    ; Check if navigation (. or [) follows — needed to decide pointer deref behavior.
    call    cur_tok_type
    cmp     rax, TOK_DOT
    je      .ga_post_nav
    cmp     rax, TOK_LBRACK
    je      .ga_post_nav
    ; NO navigation: struct locals return their stack address as-is;
    ; pointer and scalar locals also return stack addr — caller loads the value.
    cmp     qword [lv_sid], -1
    jne     .ga_post_loop       ; struct local
    jmp     .ga_post_loop       ; scalar/pointer: caller (.do_lvalue) loads the value
.ga_post_nav:
    cmp     qword [lv_isptr], 0
    jne     .ga_post_do_deref   ; pointer -> deref
    cmp     qword [lv_sid], -1
    je      .ga_post_do_deref   ; scalar -> deref
    ; it is a struct or array. Is it global or local?
    cmp     qword [lv_glb], 0
    jne     .ga_post_loop       ; global struct is inline -> NO deref
    ; local struct is an mmap pointer on the stack -> MUST deref!
    jmp     .ga_post_do_deref
.ga_post_do_deref:
    ; emit: mov rax, [rax]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    mov     qword [lv_isptr], 0
.ga_post_loop:
    call    cur_tok_type
    cmp     rax, TOK_DOT
    je      .ga_dot
    cmp     rax, TOK_LBRACK
    je      .ga_pre_index
    jmp     .ga_done

.ga_pre_index:
    ; Before array indexing after a dot, deref to load the stored pointer/value
    ; UNLESS it's an embedded array (ga_acnt > 0) — data is inline at field addr.
    ; Examples:
    ;   block.children[i]  (children: i64)       → acnt=0  → deref  ✓
    ;   jfn.strtab[i]      (strtab: &i8)         → acnt=0  → deref  ✓
    ;   jfn.blocks[i]      (blocks: BB[64])      → acnt=64 → skip   ✓
    ;   ctx.ra.pool[i]     (pool: i32[8])        → acnt=8  → skip   ✓
    cmp     qword [ga_from_dot], 0
    je      .ga_index               ; not from dot → no deref needed
    mov     qword [ga_from_dot], 0
    cmp     qword [ga_acnt], 0
    jne     .ga_index               ; embedded array (acnt>0) → no deref
    ; scalar or pointer field → deref to load the base address
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1           ; mov rax, [rax]
    mov     qword [lv_isptr], 0
    jmp     .ga_index

.ga_dot:
    call    adv_tok         ; skip '.'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    mov     rdx, [lv_sid]
    cmp     rdx, -1
    je      .ga_post_loop
    mov     rdi, rdx
    mov     r8, r12
    mov     r9, r13
    call    find_field
    cmp     rax, 0
    je      .ga_post_loop
    mov     r14, [rax+16]   ; field offset
    mov     r15, [rax+24]   ; elem_size
    mov     r13, [rax+40]   ; type_id (use r13 — emit1 clobbers rbx!)
    push    rdi
    mov     rdi, [rax+32]   ; acnt
    mov     [ga_acnt], rdi
    pop     rdi
    ; emit: add rax, field_off
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x81
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, r14
    call    emit4
    mov     [lv_esz], r15
    mov     qword [lv_sid], -1
    mov     qword [lv_isptr], 0
    mov     qword [ga_from_dot], 1  ; flag: field address needs deref before [
    ; small non-pointer fields are scalars even if type_id is unknown
    cmp     r15, 8
    jg      .ga_type_check
    bt      r13, 63
    jc      .ga_type_check
    jmp     .ga_post_loop
.ga_type_check:
    cmp     r13, -1
    je      .ga_post_loop
    bt      r13, 63         ; test PTR_FLAG (bit 63) — test reg,imm64 broken in x86
    jnc     .ga_dot_struct
    ; pointer field
    mov     qword [lv_isptr], 1
    mov     rdx, r13
    shl     rdx, 1
    shr     rdx, 1          ; clear PTR_FLAG
    cmp     rdx, TOK_I8
    je      .ga_ptr_i8
    cmp     rdx, TOK_I32
    je      .ga_ptr_i32
    cmp     rdx, TOK_I64
    je      .ga_ptr_i64
    cmp     rdx, TOK_F64
    je      .ga_ptr_i64
    ; struct pointer
    mov     [lv_sid], rdx
    mov     rax, rdx
    imul    rax, rax, STR_SZ
    mov     r15, [stt_tbl_ptr]
    add     rax, r15
    mov     r15, [rax+16]
    mov     [lv_esz], r15
    jmp     .ga_post_loop
.ga_ptr_i8:
    mov     qword [lv_esz], 1
    jmp     .ga_post_loop
.ga_ptr_i32:
    mov     qword [lv_esz], 4
    jmp     .ga_post_loop
.ga_ptr_i64:
    mov     qword [lv_esz], 8
    jmp     .ga_post_loop
.ga_dot_struct:
    ; non-pointer field: only structs carry a valid sid
    cmp     r13, TOK_I8
    je      .ga_post_loop
    cmp     r13, TOK_I32
    je      .ga_post_loop
    cmp     r13, TOK_I64
    je      .ga_post_loop
    cmp     r13, TOK_F64
    je      .ga_post_loop
    mov     [lv_sid], r13
    jmp     .ga_post_loop

.ga_index:
    call    adv_tok         ; skip '['
    ; --- Save state because gen_expr might call gen_addr recursively ---
    push    qword [lv_sid]
    push    qword [lv_esz]
    push    qword [lv_isptr]
    ; push base
    mov     rdi, 0x50
    call    emit1
    ; index expr
    mov     rax, [lv_sid]
    push    rax
    mov     rax, [lv_esz]
    push    rax
    mov     rax, [lv_isptr]
    push    rax
    call    gen_expr
    pop     rax
    mov     [lv_isptr], rax
    pop     rax
    mov     [lv_esz], rax
    pop     rax
    mov     [lv_sid], rax
    ; pop base into rbx
    mov     rdi, 0x5B
    call    emit1
    ; --- Restore state ---
    pop     qword [lv_isptr]
    pop     qword [lv_esz]
    pop     qword [lv_sid]
    ; scale index by elem_size
    mov     r14, [lv_esz]
    cmp     r14, 1
    je      .ga_idx_add
    ; imul rax, rax, imm32
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x69
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, r14
    call    emit4
.ga_idx_add:
    ; add rax, rbx
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x01
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    call    adv_tok         ; skip ']'
    ; lv_esz already carries the element size; lv_isptr stays 0 so
    ; the caller (gen_expr / gen_expr_stmt) uses the esz-based load/store path.
.ga_idx_done:
    mov     qword [ga_from_dot], 0  ; clear: result is element address, not field
    mov     qword [ga_acnt], 0
    jmp     .ga_post_loop

.ga_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

; =============================================================================
; gen_syscall — generate code for syscall(nr, arg1, ...)
; =============================================================================
gen_syscall:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    push    r15

    call    cur_tok_type
    cmp     rax, TOK_SYSCALL
    jne     .gs_skip_ident
    call    adv_tok         ; skip 'syscall'
.gs_skip_ident:
    call    adv_tok         ; skip '('
    xor     r14, r14
.gs_arg_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .gs_done_args
    cmp     rax, TOK_EOF
    je      .gs_done_args
    push    r14
    call    gen_expr
    pop     r14
    mov     rdi, 0x50
    call    emit1
    inc     r14
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .gs_arg_loop
    call    adv_tok
    jmp     .gs_arg_loop
.gs_done_args:
    call    adv_tok         ; skip ')'
    ; Syscall arguments are pushed in order: arg0, arg1, ..., argN
    ; We must pop them in REVERSE order into the syscall registers:
    ; arg5 -> r9
    ; arg4 -> r8
    ; arg3 -> r10
    ; arg2 -> rdx
    ; arg1 -> rsi
    ; arg0 -> rdi
    ; Syscall number (rax) is ALREADY pushed by the caller of gen_syscall. Wait.
    ; gen_syscall caller (gen_stmt) calls gen_expr for the syscall number first.
    ; So rax is the LAST thing pushed? No, the arg loop pushes them.
    ; r14 = total arg count including syscall number.
    ; We emit (r14-1) pops for arg regs, then always pop rax for the nr.
    ; So each threshold is one higher than for regular calls.
    cmp     r14, 7
    jl      .gs_skip_r9
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59
    call    emit1           ; pop r9 (arg5)
.gs_skip_r9:
    cmp     r14, 6
    jl      .gs_skip_r8
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58
    call    emit1           ; pop r8 (arg4)
.gs_skip_r8:
    cmp     r14, 5
    jl      .gs_skip_r10
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5A
    call    emit1           ; pop r10 (arg3)
.gs_skip_r10:
    cmp     r14, 4
    jl      .gs_skip_rdx
    mov     rdi, 0x5A
    call    emit1           ; pop rdx (arg2)
.gs_skip_rdx:
    cmp     r14, 3
    jl      .gs_skip_rsi
    mov     rdi, 0x5E
    call    emit1           ; pop rsi (arg1)
.gs_skip_rsi:
    cmp     r14, 2
    jl      .gs_skip_rdi
    mov     rdi, 0x5F
    call    emit1           ; pop rdi (arg0)
.gs_skip_rdi:
    ; Always pop rax (syscall nr)
    mov     rdi, 0x58
    call    emit1           ; pop rax
.gs_emit_sys:
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    leave
    ret

; =============================================================================
; gen_stmt — generate code for one statement
; =============================================================================
gen_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    push    r15

    call    cur_tok_type
    cmp     rax, TOK_LET
    je      .gs_let
    cmp     rax, TOK_IF
    je      .gs_if
    cmp     rax, TOK_LOOP
    je      .gs_loop
    cmp     rax, TOK_RET
    je      .gs_ret
    cmp     rax, TOK_PRINT
    je      .gs_print
    cmp     rax, TOK_SYSCALL
    je      .gs_syscall
    cmp     rax, TOK_ASM
    je      .gs_asm
    cmp     rax, TOK_BREAK
    je      .gs_break
    cmp     rax, TOK_RBRACE
    je      .gs_done
    cmp     rax, TOK_EOF
    je      .gs_done
    ; expression statement (assignment or standalone call)
    call    gen_expr_stmt
    jmp     .gs_done

; --- let x = expr ---
.gs_let:
    call    adv_tok         ; skip 'let'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]    ; var name_start
    mov     r13, [rax+16]   ; var name_len
    call    adv_tok
    call    adv_tok         ; skip '='
    ; struct literal? ident followed by '{'
    call    cur_tok_type
    cmp     rax, TOK_IDENT
    jne     .gs_let_check_array_kw
    mov     r14, [tok_pos]
    ; peek next token without advancing tok_pos
    mov     rax, r14
    inc     rax
    imul    rax, rax, TOK_SZ
    mov     rbx, [tok_buf_ptr]
    add     rax, rbx
    mov     rax, [rax]      ; next tok_type
    cmp     rax, TOK_LBRACE
    je      .gs_let_struct
    cmp     rax, TOK_LBRACK
    jne     .gs_let_expr
    ; ident followed by '[': only treat as array alloc if ident is a struct type
    mov     [tok_pos], r14
    call    get_cur_tok_ptr
    mov     r8,  [rax+8]    ; type name_start
    mov     r9,  [rax+16]   ; type name_len
    call    lookup_struct
    cmp     rax, -1
    je      .gs_let_expr    ; not a struct type -> expression (indexing)
    jmp     .gs_let_array_ident

.gs_let_struct:
    mov     [tok_pos], r14
    call    get_cur_tok_ptr
    mov     r14, [rax+8]    ; struct name_start
    mov     r15, [rax+16]   ; struct name_len
    call    adv_tok         ; skip struct name
    call    adv_tok         ; skip '{'
    ; lookup struct id and size
    mov     r8, r14
    mov     r9, r15
    call    lookup_struct
    mov     r11, rax        ; struct id
    cmp     r11, -1
    je      .gs_let_expr
    mov     rax, r11
    imul    rax, rax, STR_SZ
    mov     rbx, [stt_tbl_ptr]
    add     rax, rbx
    mov     r15, [rax+16]   ; struct size
    ; allocate local (structs stored as pointers)
    mov     r8, r12
    mov     r9, r13
    mov     r10, TK_PTR
    mov     r12, r15
    call    add_local
    mov     r14, rax        ; rbp_offset
    ; emit mmap for struct size (r15)
    call    .gs_emit_mmap
    ; store pointer to local [rbp-off]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rax, r14
    neg     rax
    mov     rdi, rax
    call    emit4
    ; field initializers (field: expr)
.gs_let_struct_fields:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gs_let_struct_done
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    call    adv_tok         ; field name
    call    adv_tok         ; skip ':'
    call    gen_expr
    ; load base pointer into rbx
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x9D
    call    emit1
    mov     rax, r14
    neg     rax
    mov     rdi, rax
    call    emit4
    ; find field offset/size
    mov     rdi, r11
    call    find_field
    cmp     rax, 0
    je      .gs_let_struct_next
    mov     rbx, [rax+16]   ; field offset
    mov     r15, [rax+24]   ; elem_size
    ; store rax -> [rbx + offset]
    cmp     r15, 1
    je      .gs_sf_store_b
    cmp     r15, 4
    je      .gs_sf_store_d
    jmp     .gs_sf_store_q
.gs_sf_store_b:
    mov     rdi, 0x88
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, rbx
    call    emit4
    jmp     .gs_let_struct_next
.gs_sf_store_d:
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, rbx
    call    emit4
    jmp     .gs_let_struct_next
.gs_sf_store_q:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, rbx
    call    emit4
.gs_let_struct_next:
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .gs_let_struct_fields
    call    adv_tok
    jmp     .gs_let_struct_fields
.gs_let_struct_done:
    call    adv_tok         ; skip '}'
    jmp     .gs_done

.gs_let_array_ident:
    ; array alloc with struct type
    mov     [tok_pos], r14
    call    get_cur_tok_ptr
    mov     r10, [rax]      ; tok_type
    mov     r14, [rax+8]    ; type name_start
    mov     r15, [rax+16]   ; type name_len
    call    adv_tok
    call    adv_tok         ; skip '['
    call    get_cur_tok_ptr
    mov     rbx, [rax+24]   ; count
    call    adv_tok
    call    adv_tok         ; skip ']'
    ; lookup struct
    mov     r8, r14
    mov     r9, r15
    call    lookup_struct
    mov     r11, rax        ; struct id
    cmp     r11, -1
    je      .gs_let_expr
    mov     rax, r11
    imul    rax, rax, STR_SZ
    mov     rdx, [stt_tbl_ptr]
    add     rax, rdx
    mov     rcx, [rax+16]   ; rcx = elem_size (use rcx, not r15 which we need)
    imul    rbx, rcx        ; rbx = count * elem_size = total_size
    mov     r15, rbx        ; r15 = total_size (for gs_emit_mmap)
    ; allocate local pointer to array
    ; r8=VAR_ns, r9=VAR_nl, r10=TK_PTR, r11=struct_id, r12=elem_size
    mov     r8, r12         ; VAR name_start (preserved from gs_let)
    mov     r9, r13         ; VAR name_len
    mov     r10, TK_PTR
    ; r11 = struct_id already set
    mov     r12, rcx        ; r12 = elem_size (for indexing stride)
    call    add_local
    mov     r14, rax        ; rbp_offset
    call    .gs_emit_mmap
    ; store pointer
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rax, r14
    neg     rax
    mov     rdi, rax
    call    emit4
    jmp     .gs_done

.gs_let_check_array_kw:
    call    cur_tok_type
    cmp     rax, TOK_I64
    je      .gs_let_array_kw
    cmp     rax, TOK_I32
    je      .gs_let_array_kw
    cmp     rax, TOK_I8
    je      .gs_let_array_kw
    cmp     rax, TOK_F64
    je      .gs_let_array_kw
    jmp     .gs_let_expr

.gs_let_array_kw:
    mov     r14, [tok_pos]
    call    adv_tok
    call    cur_tok_type
    cmp     rax, TOK_LBRACK
    jne     .gs_let_restore_kw
    mov     [tok_pos], r14
    call    get_cur_tok_ptr
    mov     r10, [rax]      ; tok_type
    call    adv_tok
    call    adv_tok         ; skip '['
    call    get_cur_tok_ptr
    mov     rbx, [rax+24]   ; count
    call    adv_tok
    call    adv_tok         ; skip ']'
    ; elem_size from scalar type
    mov     r15, 8
    cmp     r10, TOK_I8
    jne     .gs_arr_i32
    mov     r15, 1
    jmp     .gs_arr_sz_done
.gs_arr_i32:
    cmp     r10, TOK_I32
    jne     .gs_arr_sz_done
    mov     r15, 4
.gs_arr_sz_done:
    mov     rax, rbx
    imul    rax, r15        ; total size (rax = rbx * r15)
    mov     r14, r15        ; elem_size
    mov     r15, rax        ; total size
    ; allocate local pointer to array
    mov     r8, r12
    mov     r9, r13
    mov     r10, TK_PTR
    mov     r11, -1
    mov     r12, r14
    call    add_local
    mov     r14, rax
    call    .gs_emit_mmap
    ; store pointer
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rax, r14
    neg     rax
    mov     rdi, rax
    call    emit4
    jmp     .gs_done
.gs_let_restore_kw:
    mov     [tok_pos], r14
    jmp     .gs_let_expr

.gs_let_expr:
    call    gen_expr
    ; Check if expression result is a struct address — if so, store as pointer
    ; so that field access (t.field) works correctly on the local.
    mov     rax, [lv_sid]
    cmp     rax, -1
    je      .gs_let_scalar
    ; struct address — create a pointer-to-struct local
    push    qword [lv_sid]
    push    qword [lv_esz]
    mov     r8, r12
    mov     r9, r13
    mov     r10, TK_PTR
    pop     r12             ; esz = struct element size
    pop     r11             ; sid = struct id
    push    r12
    push    r13
    call    add_local
    pop     r13
    pop     r12
    mov     r15, rax        ; rbp_offset
    jmp     .gs_let_store
.gs_let_scalar:
    ; allocate local var and store rax (scalar)
    push    r12
    push    r13
    mov     r8, r12
    mov     r9, r13
    mov     r10, TK_SCALAR
    mov     r11, -1
    mov     r12, 8
    call    add_local
    pop     r13
    pop     r12
    mov     r15, rax        ; rbp_offset (from add_local)
.gs_let_store:
    ; emit: mov [rbp-off], rax  (0x85 = rax, expression result in rax at runtime)
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r15
    mov     rdi, r15
    call    emit4
    jmp     .gs_done

.gs_emit_mmap:
    ; r15 = size (imm32)
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 9
    call    emit4
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0xBE
    call    emit1
    mov     rdi, r15
    call    emit4
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 3
    call    emit4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 0x22
    call    emit4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, -1
    call    emit4
    mov     rdi, 0x45
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    ret

; --- if cond { then } else { else } ---
.gs_if:
    call    adv_tok         ; skip 'if'
    call    gen_expr        ; cond -> rax
    ; emit: test rax, rax; jz else_label
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    ; jz rel32: 0F 84 XX XX XX XX
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1
    mov     r14, [cod_len]  ; patch offset for else
    mov     rdi, 0
    call    emit4           ; placeholder
    ; expect '{'
    call    adv_tok         ; skip '{'
    ; gen then block
    push    r14
    push    r15
    call    gen_block_body
    pop     r15
    pop     r14
    ; emit: jmp after_label: E9 XX XX XX XX
    mov     rdi, 0xE9
    call    emit1
    mov     r15, [cod_len]  ; patch offset for after
    mov     rdi, 0
    call    emit4
    ; patch else offset
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r14
    mov     [rbx], eax
    ; check for else
    call    cur_tok_type
    cmp     rax, TOK_ELSE
    jne     .gs_if_no_else
    call    adv_tok         ; skip 'else'
    call    cur_tok_type
    cmp     rax, TOK_IF
    je      .gs_else_if
    call    adv_tok         ; skip '{'
    push    r15
    call    gen_block_body
    pop     r15
    jmp     .gs_if_no_else
.gs_else_if:
    push    r15             ; save outer "after" jump offset
    call    gen_stmt        ; recursively handle 'if ...'
    pop     r15             ; restore outer "after" jump offset
.gs_if_no_else:
    ; patch after offset
    mov     rax, [cod_len]
    sub     rax, r15
    sub     rax, 4
    mov     rbx, [cod_buf_ptr]
    add     rbx, r15
    mov     [rbx], eax
    jmp     .gs_done

; --- loop cond { body } ---
.gs_loop:
    call    adv_tok         ; skip 'loop'
    ; save loop_start = cod_len in r14
    mov     r14, [cod_len]
    ; save outer break-stack base (jmp_top) for nested loops
    mov     r15, [jmp_top]  ; r15 = old jmp_top (break stack base for this loop)
    ; check: loop {} (unconditional) vs loop COND {} (conditional)
    call    cur_tok_type
    cmp     rax, TOK_LBRACE
    je      .gs_loop_body
    ; conditional loop: gen_expr for condition — r14/r15 preserved
    push    r14
    push    r15
    call    gen_expr        ; rax = condition
    pop     r15
    pop     r14
    ; emit: test rax, rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    ; emit: jz placeholder (0F 84 rel32) — treated like a break for patching
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1
    mov     rax, [jmp_top]
    imul    rax, rax, 8
    lea     rbx, [jmp_stk]
    add     rbx, rax
    mov     rax, [cod_len]  ; position of rel32 placeholder
    mov     [rbx], rax
    inc     qword [jmp_top]
    mov     rdi, 0
    call    emit4           ; placeholder rel32 = 0
.gs_loop_body:
    call    adv_tok         ; skip '{'
    push    r14
    push    r15
    call    gen_block_body  ; compile body (breaks push to jmp_stk)
    pop     r15
    pop     r14
    ; emit: jmp loop_start (backward rel32)
    mov     rdi, 0xE9
    call    emit1
    mov     rax, [cod_len]
    add     rax, 4          ; end of jmp instruction
    sub     r14, rax        ; negative displacement back to loop_start
    mov     rdi, r14
    call    emit4
    ; loop_end = cod_len — patch ALL breaks in jmp_stk[r15..jmp_top]
    mov     rbx, r15        ; start index
.gs_loop_patch:
    cmp     rbx, [jmp_top]
    jge     .gs_loop_patch_done
    mov     rax, rbx
    imul    rax, rax, 8
    lea     rcx, [jmp_stk]
    add     rcx, rax
    mov     rcx, [rcx]      ; break placeholder position
    mov     rax, [cod_len]  ; loop_end
    sub     rax, rcx
    sub     rax, 4          ; rel32 = loop_end - (placeholder + 4)
    mov     rdx, [cod_buf_ptr]
    add     rdx, rcx
    mov     [rdx], eax      ; patch break's jmp rel32
    inc     rbx
    jmp     .gs_loop_patch
.gs_loop_patch_done:
    ; restore break stack top to outer loop's base
    mov     [jmp_top], r15
    jmp     .gs_done

; --- break ---
.gs_break:
    call    adv_tok
    ; emit: jmp FORWARD placeholder (loop_end unknown yet)
    mov     rdi, 0xE9
    call    emit1
    ; record placeholder position in jmp_stk[jmp_top++]
    mov     rax, [jmp_top]
    imul    rax, rax, 8
    lea     rbx, [jmp_stk]
    add     rbx, rax
    mov     rax, [cod_len]  ; position of placeholder
    mov     [rbx], rax      ; jmp_stk[jmp_top] = placeholder position
    inc     qword [jmp_top]
    mov     rdi, 0
    call    emit4           ; placeholder = 0
    jmp     .gs_done

; --- ret expr ---
.gs_ret:
    call    adv_tok             ; skip 'ret'
    ; Only call gen_expr if there's an expression (next token is not '}')
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gs_ret_zero
    call    gen_expr
    jmp     .gs_ret_epilog
.gs_ret_zero:
    ; bare ret — emit xor rax, rax (return 0) without consuming '}'
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC0
    call    emit1
.gs_ret_epilog:
    ; emit function epilogue and ret
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5E
    call    emit1   ; pop r14
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5D
    call    emit1   ; pop r13
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5C
    call    emit1   ; pop r12
    mov     rdi, 0x5B
    call    emit1   ; pop rbx
    ; NOTE: r15 is NOT popped — not pushed in prologue (reserved for globals base)
    ; leave; ret
    mov     rdi, 0xC9
    call    emit1   ; leave
    mov     rdi, 0xC3
    call    emit1   ; ret
    jmp     .gs_done

; --- print("str") ---
.gs_print:
    call    adv_tok         ; skip 'print'
    call    adv_tok         ; skip '('
    call    cur_tok_type
    cmp     rax, TOK_STR
    jne     .gs_print_expr
    ; print("string literal"):
    ; gen_expr will handle TOK_STR and emit lea rax, [rip+str]
    call    gen_expr
    ; Now rax = pointer to string. We need to emit:
    ; mov rsi, rax  (str ptr)
    ; call strlen_gen  (or compute length at compile time)
    ; mov edx, len
    ; mov edi, 1
    ; mov eax, SYS_WRITE
    ; syscall
    ; For simplicity: string in sdt_buf, compute length via null scan
    ; emit: mov rsi, rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC6
    call    emit1
    ; emit strlen call: we need a runtime strlen in generated binary
    ; emit: call gen_strlen (a helper we embed in generated code)
    ; OR: emit inline strlen
    ; Inline strlen: xor ecx,ecx; .sl: cmp byte[rsi+rcx],0; je .se; inc ecx; jmp .sl; .se:
    ; emit: xor ecx, ecx
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    ; .sl: cmp byte [rsi+rcx], 0
    ; short jz .se
    mov     rdi, 0x80
    call    emit1
    mov     rdi, 0x3C
    call    emit1
    mov     rdi, 0x0E
    call    emit1
    mov     rdi, 0x00
    call    emit1
    ; je +4 (skip inc ecx + jmp, land on mov edx,ecx)
    mov     rdi, 0x74
    call    emit1
    mov     rdi, 4
    call    emit1
    ; inc ecx
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0xC1
    call    emit1
    ; jmp -10 (back to cmp byte [rsi+rcx],0)
    mov     rdi, 0xEB
    call    emit1
    mov     rdi, -10
    call    emit1
    ; mov edx, ecx
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xCA
    call    emit1
    ; mov edi, 1
    mov     rdi, 0xBF
    call    emit1
    mov     rdi, 1
    call    emit4
    ; mov eax, 1 (SYS_WRITE)
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 1
    call    emit4
    ; syscall
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    call    adv_tok         ; skip ')'
    jmp     .gs_done

.gs_print_expr:
    ; print(expr): gen_expr → rax = integer; emit print_int_code; skip ')'
    call    gen_expr
    lea     rdi, [print_int_code]
    mov     rsi, print_int_code_len
    call    emit_bytes
    call    adv_tok         ; skip ')'
    jmp     .gs_done

.gs_syscall:
    call    gen_syscall
    jmp     .gs_done

; --- asm { ... } block ---
.gs_asm:
    call    adv_tok         ; skip 'asm'
    call    adv_tok         ; skip '{'
    ; parse asm block: "out var = reg" or "in reg = var"
.gs_asm_loop:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gs_asm_done
    cmp     rax, TOK_EOF
    je      .gs_asm_done
    ; check for 'out'
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    ; compare with "out": strncmp_src(rbx=src_offset, rcx=len, rdx=ref_string)
    mov     rbx, r12        ; rbx = name_start (offset into src_buf)
    mov     rcx, r13        ; rcx = name_len
    lea     rdx, [kw_out]   ; rdx = "out\0"
    call    strncmp_src
    cmp     rax, 1
    jne     .gs_asm_check_in
    ; "out var = reg" -> mov [rbp-var_off], reg
    call    adv_tok         ; skip 'out'
    ; var name
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok         ; skip '='
    ; reg name
    call    get_cur_tok_ptr
    mov     r14, [rax+8]    ; reg name start in src
    mov     rax, [rax+16]
    mov     [asm_reglen], rax ; reg name len (saved to BSS; r15 is globals base, must not clobber)
    call    adv_tok
    ; look up var
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    jne     .gs_asm_out_local
    ; fallback: if local not found, use most recent local
    mov     rax, [loc_cnt]
    cmp     rax, 0
    je      .gs_asm_out_global
    dec     rax
    imul    rax, rax, LOC_SZ
    mov     rbx, [loc_tbl_ptr]
    add     rbx, rax
    mov     r12, [rbx+16]   ; rbp_offset
    ; parse register name from r14 (src_buf offset) and asm_reglen
    mov     r8, [src_buf_ptr]
    add     r8, r14
    mov     r9, [asm_reglen]
    call    parse_reg_name
    cmp     rax, -1
    je      .gs_asm_loop
    mov     r11d, eax
    jmp     .gs_asm_out_local_emit
.gs_asm_out_local:
    mov     r12, [rax+16]   ; rbp_offset
    ; parse register name from r14 (src_buf offset) and asm_reglen
    mov     r8, [src_buf_ptr]
    add     r8, r14
    mov     r9, [asm_reglen]
    call    parse_reg_name
    cmp     rax, -1
    je      .gs_asm_loop    ; skip invalid register
    mov     r11d, eax       ; r11d = register code
    ; emit: mov [rbp + disp32], <reg>
    ; 48 89 /r (mov r64, r/m64)
    ; ModRM = mod(10) | reg(3) | rm(3)  — mod=10 means 32-bit displacement
.gs_asm_out_local_emit:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rax, r11
    shl     rax, 3
    or      rax, 0x85       ; mod=10, rm=101 (rbp) — 32-bit disp
    mov     rdi, rax
    call    emit1
    neg     r12
    and     r12, 0xFFFFFFFF
    mov     rdi, r12
    call    emit4
    jmp     .gs_asm_loop
.gs_asm_out_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .gs_asm_loop
    mov     r12, [rax+16]   ; r15_offset
    ; parse register name from r14 (src_buf offset) and asm_reglen
    mov     r8, [src_buf_ptr]
    add     r8, r14
    mov     r9, [asm_reglen]
    call    parse_reg_name
    cmp     rax, -1
    je      .gs_asm_loop    ; skip invalid register
    mov     r11d, eax       ; r11d = register code
    ; emit: mov [r15 + disp32], <reg>
    ; 49 89 /r (REX.B mov r64, r/m64)
    ; ModRM = mod(2) | reg(3) | rm(3)
    mov     rdi, 0x49       ; REX.B
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rax, r11
    shl     rax, 3
    or      rax, 0x87       ; mod=10, rm=111 (r15)
    mov     rdi, rax
    call    emit1
    mov     rdi, r12
    call    emit4
    jmp     .gs_asm_loop
.gs_asm_check_in:
    ; skip unknown asm tokens
    call    adv_tok
    jmp     .gs_asm_loop
.gs_asm_done:
    call    adv_tok         ; skip '}'
    jmp     .gs_done

.gs_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    leave
    ret

; gen_expr_stmt: handle x = expr (assignment) or standalone call
gen_expr_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    mov     r14, [tok_pos]
    call    adv_tok
    call    cur_tok_type
    cmp     rax, TOK_EQ
    je      .assign_lvalue
    cmp     rax, TOK_DOT
    je      .assign_lvalue
    cmp     rax, TOK_LBRACK
    je      .assign_lvalue
    ; standalone call/expression: tok_pos is past the ident
    ; put it back and call gen_expr? No, we've advanced.
    ; Just evaluate remaining as expr...
    ; For now, treat as function call (most common expr-stmt case)
    ; Restore isn't possible cleanly - simplified: call gen_expr from after name
    ; The ident was already consumed; for a call, next token should be '('
    cmp     rax, TOK_LPAREN
    jne     .ges_done
    ; It's a function call: emit call
    ; Retrieve name from previous token (at r14)
    mov     rax, r14
    imul    rax, rax, TOK_SZ
    mov     rbx, [tok_buf_ptr]
    add     rax, rbx
    mov     r12, [rax+8]    ; name_start
    mov     r13, [rax+16]   ; name_len
    call    adv_tok         ; skip '('
    xor     r14, r14
.ges_arg_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .ges_args_done
    cmp     rax, TOK_EOF
    je      .ges_args_done
    call    gen_expr
    mov     rdi, 0x50
    call    emit1
    inc     r14
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .ges_arg_loop
    call    adv_tok
    jmp     .ges_arg_loop
.ges_args_done:
    call    adv_tok
    ; --- FIX: Resolve fn target BEFORE popping r8/r9 arg registers ---
    push    r12
    push    r13
    mov     r8, r12
    mov     r9, r13
    call    lookup_fn
    mov     r11, rax        ; save fn entry ptr in r11
    pop     r13
    pop     r12
    ; -----------------------------------------------------------------
    ; pop into arg regs (descending: rcx/rdx/rsi/rdi so arg0→rdi, arg1→rsi, ...)
    cmp     r14, 6
    jl      .ges_pop5
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59           ; pop r9
    call    emit1
.ges_pop5:
    cmp     r14, 5
    jl      .ges_pop4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58           ; pop r8
    call    emit1
.ges_pop4:
    cmp     r14, 4
    jl      .ges_pop3
    mov     rdi, 0x59           ; pop rcx
    call    emit1
.ges_pop3:
    cmp     r14, 3
    jl      .ges_pop2
    mov     rdi, 0x5A           ; pop rdx
    call    emit1
.ges_pop2:
    cmp     r14, 2
    jl      .ges_pop1
    mov     rdi, 0x5E           ; pop rsi
    call    emit1
.ges_pop1:
    cmp     r14, 1
    jl      .ges_call
    mov     rdi, 0x5F           ; pop rdi
    call    emit1
.ges_call:
    ; emit call with fixup
    push    r12
    push    r13
    push    r14
    mov     rdi, 0xE8
    call    emit1
    mov     rax, r11        ; use pre-resolved fn in r11
    cmp     rax, 0
    je      .ges_fixup
    cmp     qword [rax+40], -1
    je      .ges_fixup
    mov     r15, [rax+40]
    mov     rax, [cod_len]
    add     rax, 4
    sub     r15, rax
    mov     rdi, r15
    call    emit4
    jmp     .ges_call_done
.ges_fixup:
    mov     rax, [fix_cnt]
    imul    rax, rax, 32
    mov     rbx, [fix_buf_ptr]
    add     rbx, 8192
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    mov     [rbx+8], r12
    mov     [rbx+16], r13
    mov     qword [rbx+24], 1
    inc     qword [fix_cnt]
    mov     rdi, 0
    call    emit4
.ges_call_done:
    pop     r14
    pop     r13
    pop     r12
    jmp     .ges_done

.assign_lvalue:
    mov     [tok_pos], r14  ; rewind to ident
    call    gen_addr        ; rax=addr, lv_* set
    call    cur_tok_type
    cmp     rax, TOK_EQ
    jne     .ges_done
    call    adv_tok         ; skip '='
    ; push address
    mov     rdi, 0x50
    call    emit1
    push    qword [lv_glb]
    ; rhs expr -> rax
    push    qword [lv_sid]
    push    qword [lv_esz]
    push    qword [lv_isptr]
    call    gen_expr
    mov     r11, [lv_sid]
    mov     r12, [lv_esz]
    mov     r13, [lv_isptr]
    pop     qword [lv_isptr]
    pop     qword [lv_esz]
    pop     qword [lv_sid]
    pop     rbx             ; lhs global entry, if any
    mov     qword [lv_glb], 0
    cmp     rbx, 0
    je      .ges_assign_pop_addr
    cmp     r13, 0
    je      .ges_clear_glb_meta
    mov     qword [rbx+24], TK_PTR
    mov     [rbx+32], r11
    mov     [rbx+40], r12
    jmp     .ges_assign_pop_addr
.ges_clear_glb_meta:
    mov     qword [rbx+24], -1
    mov     qword [rbx+32], -1
    mov     qword [rbx+40], 8
.ges_assign_pop_addr:
    ; pop address into r10
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5A
    call    emit1           ; pop r10
    ; store based on lvalue type
    cmp     qword [lv_isptr], 0
    jne     .store_qword
    mov     r15, [lv_sid]
    cmp     r15, -1
    jne     .store_qword
    mov     r15, [lv_esz]
    cmp     r15, 1
    je      .store_byte
    cmp     r15, 4
    je      .store_dword
    jmp     .store_qword
.store_byte:
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x88
    call    emit1
    mov     rdi, 0x02       ; mov [r10], al
    call    emit1
    jmp     .ges_done
.store_dword:
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x02       ; mov [r10], eax
    call    emit1
    jmp     .ges_done
.store_qword:
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x02       ; mov [r10], rax
    call    emit1
    jmp     .ges_done

.ges_done:
    pop     r14
    pop     r13
    pop     r12
    leave
    ret

; gen_block_body: generate statements until '}'
gen_block_body:
    push    rbp
    mov     rbp, rsp
    push    qword [loc_cnt]
    push    qword [loc_rbp]
.gbb_loop:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gbb_done
    cmp     rax, TOK_EOF
    je      .gbb_done
    call    gen_stmt
    jmp     .gbb_loop
.gbb_done:
    call    adv_tok         ; skip '}'
    pop     qword [loc_rbp]
    pop     qword [loc_cnt]
    leave
    ret

; =============================================================================
; gen_fn — generate code for function at fn_tbl[rdi]
; =============================================================================
gen_fn:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14

    mov     r14, rdi        ; fn entry ptr
    ; record code_off
    mov     rax, [cod_len]
    mov     [r14+40], rax

    ; prologue: push rbp; mov rbp,rsp; sub rsp,0(patch later); push rbx,r12,r13,r14
    mov     rdi, 0x55
    call    emit1           ; push rbp
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xE5
    call    emit1           ; mov rbp, rsp
    ; sub rsp, N — emit with placeholder, patch after body
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x81
    call    emit1
    mov     rdi, 0xEC
    call    emit1
    mov     rax, [cod_len]
    mov     [frm_patch_off], rax    ; save frame size placeholder offset (r15 not safe)
    mov     rdi, 256        ; placeholder (will patch)
    call    emit4
    ; push callee-saved regs
    mov     rdi, 0x53
    call    emit1           ; push rbx
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x54
    call    emit1           ; push r12
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x55
    call    emit1           ; push r13
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x56
    call    emit1           ; push r14
    ; NOTE: r15 is reserved for globals base and must NOT be pushed/popped
    ; as it contains the globals memory pointer needed throughout the function

    ; setup locals: parameters are in rdi,rsi,rdx,rcx,r8,r9
    ; copy params to locals
    mov     qword [loc_cnt], 0
    mov     qword [loc_rbp], 0
    mov     qword [loc_max_rbp], 0
    ; store the 6 arg registers as the first params
    mov     rax, [r14+24]
    mov     [prm_cnt_bss], rax   ; param count in BSS (all regs clobbered in loop)
    lea     r13, [r14+64]   ; params array
    xor     rcx, rcx        ; param index
    ; arg regs bytes for mov [rbp-off], reg:
    ; rdi=0xBD, rsi=0xB5, rdx=0x95, rcx=0x8D, r8=?, r9=?
    ; Simplified: emit stores for first 6 params
.gf_param_loop:
    cmp     rcx, [prm_cnt_bss]
    jge     .gf_param_done
    cmp     rcx, 6
    jge     .gf_param_done
    ; alloc local for param
    mov     r8,  [r13]      ; param name_start
    mov     r9,  [r13+8]    ; param name_len
    mov     r10, TK_SCALAR
    mov     r11, -1
    mov     r12, [r13+16]   ; elem_size
    mov     rax, [r13+24]   ; type_id (Use rax, NOT r15!)
    bt      rax, 63         ; test PTR_FLAG (bit 63)
    jnc     .gf_param_type_done
    mov     r10, TK_PTR
    ; rax already has type_id
    shl     rax, 1
    shr     rax, 1          ; clear PTR_FLAG
    ; if scalar pointer, keep sid=-1
    cmp     rax, TOK_I64
    je      .gf_param_type_done
    cmp     rax, TOK_I32
    je      .gf_param_type_done
    cmp     rax, TOK_I8
    je      .gf_param_type_done
    cmp     rax, TOK_F64
    je      .gf_param_type_done
    ; only accept valid struct ids
    mov     rbx, [stt_cnt]
    cmp     rax, rbx
    jae     .gf_param_type_done
    mov     r11, rax        ; struct id
.gf_param_type_done:
    push    r12
    push    r13
    push    rcx
    call    add_local       ; -> rax = rbp_offset
    pop     rcx
    pop     r13
    pop     r12
    ; emit: mov [rbp-off], argreg
    ; Determine opcode based on rcx (param index)
    ; Check if param index >= 4 (r8/r9): skip emit entirely
    push    rax             ; save rbp_offset
    push    rcx
    push    r12
    push    r13
    cmp     rcx, 4
    jge     .gf_param_r8r9  ; r8/r9: need REX.WR prefix
    ; param regs: 0=rdi(7),1=rsi(6),2=rdx(2),3=rcx(1)
    ; emit REX.W + MOV [rbp-off], regN  (AFTER skip check)
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    ; ModRM: mod=10 (disp32), reg=param_reg, rm=101 (rbp)
    pop     r13
    pop     r12
    pop     rcx
    push    rcx
    push    r12
    push    r13
    cmp     rcx, 0
    je      .gf_store_rdi
    cmp     rcx, 1
    je      .gf_store_rsi
    cmp     rcx, 2
    je      .gf_store_rdx
    cmp     rcx, 3
    je      .gf_store_rcx
.gf_store_rdi:
    mov     rdi, 0xBD
    call    emit1
    jmp     .gf_store_disp
.gf_store_rsi:
    mov     rdi, 0xB5
    call    emit1
    jmp     .gf_store_disp
.gf_store_rdx:
    mov     rdi, 0x95
    call    emit1
    jmp     .gf_store_disp
.gf_store_rcx:
    mov     rdi, 0x8D
    call    emit1
.gf_store_disp:
    pop     r13
    pop     r12
    pop     rcx
    pop     rax             ; rbp_offset
    neg     rax
    mov     rdi, rax
    push    rcx
    push    r12
    push    r13
    call    emit4
    pop     r13
    pop     r12
    pop     rcx
    jmp     .gf_param_next_nostack
.gf_param_r8r9:
    ; emit: mov [rbp-off], r8 or r9
    ; REX.WR (4C) MOV (89) ModRM (85=r8/rbp+disp32, 8D=r9/rbp+disp32)
    mov     rdi, 0x4C
    call    emit1
    mov     rdi, 0x89
    call    emit1
    pop     r13
    pop     r12
    pop     rcx
    push    rcx
    push    r12
    push    r13
    cmp     rcx, 4
    je      .gf_store_r8
    ; param 5 = r9
    mov     rdi, 0x8D
    call    emit1
    jmp     .gf_store_r8r9_disp
.gf_store_r8:
    mov     rdi, 0x85
    call    emit1
.gf_store_r8r9_disp:
    pop     r13
    pop     r12
    pop     rcx
    pop     rax             ; rbp_offset
    neg     rax
    mov     rdi, rax
    push    rcx
    push    r12
    push    r13
    call    emit4
    pop     r13
    pop     r12
    pop     rcx
    jmp     .gf_param_next_nostack
.gf_param_next:
    pop     r13
    pop     r12
    pop     rcx
    pop     rax             ; discard rbp_offset
.gf_param_next_nostack:
    add     r13, PRM_SZ
    inc     rcx
    jmp     .gf_param_loop
.gf_param_done:
    ; set tok_pos to body
    mov     rax, [r14+32]   ; body_tok
    mov     [tok_pos], rax
    ; generate body
    call    gen_block_body
    ; patch frame size before the epilogue so the body layout is finalized.
    mov     rax, [loc_max_rbp]
    add     rax, 15
    and     rax, -16
    mov     rbx, [cod_buf_ptr]
    add     rbx, [frm_patch_off]
    mov     [rbx], eax
    ; epilogue
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5E
    call    emit1           ; pop r14
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5D
    call    emit1           ; pop r13
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5C
    call    emit1           ; pop r12
    mov     rdi, 0x5B
    call    emit1           ; pop rbx
    ; NOTE: r15 is not popped since it's reserved for globals base (was not pushed)
    mov     rdi, 0xC9
    call    emit1           ; leave
    mov     rdi, 0xC3
    call    emit1           ; ret

    pop     r14
    pop     r13
    pop     r12
    leave
    ret

; =============================================================================
; p2_gen — Pass 2: generate code for all functions
; =============================================================================
p2_gen:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    ; Keep a stable function count and loop index on stack so pass-2
    ; iteration isn't truncated if a callee returns with clobbered regs.
    mov     rax, [fn_cnt]
    mov     [rbp-16], rax   ; fn_cnt snapshot
    mov     qword [rbp-8], 0 ; function index
    ; First emit a _start stub for the generated binary
    ; _start: call main, then exit(0)
    ; Preservation: original rsp has [argc], [argv0], [argv1]...
    ; We must preserve this rsp before any stack operations.
    mov     rdi, 0x48       ; mov rbp, rsp
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xE5
    call    emit1
    
    ; emit _start preamble
    ; mov eax, 9 (mmap)
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 9
    call    emit4
    ; xor edi, edi
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    ; mov esi, glb_size + 4096 (imm32)
    mov     rdi, 0xBE
    call    emit1
    mov     rax, [rbp + 16]
    add     rax, 4096       ; padding
    mov     rdi, rax
    call    emit4
    ; mov edx, 3
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 3
    call    emit4
    ; mov r10d, 0x22
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xBA
    call    emit1
    mov     rdi, 0x22
    call    emit4
    ; mov r8d, -1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, -1
    call    emit4
    ; xor r9d, r9d
    mov     rdi, 0x45
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    ; syscall
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    ; mov r15, rax -> 49 89 C7 (r15 = globals base)
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    pop     rax             ; glb_size no longer needed on stack
    
    ; pass argc to main: mov rdi, [rbp]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x7D
    call    emit1
    mov     rdi, 0x00
    call    emit1
    ; pass argv to main: lea rsi, [rbp+8]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x75
    call    emit1
    mov     rdi, 0x08
    call    emit1
    ; call main (fixup needed)
    mov     rdi, 0xE8
    call    emit1
    mov     rax, [fix_cnt]
    imul    rax, rax, 32
    mov     rbx, [fix_buf_ptr]
    add     rbx, 8192
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    ; fake fn name "main" — point to a data area
    lea     rax, [kw_out]   ; just a dummy ptr for name comparison; set fn ns to "main"
    ; Actually we need the source offset of "main" identifier
    ; Simplified: use a special fixup value
    mov     qword [rbx+8], -2   ; special: main
    mov     qword [rbx+16], 4
    mov     qword [rbx+24], 2   ; type=2 (main fixup)
    inc     qword [fix_cnt]
    mov     rdi, 0
    call    emit4
    ; exit(0)
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 60
    call    emit4
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1

    ; now compile each function
.p2_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-16]
    jge     .p2_done
    mov     r12, rax        ; r12 = current index
    mov     rax, r12
    imul    rax, rax, FN_SZ
    mov     rbx, [fn_tbl_ptr]
    add     rbx, rax
    ; Skip if no body (prototype)
    cmp     qword [rbx+32], 0
    je      .p2_skip_fn
    mov     rdi, rbx
    call    gen_fn
.p2_skip_fn:
    inc     qword [rbp-8]
    jmp     .p2_loop
.p2_done:
    ; Patch call fixups
    xor     r12, r12
.p2_fix_loop:
    cmp     r12, [fix_cnt]
    jge     .p2_fix_done
    mov     rax, r12
    imul    rax, rax, 32
    mov     rbx, [fix_buf_ptr]
    add     rbx, 8192
    add     rbx, rax
    mov     r13, [rbx]      ; patch_off
    mov     r14, [rbx+24]   ; type
    cmp     r14, 2          ; main fixup
    je      .p2_fix_main
    ; regular call fixup: find fn by name
    mov     r8,  [rbx+8]    ; fn name_start
    mov     r9,  [rbx+16]   ; fn name_len
    call    lookup_fn
    cmp     rax, 0
    je      .p2_fix_next
    cmp     qword [rax+40], -1
    je      .p2_fix_next
    mov     r15, [rax+40]   ; fn code_off
    jmp     .p2_fix_patch
.p2_fix_main:
    ; find fn named "main" — scan fn_tbl
    ; r13 = patch_off already loaded above; r12 = outer fixup index (preserved)
    ; use r14 for fn_tbl entry pointer (r14 held type, no longer needed)
    xor     rcx, rcx
.p2_find_main:
    cmp     rcx, [fn_cnt]
    jge     .p2_fix_main_miss
    mov     rax, rcx
    imul    rax, rax, FN_SZ
    mov     r14, [fn_tbl_ptr]
    add     r14, rax
    ; compare fn name with "main" (4 chars)
    mov     r8,  [r14]
    mov     r9,  [r14+8]
    cmp     r9, 4
    jne     .p2_find_main_next
    mov     rbx, [src_buf_ptr]
    add     rbx, r8         ; r8 is name_start!
    cmp     byte [rbx],   'm'
    jne     .p2_find_main_next
    cmp     byte [rbx+1], 'a'
    jne     .p2_find_main_next
    cmp     byte [rbx+2], 'i'
    jne     .p2_find_main_next
    cmp     byte [rbx+3], 'n'
    jne     .p2_find_main_next
    ; found main — r14=fn_tbl entry, r13=patch_off, r12=outer idx (all intact)
    mov     r15, [r14+40]  ; code_off
    jmp     .p2_fix_patch
.p2_find_main_next:
    inc     rcx
    jmp     .p2_find_main
.p2_fix_main_miss:
    jmp     .p2_fix_next
.p2_fix_patch:
    ; patch cod_buf[r13] = r15 - (r13 + 4)
    mov     rax, r13
    add     rax, 4
    sub     r15, rax
    mov     rbx, [cod_buf_ptr]
    add     rbx, r13
    mov     [rbx], r15d
.p2_fix_next:
    inc     r12
    jmp     .p2_fix_loop

.p2_fix_done:
    ; Patch string fixups (LEA rel32)
    ; sfx_tbl[i*16] = {cod_off:8, sdt_off:8} for i in 0..sfix_cnt-1
    ; rel32 = cod_len + sdt_off - cod_off - 4
    xor     r12, r12
.p2_sfix:
    cmp     r12, [sfix_cnt]
    jge     .p2_done2
    mov     rax, r12
    imul    rax, rax, 16
    mov     rbx, [sfx_tbl_ptr]
    add     rbx, rax
    mov     r13, [rbx]      ; cod_off
    mov     r14, [rbx+8]    ; sdt_off
    ; The sdt_buf is placed AFTER the code_buf in the final file.
    ; code_buf starts at 0x78.
    ; LEA [rip+rel32] target is (0x78 + cod_len + sdt_off).
    ; Current instruction is at (0x78 + r13).
    ; rel32 = target - (curr + 7)  [assuming 7 byte LEA]
    ; Actually, jda0 emits 0x48 0x8D 0x05 rel32 (7 bytes total)
    ; rel32 = (0x78 + cod_len + sdt_off) - (0x78 + r13 + 7)
    ; rel32 = cod_len + sdt_off - r13 - 7
    mov     r15, [cod_len]
    add     r15, r14
    sub     r15, r13
    sub     r15, 4


    mov     rbx, [cod_buf_ptr]
    add     rbx, r13
    mov     [rbx], r15d
    inc     r12
    jmp     .p2_sfix
.p2_done2:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

; =============================================================================
; write_elf — write ELF64 output file
; rdi = out_fd, rsi = code_buf, rdx = code_len, rcx = str_data, r8 = str_len
; =============================================================================
write_elf:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; out_fd
    mov     r13, rdx        ; code_len
    mov     r14, r8         ; str_len

    ; Total file size = 0x78 (ELF+PHdr) + code_len + str_len
    mov     r15, 0x78
    add     r15, r13
    add     r15, r14

    ; Build ELF header in a temp buffer on stack (0x78 bytes)
    sub     rsp, 0x78
    mov     rdi, rsp        ; elf_hdr
    ; zero it
    push    r15
    mov     rcx, 0x78
.zz:
    dec     rcx
    mov     byte [rdi+rcx], 0
    jnz     .zz
    pop     r15

    ; ELF magic
    mov     dword [rdi+0], 0x464C457F
    mov     byte  [rdi+4], 2   ; EI_CLASS = 64-bit
    mov     byte  [rdi+5], 1   ; EI_DATA = little-endian
    mov     byte  [rdi+6], 1   ; EI_VERSION
    ; e_type=ET_EXEC=2, e_machine=62
    mov     word  [rdi+16], 2
    mov     word  [rdi+18], 62
    mov     dword [rdi+20], 1
    mov     qword [rdi+24], 0x400078    ; e_entry
    mov     qword [rdi+32], 64          ; e_phoff
    mov     qword [rdi+40], 0
    mov     dword [rdi+48], 0
    mov     word  [rdi+52], 64          ; e_ehsize
    mov     word  [rdi+54], 56          ; e_phentsize
    mov     word  [rdi+56], 1           ; e_phnum
    mov     word  [rdi+58], 64
    mov     word  [rdi+60], 0
    mov     word  [rdi+62], 0
    ; Program header (at offset 64)
    lea     rbx, [rdi+64]
    mov     dword [rbx+0], 1            ; PT_LOAD
    mov     dword [rbx+4], PF_RWX       ; flags
    mov     qword [rbx+8], 0            ; p_offset
    mov     qword [rbx+16], 0x400000    ; p_vaddr
    mov     qword [rbx+24], 0x400000    ; p_paddr
    mov     [rbx+32], r15               ; p_filesz
    mov     [rbx+40], r15               ; p_memsz
    mov     qword [rbx+48], 0x200000

    ; Write header (0x78 bytes)
    mov     eax, SYS_WRITE
    mov     edi, r12d
    mov     rsi, rsp
    mov     edx, 0x78
    syscall

    ; Write code_buf
    mov     eax, SYS_WRITE
    mov     edi, r12d
    mov     rsi, [cod_buf_ptr]
    mov     rdx, r13
    syscall

    ; Write str_data
    cmp     r14, 0
    je      .we_done
    mov     eax, SYS_WRITE
    mov     edi, r12d
    mov     rsi, [sdt_buf_ptr]
    mov     rdx, r14
    syscall

.we_done:
    add     rsp, 0x78
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

; =============================================================================
; main_compile
; =============================================================================
main_compile:
    push    rbp
    mov     rbp, rsp
    ; lex
    call    lex_all
    ; pass 1
    call    p1_scan
    ; pass 2: generate code
    mov     rax, [glb_r15]
    push    rax             ; push total glb_size for p2_gen _start stub
    mov     qword [cod_len], 0
    mov     qword [sdt_len], 0
    mov     qword [fix_cnt], 0
    mov     qword [glb_r15], 0
    call    p2_gen
    pop     rax             ; cleanup stack
    ; write ELF
    mov     rdi, [out_fd]
    mov     rsi, [cod_buf_ptr]
    mov     rdx, [cod_len]
    mov     rcx, [sdt_buf_ptr]
    mov     r8,  [sdt_len]
    call    write_elf
    leave
    ret

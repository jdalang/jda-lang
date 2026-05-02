#!/usr/bin/env python3
"""gen_jda0_p2.py — _start, Lexer and utility functions"""

print(r"""
section .text

_start:
    ; debug: print 'B'
    mov     rax, 1
    mov     rdi, 2
    push    0x42 ; 'B'
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    pop     rax

    ; argc=[rsp] argv=[rsp+8..]
    mov     rdi, [rsp]
    cmp     rdi, 3
    jl      .bad_args

    ; open source file: argv[1]
    mov     rdi, [rsp+16]
    mov     eax, SYS_OPEN
    xor     rsi, rsi ; O_RDONLY
    syscall
    cmp     rax, 0
    jl      .bad_args
    mov     r13, rax ; src fd

    ; read source
    mov     rdi, rax
    lea     rsi, [src_buf]
    mov     rdx, 1048576
    mov     eax, SYS_READ
    syscall
    mov     [src_len], rax
    lea     rbx, [src_buf]
    add     rbx, rax
    mov     byte [rbx], 0

    ; close src
    mov     eax, SYS_CLOSE
    mov     rdi, r13
    syscall

    ; open output file: argv[2]
    mov     rdi, [rsp+24]
    mov     eax, SYS_OPEN
    mov     esi, 0x241 ; O_WRONLY|O_CREAT|O_TRUNC
    mov     edx, 0o755
    syscall
    cmp     rax, 0
    jl      .bad_args
    mov     [out_fd], rax

    ; debug: print 'C'
    mov     rax, 1
    mov     rdi, 2
    push    0x43 ; 'C'
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    pop     rax

    call    main_compile

    ; close output
    mov     eax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall

    ; exit 0
    mov     eax, SYS_EXIT
    xor     edi, edi
    syscall

.bad_args:
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall

; =============================================================================
; Utility Functions
; =============================================================================

; die — write msg to stderr and exit(1)
die:
    mov     rax, SYS_WRITE
    mov     rdx, rsi
    mov     rsi, rdi
    mov     edi, 2
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 1
    syscall

; strncmp_src: compare src_buf[rbx..rbx+rcx] with nul-terminated string rdx
strncmp_src:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    mov     r8, rbx
    mov     rsi, rcx
.snc_loop:
    cmp     rsi, 0
    je      .snc_check_nul
    mov     al, [rdx]
    cmp     al, 0
    je      .snc_fail
    lea     rdi, [src_buf]
    add     rdi, r8
    mov     bl, [rdi]
    cmp     al, bl
    jne     .snc_fail
    inc     r8
    inc     rdx
    dec     rsi
    jmp     .snc_loop
.snc_check_nul:
    cmp     byte [rdx], 0
    jne     .snc_fail
    mov     rax, 1
    jmp     .snc_done
.snc_fail:
    xor     rax, rax
.snc_done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; emit functions
emit1:
    mov     rax, [cod_len]
    lea     rbx, [cod_buf]
    add     rbx, rax
    mov     [rbx], dil
    inc     qword [cod_len]
    ret

emit4:
    mov     rax, [cod_len]
    lea     rbx, [cod_buf]
    add     rbx, rax
    mov     [rbx], edi
    add     qword [cod_len], 4
    ret

emit8:
    mov     rax, [cod_len]
    lea     rbx, [cod_buf]
    add     rbx, rax
    mov     [rbx], rdi
    add     qword [cod_len], 8
    ret

; =============================================================================
; LEX_ALL — lex entire src_buf -> tok_buf, tok_cnt
; =============================================================================
lex_all:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_lex]
    mov     rdx, 4
    syscall
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    mov     qword [rbp-8], 0    ; pos
    mov     qword [rbp-16], 0   ; count
    mov     rax, [src_len]
    mov     [rbp-24], rax
.main_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .done_lex
    lea     rbx, [src_buf]
    add     rbx, rax
    movsx   rcx, byte [rbx]

    ; Skip whitespace
    cmp     cl, ' '
    je      .skip1
    cmp     cl, 9
    je      .skip1
    cmp     cl, 10
    je      .skip1
    cmp     cl, 13
    je      .skip1
    jmp     .not_ws
.skip1:
    inc     qword [rbp-8]
    jmp     .main_loop
.not_ws:
    ; Skip line comment
    cmp     cl, ';'
    jne     .not_semi
.semi_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .done_lex
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], 10
    je      .main_loop
    inc     qword [rbp-8]
    jmp     .semi_loop
.not_semi:
    ; String literal
    cmp     cl, '"'
    jne     .not_str
    inc     qword [rbp-8]
    mov     rax, [rbp-8]
    mov     [rbp-32], rax
.str_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .str_end
    lea     rbx, [src_buf]
    add     rbx, rax
    mov     cl, [rbx]
    cmp     cl, '"'
    je      .str_end
    cmp     cl, '\\'
    jne     .str_nc
    inc     qword [rbp-8]
.str_nc:
    inc     qword [rbp-8]
    jmp     .str_loop
.str_end:
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     qword [rdi], TOK_STR
    mov     rax, [rbp-32]
    mov     [rdi+8], rax
    mov     rax, [rbp-8]
    sub     rax, [rbp-32]
    mov     [rdi+16], rax
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    inc     qword [rbp-8]
    jmp     .main_loop
.not_str:
    ; Integer literal
    cmp     cl, '0'
    jl      .not_int
    cmp     cl, '9'
    jg      .not_int
    mov     r15, [rbp-8] ; start
.dec_int:
    xor     r14, r14
.dec_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .dec_done
    lea     rbx, [src_buf]
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
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     qword [rdi], TOK_INT
    mov     [rdi+8], r15
    mov     rax, [rbp-8]
    sub     rax, r15
    mov     [rdi+16], rax
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
    mov     r14, [rbp-8]
.ident_loop:
    mov     rax, [rbp-8]
    cmp     rax, [rbp-24]
    jge     .ident_done
    lea     rbx, [src_buf]
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
    mov     rax, [rbp-8]
    sub     rax, r14
    push    r14
    mov     rbx, r14
    mov     rcx, rax
    call    classify_kw
    pop     r14
    mov     r15, rax
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     [rdi], r15
    mov     [rdi+8], r14
    mov     rax, [rbp-8]
    sub     rax, r14
    mov     [rdi+16], rax
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
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], '>'
    jne     .single_char
    mov     r15, [rbp-8]
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
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .not_fat
    mov     r15, [rbp-8]
    add     qword [rbp-8], 2
    mov     r14, TOK_EQEQ
    jmp     .emit_op2
.not_fat:
    cmp     byte [rbx], '>'
    jne     .single_char
    mov     r15, [rbp-8]
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
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .single_char
    mov     r15, [rbp-8]
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
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .single_char
    mov     r15, [rbp-8]
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
    lea     rbx, [src_buf]
    add     rbx, rax
    cmp     byte [rbx], '='
    jne     .single_char
    mov     r15, [rbp-8]
    add     qword [rbp-8], 2
    mov     r14, TOK_GTEQ
    jmp     .emit_op2
.emit_op2:
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     [rdi], r14
    mov     [rdi+8], r15
    mov     qword [rdi+16], 2
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    jmp     .main_loop
.single_char:
    mov     r15, [rbp-8]
    push    rcx
    call    char_to_tok
    pop     rcx
    mov     r14, rax
    inc     qword [rbp-8]
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     [rdi], r14
    mov     [rdi+8], r15
    mov     qword [rdi+16], 1
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    jmp     .main_loop
.done_lex:
    mov     rsi, [rbp-16]
    imul    rsi, rsi, TOK_SZ
    lea     rdi, [tok_buf]
    add     rdi, rsi
    mov     qword [rdi], TOK_EOF
    mov     rax, [rbp-8]
    mov     [rdi+8], rax
    mov     qword [rdi+16], 0
    mov     qword [rdi+24], 0
    inc     qword [rbp-16]
    mov     rax, [rbp-16]
    mov     [tok_cnt], rax
    leave
    ret

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

classify_kw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rcx
    push    rdx
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
    mov     eax, TOK_IDENT
.ck_done:
    pop     rdx
    pop     rcx
    pop     rbx
    leave
    ret
""")

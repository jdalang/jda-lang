#!/usr/bin/env python3
"""gen_jda0_p4.py — Code generation, ELF writer, main_compile"""

print(r"""
; =============================================================================
; gen_expr — evaluate expression into rax; advances tok_pos
; Handles: INT, CHAR, STR, IDENT (local/global/const/fn-call), unary-, &, binary ops
; Note: complex LHS.field and x[i] are handled by gen_lvalue/gen_field
; =============================================================================
gen_expr:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    call    cur_tok_type
    cmp     rax, TOK_INT
    jne     .not_int
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

.not_int:
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
    cmp     rax, TOK_STR
    jne     .not_str
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    mov     r14, [sdt_len]
    lea     rbx, [src_buf]
    add     rbx, r12
    lea     rcx, [sdt_buf]
    add     rcx, [sdt_len]
    push    r13
.sdt_cp:
    cmp     r13, 0
    je      .sdt_cp_done
    mov     al, [rbx]
    cmp     al, '\\'
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
    mov     byte [rcx], 0
    add     qword [sdt_len], 1
    pop     r13
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x05
    call    emit1
    mov     rax, [sfix_cnt]
    imul    rax, 16
    lea     rbx, [fix_buf]
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    mov     [rbx+8], r14
    inc     qword [sfix_cnt]
    mov     rdi, 0
    call    emit4
    jmp     .maybe_binary

.not_str:
    cmp     rax, TOK_MINUS
    jne     .not_neg
    call    adv_tok
    call    gen_expr
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xF7
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    jmp     .maybe_binary

.not_neg:
    cmp     rax, TOK_AMP
    jne     .not_amp
    call    adv_tok
    call    gen_addr
    jmp     .maybe_binary

.not_amp:
    cmp     rax, TOK_IDENT
    je      .do_ident
    cmp     rax, TOK_PRINT
    je      .do_ident
    cmp     rax, TOK_SYSCALL
    je      .do_syscall_expr
    jmp     .literal_done

.do_ident:
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    mov     r14, [tok_pos]
    call    adv_tok
    call    cur_tok_type
    cmp     rax, TOK_LPAREN
    je      .do_call
    cmp     rax, TOK_DOT
    je      .do_field_access
    cmp     rax, TOK_LBRACK
    je      .do_array_access
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    je      .try_global
    mov     r12, [rax+16]
    mov     r15, [rax+40]
    cmp     r15, 1
    je      .load_local_b
    cmp     r15, 4
    je      .load_local_d
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .maybe_binary
.load_local_b:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .maybe_binary
.load_local_d:
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .maybe_binary

.try_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .try_const
    mov     r12, [rax+16]
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x87
    call    emit1
    mov     rdi, r12
    call    emit4
    jmp     .maybe_binary

.try_const:
    mov     r8, r12
    mov     r9, r13
    call    lookup_const
    cmp     rdx, 1
    jne     .try_fn
    mov     r12, rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, r12
    call    emit8
    jmp     .maybe_binary

.try_fn:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    jmp     .maybe_binary

.do_call:
    call    adv_tok
    push    r12
    push    r13
    xor     r14, r14
.call_arg_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .call_done_args
    cmp     rax, TOK_EOF
    je      .call_done_args
    call    gen_expr
    mov     rdi, 0x50
    call    emit1
    inc     r14
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .call_arg_loop
    call    adv_tok
    jmp     .call_arg_loop
.call_done_args:
    call    adv_tok
    pop     r13
    pop     r12
    cmp     r14, 6
    jl      .pop5
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59
    call    emit1
.pop5:
    cmp     r14, 5
    jl      .pop4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58
    call    emit1
.pop4:
    cmp     r14, 4
    jl      .pop3
    mov     rdi, 0x59
    call    emit1
.pop3:
    cmp     r14, 3
    jl      .pop2
    mov     rdi, 0x5A
    call    emit1
.pop2:
    cmp     r14, 2
    jl      .pop1
    mov     rdi, 0x5E
    call    emit1
.pop1:
    cmp     r14, 1
    jl      .real_call
    mov     rdi, 0x5F
    call    emit1
.real_call:
    push    r12
    push    r13
    push    r14
    mov     r8, r12
    mov     r9, r13
    call    lookup_fn
    pop     r14
    pop     r13
    pop     r12
    mov     rdi, 0xE8
    call    emit1
    cmp     rax, 0
    je      .call_unknown
    mov     rbx, rax
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
    imul    rax, 32
    lea     rbx, [fix_buf+8192]
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
    jmp     .maybe_binary

.do_syscall_expr:
    call    adv_tok
    call    adv_tok
    xor     r14, r14
.sc_arg_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .sc_done_args
    call    gen_expr
    mov     rdi, 0x50
    call    emit1
    inc     r14
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .sc_arg_loop
    call    adv_tok
    jmp     .sc_arg_loop
.sc_done_args:
    call    adv_tok
    cmp     r14, 7
    jl      .scp6
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59
    call    emit1
.scp6:
    cmp     r14, 6
    jl      .scp5
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58
    call    emit1
.scp5:
    cmp     r14, 5
    jl      .scp4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5A
    call    emit1
.scp4:
    cmp     r14, 4
    jl      .scp3
    mov     rdi, 0x5A
    call    emit1
.scp3:
    cmp     r14, 3
    jl      .scp2
    mov     rdi, 0x5E
    call    emit1
.scp2:
    cmp     r14, 2
    jl      .scp1
    mov     rdi, 0x5F
    call    emit1
.scp1:
    cmp     r14, 1
    jl      .sc_call_exec
    mov     rdi, 0x58
    call    emit1
.sc_call_exec:
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    jmp     .maybe_binary

.do_field_access:
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    je      .ff_global
    mov     r12, [rax+16]
    mov     r15, [rax+32]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .ff_start
.ff_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .maybe_binary
    mov     r12, [rax+16]
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x87
    call    emit1
    mov     rdi, r12
    call    emit4
    mov     r15, -1
.ff_start:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    call    adv_tok
    cmp     r15, -1
    je      .maybe_binary
    mov     rdi, r15
    call    find_field
    cmp     rax, 0
    je      .maybe_binary
    mov     r14, [rax+16]
    mov     rsi, [rax+24]
    cmp     rsi, 1
    je      .ff_load1
    cmp     rsi, 4
    je      .ff_load4
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, r14
    call    emit4
    jmp     .maybe_binary
.ff_load1:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0xB6
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, r14
    call    emit4
    jmp     .maybe_binary
.ff_load4:
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x83
    call    emit1
    mov     rdi, r14
    call    emit4
    jmp     .maybe_binary

.do_array_access:
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
    cmp     rax, TOK_PLUS
    je      .do_add
    cmp     rax, TOK_MINUS
    je      .do_sub
    cmp     rax, TOK_STAR
    je      .do_mul
    cmp     rax, TOK_EQEQ
    je      .do_cmp_eq
    cmp     rax, TOK_NEQ
    je      .do_cmp_ne
    cmp     rax, TOK_LT
    je      .do_cmp_lt
    cmp     rax, TOK_GT
    je      .do_cmp_gt
    cmp     rax, TOK_AND
    je      .do_and
    cmp     rax, TOK_OR
    je      .do_or
    jmp     .expr_done

.do_add:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr
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
    call    gen_expr
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
    call    gen_expr
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
.do_cmp_eq:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr
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
    call    gen_expr
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
    call    gen_expr
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
    call    gen_expr
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
.do_and:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x21
    call    emit1
    mov     rdi, 0xD8
    call    emit1
    jmp     .maybe_binary
.do_or:
    call    adv_tok
    mov     rdi, 0x50
    call    emit1
    call    gen_expr
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x09
    call    emit1
    mov     rdi, 0xD8
    call    emit1
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
    push    r12
    push    r13
    push    r14
    push    r15
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    je      .ga_global
    mov     r12, [rax+16]
    mov     r15, [rax+32]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x85
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .ga_check_suffix
.ga_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .ga_ret
    mov     r12, [rax+16]
    mov     r15, -1
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x87
    call    emit1
    mov     rdi, r12
    call    emit4
.ga_check_suffix:
    call    cur_tok_type
    cmp     rax, TOK_DOT
    jne     .ga_ret
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8B
    call    emit1
    mov     rdi, 0x00
    call    emit1
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    call    adv_tok
    cmp     r15, -1
    je      .ga_ret
    mov     rdi, r15
    call    find_field
    cmp     rax, 0
    je      .ga_ret
    mov     r14, [rax+16]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x05
    call    emit1
    mov     rdi, r14
    call    emit4
.ga_ret:
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
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_dot]
    mov     rdx, 1
    syscall
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
    cmp     rax, TOK_ASM
    je      .gs_asm
    cmp     rax, TOK_BREAK
    je      .gs_break
    cmp     rax, TOK_RBRACE
    je      .gs_done
    cmp     rax, TOK_EOF
    je      .gs_done
    call    gen_expr_stmt
    jmp     .gs_done

.gs_let:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok
    call    gen_expr
    push    rax
    push    r12
    push    r13
    mov     r8, r12
    mov     r9, r13
    mov     r10, 0
    mov     r11, -1
    mov     r12, 8
    call    add_local
    pop     r13
    pop     r12
    pop     rbx
    mov     r15, rax
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x9D
    call    emit1
    neg     r15
    mov     rdi, r15
    call    emit4
    jmp     .gs_done

.gs_if:
    call    adv_tok
    call    gen_expr
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1
    mov     r14, [cod_len]
    mov     rdi, 0
    call    emit4
    call    adv_tok
    call    gen_block_body
    mov     rdi, 0xE9
    call    emit1
    mov     r15, [cod_len]
    mov     rdi, 0
    call    emit4
    mov     rax, [cod_len]
    sub     rax, r14
    sub     rax, 4
    lea     rbx, [cod_buf]
    add     rbx, r14
    mov     [rbx], eax
    call    cur_tok_type
    cmp     rax, TOK_ELSE
    jne     .gs_if_no_else
    call    adv_tok
    call    adv_tok
    call    gen_block_body
.gs_if_no_else:
    mov     rax, [cod_len]
    sub     rax, r15
    sub     rax, 4
    lea     rbx, [cod_buf]
    add     rbx, r15
    mov     [rbx], eax
    jmp     .gs_done

.gs_loop:
    call    adv_tok
    mov     r14, [cod_len]
    call    gen_expr
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x85
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x84
    call    emit1
    mov     r15, [cod_len]
    mov     rdi, 0
    call    emit4
    push    qword [brk_lbl]
    mov     [brk_lbl], r15
    call    adv_tok
    call    gen_block_body
    mov     rdi, 0xE9
    call    emit1
    mov     rax, [cod_len]
    add     rax, 4
    sub     r14, rax
    mov     rdi, r14
    call    emit4
    mov     rax, [cod_len]
    sub     rax, r15
    sub     rax, 4
    lea     rbx, [cod_buf]
    add     rbx, r15
    mov     [rbx], eax
    pop     qword [brk_lbl]
    jmp     .gs_done

.gs_break:
    call    adv_tok
    mov     rdi, 0xE9
    call    emit1
    mov     rax, [brk_lbl]
    mov     r14, [cod_len]
    add     r14, 4
    sub     rax, r14
    mov     rdi, rax
    call    emit4
    jmp     .gs_done

.gs_ret:
    call    adv_tok
    call    gen_expr
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5C
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5D
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5E
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5F
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    jmp     .gs_done

.gs_print:
    call    adv_tok
    call    adv_tok
    call    gen_expr
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC6
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    mov     rdi, 0x80
    call    emit1
    mov     rdi, 0x3C
    call    emit1
    mov     rdi, 0x0E
    call    emit1
    mov     rdi, 0x00
    call    emit1
    mov     rdi, 0x74
    call    emit1
    mov     rdi, 4
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0xC1
    call    emit1
    mov     rdi, 0xEB
    call    emit1
    mov     rdi, -10
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xCA
    call    emit1
    mov     rdi, 0xBF
    call    emit1
    mov     rdi, 1
    call    emit4
    mov     rdi, 0xB8
    call    emit1
    mov     rdi, 1
    call    emit4
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    call    adv_tok
    jmp     .gs_done

.gs_asm:
    call    adv_tok
    call    adv_tok
.gs_asm_loop:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gs_asm_done
    call    get_cur_tok_ptr
    mov     r8, [rax+8]
    mov     r9, [rax+16]
    mov     rbx, r8
    mov     rcx, r9
    lea     rdx, [kw_out]
    call    strncmp_src
    cmp     rax, 1
    jne     .gs_asm_check_in
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r14, [rax+8]
    mov     r15, [rax+16]
    call    adv_tok
    mov     r8, r12
    mov     r9, r13
    call    lookup_local
    cmp     rax, 0
    je      .gs_asm_out_global
    mov     r12, [rax+16]
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xB5
    call    emit1
    neg     r12
    mov     rdi, r12
    call    emit4
    jmp     .gs_asm_loop
.gs_asm_out_global:
    mov     r8, r12
    mov     r9, r13
    call    lookup_global
    cmp     rax, 0
    je      .gs_asm_loop
    mov     r12, [rax+16]
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xB7
    call    emit1
    mov     rdi, r12
    call    emit4
    jmp     .gs_asm_loop
.gs_asm_check_in:
    mov     rbx, r8
    mov     rcx, r9
    lea     rdx, [kw_in]
    call    strncmp_src
    cmp     rax, 1
    jne     .gs_asm_skip
.gs_asm_skip:
    call    adv_tok
    jmp     .gs_asm_loop
.gs_asm_done:
    call    adv_tok
    jmp     .gs_done

.gs_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    leave
    ret

gen_block_body:
    push    rbp
    mov     rbp, rsp
.gbb_loop:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .gbb_done
    cmp     rax, TOK_EOF
    je      .gbb_done
    call    gen_stmt
    jmp     .gbb_loop
.gbb_done:
    call    adv_tok
    leave
    ret

gen_fn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     [cur_fn_ptr], rdi
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2G]
    mov     rdx, 1
    syscall
    mov     rax, [cod_len]
    mov     rcx, [cur_fn_ptr]
    mov     [rcx+40], rax
    mov     rdi, 0x55
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xE5
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x81
    call    emit1
    mov     rdi, 0xEC
    call    emit1
    mov     rax, [cod_len]
    mov     [cur_patch_off], rax
    mov     rdi, 256
    call    emit4
    mov     rdi, 0x53
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x54
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x55
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x56
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x57
    call    emit1
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2L]
    mov     rdx, 1
    syscall
    mov     qword [loc_cnt], 0
    mov     qword [loc_rbp], 0
    xor     rcx, rcx
.gf_param_loop:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2P]
    mov     rdx, 1
    syscall
    mov     r14, [cur_fn_ptr]
    mov     r12, [r14+24]
    cmp     rcx, r12
    jge     .gf_param_done
    mov     rax, rcx
    imul    rax, PRM_SZ
    lea     r13, [r14+64]
    add     r13, rax
    mov     r8, [r13]
    mov     r9, [r13+8]
    mov     r10, TK_SCALAR
    mov     r11, -1
    mov     rdx, [r13+16]
    mov     r15, [r13+24]
    test    r15, r15
    jns     .gf_param_type_done
    mov     r10, TK_PTR
    mov     rax, r15
    shl     rax, 1
    shr     rax, 1
    cmp     rax, 1000000
    ja      .gf_param_type_done
    mov     r11, rax
.gf_param_type_done:
    push    rdx
    push    r13
    push    rcx
    push    r12
    mov     r12, rdx
    call    add_local
    pop     r12
    pop     rcx
    pop     r13
    pop     rdx
    push    rax
    push    rcx
    push    r12
    push    r13
    cmp     rcx, 6
    jge     .gf_param_next
    cmp     rcx, 4
    jge     .gf_emit_rex_r
    mov     rdi, 0x48
    call    emit1
    jmp     .gf_emit_mov_op
.gf_emit_rex_r:
    mov     rdi, 0x4C
    call    emit1
.gf_emit_mov_op:
    mov     rdi, 0x89
    call    emit1
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
    cmp     rcx, 4
    je      .gf_store_r8
    cmp     rcx, 5
    je      .gf_store_r9
.gf_store_rdi:
    mov     rdi, 0xBD
    jmp     .gf_store_disp
.gf_store_rsi:
    mov     rdi, 0xB5
    jmp     .gf_store_disp
.gf_store_rdx:
    mov     rdi, 0x95
    jmp     .gf_store_disp
.gf_store_rcx:
    mov     rdi, 0x8D
    jmp     .gf_store_disp
.gf_store_r8:
    mov     rdi, 0x85
    jmp     .gf_store_disp
.gf_store_r9:
    mov     rdi, 0x8D
    jmp     .gf_store_disp
.gf_store_disp:
    call    emit1
    pop     r13
    pop     r12
    pop     rcx
    pop     rax
    neg     rax
    mov     rdi, rax
    call    emit4
    jmp     .gf_param_next_nostack
.gf_param_next:
    pop     r13
    pop     r12
    pop     rcx
    pop     rax
.gf_param_next_nostack:
    add     r13, PRM_SZ
    inc     rcx
    jmp     .gf_param_loop
.gf_param_done:
    mov     r14, [cur_fn_ptr]
    mov     rax, [r14+32]
    mov     [tok_pos], rax
    call    gen_block_body
    mov     rdi, 0x5B
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5C
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5D
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5E
    call    emit1
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x5F
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    mov     rdi, 0xC3
    call    emit1
    mov     rax, [loc_rbp]
    add     rax, 15
    and     rax, -16
    mov     r15, [cur_patch_off]
    lea     rbx, [cod_buf]
    add     rbx, r15
    mov     [rbx], eax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

p2_gen:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2s]
    mov     rdx, 13
    syscall
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC6
    call    emit1
    mov     rdi, 0x00
    call    emit1
    mov     rdi, 0x00
    call    emit1
    mov     rdi, 0x01
    call    emit1
    mov     rdi, 0x00
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC2
    call    emit1
    mov     rdi, 3
    call    emit4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC2
    call    emit1
    mov     rdi, 0x22
    call    emit4
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, -1
    call    emit4
    mov     rdi, 0x45
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xC9
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 9
    call    emit4
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    mov     rdi, 0x49
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x8D
    call    emit1
    mov     rdi, 0x74
    call    emit1
    mov     rdi, 0x24
    call    emit1
    mov     rdi, 0x08
    call    emit1
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2c]
    mov     rdx, 18
    syscall
    mov     rdi, 0xE8
    call    emit1
    mov     rax, [fix_cnt]
    imul    rax, 32
    lea     rbx, [fix_buf+8192]
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    mov     qword [rbx+8], -2
    mov     qword [rbx+16], 4
    mov     qword [rbx+24], 2
    inc     qword [fix_cnt]
    mov     rdi, 0
    call    emit4
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0xC7
    call    emit1
    mov     rdi, 0xC0
    call    emit1
    mov     rdi, 60
    call    emit4
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x31
    call    emit1
    mov     rdi, 0xFF
    call    emit1
    mov     rdi, 0x0F
    call    emit1
    mov     rdi, 0x05
    call    emit1
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2f]
    mov     rdx, 16
    syscall
    xor     r12, r12
.p2_loop:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2i]
    mov     rdx, 1
    syscall
    cmp     r12, [fn_cnt]
    jge     .p2_done
    mov     rax, r12
    imul    rax, FN_SZ
    lea     rbx, [fn_tbl]
    add     rbx, rax
    mov     rdi, rbx
    call    gen_fn
    inc     r12
    jmp     .p2_loop
.p2_done:
    xor     r12, r12
.p2_fix:
    cmp     r12, [fix_cnt]
    jge     .p2_fix_done
    mov     rax, r12
    imul    rax, 32
    lea     rbx, [fix_buf+8192]
    add     rbx, rax
    mov     r13, [rbx]
    mov     r14, [rbx+24]
    cmp     r14, 2
    je      .p2_fix_main
    mov     r8, [rbx+8]
    mov     r9, [rbx+16]
    call    lookup_fn
    cmp     rax, 0
    je      .p2_fix_next
    cmp     qword [rax+40], -1
    je      .p2_fix_next
    mov     r15, [rax+40]
    jmp     .p2_fix_patch
.p2_fix_main:
    xor     rcx, rcx
.p2_find_main:
    cmp     rcx, [fn_cnt]
    jge     .p2_fix_next
    mov     rax, rcx
    imul    rax, FN_SZ
    lea     r14, [fn_tbl]
    add     r14, rax
    mov     r8, [r14]
    mov     r9, [r14+8]
    cmp     r9, 4
    jne     .p2_find_main_next
    lea     rdx, [src_buf]
    add     rdx, r8
    cmp     byte [rdx], 'm'
    jne     .p2_find_main_next
    cmp     byte [rdx+1], 'a'
    jne     .p2_find_main_next
    cmp     byte [rdx+2], 'i'
    jne     .p2_find_main_next
    cmp     byte [rdx+3], 'n'
    jne     .p2_find_main_next
    mov     r15, [r14+40]
    jmp     .p2_fix_patch
.p2_find_main_next:
    inc     rcx
    jmp     .p2_find_main
.p2_fix_patch:
    mov     rax, r13
    add     rax, 4
    sub     r15, rax
    lea     rbx, [cod_buf]
    add     rbx, r13
    mov     [rbx], r15d
.p2_fix_next:
    inc     r12
    jmp     .p2_fix
.p2_fix_done:
    xor     r12, r12
.p2_sfix:
    cmp     r12, [sfix_cnt]
    jge     .p2_done2
    mov     rax, r12
    imul    rax, 16
    lea     rbx, [fix_buf]
    add     rbx, rax
    mov     r13, [rbx]
    mov     r14, [rbx+8]
    mov     r15, [cod_len]
    add     r15, r14
    sub     r15, r13
    sub     r15, 4
    lea     rbx, [cod_buf]
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

gen_expr_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    push    r15
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    mov     r14, [tok_pos]
    call    adv_tok
    call    cur_tok_type
    cmp     rax, TOK_EQ
    je      .ges_assign
    cmp     rax, TOK_DOT
    je      .ges_assign
    cmp     rax, TOK_LBRACK
    je      .ges_assign
    cmp     rax, TOK_LPAREN
    jne     .ges_done
    call    adv_tok
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
    cmp     r14, 6
    jl      .gpop5
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x59
    call    emit1
.gpop5:
    cmp     r14, 5
    jl      .gpop4
    mov     rdi, 0x41
    call    emit1
    mov     rdi, 0x58
    call    emit1
.gpop4:
    cmp     r14, 4
    jl      .gpop3
    mov     rdi, 0x59
    call    emit1
.gpop3:
    cmp     r14, 3
    jl      .gpop2
    mov     rdi, 0x5A
    call    emit1
.gpop2:
    cmp     r14, 2
    jl      .gpop1
    mov     rdi, 0x5E
    call    emit1
.gpop1:
    cmp     r14, 1
    jl      .ges_call
    mov     rdi, 0x5F
    call    emit1
.ges_call:
    mov     rdi, 0xE8
    call    emit1
    push    r12
    push    r13
    push    r14
    mov     r8, r12
    mov     r9, r13
    call    lookup_fn
    pop     r14
    pop     r13
    pop     r12
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
    jmp     .ges_done
.ges_fixup:
    mov     rax, [fix_cnt]
    imul    rax, 32
    lea     rbx, [fix_buf+8192]
    add     rbx, rax
    mov     rax, [cod_len]
    mov     [rbx], rax
    mov     [rbx+8], r12
    mov     [rbx+16], r13
    mov     qword [rbx+24], 1
    inc     qword [fix_cnt]
    mov     rdi, 0
    call    emit4
    jmp     .ges_done
.ges_assign:
    mov     [tok_pos], r14
    call    gen_addr
    push    rax
    mov     rdi, TOK_EQ
    call    expect_tok
    call    gen_expr
    pop     rbx
    cmp     qword [lv_isptr], 0
    jne     .ges_store8
    mov     r15, [lv_sid]
    cmp     r15, -1
    jne     .ges_store8
    mov     r15, [lv_esz]
    cmp     r15, 1
    je      .ges_store1
    cmp     r15, 4
    je      .ges_store4
.ges_store8:
    mov     rdi, 0x48
    call    emit1
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x03
    call    emit1
    jmp     .ges_done
.ges_store1:
    mov     rdi, 0x88
    call    emit1
    mov     rdi, 0x03
    call    emit1
    jmp     .ges_done
.ges_store4:
    mov     rdi, 0x89
    call    emit1
    mov     rdi, 0x03
    call    emit1
.ges_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    leave
    ret

write_elf:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rdx
    mov     r14, r8
    mov     r15, 0x78
    add     r15, r13
    add     r15, r14
    sub     rsp, 0x78
    mov     rdi, rsp
    push    r15
    mov     rcx, 0x78
.zz:
    dec     rcx
    mov     byte [rdi+rcx], 0
    jnz     .zz
    pop     r15
    mov     dword [rdi+0], 0x464C457F
    mov     byte [rdi+4], 2
    mov     byte [rdi+5], 1
    mov     byte [rdi+6], 1
    mov     word [rdi+16], 2
    mov     word [rdi+18], 62
    mov     dword [rdi+20], 1
    mov     qword [rdi+24], 0x400078
    mov     qword [rdi+32], 64
    mov     qword [rdi+40], 0
    mov     dword [rdi+48], 0
    mov     word [rdi+52], 64
    mov     word [rdi+54], 56
    mov     word [rdi+56], 1
    mov     word [rdi+58], 64
    mov     word [rdi+60], 0
    mov     word [rdi+62], 0
    lea     rbx, [rdi+64]
    mov     dword [rbx+0], 1
    mov     dword [rbx+4], PF_RWX
    mov     qword [rbx+8], 0
    mov     qword [rbx+16], 0x400000
    mov     qword [rbx+24], 0x400000
    mov     [rbx+32], r15
    mov     [rbx+40], r15
    mov     qword [rbx+48], 0x200000
    mov     eax, SYS_WRITE
    mov     edi, r12d
    mov     rsi, rsp
    mov     edx, 0x78
    syscall
    mov     eax, SYS_WRITE
    mov     edi, r12d
    lea     rsi, [cod_buf]
    mov     rdx, r13
    syscall
    cmp     r14, 0
    je      .we_done
    mov     eax, SYS_WRITE
    mov     edi, r12d
    lea     rsi, [sdt_buf]
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

main_compile:
    push    rbp
    mov     rbp, rsp
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_lex]
    mov     rdx, 4
    syscall
    call    lex_all
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p1]
    mov     rdx, 3
    syscall
    call    p1_scan
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_p2]
    mov     rdx, 3
    syscall
    mov     qword [cod_len], 0
    mov     qword [sdt_len], 0
    mov     qword [fix_cnt], 0
    mov     qword [glb_r15], 0
    call    p2_gen
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [dbg_elf]
    mov     rdx, 4
    syscall
    mov     rdi, [out_fd]
    lea     rsi, [cod_buf]
    mov     rdx, [cod_len]
    lea     rcx, [sdt_buf]
    mov     r8,  [sdt_len]
    call    write_elf
    leave
    ret
""")

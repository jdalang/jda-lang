#!/usr/bin/env python3
"""gen_jda0_p3.py — Pass 1: scan for declarations (const, struct, fn)"""

print(r"""
; =============================================================================
; Token cursor helpers (use tok_pos global)
; =============================================================================
get_cur_tok_ptr:
    mov     rax, [tok_pos]
    imul    rax, rax, TOK_SZ
    lea     rdx, [tok_buf]
    add     rax, rdx
    ret

adv_tok:
    inc     qword [tok_pos]
    ret

cur_tok_type:
    call    get_cur_tok_ptr
    mov     rax, [rax]
    ret

expect_tok:
    push    rdi
    call    cur_tok_type
    pop     rdi
    cmp     rax, rdi
    jne     .bad_tok
    call    adv_tok
    ret
.bad_tok:
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
    jne     .sne_diff
    push    rcx
    push    rsi
    push    rdi
    lea     rsi, [src_buf]
    add     rsi, r8
    lea     rdi, [src_buf]
    add     rdi, r10
    mov     rcx, r9
    repe    cmpsb
    pop     rdi
    pop     rsi
    pop     rcx
    jne     .sne_diff
    mov     rax, 1
    ret
.sne_diff:
    xor     rax, rax
    ret

; =============================================================================
; lookup_const: r8=name_start, r9=name_len -> rax=value, rdx=1/0 (found)
; =============================================================================
lookup_const:
    push    rbx
    push    rcx
    push    r12
    xor     rcx, rcx
.lc_loop:
    cmp     rcx, [cst_cnt]
    jge     .lc_fail
    mov     rax, rcx
    imul    rax, rax, CST_SZ
    lea     rbx, [cst_tbl]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    cmp     rax, 1
    je      .lc_hit
    inc     rcx
    jmp     .lc_loop
.lc_hit:
    mov     rax, [rdx+16]
    mov     rdx, 1
    pop     r12
    pop     rcx
    pop     rbx
    ret
.lc_fail:
    xor     rdx, rdx
    pop     r12
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; lookup_struct: r8=ns, r9=nl -> rax=struct_index (-1=not found)
; =============================================================================
lookup_struct:
    push    rbx
    push    rcx
    xor     rcx, rcx
.ls_loop:
    cmp     rcx, [stt_cnt]
    jge     .ls_fail
    mov     rax, rcx
    imul    rax, STR_SZ
    lea     rbx, [stt_tbl]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    cmp     rax, 1
    je      .ls_hit
    inc     rcx
    jmp     .ls_loop
.ls_hit:
    mov     rax, rcx
    pop     rcx
    pop     rbx
    ret
.ls_fail:
    mov     rax, -1
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; get_elem_sz: rdi=tok_type, rsi=name_start_in_src -> rax=elem_byte_size
; Returns actual element size for arrays (i8->1, i32->4, i64->8, struct->size)
; =============================================================================
get_elem_sz:
    cmp     rdi, TOK_I8
    je      .ges_1
    cmp     rdi, TOK_I32
    je      .ges_4
    cmp     rdi, TOK_I64
    je      .ges_8
    cmp     rdi, TOK_F64
    je      .ges_8
    cmp     rdi, TOK_IDENT
    je      .ges_struct
    mov     rax, 8
    ret
.ges_1: mov rax, 1; ret
.ges_4: mov rax, 4; ret
.ges_8: mov rax, 8; ret
.ges_struct:
    push    r10
    push    r11
    mov     r8, rsi
    mov     r9, 64 ; heuristic
    call    lookup_struct
    pop     r11
    pop     r10
    cmp     rax, -1
    je      .ges_8
    imul    rax, STR_SZ
    lea     rdx, [stt_tbl]
    add     rax, rdx
    mov     rax, [rax+16]
    ret

; =============================================================================
; P1_SCAN — Pass 1: scan token stream for const, struct, fn declarations
; =============================================================================
p1_scan:
    push    rbp
    mov     rbp, rsp
    mov     qword [tok_pos], 0
    mov     qword [cst_cnt], 0
    mov     qword [stt_cnt], 0
    mov     qword [fn_cnt],  0
    mov     qword [glb_cnt], 0
    mov     qword [lbl_seq], 0

.p1_loop:
    call    cur_tok_type
    cmp     rax, TOK_EOF
    je      .p1_done

    cmp     rax, TOK_LET
    je      .p1_let
    cmp     rax, TOK_CONST
    je      .p1_const
    cmp     rax, TOK_STRUCT
    je      .p1_struct
    cmp     rax, TOK_FN
    je      .p1_fn

    call    adv_tok
    jmp     .p1_loop

.p1_let:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r14, [rax+24]
    call    adv_tok
    mov     rax, [glb_cnt]
    imul    rax, GLB_SZ
    lea     rbx, [glb_tbl]
    add     rbx, rax
    mov     qword [rbx],    r12
    mov     qword [rbx+8],  r13
    mov     rax, [glb_r15]
    mov     qword [rbx+16], rax
    mov     qword [rbx+24], TK_SCALAR
    add     qword [glb_r15], 8
    inc     qword [glb_cnt]
    jmp     .p1_loop

.p1_const:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r14, [rax+24]
    call    adv_tok
    mov     rax, [cst_cnt]
    imul    rax, CST_SZ
    lea     rbx, [cst_tbl]
    add     rbx, rax
    mov     qword [rbx],    r12
    mov     qword [rbx+8],  r13
    mov     qword [rbx+16], r14
    inc     qword [cst_cnt]
    jmp     .p1_loop

.p1_struct:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    call    adv_tok
    mov     rax, [stt_cnt]
    imul    rax, STR_SZ
    lea     r14, [stt_tbl]
    add     r14, rax
    mov     qword [r14],    r12
    mov     qword [r14+8],  r13
    mov     qword [r14+16], 0
    mov     qword [r14+24], 0
    inc     qword [stt_cnt]
    xor     r15, r15
    xor     rbx, rbx
.p1_struct_loop:
    call    cur_tok_type
    cmp     rax, TOK_RBRACE
    je      .p1_struct_done
    cmp     rax, TOK_EOF
    je      .p1_done
    call    get_cur_tok_ptr
    mov     r8,  [rax+8]
    mov     r9,  [rax+16]
    call    adv_tok ; name
    call    adv_tok ; ':'
    call    cur_tok_type
    mov     r13, 0
    cmp     rax, TOK_AMP
    jne     .p1_struct_no_ptr
    mov     r13, 1
    call    adv_tok
    call    cur_tok_type
.p1_struct_no_ptr:
    mov     r10, rax
    call    get_cur_tok_ptr
    mov     r11, [rax+8]
    call    adv_tok
    mov     rdi, r10
    mov     rsi, r11
    call    get_elem_sz
    mov     rsi, rax
    call    cur_tok_type
    xor     rdi, rdi
    cmp     rax, TOK_LBRACK
    jne     .p1_struct_no_arr
    call    adv_tok
    call    get_cur_tok_ptr
    mov     rdi, [rax+24]
    call    adv_tok
    call    adv_tok
.p1_struct_no_arr:
    mov     rax, rsi
    cmp     rdi, 0
    je      .p1_struct_sz_ok
    imul    rax, rdi
.p1_struct_sz_ok:
    push    rax
    mov     rax, rbx
    imul    rax, FLD_SZ
    lea     rdx, [r14+32]
    add     rax, rdx
    mov     qword [rax],    r8
    mov     qword [rax+8],  r9
    mov     qword [rax+16], r15
    mov     qword [rax+24], rsi
    mov     qword [rax+32], rdi
    mov     qword [rax+40], -1
    pop     rax
    add     r15, rax
    inc     rbx
    jmp     .p1_struct_loop
.p1_struct_done:
    mov     qword [r14+16], r15
    mov     qword [r14+24], rbx
    call    adv_tok
    jmp     .p1_loop

.p1_fn:
    call    adv_tok
    call    get_cur_tok_ptr
    mov     r12, [rax+8]
    mov     r13, [rax+16]
    call    adv_tok
    mov     rax, [fn_cnt]
    imul    rax, FN_SZ
    lea     r14, [fn_tbl]
    add     r14, rax
    mov     qword [r14],    r12
    mov     qword [r14+8],  r13
    mov     qword [r14+16], 0
    mov     qword [r14+24], 0
    mov     qword [r14+32], 0
    mov     qword [r14+40], -1
    mov     qword [r14+48], 0
    call    adv_tok ; skip '('
    xor     rbx, rbx
.p1_fn_param_loop:
    call    cur_tok_type
    cmp     rax, TOK_RPAREN
    je      .p1_fn_param_done
    cmp     rax, TOK_EOF
    je      .p1_done
    call    get_cur_tok_ptr
    mov     r8,  [rax+8]
    mov     r9,  [rax+16]
    call    adv_tok ; name
    call    adv_tok ; ':'
    xor     r13, r13
    call    cur_tok_type
    cmp     rax, TOK_AMP
    jne     .p1_fn_no_ptr
    mov     r13, 1
    call    adv_tok
    call    cur_tok_type
.p1_fn_no_ptr:
    mov     r10, rax
    call    get_cur_tok_ptr
    mov     r11, [rax+8]
    mov     r12, [rax+16]
    call    adv_tok
    call    cur_tok_type
    cmp     rax, TOK_LBRACK
    jne     .p1_fn_p_no_arr
    call    adv_tok
    call    get_cur_tok_ptr
    mov     rax, [rax+24]
    call    adv_tok ; N
    call    adv_tok ; ]
.p1_fn_p_no_arr:
    mov     rdx, -1
    mov     rsi, 8
    cmp     r10, TOK_IDENT
    jne     .p1_fn_p_not_ident
    push    r8
    push    r9
    mov     r8, r11
    mov     r9, r12
    call    lookup_struct
    pop     r9
    pop     r8
    cmp     rax, -1
    je      .p1_fn_p_scalar
    mov     rdx, rax
    imul    rax, STR_SZ
    lea     rcx, [stt_tbl]
    add     rax, rcx
    mov     rsi, [rax+16]
    jmp     .p1_fn_p_scalar
.p1_fn_p_not_ident:
    mov     rdx, r10
    mov     rdi, r10
    mov     rsi, r11
    call    get_elem_sz
    mov     rsi, rax
.p1_fn_p_scalar:
    cmp     r13, 1
    jne     .p1_fn_p_store
    mov     rax, rdx
    or      rax, PTR_FLAG
    mov     rdx, rax
.p1_fn_p_store:
    mov     rax, rbx
    imul    rax, PRM_SZ
    lea     rcx, [r14+64]
    add     rax, rcx
    mov     qword [rax],    r8
    mov     qword [rax+8],  r9
    mov     qword [rax+16], rsi
    mov     qword [rax+24], rdx
    inc     rbx
    call    cur_tok_type
    cmp     rax, TOK_COMMA
    jne     .p1_fn_param_loop
    call    adv_tok
    jmp     .p1_fn_param_loop
.p1_fn_param_done:
    mov     qword [r14+24], rbx
    call    adv_tok
.p1_fn_skip_to_brace:
    call    cur_tok_type
    cmp     rax, TOK_LBRACE
    je      .p1_fn_body
    cmp     rax, TOK_EOF
    je      .p1_done
    call    adv_tok
    jmp     .p1_fn_skip_to_brace
.p1_fn_body:
    mov     rax, [tok_pos]
    inc     rax
    mov     [r14+32], rax
    mov     r15, 1
    call    adv_tok
.p1_fn_skip_loop:
    call    cur_tok_type
    cmp     rax, TOK_LBRACE
    jne     .p1_fn_skip_r
    inc     r15
    jmp     .p1_fn_skip_next
.p1_fn_skip_r:
    cmp     rax, TOK_RBRACE
    jne     .p1_fn_skip_next_check_eof
    dec     r15
    cmp     r15, 0
    je      .p1_fn_skip_done
.p1_fn_skip_next_check_eof:
    cmp     rax, TOK_EOF
    je      .p1_done
.p1_fn_skip_next:
    call    adv_tok
    jmp     .p1_fn_skip_loop
.p1_fn_skip_done:
    call    adv_tok
    inc     qword [fn_cnt]
    jmp     .p1_loop

.p1_done:
    leave
    ret

; =============================================================================
; lookup_fn: r8=ns, r9=nl -> rax=fn entry ptr, or 0 if not found
; =============================================================================
lookup_fn:
    push    rbx
    push    rcx
    xor     rcx, rcx
.lf_loop:
    cmp     rcx, [fn_cnt]
    jge     .lf_fail
    mov     rax, rcx
    imul    rax, FN_SZ
    lea     rbx, [fn_tbl]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    cmp     rax, 1
    je      .lf_hit
    inc     rcx
    jmp     .lf_loop
.lf_hit:
    mov     rax, rdx
    pop     rcx
    pop     rbx
    ret
.lf_fail:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; find_field: rdi=struct_idx, r8=fn_start, r9=fn_len -> rax=field_entry ptr (or 0)
; =============================================================================
find_field:
    push    rbx
    push    rcx
    push    r12
    mov     rax, rdi
    imul    rax, STR_SZ
    lea     rbx, [stt_tbl]
    add     rax, rbx
    mov     rcx, [rax+24]
    lea     r12, [rax+32]
    xor     rdx, rdx
.ff_loop:
    cmp     rdx, rcx
    jge     .ff_fail
    mov     rax, rdx
    imul    rax, FLD_SZ
    add     rax, r12
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rdx
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    pop     r10
    cmp     rax, 1
    je      .ff_hit
    inc     rdx
    jmp     .ff_loop
.ff_hit:
    mov     rax, r10
    pop     r12
    pop     rcx
    pop     rbx
    ret
.ff_fail:
    xor     rax, rax
    pop     r12
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; add_local: r8=ns, r9=nl, r10=tkind, r11=sid, r12=esz -> rax=rbp_offset
; Adds to loc_tbl, updates loc_rbp
; =============================================================================
add_local:
    push    rbx
    mov     rax, [loc_rbp]
    add     rax, r12
    add     rax, 7
    and     rax, -8
    mov     [loc_rbp], rax
    mov     rdx, [loc_cnt]
    imul    rdx, LOC_SZ
    lea     rbx, [loc_tbl]
    add     rbx, rdx
    mov     qword [rbx],    r8
    mov     qword [rbx+8],  r9
    mov     qword [rbx+16], rax
    mov     qword [rbx+24], r10
    mov     qword [rbx+32], r11
    mov     qword [rbx+40], r12
    inc     qword [loc_cnt]
    pop     rbx
    ret

; =============================================================================
; lookup_local: r8=ns, r9=nl -> rax=loc entry ptr, or 0 if not found
; =============================================================================
lookup_local:
    push    rbx
    push    rcx
    xor     rcx, rcx
.ll_loop:
    cmp     rcx, [loc_cnt]
    jge     .ll_fail
    mov     rax, rcx
    imul    rax, LOC_SZ
    lea     rbx, [loc_tbl]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    cmp     rax, 1
    je      .ll_hit
    inc     rcx
    jmp     .ll_loop
.ll_hit:
    mov     rax, rdx
    pop     rcx
    pop     rbx
    ret
.ll_fail:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; add_global: r8=ns, r9=nl, r10=tkind -> rax=r15_offset
; =============================================================================
add_global:
    push    rbx
    mov     rax, [glb_cnt]
    imul    rax, GLB_SZ
    lea     rbx, [glb_tbl]
    add     rbx, rax
    mov     qword [rbx],    r8
    mov     qword [rbx+8],  r9
    mov     rax, [glb_r15]
    mov     qword [rbx+16], rax
    mov     qword [rbx+24], r10
    add     qword [glb_r15], 8
    inc     qword [glb_cnt]
    pop     rbx
    ret

; =============================================================================
; lookup_global: r8=ns, r9=nl -> rax=glb entry ptr, or 0
; =============================================================================
lookup_global:
    push    rbx
    push    rcx
    xor     rcx, rcx
.lg_loop:
    cmp     rcx, [glb_cnt]
    jge     .lg_fail
    mov     rax, rcx
    imul    rax, GLB_SZ
    lea     rbx, [glb_tbl]
    add     rax, rbx
    mov     r10, [rax]
    mov     r11, [rax+8]
    push    rax
    push    rcx
    call    src_name_eq
    pop     rcx
    pop     rdx
    cmp     rax, 1
    je      .lg_hit
    inc     rcx
    jmp     .lg_loop
.lg_hit:
    mov     rax, rdx
    pop     rcx
    pop     rbx
    ret
.lg_fail:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret
""")

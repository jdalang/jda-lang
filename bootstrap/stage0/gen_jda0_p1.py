#!/usr/bin/env python3
"""gen_jda0_p1.py — Common header, constants, memory layout"""

def o(s=''): print(s)

# Entry sizes
TOK_SZ = 32
CST_SZ = 32
FLD_SZ = 48
STR_SZ = 1024
FN_SZ  = 1024
PRM_SZ = 32
LOC_SZ = 64
GLB_SZ = 32

# Limits
MAX_TOK = 131072
MAX_CST = 1024
MAX_STR = 256
MAX_FN  = 1024
MAX_LOC = 512
MAX_GLB = 1024
COD_SZ  = 1048576
SDT_SZ  = 262144
FIX_SZ  = 65536

# Aligned with jda1.jda constants (0-39) + Stage 0 extras (40+)
TOKS = [
    ('TOK_FN',0),('TOK_LET',1),('TOK_IF',2),('TOK_ELSE',3),('TOK_LOOP',4),
    ('TOK_RET',5),('TOK_STRUCT',6),('TOK_MATCH',7),('TOK_PRINT',8),
    ('TOK_SYSCALL',9),('TOK_IDENT',10),('TOK_INT',11),('TOK_STR',12),
    ('TOK_LPAREN',13),('TOK_RPAREN',14),('TOK_LBRACE',15),('TOK_RBRACE',16),
    ('TOK_LBRACK',17),('TOK_RBRACK',18),('TOK_COMMA',19),('TOK_COLON',20),
    ('TOK_SEMI',21),('TOK_ARROW',22),('TOK_EQ',23),('TOK_EQEQ',24),
    ('TOK_NEQ',25),('TOK_LT',26),('TOK_GT',27),('TOK_PLUS',28),
    ('TOK_MINUS',29),('TOK_STAR',30),('TOK_SLASH',31),('TOK_AMP',32),
    ('TOK_DOT',33),('TOK_FATARROW',34),('TOK_EOF',35),('TOK_I64',36),
    ('TOK_I32',37),('TOK_I8',38),('TOK_F64',39),
    ('TOK_CHAR',40),('TOK_LTEQ',41),('TOK_GTEQ',42),('TOK_CONST',43),
    ('TOK_ASM',44),('TOK_BREAK',45),('TOK_OR',46),('TOK_AND',47)
]

def header():
    o('; Jda Stage 0 Bootstrap Compiler (x86-64 NASM)')
    o('bits 64')
    o('global _start')
    o()
    o('; --- System Calls (Linux x64) ---')
    o('SYS_READ         equ 0')
    o('SYS_WRITE        equ 1')
    o('SYS_OPEN         equ 2')
    o('SYS_CLOSE        equ 3')
    o('SYS_MMAP         equ 9')
    o('SYS_MUNMAP       equ 11')
    o('SYS_EXIT         equ 60')
    o()
    o('; --- ELF constants ---')
    for n,v in [('PT_LOAD',1),('ET_EXEC',2),('EM_X86_64',62),
                ('PF_RWX',7),('PROT_RW',3),('MAP_PA',0x22)]:
        o(f'{n:16} equ {v}')
    o()
    o('; Table entry sizes')
    for n,v in [('TOK_SZ',TOK_SZ),('CST_SZ',CST_SZ),('FLD_SZ',FLD_SZ),
                ('STR_SZ',STR_SZ),('FN_SZ',FN_SZ),('PRM_SZ',PRM_SZ),
                ('LOC_SZ',LOC_SZ),('GLB_SZ',GLB_SZ)]:
        o(f'{n:16} equ {v}')
    o()
    o('; Token type constants')
    for n,v in TOKS:
        o(f'{n:16} equ {v}')
    o()
    o('; Type kind')
    o('TK_SCALAR        equ 0')
    o('TK_STRUCT        equ 1')
    o('TK_PTR           equ 2')
    o('PTR_FLAG         equ 0x8000000000000000')

def bss():
    o()
    o('section .bss')
    entries=[
        ('src_buf',  1048576),
        ('tok_buf',  MAX_TOK*TOK_SZ),
        ('tok_cnt',  8),
        ('tok_pos',  8),
        ('cst_tbl',  MAX_CST*CST_SZ),
        ('cst_cnt',  8),
        ('stt_tbl',  MAX_STR*STR_SZ),
        ('stt_cnt',  8),
        ('fn_tbl',   MAX_FN*FN_SZ),
        ('fn_cnt',   8),
        ('loc_tbl',  MAX_LOC*LOC_SZ),
        ('loc_cnt',  8),
        ('loc_rbp',  8),
        ('glb_tbl',  MAX_GLB*GLB_SZ),
        ('glb_cnt',  8),
        ('glb_r15',  8),
        ('cod_buf',  COD_SZ),
        ('cod_len',  8),
        ('sdt_buf',  SDT_SZ),
        ('sdt_len',  8),
        ('fix_buf',  FIX_SZ),
        ('fix_cnt',  8),
        ('sfix_cnt', 8),
        ('jmp_stk',  4096),
        ('brk_lbl',  8),
        ('cur_fn_ptr', 8),
        ('cur_patch_off', 8),
        ('src_len',  8),
        ('out_fd',   8),
        ('lv_isptr', 8),
        ('lv_esz',   8),
        ('lv_sid',   8),
        ('lbl_seq',   8)
    ]
    for n,v in entries:
        o(f'{n:16} resb {v}')
    o()
    o('section .data')
    o('dbg_lex: db "LEX ", 0')
    o('dbg_p1:  db "P1 ", 0')
    o('dbg_p2:  db "P2 ", 0')
    o('dbg_elf: db "ELF", 10, 0')
    o('dbg_p2s: db "P2_gen_start", 10, 0')
    o('dbg_p2c: db "P2_main_call_emit", 10, 0')
    o('dbg_p2f: db "P2_gen_finished", 10, 0')
    o('dbg_p2G: db "G", 0')
    o('dbg_p2L: db "L", 0')
    o('dbg_p2P: db "P", 0')
    o('dbg_p2i: db "i", 0')
    o('dbg_dot: db ".", 0')
    o('m_ok:    db "OK", 10')
    o('m_ok_l:  equ $ - m_ok')
    o('m_err:   db "Error", 10')
    o('m_err_l: equ $ - m_err')
    o('m_usage: db "Usage: jda0 <src.jda> <out_bin>", 10')
    o('m_usage_l: equ $ - m_usage')
    o('kw_fn:      db "fn", 0')
    o('kw_let:     db "let", 0')
    o('kw_if:      db "if", 0')
    o('kw_else:    db "else", 0')
    o('kw_loop:    db "loop", 0')
    o('kw_break:   db "break", 0')
    o('kw_ret:     db "return", 0')
    o('kw_struct:  db "struct", 0')
    o('kw_const:   db "const", 0')
    o('kw_asm:     db "asm", 0')
    o('kw_syscall: db "syscall", 0')
    o('kw_print:   db "print", 0')
    o('kw_in:      db "in", 0')
    o('kw_out:     db "out", 0')
    o('kw_match:   db "match", 0')
    o('kw_i64:     db "i64", 0')
    o('kw_i32:     db "i32", 0')
    o('kw_i8:      db "i8", 0')
    o('kw_f64:     db "f64", 0')
    o('kw_and:     db "and", 0')
    o('kw_or:      db "or", 0')
    o('kw_ok:      db "ok", 0')

if __name__ == "__main__":
    header()
    bss()
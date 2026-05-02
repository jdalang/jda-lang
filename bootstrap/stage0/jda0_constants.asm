; ============================================================
; AUTO-GENERATED CONSTANTS FROM jda1.jda
; DO NOT EDIT - Run: python3 tools/generate_jda0_constants.py
; ============================================================
;
; This file contains constant definitions automatically extracted from
; jda1.jda specification. It is included in jda0.asm via:
;   %include "jda0_constants.asm"
;
; REGENERATION:
;   When jda1.jda constants or structures change:
;   1. Run: python3 tools/generate_jda0_spec.py bootstrap/stage1/jda1.jda
;   2. Run: python3 tools/generate_jda0_constants.py
;   3. Commit the updated jda0_constants.asm
;
; FORMAT:
;   - Token type constants (TOK_*): enumeration values for token types
;   - Type constants (TYPE_*): enumeration values for data types
;   - Opcode constants (OP_*): enumeration values for JIR opcodes
;   - Structure sizes (*_SZ): byte sizes for structs
;   - AST node types (NODE_*): enumeration for AST node kinds
;   - System constants (SYS_*, ET_*, etc.): platform-specific values
;
; DEPENDENCIES:
;   - Requires: jda0_spec.py (auto-generated specification)
;   - Included by: jda0.asm (via %include directive)
;   - Used by: jda0 assembler code that references these constants
;
; ============================================================

; Token type constants
TOK_FN               equ 0
TOK_LET              equ 1
TOK_IF               equ 2
TOK_ELSE             equ 3
TOK_LOOP             equ 4
TOK_RET              equ 5
TOK_STRUCT           equ 6
TOK_MATCH            equ 7
TOK_PRINT            equ 8
TOK_SYSCALL          equ 9
TOK_IDENT            equ 10
TOK_INT              equ 11
TOK_STR              equ 12
TOK_LPAREN           equ 13
TOK_RPAREN           equ 14
TOK_LBRACE           equ 15
TOK_RBRACE           equ 16
TOK_LBRACK           equ 17
TOK_RBRACK           equ 18
TOK_COMMA            equ 19
TOK_COLON            equ 20
TOK_SEMI             equ 21
TOK_ARROW            equ 22
TOK_EQ               equ 23
TOK_EQEQ             equ 24
TOK_NEQ              equ 25
TOK_LT               equ 26
TOK_GT               equ 27
TOK_PLUS             equ 28
TOK_MINUS            equ 29
TOK_STAR             equ 30
TOK_SLASH            equ 31
TOK_AMP              equ 32
TOK_DOT              equ 33
TOK_FATARROW         equ 34
TOK_GTE              equ 35
TOK_LTE              equ 36
TOK_AND              equ 37
TOK_OR               equ 38
TOK_PIPE             equ 39
TOK_TILDE            equ 40
TOK_SHR              equ 41
TOK_SHL              equ 42
TOK_CONST            equ 43
TOK_EOF              equ 44
TOK_I64              equ 45
TOK_I32              equ 46
TOK_I8               equ 47
TOK_F64              equ 48


; Type constants
TYPE_VOID            equ 0
TYPE_I64             equ 1
TYPE_I32             equ 2
TYPE_I8              equ 3
TYPE_F64             equ 4
TYPE_PTR             equ 5
TYPE_PTR_FLAG        equ 65536
TYPE_PTR_I64         equ 65537
TYPE_PTR_I32         equ 65538
TYPE_PTR_I8          equ 65539


; Opcode constants
OP_CONST             equ 0
OP_ADD               equ 1
OP_SUB               equ 2
OP_MUL               equ 3
OP_DIV               equ 4
OP_NEG               equ 5
OP_CMP_EQ            equ 6
OP_CMP_NE            equ 7
OP_CMP_LT            equ 8
OP_CMP_GT            equ 9
OP_CMP_GTE           equ 10
OP_CMP_LTE           equ 11
OP_AND               equ 12
OP_OR                equ 13
OP_RET               equ 14
OP_BR                equ 15
OP_JMP               equ 16
OP_CALL              equ 17
OP_SYSCALL           equ 18
OP_STRLIT            equ 19
OP_STRLEN            equ 20
OP_STORE             equ 21
OP_LOAD              equ 22
OP_ADDR              equ 23
OP_LOAD_MEM          equ 24
OP_STORE_MEM         equ 25
OP_ALLOC             equ 26
OP_PRINT_INT         equ 27
OP_SHR               equ 28
OP_SHL               equ 29
OP_GADDR             equ 30
OP_ARGV_BASE         equ 31


; Structure sizes
BB_SZ                equ 24600
CST_SZ               equ 16
FIXUP_SZ             equ 32
FLD_SZ               equ 112
FN_SZ                equ 6305864
LOWER_SZ             equ 100464
NODE_SZ              equ 112
REGALLOC_SZ          equ 49256
STRUCTTABLE_SZ       equ 199184
TOK_SZ               equ 40
PRM_SZ               equ 32


; AST Node type constants
NODE_FN              equ 0
NODE_LET             equ 1
NODE_IF              equ 2
NODE_LOOP            equ 3
NODE_CALL            equ 4
NODE_BINOP           equ 5
NODE_IDENT           equ 6
NODE_INT             equ 7
NODE_STR             equ 8
NODE_RET             equ 9
NODE_BLOCK           equ 10
NODE_STRUCT          equ 11
NODE_FIELD           equ 12
NODE_MATCH           equ 13
NODE_PRINT           equ 14
NODE_SYSCALL         equ 15
NODE_FIELD_STORE     equ 16
NODE_STRUCT_INIT     equ 17
NODE_ADDR            equ 18
NODE_ARRAY_ALLOC     equ 19
NODE_INDEX_STORE     equ 20
NODE_DEREF           equ 21


; ============================================================
; SYSTEM CONSTANTS - Platform specific (x86-64 Linux)
; ============================================================

; System call numbers
SYS_READ             equ 0
SYS_WRITE            equ 1
SYS_OPEN             equ 2
SYS_CLOSE            equ 3
SYS_MMAP             equ 9
SYS_EXIT             equ 60

; ELF file format constants
ET_EXEC              equ 2
ET_DYN               equ 3
EM_X86_64            equ 62
PT_LOAD              equ 1
PF_RWX               equ 7

; Memory protection constants
PROT_RW              equ 3
MAP_PA               equ 34

; String table size
STR_SZ               equ 3104


; ============================================================
; COMPATIBILITY CONSTANTS - Used by jda0, not in jda1 spec
; ============================================================

; Additional token types
TOK_ASM              equ 41
TOK_BREAK            equ 42
TOK_CHAR             equ 45
TOK_LTEQ             equ 46
TOK_GTEQ             equ 47
TOK_ALLOC_PAGES      equ 51

; Type kind constants
TK_SCALAR            equ 0
TK_STRUCT            equ 1
TK_PTR               equ 2

; Additional size constants
LOC_SZ               equ 48
GLB_SZ               equ 32

; Pointer type flag
PTR_FLAG             equ 0x8000000000000000


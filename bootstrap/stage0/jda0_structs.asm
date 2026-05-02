; ============================================================
; AUTO-GENERATED STRUCT FIELD OFFSETS FROM jda1.jda
; DO NOT EDIT - Run: python3 tools/generate_jda0_structs.py
; ============================================================

; BasicBlock struct (size: 24600 bytes)
BB_ID                     equ 0
BB_INSTRS                 equ 8
BB_INSTR_CNT              equ 24584
BB_LABEL_OFF              equ 24592
BB_SZ                     equ 24600

; ConstVal struct (size: 12 bytes)
CST_FOUND                 equ 0
CST_VAL                   equ 4
CST_SZ                    equ 12

; Fixup struct (size: 32 bytes)
FIXUP_CODE_OFF            equ 0
FIXUP_TARGET_BB           equ 8
FIXUP_KIND                equ 16
FIXUP_STR_LEN             equ 24
FIXUP_SZ                  equ 32

; Instr struct (size: 96 bytes)
INSTR_OP                  equ 0
INSTR_ITYPE               equ 4
INSTR_ID                  equ 8
INSTR_DEAD                equ 16
INSTR_PAD                 equ 20
INSTR_OPERAND0            equ 24
INSTR_OPERAND1            equ 32
INSTR_OPERAND2            equ 40
INSTR_OPERAND3            equ 48
INSTR_IMM                 equ 56
INSTR_STR_START           equ 64
INSTR_STR_LEN             equ 72
INSTR_BB_TARGET0          equ 80
INSTR_BB_TARGET1          equ 88
INSTR_SZ                  equ 96

; JirFunction struct (size: 791873 bytes)
FN_SRC                    equ 0
FN_SRC_LEN                equ 1
FN_BLOCKS                 equ 9
FN_BLOCK_CNT              equ 787209
FN_VARS                   equ 787217
FN_VAR_CNT                equ 791313
FN_NEXT_SLOT_OFF          equ 791321
FN_NEXT_ID                equ 791329
FN_STRTAB                 equ 791337
FN_STRTAB_POS             equ 791849
FN_STAB                   equ 791857
FN_PARAM_CNT              equ 791865
FN_SZ                     equ 791873

; LowerCtx struct (size: 100464 bytes)
LOWER_RA                  equ 0
LOWER_FIXUPS              equ 49256
LOWER_FIX_CNT             equ 82024
LOWER_BB_OFFSETS          equ 82032
LOWER_USE_CNT             equ 84080
LOWER_SZ                  equ 100464

; Node struct (size: 88 bytes)
NODE_NODE_TYPE            equ 0
NODE_OP                   equ 4
NODE_IMM                  equ 8
NODE_DATA_TYPE            equ 16
NODE_PARAM_CNT            equ 20
NODE_CHILD_CNT            equ 24
NODE_RET_TYPE             equ 28
NODE_TOKEN                equ 32
NODE_TOKEN2               equ 40
NODE_CHILD0               equ 48
NODE_CHILD1               equ 56
NODE_CHILD2               equ 64
NODE_CHILD3               equ 72
NODE_CHILDREN             equ 80
NODE_SZ                   equ 88

; RegAlloc struct (size: 49256 bytes)
REGALLOC_POOL             equ 0
REGALLOC_VAL2REG          equ 32
REGALLOC_REG2VAL          equ 16416
REGALLOC_SPILL_OFF        equ 16480
REGALLOC_SP_TOP           equ 49248
REGALLOC_SZ               equ 49256

; StructTable struct (size: 199184 bytes)
STRUCTTABLE_CNT           equ 0
STRUCTTABLE_NAMES         equ 8
STRUCTTABLE_NLENS         equ 520
STRUCTTABLE_FCNTS         equ 1032
STRUCTTABLE_SIZES         equ 1544
STRUCTTABLE_FBASES        equ 2056
STRUCTTABLE_FIELD_CNT     equ 2568
STRUCTTABLE_FNAMES        equ 2576
STRUCTTABLE_FLENS         equ 35344
STRUCTTABLE_FOFFS         equ 68112
STRUCTTABLE_FTYPES        equ 100880
STRUCTTABLE_FIS_ARRAY     equ 133648
STRUCTTABLE_FOWNERS       equ 166416
STRUCTTABLE_SZ            equ 199184

; Token struct (size: 40 bytes)
TOK_TYPE                  equ 0
TOK_PAD                   equ 8
TOK_STR_START             equ 16
TOK_STR_LEN               equ 24
TOK_IMM                   equ 32
TOK_SZ                    equ 40

; VarEntry struct (size: 32 bytes)
VAR_NAME_START            equ 0
VAR_NAME_LEN              equ 8
VAR_SLOT_OFF              equ 16
VAR_STYPE                 equ 24
VAR_SZ                    equ 32


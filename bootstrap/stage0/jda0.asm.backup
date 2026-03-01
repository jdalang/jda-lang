; =============================================================================
; Jda Stage 0 Compiler - x86-64 NASM Assembly
; =============================================================================
; Bootstrapper: Zero C, Zero libc. Direct Linux syscalls only.
;
; Supported minimal Jda syntax:
;   fn main() {
;       print("any string here")
;   }
; Bootstrap mode:
;   - If source looks like bootstrap/stage1/jda1.jda, emit a Stage1 shim
;     compiler binary by copying jda0 itself.
;
; Usage: jda0 <source.jda> <output_binary>
; Output: A valid ELF64 executable that prints the string and exits 0.
; =============================================================================

BITS 64
DEFAULT REL

; --- Linux Syscall Numbers ---
SYS_READ        equ 0
SYS_WRITE       equ 1
SYS_OPEN        equ 2
SYS_CLOSE       equ 3
SYS_LSEEK       equ 8
SYS_MMAP        equ 9
SYS_MUNMAP      equ 11
SYS_EXIT        equ 60
SYS_CREAT       equ 85
SYS_FSTAT       equ 5

; --- File Flags ---
O_RDONLY        equ 0
O_WRONLY        equ 1
O_CREAT         equ 64
O_TRUNC         equ 512
PROT_READ       equ 1
PROT_WRITE      equ 2
MAP_PRIVATE     equ 2
MAP_ANONYMOUS   equ 32

; --- ELF constants ---
ELFCLASS64      equ 2
ELFDATA2LSB     equ 1
ET_EXEC         equ 2
EM_X86_64       equ 62
EV_CURRENT      equ 1
PT_LOAD         equ 1
PF_R            equ 4
PF_W            equ 2
PF_X            equ 1

; --- Buffer Sizes ---
SOURCE_BUF_SIZE equ 65536       ; 64KB max source file
OUTPUT_BUF_SIZE equ 65536       ; 64KB output buffer

; =============================================================================
; BSS: Uninitialized data
; =============================================================================
section .bss
    source_buf      resb SOURCE_BUF_SIZE    ; Source file contents
    output_buf      resb OUTPUT_BUF_SIZE    ; Generated ELF output
    str_buf         resb 4096               ; Extracted print string
    source_len      resq 1                  ; Length of source file
    str_len         resq 1                  ; Length of extracted string
    exit_code       resq 1                  ; Parsed `ret <int>` exit code
    var_name_buf    resb 64                 ; Single let-binding variable name
    var_name_len    resq 1
    var_value       resq 1
    var_defined     resq 1

; =============================================================================
; DATA: Initialized data
; =============================================================================
section .data

    msg_usage       db "Usage: jda0 <source.jda> <output>", 10
    msg_usage_len   equ $ - msg_usage

    msg_ok          db "[jda0] Compiled successfully.", 10
    msg_ok_len      equ $ - msg_ok

    msg_err_args    db "[jda0] Error: requires 2 arguments.", 10
    msg_err_args_len equ $ - msg_err_args

    msg_err_open    db "[jda0] Error: cannot open source file.", 10
    msg_err_open_len equ $ - msg_err_open

    msg_err_create  db "[jda0] Error: cannot create output file.", 10
    msg_err_create_len equ $ - msg_err_create

    msg_err_parse   db "[jda0] Error: no print() call found in source.", 10
    msg_err_parse_len equ $ - msg_err_parse

    msg_bootstrap   db "[jda0] Bootstrap mode: emitted Stage1 shim compiler.", 10
    msg_bootstrap_len equ $ - msg_bootstrap

    ; Pattern we search for: print("
    pat_print       db `print("`, 0
    pat_print_len   equ 7
    pat_print_open  db "print(", 0
    pat_print_open_len equ 6
    pat_ret         db "ret", 0
    pat_ret_len     equ 3
    pat_let         db "let", 0
    pat_let_len     equ 3

    ; Signature used to detect Stage 1 source file
    pat_stage1_sig      db "Jda Stage 1 Compiler - Written in Jda"
    pat_stage1_sig_len  equ $ - pat_stage1_sig

    path_self_exe    db "/proc/self/exe", 0

    ; ELF64 Header template (64 bytes)
    ; We will patch: entry point, phoff, phnum, shoff
    elf_magic       db 0x7F, 'E', 'L', 'F'     ; Magic
                    db ELFCLASS64               ; 64-bit
                    db ELFDATA2LSB              ; Little endian
                    db EV_CURRENT               ; Version
                    db 0, 0, 0, 0, 0, 0, 0, 0, 0 ; OS/ABI + padding

    ; We build the ELF header in the output buffer at runtime.

; =============================================================================
; TEXT: Code
; =============================================================================
section .text
    global _start

_start:
    ; --- Check argument count ---
    ; rsp+0 = argc, rsp+8 = argv[0], rsp+16 = argv[1], rsp+24 = argv[2]
    mov     rax, [rsp]          ; argc
    cmp     rax, 3
    jl      .err_args

    mov     rbx, [rsp + 16]     ; argv[1] = source file path
    mov     r12, [rsp + 24]     ; argv[2] = output file path

    ; --- Open source file ---
    mov     rax, SYS_OPEN
    mov     rdi, rbx            ; filename
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .err_open
    mov     r13, rax            ; r13 = source fd

    ; --- Read source file ---
    mov     rax, SYS_READ
    mov     rdi, r13
    lea     rsi, [source_buf]
    mov     rdx, SOURCE_BUF_SIZE - 1
    syscall
    test    rax, rax
    jle     .err_open
    mov     [source_len], rax
    mov     byte [source_buf + rax], 0  ; null-terminate

    ; --- Close source file ---
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall

    ; --- Bootstrap path: if source is Stage 1 compiler, emit shim binary ---
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    lea     rsi, [pat_stage1_sig]
    mov     rdx, pat_stage1_sig_len
    call    find_substr
    test    rax, rax
    jz      .normal_compile

    call    emit_stage1_shim
    test    rax, rax
    jnz     .err_create

    ; --- Print bootstrap success ---
    mov     rax, SYS_WRITE
    mov     rdi, 1
    lea     rsi, [msg_bootstrap]
    mov     rdx, msg_bootstrap_len
    syscall

    mov     rax, SYS_EXIT
    xor     rdi, rdi
    syscall

.normal_compile:
    mov     qword [exit_code], 0
    mov     qword [var_defined], 0
    ; Optional: parse one `let <ident> = <int>` binding for identifier use
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_let_binding_int

    ; --- Parse: find print(" pattern ---
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_string
    test    rax, rax
    jz      .try_print_int

    ; rax = pointer to start of string content (after the quote)
    ; extract string until closing "
    mov     rsi, rax
    lea     rdi, [str_buf]
    xor     rcx, rcx
.copy_str:
    mov     al, byte [rsi + rcx]
    cmp     al, '"'
    je      .copy_done
    cmp     al, 0
    je      .err_parse
    cmp     rcx, 4095
    jge     .err_parse
    mov     byte [rdi + rcx], al
    inc     rcx
    jmp     .copy_str
.copy_done:
    mov     [str_len], rcx

    ; Optional: if source has `ret <int>`, preserve it as process exit code
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_ret_imm

    ; --- Build ELF64 binary in output_buf ---
    call    build_elf
    jmp     .write_output

.try_print_int:
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_int_expr
    test    rax, rax
    jnz     .after_print_int_parse

    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_int_literal
    test    rax, rax
    jz      .try_print_ident

    ; rax = start ptr of integer literal, rdx = length
    mov     rsi, rax
    lea     rdi, [str_buf]
    mov     rcx, rdx
    mov     [str_len], rcx
    test    rcx, rcx
    jz      .try_ret_compile
.copy_int_lit:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .copy_int_lit

.after_print_int_parse:
    ; Optional: preserve `ret <int>` as exit code
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_ret_imm

    call    build_elf
    jmp     .write_output

.try_print_ident:
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_ident_expr
    test    rax, rax
    jnz     .after_print_ident_parse

    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_ident_binding
    test    rax, rax
    jz      .try_ret_compile

.after_print_ident_parse:
    ; Optional: preserve `ret <int>` / `ret <ident>` as exit code
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_ret_imm
    call    build_elf
    jmp     .write_output

.try_ret_compile:
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_ret_imm
    test    rax, rax
    jz      .err_parse
    call    build_elf_exit_only

.write_output:
    ; --- Write output file ---
    mov     rax, SYS_OPEN
    mov     rdi, r12            ; output path
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0755o          ; rwxr-xr-x
    syscall
    test    rax, rax
    js      .err_create
    mov     r14, rax            ; r14 = output fd

    mov     rax, SYS_WRITE
    mov     rdi, r14
    lea     rsi, [output_buf]
    mov     rdx, [output_size]
    syscall

    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall

    ; --- Print success ---
    mov     rax, SYS_WRITE
    mov     rdi, 1
    lea     rsi, [msg_ok]
    mov     rdx, msg_ok_len
    syscall

    mov     rax, SYS_EXIT
    xor     rdi, rdi
    syscall

; --- Error handlers ---
.err_args:
    mov     rax, SYS_WRITE
    mov     rdi, 2
    lea     rsi, [msg_err_args]
    mov     rdx, msg_err_args_len
    syscall
    jmp     .exit1

.err_open:
    mov     rax, SYS_WRITE
    mov     rdi, 2
    lea     rsi, [msg_err_open]
    mov     rdx, msg_err_open_len
    syscall
    jmp     .exit1

.err_create:
    mov     rax, SYS_WRITE
    mov     rdi, 2
    lea     rsi, [msg_err_create]
    mov     rdx, msg_err_create_len
    syscall
    jmp     .exit1

.err_parse:
    mov     rax, SYS_WRITE
    mov     rdi, 2
    lea     rsi, [msg_err_parse]
    mov     rdx, msg_err_parse_len
    syscall

.exit1:
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

; =============================================================================
; find_print_string
; Input:  rdi = buffer start, rcx = buffer length
; Output: rax = pointer to char after the opening quote, or 0 on failure
; =============================================================================
find_print_string:
    push    rbx
    push    r15
    mov     rbx, rdi            ; buffer base
    mov     r15, rcx            ; length
    xor     r9, r9              ; index

.scan:
    cmp     r9, r15
    jge     .not_found
    ; Try to match print(" at position r9
    lea     rdi, [rbx + r9]
    lea     rsi, [pat_print]
    mov     rcx, pat_print_len
    call    memeq
    test    rax, rax
    jnz     .found
    inc     r9
    jmp     .scan

.found:
    lea     rax, [rbx + r9 + pat_print_len]  ; pointer just after print("
    pop     r15
    pop     rbx
    ret

.not_found:
    xor     rax, rax
    pop     r15
    pop     rbx
    ret

; =============================================================================
; find_substr
; Input:
;   rdi = haystack ptr
;   rcx = haystack len
;   rsi = needle ptr
;   rdx = needle len
; Output:
;   rax = ptr to first match, or 0 if not found
; =============================================================================
find_substr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r8
    push    r9

    mov     rbx, rdi        ; haystack base
    mov     r12, rcx        ; haystack len
    mov     r13, rsi        ; needle ptr
    mov     r14, rdx        ; needle len

    test    r14, r14
    jz      .fs_not_found
    cmp     r12, r14
    jb      .fs_not_found

    xor     r8, r8
    mov     r9, r12
    sub     r9, r14         ; max start index

.fs_scan:
    cmp     r8, r9
    ja      .fs_not_found
    lea     rdi, [rbx + r8]
    mov     rsi, r13
    mov     rcx, r14
    call    memeq
    test    rax, rax
    jnz     .fs_found
    inc     r8
    jmp     .fs_scan

.fs_found:
    lea     rax, [rbx + r8]
    jmp     .fs_done

.fs_not_found:
    xor     rax, rax

.fs_done:
    pop     r9
    pop     r8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; find_ret_imm
; Input:  rdi = source ptr, rcx = source len
; Output: rax = 1 on success, 0 on failure
; Side effect: [exit_code] = parsed integer
; =============================================================================
find_ret_imm:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi
    mov     r12, rcx

    lea     rsi, [pat_ret]
    mov     rdx, pat_ret_len
    call    find_substr
    test    rax, rax
    jz      .fri_fail

    ; Parse integer right after "ret", allowing spaces/tabs
    lea     r13, [rax + 3]
    mov     r14, 0

.fri_skip_ws:
    mov     al, [r13]
    cmp     al, ' '
    je      .fri_skip_adv
    cmp     al, 9               ; tab
    je      .fri_skip_adv
    jmp     .fri_digit_check
.fri_skip_adv:
    inc     r13
    jmp     .fri_skip_ws

.fri_digit_check:
    mov     al, [r13]
    mov     rbx, 0              ; sign flag
    cmp     al, '-'
    jne     .fri_after_sign
    mov     rbx, 1
    inc     r13
    mov     al, [r13]
.fri_after_sign:
    cmp     al, '0'
    jb      .fri_try_ident
    cmp     al, '9'
    ja      .fri_try_ident

.fri_parse_loop:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fri_after_first
    cmp     al, '9'
    ja      .fri_after_first
    imul    r14, r14, 10
    movzx   rax, al
    sub     rax, '0'
    add     r14, rax
    inc     r13
    jmp     .fri_parse_loop

.fri_after_first:
    cmp     rbx, 0
    je      .fri_store
    neg     r14
.fri_store:
    ; Optional binary op: ret <a> (+|-) <b>
.fri_ws_after_first:
    mov     al, [r13]
    cmp     al, ' '
    je      .fri_ws1_adv
    cmp     al, 9
    je      .fri_ws1_adv
    jmp     .fri_op_check
.fri_ws1_adv:
    inc     r13
    jmp     .fri_ws_after_first

.fri_op_check:
    mov     al, [r13]
    cmp     al, '+'
    je      .fri_have_op
    cmp     al, '-'
    je      .fri_have_op
    jmp     .fri_store_exit

.fri_have_op:
    mov     bl, al
    inc     r13
.fri_ws_rhs:
    mov     al, [r13]
    cmp     al, ' '
    je      .fri_ws_rhs_adv
    cmp     al, 9
    je      .fri_ws_rhs_adv
    jmp     .fri_rhs_sign
.fri_ws_rhs_adv:
    inc     r13
    jmp     .fri_ws_rhs

.fri_rhs_sign:
    mov     rcx, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .fri_rhs_token
    mov     rcx, 1
    inc     r13
    mov     al, [r13]

.fri_rhs_token:
    cmp     al, '0'
    jb      .fri_rhs_ident
    cmp     al, '9'
    jbe     .fri_rhs_digit_check

.fri_rhs_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .fri_store_exit
    cmp     rcx, 0
    jne     .fri_store_exit      ; disallow unary minus on identifier operand
    mov     r8, rax
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    mov     rsi, r13
    mov     rdx, r8
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .fri_store_exit
    mov     r15, [var_value]
    add     r13, r8
    jmp     .fri_rhs_apply

.fri_rhs_digit_check:
    cmp     al, '0'
    jb      .fri_store_exit
    cmp     al, '9'
    ja      .fri_store_exit
    xor     r15, r15
.fri_rhs_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fri_rhs_done
    cmp     al, '9'
    ja      .fri_rhs_done
    imul    r15, r15, 10
    movzx   rax, al
    sub     rax, '0'
    add     r15, rax
    inc     r13
    jmp     .fri_rhs_digits
.fri_rhs_done:
    cmp     rcx, 0
    je      .fri_rhs_apply
    neg     r15
.fri_rhs_apply:
    cmp     bl, '+'
    je      .fri_add_rhs
    sub     r14, r15
    jmp     .fri_store_exit
.fri_add_rhs:
    add     r14, r15

.fri_store_exit:
    mov     [exit_code], r14
    mov     rax, 1
    jmp     .fri_exit

.fri_try_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .fri_fail
    mov     r8, rax             ; save ident len
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    mov     rsi, r13            ; ident ptr
    mov     rdx, r8             ; ident len
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .fri_fail
    mov     r14, [var_value]
    add     r13, r8             ; consume identifier
    jmp     .fri_store

.fri_fail:
    xor     rax, rax

.fri_exit:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; find_print_int_expr
; Input:  rdi = source ptr, rcx = source len
; Output: rax = 1 on success (str_buf/str_len set), 0 on failure
; Supports: print(<int>) and print(<int> (+|-) <int>)
; =============================================================================
find_print_int_expr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi
    mov     r12, rcx
    lea     rsi, [pat_print_open]
    mov     rdx, pat_print_open_len
    call    find_substr
    test    rax, rax
    jz      .fpie_fail

    lea     r13, [rax + pat_print_open_len]

.fpie_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpie_ws1_adv
    cmp     al, 9
    je      .fpie_ws1_adv
    jmp     .fpie_first_sign
.fpie_ws1_adv:
    inc     r13
    jmp     .fpie_ws1

.fpie_first_sign:
    mov     rcx, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .fpie_first_digit_check
    mov     rcx, 1
    inc     r13
    mov     al, [r13]
.fpie_first_digit_check:
    cmp     al, '0'
    jb      .fpie_fail
    cmp     al, '9'
    ja      .fpie_fail
    xor     r14, r14
.fpie_first_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fpie_after_first
    cmp     al, '9'
    ja      .fpie_after_first
    imul    r14, r14, 10
    movzx   rax, al
    sub     rax, '0'
    add     r14, rax
    inc     r13
    jmp     .fpie_first_digits
.fpie_after_first:
    cmp     rcx, 0
    je      .fpie_after_first_sign
    neg     r14
.fpie_after_first_sign:

.fpie_ws2:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpie_ws2_adv
    cmp     al, 9
    je      .fpie_ws2_adv
    jmp     .fpie_op_or_close
.fpie_ws2_adv:
    inc     r13
    jmp     .fpie_ws2

.fpie_op_or_close:
    mov     al, [r13]
    cmp     al, ')'
    je      .fpie_emit
    cmp     al, '+'
    je      .fpie_have_op
    cmp     al, '-'
    je      .fpie_have_op
    jmp     .fpie_fail

.fpie_have_op:
    mov     bl, al
    inc     r13
.fpie_ws3:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpie_ws3_adv
    cmp     al, 9
    je      .fpie_ws3_adv
    jmp     .fpie_rhs_sign
.fpie_ws3_adv:
    inc     r13
    jmp     .fpie_ws3

.fpie_rhs_sign:
    mov     rcx, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .fpie_rhs_digit_check
    mov     rcx, 1
    inc     r13
    mov     al, [r13]
.fpie_rhs_digit_check:
    cmp     al, '0'
    jb      .fpie_fail
    cmp     al, '9'
    ja      .fpie_fail
    xor     r15, r15
.fpie_rhs_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fpie_rhs_done
    cmp     al, '9'
    ja      .fpie_rhs_done
    imul    r15, r15, 10
    movzx   rax, al
    sub     rax, '0'
    add     r15, rax
    inc     r13
    jmp     .fpie_rhs_digits
.fpie_rhs_done:
    cmp     rcx, 0
    je      .fpie_rhs_apply
    neg     r15
.fpie_rhs_apply:
    cmp     bl, '+'
    je      .fpie_add
    sub     r14, r15
    jmp     .fpie_expect_close
.fpie_add:
    add     r14, r15

.fpie_expect_close:
.fpie_ws4:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpie_ws4_adv
    cmp     al, 9
    je      .fpie_ws4_adv
    jmp     .fpie_check_close
.fpie_ws4_adv:
    inc     r13
    jmp     .fpie_ws4
.fpie_check_close:
    cmp     byte [r13], ')'
    jne     .fpie_fail

.fpie_emit:
    mov     rax, r14
    call    i64_to_str_buf
    mov     rax, 1
    jmp     .fpie_done

.fpie_fail:
    xor     rax, rax

.fpie_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; find_print_int_literal
; Input:  rdi = source ptr, rcx = source len
; Output: rax = pointer to int literal, rdx = length (includes optional '-')
;         rax = 0 on failure
; =============================================================================
find_print_int_literal:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r12, rcx

    lea     rsi, [pat_print_open]
    mov     rdx, pat_print_open_len
    call    find_substr
    test    rax, rax
    jz      .fpil_fail

    lea     r13, [rax + pat_print_open_len] ; cursor after "print("

.fpil_skip_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpil_adv1
    cmp     al, 9
    je      .fpil_adv1
    jmp     .fpil_sign_or_digit
.fpil_adv1:
    inc     r13
    jmp     .fpil_skip_ws1

.fpil_sign_or_digit:
    mov     r14, r13            ; literal start
    mov     al, [r13]
    cmp     al, '-'
    jne     .fpil_digit_check
    inc     r13
    mov     al, [r13]

.fpil_digit_check:
    cmp     al, '0'
    jb      .fpil_fail
    cmp     al, '9'
    ja      .fpil_fail

.fpil_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fpil_after_digits
    cmp     al, '9'
    ja      .fpil_after_digits
    inc     r13
    jmp     .fpil_digits

.fpil_after_digits:
    ; skip ws before ')'
.fpil_skip_ws2:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpil_adv2
    cmp     al, 9
    je      .fpil_adv2
    jmp     .fpil_expect_rparen
.fpil_adv2:
    inc     r13
    jmp     .fpil_skip_ws2

.fpil_expect_rparen:
    cmp     byte [r13], ')'
    jne     .fpil_fail

    ; length = end_of_literal - start
    mov     rdx, r13
    ; backtrack over ws to last digit
.fpil_trim_ws_back:
    cmp     byte [rdx - 1], ' '
    je      .fpil_dec_back
    cmp     byte [rdx - 1], 9
    je      .fpil_dec_back
    jmp     .fpil_len_ready
.fpil_dec_back:
    dec     rdx
    jmp     .fpil_trim_ws_back

.fpil_len_ready:
    sub     rdx, r14
    mov     rax, r14
    jmp     .fpil_done

.fpil_fail:
    xor     rax, rax
    xor     rdx, rdx

.fpil_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; find_let_binding_int
; Parses the last valid `let <ident> = <int>` and stores it in var_* globals.
; Input:  rdi = source ptr, rcx = source len
; Output: rax = 1 if binding found, 0 otherwise
; =============================================================================
find_let_binding_int:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi            ; source base
    mov     r12, rcx            ; source len
    cmp     r12, 4
    jb      .flbi_fail

    ; Scan backwards for last "let"
    mov     r11, r12
    sub     r11, 3              ; max index where "let" can start

.flbi_scan_back:
    cmp     r11, 0
    jl      .flbi_fail
    lea     r10, [rbx + r11]
    cmp     byte [r10 + 0], 'l'
    jne     .flbi_prev
    cmp     byte [r10 + 1], 'e'
    jne     .flbi_prev
    cmp     byte [r10 + 2], 't'
    jne     .flbi_prev

    lea     r13, [r10 + 3]
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_ws1
    cmp     al, 9
    je      .flbi_ws1
    jmp     .flbi_prev

.flbi_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_ws1_adv
    cmp     al, 9
    je      .flbi_ws1_adv
    jmp     .flbi_ident_start
.flbi_ws1_adv:
    inc     r13
    jmp     .flbi_ws1

.flbi_ident_start:
    mov     al, [r13]
    ; first char: [A-Za-z_]
    cmp     al, '_'
    je      .flbi_ident_ok
    cmp     al, 'A'
    jb      .flbi_prev
    cmp     al, 'Z'
    jbe     .flbi_ident_ok
    cmp     al, 'a'
    jb      .flbi_prev
    cmp     al, 'z'
    ja      .flbi_prev

.flbi_ident_ok:
    mov     r14, r13            ; ident start
    xor     r15, r15            ; ident len
.flbi_ident_loop:
    mov     al, [r13]
    cmp     al, '_'
    je      .flbi_ident_take
    cmp     al, '0'
    jb      .flbi_ident_chk_alpha
    cmp     al, '9'
    jbe     .flbi_ident_take
.flbi_ident_chk_alpha:
    cmp     al, 'A'
    jb      .flbi_ident_done
    cmp     al, 'Z'
    jbe     .flbi_ident_take
    cmp     al, 'a'
    jb      .flbi_ident_done
    cmp     al, 'z'
    ja      .flbi_ident_done
.flbi_ident_take:
    inc     r13
    inc     r15
    cmp     r15, 63
    jbe     .flbi_ident_loop
    jmp     .flbi_prev

.flbi_ident_done:
    test    r15, r15
    jz      .flbi_prev

    ; copy identifier to var_name_buf
    mov     [var_name_len], r15
    lea     rdi, [var_name_buf]
    mov     rsi, r14
    mov     rcx, r15
    rep movsb

.flbi_ws2:
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_ws2_adv
    cmp     al, 9
    je      .flbi_ws2_adv
    jmp     .flbi_expect_eq
.flbi_ws2_adv:
    inc     r13
    jmp     .flbi_ws2

.flbi_expect_eq:
    cmp     byte [r13], '='
    jne     .flbi_prev
    inc     r13

.flbi_ws3:
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_ws3_adv
    cmp     al, 9
    je      .flbi_ws3_adv
    jmp     .flbi_digit_check
.flbi_ws3_adv:
    inc     r13
    jmp     .flbi_ws3

.flbi_digit_check:
    mov     al, [r13]
    mov     r15, 0              ; sign flag
    cmp     al, '-'
    jne     .flbi_after_sign
    mov     r15, 1
    inc     r13
    mov     al, [r13]
.flbi_after_sign:
    cmp     al, '0'
    jb      .flbi_prev
    cmp     al, '9'
    ja      .flbi_prev
    xor     r14, r14
.flbi_parse_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .flbi_after_first
    cmp     al, '9'
    ja      .flbi_after_first
    imul    r14, r14, 10
    movzx   rax, al
    sub     rax, '0'
    add     r14, rax
    inc     r13
    jmp     .flbi_parse_digits

.flbi_after_first:
    cmp     r15, 0
    je      .flbi_base_ready
    neg     r14
.flbi_base_ready:
    ; Optional binary RHS: let x = <a> (+|-) <b>
.flbi_ws_after_first:
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_wsaf_adv
    cmp     al, 9
    je      .flbi_wsaf_adv
    jmp     .flbi_op_check
.flbi_wsaf_adv:
    inc     r13
    jmp     .flbi_ws_after_first

.flbi_op_check:
    mov     al, [r13]
    cmp     al, '+'
    je      .flbi_have_op
    cmp     al, '-'
    je      .flbi_have_op
    jmp     .flbi_store

.flbi_have_op:
    mov     r10b, al
    inc     r13

.flbi_ws_rhs:
    mov     al, [r13]
    cmp     al, ' '
    je      .flbi_ws_rhs_adv
    cmp     al, 9
    je      .flbi_ws_rhs_adv
    jmp     .flbi_rhs_sign
.flbi_ws_rhs_adv:
    inc     r13
    jmp     .flbi_ws_rhs

.flbi_rhs_sign:
    mov     r11, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .flbi_rhs_digit_check
    mov     r11, 1
    inc     r13
    mov     al, [r13]
.flbi_rhs_digit_check:
    cmp     al, '0'
    jb      .flbi_store
    cmp     al, '9'
    ja      .flbi_store
    xor     r15, r15
.flbi_rhs_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .flbi_rhs_done
    cmp     al, '9'
    ja      .flbi_rhs_done
    imul    r15, r15, 10
    movzx   rax, al
    sub     rax, '0'
    add     r15, rax
    inc     r13
    jmp     .flbi_rhs_digits
.flbi_rhs_done:
    cmp     r11, 0
    je      .flbi_rhs_apply
    neg     r15
.flbi_rhs_apply:
    cmp     r10b, '+'
    je      .flbi_rhs_add
    sub     r14, r15
    jmp     .flbi_store
.flbi_rhs_add:
    add     r14, r15

.flbi_store:
    mov     [var_value], r14
    mov     qword [var_defined], 1
    mov     rax, 1
    jmp     .flbi_exit

.flbi_prev:
    dec     r11
    jmp     .flbi_scan_back

.flbi_fail:
    xor     rax, rax

.flbi_exit:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ident_len_at
; Input:  rdi = pointer to identifier start
; Output: rax = identifier length, or 0 if invalid start
; =============================================================================
ident_len_at:
    push    rcx
    xor     rax, rax
    mov     cl, [rdi]
    cmp     cl, '_'
    je      .ila_ok_start
    cmp     cl, 'A'
    jb      .ila_fail
    cmp     cl, 'Z'
    jbe     .ila_ok_start
    cmp     cl, 'a'
    jb      .ila_fail
    cmp     cl, 'z'
    ja      .ila_fail
.ila_ok_start:
    mov     rax, 1
.ila_loop:
    mov     cl, [rdi + rax]
    cmp     cl, '_'
    je      .ila_inc
    cmp     cl, '0'
    jb      .ila_done
    cmp     cl, '9'
    jbe     .ila_inc
    cmp     cl, 'A'
    jb      .ila_done
    cmp     cl, 'Z'
    jbe     .ila_inc
    cmp     cl, 'a'
    jb      .ila_done
    cmp     cl, 'z'
    ja      .ila_done
.ila_inc:
    inc     rax
    cmp     rax, 63
    jbe     .ila_loop
.ila_done:
    pop     rcx
    ret
.ila_fail:
    xor     rax, rax
    pop     rcx
    ret

; =============================================================================
; find_let_binding_by_ident
; Input:
;   rdi = source ptr
;   rcx = source len
;   rsi = ident ptr
;   rdx = ident len
; Output:
;   rax = 1 if found, 0 otherwise
; Side effect:
;   var_value set to matched binding value
; =============================================================================
find_let_binding_by_ident:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    r8
    push    r9
    push    r10
    push    r11

    mov     rbx, rdi        ; source base
    mov     r12, rcx        ; source len
    mov     r8, rsi         ; ident ptr
    mov     r9, rdx         ; ident len
    test    r9, r9
    jz      .flb_fail
    cmp     r12, 4
    jb      .flb_fail

    mov     r11, r12
    sub     r11, 3

.flb_scan_back:
    cmp     r11, 0
    jl      .flb_fail
    lea     r10, [rbx + r11]
    cmp     byte [r10 + 0], 'l'
    jne     .flb_prev
    cmp     byte [r10 + 1], 'e'
    jne     .flb_prev
    cmp     byte [r10 + 2], 't'
    jne     .flb_prev

    lea     r13, [r10 + 3]
    ; require ws after let
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_ws1
    cmp     al, 9
    je      .flb_ws1
    jmp     .flb_prev

.flb_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_ws1_adv
    cmp     al, 9
    je      .flb_ws1_adv
    jmp     .flb_ident
.flb_ws1_adv:
    inc     r13
    jmp     .flb_ws1

.flb_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .flb_prev
    cmp     rax, r9
    jne     .flb_prev
    mov     rdi, r13
    mov     rsi, r8
    mov     rcx, r9
    call    memeq
    test    rax, rax
    jz      .flb_prev
    add     r13, r9

.flb_ws2:
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_ws2_adv
    cmp     al, 9
    je      .flb_ws2_adv
    jmp     .flb_expect_eq
.flb_ws2_adv:
    inc     r13
    jmp     .flb_ws2

.flb_expect_eq:
    cmp     byte [r13], '='
    jne     .flb_prev
    inc     r13

.flb_ws3:
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_ws3_adv
    cmp     al, 9
    je      .flb_ws3_adv
    jmp     .flb_first_sign
.flb_ws3_adv:
    inc     r13
    jmp     .flb_ws3

.flb_first_sign:
    mov     r15, 0          ; sign flag
    mov     al, [r13]
    cmp     al, '-'
    jne     .flb_first_token
    mov     r15, 1
    inc     r13
    mov     al, [r13]
.flb_first_token:
    cmp     al, '0'
    jb      .flb_first_ident
    cmp     al, '9'
    jbe     .flb_first_digit

.flb_first_ident:
    ; allow first operand to be an identifier bound by an earlier let
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .flb_prev
    cmp     r15, 0
    jne     .flb_prev          ; disallow unary minus on identifier operand
    mov     r15, rax           ; preserve ident len across call
    mov     rdi, rbx
    mov     rcx, r10
    sub     rcx, rbx           ; only resolve from source before current let
    mov     rsi, r13
    mov     rdx, r15
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .flb_prev
    mov     r14, [var_value]
    add     r13, r15
    jmp     .flb_base_ready

.flb_first_digit:
    cmp     al, '0'
    jb      .flb_prev
    cmp     al, '9'
    ja      .flb_prev
    xor     r14, r14
.flb_first_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .flb_after_first
    cmp     al, '9'
    ja      .flb_after_first
    imul    r14, r14, 10
    movzx   rax, al
    sub     rax, '0'
    add     r14, rax
    inc     r13
    jmp     .flb_first_digits
.flb_after_first:
    cmp     r15, 0
    je      .flb_base_ready
    neg     r14
.flb_base_ready:

.flb_ws_after_first:
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_wsaf_adv
    cmp     al, 9
    je      .flb_wsaf_adv
    jmp     .flb_op_check
.flb_wsaf_adv:
    inc     r13
    jmp     .flb_ws_after_first

.flb_op_check:
    mov     al, [r13]
    cmp     al, '+'
    je      .flb_have_op
    cmp     al, '-'
    je      .flb_have_op
    jmp     .flb_store_ok

.flb_have_op:
    mov     r12b, al
    inc     r13

.flb_ws_rhs:
    mov     al, [r13]
    cmp     al, ' '
    je      .flb_ws_rhs_adv
    cmp     al, 9
    je      .flb_ws_rhs_adv
    jmp     .flb_rhs_sign
.flb_ws_rhs_adv:
    inc     r13
    jmp     .flb_ws_rhs

.flb_rhs_sign:
    mov     r11, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .flb_rhs_token
    mov     r11, 1
    inc     r13
    mov     al, [r13]

.flb_rhs_token:
    cmp     al, '0'
    jb      .flb_rhs_ident
    cmp     al, '9'
    jbe     .flb_rhs_digit

.flb_rhs_ident:
    ; allow rhs operand to be an identifier bound by an earlier let
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .flb_store_ok
    cmp     r11, 0
    jne     .flb_store_ok      ; disallow unary minus on identifier operand
    push    rax                ; preserve ident len across lookup call
    mov     rdi, rbx
    mov     rcx, r10
    sub     rcx, rbx           ; only resolve from source before current let
    mov     rsi, r13
    mov     rdx, rax
    call    find_let_binding_by_ident
    pop     rcx
    test    rax, rax
    jz      .flb_store_ok
    mov     r15, [var_value]
    add     r13, rcx
    jmp     .flb_rhs_apply

.flb_rhs_digit:
    cmp     al, '0'
    jb      .flb_store_ok
    cmp     al, '9'
    ja      .flb_store_ok
    xor     r15, r15
.flb_rhs_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .flb_rhs_done
    cmp     al, '9'
    ja      .flb_rhs_done
    imul    r15, r15, 10
    movzx   rax, al
    sub     rax, '0'
    add     r15, rax
    inc     r13
    jmp     .flb_rhs_digits
.flb_rhs_done:
    cmp     r11, 0
    je      .flb_rhs_apply
    neg     r15
.flb_rhs_apply:
    cmp     r12b, '+'
    je      .flb_rhs_add
    sub     r14, r15
    jmp     .flb_store_ok
.flb_rhs_add:
    add     r14, r15

.flb_store_ok:
    mov     [var_value], r14
    mov     qword [var_defined], 1
    mov     rax, 1
    jmp     .flb_done

.flb_prev:
    dec     r11
    jmp     .flb_scan_back

.flb_fail:
    xor     rax, rax

.flb_done:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; match_bound_ident
; Input:  rdi = identifier start in source
; Output: rax = 1 if identifier exactly matches stored var_name, else 0
; =============================================================================
match_bound_ident:
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    cmp     qword [var_defined], 1
    jne     .mbi_fail

    lea     rsi, [var_name_buf]
    mov     rcx, [var_name_len]
    test    rcx, rcx
    jz      .mbi_fail

.mbi_cmp_loop:
    test    rcx, rcx
    jz      .mbi_boundary
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .mbi_fail
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .mbi_cmp_loop

.mbi_boundary:
    ; next char must not be identifier char
    mov     al, [rdi]
    cmp     al, '_'
    je      .mbi_fail
    cmp     al, '0'
    jb      .mbi_ok
    cmp     al, '9'
    jbe     .mbi_fail
    cmp     al, 'A'
    jb      .mbi_ok
    cmp     al, 'Z'
    jbe     .mbi_fail
    cmp     al, 'a'
    jb      .mbi_ok
    cmp     al, 'z'
    jbe     .mbi_fail

.mbi_ok:
    mov     rax, 1
    jmp     .mbi_exit

.mbi_fail:
    xor     rax, rax

.mbi_exit:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; i64_to_str_buf
; Input:  rax = signed value
; Output: str_buf filled with decimal digits, [str_len] set
; =============================================================================
i64_to_str_buf:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8

    mov     rbx, 0              ; negative flag
    cmp     rax, 0
    jge     .i64_abs_ready
    mov     rbx, 1
    neg     rax
.i64_abs_ready:

    cmp     rax, 0
    jne     .i64_nonzero
    cmp     rbx, 0
    jne     .i64_neg_zero
    mov     byte [str_buf], '0'
    mov     qword [str_len], 1
    jmp     .i64_done

.i64_neg_zero:
    mov     byte [str_buf], '-'
    mov     byte [str_buf + 1], '0'
    mov     qword [str_len], 2
    jmp     .i64_done

.i64_nonzero:
    lea     rdi, [str_buf + 4095]
    xor     rcx, rcx
    mov     r8, 10
.i64_div_loop:
    xor     rdx, rdx
    div     r8
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    inc     rcx
    test    rax, rax
    jnz     .i64_div_loop

    cmp     rbx, 0
    je      .i64_copy
    dec     rdi
    mov     byte [rdi], '-'
    inc     rcx

    ; copy to start of str_buf
.i64_copy:
    lea     rsi, [rdi]
    lea     rdi, [str_buf]
    mov     [str_len], rcx
    rep movsb

.i64_done:
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; find_print_ident_expr
; Input:  rdi = source ptr, rcx = source len
; Output: rax = 1 on success (str_buf/str_len set), 0 on failure
; Supports: print(<bound_ident> +/- <int>)
; =============================================================================
find_print_ident_expr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    cmp     qword [var_defined], 1
    jne     .fpiei_fail

    mov     rbx, rdi
    mov     r12, rcx
    lea     rsi, [pat_print_open]
    mov     rdx, pat_print_open_len
    call    find_substr
    test    rax, rax
    jz      .fpiei_fail

    lea     r13, [rax + pat_print_open_len]
.fpiei_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpiei_ws1_adv
    cmp     al, 9
    je      .fpiei_ws1_adv
    jmp     .fpiei_ident
.fpiei_ws1_adv:
    inc     r13
    jmp     .fpiei_ws1

.fpiei_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .fpiei_fail
    mov     r8, rax             ; ident len
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    mov     rsi, r13
    mov     rdx, r8
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .fpiei_fail
    mov     r14, [var_value]
    add     r13, r8

.fpiei_ws2:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpiei_ws2_adv
    cmp     al, 9
    je      .fpiei_ws2_adv
    jmp     .fpiei_op
.fpiei_ws2_adv:
    inc     r13
    jmp     .fpiei_ws2

.fpiei_op:
    mov     al, [r13]
    cmp     al, '+'
    je      .fpiei_have_op
    cmp     al, '-'
    je      .fpiei_have_op
    jmp     .fpiei_fail

.fpiei_have_op:
    mov     bl, al
    inc     r13

.fpiei_ws3:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpiei_ws3_adv
    cmp     al, 9
    je      .fpiei_ws3_adv
    jmp     .fpiei_rhs_sign
.fpiei_ws3_adv:
    inc     r13
    jmp     .fpiei_ws3

.fpiei_rhs_sign:
    mov     rcx, 0
    mov     al, [r13]
    cmp     al, '-'
    jne     .fpiei_rhs_token
    mov     rcx, 1
    inc     r13
    mov     al, [r13]

.fpiei_rhs_token:
    cmp     al, '0'
    jb      .fpiei_rhs_ident
    cmp     al, '9'
    jbe     .fpiei_rhs_digit_check

.fpiei_rhs_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .fpiei_fail
    cmp     rcx, 0
    jne     .fpiei_fail          ; disallow unary minus on identifier operand
    mov     r8, rax
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    mov     rsi, r13
    mov     rdx, r8
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .fpiei_fail
    mov     r15, [var_value]
    add     r13, r8
    jmp     .fpiei_rhs_apply

.fpiei_rhs_digit_check:
    cmp     al, '0'
    jb      .fpiei_fail
    cmp     al, '9'
    ja      .fpiei_fail
    xor     r15, r15
.fpiei_rhs_digits:
    mov     al, [r13]
    cmp     al, '0'
    jb      .fpiei_rhs_done
    cmp     al, '9'
    ja      .fpiei_rhs_done
    imul    r15, r15, 10
    movzx   rax, al
    sub     rax, '0'
    add     r15, rax
    inc     r13
    jmp     .fpiei_rhs_digits
.fpiei_rhs_done:
    cmp     rcx, 0
    je      .fpiei_rhs_apply
    neg     r15
.fpiei_rhs_apply:
    cmp     bl, '+'
    je      .fpiei_add
    sub     r14, r15
    jmp     .fpiei_expect_close
.fpiei_add:
    add     r14, r15

.fpiei_expect_close:
.fpiei_ws4:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpiei_ws4_adv
    cmp     al, 9
    je      .fpiei_ws4_adv
    jmp     .fpiei_check_close
.fpiei_ws4_adv:
    inc     r13
    jmp     .fpiei_ws4
.fpiei_check_close:
    cmp     byte [r13], ')'
    jne     .fpiei_fail

    mov     rax, r14
    call    i64_to_str_buf
    mov     rax, 1
    jmp     .fpiei_done

.fpiei_fail:
    xor     rax, rax

.fpiei_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; find_print_ident_binding
; Input:  rdi = source ptr, rcx = source len
; Output: rax = 1 if print(<bound_ident>) parsed and rendered into str_buf
; =============================================================================
find_print_ident_binding:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi
    mov     r12, rcx
    lea     rsi, [pat_print_open]
    mov     rdx, pat_print_open_len
    call    find_substr
    test    rax, rax
    jz      .fpib_fail

    lea     r13, [rax + pat_print_open_len]
.fpib_ws1:
    mov     al, [r13]
    cmp     al, ' '
    je      .fpib_ws1_adv
    cmp     al, 9
    je      .fpib_ws1_adv
    jmp     .fpib_ident
.fpib_ws1_adv:
    inc     r13
    jmp     .fpib_ws1

.fpib_ident:
    mov     rdi, r13
    call    ident_len_at
    test    rax, rax
    jz      .fpib_fail
    mov     r8, rax
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    mov     rsi, r13
    mov     rdx, r8
    call    find_let_binding_by_ident
    test    rax, rax
    jz      .fpib_fail

    ; render bound value to str_buf
    mov     rax, [var_value]
    call    i64_to_str_buf
    mov     rax, 1
    jmp     .fpib_done

.fpib_fail:
    xor     rax, rax

.fpib_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; emit_stage1_shim
; Copies /proc/self/exe to argv[2], producing a runnable Stage1 shim compiler.
; Returns rax=0 on success, rax=1 on error.
; =============================================================================
emit_stage1_shim:
    push    rbx
    push    r13
    push    r14

    mov     r13, -1         ; self fd
    mov     r14, -1         ; out fd

    ; Open output path (argv[2] in r12)
    mov     rax, SYS_OPEN
    mov     rdi, r12
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0755o
    syscall
    test    rax, rax
    js      .es_fail
    mov     r14, rax

    ; Open /proc/self/exe
    mov     rax, SYS_OPEN
    lea     rdi, [path_self_exe]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .es_fail
    mov     r13, rax

.es_read_loop:
    mov     rax, SYS_READ
    mov     rdi, r13
    lea     rsi, [source_buf]
    mov     rdx, 8192
    syscall
    test    rax, rax
    js      .es_fail
    jz      .es_ok

    mov     rbx, rax        ; bytes remaining to write
    lea     rsi, [source_buf]

.es_write_loop:
    mov     rax, SYS_WRITE
    mov     rdi, r14
    mov     rdx, rbx
    syscall
    test    rax, rax
    jle     .es_fail
    sub     rbx, rax
    add     rsi, rax
    test    rbx, rbx
    jnz     .es_write_loop
    jmp     .es_read_loop

.es_ok:
    xor     rax, rax
    jmp     .es_cleanup

.es_fail:
    mov     rax, 1

.es_cleanup:
    cmp     r13, -1
    je      .es_skip_self_close
    mov     rbx, rax
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    mov     rax, rbx
.es_skip_self_close:
    cmp     r14, -1
    je      .es_done
    mov     rbx, rax
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
    mov     rax, rbx
.es_done:
    pop     r14
    pop     r13
    pop     rbx
    ret

; =============================================================================
; memeq: compare rcx bytes at rdi and rsi
; Returns rax=1 if equal, rax=0 if not
; =============================================================================
memeq:
    push    rdi
    push    rsi
    push    rcx
.loop:
    test    rcx, rcx
    jz      .equal
    mov     al, byte [rdi]
    cmp     al, byte [rsi]
    jne     .neq
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .loop
.equal:
    mov     rax, 1
    pop     rcx
    pop     rsi
    pop     rdi
    ret
.neq:
    xor     rax, rax
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; =============================================================================
; build_elf
; Generates a minimal ELF64 executable in output_buf that:
;   1. Writes str_buf (str_len bytes) to stdout via SYS_WRITE
;   2. Exits 0 via SYS_EXIT
;
; ELF Layout (all packed into one LOAD segment):
;   Offset 0x000: ELF Header       (64 bytes)
;   Offset 0x040: Program Header   (56 bytes)
;   Offset 0x078: Machine Code     (variable)
;
; Load address: 0x400000 (standard Linux x86-64)
; =============================================================================
section .bss
    output_size     resq 1

section .text

build_elf:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    lea     r15, [output_buf]       ; r15 = output buffer pointer
    xor     r14, r14                ; r14 = current write offset

    ; -------------------------
    ; We will generate the machine code FIRST to know its length,
    ; then fill in the ELF/program headers.
    ; Code starts at offset 0x78 (0x40 hdr + 0x38 phdr)
    ; -------------------------

    mov     r8, 0x78                ; code offset in file
    mov     r9, 0x400000            ; load virtual address
    mov     r10, r9                 ; r10 = load vaddr

    ; Code virtual address = load_vaddr + code_offset
    mov     r11, r9
    add     r11, r8                 ; r11 = code entry vaddr = 0x400078

    ; --- Generate machine code at output_buf + 0x78 ---
    lea     rdi, [output_buf + 0x78]
    mov     r14, 0                  ; code byte counter

    ; The generated program needs to:
    ; 1) write(1, <string_addr>, <str_len>)
    ; 2) exit(0)
    ;
    ; The string will be embedded right after the code.
    ; We don't know the string address yet at code-gen time,
    ; so we use RIP-relative addressing.
    ;
    ; Code sequence:
    ;   mov rax, 1          ; SYS_WRITE
    ;   mov rdi, 1          ; fd = stdout
    ;   lea rsi, [rip+X]    ; pointer to string (after code)
    ;   mov rdx, <str_len>  ; string length
    ;   syscall
    ;   mov rax, 60         ; SYS_EXIT
    ;   xor rdi, rdi        ; exit code 0
    ;   syscall
    ;
    ; Then the string bytes follow.

    ; mov rax, 1  =>  48 C7 C0 01 00 00 00
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC0
    inc     r14
    mov     byte [rdi + r14], 0x01
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14

    ; mov rdi, 1  =>  48 C7 C7 01 00 00 00
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0x01
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14

    ; lea rsi, [rip + offset_to_string]
    ; Opcode: 48 8D 35 <rel32>
    ; After this instruction, RIP = code_base + r14 + 7 (4 bytes for rel32 + 3 bytes opcode)
    ; String is at code_base + <code_length_after_syscalls>
    ;
    ; We'll patch the rel32 after we know code length.
    ; For now, remember the offset of rel32 in the code.
    mov     r13, r14                ; save position of lea instruction start
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0x8D
    inc     r14
    mov     byte [rdi + r14], 0x35
    inc     r14
    ; rel32 placeholder (4 bytes)
    mov     dword [rdi + r14], 0
    add     r14, 4

    ; After 'lea rsi, [rip+X]', RIP advances past the instruction.
    ; Instruction length = 7 bytes (48 8D 35 + 4 byte rel32)
    ; So after the instruction executes, rip = code_start + (r13 + 7)

    ; mov rdx, str_len  =>  48 C7 C2 <len32>
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC2
    inc     r14
    mov     eax, dword [str_len]
    mov     dword [rdi + r14], eax
    add     r14, 4

    ; syscall  =>  0F 05
    mov     byte [rdi + r14], 0x0F
    inc     r14
    mov     byte [rdi + r14], 0x05
    inc     r14

    ; mov rax, 60  =>  48 C7 C0 3C 00 00 00
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC0
    inc     r14
    mov     byte [rdi + r14], 0x3C
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14

    ; mov rdi, <exit_code>  => 48 C7 C7 <imm32>
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     eax, dword [exit_code]
    mov     dword [rdi + r14], eax
    add     r14, 4

    ; syscall  =>  0F 05
    mov     byte [rdi + r14], 0x0F
    inc     r14
    mov     byte [rdi + r14], 0x05
    inc     r14

    ; r14 = total code bytes (excluding string)
    ; Now patch the RIP-relative offset in the lea instruction.
    ; lea rsi, [rip + rel32]
    ; The instruction is at offset r13 in the code block.
    ; After the instruction, rip = r13 + 7
    ; String starts at offset r14 in the code block.
    ; rel32 = r14 - (r13 + 7)
    mov     rax, r14
    mov     rcx, r13
    add     rcx, 7              ; rip after lea
    sub     rax, rcx            ; rel32 = string_offset - rip_after_lea
    mov     dword [rdi + r13 + 3], eax  ; patch the rel32 field

    ; Now copy the string bytes after the code
    lea     rsi, [str_buf]
    mov     rcx, [str_len]
    mov     rbx, rcx            ; save str_len
    ; rdi still points to code base in output_buf
.copy_string:
    test    rcx, rcx
    jz      .copy_done2
    mov     al, byte [rsi]
    mov     byte [rdi + r14], al
    inc     rsi
    inc     r14
    dec     rcx
    jmp     .copy_string
.copy_done2:

    ; Append newline
    mov     byte [rdi + r14], 0x0A
    inc     r14
    inc     rbx                 ; str_len + 1 for newline

    ; Now patch mov rdx, str_len with actual str_len+1
    ; The mov rdx instruction is at offset r13+7+7 = r13+14... wait let me recalculate.
    ; Instructions emitted before mov rdx:
    ;   mov rax,1 = 7 bytes
    ;   mov rdi,1 = 7 bytes
    ;   lea rsi   = 7 bytes (r13 to r13+7)
    ; So mov rdx starts at r13+7 = offset 21
    ; Actually r13 = offset of lea, so mov rdx starts at r13+7
    ; The immediate in mov rdx is at offset r13+7+3 = r13+10
    mov     rax, r13
    add     rax, 7 + 3          ; skip lea (7) + mov rdx opcode (3)
    mov     dword [rdi + rax], ebx  ; patch str_len+1

    ; Total file size = 0x78 + r14
    add     r14, 0x78           ; r14 = total output size
    mov     [output_size], r14

    ; -------------------------
    ; Build ELF Header at output_buf + 0
    ; -------------------------
    lea     rbx, [output_buf]

    ; e_ident (16 bytes)
    mov     dword [rbx + 0],  0x464C457F  ; Magic: \x7fELF
    mov     byte  [rbx + 4],  2           ; EI_CLASS: ELFCLASS64
    mov     byte  [rbx + 5],  1           ; EI_DATA: ELFDATA2LSB
    mov     byte  [rbx + 6],  1           ; EI_VERSION: EV_CURRENT
    mov     byte  [rbx + 7],  0           ; EI_OSABI: ELFOSABI_NONE
    mov     qword [rbx + 8],  0           ; EI_ABIVERSION + padding

    ; e_type (2 bytes at offset 16): ET_EXEC = 2
    mov     word  [rbx + 16], 2
    ; e_machine (2 bytes at offset 18): EM_X86_64 = 62
    mov     word  [rbx + 18], 62
    ; e_version (4 bytes at offset 20): EV_CURRENT = 1
    mov     dword [rbx + 20], 1
    ; e_entry (8 bytes at offset 24): virtual address of entry = 0x400078
    mov     qword [rbx + 24], r11
    ; e_phoff (8 bytes at offset 32): program header offset = 64 (right after ELF header)
    mov     qword [rbx + 32], 64
    ; e_shoff (8 bytes at offset 40): no section headers
    mov     qword [rbx + 40], 0
    ; e_flags (4 bytes at offset 48): 0
    mov     dword [rbx + 48], 0
    ; e_ehsize (2 bytes at offset 52): 64
    mov     word  [rbx + 52], 64
    ; e_phentsize (2 bytes at offset 54): 56
    mov     word  [rbx + 54], 56
    ; e_phnum (2 bytes at offset 56): 1
    mov     word  [rbx + 56], 1
    ; e_shentsize (2 bytes at offset 58): 64
    mov     word  [rbx + 58], 64
    ; e_shnum (2 bytes at offset 60): 0
    mov     word  [rbx + 60], 0
    ; e_shstrndx (2 bytes at offset 62): 0
    mov     word  [rbx + 62], 0

    ; -------------------------
    ; Build Program Header at output_buf + 64
    ; -------------------------
    lea     rbx, [output_buf + 64]

    ; p_type (4 bytes at offset 0): PT_LOAD = 1
    mov     dword [rbx + 0],  1
    ; p_flags (4 bytes at offset 4): PF_R|PF_X = 5
    mov     dword [rbx + 4],  5
    ; p_offset (8 bytes at offset 8): 0 (load from start of file)
    mov     qword [rbx + 8],  0
    ; p_vaddr (8 bytes at offset 16): 0x400000
    mov     qword [rbx + 16], r10
    ; p_paddr (8 bytes at offset 24): 0x400000
    mov     qword [rbx + 24], r10
    ; p_filesz (8 bytes at offset 32): total output size
    mov     rax, [output_size]
    mov     qword [rbx + 32], rax
    ; p_memsz (8 bytes at offset 40): same
    mov     qword [rbx + 40], rax
    ; p_align (8 bytes at offset 48): 0x200000
    mov     qword [rbx + 48], 0x200000

    leave
    ret

; =============================================================================
; build_elf_exit_only
; Emits ELF64 that performs exit(<exit_code>) with no stdout write.
; =============================================================================
build_elf_exit_only:
    push    rbp
    mov     rbp, rsp

    ; Code starts at file offset 0x78, vaddr 0x400078
    lea     rdi, [output_buf + 0x78]
    xor     r14, r14

    ; mov rax, 60
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC0
    inc     r14
    mov     byte [rdi + r14], 0x3C
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14
    mov     byte [rdi + r14], 0x00
    inc     r14

    ; mov rdi, <exit_code>
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     byte [rdi + r14], 0xC7
    inc     r14
    mov     eax, dword [exit_code]
    mov     dword [rdi + r14], eax
    add     r14, 4

    ; syscall
    mov     byte [rdi + r14], 0x0F
    inc     r14
    mov     byte [rdi + r14], 0x05
    inc     r14

    ; Total size
    mov     rax, r14
    add     rax, 0x78
    mov     [output_size], rax

    ; ELF header
    lea     rbx, [output_buf]
    mov     dword [rbx + 0],  0x464C457F
    mov     byte  [rbx + 4],  2
    mov     byte  [rbx + 5],  1
    mov     byte  [rbx + 6],  1
    mov     byte  [rbx + 7],  0
    mov     qword [rbx + 8],  0
    mov     word  [rbx + 16], 2
    mov     word  [rbx + 18], 62
    mov     dword [rbx + 20], 1
    mov     qword [rbx + 24], 0x400078
    mov     qword [rbx + 32], 64
    mov     qword [rbx + 40], 0
    mov     dword [rbx + 48], 0
    mov     word  [rbx + 52], 64
    mov     word  [rbx + 54], 56
    mov     word  [rbx + 56], 1
    mov     word  [rbx + 58], 64
    mov     word  [rbx + 60], 0
    mov     word  [rbx + 62], 0

    ; Program header
    lea     rbx, [output_buf + 64]
    mov     dword [rbx + 0],  1
    mov     dword [rbx + 4],  5
    mov     qword [rbx + 8],  0
    mov     qword [rbx + 16], 0x400000
    mov     qword [rbx + 24], 0x400000
    mov     rax, [output_size]
    mov     qword [rbx + 32], rax
    mov     qword [rbx + 40], rax
    mov     qword [rbx + 48], 0x200000

    leave
    ret

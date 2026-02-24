; =============================================================================
; Jda Stage 0 Compiler - x86-64 NASM Assembly
; =============================================================================
; Bootstrapper: Zero C, Zero libc. Direct Linux syscalls only.
;
; Supported minimal Jda syntax:
;   fn main() {
;       print("any string here")
;   }
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

    ; Pattern we search for: print("
    pat_print       db `print("`, 0
    pat_print_len   equ 7

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

    ; --- Parse: find print(" pattern ---
    lea     rdi, [source_buf]
    mov     rcx, [source_len]
    call    find_print_string
    test    rax, rax
    jz      .err_parse

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

    ; --- Build ELF64 binary in output_buf ---
    call    build_elf

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

    ; xor rdi, rdi  =>  48 31 FF
    mov     byte [rdi + r14], 0x48
    inc     r14
    mov     byte [rdi + r14], 0x31
    inc     r14
    mov     byte [rdi + r14], 0xFF
    inc     r14

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

#!/usr/bin/env python3
"""
Generate jda0 NASM constant definitions from jda0_spec.py

This script reads the auto-generated specification and outputs NASM-formatted
constant definitions that can be included in jda0.asm.

USAGE:
    python3 tools/generate_jda0_constants.py

INPUTS:
    - tools/jda0_spec.py: Auto-generated specification from jda1.jda

OUTPUT:
    - bootstrap/stage0/jda0_constants.asm: NASM constant definitions

GENERATED CONTENT:
    - Token type constants (TOK_FN, TOK_LET, etc.)
    - Type constants (TYPE_VOID, TYPE_I64, etc.)
    - Opcode constants (OP_CONST, OP_ADD, etc.)
    - Structure size equations (TOK_SZ, CST_SZ, etc.)
    - AST node type constants (NODE_*)
    - Platform-specific constants (SYS_*, ET_*, etc.)
    - Compatibility constants (for jda0-specific tokens)

REGENERATION:
    Run this script anytime jda1.jda changes constants or structures.
    The Makefile automates this: make generate-constants

VALIDATION:
    After generation, run: python3 tools/validate_jda0_constants.py
    This checks constant consistency and reports differences from current jda0.asm
"""

import sys
import os

def load_spec():
    """Load jda0_spec.py from tools directory"""
    spec_path = os.path.join(os.path.dirname(__file__), 'jda0_spec.py')

    spec = {}
    with open(spec_path, 'r') as f:
        content = f.read()
        # Execute the spec file to load the dictionaries
        exec(content, spec)

    return spec

def generate_token_constants(spec):
    """Generate NASM token type constant definitions"""
    output = "; Token type constants\n"
    tokens = spec['TOKENS']

    for name in sorted(tokens.keys(), key=lambda x: tokens[x]):
        value = tokens[name]
        output += f"{name:20} equ {value}\n"

    return output

def generate_type_constants(spec):
    """Generate NASM type constant definitions"""
    output = "\n; Type constants\n"
    types = spec['TYPES']

    for name in sorted(types.keys(), key=lambda x: types[x]):
        value = types[name]
        output += f"{name:20} equ {value}\n"

    return output

def generate_opcode_constants(spec):
    """Generate NASM opcode constant definitions"""
    output = "\n; Opcode constants\n"
    opcodes = spec['OPCODES']

    for name in sorted(opcodes.keys(), key=lambda x: opcodes[x]):
        value = opcodes[name]
        output += f"{name:20} equ {value}\n"

    return output

def generate_struct_sizes(spec):
    """Generate NASM structure size equations"""
    output = "\n; Structure sizes\n"
    structures = spec['STRUCTURES']

    # Mapping of structure names to their NASM constant names
    # These are hardcoded to match the original jda0.asm
    size_mapping = {
        'Token': 'TOK_SZ',
        'ConstVal': 'CST_SZ',
        'VarEntry': 'PRM_SZ',
        'Instr': 'FLD_SZ',
        'JirFunction': 'FN_SZ',
        'BasicBlock': 'BB_SZ',
        'Node': 'NODE_SZ',
        'Fixup': 'FIXUP_SZ',
        'LowerCtx': 'LOWER_SZ',
        'RegAlloc': 'REGALLOC_SZ',
        'StructTable': 'STRUCTTABLE_SZ',
    }

    for struct_name in sorted(structures.keys()):
        struct = structures[struct_name]
        size = struct['size']

        if struct_name in size_mapping:
            const_name = size_mapping[struct_name]
            output += f"{const_name:20} equ {size}\n"

    return output

def generate_node_type_constants(spec):
    """Generate NODE_* type constants from ALL_CONSTANTS"""
    output = "\n; AST Node type constants\n"
    constants = spec['ALL_CONSTANTS']

    node_consts = {k: v for k, v in constants.items() if k.startswith('NODE_')}

    for name in sorted(node_consts.keys(), key=lambda x: node_consts[x]):
        value = node_consts[name]
        output += f"{name:20} equ {value}\n"

    return output

def generate_system_constants():
    """Generate platform-specific system constants for x86-64 Linux"""
    output = "\n; ============================================================\n"
    output += "; SYSTEM CONSTANTS - Platform specific (x86-64 Linux)\n"
    output += "; ============================================================\n\n"

    # Linux x86-64 system call numbers
    output += "; System call numbers\n"
    syscall_numbers = {
        'SYS_READ': 0,
        'SYS_WRITE': 1,
        'SYS_OPEN': 2,
        'SYS_CLOSE': 3,
        'SYS_MMAP': 9,
        'SYS_EXIT': 60,
    }
    for name, value in syscall_numbers.items():
        output += f"{name:20} equ {value}\n"

    # ELF file format constants
    output += "\n; ELF file format constants\n"
    elf_constants = {
        'ET_EXEC': 2,
        'ET_DYN': 3,
        'EM_X86_64': 62,
        'PT_LOAD': 1,
        'PF_RWX': 7,
    }
    for name, value in elf_constants.items():
        output += f"{name:20} equ {value}\n"

    # Memory mapping constants
    output += "\n; Memory protection constants\n"
    prot_constants = {
        'PROT_RW': 3,
        'MAP_PA': 34,
    }
    for name, value in prot_constants.items():
        output += f"{name:20} equ {value}\n"

    # Buffer sizes
    output += "\n; String table size\n"
    output += f"{'STR_SZ':20} equ 3104\n"

    return output

def generate_compatibility_constants():
    """Generate compatibility constants used by jda0 but not in jda1 spec

    These are tokens and constants that jda0 needs for backward compatibility
    or for features that jda1 hasn't formalized yet.
    """
    output = "\n; ============================================================\n"
    output += "; COMPATIBILITY CONSTANTS - Used by jda0, not in jda1 spec\n"
    output += "; ============================================================\n\n"

    # Token types that jda0 uses but jda1 doesn't explicitly define
    output += "; Additional token types\n"
    compat_tokens = {
        'TOK_CHAR': 45,
        'TOK_LTEQ': 46,
        'TOK_GTEQ': 47,
        'TOK_PIPE': 48,
        'TOK_SHL': 49,
        'TOK_SHR': 50,
        'TOK_ALLOC_PAGES': 51,
        'TOK_ASM': 41,
        'TOK_BREAK': 42,
    }
    for name, value in sorted(compat_tokens.items(), key=lambda x: x[1]):
        output += f"{name:20} equ {value}\n"

    # Type kind constants
    output += "\n; Type kind constants\n"
    type_kinds = {
        'TK_SCALAR': 0,
        'TK_STRUCT': 1,
        'TK_PTR': 2,
    }
    for name, value in type_kinds.items():
        output += f"{name:20} equ {value}\n"

    # Size constants not in spec
    output += "\n; Additional size constants\n"
    output += f"{'LOC_SZ':20} equ 48\n"
    output += f"{'GLB_SZ':20} equ 32\n"

    # Pointer flag
    output += "\n; Pointer type flag\n"
    output += f"{'PTR_FLAG':20} equ 0x8000000000000000\n"

    return output

def generate_header():
    """Generate file header"""
    return """; ============================================================
; AUTO-GENERATED CONSTANTS FROM jda1.jda
; DO NOT EDIT - Run: python3 tools/generate_jda0_constants.py
; ============================================================

"""

def write_asm_file(output_path, content):
    """Write generated content to NASM file"""
    with open(output_path, 'w') as f:
        f.write(content)
    print(f"✅ Generated {output_path}")
    print(f"   Size: {len(content)} bytes")

def main():
    # Load specification
    print("📖 Loading jda0_spec.py...")
    spec = load_spec()

    print(f"   Loaded {len(spec['TOKENS'])} tokens")
    print(f"   Loaded {len(spec['TYPES'])} types")
    print(f"   Loaded {len(spec['OPCODES'])} opcodes")
    print(f"   Loaded {len(spec['STRUCTURES'])} structures")

    # Generate all sections
    output = generate_header()
    output += generate_token_constants(spec)
    output += generate_type_constants(spec)
    output += generate_opcode_constants(spec)
    output += generate_struct_sizes(spec)
    output += generate_node_type_constants(spec)
    output += generate_system_constants()
    output += generate_compatibility_constants()

    # Write to output file
    output_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0_constants.asm'
    )

    write_asm_file(output_path, output)

    print("\n✅ Constant generation complete!")
    print(f"   Run: nasm -f elf64 -o jda0_constants.o {output_path}")

if __name__ == '__main__':
    main()

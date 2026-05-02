#!/usr/bin/env python3
"""
Generate jda0 NASM struct field offset definitions from jda0_spec.py

This script reads the auto-generated specification and outputs NASM-formatted
field offset equations for each struct, which can be included in jda0.asm.

Output: bootstrap/stage0/jda0_structs.asm
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

def generate_struct_offsets(spec):
    """Generate NASM field offset equations for all structures"""
    structures = spec['STRUCTURES']
    output = ""

    # Define a canonical ordering and naming for structs
    struct_name_map = {
        'Token': 'TOK',
        'ConstVal': 'CST',
        'VarEntry': 'VAR',
        'Instr': 'INSTR',
        'BasicBlock': 'BB',
        'JirFunction': 'FN',
        'Node': 'NODE',
        'Fixup': 'FIXUP',
        'LowerCtx': 'LOWER',
        'RegAlloc': 'REGALLOC',
        'StructTable': 'STRUCTTABLE',
    }

    for struct_name in sorted(structures.keys()):
        if struct_name not in struct_name_map:
            continue

        struct = structures[struct_name]
        const_prefix = struct_name_map[struct_name]

        # Add comment with struct description
        output += f"; {struct_name} struct (size: {struct['size']} bytes)\n"

        # Generate field offset equations
        fields = struct['fields']
        for field_name in sorted(fields.keys(), key=lambda x: fields[x]['offset']):
            field = fields[field_name]
            offset = field['offset']

            # Convert field name to constant name (uppercase with underscores)
            const_name = f"{const_prefix}_{field_name.upper()}"
            output += f"{const_name:25} equ {offset}\n"

        # Add size equation
        size_const = f"{const_prefix}_SZ"
        output += f"{size_const:25} equ {struct['size']}\n"
        output += "\n"

    return output

def generate_header():
    """Generate file header"""
    return """; ============================================================
; AUTO-GENERATED STRUCT FIELD OFFSETS FROM jda1.jda
; DO NOT EDIT - Run: python3 tools/generate_jda0_structs.py
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

    print(f"   Loaded {len(spec['STRUCTURES'])} structures")

    # Generate struct offsets
    print("\n🔨 Generating field offset equations...")
    output = generate_header()
    output += generate_struct_offsets(spec)

    # Write to output file
    output_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0_structs.asm'
    )

    write_asm_file(output_path, output)

    print("\n✅ Struct offset generation complete!")
    print(f"   Run: nasm -f elf64 -o jda0_structs.o {output_path}")

if __name__ == '__main__':
    main()

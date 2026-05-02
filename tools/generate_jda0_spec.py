#!/usr/bin/env python3
"""
Extract jda1.jda constants and structure definitions to create jda0 generation spec.

This script parses jda1.jda to extract:
- Token type constants (TOK_*)
- Type constants (TYPE_*)
- Opcode constants (OP_*)
- Structure definitions and sizes
- Field offsets

Output: jda0_spec.py - Data-driven specification for generating jda0.asm
"""

import re
import sys

def extract_constants(jda1_path):
    """Extract all const declarations from jda1.jda"""
    constants = {}

    with open(jda1_path, 'r') as f:
        content = f.read()

    # Match: const NAME = VALUE
    pattern = r'^const\s+(\w+)\s*=\s*(\S+)'

    # Names that jda0 uses as globals in .bss
    reserved_names = {
        'src_len', 'tok_cnt', 'tok_pos', 'cst_cnt', 'stt_cnt', 'fn_cnt', 
        'loc_cnt', 'glb_cnt', 'fix_cnt', 'cod_len', 'sdt_len', 'out_fd', 
        'glb_r15', 'lbl_seq', 'brk_lbl', 'jmp_top', 'jmp_stk', 'loc_rbp', 
        'loc_max_rbp', 'lv_sid', 'lv_esz', 'lv_isptr', 'lv_glb', 
        'p1_glb_tkind', 'p1_glb_sid', 'p1_glb_esz', 'ga_from_dot', 'ga_acnt',
        'sfx_tbl_ptr', 'sfix_cnt', 'frm_patch_off', 'prm_cnt_bss', 'prec_stop',
        'arith_stop', 'asm_reglen', 'src_buf', 'tok_buf_ptr', 'cst_tbl_ptr',
        'stt_tbl_ptr', 'fn_tbl_ptr', 'loc_tbl_ptr', 'glb_tbl_ptr', 'cod_buf_ptr',
        'sdt_buf_ptr', 'fix_buf_ptr'
    }

    for line in content.split('\n'):
        # Clean line: remove trailing comments
        clean_line = line.split(';')[0].strip()
        match = re.match(pattern, clean_line)
        if match:
            name = match.group(1)
            value = match.group(2)
            # Only keep the first definition and skip reserved names
            if name not in constants and name not in reserved_names:
                # Handle hex values
                if value.startswith('0x'):
                    constants[name] = int(value, 16)
                else:
                    try:
                        constants[name] = int(value)
                    except:
                        constants[name] = value

    return constants

def extract_structs(jda1_path):
    """Extract struct definitions with field offsets"""
    structs = {}

    with open(jda1_path, 'r') as f:
        lines = f.readlines()

    current_struct = None
    fields = []
    offset = 0

    for i, line in enumerate(lines):
        # Match: struct NAME {
        if re.match(r'^struct\s+(\w+)\s*\{', line):
            current_struct = re.match(r'^struct\s+(\w+)', line).group(1)
            fields = []
            offset = 0
            continue

        # Match: field: type
        if current_struct and re.match(r'^\s+(\w+):\s+(\S+)', line):
            match = re.match(r'^\s+(\w+):\s+(\S+)', line)
            field_name = match.group(1)
            field_type = match.group(2)

            # Estimate size based on type
            size = 8  # Default: 8 bytes for pointers and i64
            
            # Helper to get base type size
            def get_base_size(t):
                if 'i64' in t: return 8
                if 'i32' in t: return 4
                if 'i8' in t: return 1
                if 'Token' in t: return 40
                if 'Node' in t: return 88
                if 'Instr' in t: return 96
                if 'Fixup' in t: return 32
                if 'BasicBlock' in t: return 24600
                if 'VarEntry' in t: return 32
                if 'RegAlloc' in t: return 49256
                if 'LowerCtx' in t: return 102512
                return 8

            if '[' in field_type:
                # Array type: count elements
                array_match = re.search(r'\[(\d+)\]', field_type)
                if array_match:
                    count = int(array_match.group(1))
                    elem_type = field_type.split('[')[0]
                    elem_size = get_base_size(elem_type)
                    size = count * elem_size
            elif 'i32' in field_type:
                size = 4
            elif 'i8' in field_type:
                size = 1
            elif '&' in field_type:
                size = 8
            else:
                # Custom struct type (not array, not pointer)
                size = get_base_size(field_type)

            # 8-byte alignment:
            if offset % 8 != 0:
                offset = (offset + 7) & ~7

            fields.append({
                'name': field_name,
                'type': field_type,
                'offset': offset,
                'size': size
            })
            offset += size

        # End of struct
        if current_struct and re.match(r'^\}', line):
            structs[current_struct] = {
                'fields': fields,
                'size': offset
            }
            current_struct = None

    return structs

def generate_spec_file(constants, structs, output_path):
    """Generate jda0_spec.py with all extracted information"""

    spec_content = '''#!/usr/bin/env python3
"""
Auto-generated jda0 specification from jda1.jda constants and structures.

DO NOT EDIT MANUALLY - regenerate using:
  python3 tools/generate_jda0_spec.py bootstrap/stage1/jda1.jda tools/jda0_spec.py
"""

# Token type constants
TOKENS = {
'''

    # Group tokens
    token_consts = {k: v for k, v in constants.items() if k.startswith('TOK_')}
    for name in sorted(token_consts.keys()):
        spec_content += f"    '{name}': {token_consts[name]},\n"

    spec_content += '''}\n\n# Type constants
TYPES = {
'''

    type_consts = {k: v for k, v in constants.items() if k.startswith('TYPE_')}
    for name in sorted(type_consts.keys()):
        spec_content += f"    '{name}': {hex(type_consts[name]) if isinstance(type_consts[name], int) and type_consts[name] > 255 else type_consts[name]},\n"

    spec_content += '''}\n\n# Opcode constants
OPCODES = {
'''

    op_consts = {k: v for k, v in constants.items() if k.startswith('OP_')}
    for name in sorted(op_consts.keys()):
        spec_content += f"    '{name}': {op_consts[name]},\n"

    spec_content += '''}\n\n# Structure definitions with field offsets
STRUCTURES = {
'''

    for struct_name in sorted(structs.keys()):
        struct = structs[struct_name]
        spec_content += f'''    '{struct_name}': {{
        'size': {struct['size']},
        'fields': {{
'''
        for field in struct['fields']:
            spec_content += f"            '{field['name']}': {{'offset': {field['offset']}, 'size': {field['size']}, 'type': '{field['type']}'}},\n"
        spec_content += '''        }
    },
'''

    spec_content += '''}\n\n# All constants (for reference)
ALL_CONSTANTS = {
'''

    for name in sorted(constants.keys()):
        value = constants[name]
        if isinstance(value, int):
            spec_content += f"    '{name}': {hex(value) if value > 255 else value},\n"
        else:
            spec_content += f"    '{name}': {repr(value)},\n"

    spec_content += "}\n"

    with open(output_path, 'w') as f:
        f.write(spec_content)

    print(f"✅ Generated {output_path}")
    print(f"   Tokens: {len(token_consts)}")
    print(f"   Types: {len(type_consts)}")
    print(f"   Opcodes: {len(op_consts)}")
    print(f"   Structures: {len(structs)}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 generate_jda0_spec.py <jda1.jda> [output_file]")
        sys.exit(1)

    jda1_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'tools/jda0_spec.py'

    print(f"📖 Parsing {jda1_path}...")
    constants = extract_constants(jda1_path)
    structs = extract_structs(jda1_path)

    print(f"   Found {len(constants)} constants")
    print(f"   Found {len(structs)} structures")

    generate_spec_file(constants, structs, output_path)

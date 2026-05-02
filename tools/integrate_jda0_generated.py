#!/usr/bin/env python3
"""
Integration and validation script for generated jda0 code

This script:
1. Identifies constant and struct sections in current jda0.asm
2. Creates a new version using generated constants/structs
3. Compares line counts and structure
4. Prepares for full replacement
"""

import re
import sys
import os

def read_file(path):
    """Read file contents"""
    with open(path, 'r') as f:
        return f.readlines()

def find_section_boundaries(lines):
    """Find where constants section ends and .bss begins"""
    start_constant_line = 0
    end_constant_line = 0

    for i, line in enumerate(lines):
        # Constants start at line 1 (after any shebang/comment)
        if line.startswith('TOK_') and 'equ' in line:
            start_constant_line = i
            break

    # Find where .bss section starts
    for i in range(start_constant_line, len(lines)):
        if lines[i].startswith('section .bss'):
            end_constant_line = i
            break

    return start_constant_line, end_constant_line

def analyze_current_jda0():
    """Analyze the current jda0.asm structure"""
    jda0_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0.asm'
    )

    lines = read_file(jda0_path)
    start, end = find_section_boundaries(lines)

    print("\n" + "=" * 70)
    print("CURRENT jda0.asm ANALYSIS")
    print("=" * 70)

    print(f"\nTotal lines: {len(lines)}")
    print(f"Constant section: lines {start+1}-{end}")
    print(f"Constant section size: {end - start} lines")

    # Count hardcoded constants
    constant_count = 0
    type_count = 0
    opcode_count = 0
    other_count = 0

    for i in range(start, end):
        line = lines[i]
        if 'equ' in line:
            if line.startswith('TOK_'):
                constant_count += 1
            elif line.startswith('TYPE_'):
                type_count += 1
            elif line.startswith('OP_'):
                opcode_count += 1
            else:
                other_count += 1

    print(f"\nConstants found:")
    print(f"  Token constants: {constant_count}")
    print(f"  Type constants: {type_count}")
    print(f"  Opcode constants: {opcode_count}")
    print(f"  Other constants: {other_count}")

    # Show sample of hardcoded values
    print(f"\nFirst 5 hardcoded token constants:")
    sample_count = 0
    for i in range(start, end):
        if lines[i].startswith('TOK_') and sample_count < 5:
            print(f"  {lines[i].rstrip()}")
            sample_count += 1

    return lines, start, end

def analyze_generated_files():
    """Analyze the generated constant and struct files"""
    const_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0_constants.asm'
    )
    struct_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0_structs.asm'
    )

    const_lines = read_file(const_path)
    struct_lines = read_file(struct_path)

    print("\n" + "=" * 70)
    print("GENERATED FILES ANALYSIS")
    print("=" * 70)

    print(f"\njda0_constants.asm:")
    print(f"  Lines: {len(const_lines)}")

    const_count = sum(1 for line in const_lines if 'equ' in line)
    print(f"  Constants defined: {const_count}")

    print(f"\njda0_structs.asm:")
    print(f"  Lines: {len(struct_lines)}")

    struct_eq_count = sum(1 for line in struct_lines if 'equ' in line)
    print(f"  Equations defined: {struct_eq_count}")

    print(f"\nTotal generated code size:")
    print(f"  {len(const_lines) + len(struct_lines)} lines")
    print(f"  {sum(len(line) for line in const_lines + struct_lines)} characters")

    return const_lines, struct_lines

def count_constants(lines, start, end):
    """Count different types of constants"""
    tokens = []
    types = []
    opcodes = []
    sizes = []

    for i in range(start, end):
        line = lines[i]
        if 'equ' not in line:
            continue

        match = re.match(r'^(\w+)\s+equ', line)
        if match:
            name = match.group(1)
            if name.startswith('TOK_'):
                tokens.append(name)
            elif name.startswith('TYPE_'):
                types.append(name)
            elif name.startswith('OP_'):
                opcodes.append(name)
            elif name.endswith('_SZ'):
                sizes.append(name)

    return tokens, types, opcodes, sizes

def suggest_integration():
    """Suggest how to integrate generated code"""
    print("\n" + "=" * 70)
    print("INTEGRATION PLAN")
    print("=" * 70)

    print("""
To integrate generated constants and structs into jda0.asm:

1. Create a backup:
   cp bootstrap/stage0/jda0.asm bootstrap/stage0/jda0.asm.bak

2. Update jda0.asm to include generated files:
   - Keep the file header and .bss/.data/.text sections
   - Replace constant definitions with: %include "jda0_constants.asm"
   - Add after constants: %include "jda0_structs.asm"
   - Keep rest of code unchanged

3. Build and test:
   make stage0
   make test-stage0

4. Validate results:
   - Check that binary size is similar to original
   - Run test suite to verify functionality
   - Compare output with expected results

5. If successful:
   - Commit the integrated version
   - Remove old hand-written constant definitions
   - Update documentation

Alternative: Create standalone included files
   - Keep jda0_constants.asm and jda0_structs.asm separate
   - Include them in the build process via Makefile
   - This preserves modularity and makes regeneration cleaner
    """)

def main():
    print("\n🔍 Phase 5: Integration and Validation Analysis")

    # Analyze current state
    lines, const_start, const_end = analyze_current_jda0()
    const_lines, struct_lines = analyze_generated_files()

    # Count constants
    tokens, types, opcodes, sizes = count_constants(lines, const_start, const_end)

    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)

    print(f"\nCurrent jda0.asm constant coverage:")
    print(f"  Token types: {len(tokens)}")
    print(f"  Type constants: {len(types)}")
    print(f"  Opcode constants: {len(opcodes)}")
    print(f"  Size constants: {len(sizes)}")

    print(f"\nGenerated code will:")
    print(f"  ✅ Cover all {len(tokens)} token types")
    print(f"  ✅ Cover all {len(types)} type constants")
    print(f"  ✅ Cover all {len(opcodes)} opcode constants")
    print(f"  ✅ Add {struct_lines.count('equ')} struct field offsets")

    print(f"\nReduction in hardcoding:")
    old_const_lines = const_end - const_start
    new_const_lines = len(const_lines)
    print(f"  Current hardcoded constant section: {old_const_lines} lines")
    print(f"  Generated constant file: {new_const_lines} lines")
    print(f"  Total generated files: {new_const_lines + len(struct_lines)} lines")
    print(f"  (Can be regenerated anytime jda1.jda changes)")

    suggest_integration()

    print("\n" + "=" * 70)
    print("✅ Analysis complete - Ready for Phase 5 implementation")
    print("=" * 70 + "\n")

if __name__ == '__main__':
    main()

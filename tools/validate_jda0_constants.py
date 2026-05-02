#!/usr/bin/env python3
"""
Validate that generated jda0 constants match the current jda0.asm

This script compares:
1. Tokens in generated vs. current jda0.asm
2. Type constants
3. Opcode constants
4. Structure sizes

Output: Detailed report of any mismatches
"""

import re
import sys
import os

def extract_constants_from_asm(asm_path):
    """Extract all constants from NASM file in format: NAME equ VALUE"""
    constants = {}

    with open(asm_path, 'r') as f:
        for line in f:
            # Match: NAME equ VALUE (or NAME = VALUE for older syntax)
            match = re.match(r'^(\w+)\s+equ\s+(\S+)', line)
            if match:
                name = match.group(1)
                value = match.group(2)

                # Parse hex or decimal values
                try:
                    if value.startswith('0x'):
                        constants[name] = int(value, 16)
                    else:
                        constants[name] = int(value)
                except ValueError:
                    constants[name] = value

    return constants

def load_generated_spec():
    """Load the generated jda0_spec.py"""
    spec_path = os.path.join(os.path.dirname(__file__), 'jda0_spec.py')

    spec = {}
    with open(spec_path, 'r') as f:
        content = f.read()
        exec(content, spec)

    return spec

def flatten_spec_constants(spec):
    """Flatten spec dictionaries into single constants dict"""
    constants = {}

    # Add all token constants
    if 'TOKENS' in spec:
        constants.update(spec['TOKENS'])

    # Add all type constants
    if 'TYPES' in spec:
        constants.update(spec['TYPES'])

    # Add all opcode constants
    if 'OPCODES' in spec:
        constants.update(spec['OPCODES'])

    # Add structure sizes
    if 'STRUCTURES' in spec:
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

        for struct_name, const_name in size_mapping.items():
            if struct_name in spec['STRUCTURES']:
                constants[const_name] = spec['STRUCTURES'][struct_name]['size']

    return constants

def compare_constants(current, generated):
    """Compare two constant dictionaries and report differences"""
    all_names = set(current.keys()) | set(generated.keys())

    matches = 0
    mismatches = []
    missing_in_generated = []
    extra_in_generated = []

    for name in sorted(all_names):
        if name not in current:
            extra_in_generated.append((name, generated[name]))
        elif name not in generated:
            missing_in_generated.append((name, current[name]))
        elif current[name] == generated[name]:
            matches += 1
        else:
            mismatches.append((name, current[name], generated[name]))

    return {
        'matches': matches,
        'mismatches': mismatches,
        'missing_in_generated': missing_in_generated,
        'extra_in_generated': extra_in_generated,
    }

def report_validation(comparison):
    """Print validation report"""
    total = comparison['matches'] + len(comparison['mismatches']) + len(comparison['missing_in_generated'])

    print("\n" + "=" * 70)
    print("CONSTANT VALIDATION REPORT")
    print("=" * 70)

    print(f"\n✅ Matches: {comparison['matches']}/{total}")

    if comparison['mismatches']:
        print(f"\n❌ VALUE MISMATCHES ({len(comparison['mismatches'])} found):")
        print("-" * 70)
        for name, old_val, new_val in comparison['mismatches']:
            print(f"  {name:25} OLD: {old_val:6}  NEW: {new_val:6}")

    if comparison['missing_in_generated']:
        print(f"\n⚠️  MISSING IN GENERATED ({len(comparison['missing_in_generated'])} found):")
        print("-" * 70)
        for name, value in comparison['missing_in_generated']:
            print(f"  {name:25} = {value}")
        print("\n  These constants are in current jda0.asm but not in jda1.jda")
        print("  They may be deprecated or unused.")

    if comparison['extra_in_generated']:
        print(f"\n✨ NEW IN GENERATED ({len(comparison['extra_in_generated'])} found):")
        print("-" * 70)
        for name, value in comparison['extra_in_generated']:
            print(f"  {name:25} = {value}")
        print("\n  These are new constants from jda1.jda")

    print("\n" + "=" * 70)
    success = len(comparison['mismatches']) == 0 and len(comparison['missing_in_generated']) == 0
    if success:
        print("✅ VALIDATION PASSED - Generated constants ready!")
    else:
        print("⚠️  VALIDATION COMPLETE - Review differences above")
    print("=" * 70 + "\n")

    return success

def main():
    current_jda0_path = os.path.join(
        os.path.dirname(__file__),
        '../bootstrap/stage0/jda0.asm'
    )

    print("📖 Loading current jda0.asm...")
    current = extract_constants_from_asm(current_jda0_path)
    print(f"   Found {len(current)} constants")

    print("📖 Loading generated spec...")
    spec = load_generated_spec()
    generated = flatten_spec_constants(spec)
    print(f"   Found {len(generated)} constants")

    print("\n🔍 Comparing constants...")
    comparison = compare_constants(current, generated)

    success = report_validation(comparison)

    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())

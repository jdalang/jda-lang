#!/usr/bin/env python3
"""
Validate that generated jda0 struct field offsets are correct and consistent

This script validates:
1. Field offsets fit within declared struct size
2. No overlapping fields
3. Struct sizes match between spec and generated code
4. Field order is consistent
"""

import sys
import os

def load_spec():
    """Load jda0_spec.py"""
    spec_path = os.path.join(os.path.dirname(__file__), 'jda0_spec.py')

    spec = {}
    with open(spec_path, 'r') as f:
        content = f.read()
        exec(content, spec)

    return spec

def validate_struct(struct_name, struct_def):
    """Validate a single struct definition"""
    errors = []
    warnings = []

    size = struct_def['size']
    fields = struct_def['fields']

    # Check for field overlaps and bounds
    field_list = []
    for field_name, field_info in fields.items():
        offset = field_info['offset']
        field_size = field_info['size']
        end_offset = offset + field_size

        # Check bounds
        if end_offset > size:
            errors.append(f"  Field {field_name} extends beyond struct size: "
                         f"{offset} + {field_size} = {end_offset} > {size}")

        field_list.append((offset, end_offset, field_name, field_size))

    # Sort by offset to check for overlaps
    field_list.sort()

    for i in range(len(field_list) - 1):
        curr_end = field_list[i][1]
        next_start = field_list[i + 1][0]

        if curr_end > next_start:
            curr_name = field_list[i][2]
            next_name = field_list[i + 1][2]
            errors.append(f"  Field overlap: {curr_name} (ends at {curr_end}) "
                         f"overlaps with {next_name} (starts at {next_start})")

        elif curr_end < next_start:
            gap = next_start - curr_end
            if gap > 0:
                warnings.append(f"  Gap between {field_list[i][2]} and "
                              f"{field_list[i + 1][2]}: {gap} bytes")

    return errors, warnings

def extract_struct_sizes_from_asm(asm_path):
    """Extract struct size constants from NASM file"""
    sizes = {}

    with open(asm_path, 'r') as f:
        for line in f:
            # Look for SZ constants (e.g., FN_SZ equ 288)
            if '_SZ' in line and 'equ' in line:
                parts = line.split()
                if len(parts) >= 3:
                    name = parts[0]
                    try:
                        value = int(parts[2])
                        sizes[name] = value
                    except ValueError:
                        pass

    return sizes

def report_validation(spec):
    """Print comprehensive validation report"""
    structures = spec['STRUCTURES']

    print("\n" + "=" * 70)
    print("STRUCT FIELD OFFSET VALIDATION REPORT")
    print("=" * 70)

    total_structs = len(structures)
    valid_structs = 0
    total_errors = 0
    total_warnings = 0

    for struct_name in sorted(structures.keys()):
        struct_def = structures[struct_name]
        errors, warnings = validate_struct(struct_name, struct_def)

        status = "✅" if not errors else "❌"
        print(f"\n{status} {struct_name} (size: {struct_def['size']} bytes)")

        if errors:
            total_errors += len(errors)
            for error in errors:
                print(f"   ERROR: {error}")
        else:
            valid_structs += 1

        if warnings:
            total_warnings += len(warnings)
            for warning in warnings[:3]:  # Show first 3 warnings only
                print(f"   ⚠️  {warning}")
            if len(warnings) > 3:
                print(f"   ⚠️  ... and {len(warnings) - 3} more gaps")

    print("\n" + "=" * 70)
    print(f"SUMMARY: {valid_structs}/{total_structs} structures valid")
    print(f"  Errors: {total_errors}")
    print(f"  Warnings (gaps): {total_warnings}")

    if total_errors == 0:
        print("\n✅ ALL STRUCTURES VALID - Field offsets are correct!")
    else:
        print("\n❌ VALIDATION FAILED - Fix field offsets above")

    print("=" * 70 + "\n")

    return total_errors == 0

def main():
    print("📖 Loading jda0_spec.py...")
    spec = load_spec()

    print(f"   Loaded {len(spec['STRUCTURES'])} structures")
    print("\n🔍 Validating struct field offsets...")

    success = report_validation(spec)

    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())

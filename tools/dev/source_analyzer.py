#!/usr/bin/env python3
"""
Analyze Jda source file to identify missing Stage 0 features.
Reports feature usage statistics and generates feature gap inventory.

Usage:
    python3 source_analyzer.py <jda_file>
    python3 source_analyzer.py bootstrap/stage1/jda1.jda
"""

import sys
import re
from collections import defaultdict
import json

def analyze_file(filepath):
    """Analyze a Jda source file for feature usage."""
    with open(filepath, 'r') as f:
        content = f.read()
        lines = content.split('\n')
    
    stats = {
        'file': filepath,
        'total_lines': len(lines),
        'structs': [],
        'functions': [],
        'feature_counts': defaultdict(int),
        'feature_lines': defaultdict(list),
    }
    
    # Track line-by-line
    for line_num, line in enumerate(lines, 1):
        stripped = line.strip()
        
        # Struct definitions
        if stripped.startswith('struct '):
            match = re.match(r'struct\s+(\w+)\s*{', stripped)
            if match:
                name = match.group(1)
                stats['structs'].append({'name': name, 'line': line_num})
                stats['feature_counts']['struct_def'] += 1
                stats['feature_lines']['struct_def'].append(line_num)
        
        # Function definitions
        if stripped.startswith('fn '):
            match = re.match(r'fn\s+(\w+)\s*\(', stripped)
            if match:
                name = match.group(1)
                stats['functions'].append({'name': name, 'line': line_num})
                stats['feature_counts']['fn_def'] += 1
                stats['feature_lines']['fn_def'].append(line_num)
        
        # Keywords and control flow
        keywords = {
            'fn ': 'fn_keyword',
            'let ': 'let_binding',
            'if ': 'if_stmt',
            'else': 'else_stmt',
            'loop ': 'loop_stmt',
            'ret ': 'ret_stmt',
            'struct ': 'struct_keyword',
            'match ': 'match_expr',
            'print(': 'print_call',
            'syscall(': 'syscall_call',
        }
        
        for kw, feature in keywords.items():
            if kw in stripped:
                stats['feature_counts'][feature] += 1
                if line_num not in stats['feature_lines'][feature]:
                    stats['feature_lines'][feature].append(line_num)
        
        # Type annotations
        types = {
            '-> i64': 'ret_type_i64',
            '-> i32': 'ret_type_i32',
            '-> i8': 'ret_type_i8',
            '-> f64': 'ret_type_f64',
            ': i64': 'param_type_i64',
            ': i32': 'param_type_i32',
            ': i8': 'param_type_i8',
            ': f64': 'param_type_f64',
            ': &i8': 'ptr_type_i8',
        }
        
        for type_sig, feature in types.items():
            if type_sig in stripped:
                stats['feature_counts'][feature] += 1
        
        # Operators
        if '==' in stripped:
            stats['feature_counts']['op_eq'] += 1
        if '!=' in stripped:
            stats['feature_counts']['op_neq'] += 1
        if '=>' in stripped:
            stats['feature_counts']['fat_arrow'] += 1
        if '&' in stripped and '&i8' not in stripped:
            stats['feature_counts']['borrow_op'] += 1
    
    # Convert defaultdict to regular dict for JSON
    stats['feature_counts'] = dict(stats['feature_counts'])
    for key in stats['feature_lines']:
        stats['feature_lines'][key].sort()
    
    return stats

def stage0_support():
    """List features currently supported by Stage 0."""
    return {
        'print_call': True,
        'let_binding': True,
        'ret_stmt': True,
        'simple_arithmetic': True,
    }

def identify_gaps(analysis):
    """Identify features in the file not supported by Stage 0."""
    stage0 = stage0_support()
    
    gaps = {
        'critical': [],
        'important': [],
        'nice_to_have': [],
    }
    
    # Critical for bootstrapping Stage 1
    critical_features = [
        'fn_def', 'struct_def', 'if_stmt', 'loop_stmt', 'match_expr'
    ]
    
    for feature in critical_features:
        if analysis['feature_counts'].get(feature, 0) > 0:
            count = analysis['feature_counts'][feature]
            lines = analysis['feature_lines'].get(feature, [])
            gaps['critical'].append({
                'feature': feature,
                'count': count,
                'lines': lines[:5],  # Show first 5 occurrences
                'priority': 'HIGH - required for self-hosting'
            })
    
    # Important but not critical
    important_features = ['syscall_call', 'match_expr', 'fat_arrow']
    for feature in important_features:
        if analysis['feature_counts'].get(feature, 0) > 0 and feature not in [x['feature'] for x in gaps['critical']]:
            count = analysis['feature_counts'][feature]
            lines = analysis['feature_lines'].get(feature, [])
            gaps['important'].append({
                'feature': feature,
                'count': count,
                'lines': lines[:5],
            })
    
    return gaps

def print_report(filepath):
    """Print analysis report."""
    analysis = analyze_file(filepath)
    gaps = identify_gaps(analysis)
    
    print(f"\n{'='*70}")
    print(f"Jda Source Analysis: {filepath}")
    print(f"{'='*70}\n")
    
    print(f"Total lines:        {analysis['total_lines']}")
    print(f"Struct definitions: {len(analysis['structs'])}")
    print(f"Function defs:      {len(analysis['functions'])}\n")
    
    print("Feature Inventory:")
    print("-" * 70)
    
    # Sort by count
    features = sorted(
        analysis['feature_counts'].items(),
        key=lambda x: x[1],
        reverse=True
    )
    
    for feature, count in features:
        lines = analysis['feature_lines'].get(feature, [])
        line_info = f" (lines: {lines[:3]})" if lines else ""
        print(f"  {feature:25} {count:4} uses{line_info}")
    
    print(f"\nCritical Feature Gaps (Stage 0 missing):")
    print("-" * 70)
    for gap in gaps['critical']:
        print(f"  ❌ {gap['feature']:25} {gap['count']:3} uses - {gap['priority']}")
        if gap['lines']:
            print(f"     First occurrences: {gap['lines'][:5]}")
    
    if gaps['important']:
        print(f"\nImportant Feature Gaps:")
        print("-" * 70)
        for gap in gaps['important']:
            print(f"  ⚠️  {gap['feature']:25} {gap['count']:3} uses")
            if gap['lines']:
                print(f"     First occurrences: {gap['lines'][:5]}")
    
    # Stage 0 capability summary
    print(f"\nStage 0 Currently Supports:")
    print("-" * 70)
    for feature, supported in stage0_support().items():
        symbol = "✓" if supported else "✗"
        print(f"  {symbol} {feature}")
    
    print(f"\nBootstrap Path:")
    print("-" * 70)
    print(f"  Stage 0 (NASM) -> Stage 1 ({analysis['total_lines']} lines, {len(analysis['functions'])} functions)")
    print(f"  Missing {len(gaps['critical'])} critical feature types to compile jda1.jda\n")
    
    # JSON output
    return {
        'analysis': analysis,
        'gaps': gaps,
    }

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 source_analyzer.py <jda_file>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    result = print_report(filepath)
    
    # Optional: write JSON output
    if len(sys.argv) > 2 and sys.argv[2] == '--json':
        import json
        # Convert sets to lists for JSON serialization
        result['analysis']['feature_lines'] = {k: v for k, v in result['analysis']['feature_lines'].items()}
        print("\n" + json.dumps(result, indent=2, default=str))

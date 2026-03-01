#!/usr/bin/env python3
"""
Split large Jda source files into smaller, compilable chunks.
Preserves cross-chunk dependencies (function signatures, struct definitions).

Usage:
    python3 source_splitter.py <input.jda> [--chunk-size 500]
"""

import sys
import re
from typing import List, Tuple, Dict

class SourceSplitter:
    def __init__(self, filepath: str, chunk_size: int = 500):
        self.filepath = filepath
        self.chunk_size = chunk_size
        with open(filepath, 'r') as f:
            self.content = f.read()
            self.lines = self.content.split('\n')
        
        self.structs = []
        self.functions = []
        self.constants = []
        self._parse_definitions()
    
    def _parse_definitions(self):
        """Parse struct/function/const definitions from source."""
        i = 0
        while i < len(self.lines):
            line = self.lines[i]
            stripped = line.strip()
            
            # Struct definitions
            if stripped.startswith('struct '):
                match = re.match(r'struct\s+(\w+)\s*{', stripped)
                if match:
                    name = match.group(1)
                    start = i
                    # Find closing brace
                    brace_count = stripped.count('{') - stripped.count('}')
                    j = i + 1
                    while j < len(self.lines) and brace_count > 0:
                        brace_count += self.lines[j].count('{') - self.lines[j].count('}')
                        j += 1
                    self.structs.append({
                        'name': name,
                        'start': start,
                        'end': j - 1,
                        'lines': list(range(start, j))
                    })
                    i = j
                    continue
            
            # Function definitions
            if stripped.startswith('fn '):
                match = re.match(r'fn\s+(\w+)\s*\(', stripped)
                if match:
                    name = match.group(1)
                    start = i
                    # Find closing brace
                    brace_count = 0
                    in_signature = True
                    j = i
                    while j < len(self.lines):
                        line_text = self.lines[j]
                        if in_signature and '{' in line_text:
                            in_signature = False
                        brace_count += line_text.count('{') - line_text.count('}')
                        if brace_count == 0 and not in_signature:
                            break
                        j += 1
                    self.functions.append({
                        'name': name,
                        'start': start,
                        'end': j,
                        'lines': list(range(start, j + 1))
                    })
                    i = j + 1
                    continue
            
            # Const definitions
            if stripped.startswith('const '):
                match = re.match(r'const\s+(\w+)\s*=', stripped)
                if match:
                    name = match.group(1)
                    self.constants.append({
                        'name': name,
                        'line': i,
                        'text': line
                    })
            
            i += 1
    
    def generate_header_chunk(self) -> str:
        """Generate chunk with all constants and struct definitions."""
        lines = []
        
        # Add header comment
        lines.append("; GENERATED: Header chunk with constants and struct definitions")
        lines.append("; This must be compiled before any functions that use these types")
        lines.append("")
        
        # Add all constants
        for const in self.constants:
            lines.append(const['text'])
        
        lines.append("")
        
        # Add all struct definitions
        for struct in self.structs:
            for line_no in struct['lines']:
                lines.append(self.lines[line_no])
        
        return '\n'.join(lines)
    
    def generate_function_chunk(self, func_index: int) -> str:
        """Generate chunk with a single function (with header deps)."""
        lines = []
        
        func = self.functions[func_index]
        lines.append(f"; GENERATED: Function chunk #{func_index}")
        lines.append(f"; Function: {func['name']} (lines {func['start']}-{func['end']})")
        lines.append("")
        
        # Add header (constants + structs)
        lines.append(self.generate_header_chunk())
        lines.append("")
        
        # Add the function
        lines.append("; ===== FUNCTION DEFINITION =====")
        for line_no in func['lines']:
            lines.append(self.lines[line_no])
        
        return '\n'.join(lines)
    
    def split_by_lines(self) -> List[str]:
        """Split source into chunks of ~chunk_size lines."""
        chunks = []
        i = 0
        
        while i < len(self.lines):
            # Create header chunk first time
            if i == 0:
                # Find all constants and structs before first function
                chunk_lines = []
                j = 0
                while j < len(self.lines) and not self.lines[j].strip().startswith('fn '):
                    chunk_lines.append(self.lines[j])
                    j += 1
                
                if chunk_lines:
                    chunks.append('\n'.join(chunk_lines))
                    i = j
            else:
                # Regular chunks of chunk_size
                chunk_end = min(i + self.chunk_size, len(self.lines))
                chunk = '\n'.join(self.lines[i:chunk_end])
                chunks.append(chunk)
                i = chunk_end
        
        return chunks
    
    def split_by_functions(self) -> List[str]:
        """Split source into one chunk per function (plus header)."""
        chunks = []
        
        # Header chunk with constants and structs
        header = self.generate_header_chunk()
        chunks.append(header)
        
        # One chunk per function
        for i in range(len(self.functions)):
            chunks.append(self.generate_function_chunk(i))
        
        return chunks
    
    def analyze_dependencies(self) -> Dict:
        """Analyze which functions call which other functions."""
        deps = {}
        for func in self.functions:
            deps[func['name']] = {'calls': [], 'lines': func['lines']}
            
            # Extract function body
            body_lines = [self.lines[ln] for ln in func['lines']]
            body_text = '\n'.join(body_lines)
            
            # Find function calls (simple heuristic)
            for other in self.functions:
                if other['name'] == func['name']:
                    continue
                # Look for patterns like "call func_name(" or just "func_name("
                pattern = rf'\b{other["name"]}\s*\('
                if re.search(pattern, body_text):
                    deps[func['name']]['calls'].append(other['name'])
        
        return deps


def print_report(splitter: SourceSplitter):
    """Print analysis report."""
    print(f"\n{'='*70}")
    print(f"Jda Source Splitter Analysis: {splitter.filepath}")
    print(f"{'='*70}\n")
    
    print(f"Total lines:         {len(splitter.lines)}")
    print(f"Constants:           {len(splitter.constants)}")
    print(f"Structs:             {len(splitter.structs)}")
    print(f"Functions:           {len(splitter.functions)}\n")
    
    print("Struct Definitions:")
    print("-" * 70)
    for s in splitter.structs[:5]:
        line_count = len(s['lines'])
        print(f"  {s['name']:20} lines {s['start']:4}-{s['end']:4} ({line_count} lines)")
    if len(splitter.structs) > 5:
        print(f"  ... and {len(splitter.structs) - 5} more")
    
    print("\nFunction Definitions (first 10):")
    print("-" * 70)
    for f in splitter.functions[:10]:
        line_count = len(f['lines'])
        print(f"  {f['name']:20} lines {f['start']:4}-{f['end']:4} ({line_count} lines)")
    if len(splitter.functions) > 10:
        print(f"  ... and {len(splitter.functions) - 10} more")
    
    # Show split strategy
    print("\nSplit Strategies:")
    print("-" * 70)
    
    by_lines = splitter.split_by_lines()
    print(f"  By-lines (chunk_size={splitter.chunk_size}):")
    print(f"    - Total chunks: {len(by_lines)}")
    print(f"    - Chunk sizes: {[len(c.split(chr(10))) for c in by_lines[:3]]} lines (first 3)")
    
    by_funcs = splitter.split_by_functions()
    print(f"\n  By-functions:")
    print(f"    - Total chunks: {len(by_funcs)}")
    print(f"    - Header chunk: ~{len(by_funcs[0].split(chr(10)))} lines")
    print(f"    - Per-function chunks: ~{len(by_funcs[1].split(chr(10)))} lines each (avg)")
    
    # Dependencies
    deps = splitter.analyze_dependencies()
    print(f"\nFunction Call Dependencies (first 5):")
    print("-" * 70)
    for name in list(deps.keys())[:5]:
        dep = deps[name]
        calls = dep['calls']
        if calls:
            print(f"  {name:20} calls: {', '.join(calls[:3])}")
            if len(calls) > 3:
                print(f"  {' ':20}        ... and {len(calls)-3} more")
        else:
            print(f"  {name:20} (no internal calls)")
    
    print("\nRecommendation:")
    print("-" * 70)
    print("  For Stage 1 self-hosting, use 'by-functions' strategy:")
    print("  1. Compile header chunk (constants + structs)")
    print("  2. Compile each function chunk individually")
    print("  3. Link compiled chunks together")
    print("  This allows incremental compilation and easier error isolation.\n")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 source_splitter.py <input.jda> [--chunk-size 500]")
        sys.exit(1)
    
    filepath = sys.argv[1]
    chunk_size = 500
    
    if '--chunk-size' in sys.argv:
        idx = sys.argv.index('--chunk-size')
        if idx + 1 < len(sys.argv):
            chunk_size = int(sys.argv[idx + 1])
    
    splitter = SourceSplitter(filepath, chunk_size)
    print_report(splitter)

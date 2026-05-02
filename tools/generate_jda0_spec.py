#!/usr/bin/env python3
import re
import sys

def extract_constants(jda1_path):
    constants = {}
    with open(jda1_path, 'r') as f:
        for line in f:
            match = re.match(r'^const\s+(\w+)\s*=\s*(\S+)', line)
            if match:
                name, value = match.groups()
                if value.startswith('0x'):
                    constants[name] = int(value, 16)
                else:
                    try:
                        constants[name] = int(value)
                    except:
                        constants[name] = value
    return constants

def extract_structs(jda1_path):
    structs = {}
    with open(jda1_path, 'r') as f:
        lines = f.readlines()

    def get_size(t, known_structs):
        if 'i64' in t: return 8
        if 'i32' in t: return 4
        if 'i8' in t: return 1
        if '&' in t: return 8
        base = t.split('[')[0]
        if base in known_structs:
            base_size = known_structs[base]['size']
        else:
            if 'Token' in base: base_size = 40
            elif 'Node' in base: base_size = 112
            elif 'Instr' in base: base_size = 96
            elif 'Fixup' in base: base_size = 32
            elif 'VarEntry' in base: base_size = 32
            else: base_size = 8
        
        if '[' in t:
            count = int(re.search(r'\[(\d+)\]', t).group(1))
            return count * base_size
        return base_size

    for _ in range(3):
        current_struct = None
        fields = {}
        offset = 0
        for line in lines:
            if re.match(r'^struct\s+(\w+)\s*\{', line):
                current_struct = re.match(r'^struct\s+(\w+)', line).group(1)
                fields = {}
                offset = 0
            elif current_struct and re.match(r'^\s+(\w+):\s*(\S+)', line):
                match = re.match(r'^\s+(\w+):\s*(\S+)', line)
                f_name, f_type = match.groups()
                if offset % 8 != 0: offset = (offset + 7) & ~7
                f_size = get_size(f_type, structs)
                fields[f_name] = {'offset': offset, 'size': f_size}
                offset += f_size
            elif current_struct and re.match(r'^\}', line):
                structs[current_struct] = {'fields': fields, 'size': offset}
                current_struct = None
    return structs

def main():
    jda1_path = sys.argv[1]
    output_path = sys.argv[2]
    consts = extract_constants(jda1_path)
    structs = extract_structs(jda1_path)
    with open(output_path, 'w') as f:
        f.write("#!/usr/bin/env python3\n")
        f.write("CONSTANTS = " + repr(consts) + "\n")
        f.write("STRUCTURES = " + repr(structs) + "\n")

if __name__ == "__main__":
    main()

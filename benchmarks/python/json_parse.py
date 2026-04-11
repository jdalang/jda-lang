"""JSON parse benchmark — parse array of objects, sum 'value' fields"""
import json

NUM_OBJECTS = 50000

def generate_json(n):
    parts = []
    for i in range(n):
        parts.append(f'{{"id":{i},"value":{100 + (i % 1000)}}}')
    return "[" + ",".join(parts) + "]"

json_str = generate_json(NUM_OBJECTS)
entries = json.loads(json_str)
total = sum(e["value"] for e in entries)
print(f"len={len(json_str)} sum={total}")

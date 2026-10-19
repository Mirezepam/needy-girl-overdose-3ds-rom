"""Lists hardcoded Japanese string literals in the transpiled Lua that can reach the screen.

usage: python -X utf8 find_jp.py <port3ds/lua/gen>
"""
import collections
import os
import re
import sys

GEN = sys.argv[1]
JP = re.compile(r'"((?:[^"\\]|\\.)*[぀-ヿ一-鿿](?:[^"\\]|\\.)*)"')
hits = collections.defaultdict(list)
for fn in sorted(os.listdir(GEN)):
    for ln, line in enumerate(open(os.path.join(GEN, fn), encoding="utf-8"), 1):
        if "Debug.Log" in line:
            continue
        for m in JP.findall(line):
            hits[fn].append((ln, m[:50], line.strip()[:110]))
for fn, items in sorted(hits.items(), key=lambda kv: -len(kv[1])):
    print(f"{fn} ({len(items)})")
    for ln, m, line in items[:3]:
        print(f"   {ln}: {line}")

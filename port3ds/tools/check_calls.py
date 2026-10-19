"""Checks that hand-written Lua (ui/, override/, runtime/) only calls methods that exist in the
transpiled classes (cs2lua mangles overloads as Name_1, Name_2...).

usage: python check_calls.py <port3ds/lua>
"""
import os
import re
import sys

LUA = sys.argv[1]
GEN = os.path.join(LUA, "gen")
defs = {}
for fn in os.listdir(GEN):
    if fn.endswith(".lua") and not fn.startswith("_"):
        src = open(os.path.join(GEN, fn), encoding="utf-8").read()
        defs[fn[:-4]] = set(re.findall(r"^function C[.:](\w+)", src, re.M)) | set(re.findall(r"^\s+self\.(\w+) =", src, re.M)) \
            | set(re.findall(r'C\.__getters\["(\w+)"\]', src)) | set(re.findall(r"^C\.(\w+) =", src, re.M))

overrides = {}
for fn in os.listdir(os.path.join(LUA, "override")):
    if fn.endswith(".lua"):
        src = open(os.path.join(LUA, "override", fn), encoding="utf-8").read()
        overrides[fn[:-4]] = set(re.findall(r"function C[.:](\w+)", src)) | set(re.findall(r"self\.(\w+) =", src)) \
            | set(re.findall(r"C\.(\w+) =", src)) | set(re.findall(r'__getters\.(\w+)', src))

bad = 0
for sub in ("ui", "ui/apps", "override", "runtime"):
    d = os.path.join(LUA, sub)
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".lua"):
            continue
        for ln, line in enumerate(open(os.path.join(d, fn), encoding="utf-8"), 1):
            for cls, meth in re.findall(r"\b([A-Z]\w+)[.:](\w+)\s*\(", line):
                if cls not in defs:
                    continue
                known = defs[cls] | overrides.get(cls, set())
                # base classes are not resolved here; flag only clear misses
                if meth not in known and not meth.startswith("_"):
                    bad += 1
                    sugg = sorted(m for m in known if m.startswith(meth + "_"))
                    print(f"{sub}/{fn}:{ln}: {cls}.{meth} not found" + (f" (did you mean {', '.join(sugg)}?)" if sugg else ""))
print("problems:", bad)

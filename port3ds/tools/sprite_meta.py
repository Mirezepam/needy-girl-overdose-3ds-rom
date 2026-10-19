"""Exports Sprite metadata (9-slice borders, pivot, size) -> tools/.sprite_meta.json

usage: python -I sprite_meta.py <Game_Data dir>
"""
import json
import os
import re
import sys

import UnityPy

DATA = sys.argv[1]
SUFFIX_RE = re.compile(r"_-?\d{6,}$")
files = [os.path.join(DATA, f) for f in os.listdir(DATA) if f.startswith(("level", "sharedassets", "resources"))]
bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
files += [os.path.join(bdir, b) for b in os.listdir(bdir) if b.startswith("defaultlocalgroup")]
env = UnityPy.load(*files)
meta = {}
for obj in env.objects:
    if obj.type.name != "Sprite":
        continue
    try:
        s = obj.read()
        b = s.m_Border
        r = s.m_Rect
        name = SUFFIX_RE.sub("", s.m_Name)
        border = [round(b.x), round(b.y), round(b.z), round(b.w)]  # left, bottom, right, top
        if name not in meta or any(border):
            meta[name] = {"border": border, "w": round(r.width), "h": round(r.height),
                          "pivot": [round(s.m_Pivot.x, 3), round(s.m_Pivot.y, 3)]}
    except Exception:
        pass
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".sprite_meta.json")
json.dump(meta, open(out, "w", encoding="utf-8"))
print(len(meta), "sprites,", sum(1 for m in meta.values() if any(m["border"])), "with 9-slice borders")
for n in ("windowbase_active", "JINE_date", "BaseButton", "InputFieldBackground", "balloon", "tail", "PoketterNakami2"):
    print(n, meta.get(n))

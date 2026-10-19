"""Prints a dumped prefab tree compactly. usage: python -X utf8 show_prefab.py <prefab.json> [maxdepth]"""
import json
import sys

MAX = int(sys.argv[2]) if len(sys.argv) > 2 else 9


def col(c):
    return "#%02x%02x%02x%02x" % tuple(int(v * 255) for v in c) if c else ""


def walk(n, d=0):
    if d > MAX:
        return
    r = n.get("rect", {})
    parts = []
    for u in n.get("ui", []):
        s = u["class"]
        if u.get("sprite"):
            s += f":{u['sprite']}" + ("(9s)" if u.get("type") == 1 else "")
        if u.get("color") and u["color"] != [1, 1, 1, 1]:
            s += col(u["color"])
        if u.get("m_text"):
            s += ' "' + u["m_text"].replace("\n", " ")[:24] + '"'
        if u.get("m_fontSize"):
            s += f" {u['m_fontSize']}px" + col(u.get("fontColor"))
        parts.append(s)
    pos = r.get("m_AnchoredPosition")
    size = r.get("m_SizeDelta")
    anc = (r.get("m_AnchorMin"), r.get("m_AnchorMax"))
    print("  " * d + f"{n['name']}{'' if n['active'] else ' (off)'} size={size} pos={pos} anc={anc} | " + "  ".join(parts))
    for c in n["children"]:
        walk(c, d + 1)


walk(json.load(open(sys.argv[1], encoding="utf-8")))

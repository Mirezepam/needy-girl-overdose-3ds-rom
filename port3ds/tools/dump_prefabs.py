"""Dumps Unity UI prefab hierarchies (RectTransform layout, Image sprites, texts, animators) so the
3DS UI can reproduce the original windows.

usage: python -I dump_prefabs.py <Game_Data dir> <out dir> [name-prefix ...]
"""
import json
import os
import sys

import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

DATA, OUT = sys.argv[1], sys.argv[2]
PREFIXES = sys.argv[3:] or ["App_"]
gen = None


def tree(obj):
    global gen
    try:
        return obj.read_typetree()
    except Exception:
        pass
    if gen is None:
        gen = TypeTreeGenerator(obj.assets_file.unity_version)
        gen.load_local_game(os.path.dirname(DATA))
    script = obj.read(check_read=False).m_Script.read()
    full = f"{script.m_Namespace}.{script.m_ClassName}" if script.m_Namespace else script.m_ClassName
    return obj.read_typetree(gen.get_nodes_up(script.m_AssemblyName, full), check_read=False)


def deref(pptr):
    try:
        if pptr and pptr.m_PathID:
            return pptr.read()
    except Exception:
        return None


def v2(d):
    return [round(d["x"], 2), round(d["y"], 2)] if isinstance(d, dict) else None


def node(go):
    out = {"name": go.m_Name, "active": bool(go.m_IsActive), "children": []}
    rt = None
    for comp in go.m_Components:
        c = deref(comp.component if hasattr(comp, "component") else comp)
        if c is None:
            continue
        t = c.object_reader.type.name
        if t in ("RectTransform", "Transform"):
            rt = c
            if t == "RectTransform":
                tt = c.object_reader.read_typetree()
                out["rect"] = {k: v2(tt.get(k)) for k in ("m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition", "m_SizeDelta", "m_Pivot")}
        elif t == "MonoBehaviour":
            try:
                mb = c.object_reader.read(check_read=False)
                cls = mb.m_Script.read().m_ClassName
                tt = tree(c.object_reader)
            except Exception:
                continue
            entry = {"class": cls}
            if "m_Sprite" in tt:
                sp = deref(mb.m_Sprite) if hasattr(mb, "m_Sprite") else None
                if sp is None:
                    try:
                        pid = tt["m_Sprite"]["m_PathID"]
                        sp = c.object_reader.assets_file.objects[pid].read() if pid else None
                    except Exception:
                        sp = None
                entry["sprite"] = sp.m_Name if sp is not None else None
                entry["type"] = tt.get("m_Type")
            if "m_Color" in tt:
                col = tt["m_Color"]
                entry["color"] = [round(col["r"], 3), round(col["g"], 3), round(col["b"], 3), round(col["a"], 3)]
            for key in ("m_text", "m_fontSize", "m_enableWordWrapping", "m_HorizontalAlignment", "m_VerticalAlignment"):
                if key in tt:
                    entry[key] = tt[key]
            if "m_fontColor" in tt:
                col = tt["m_fontColor"]
                entry["fontColor"] = [round(col["r"], 3), round(col["g"], 3), round(col["b"], 3), round(col["a"], 3)]
            out.setdefault("ui", []).append(entry)
        elif t == "Animator":
            ctl = deref(getattr(c, "m_Controller", None))
            out["animator"] = ctl.m_Name if ctl is not None else None
        elif t == "SpriteRenderer":
            sp = deref(getattr(c, "m_Sprite", None))
            out.setdefault("ui", []).append({"class": "SpriteRenderer", "sprite": sp.m_Name if sp else None})
    if rt is not None:
        for ch in rt.m_Children:
            t = deref(ch)
            if t is not None:
                g = deref(t.m_GameObject)
                if g is not None:
                    out["children"].append(node(g))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    only = os.environ.get("DUMP_FILES")
    if only:
        files = [os.path.join(DATA, f) for f in only.split(",")]
    else:
        files = [os.path.join(DATA, f) for f in os.listdir(DATA) if f.startswith(("level", "sharedassets", "resources"))]
        bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
        files += [os.path.join(bdir, b) for b in os.listdir(bdir) if b.startswith("defaultlocalgroup")]
    env = UnityPy.load(*files)
    done = set()
    for obj in env.objects:
        if obj.type.name != "GameObject":
            continue
        go = obj.read()
        if not any(go.m_Name.startswith(p) for p in PREFIXES) or go.m_Name in done:
            continue
        # roots only: transforms without a parent
        tr = None
        for comp in go.m_Components:
            c = deref(comp.component if hasattr(comp, "component") else comp)
            if c is not None and c.object_reader.type.name in ("RectTransform", "Transform"):
                tr = c
        if tr is not None and tr.m_Father and tr.m_Father.m_PathID:
            continue
        done.add(go.m_Name)
        with open(os.path.join(OUT, go.m_Name + ".json"), "w", encoding="utf-8") as f:
            json.dump(node(go), f, ensure_ascii=False, indent=1)
        print("dumped", go.m_Name)


main()

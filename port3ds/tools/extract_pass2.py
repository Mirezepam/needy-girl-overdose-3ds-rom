"""Second pass: MonoBehaviours via generated typetrees, VideoClips, failed Texture2Ds.

usage: python -I extract_pass2.py <Game_Data dir> <output dir>
"""
import json
import os
import re
import sys
from collections import Counter

import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

DATA, OUT = sys.argv[1], sys.argv[2]
stats = Counter()
errors = []
used = set()
gen = None


def safe(s):
    s = re.sub(r'[<>:"|?*\x00-\x1f]', "_", s).strip().strip(".")
    return s or "_"


def target(kind, name, container, path_id, ext):
    if container:
        rel = "/".join(safe(p) for p in os.path.splitext(container)[0].split("/"))
        base = os.path.join(OUT, kind, rel)
    else:
        base = os.path.join(OUT, kind, safe(name or f"unnamed_{path_id}"))
    p = base + ext
    if p.lower() in used:
        p = f"{base}_{path_id}{ext}"
    used.add(p.lower())
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def mb_tree(obj):
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
    nodes = gen.get_nodes_up(script.m_AssemblyName, full)
    return obj.read_typetree(nodes, check_read=False)


def process(env, label):
    containers = {}
    for path, reader in env.container.items():
        try:
            containers[(reader.assets_file.name, reader.path_id)] = path
        except Exception:
            pass
    for obj in env.objects:
        t = obj.type.name
        if t not in ("MonoBehaviour", "VideoClip", "Texture2D"):
            continue
        key = (obj.assets_file.name, obj.path_id)
        cont = containers.get(key)
        try:
            if t == "MonoBehaviour":
                tree = mb_tree(obj)
                name = tree.get("m_Name") or ""
                if not name:
                    try:
                        name = obj.read(check_read=False).m_Script.read().m_ClassName + f"_{obj.path_id}"
                    except Exception:
                        name = f"mb_{obj.path_id}"
                with open(target(t, name, cont, obj.path_id, ".json"), "w", encoding="utf-8") as f:
                    json.dump(tree, f, ensure_ascii=False, indent=1, default=repr)
            elif t == "VideoClip":
                d = obj.read()
                res = d.m_ExternalResources
                src = os.path.join(DATA, os.path.basename(res.m_Source))
                with open(src, "rb") as f:
                    f.seek(res.m_Offset)
                    data = f.read(res.m_Size)
                ext = os.path.splitext(d.m_OriginalPath or "")[1] or ".mp4"
                with open(target(t, d.m_Name, cont, obj.path_id, ext), "wb") as f:
                    f.write(data)
            else:  # retry textures only when their stream path is empty-but-sized
                d = obj.read()
                sd = getattr(d, "m_StreamData", None)
                if not sd or sd.path:
                    continue
                img = d.image
                if img is None or img.width == 0:
                    continue
                img.save(target("Texture2D_retry", d.m_Name, cont, obj.path_id, ".png"))
            stats[t] += 1
        except Exception as e:
            errors.append(f"[{label}] {t} {key}: {type(e).__name__}: {e}")


def main():
    top = [os.path.join(DATA, f) for f in os.listdir(DATA)
           if f.startswith(("level", "sharedassets", "resources", "globalgamemanagers"))]
    process(UnityPy.load(*top), "main")
    print(dict(stats), flush=True)
    bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
    for b in sorted(os.listdir(bdir)):
        try:
            process(UnityPy.load(os.path.join(bdir, b)), b)
        except Exception as e:
            errors.append(f"[{b}] load: {e}")
    with open(os.path.join(OUT, "_extract_report_pass2.json"), "w", encoding="utf-8") as f:
        json.dump({"counts": dict(stats), "errors": errors}, f, ensure_ascii=False, indent=1)
    print("done", dict(stats), "errors:", len(errors))


main()

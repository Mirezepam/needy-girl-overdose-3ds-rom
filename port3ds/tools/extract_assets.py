"""Extract assets from a Unity game data folder with UnityPy.

usage: python -I extract_assets.py <Game_Data dir> <output dir>
"""
import json
import os
import re
import sys
import traceback
from collections import Counter

import UnityPy

DATA, OUT = sys.argv[1], sys.argv[2]
MANAGED = os.path.join(DATA, "Managed")
stats = Counter()
errors = []
used = set()

try:
    from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator
    gen = TypeTreeGenerator("2022.3.0f1")
    gen.load_local_game(os.path.dirname(DATA))
    UnityPy.config.TYPETREE_GENERATOR = gen  # may not exist in all versions
except Exception as e:  # typetree generation is optional
    gen = None
    print("typetree generator unavailable:", e)


def safe(s):
    s = re.sub(r'[<>:"|?*\x00-\x1f]', "_", s).strip().strip(".")
    return s or "_"


def target(kind, name, container, path_id, ext):
    if container:
        rel = os.path.splitext(container)[0]
        rel = "/".join(safe(p) for p in rel.split("/"))
        base = os.path.join(OUT, kind, rel)
    else:
        base = os.path.join(OUT, kind, safe(name or f"unnamed_{path_id}"))
    p = base + ext
    if p.lower() in used:
        p = f"{base}_{path_id}{ext}"
    used.add(p.lower())
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def dump_tree(obj):
    try:
        return obj.read_typetree()
    except Exception:
        if gen is not None:
            try:
                return obj.read_typetree(gen.get_nodes_up(*obj.read().m_Script.read().get_full_name()))
            except Exception:
                pass
        raise


def process(env, label):
    containers = {}
    for path, reader in env.container.items():
        try:
            containers[(reader.assets_file.name, reader.path_id)] = path
        except Exception:
            pass
    for obj in env.objects:
        t = obj.type.name
        key = (obj.assets_file.name, obj.path_id)
        cont = containers.get(key)
        try:
            if t in ("Texture2D", "Sprite"):
                d = obj.read()
                img = d.image
                if img is None or img.width == 0:
                    continue
                img.save(target(t, d.m_Name, cont, obj.path_id, ".png"))
            elif t == "AudioClip":
                d = obj.read()
                for name, data in d.samples.items():
                    p = target("AudioClip", os.path.splitext(name)[0], cont, obj.path_id, ".wav")
                    with open(p, "wb") as f:
                        f.write(data)
            elif t == "TextAsset":
                d = obj.read()
                raw = d.m_Script
                raw = raw.encode("utf-8", "surrogateescape") if isinstance(raw, str) else bytes(raw)
                ext = os.path.splitext(d.m_Name)[1] or ".txt"
                with open(target("TextAsset", d.m_Name, cont, obj.path_id, "" if os.path.splitext(d.m_Name)[1] else ext), "wb") as f:
                    f.write(raw)
            elif t == "Font":
                d = obj.read()
                fd = bytes(d.m_FontData or b"")
                if fd:
                    ext = ".otf" if fd[:4] == b"OTTO" else ".ttf"
                    with open(target("Font", d.m_Name, cont, obj.path_id, ext), "wb") as f:
                        f.write(fd)
            elif t == "VideoClip":
                d = obj.read()
                data = d.m_VideoData
                ext = os.path.splitext(d.m_OriginalPath or "")[1] or ".mp4"
                with open(target("VideoClip", d.m_Name, cont, obj.path_id, ext), "wb") as f:
                    f.write(bytes(data))
            elif t == "Mesh":
                d = obj.read()
                with open(target("Mesh", d.m_Name, cont, obj.path_id, ".obj"), "w", encoding="utf-8") as f:
                    f.write(d.export())
            elif t in ("MonoBehaviour", "MonoScript", "AnimationClip", "Material",
                       "Shader", "GameObject", "AnimatorController", "PlayableDirector"):
                if t == "Shader":
                    continue  # compiled blobs, not useful as JSON
                tree = dump_tree(obj)
                name = tree.get("m_Name") or ""
                if t == "MonoBehaviour" and not name:
                    try:
                        name = obj.read().m_Script.read().m_ClassName + f"_{obj.path_id}"
                    except Exception:
                        name = f"mb_{obj.path_id}"
                with open(target(t, name, cont, obj.path_id, ".json"), "w", encoding="utf-8") as f:
                    json.dump(tree, f, ensure_ascii=False, indent=1, default=lambda o: repr(o))
            else:
                continue
            stats[t] += 1
        except Exception as e:
            errors.append(f"[{label}] {t} {key}: {type(e).__name__}: {e}")


def main():
    os.makedirs(OUT, exist_ok=True)
    top = [os.path.join(DATA, f) for f in os.listdir(DATA)
           if f.startswith(("level", "sharedassets", "resources", "globalgamemanagers"))]
    print("loading main data files...")
    process(UnityPy.load(*top), "main")
    print(dict(stats))
    bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
    bundles = sorted(os.listdir(bdir))
    for i, b in enumerate(bundles):
        if i % 50 == 0:
            print(f"bundle {i}/{len(bundles)}", flush=True)
        try:
            process(UnityPy.load(os.path.join(bdir, b)), b)
        except Exception as e:
            errors.append(f"[{b}] load: {e}")
    with open(os.path.join(OUT, "_extract_report.json"), "w", encoding="utf-8") as f:
        json.dump({"counts": dict(stats), "errors": errors}, f, ensure_ascii=False, indent=1)
    print("done", dict(stats), "errors:", len(errors))


main()

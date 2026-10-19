"""Resolve SoundMaster clip references (PPtr) to AudioClip names -> data/sounds.lua.

usage: python -I resolve_sound_master.py <Game_Data dir> <out needy3ds dir>
"""
import os
import sys

import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

DATA, OUT = sys.argv[1], sys.argv[2]
gen = None


def tree_of(obj):
    global gen
    try:
        return obj.read_typetree()
    except Exception:
        pass
    if gen is None:
        gen = TypeTreeGenerator(obj.assets_file.unity_version)
        gen.load_local_game(os.path.dirname(DATA))
    script = obj.read(check_read=False).m_Script.read()
    if script.m_ClassName != "SoundMaster":
        return {}
    full = f"{script.m_Namespace}.{script.m_ClassName}" if script.m_Namespace else script.m_ClassName
    return obj.read_typetree(gen.get_nodes_up(script.m_AssemblyName, full), check_read=False)


top = [os.path.join(DATA, f) for f in os.listdir(DATA)
       if f.startswith(("level", "sharedassets", "resources", "globalgamemanagers"))]
bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
envs = [UnityPy.load(*top)] + [UnityPy.load(os.path.join(bdir, b)) for b in os.listdir(bdir) if b.startswith("defaultlocalgroup")]
rows = {}
for env, obj in ((e, o) for e in envs for o in e.objects):
    if obj.type.name != "MonoBehaviour":
        continue
    try:
        if obj.read(check_read=False).m_Script.read().m_ClassName != "SoundMaster":
            continue
        tree = tree_of(obj)
    except Exception:
        continue
    if "SoundList" not in tree:
        continue
    for row in tree["SoundList"]:
        clip = row.get("Clip") or {}
        name = None
        try:
            if clip.get("m_PathID"):
                ref = obj.assets_file
                fid = clip["m_FileID"]
                if fid:
                    ext = obj.assets_file.externals[fid - 1].name.lower()
                    ref = next(f for n, f in env.files.items() if os.path.basename(n).lower() == os.path.basename(ext))
                name = ref.objects[clip["m_PathID"]].read().m_Name
        except Exception as e:
            name = None
        rows[row["Id"]] = (name, row.get("Category"), row.get("Music") or "")
os.makedirs(os.path.join(OUT, "data"), exist_ok=True)
with open(os.path.join(OUT, "data", "sounds.lua"), "w", encoding="utf-8") as f:
    f.write("-- SoundType -> {clip, category}\nreturn {\n")
    for k, (n, cat, music) in sorted(rows.items()):
        f.write(f'["{k}"]={{"{n or ""}","{cat or ""}"}},\n')
    f.write("}\n")
print(len(rows), "sounds;", sum(1 for v in rows.values() if v[0]), "resolved")

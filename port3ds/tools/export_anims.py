"""Exports sprite animations with their real timing from Unity AnimationClips (muscle clip
streamed/dense/constant curves bound to Image.m_Sprite / SpriteRenderer.m_Sprite), plus Animator
controller states and transitions -> data/anims.lua

usage: python -I export_anims.py <Game_Data dir> <out needy3ds dir>
"""
import os
import re
import struct
import sys

import UnityPy

DATA, OUT = sys.argv[1], sys.argv[2]
SUFFIX_RE = re.compile(r"_-?\d{6,}$")


def floats_from_uints(arr):
    return struct.unpack(f"<{len(arr)}f", struct.pack(f"<{len(arr)}I", *arr))


def streamed_frames(data_uints):
    """Unity StreamedClip: [time f32][numKeys i32]{[index i32][coeff f32 x4]}*"""
    raw = struct.pack(f"<{len(data_uints)}I", *data_uints)
    pos, frames = 0, []
    while pos + 8 <= len(raw):
        t, n = struct.unpack_from("<fi", raw, pos)
        pos += 8
        keys = []
        for _ in range(n):
            idx, a, b, c, d = struct.unpack_from("<i4f", raw, pos)
            pos += 20
            keys.append((idx, d))
        frames.append((t, keys))
    return frames


def binding_curve_count(b):
    tid, attr = b["typeID"], b["attribute"]
    if tid == 4:  # Transform: position/scale 3, rotation 4 (quaternion) or 3 (euler)
        return 4 if attr == 2 else 3
    return 1


def export_clip(clip_obj, tt):
    mc = tt["m_MuscleClip"]
    clip = mc["m_Clip"]["data"]
    bindings = tt["m_ClipBindingConstant"]["genericBindings"]
    mapping = tt["m_ClipBindingConstant"]["pptrCurveMapping"]
    # curve index -> binding
    cur, curve_bind = 0, {}
    for b in bindings:
        n = binding_curve_count(b)
        for k in range(n):
            curve_bind[cur + k] = b
        cur += n
    names = []
    af = clip_obj.assets_file
    for p in mapping:
        name = None
        try:
            if p["m_PathID"]:
                ref = af
                if p["m_FileID"]:
                    ref = af.externals[p["m_FileID"] - 1]
                    ref = clip_obj.assets_file.environment.get_cab(ref.name) if hasattr(clip_obj.assets_file, "environment") else None
                obj = (ref or af).objects[p["m_PathID"]]
                name = obj.read().m_Name
        except Exception:
            name = None
        names.append(SUFFIX_RE.sub("", name) if name else None)

    def is_sprite(b):
        return b.get("isPPtrCurve", 0) and b["customType"] in (0, 23) or (b.get("isPPtrCurve") and b["typeID"] in (212, 114))

    keys = []  # (time, sprite)
    streamed = clip["m_StreamedClip"]
    nstream = streamed["curveCount"]
    for t, ks in streamed_frames(streamed["data"]):
        for idx, val in ks:
            b = curve_bind.get(idx)
            if b and b.get("isPPtrCurve"):
                i = int(round(val))
                if 0 <= i < len(names):
                    keys.append((max(0.0, t), names[i]))
    dense = clip["m_DenseClip"]
    if dense["m_CurveCount"]:
        arr = dense["m_SampleArray"]
        for f in range(dense["m_FrameCount"]):
            t = dense["m_BeginTime"] + f / dense["m_SampleRate"]
            for ci in range(dense["m_CurveCount"]):
                b = curve_bind.get(nstream + ci)
                if b and b.get("isPPtrCurve"):
                    i = int(round(arr[f * dense["m_CurveCount"] + ci]))
                    if 0 <= i < len(names):
                        keys.append((t, names[i]))
    const = clip["m_ConstantClip"]["data"]
    base = nstream + dense["m_CurveCount"]
    for ci, val in enumerate(const):
        b = curve_bind.get(base + ci)
        if b and b.get("isPPtrCurve"):
            i = int(round(val))
            if 0 <= i < len(names):
                keys.append((0.0, names[i]))
    keys.sort()
    dedup = []
    for t, n in keys:
        if n and (not dedup or dedup[-1][1] != n or abs(dedup[-1][0] - t) > 1e-4):
            if dedup and abs(dedup[-1][0] - t) < 1e-4:
                dedup[-1] = (t, n)
            else:
                dedup.append((round(t, 4), n))
    length = round(mc["m_StopTime"] - mc["m_StartTime"], 4)
    return {"len": length, "loop": bool(mc.get("m_LoopTime")), "keys": dedup}


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    files = [os.path.join(DATA, f) for f in os.listdir(DATA) if f.startswith(("level", "sharedassets", "resources"))]
    bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
    files += [os.path.join(bdir, b) for b in os.listdir(bdir) if not b.startswith("picturetextures")]
    env = UnityPy.load(*files)
    clips, controllers = {}, {}
    for obj in env.objects:
        t = obj.type.name
        try:
            if t == "AnimationClip":
                tt = obj.read_typetree()
                name = tt["m_Name"]
                c = export_clip(obj, tt)
                if c["keys"] and (name not in clips or len(c["keys"]) > len(clips[name]["keys"])):
                    clips[name] = c
            elif t == "AnimatorController":
                tt = obj.read_typetree()
                tos = {int(k): v for k, v in tt["m_TOS"]}
                ac = tt["m_Controller"]
                # clip names repeat across controllers ("in", "idle"...): each controller gets its own
                # copy as "<controller>/<clip>" when the plain name belongs to another clip
                clipnames = []
                for p in tt["m_AnimationClips"]:
                    try:
                        cobj = obj.assets_file.objects[p["m_PathID"]] if p["m_PathID"] else None
                        if cobj is None:
                            clipnames.append(None)
                            continue
                        ctt = cobj.read_typetree()
                        cname = ctt["m_Name"]
                        cc = export_clip(cobj, ctt)
                        if cc["keys"]:
                            key = tt["m_Name"] + "/" + cname
                            clips[key] = cc
                            clipnames.append(key)
                        else:
                            clipnames.append(cname)
                    except Exception:
                        clipnames.append(None)
                states = {}
                for sm in ac["m_StateMachineArray"]:
                    st_list = sm["data"]["m_StateConstantArray"]
                    st_names = [tos.get(s["data"]["m_NameID"], str(s["data"]["m_NameID"])) for s in st_list]
                    for si, s in enumerate(st_list):
                        sd = s["data"]
                        clip = None
                        try:
                            node = sd["m_BlendTreeConstantArray"][0]["data"]["m_NodeArray"][0]["data"]
                            cid = node["m_ClipID"]
                            clip = clipnames[cid] if 0 <= cid < len(clipnames) else None
                        except Exception:
                            pass
                        nxt = None
                        for tr in sd["m_TransitionConstantArray"]:
                            td = tr["data"]
                            dst = td["m_DestinationState"]
                            if td.get("m_HasExitTime") and 0 <= dst < len(st_names):
                                nxt = st_names[dst]
                                break
                        states[st_names[si]] = {"clip": clip, "next": nxt, "speed": sd.get("m_Speed", 1.0)}
                controllers[tt["m_Name"]] = {"default": None, "states": states}
        except Exception as e:
            print("skip", t, e)
    os.makedirs(os.path.join(OUT, "data"), exist_ok=True)
    with open(os.path.join(OUT, "data", "anims.lua"), "w", encoding="utf-8") as f:
        f.write("-- clip -> {len, loop, keys={{time, sprite}...}}; controller -> states\nreturn {\nclips = {\n")
        for name, c in sorted(clips.items()):
            ks = ",".join("{%s,%s}" % (k[0], lua_str(k[1])) for k in c["keys"])
            f.write(f"[{lua_str(name)}]={{len={c['len']},loop={'true' if c['loop'] else 'false'},keys={{{ks}}}}},\n")
        f.write("},\ncontrollers = {\n")
        for name, ctl in sorted(controllers.items()):
            f.write(f"[{lua_str(name)}]={{\n")
            for sn, s in sorted(ctl["states"].items()):
                f.write(f"  [{lua_str(sn)}]={{clip={lua_str(s['clip']) if s['clip'] else 'nil'},next={lua_str(s['next']) if s['next'] else 'nil'},speed={s['speed']}}},\n")
            f.write("},\n")
        f.write("}}\n")
    print(len(clips), "clips with sprite keys;", len(controllers), "controllers")


main()

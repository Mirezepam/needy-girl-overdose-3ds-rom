"""Exports the stream-opening bank animation (BankAnimation*) as ETV1 videos.

The clips share sprite names (bank_000...) across their language / dark variants, so the regular
anim export mixes them up; here every clip's own sprites are resolved by PathID. As sprite
sequences they took 31 atlas pages (62 MB streamed from the SD while playing); as ETC1 video they
are a few MB and decode for free.
usage: python export_bank.py "<game>/Windose_Data" build_data/needy3ds
"""
import os
import struct
import sys

import numpy as np
import UnityPy
from PIL import Image

DATA, OUT = sys.argv[1], sys.argv[2]


# (same as export_anims.py / build_assets.py, which run their pipeline on import)
def binding_curve_count(b):
    tid, attr = b["typeID"], b["attribute"]
    if tid == 4:
        return 4 if attr == 2 else 3
    return 1


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


def etc1_encode(rgb_img):
    """PIL RGB image (w,h multiple of 8) -> 3DS ETC1 bytes (tiled blocks, little-endian)."""
    import etcpak
    w, h = rgb_img.size
    arr = np.asarray(rgb_img.convert("RGBA"))
    raw = etcpak.compress_etc1_rgb(arr.tobytes(), w, h)
    blocks = np.frombuffer(raw, np.uint8).reshape(h // 4, w // 4, 8)
    t = blocks.reshape(h // 8, 2, w // 8, 2, 8).transpose(0, 2, 1, 3, 4)
    return np.ascontiguousarray(t[..., ::-1]).tobytes()


def pow2(n):
    p = 8
    while p < n:
        p *= 2
    return p
CLIPS = {"BankAnimation": "bank_jp", "BankAnimation_B": "bank_jp_b",
         "BankAnimation_Eng": "bank_eng", "BankAnimation_Eng_B": "bank_eng_b"}
FPS = 12
W, H = 320, 240  # 4:3 art fitted to the 400x240 top screen


def sprite_keys(obj, tt):
    """[(time, Sprite object)] of the clip's sprite curve"""
    mc = tt["m_MuscleClip"]
    clip = mc["m_Clip"]["data"]
    bindings = tt["m_ClipBindingConstant"]["genericBindings"]
    mapping = tt["m_ClipBindingConstant"]["pptrCurveMapping"]
    cur, curve_bind = 0, {}
    for b in bindings:
        for k in range(binding_curve_count(b)):
            curve_bind[cur + k] = b
        cur += binding_curve_count(b)
    af = obj.assets_file
    sprites = []
    for p in mapping:
        ref = af
        if p["m_FileID"]:
            ext = af.externals[p["m_FileID"] - 1].name
            ref = next((f for f in af.environment.files.values()
                        if hasattr(f, "objects") and os.path.basename(getattr(f, "name", "")) == ext), None)
            if ref is None:
                ref = next((f for f in af.environment.cabs.values() if getattr(f, "name", "") == ext), af)
        sprites.append(ref.objects.get(p["m_PathID"]) if hasattr(ref, "objects") else None)
    keys = []
    for t, ks in streamed_frames(clip["m_StreamedClip"]["data"]):
        for idx, val in ks:
            b = curve_bind.get(idx)
            if b and b.get("isPPtrCurve"):
                i = int(round(val))
                if 0 <= i < len(sprites) and sprites[i] is not None:
                    keys.append((max(0.0, t), sprites[i]))
    keys.sort(key=lambda k: k[0])
    return keys, mc["m_StopTime"] - mc["m_StartTime"]


def write_etv(path, frames):
    import lz4.block
    tw, th = pow2(W), pow2(H)
    blobs = []
    for fr in frames:
        canvas = Image.new("RGB", (tw, th), (255, 255, 255))
        canvas.paste(fr, (0, 0))
        blobs.append(lz4.block.compress(etc1_encode(canvas), store_size=False))
    n = len(blobs)
    with open(path, "wb") as f:
        f.write(b"ETV1" + struct.pack("<HHHHHHI", W, H, tw, th, FPS,
                                      len(etc1_encode(Image.new("RGB", (tw, th)))) // 1024, n))
        offs, o = [], 0
        for b in blobs:
            offs.append(o)
            o += len(b)
        offs.append(o)
        f.write(struct.pack(f"<{n + 1}I", *offs))
        for b in blobs:
            f.write(b)


def main():
    files = [os.path.join(DATA, f) for f in os.listdir(DATA) if f.startswith(("level", "sharedassets", "resources"))]
    bdir = os.path.join(DATA, "StreamingAssets", "aa", "StandaloneWindows64")
    files += [os.path.join(bdir, b) for b in os.listdir(bdir) if not b.startswith("picturetextures")]
    env = UnityPy.load(*files)
    os.makedirs(os.path.join(OUT, "vid"), exist_ok=True)
    done = set()
    for obj in env.objects:
        if obj.type.name != "AnimationClip":
            continue
        tt = obj.read_typetree()
        name = tt["m_Name"]
        if name not in CLIPS or name in done:
            continue
        keys, length = sprite_keys(obj, tt)
        if len(keys) < 10:
            continue
        cache, frames = {}, []
        n = int(round(length * FPS))
        k = 0
        for i in range(n):
            t = i / FPS
            while k + 1 < len(keys) and keys[k + 1][0] <= t + 1e-4:
                k += 1
            spr = keys[k][1]
            if spr.path_id not in cache:
                img = spr.read().image.convert("RGBA")
                bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
                bg.alpha_composite(img)
                cache[spr.path_id] = bg.convert("RGB").resize((W, H), Image.LANCZOS)
            frames.append(cache[spr.path_id])
        dst = os.path.join(OUT, "vid", CLIPS[name] + ".etv")
        write_etv(dst, frames)
        done.add(name)
        print(f"  {name} -> {os.path.basename(dst)}: {len(frames)} frames, "
              f"{len(cache)} sprites, {os.path.getsize(dst) / 2**20:.1f} MB", flush=True)
    missing = set(CLIPS) - done
    if missing:
        print("  missing clips:", ", ".join(sorted(missing)))


if __name__ == "__main__":
    main()

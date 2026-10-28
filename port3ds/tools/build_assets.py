"""Convert the extracted NEEDY GIRL OVERDOSE assets into the 3DS data folder.

Reads only the user's own extraction (assets/ from extract_assets.py) and writes
<out>/needy3ds/, which is copied to the SD card as sdmc:/3ds/needy3ds/.

usage: python -I build_assets.py <assets dir> <out dir> [gfx|text|font|audio|video|lua|all ...]
"""
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

ASSETS, OUT = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
STEPS = set(sys.argv[3:] or ["all"])
ROOT = os.path.join(OUT, "needy3ds")
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = os.path.dirname(HERE)

TOP_W, TOP_H = 400, 240
PAGE = 1024
LANGS = {"es": ("Sp",), "en": ("En", "EN"), "ja": ("Jp", "JP")}
LANG_SUFFIXES = ("Jp", "JP", "En", "EN", "Cn", "Ch", "Ko", "Tw", "Vn", "VN", "Fr", "It", "Ge", "Sp", "Ru")

# GPU_TEXCOLOR values (citro3d)
FMT_RGBA8, FMT_RGB565, FMT_RGBA5551, FMT_RGBA4, FMT_A8, FMT_ETC1 = 0, 3, 2, 4, 8, 12


def step(name):
    return "all" in STEPS or name in STEPS


def mkdir(*p):
    d = os.path.join(ROOT, *p)
    os.makedirs(d, exist_ok=True)
    return d


def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    return f'"{s}"'


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_val(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(f"[{lua_str(str(k))}]={lua_val(x)}" for k, x in v.items()) + "}"
    return "nil"


# ------------------------------------------------------------------ GPU texture encoding

def _morton_index(w, h):
    """Map from (flipped) linear pixel order to 3DS tiled order: 8x8 tiles, Z-order inside."""
    ys, xs = np.mgrid[0:h, 0:w]
    tile = (ys // 8) * (w // 8) + (xs // 8)
    x, y = xs & 7, ys & 7
    z = (x & 1) | ((y & 1) << 1) | ((x & 2) << 1) | ((y & 2) << 2) | ((x & 4) << 2) | ((y & 4) << 3)
    return (tile * 64 + z).ravel()


_MORTON = {}


def tile_pixels(arr):
    """arr: (h, w, c) in image row order. Returns array in GPU (tiled) order."""
    h, w = arr.shape[:2]
    if (w, h) not in _MORTON:
        _MORTON[(w, h)] = _morton_index(w, h)
    out = np.empty((h * w,) + arr.shape[2:], arr.dtype)
    out[_MORTON[(w, h)]] = arr.reshape((h * w,) + arr.shape[2:])
    return out


def encode_pixels(rgba, fmt):
    """rgba: (h, w, 4) uint8 top-down. Returns GPU-ready bytes."""
    # the 3DS GPU samples memory row 0 at t=1 (top), so rows stay in image order
    a = np.ascontiguousarray(rgba).astype(np.uint16)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    if fmt == FMT_RGBA8:
        px = np.stack([al, b, g, r], -1).astype(np.uint8)  # ABGR in memory
    elif fmt == FMT_RGBA5551:
        px = ((r >> 3) << 11) | ((g >> 3) << 6) | ((b >> 3) << 1) | (al >> 7)
    elif fmt == FMT_RGB565:
        px = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    elif fmt == FMT_RGBA4:
        px = ((r >> 4) << 12) | ((g >> 4) << 8) | ((b >> 4) << 4) | (al >> 4)
    elif fmt == FMT_A8:
        px = al.astype(np.uint8)
    else:
        raise ValueError(fmt)
    return tile_pixels(px).astype(px.dtype).tobytes()


def write_ntx(path, rgba, fmt):
    h, w = rgba.shape[:2]
    data = encode_pixels(rgba, fmt)
    with open(path, "wb") as f:
        f.write(b"NTX1" + struct.pack("<HHBxxxI", w, h, fmt, len(data)))
        f.write(data)


def etc1_encode(rgb_img):
    """PIL RGB image (w,h multiple of 8) -> 3DS ETC1 bytes (tiled blocks, little-endian)."""
    import etcpak
    w, h = rgb_img.size
    arr = np.asarray(rgb_img.convert("RGBA"))
    raw = etcpak.compress_etc1_rgb(arr.tobytes(), w, h)
    blocks = np.frombuffer(raw, np.uint8).reshape(h // 4, w // 4, 8)
    # 8x8 tile = 2x2 blocks in Z order; each 64-bit block byte-reversed
    t = blocks.reshape(h // 8, 2, w // 8, 2, 8).transpose(0, 2, 1, 3, 4)
    return np.ascontiguousarray(t[..., ::-1]).tobytes()


def pow2(n):
    p = 8
    while p < n:
        p *= 2
    return p


# ------------------------------------------------------------------ sprites -> atlases

# Unity duplicate suffixes ("_-6290023870359517497"); photo names keep their time (IMG_20190505_182017)
SUFFIX_RE = re.compile(r"(?<!IMG_\d{8})_-?\d{6,}$")
SEQ_RE = re.compile(r"^(.*?)_?(\d{2,4})$")


class Skyline:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.sky = [(0, 0, w)]  # x, y, width

    def insert(self, rw, rh):
        best = None
        for i, (x, _, _) in enumerate(self.sky):
            if x + rw > self.w:
                break
            y, need, j = 0, rw, i
            while need > 0:
                y = max(y, self.sky[j][1])
                need -= self.sky[j][2]
                j += 1
                if j >= len(self.sky) and need > 0:
                    y = self.h + 1
                    break
            if y + rh <= self.h and (best is None or y + rh < best[1] + rh or (y + rh == best[1] + rh and x < best[0])):
                best = (x, y, i)
        if best is None:
            return None
        x, y, i = best
        new = [(x, y + rh, rw)]
        end = x + rw
        rest = []
        for sx, sy, sw in self.sky[i:]:
            if sx + sw <= end:
                continue
            if sx < end:
                rest.append((end, sy, sx + sw - end))
            else:
                rest.append((sx, sy, sw))
        self.sky = self.sky[:i] + new + rest
        return x, y


def collect_sprites():
    files = {}
    for kind in ("Sprite", "Texture2D", "Texture2D_retry"):
        for p in glob.glob(os.path.join(ASSETS, kind, "**", "*.png"), recursive=True):
            name = SUFFIX_RE.sub("", os.path.splitext(os.path.basename(p))[0])
            if name not in files:  # Sprite wins over Texture2D
                files[name] = p
    return files


def group_of(name, seq_counts):
    m = SEQ_RE.match(name)
    if m and seq_counts.get(m.group(1), 0) >= 2:
        return "seq_" + m.group(1)
    head = name.split("_")[0].lower() or "misc"
    return "g_" + re.sub(r"[^a-z0-9]", "", head)[:24]


_META = None


def sprite_meta(name):
    global _META
    if _META is None:
        p = os.path.join(HERE, ".sprite_meta.json")
        _META = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    return _META.get(name)


def load_sprite(path, name):
    """UI pieces keep their native pixels (drawn at 0.5 they match the original 2x pixel art);
    only full-screen backgrounds and photos are reduced to the 3DS screen size."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    meta = sprite_meta(name)
    border = list(meta["border"]) if meta and any(meta["border"]) else None
    if w > 640 or h > 480:
        s = min(TOP_W / w, TOP_H / h)
        im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.BOX)
        if border:
            border = [round(b * s) for b in border]
    full = im.size
    if border:
        # 9-slice sprites are kept untrimmed so the borders stay aligned
        return im, 0, 0, full, border
    bbox = im.getchannel("A").getbbox()
    if bbox is None:
        return None
    return im.crop(bbox), bbox[0], bbox[1], full, None


def build_gfx():
    out = mkdir("gfx")
    files = collect_sprites()
    seq_counts = defaultdict(int)
    for n in files:
        m = SEQ_RE.match(n)
        if m:
            seq_counts[m.group(1)] += 1
    groups = defaultdict(list)
    for n, p in files.items():
        groups[group_of(n, seq_counts)].append((n, p))
    index, pages_per_group = {}, {}
    total_bytes = 0
    for gi, (g, items) in enumerate(sorted(groups.items())):
        sprites = []
        for n, p in items:
            s = load_sprite(p, n)
            if s:
                sprites.append((n,) + s)
        sprites.sort(key=lambda s: (-s[1].size[1], -s[1].size[0]))
        pages = []
        for n, im, ox, oy, full, border in sprites:
            w, h = im.size[0] + 1, im.size[1] + 1  # 1px gutter against bleeding
            for pi, (pack, canvas, used) in enumerate(pages):
                pos = pack.insert(w, h)
                if pos:
                    break
            else:
                pack = Skyline(PAGE, PAGE)
                pages.append((pack, Image.new("RGBA", (PAGE, PAGE)), []))
                pi = len(pages) - 1
                pos = pack.insert(w, h)
            pack, canvas, used = pages[pi]
            canvas.paste(im, pos)
            used.append((pos[0] + w, pos[1] + h))
            index[n] = [g, pi, pos[0], pos[1], im.size[0], im.size[1], ox, oy, full[0], full[1]] + (border or [])
        for pi, (pack, canvas, used) in enumerate(pages):
            cw = pow2(max(u[0] for u in used))
            ch = pow2(max(u[1] for u in used))
            canvas = canvas.crop((0, 0, cw, ch))
            arr = np.asarray(canvas)
            alpha = arr[..., 3]
            if alpha.min() == 255:
                fmt = FMT_RGB565
            elif np.isin(alpha, (0, 255)).all():
                fmt = FMT_RGBA5551
            else:
                fmt = FMT_RGBA4 if cw * ch > 512 * 512 else FMT_RGBA8
            write_ntx(os.path.join(out, f"{g}_{pi}.ntx"), arr, fmt)
            total_bytes += cw * ch * (4 if fmt == FMT_RGBA8 else 2)
        pages_per_group[g] = (len(pages), [(pow2(max(u[0] for u in pg[2])), pow2(max(u[1] for u in pg[2]))) for pg in pages])
        if gi % 50 == 0:
            print(f"  gfx group {gi}/{len(groups)}", flush=True)
    with open(os.path.join(out, "index.lua"), "w", encoding="utf-8") as f:
        f.write("-- sprite -> {group, page, x, y, w, h, offx, offy, fullw, fullh[, border l, b, r, t]}\nreturn {\nsprites = {\n")
        for n in sorted(index):
            f.write(f"[{lua_str(n)}]={lua_val(index[n])},\n")
        f.write("},\ngroups = {\n")
        for g, (n, sizes) in sorted(pages_per_group.items()):
            f.write(f"[{lua_str(g)}]={{pages={n},sizes={lua_val([list(s) for s in sizes])}}},\n")
        f.write("}}\n")
    print(f"gfx: {len(index)} sprites, {len(pages_per_group)} groups, {total_bytes / 2**20:.1f} MB of textures")


# ------------------------------------------------------------------ texts

def build_text():
    mb = os.path.join(ASSETS, "MonoBehaviour")
    texts = {lang: defaultdict(lambda: defaultdict(dict)) for lang in LANGS}
    data = {}
    used_chars = {lang: set() for lang in LANGS}
    for p in sorted(glob.glob(os.path.join(mb, "*.json"))):
        name = os.path.splitext(os.path.basename(p))[0]
        if os.path.getsize(p) < 2000 and name not in ("statuses",):
            continue
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        for key, rows in d.items():
            if not (isinstance(rows, list) and rows and isinstance(rows[0], dict)):
                continue
            multilingual = any(k.endswith(LANG_SUFFIXES) for k in rows[0])
            if not multilingual and name not in ("SoundMaster", "statuses", "ResourceLocalMaster", "PlatformDiffAnimationMaster"):
                continue
            table = f"{name}" if key in ("param", "StatusList") else f"{name}.{key}"
            plain_rows = []
            for row in rows:
                rid = str(row.get("Id", row.get("StatusType", len(plain_rows))))
                plain = {}
                by_base = defaultdict(dict)
                for k, v in row.items():
                    suf = next((s for s in LANG_SUFFIXES if k.endswith(s) and len(k) > len(s) and k[-len(s) - 1].islower()), None)
                    if suf and isinstance(v, str):
                        by_base[k[: -len(suf)]][suf] = v
                    elif isinstance(v, (str, int, float, bool)):
                        plain[k] = v
                for base, variants in by_base.items():
                    for lang, sufs in LANGS.items():
                        txt = next((variants[s] for s in sufs if variants.get(s)), None)
                        if txt is None:
                            txt = variants.get("En") or variants.get("EN") or next(iter(variants.values()))
                        texts[lang][table][base][rid] = txt
                        used_chars[lang].update(txt)
                plain_rows.append(plain)
            data[table] = plain_rows
    # translation slips in the original tables (e.g. the Spanish WristGO is the French "VAS-Y !")
    TEXT_FIXES = {"es": {"WristGO": "¡VAMOS!"}}
    for lang, fixes in TEXT_FIXES.items():
        for fields in texts[lang].values():
            for rows in fields.values():
                for rid, txt in fixes.items():
                    if rid in rows:
                        rows[rid] = txt
    out = mkdir("text")
    for lang, tables in texts.items():
        with open(os.path.join(out, f"{lang}.lua"), "w", encoding="utf-8") as f:
            f.write("return {\n")
            for t, fields in sorted(tables.items()):
                f.write(f"[{lua_str(t)}]={{\n")
                for field, rows in sorted(fields.items()):
                    f.write(f"  [{lua_str(field)}]={{\n")
                    for rid, txt in rows.items():
                        f.write(f"    [{lua_str(rid)}]={lua_str(txt)},\n")
                    f.write("  },\n")
                f.write("},\n")
            f.write("}\n")
    with open(os.path.join(mkdir("data"), "masters.lua"), "w", encoding="utf-8") as f:
        f.write("return {\n")
        for t, rows in sorted(data.items()):
            f.write(f"[{lua_str(t)}]={{\n")
            for r in rows:
                f.write("  " + lua_val(r) + ",\n")
            f.write("},\n")
        f.write("}\n")
    with open(os.path.join(HERE, ".chars.json"), "w", encoding="utf-8") as f:
        json.dump({k: "".join(sorted(v)) for k, v in used_chars.items()}, f, ensure_ascii=False)
    print("text:", {lang: sum(len(r) for fl in t.values() for r in fl.values()) for lang, t in texts.items()}, "entries")


# ------------------------------------------------------------------ font

def build_font():
    from fontTools.ttLib import TTFont
    from PIL import ImageDraw, ImageFont

    chars_file = os.path.join(HERE, ".chars.json")
    if not os.path.exists(chars_file):
        build_text()
    chars = set("".join(json.load(open(chars_file, encoding="utf-8")).values()))
    chars |= set(chr(c) for c in range(32, 127)) | set("áéíóúüñÁÉÍÓÚÜÑ¿¡…「」『』、。・♥♡★☆→←↑↓○×◀▶◆■▼↻")
    # every character the port's own UI code writes (labels, buttons like "◀", port-only strings)
    for sub in ("ui", "override", "runtime"):
        for root, _, files in os.walk(os.path.join(HERE, "..", "lua", sub)):
            for fn in files:
                if fn.endswith(".lua"):
                    chars |= set(open(os.path.join(root, fn), encoding="utf-8", errors="ignore").read())
    fonts_dir = os.path.join(ASSETS, "Font")
    chain = [("PixelMplus10-Regular.ttf", 10), ("DinkieBitmap-9px.ttf", 9), ("zpix.ttf", 12)]
    SS = 10
    loaded = []
    for fn, size in chain:
        path = os.path.join(fonts_dir, fn)
        if os.path.exists(path):
            cmap = TTFont(path, fontNumber=0, lazy=True).getBestCmap()
            # rendered 10x and sampled at pixel centres: FreeType's mono hinting breaks pixel fonts
            loaded.append(((ImageFont.truetype(path, size * SS), size), set(cmap)))
    cell = 16   # room for accents above and descenders below (PixelMplus10 overflows 12 px)
    glyphs = []
    for ch in sorted(chars, key=ord):
        cp = ord(ch)
        if cp < 32 or ch in "\r\n\t":
            continue
        font = next((f for f, cm in loaded if cp in cm), None)
        if font is None:
            continue
        glyphs.append((cp, ch, font))
    cols = PAGE // cell
    rows = (len(glyphs) + cols - 1) // cols
    atlas_h = pow2(rows * cell)
    atlas = Image.new("L", (PAGE, atlas_h), 0)
    table = []
    big = Image.new("L", (cell * SS, cell * SS), 0)
    bdraw = ImageDraw.Draw(big)
    centres = np.arange(cell) * SS + SS // 2
    for i, (cp, ch, (font, size)) in enumerate(glyphs):
        x, y = (i % cols) * cell, (i // cols) * cell
        bdraw.rectangle((0, 0, cell * SS, cell * SS), fill=0)
        ascent = font.getmetrics()[0] / SS
        baseline = 2 + round(ascent)
        bdraw.text((0, baseline * SS), ch, font=font, fill=255, anchor="ls")
        arr = np.asarray(big)[np.ix_(centres, centres)]
        atlas.paste(Image.fromarray(np.where(arr > 127, 255, 0).astype(np.uint8)), (x, y))
        adv = max(1, round(font.getlength(ch) / SS))
        table.append((cp, x, y, min(adv, cell), adv))
    rgba = np.zeros((atlas_h, PAGE, 4), np.uint8)
    rgba[..., 3] = np.asarray(atlas)
    rgba[..., :3] = 255
    out = mkdir("font")
    write_ntx(os.path.join(out, "main.ntx"), rgba, FMT_RGBA4)
    with open(os.path.join(out, "main.bin"), "wb") as f:
        f.write(b"NFN1" + struct.pack("<HHI", cell, cell, len(table)))
        for cp, x, y, w, adv in table:
            f.write(struct.pack("<IHHBB", cp, x, y, w, adv))
    print(f"font: {len(table)} glyphs, atlas {PAGE}x{atlas_h}")


# ------------------------------------------------------------------ audio

def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def build_audio():
    import soundfile as sf
    out = mkdir("snd")
    bgm_names = set()
    sm = os.path.join(ASSETS, "MonoBehaviour", "SoundMaster.json")
    if os.path.exists(sm):
        for row in json.load(open(sm, encoding="utf-8")).get("SoundList", []):
            if "BGM" in str(row.get("Id", "")) or row.get("Category") in (1, "BGM"):
                bgm_names.add(str(row.get("Id")))
    n_bgm = n_se = 0
    for p in sorted(glob.glob(os.path.join(ASSETS, "AudioClip", "*.wav"))):
        name = SUFFIX_RE.sub("", os.path.splitext(os.path.basename(p))[0])
        dur = sf.info(p).duration
        if dur > 12:
            dst = os.path.join(out, name + ".ogg")
            if not os.path.exists(dst):
                subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-i", p, "-ar", "32000", "-ac", "2",
                                "-c:a", "libvorbis", "-q:a", "2", dst], check=True)
            n_bgm += 1
        else:
            dst = os.path.join(out, name + ".pcm")
            if not os.path.exists(dst):
                raw = subprocess.run([ffmpeg(), "-loglevel", "error", "-i", p, "-ar", "22050", "-ac", "1",
                                      "-f", "s16le", "-"], check=True, capture_output=True).stdout
                with open(dst, "wb") as f:
                    f.write(b"PCM1" + struct.pack("<IHHI", 22050, 1, 16, len(raw) // 2))
                    f.write(raw)
            n_se += 1
    print(f"audio: {n_bgm} streamed (ogg), {n_se} effects (pcm)")


# ------------------------------------------------------------------ video

def build_video(fps=12):
    import lz4.block
    out = mkdir("vid")
    for p in sorted(glob.glob(os.path.join(ASSETS, "VideoClip", "*"))):
        name = os.path.splitext(os.path.basename(p))[0]
        dst = os.path.join(out, name + ".etv")
        if os.path.exists(dst):
            continue
        probe = subprocess.run([ffmpeg(), "-i", p], capture_output=True, text=True).stderr
        m = re.search(r"Video: .*?, (\d+)x(\d+)", probe)
        sw, sh = int(m.group(1)), int(m.group(2))
        s = min(TOP_W / sw, TOP_H / sh, 1.0)
        w, h = int(sw * s) // 2 * 2, int(sh * s) // 2 * 2
        tw, th = pow2(w), pow2(h)
        raw = subprocess.run([ffmpeg(), "-loglevel", "error", "-i", p, "-vf", f"fps={fps},scale={w}:{h}:flags=area",
                              "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], check=True, capture_output=True).stdout
        n = len(raw) // (w * h * 3)
        frames = []
        for i in range(n):
            fr = Image.frombuffer("RGB", (w, h), raw[i * w * h * 3:(i + 1) * w * h * 3])
            canvas = Image.new("RGB", (tw, th))
            canvas.paste(fr, (0, 0))
            frames.append(lz4.block.compress(etc1_encode(canvas), store_size=False))
        with open(dst, "wb") as f:
            f.write(b"ETV1" + struct.pack("<HHHHHHI", w, h, tw, th, fps, len(etc1_encode(Image.new("RGB", (tw, th)))) // 1024, n))
            offs, o = [], 0
            for fr in frames:
                offs.append(o)
                o += len(fr)
            offs.append(o)
            f.write(struct.pack(f"<{n + 1}I", *offs))
            for fr in frames:
                f.write(fr)
        subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-i", p, "-vn", "-ar", "32000", "-ac", "2",
                        "-c:a", "libvorbis", "-q:a", "2", os.path.join(out, name + ".ogg")], check=False)
        print(f"  video {name}: {n} frames {w}x{h} -> {os.path.getsize(dst) / 2**20:.1f} MB", flush=True)


# ------------------------------------------------------------------ scriptable objects

def build_so():
    """ScriptableObjects (MonoBehaviours without GameObject) -> data/so/<name>.lua for Resources.Load."""
    out = mkdir("data", "so")
    n = 0
    for p in glob.glob(os.path.join(ASSETS, "MonoBehaviour", "*.json")):
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        if d.get("m_GameObject", {}).get("m_PathID", 1) != 0 or not d.get("m_Name"):
            continue
        name = re.sub(r"[^A-Za-z0-9_]", "_", d["m_Name"])
        body = {k: v for k, v in d.items() if k not in ("m_GameObject", "m_Enabled", "m_Script", "m_Name")}
        with open(os.path.join(out, name + ".lua"), "w", encoding="utf-8") as f:
            f.write("return " + lua_val(body) + "\n")
        n += 1
    print("scriptable objects:", n)


# ------------------------------------------------------------------ lua

def build_lua():
    dst = os.path.join(ROOT, "lua")
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(os.path.join(PORT, "lua"), dst, ignore=shutil.ignore_patterns("*.md"))
    print("lua: copied")


if __name__ == "__main__":
    os.makedirs(ROOT, exist_ok=True)
    if step("text"):
        build_text()
    if step("font"):
        build_font()
    if step("lua"):
        build_lua()
    if step("so"):
        build_so()
    if step("gfx"):
        build_gfx()
    if step("audio"):
        build_audio()
    if step("video"):
        build_video()

"""Renders a draw-command snapshot recorded by pc_harness.lua into a PNG of both 3DS screens,
using the real NTX textures (3DS tiled formats decoded here).

usage: python -I render_snap.py <snapshot.json> <out.png> <needy3ds data dir>
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

SNAP, OUT, DATA = sys.argv[1:4]
_cache = {}


def morton_index(w, h):
    ys, xs = np.mgrid[0:h, 0:w]
    tile = (ys // 8) * (w // 8) + (xs // 8)
    x, y = xs & 7, ys & 7
    z = (x & 1) | ((y & 1) << 1) | ((x & 2) << 1) | ((y & 2) << 2) | ((x & 4) << 2) | ((y & 4) << 3)
    return (tile * 64 + z).ravel()


def load_ntx(path):
    if path in _cache:
        return _cache[path]
    d = open(path, "rb").read()
    w, h, fmt = struct.unpack("<HHB", d[4:9])
    raw = d[16:]
    idx = morton_index(w, h)
    if fmt == 0:      # RGBA8 stored ABGR
        px = np.frombuffer(raw, np.uint8).reshape(-1, 4)[idx]
        rgba = px[:, ::-1]
    elif fmt == 8:    # A8
        a = np.frombuffer(raw, np.uint8)[idx]
        rgba = np.stack([np.full_like(a, 255)] * 3 + [a], -1)
    else:
        v = np.frombuffer(raw, np.uint16)[idx].astype(np.uint32)
        if fmt == 2:   # RGBA5551
            r, g, b, a = (v >> 11) & 31, (v >> 6) & 31, (v >> 1) & 31, (v & 1) * 255
            r, g, b = r * 255 // 31, g * 255 // 31, b * 255 // 31
        elif fmt == 3:  # RGB565
            r, g, b = ((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31
            a = np.full_like(v, 255)
        else:           # RGBA4
            r, g, b, a = ((v >> 12) & 15) * 17, ((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17
        rgba = np.stack([r, g, b, a], -1).astype(np.uint8)
    img = rgba.reshape(h, w, 4).astype(np.float32) / 255.0
    _cache[path] = img
    return img


def unpack(c):
    return ((c >> 24) & 255) / 255, ((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255


def composite(canvas, src, x, y, clip):
    h, w = src.shape[:2]
    x0, y0 = int(round(x)), int(round(y))
    cx0, cy0, cx1, cy1 = clip
    ax0, ay0 = max(x0, cx0), max(y0, cy0)
    ax1, ay1 = min(x0 + w, cx1), min(y0 + h, cy1)
    if ax1 <= ax0 or ay1 <= ay0:
        return
    s = src[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
    d = canvas[ay0:ay1, ax0:ax1]
    a = s[..., 3:4]
    d[..., :3] = s[..., :3] * a + d[..., :3] * (1 - a)


def render_screen(cmds, width, textures):
    canvas = np.zeros((240, width, 4), np.float32)
    canvas[..., 3] = 1
    clip = (0, 0, width, 240)
    for c in cmds:
        k = c[0]
        if k == "rect":
            _, x, y, w, h, col = c
            r, g, b, a = unpack(int(col))
            if a <= 0:
                continue
            src = np.zeros((max(1, int(round(h))), max(1, int(round(w))), 4), np.float32)
            src[...] = (r, g, b, a)
            composite(canvas, src, x, y, clip)
        elif k == "clip":
            clip = (int(c[1]), int(c[2]), int(c[1] + c[3]), int(c[2] + c[4])) if len(c) > 1 else (0, 0, width, 240)
        elif k == "draw":
            _, tid, sx, sy, sw, sh, dx, dy, scx, scy, alpha, tint, blend = c[:13]
            path = textures.get(str(tid))
            if not path:
                continue
            tex = load_ntx(path)
            sub = tex[int(sy):int(sy + sh), int(sx):int(sx + sw)].copy()
            if sub.size == 0:
                continue
            flipx, flipy = scx < 0, scy < 0
            if flipx:
                sub = sub[:, ::-1]
                dx += sw * scx
            if flipy:
                sub = sub[::-1]
                dy += sh * scy
            nw, nh = max(1, int(round(sw * abs(scx)))), max(1, int(round(sh * abs(scy))))
            if (nw, nh) != (sub.shape[1], sub.shape[0]):
                im = Image.fromarray((np.ascontiguousarray(sub) * 255).astype(np.uint8), "RGBA").resize((nw, nh), Image.NEAREST)
                sub = np.asarray(im).astype(np.float32) / 255
            tr, tg, tb, ta = unpack(int(tint))
            if blend > 0:
                sub[..., :3] = sub[..., :3] * (1 - blend) + np.array([tr, tg, tb]) * blend
            sub[..., 3] *= alpha * (ta if blend > 0 else 1)
            composite(canvas, sub, dx, dy, clip)
    return canvas


def main():
    snap = json.load(open(SNAP, encoding="utf-8"))
    tex = {k: os.path.join(DATA, v) for k, v in snap["textures"].items()}
    top = render_screen(snap["top"], 400, tex)
    bot = render_screen(snap["bottom"], 320, tex)
    out = np.zeros((480, 400, 3), np.float32)
    out[:240] = top[..., :3]
    out[240:, 40:360] = bot[..., :3]
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGB").resize((800, 960), Image.NEAREST)
    img.save(OUT)
    print("saved", OUT)


main()

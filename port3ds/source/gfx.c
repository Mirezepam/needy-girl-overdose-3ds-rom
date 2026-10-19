// Rendering on both screens with citro2d: GPU textures in the NTX1 format produced by
// tools/build_assets.py (already tiled + flipped), sprite drawing and a bitmap font.
#include "engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TEX 768

typedef struct {
    C3D_Tex tex;
    u16 w, h;
    u32 bytes;
    bool used;
} NTex;

static NTex texs[MAX_TEX];
static u32 texBytes;
static C3D_RenderTarget *targets[2];
static u32 clearColor[2] = {0xff000000, 0xff000000};
static int curScreen;

static u32 rgba_to_c2d(u32 rgba) {
    return C2D_Color32((rgba >> 24) & 0xff, (rgba >> 16) & 0xff, (rgba >> 8) & 0xff, rgba & 0xff);
}

bool gfx_init(void) {
    gfxInitDefault();
    gfxSet3D(false);
    if (!C3D_Init(C3D_DEFAULT_CMDBUF_SIZE * 2)) return false;
    if (!C2D_Init(4096)) return false;
    C2D_Prepare();
    targets[0] = C2D_CreateScreenTarget(GFX_TOP, GFX_LEFT);
    targets[1] = C2D_CreateScreenTarget(GFX_BOTTOM, GFX_LEFT);
    return targets[0] && targets[1];
}

void gfx_exit(void) {
    for (int i = 0; i < MAX_TEX; i++) gfx_tex_free(i);
    C2D_Fini();
    C3D_Fini();
    gfxExit();
}

void gfx_set_clear(int screen, u32 rgba) { clearColor[screen & 1] = rgba_to_c2d(rgba); }

void gfx_begin_frame(void) { C3D_FrameBegin(C3D_FRAME_SYNCDRAW); }

void gfx_target(int screen) {
    curScreen = screen & 1;
    C2D_TargetClear(targets[curScreen], clearColor[curScreen]);
    C2D_SceneBegin(targets[curScreen]);
}

void gfx_end_frame(void) { C3D_FrameEnd(0); }

int gfx_tex_load(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    u8 hdr[16];
    if (fread(hdr, 1, 16, f) != 16 || memcmp(hdr, "NTX1", 4) != 0) {
        fclose(f);
        return -1;
    }
    u16 w = hdr[4] | (hdr[5] << 8), h = hdr[6] | (hdr[7] << 8);
    GPU_TEXCOLOR fmt = (GPU_TEXCOLOR)hdr[8];
    u32 size = hdr[12] | (hdr[13] << 8) | (hdr[14] << 16) | ((u32)hdr[15] << 24);
    int id = -1;
    for (int i = 0; i < MAX_TEX; i++)
        if (!texs[i].used) { id = i; break; }
    if (id < 0 || !C3D_TexInit(&texs[id].tex, w, h, fmt)) {
        fclose(f);
        return -1;
    }
    size_t got = fread(texs[id].tex.data, 1, size, f);
    fclose(f);
    if (got != size) {
        C3D_TexDelete(&texs[id].tex);
        return -1;
    }
    C3D_TexFlush(&texs[id].tex);
    C3D_TexSetFilter(&texs[id].tex, GPU_NEAREST, GPU_NEAREST);
    C3D_TexSetWrap(&texs[id].tex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
    texs[id].w = w;
    texs[id].h = h;
    texs[id].bytes = size;
    texs[id].used = true;
    texBytes += size;
    return id;
}

void gfx_tex_free(int id) {
    if (id < 0 || id >= MAX_TEX || !texs[id].used) return;
    C3D_TexDelete(&texs[id].tex);
    texBytes -= texs[id].bytes;
    texs[id].used = false;
}

bool gfx_tex_size(int id, int *w, int *h) {
    if (id < 0 || id >= MAX_TEX || !texs[id].used) return false;
    *w = texs[id].w;
    *h = texs[id].h;
    return true;
}

u32 gfx_tex_bytes(void) { return texBytes; }

static int fontTexId(void);
void gfx_free_game_textures(void) {
    for (int i = 0; i < MAX_TEX; i++)
        if (i != fontTexId()) gfx_tex_free(i);
}

C3D_Tex *gfx_tex_get(int id) {
    if (id < 0 || id >= MAX_TEX || !texs[id].used) return NULL;
    return &texs[id].tex;
}

static void draw_tex(C3D_Tex *tex, float tw, float th, float sx, float sy, float sw, float sh, float dx, float dy,
                     float scx, float scy, float alpha, u32 tint, float blend, float angle) {
    Tex3DS_SubTexture sub = {
        .width = (u16)sw, .height = (u16)sh,
        .left = sx / tw, .right = (sx + sw) / tw,
        .top = 1.0f - sy / th, .bottom = 1.0f - (sy + sh) / th,
    };
    C2D_Image img = {tex, &sub};
    C2D_ImageTint t;
    u32 c = rgba_to_c2d((tint & 0xffffff00) | (u32)(alpha * 255.0f));
    C2D_PlainImageTint(&t, c, blend);
    if (angle != 0.0f) {
        C2D_DrawImageAtRotated(img, dx + sw * scx / 2, dy + sh * scy / 2, 0.5f, angle, &t, scx, scy);
    } else {
        C2D_DrawImageAt(img, dx, dy, 0.5f, &t, scx, scy);
    }
}

void gfx_draw(int id, float sx, float sy, float sw, float sh, float dx, float dy,
              float scx, float scy, float alpha, u32 tint, float blend, float angle) {
    if (id < 0 || id >= MAX_TEX || !texs[id].used || alpha <= 0.0f) return;
    draw_tex(&texs[id].tex, texs[id].w, texs[id].h, sx, sy, sw, sh, dx, dy, scx, scy, alpha, tint, blend, angle);
}

void gfx_rect(float x, float y, float w, float h, u32 rgba) {
    if ((rgba & 0xff) == 0) return;
    C2D_DrawRectSolid(x, y, 0.5f, w, h, rgba_to_c2d(rgba));
}

void gfx_scissor(int x, int y, int w, int h) {
    C2D_Flush();
    int sw = curScreen == 0 ? TOP_W : BOT_W;
    // the framebuffer is rotated 90 degrees: scissor coordinates are in its space
    C3D_SetScissor(GPU_SCISSOR_NORMAL, SCR_H - (y + h), sw - (x + w), SCR_H - y, sw - x);
}

void gfx_scissor_off(void) {
    C2D_Flush();
    C3D_SetScissor(GPU_SCISSOR_DISABLE, 0, 0, 0, 0);
}

// ------------------------------------------------------------------ bitmap font

typedef struct {
    u32 cp;
    u16 x, y;
    u8 w, adv;
} Glyph;

static Glyph *glyphs;
static int glyphCount, cellW, cellH, fontTex = -1;

bool font_load(const char *ntx, const char *bin) {
    fontTex = gfx_tex_load(ntx);
    FILE *f = fopen(bin, "rb");
    if (fontTex < 0 || !f) {
        if (f) fclose(f);
        return false;
    }
    u8 hdr[12];
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "NFN1", 4) != 0) {
        fclose(f);
        return false;
    }
    cellW = hdr[4] | (hdr[5] << 8);
    cellH = hdr[6] | (hdr[7] << 8);
    glyphCount = hdr[8] | (hdr[9] << 8) | (hdr[10] << 16) | (hdr[11] << 24);
    glyphs = malloc(sizeof(Glyph) * glyphCount);
    for (int i = 0; i < glyphCount; i++) {
        u8 r[10];
        if (fread(r, 1, 10, f) != 10) break;
        glyphs[i].cp = r[0] | (r[1] << 8) | (r[2] << 16) | ((u32)r[3] << 24);
        glyphs[i].x = r[4] | (r[5] << 8);
        glyphs[i].y = r[6] | (r[7] << 8);
        glyphs[i].w = r[8];
        glyphs[i].adv = r[9];
    }
    fclose(f);
    return true;
}

int font_line_height(void) { return cellH - 4; }
static int fontTexId(void) { return fontTex; }

static const Glyph *find_glyph(u32 cp) {
    int lo = 0, hi = glyphCount - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (glyphs[mid].cp == cp) return &glyphs[mid];
        if (glyphs[mid].cp < cp) lo = mid + 1;
        else hi = mid - 1;
    }
    return NULL;
}

static u32 utf8_next(const char **p) {
    const u8 *s = (const u8 *)*p;
    u32 c = *s++;
    if (c >= 0xf0) { c = ((c & 7) << 18) | ((s[0] & 63) << 12) | ((s[1] & 63) << 6) | (s[2] & 63); s += 3; }
    else if (c >= 0xe0) { c = ((c & 15) << 12) | ((s[0] & 63) << 6) | (s[1] & 63); s += 2; }
    else if (c >= 0xc0) { c = ((c & 31) << 6) | (s[0] & 63); s += 1; }
    *p = (const char *)s;
    return c;
}

static bool is_wide(u32 cp) { return cp >= 0x2e80; }  // CJK: may break anywhere

static float glyph_adv(u32 cp) {
    if (cp == ' ') return cellW / 2.5f;
    const Glyph *g = find_glyph(cp);
    return g ? g->adv : cellW / 2;
}

// Measures the width of the next word (Latin) or char (CJK) starting at p.
static float word_width(const char *p, float scale) {
    float w = 0;
    while (*p && *p != ' ' && *p != '\n') {
        const char *q = p;
        u32 cp = utf8_next(&q);
        if (is_wide(cp) && w > 0) break;
        w += glyph_adv(cp) * scale;
        p = q;
        if (is_wide(cp)) break;
    }
    return w;
}

float font_draw(const char *s, float x, float y, u32 rgba, float scale, float wrap, int maxLines, bool measureOnly, float *outW) {
    if (!s || !glyphs) return 0;
    float lh = font_line_height() * scale;
    float cx = x, cy = y, maxW = 0;
    int line = 1;
    C3D_Tex *tex = gfx_tex_get(fontTex);
    float alpha = (rgba & 0xff) / 255.0f;
    const char *p = s;
    while (*p) {
        if (*p == '\n') {
            p++;
            if (cx - x > maxW) maxW = cx - x;
            if (maxLines > 0 && line >= maxLines) break;
            cx = x; cy += lh; line++;
            continue;
        }
        if (wrap > 0 && *p != ' ') {
            float ww = word_width(p, scale);
            if (cx > x && cx + ww > x + wrap) {
                if (cx - x > maxW) maxW = cx - x;
                if (maxLines > 0 && line >= maxLines) break;
                cx = x; cy += lh; line++;
            }
        }
        u32 cp = utf8_next(&p);
        if (cp == ' ' && cx == x && line > 1) continue;  // no leading space after wrap
        const Glyph *g = find_glyph(cp);
        if (g && !measureOnly && tex && cp != ' ')
            draw_tex(tex, tex->width, tex->height, g->x, g->y, cellW, cellH, cx, cy - 2 * scale, scale, scale, alpha, rgba, 1.0f, 0);
        cx += (cp == ' ' ? cellW / 2.5f : (g ? g->adv : cellW / 2)) * scale;
    }
    if (cx - x > maxW) maxW = cx - x;
    if (outW) *outW = maxW;
    return (cy - y) + lh;
}

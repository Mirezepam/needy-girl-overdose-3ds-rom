// ETV1 video playback: LZ4-compressed ETC1 frames decoded straight into a GPU texture.
// Costs almost no CPU, which is what makes full-screen video viable on Old 3DS.
#include "engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_VIDEOS 2

typedef struct {
    FILE *f;
    u16 w, h, tw, th, fps;
    u32 frames, frameBytes, dataStart, curFrame;
    u32 *offsets;
    u8 *buf;
    u32 bufCap;
    C3D_Tex tex;
    bool used;
} Video;

static Video vids[MAX_VIDEOS];

static u32 rd32(const u8 *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((u32)p[3] << 24); }
static u16 rd16(const u8 *p) { return p[0] | (p[1] << 8); }

int video_open(const char *path) {
    int id = -1;
    for (int i = 0; i < MAX_VIDEOS; i++)
        if (!vids[i].used) { id = i; break; }
    if (id < 0) return -1;
    Video *v = &vids[id];
    memset(v, 0, sizeof(*v));
    v->f = fopen(path, "rb");
    if (!v->f) return -1;
    u8 hdr[20];
    if (fread(hdr, 1, 20, v->f) != 20 || memcmp(hdr, "ETV1", 4) != 0) {
        fclose(v->f);
        return -1;
    }
    v->w = rd16(hdr + 4); v->h = rd16(hdr + 6);
    v->tw = rd16(hdr + 8); v->th = rd16(hdr + 10);
    v->fps = rd16(hdr + 12);
    v->frames = rd32(hdr + 16);
    v->frameBytes = v->tw * v->th / 2;  // ETC1 = 4 bits per pixel
    v->offsets = malloc(4 * (v->frames + 1));
    if (fread(v->offsets, 4, v->frames + 1, v->f) != v->frames + 1) {
        fclose(v->f);
        free(v->offsets);
        return -1;
    }
    v->dataStart = 20 + 4 * (v->frames + 1);
    v->bufCap = v->frameBytes + v->frameBytes / 8 + 64;
    v->buf = malloc(v->bufCap);
    if (!v->buf || !C3D_TexInit(&v->tex, v->tw, v->th, GPU_ETC1)) {
        fclose(v->f);
        free(v->offsets);
        free(v->buf);
        return -1;
    }
    C3D_TexSetFilter(&v->tex, GPU_LINEAR, GPU_LINEAR);
    v->curFrame = 0xffffffff;
    v->used = true;
    return id;
}

bool video_info(int id, int *w, int *h, int *fps, int *frames) {
    if (id < 0 || id >= MAX_VIDEOS || !vids[id].used) return false;
    *w = vids[id].w; *h = vids[id].h; *fps = vids[id].fps; *frames = vids[id].frames;
    return true;
}

bool video_show(int id, int frame) {
    if (id < 0 || id >= MAX_VIDEOS || !vids[id].used) return false;
    Video *v = &vids[id];
    if (frame < 0) frame = 0;
    if ((u32)frame >= v->frames) frame = v->frames - 1;
    if ((u32)frame == v->curFrame) return true;
    u32 len = v->offsets[frame + 1] - v->offsets[frame];
    if (len > v->bufCap) return false;
    fseek(v->f, v->dataStart + v->offsets[frame], SEEK_SET);
    if (fread(v->buf, 1, len, v->f) != len) return false;
    if (lz4_decompress(v->buf, len, v->tex.data, v->frameBytes) != (int)v->frameBytes) return false;
    C3D_TexFlush(&v->tex);
    v->curFrame = frame;
    return true;
}

void video_draw(int id, float x, float y, float scale, float alpha) {
    if (id < 0 || id >= MAX_VIDEOS || !vids[id].used || vids[id].curFrame == 0xffffffff) return;
    Video *v = &vids[id];
    Tex3DS_SubTexture sub = {
        .width = v->w, .height = v->h,
        .left = 0, .right = (float)v->w / v->tw,
        .top = 1.0f, .bottom = 1.0f - (float)v->h / v->th,
    };
    C2D_Image img = {&v->tex, &sub};
    C2D_ImageTint t;
    C2D_AlphaImageTint(&t, alpha);
    C2D_DrawImageAt(img, x, y, 0.5f, &t, scale, scale);
}

void video_close(int id) {
    if (id < 0 || id >= MAX_VIDEOS || !vids[id].used) return;
    Video *v = &vids[id];
    fclose(v->f);
    free(v->offsets);
    free(v->buf);
    C3D_TexDelete(&v->tex);
    v->used = false;
}

#pragma once
#include <3ds.h>
#include <citro2d.h>
#include <stdbool.h>

#define DATA_DIR "sdmc:/3ds/needy3ds/"
#define TOP_W 400
#define BOT_W 320
#define SCR_H 240

// gfx.c
bool gfx_init(void);
void gfx_exit(void);
void gfx_begin_frame(void);
void gfx_target(int screen);  // 0 = top, 1 = bottom
void gfx_end_frame(void);
int gfx_tex_load(const char *path);
void gfx_tex_free(int id);
bool gfx_tex_size(int id, int *w, int *h);
u32 gfx_tex_bytes(void);
void gfx_free_game_textures(void);  // everything except the font
C3D_Tex *gfx_tex_get(int id);
void gfx_draw(int id, float sx, float sy, float sw, float sh, float dx, float dy,
              float scx, float scy, float alpha, u32 tint, float blend, float angle);
void gfx_rect(float x, float y, float w, float h, u32 rgba);
void gfx_scissor(int x, int y, int w, int h);
void gfx_scissor_off(void);
void gfx_set_clear(int screen, u32 rgba);

// font (gfx.c)
bool font_load(const char *ntx, const char *bin);
// draws UTF-8 text; returns the height used. wrap <= 0 disables wrapping.
float font_draw(const char *s, float x, float y, u32 rgba, float scale, float wrap, int maxLines, bool measureOnly, float *outW);
int font_line_height(void);

// audio.c
bool audio_init(void);
bool audio_ok(void);
void audio_exit(void);
bool audio_bgm_play(const char *path, bool loop);
void audio_bgm_stop(void);
void audio_bgm_volume(float v);
double audio_bgm_position(void);
int audio_se_load(const char *path);
void audio_se_free(int id);
void audio_se_play(int id, float volume);
void audio_se_free_all(void);

// video.c
int video_open(const char *path);
bool video_info(int h, int *w, int *hgt, int *fps, int *frames);
bool video_show(int h, int frame);
void video_draw(int h, float x, float y, float scale, float alpha);
void video_close(int h);

// lz4.c
int lz4_decompress(const u8 *src, int srcLen, u8 *dst, int dstCap);

// luabind.c
struct lua_State;
int luaopen_sys(struct lua_State *L);

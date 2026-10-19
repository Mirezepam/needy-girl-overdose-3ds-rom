// "sys" Lua module: the only bridge between the game runtime (Lua) and the 3DS hardware.
#include "engine.h"
#include "lauxlib.h"
#include "lua.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static u32 opt_color(lua_State *L, int idx, u32 def) {
    return lua_isnoneornil(L, idx) ? def : (u32)luaL_checkinteger(L, idx);
}

static int l_tex_load(lua_State *L) {
    int id = gfx_tex_load(luaL_checkstring(L, 1));
    if (id < 0) { lua_pushnil(L); return 1; }
    int w, h;
    gfx_tex_size(id, &w, &h);
    lua_pushinteger(L, id);
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    return 3;
}

static int l_tex_free(lua_State *L) { gfx_tex_free((int)luaL_checkinteger(L, 1)); return 0; }

// draw(tex, sx, sy, sw, sh, dx, dy [, scx, scy, alpha, tint, blend, angle])
static int l_draw(lua_State *L) {
    float scx = luaL_optnumber(L, 8, 1), scy = luaL_optnumber(L, 9, scx);
    gfx_draw((int)luaL_checkinteger(L, 1), luaL_checknumber(L, 2), luaL_checknumber(L, 3), luaL_checknumber(L, 4),
             luaL_checknumber(L, 5), luaL_checknumber(L, 6), luaL_checknumber(L, 7), scx, scy,
             luaL_optnumber(L, 10, 1), opt_color(L, 11, 0xffffffff), luaL_optnumber(L, 12, 0), luaL_optnumber(L, 13, 0));
    return 0;
}

static int l_rect(lua_State *L) {
    gfx_rect(luaL_checknumber(L, 1), luaL_checknumber(L, 2), luaL_checknumber(L, 3), luaL_checknumber(L, 4),
             opt_color(L, 5, 0xffffffff));
    return 0;
}

// text(str, x, y [, color, scale, wrap, maxLines]) -> height, width
static int l_text(lua_State *L) {
    float w;
    float h = font_draw(luaL_checkstring(L, 1), luaL_checknumber(L, 2), luaL_checknumber(L, 3), opt_color(L, 4, 0xffffffff),
                        luaL_optnumber(L, 5, 1), luaL_optnumber(L, 6, 0), (int)luaL_optinteger(L, 7, 0), false, &w);
    lua_pushnumber(L, h);
    lua_pushnumber(L, w);
    return 2;
}

// measure(str [, scale, wrap, maxLines]) -> width, height
static int l_measure(lua_State *L) {
    float w;
    float h = font_draw(luaL_checkstring(L, 1), 0, 0, 0, luaL_optnumber(L, 2, 1), luaL_optnumber(L, 3, 0),
                        (int)luaL_optinteger(L, 4, 0), true, &w);
    lua_pushnumber(L, w);
    lua_pushnumber(L, h);
    return 2;
}

static int l_line_height(lua_State *L) { lua_pushinteger(L, font_line_height()); return 1; }

static int l_scissor(lua_State *L) {
    if (lua_isnoneornil(L, 1)) gfx_scissor_off();
    else gfx_scissor((int)luaL_checknumber(L, 1), (int)luaL_checknumber(L, 2), (int)luaL_checknumber(L, 3), (int)luaL_checknumber(L, 4));
    return 0;
}

static int l_clear_color(lua_State *L) {
    gfx_set_clear((int)luaL_checkinteger(L, 1), (u32)luaL_checkinteger(L, 2));
    return 0;
}

static int l_bgm_play(lua_State *L) { lua_pushboolean(L, audio_bgm_play(luaL_checkstring(L, 1), lua_toboolean(L, 2))); return 1; }
static int l_bgm_stop(lua_State *L) { (void)L; audio_bgm_stop(); return 0; }
static int l_bgm_volume(lua_State *L) { audio_bgm_volume(luaL_checknumber(L, 1)); return 0; }
static int l_bgm_pos(lua_State *L) { lua_pushnumber(L, audio_bgm_position()); return 1; }

static int l_se_load(lua_State *L) {
    int id = audio_se_load(luaL_checkstring(L, 1));
    if (id < 0) lua_pushnil(L); else lua_pushinteger(L, id);
    return 1;
}
static int l_se_free(lua_State *L) { audio_se_free((int)luaL_checkinteger(L, 1)); return 0; }
static int l_se_play(lua_State *L) { audio_se_play((int)luaL_checkinteger(L, 1), luaL_optnumber(L, 2, 1)); return 0; }

static int l_video_open(lua_State *L) {
    int id = video_open(luaL_checkstring(L, 1));
    int w, h, fps, frames;
    if (id < 0 || !video_info(id, &w, &h, &fps, &frames)) { lua_pushnil(L); return 1; }
    lua_pushinteger(L, id);
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    lua_pushinteger(L, fps);
    lua_pushinteger(L, frames);
    return 5;
}
static int l_video_show(lua_State *L) { lua_pushboolean(L, video_show((int)luaL_checkinteger(L, 1), (int)luaL_checkinteger(L, 2))); return 1; }
static int l_video_draw(lua_State *L) {
    video_draw((int)luaL_checkinteger(L, 1), luaL_checknumber(L, 2), luaL_checknumber(L, 3), luaL_optnumber(L, 4, 1), luaL_optnumber(L, 5, 1));
    return 0;
}
static int l_video_close(lua_State *L) { video_close((int)luaL_checkinteger(L, 1)); return 0; }

static int l_read(lua_State *L) {
    FILE *f = fopen(luaL_checkstring(L, 1), "rb");
    if (!f) { lua_pushnil(L); return 1; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(n > 0 ? n : 1);
    size_t got = fread(buf, 1, n, f);
    fclose(f);
    lua_pushlstring(L, buf, got);
    free(buf);
    return 1;
}

static int l_write(lua_State *L) {
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    FILE *f = fopen(luaL_checkstring(L, 1), "wb");
    if (!f) { lua_pushboolean(L, 0); return 1; }
    bool ok = fwrite(data, 1, len, f) == len;
    fclose(f);
    lua_pushboolean(L, ok);
    return 1;
}

static int l_exists(lua_State *L) {
    struct stat st;
    lua_pushboolean(L, stat(luaL_checkstring(L, 1), &st) == 0);
    return 1;
}

static int l_mkdir(lua_State *L) { mkdir(luaL_checkstring(L, 1), 0777); return 0; }

static int l_remove(lua_State *L) { lua_pushboolean(L, remove(luaL_checkstring(L, 1)) == 0); return 1; }

static int l_time(lua_State *L) { lua_pushinteger(L, (lua_Integer)osGetTime()); return 1; }

// high resolution clock in milliseconds (for the on-screen profiler)
static int l_ticks(lua_State *L) { lua_pushnumber(L, (double)svcGetSystemTick() / (SYSCLOCK_ARM11 / 1000.0)); return 1; }

static int l_mem(lua_State *L) {
    lua_pushinteger(L, linearSpaceFree());
    lua_pushinteger(L, gfx_tex_bytes());
    lua_pushinteger(L, lua_gc(L, LUA_GCCOUNT, 0) * 1024);
    return 3;
}

// keyboard(hint, initial, maxLen) -> string or nil
static int l_keyboard(lua_State *L) {
    SwkbdState kb;
    char buf[256];
    int maxLen = (int)luaL_optinteger(L, 3, 32);
    if (maxLen > 255) maxLen = 255;
    swkbdInit(&kb, SWKBD_TYPE_NORMAL, 2, maxLen);
    swkbdSetHintText(&kb, luaL_optstring(L, 1, ""));
    swkbdSetInitialText(&kb, luaL_optstring(L, 2, ""));
    SwkbdButton b = swkbdInputText(&kb, buf, sizeof(buf));
    if (b == SWKBD_BUTTON_CONFIRM) lua_pushstring(L, buf);
    else lua_pushnil(L);
    return 1;
}

static int l_is_new3ds(lua_State *L) {
    bool n = false;
    APT_CheckNew3DS(&n);
    lua_pushboolean(L, n);
    return 1;
}

int luaopen_sys(lua_State *L) {
    static const luaL_Reg fns[] = {
        {"tex_load", l_tex_load}, {"tex_free", l_tex_free}, {"draw", l_draw}, {"rect", l_rect},
        {"text", l_text}, {"measure", l_measure}, {"line_height", l_line_height}, {"scissor", l_scissor},
        {"clear_color", l_clear_color},
        {"bgm_play", l_bgm_play}, {"bgm_stop", l_bgm_stop}, {"bgm_volume", l_bgm_volume}, {"bgm_pos", l_bgm_pos},
        {"se_load", l_se_load}, {"se_free", l_se_free}, {"se_play", l_se_play},
        {"video_open", l_video_open}, {"video_show", l_video_show}, {"video_draw", l_video_draw}, {"video_close", l_video_close},
        {"read", l_read}, {"write", l_write}, {"exists", l_exists}, {"mkdir", l_mkdir}, {"remove", l_remove},
        {"time", l_time}, {"ticks", l_ticks}, {"mem", l_mem}, {"keyboard", l_keyboard}, {"is_new3ds", l_is_new3ds},
        {NULL, NULL},
    };
    luaL_newlib(L, fns);
    lua_pushstring(L, DATA_DIR);
    lua_setfield(L, -2, "data");
    return 1;
}

// NEEDY GIRL OVERDOSE 3DS - engine entry point.
// The C side owns hardware (two screens, touch, audio, video); the game itself runs in Lua
// (sdmc:/3ds/needy3ds/lua/main.lua), mostly transpiled from the original C# event scripts.
#include "engine.h"
#include <sys/stat.h>
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
#include <stdio.h>
#include <string.h>

static lua_State *L;
static char errorMsg[2048];

static void set_error(const char *msg) {
    snprintf(errorMsg, sizeof(errorMsg), "%s", msg ? msg : "unknown error");
    FILE *f = fopen(DATA_DIR "error.log", "w");
    if (f) { fputs(errorMsg, f); fclose(f); }
}

static int traceback(lua_State *Ls) {
    luaL_traceback(Ls, Ls, lua_tostring(Ls, 1), 1);
    return 1;
}

// calls game.<fn>(...) with nargs already pushed; on error stores the message
static bool call_game(const char *fn, int nargs) {
    if (errorMsg[0]) { lua_pop(L, nargs); return false; }
    lua_getglobal(L, "game");
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, nargs + 1); return false; }
    lua_insert(L, -(nargs + 1));
    lua_pushcfunction(L, traceback);
    lua_insert(L, -(nargs + 2));
    int base = lua_gettop(L) - nargs - 1;
    if (lua_pcall(L, nargs, 0, base) != LUA_OK) {
        set_error(lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    lua_remove(L, base);
    return !errorMsg[0];
}

static void draw_error(int screen) {
    gfx_rect(0, 0, screen == 0 ? TOP_W : BOT_W, SCR_H, 0x200020ff);
    if (screen == 0) {
        font_draw("Error del port (START para salir)", 6, 4, 0xff6080ff, 1, 0, 0, false, NULL);
        font_draw(errorMsg, 6, 20, 0xffffffff, 1, TOP_W - 12, 17, false, NULL);
    } else {
        font_draw("Se guardó en sdmc:/3ds/needy3ds/error.log", 6, 4, 0xc0c0c0ff, 1, BOT_W - 12, 0, false, NULL);
    }
}

static bool boot_lua(void) {
    L = luaL_newstate();
    luaL_openlibs(L);
    luaL_requiref(L, "sys", luaopen_sys, 1);
    lua_pop(L, 1);
    lua_getglobal(L, "package");
    char path[256];
    snprintf(path, sizeof(path), "%slua/?.lua;%slua/?/init.lua;%s?.lua", data_dir, data_dir, data_dir);
    lua_pushstring(L, path);
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
    lua_pushcfunction(L, traceback);
    snprintf(path, sizeof(path), "%slua/main.lua", data_dir);
    if (luaL_loadfile(L, path) != LUA_OK || lua_pcall(L, 0, 0, -2) != LUA_OK) {
        set_error(lua_tostring(L, -1));
        return false;
    }
    lua_pop(L, 1);
    return call_game("init", 0);
}

const char *data_dir = DATA_DIR;

int main(void) {
    osSetSpeedupEnable(true);  // New 3DS: 804 MHz + L2 cache; no-op on Old 3DS
    if (!gfx_init()) return 1;
    // a test CIA can carry the game data in its RomFS; the .3dsx / normal CIA read the SD
    bool romfs = R_SUCCEEDED(romfsInit());
    if (romfs) {
        FILE *t = fopen("romfs:/font/main.bin", "rb");
        if (t) { fclose(t); data_dir = "romfs:/"; }
    }
    mkdir("sdmc:/3ds", 0777);
    mkdir(DATA_DIR, 0777);
    char fnt[96], fbin[96];
    snprintf(fnt, sizeof(fnt), "%sfont/main.ntx", data_dir);
    snprintf(fbin, sizeof(fbin), "%sfont/main.bin", data_dir);
    bool fontOk = font_load(fnt, fbin);
    audio_init();
    if (!fontOk) {
        consoleInit(GFX_BOTTOM, NULL);
        printf("\n Faltan los datos del juego.\n\n Genera la carpeta con tools/build_assets.py\n y copiala a sdmc:/3ds/needy3ds/\n\n START para salir.\n");
        while (aptMainLoop()) {
            hidScanInput();
            if (hidKeysDown() & KEY_START) break;
            gspWaitForVBlank();
        }
        gfx_exit();
        return 0;
    }
    boot_lua();

    u64 last = osGetTime();
    while (aptMainLoop()) {
        hidScanInput();
        u32 down = hidKeysDown(), held = hidKeysHeld(), up = hidKeysUp();
        touchPosition tp;
        hidTouchRead(&tp);
        if (errorMsg[0] && (down & KEY_START)) break;

        u64 now = osGetTime();
        double dt = (now - last) / 1000.0;
        if (dt > 0.1) dt = 0.1;
        last = now;

        lua_pushnumber(L, dt);
        lua_pushinteger(L, down);
        lua_pushinteger(L, held);
        lua_pushinteger(L, up);
        lua_pushinteger(L, tp.px);
        lua_pushinteger(L, tp.py);
        call_game("update", 6);

        lua_getglobal(L, "game");
        bool quit = lua_istable(L, -1) && (lua_getfield(L, -1, "quit"), lua_toboolean(L, -1));
        lua_settop(L, 0);
        if (quit) break;
        // "back to title": restart the whole Lua runtime (the game scene is rebuilt from scratch)
        lua_getglobal(L, "game");
        bool reboot = lua_istable(L, -1) && (lua_getfield(L, -1, "reboot"), lua_toboolean(L, -1));
        lua_settop(L, 0);
        if (reboot) {
            call_game("shutdown", 0);
            lua_close(L);
            audio_bgm_stop();
            gfx_free_game_textures();
            audio_se_free_all();
            boot_lua();
            continue;
        }

        gfx_begin_frame();
        for (int screen = 0; screen < 2; screen++) {
            gfx_target(screen);
            if (errorMsg[0]) {
                draw_error(screen);
            } else {
                lua_pushinteger(L, screen);
                call_game("draw", 1);
            }
            gfx_scissor_off();
        }
        gfx_end_frame();
    }
    if (!errorMsg[0]) call_game("shutdown", 0);
    lua_close(L);
    audio_exit();
    gfx_exit();
    if (romfs) romfsExit();
    return 0;
}

# NEEDY GIRL OVERDOSE — 3DS fan port

An unofficial Nintendo 3DS / 2DS port of NEEDY GIRL OVERDOSE, made as an academic project.
It runs the original game logic (translated from C# to Lua) on a small C engine built with
citro2d, and spreads the Windose desktop across the two screens: Ame's webcam and the stream on
top, the touch desktop below.

**Everything is in [`port3ds/`](port3ds/)** — see its [README](port3ds/README.md) for features,
controls, installation and build instructions.

## Repository layout

| Path | Contents |
|---|---|
| `port3ds/source/` | C engine: graphics, input, audio, video, Lua bindings (plus Lua 5.4 and LZ4) |
| `port3ds/lua/gen/` | Game logic translated from the original C# by `cs2lua` |
| `port3ds/lua/runtime/`, `port3ds/lua/override/` | Unity-like runtime and replacements for engine-bound classes |
| `port3ds/lua/ui/` | Dual-screen Windose UI and every in-game app |
| `port3ds/tools/` | Asset extraction/conversion, `cs2lua`, PC test harness, emulator scripts |
| `port3ds/docs/` | Design notes, screen mapping and event catalogue (Spanish) |

## Not included

Extracted game material (`assets/`, `code/`, `raw_data/`) and the generated 3DS data folder
(`port3ds/build_data/`) are excluded with `.gitignore`. They are copyrighted and must be
generated from your own Steam copy of the game.

## Legal

NEEDY GIRL OVERDOSE © WSS playground / xemono. This project is not affiliated with or endorsed by
the original developers, is non-commercial, and is intended for personal study only.

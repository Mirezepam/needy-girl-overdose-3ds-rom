# NEEDY GIRL OVERDOSE 3DS (fan port)

*[Leer en español](README.es.md)*

A homebrew port of NEEDY GIRL OVERDOSE for Nintendo 3DS / 2DS that uses both screens: the top
screen shows Ame's webcam and the stream, and the bottom screen is the touch-driven Windose
desktop. Texts are available in Spanish, English and Japanese.

> **No original game data is distributed.** The data folder is generated from your own Steam copy
> and is for personal use only. Do not share it.

## How it works

- **C engine** (`source/`): citro2d rendering on both screens, touch and buttons, NDSP audio (Ogg
  streaming for music, cached PCM for sound effects), ETC1 + LZ4 video playback, and an embedded
  Lua 5.4 interpreter.
- **Game logic** (`lua/gen/`): the original C# scripts translated to Lua by `tools/cs2lua`.
- **Runtime and overrides** (`lua/runtime/`, `lua/override/`): a small Unity-like runtime
  (coroutines, timers, reactive properties, saves) and hand-written replacements for the Unity
  classes that are tied to the original UI (windows, audio, live stream, effects).
- **UI** (`lua/ui/`): the Windose desktop and every app (JINE, Poketter, streams, documents,
  endings, settings...) redrawn for 400×240 + 320×240 with the original art.

## Install on a console

1. You need a 3DS with [homebrew](https://3ds.hacks.guide/) (Homebrew Launcher) and the dumped DSP
   firmware (`sdmc:/3ds/dspfirm.cdc`, created with *DSP1*). Without it the game runs silent and the
   title screen shows a warning.
2. Copy `needy3ds.3dsx` to `sdmc:/3ds/`.
3. Copy the whole `build_data/needy3ds/` folder to `sdmc:/3ds/needy3ds/` (about 850 MB).
4. Launch *NEEDY GIRL OVERDOSE 3DS* from the Homebrew Launcher.

On the Azahar emulator: `File → Load File…` → `needy3ds.3dsx`, with the data folder in
`%APPDATA%\Azahar\sdmc\3ds\needy3ds\`. With HLE audio emulation any file named
`sdmc:/3ds/dspfirm.cdc` is enough to enable sound.

## Controls

| Action | Touch | Buttons |
|---|---|---|
| Select / press | Tap | D-pad + **A** |
| Advance dialogue | Tap anywhere | **A** |
| **Skip text** (fast-forward) | `>>` button on the taskbar | **SELECT** |
| Close app / back | `x` button | **B** |
| Switch app | Taskbar | **L / R** |
| JINE / Poketter | Icons | **Y / X** |
| Start menu (My Pictures, Control Panel, Restart, Shut down) | *Start* button on the taskbar | **START** |
| Task Manager (stats and graphs) | Taskbar icon | — |
| Show a command's description | Touch and hold | — |
| Stream: pick a super chat | Tap the coloured comment | D-pad + **A** |
| Stream: delete a comment | Tap it or swipe left | D-pad + **A** |
| Stream: pause | Keep your finger on the chat | — |
| Stream: speed / skip | *Stream pace* / *▶SKIP* buttons | **R**, **L** / **SELECT** |
| Stream: next line | — | **A** |
| Pet Ame | Rub her head on the bottom screen | **A** |
| Performance overlay | — | **L + R + SELECT** |

## Building the data and the executable (PC)

Requirements: the Steam version of the game, Python 3, the .NET SDK and devkitPro (3ds-dev).

```bash
# 1. extract the game assets (UnityPy)
tools/.venv/Scripts/python -I tools/extract_assets.py "<game>/Windose_Data" ../assets
tools/.venv/Scripts/python -I tools/extract_pass2.py "<game>/Windose_Data" ../assets
# 2. translate the game code to Lua
tools/cs2lua/bin/Release/net10.0/cs2lua.exe ../code/Assembly-CSharp "<game>/Windose_Data/Managed" lua
# 3. convert the assets to 3DS formats
tools/.venv/Scripts/python -I tools/build_assets.py ../assets build_data
tools/.venv/Scripts/python -I tools/resolve_sound_master.py "<game>/Windose_Data" build_data/needy3ds
tools/.venv/Scripts/python -I tools/export_anims.py "<game>/Windose_Data" build_data/needy3ds
tools/.venv/Scripts/python -I tools/dump_prefabs.py "<game>/Windose_Data" build_data/prefabs
tools/.venv/Scripts/python -I tools/export_ideon.py .
tools/.venv/Scripts/python -I tools/export_bank.py "<game>/Windose_Data" build_data/needy3ds
# 4. build the .3dsx (inside MSYS2)
./build.sh
```

After editing Lua files, copy them into the data folder with
`tools/.venv/Scripts/python -I tools/build_assets.py ../assets build_data lua`.

## Testing without a console

- `tools/pc_harness.lua`: runs the game on PC (Lua 5.4) with a bot that plays by itself and prints
  how many music tracks and sound effects were played. Environment variables:
  `NGO_FAST=1` (fast-forward), `NGO_BOOST=1` (passes follower milestones to test later days),
  `NGO_TOUR=1` (visits every screen and saves snapshots to `build_data/snaps/`),
  `NGO_LINT=1` (reports clipped or overflowing text), `NGO_LANG=en|ja` (language),
  `NGO_SEED=n` (bot seed, to reach other endings).
- `tools/render_snap.py`: renders those snapshots to PNG images of both screens.
- `tools/test_endings.ps1`: forces every ending and checks that each one reaches its final screen.
- `tools/azahar_run.ps1`, `tools/azahar_shot.ps1`: launch the emulator off-screen and capture it.
- If `sdmc:/3ds/needy3ds/autoplay.txt` exists, the port starts a game in slot 3 and plays by
  itself (for emulator testing). It ships disabled as `autoplay.txt.off`; rename it to use it.

More details (in Spanish): [docs/PLAN.md](docs/PLAN.md), [docs/PANTALLAS.md](docs/PANTALLAS.md) and
[docs/EVENTOS.md](docs/EVENTOS.md).

## Credits

NEEDY GIRL OVERDOSE © WSS playground / xemono. This is an unofficial, non-commercial fan project
made for academic study; it is not affiliated with or endorsed by the original developers.
Lua 5.4 © Lua.org, PUC-Rio (MIT). LZ4 © Yann Collet (BSD-2-Clause).

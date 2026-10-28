# NEEDY GIRL OVERDOSE — 3DS fan port

An unofficial Nintendo 3DS / 2DS port of NEEDY GIRL OVERDOSE, made as an academic project.
It runs the original game logic (translated from C# to Lua) on a small C engine built with
citro2d, and spreads the Windose desktop across the two screens: Ame's webcam and the stream on
top, the touch desktop below.

<p align="center">
  <img src="port3ds/docs/screenshots/02_jine.png" width="200">
  <img src="port3ds/docs/screenshots/04_stream.png" width="200">
  <img src="port3ds/docs/screenshots/09_going_out.png" width="200">
  <img src="port3ds/docs/screenshots/23_ending_screen.png" width="200">
</p>

**Everything is in [`port3ds/`](port3ds/)** — see its [README](port3ds/README.md) for features,
controls, installation and build instructions.

## Download

**Test builds with the game data inside** ([v1.0.15](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/tag/v1.0.15)) — private repository,
for personal testing only. Nothing to copy to the SD card: the data travels inside each file.

| File | Version | How to use it |
|---|---|---|
| [`needy3ds_full.cia`](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/download/v1.0.15/needy3ds_full.cia) | Standard | Install with FBI → HOME Menu |
| [`needy3ds_full.3dsx`](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/download/v1.0.15/needy3ds_full.3dsx) | Standard | Copy to `sdmc:/3ds/` → Homebrew Launcher |
| [`needy3ds_3d.cia`](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/download/v1.0.15/needy3ds_3d.cia) | Stereoscopic 3D | Install with FBI → HOME Menu ("Ame-chan 3D") |
| [`needy3ds_3d.3dsx`](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/download/v1.0.15/needy3ds_3d.3dsx) | Stereoscopic 3D | Copy to `sdmc:/3ds/` → Homebrew Launcher |

**Engine only** ([v1.0.14](https://github.com/Mirezepam/needy-girl-overdose-3ds/releases/tag/v1.0.14)): `needy3ds.3dsx` / `needy3ds.cia`, which read the
data folder from `sdmc:/3ds/needy3ds/`, generated from your own Steam copy of the game (see
[Building the data](port3ds/README.md#building-the-data-and-the-executable-pc)).

Saves, settings and the log always go to `sdmc:/3ds/needy3ds/`. Sound needs the DSP firmware dump
(`sdmc:/3ds/dspfirm.cdc`, made with DSP1).

## Screenshots

Both screens at the 3DS's native resolution (top 400×240, bottom 320×240).

<table>
<tr><td align="center"><img src="port3ds/docs/screenshots/01_title.png" width="260" alt="Title screen and save slots"><br><sub>Title screen and save slots</sub></td><td align="center"><img src="port3ds/docs/screenshots/02_jine.png" width="260" alt="JINE chat with Ame"><br><sub>JINE chat with Ame</sub></td><td align="center"><img src="port3ds/docs/screenshots/03_jine_reply.png" width="260" alt="Choosing a reply"><br><sub>Choosing a reply</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/04_stream.png" width="260" alt="Live stream"><br><sub>Live stream</sub></td><td align="center"><img src="port3ds/docs/screenshots/05_stream_comments.png" width="260" alt="Reading the stream chat"><br><sub>Reading the stream chat</sub></td><td align="center"><img src="port3ds/docs/screenshots/06_stream_topic.png" width="260" alt="Picking the stream topic"><br><sub>Picking the stream topic</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/07_internet.png" width="260" alt="Internet"><br><sub>Internet</sub></td><td align="center"><img src="port3ds/docs/screenshots/08_medicine.png" width="260" alt="Medicine"><br><sub>Medicine</sub></td><td align="center"><img src="port3ds/docs/screenshots/09_going_out.png" width="260" alt="Going out (map on top)"><br><sub>Going out (map on top)</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/10_sleep.png" width="260" alt="Sleep"><br><sub>Sleep</sub></td><td align="center"><img src="port3ds/docs/screenshots/11_poketter.png" width="260" alt="Poketter"><br><sub>Poketter</sub></td><td align="center"><img src="port3ds/docs/screenshots/12_train.png" width="260" alt="Train ride"><br><sub>Train ride</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/13_call.png" width="260" alt="Ame is calling"><br><sub>Ame is calling</sub></td><td align="center"><img src="port3ds/docs/screenshots/14_package_insert.png" width="260" alt="Package insert"><br><sub>Package insert</sub></td><td align="center"><img src="port3ds/docs/screenshots/15_task_manager.png" width="260" alt="Task Manager"><br><sub>Task Manager</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/16_control_panel.png" width="260" alt="Control Panel"><br><sub>Control Panel</sub></td><td align="center"><img src="port3ds/docs/screenshots/17_board.png" width="260" alt="Message board"><br><sub>Message board</sub></td><td align="center"><img src="port3ds/docs/screenshots/18_dinder.png" width="260" alt="Dinder"><br><sub>Dinder</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/19_new_idea.png" width="260" alt="New stream idea"><br><sub>New stream idea</sub></td><td align="center"><img src="port3ds/docs/screenshots/20_internet_angel.png" width="260" alt="Internet Angel"><br><sub>Internet Angel</sub></td><td align="center"><img src="port3ds/docs/screenshots/21_bank.png" width="260" alt="Stream opening"><br><sub>Stream opening</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/22_ending.png" width="260" alt="Ending"><br><sub>Ending</sub></td><td align="center"><img src="port3ds/docs/screenshots/23_ending_screen.png" width="260" alt="Ending screen"><br><sub>Ending screen</sub></td><td align="center"><img src="port3ds/docs/screenshots/24_choose_zip.png" width="260" alt="Choosing a ZIP after an ending"><br><sub>Choosing a ZIP after an ending</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/25_my_pictures.png" width="260" alt="My Pictures"><br><sub>My Pictures</sub></td><td align="center"><img src="port3ds/docs/screenshots/26_en_jine.png" width="260" alt="English: JINE"><br><sub>English: JINE</sub></td><td align="center"><img src="port3ds/docs/screenshots/27_en_stream.png" width="260" alt="English: stream"><br><sub>English: stream</sub></td></tr>
<tr><td align="center"><img src="port3ds/docs/screenshots/28_ja_jine.png" width="260" alt="Japanese: JINE"><br><sub>Japanese: JINE</sub></td><td align="center"><img src="port3ds/docs/screenshots/29_ja_stream.png" width="260" alt="Japanese: stream"><br><sub>Japanese: stream</sub></td><td align="center"><img src="port3ds/docs/screenshots/30_ja_package_insert.png" width="260" alt="Japanese: package insert"><br><sub>Japanese: package insert</sub></td></tr>
</table>

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

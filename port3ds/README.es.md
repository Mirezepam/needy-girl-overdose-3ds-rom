# NEEDY GIRL OVERDOSE 3DS (port de fans)

Port homebrew para Nintendo 3DS / 2DS que usa las dos pantallas: arriba la webcam de Ame y el
stream, abajo el escritorio Windose táctil. El juego incluye textos en español, inglés y japonés.

> **No incluye nada del juego original.** La carpeta de datos se genera a partir de tu propia copia
> de Steam y es solo para uso personal. No la compartas.

## Instalar en la consola

1. Necesitas una 3DS con [homebrew](https://3ds.hacks.guide/) (Homebrew Launcher) y el firmware
   del DSP volcado (`sdmc:/3ds/dspfirm.cdc`, se crea con *DSP1*) para que haya sonido.
2. Copia `needy3ds.3dsx` a `sdmc:/3ds/`.
3. Copia la carpeta `build_data/needy3ds/` entera a `sdmc:/3ds/needy3ds/` (unos 850 MB).
4. Abre *NEEDY GIRL OVERDOSE 3DS* desde el Homebrew Launcher.

En el emulador Azahar: `Archivo → Cargar archivo…` → `needy3ds.3dsx`, con la carpeta de datos en
`%APPDATA%\Azahar\sdmc\3ds\needy3ds\`.

## Controles

| Acción | Táctil | Botones |
|---|---|---|
| Elegir / pulsar | Tocar | Cruceta + **A** |
| Avanzar diálogo | Tocar en cualquier sitio | **A** |
| **Saltar texto** (avance rápido) | Botón `>>` de la barra de tareas | **SELECT** |
| Cerrar app / volver | Botón `x` | **B** |
| Cambiar de app | Barra de tareas | **L / R** |
| JINE / Poketter | Iconos | **Y / X** |
| Menú Inicio (Mis imágenes, Panel de control, Reiniciar, Apagar) | Botón *Inicio* de la barra de tareas | **START** |
| Administrador de tareas (estados y gráficas) | Icono de la barra de tareas | — |
| Ver la descripción de un comando | Mantener pulsado | — |
| Stream: recoger super chat | Tocar el comentario de color | Cruceta + **A** |
| Stream: borrar comentario | Tocarlo o deslizar a la izquierda | Cruceta + **A** |
| Stream: pausar | Mantener el dedo sobre el chat | — |
| Stream: velocidad / saltar | Botones *Ritmo del directo* / *▶SKIP* | **R**, **L** / **SELECT** |
| Stream: siguiente frase | — | **A** |
| Acariciar a Ame | Frotar su cabeza en la pantalla inferior | **A** |
| Medidor de rendimiento | — | **L + R + SELECT** |

## Generar los datos y compilar (PC)

Requisitos: el juego de Steam instalado, Python 3, .NET SDK y devkitPro (3ds-dev).

```bash
# 1. extraer los assets del juego (UnityPy)
tools/.venv/Scripts/python -I tools/extract_assets.py "<juego>/Windose_Data" ../assets
tools/.venv/Scripts/python -I tools/extract_pass2.py "<juego>/Windose_Data" ../assets
# 2. traducir el código del juego a Lua
tools/cs2lua/bin/Release/net10.0/cs2lua.exe ../code/Assembly-CSharp "<juego>/Windose_Data/Managed" lua
# 3. convertir assets al formato de la 3DS
tools/.venv/Scripts/python -I tools/build_assets.py ../assets build_data
tools/.venv/Scripts/python -I tools/resolve_sound_master.py "<juego>/Windose_Data" build_data/needy3ds
tools/.venv/Scripts/python -I tools/export_anims.py "<juego>/Windose_Data" build_data/needy3ds
tools/.venv/Scripts/python -I tools/dump_prefabs.py "<juego>/Windose_Data" build_data/prefabs
tools/.venv/Scripts/python -I tools/export_ideon.py .
tools/.venv/Scripts/python -I tools/export_bank.py "<juego>/Windose_Data" build_data/needy3ds
# 4. compilar el .3dsx (en MSYS2)
./build.sh
```

## Pruebas sin consola

- `tools/pc_harness.lua`: ejecuta el juego en el PC con un bot que juega solo. Variables:
  `NGO_FAST=1` (avance rápido), `NGO_BOOST=1` (supera los hitos de seguidores para probar días
  posteriores), `NGO_TOUR=1` (recorre todas las pantallas y saca capturas en `build_data/snaps/`),
  `NGO_LANG=en|ja` (idioma), `NGO_SEED=n` (semilla del bot, para probar otros finales).
- `tools/render_snap.py`: convierte esas capturas en PNG de las dos pantallas.
- Si existe `sdmc:/3ds/needy3ds/autoplay.txt`, el port arranca una partida en la ranura 3 y se juega
  solo (para probar en emulador). Viene desactivado como `autoplay.txt.off`; renómbralo para usarlo.

Más detalles: [docs/PLAN.md](docs/PLAN.md), [docs/PANTALLAS.md](docs/PANTALLAS.md) y
[docs/EVENTOS.md](docs/EVENTOS.md).

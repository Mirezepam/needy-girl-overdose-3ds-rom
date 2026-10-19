# NEEDY GIRL OVERDOSE 3DS: plan técnico del port

Objetivo: port homebrew (`.3dsx`) jugable de principio a fin en **Old 3DS / 2DS**, con las dos pantallas,
controles táctiles adaptados e idiomas **ES / EN / JP**.

> Aviso legal: el port **no incluye ningún asset del juego**. El pipeline genera la carpeta de datos
> a partir de la copia de Steam del propio usuario. No se distribuye la carpeta `sdmc/needy3ds/`.

---

## 1. Qué hay en el juego (resultado del análisis)

| Sistema | Implementación original | Volumen |
|---|---|---|
| Bucle principal | `EventManager` + `StatusManager`: 30 días × 3 franjas (día / tarde / noche) | 1 500 líneas |
| Eventos de historia | 376 clases `NgoEvent` (guiones async) | ~12 000 líneas |
| Streams | 83 clases `LiveScenario` (listas de comentarios/frases) | ~5 000 líneas |
| Textos | Tablas maestras (`Line`, `Tweet`, `KusoComment`, `TenComment`, `SystemText`...) con 11 idiomas | ~7 000 entradas |
| Comandos | `Cmd.json`: 126 acciones con delta de stats y tiempo | |
| Finales | 26 `EndingType` | |
| Gráficos | Pixel art. Webcam y stream: sprites de **348×227**; fondos de escritorio a 1920×1080 | ~7 000 imágenes, 166 animaciones por frames |
| Audio | 142 clips WAV 44,1 kHz estéreo | 52 min |
| Vídeo | 32 vídeos `psyche` de 360×202 (20 s cada uno) + MV *INTERNET OVERDOSE* de 1920×1440 (223 s) | 14 min |

El catálogo completo de eventos, con disparadores, elecciones y stats, está en [EVENTOS.md](EVENTOS.md).
Los eventos solo usan **132 llamadas distintas** de API, y las más frecuentes son `AddJineHistory` (1 122),
`DelaySkippable` (593), `NewWindow` (281), `UpdateStatus` (161) y `StartOption` (90).

### Flujo de un día (de `EventManager.cs`)

1. Cambio de `DayIndex`: autoguardado → `FetchDayEvent()` (eventos fijos por día: día 3 alquiler,
   día 5 wishlist, 10/14/17/22/27 hitos de seguidores, 30 final según stats; si no, diálogo aleatorio).
2. El jugador elige un comando (stream, Ame, pastillas, salir, internet, dormir).
   `ExecuteAction` → evento `Action_<Cmd>` → aplica delta de `Cmd.json` → tweets de resultado →
   posible obtención de *neta* (tema de stream) → avanza `PassingTime` franjas.
3. Franja 1: monólogo. Franja 2: `FetchNightEvent()` comprueba finales por stats
   (estrés ≥ 120, yami = 0, amor = máx, amor = 0, 5 psyches...).
4. Ignorar 5 notificaciones de JINE lleva al final *Jine*.

---

## 2. Arquitectura del port

```
                 PC (una vez, con la copia del usuario)                    3DS
┌────────────────────────────────────────────────┐     ┌──────────────────────────────────────┐
│ code/ (C# descompilado)                        │     │ needy3ds.3dsx (motor en C)           │
│   └─ tools/cs2lua  (Roslyn) ─► lua/events/*.lua│ ──► │  ├─ citro2d: 2 pantallas, sprites    │
│ assets/ (UnityPy)                              │     │  ├─ ndsp + tremor: BGM ogg / SE pcm  │
│   └─ tools/build_assets.py ─► sdmc/needy3ds/   │     │  ├─ vídeo: frames ETC1 + LZ4         │
│        gfx/*.t3x  snd/*.ogg  vid/*.etcv        │     │  ├─ Lua 5.4 (corutinas = async/await)│
│        text/{es,en,ja}.bin  font/*.t3x         │     │  └─ runtime Lua: managers del juego  │
└────────────────────────────────────────────────┘     └──────────────────────────────────────┘
```

### Por qué Lua + transpilador

Los 459 guiones son C# `async` con un vocabulario reducido. Reescribirlos a mano en C serían meses y
dejaría errores en la lógica de la historia. En su lugar:

- **`tools/cs2lua`** (C# + Roslyn) recorre el árbol sintáctico de cada clase de evento y genera Lua.
  `await X` → `X` dentro de una corutina (yield implícito); `if/switch/for` → Lua;
  `SingletonMonoBehaviour<JineManager>.Instance.AddJineHistory(JineType.Foo)` → `JineManager:AddJineHistory("Foo")`.
- El patrón de elección de JINE
  (`StartOption([...])` + varios `OnChangeHistory.Where(id == X).Subscribe(...)`) se reconoce y se
  convierte en `local c = JineManager:Choose{...}; if c == "X" then ... end`.
- Los `LiveScenario` (constructores con `playing.Add(new Playing(...))`) se convierten en tablas de datos.
- La lógica central (`EventManager.FetchDayEvent/FetchNightEvent/chooseMaturo`, `NetaManager`) también se
  transpila. Así las condiciones de los 26 finales son las originales.
- Cualquier sentencia que el transpilador no entienda se emite como `TODO("...")` con el C# original
  y queda listada en un informe, para revisarla a mano.

### Memoria en Old 3DS (64 MB de aplicación)

| Bloque | Presupuesto |
|---|---|
| Motor + Lua VM + scripts (bytecode, se cargan por evento) | 6 MB |
| Textos del idioma activo | 2 MB |
| Fuente (Dinkie Bitmap 9/12 px; JP con subconjunto de kanji usados) | 1,5 MB |
| Caché de texturas (LRU, ETC1A4/RGBA5551) | 24 MB |
| Audio: buffers BGM en streaming + SE en caché | 4 MB |
| Vídeo (doble buffer de frames) | 0,2 MB |
| Margen | ~10 MB |

---

## 3. Diseño de las dos pantallas

**Pantalla superior (400×240): el mundo.**
- Webcam de Ame a escala 1:1 (348×227), con la habitación y las animaciones originales por frames.
- Barra superior: día, franja horaria, seguidores, estrés, afecto y oscuridad (yami).
- Durante el stream: la vista del stream con subtítulos (jimaku) y la animación de Ame.
- Vídeos psyche (360×202 nativo), MV final, trenes al salir, finales y pantallas de crisis.
- Notificaciones flotantes y tooltips (en el original salían al pasar el ratón).

**Pantalla inferior (320×240, táctil): el sistema operativo "Windose".**
- Una sola app a pantalla completa (ventanas a 320×240), con barra de tareas de iconos grandes abajo.
- Apps: **JINE** (chat), **Poketter** (tweets), **Tareas** (comandos: stream, Ame, pastillas, salir,
  internet, dormir), **Stats**, **Neta** (temas de stream), **Ajustes / Guardar**.
- Cuando entra un mensaje de JINE se abre solo en la inferior y la webcam sigue visible arriba.

---

## 4. Adaptación de mecánicas al táctil

| Original (ratón/teclado) | Port 3DS |
|---|---|
| Arrastrar y redimensionar ventanas | Eliminado: una app a pantalla completa; **L/R** cambia de app |
| Tooltip al pasar el ratón | **Mantener pulsado** un icono → tooltip en la pantalla superior |
| Clic en opciones de JINE | Botones grandes (≥ 40 px de alto) con el lápiz, o cruceta + **A** |
| Stamps de JINE | Cuadrícula de 4×2 stamps táctiles |
| Stream: clic en comentarios para "recogerlos" | **Tocar** comentario → se recoge (destello) |
| Stream: borrar comentarios malos | **Deslizar a la izquierda** el comentario (o mantener + B) |
| Stream: velocidad / saltar | **R** = velocidad ×2, **SELECT** = saltar (como el original) |
| Elegir neta antes del stream | Carrusel táctil de chips (alfa) + selector de tono (beta) |
| Minijuego de corte | Trazo con el lápiz sobre la zona, como el gesto de ratón original |
| Crisis (ventanas que huyen del cursor) | Las ventanas huyen del **punto de contacto** del lápiz |
| Ojos (Medama) que siguen el cursor | Siguen al lápiz; sin contacto, a la última posición |
| Lluvia de ventanas (BrowserCrasher) | Tocar para cerrar; se reparten entre ambas pantallas |
| Login / contraseña / texto libre | Teclado del sistema (`swkbd`) |
| Final Ideon (multi-ventana) | Ventanas repartidas entre las dos pantallas |
| Cursor de espera / cursor falso en finales | Sprite de cursor dibujado en la inferior cuando el guion lo pide |
| Saltar diálogo (clic) | Tocar cualquier sitio o **A** (`DelaySkippable`) |
| Atajos de teclado | **START** = menú / guardar, **X** = Poketter, **Y** = JINE |

Todo es también jugable sin lápiz: cruceta y botones, siguiendo el esquema de mando que ya tenía el
port de Switch (Rewired).

---

## 5. Formatos de datos en la 3DS

| Tipo | Formato | Motivo |
|---|---|---|
| Sprites / animaciones | `.t3x` (tex3ds), atlas por animación, RGBA5551 para pixel art y ETC1A4 para fondos grandes | La GPU los usa sin decodificar |
| Fondos de escritorio 1920×1080 | Reescalados a 320×240 / 400×240 | |
| BGM | Ogg Vorbis 32 kHz estéreo q2, en streaming | ~25 MB en total; tremor (decodificador Vorbis en enteros) en Old 3DS |
| SE | PCM16 mono 22 kHz precargado | Latencia cero |
| Vídeo | `.etcv`: frames ETC1 512×256 + LZ4, a 12 fps, con audio Ogg aparte | Coste de CPU casi nulo en Old 3DS |
| Texto | `text/<lang>.bin`: tabla id → UTF-8, con índice ordenado | Carga solo el idioma activo |
| Guardado | `sdmc:/3ds/needy3ds/save/DataN_DayX.sav` (tabla Lua serializada) | Mismos slots/días que el original |

---

## 6. Fases

| Fase | Entregable | Estado |
|---|---|---|
| 0 | Análisis, catálogo de eventos y plan | ✅ |
| 1 | Toolchain (devkitPro), esqueleto del motor: 2 pantallas, input, carga de datos desde la SD | en curso |
| 2 | Pipeline de assets: texturas, fuentes, textos, audio y vídeo | en curso |
| 3 | `cs2lua`: transpilar los 459 guiones e informar de los TODO | en curso |
| 4 | Runtime Lua: StatusManager, EventManager, JineManager, PoketterManager, WindowManager→apps | |
| 5 | **Rebanada vertical**: arranque → día 1 → comando → evento JINE con elección → noche → día 2 | |
| 6 | Streams completos (Live + comentarios táctiles + netas) | |
| 7 | Minijuegos y pantallas especiales (crisis, corte, ojos, Ideon, vídeos psyche) | |
| 8 | Los 26 finales, guardado y carga, ajustes, idiomas | |
| 9 | Optimización para Old 3DS, pruebas en hardware y en emulador (Azahar) | |

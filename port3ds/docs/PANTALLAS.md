# Uso de las dos pantallas: especificación

Principio: **arriba se mira, abajo se toca.** La pantalla superior (400×240) es el mundo de Ame
y nunca necesita input. La inferior (320×240, táctil) es el sistema operativo *Windose* y es donde
el jugador actúa. Las dos pantallas muestran siempre cosas distintas y relacionadas: nunca se
duplica contenido ni se deja una pantalla en negro.

Coordenadas en píxeles. `HUD` = barra de estado superior. `TB` = barra de tareas inferior.

## Pantalla superior: capas fijas

```
┌──────────────────────────── 400 ────────────────────────────┐
│ HUD 14px: Día 3 ☀  👥 1.234  ❤ 40  💢 5  🌙 15     [🔔2]    │
├────┬──────────────────────────────────────────────────┬─────┤
│side│                                                  │side │
│bar │        WEBCAM / ESCENA  348×226 (1:1)            │bar  │
│26px│                                                  │26px │
│    │  [toast de notificación arriba a la derecha]     │     │
│    │  [tooltip / tutorial abajo]                      │     │
└────┴──────────────────────────────────────────────────┴─────┘
```

- El arte de la webcam y del stream mide 348×227 en el original, así que se pinta a escala 1:1.
- Las barras laterales cambian de color con la franja horaria (día, tarde, noche), como el fondo del original.
- Cuando cambia un stat, la cifra del HUD parpadea y muestra `+N` / `-N` (el `TaskManager` del original).

## Estados del juego

| Estado | Pantalla superior | Pantalla inferior (táctil) |
|---|---|---|
| **Arranque / login** | BIOS y logo de Windose; después vista previa de la webcam | Selector de partida (3 ranuras) y botón *Iniciar sesión* |
| **Escritorio** (hub) | HUD + webcam con la animación de Ame según sus stats | Fondo de escritorio, iconos grandes (JINE, Poketter, Acciones, Netas, Internet, Ajustes) y TB con apps abiertas |
| **JINE** (chat) | La webcam sigue arriba. Cuando Ame escribe, sale *escribiendo…* y su última frase como subtítulo | Historial con burbujas (arrastrar para desplazar). Opciones en botones grandes. Stickers en cuadrícula 4×2 |
| **Acciones** (comandos) | Al mantener pulsado un comando, el tooltip con descripción y efecto previsto sale **arriba**, sin tapar los dedos | Categorías (Directo, Ame, Pastillas, Internet, Salir, Dormir), después lista de comandos |
| **Confirmar paso de tiempo** | Atenuada, con el texto *"¿Pasará el tiempo?"* | Diálogo modal Sí / No |
| **Resultado de una acción** | Animación de la acción (salir en tren, dormir, juego...) | Poketter en modo resultado: los tweets "se publican" uno a uno con sus respuestas |
| **Elegir neta** (tema del stream) | Previsualización: título del stream, nivel y efecto esperado | Carrusel de chips de neta (tocar) y selector de tono |
| **Stream** | Vista del stream: fondo, Ame animada, subtítulos (jimaku), título, espectadores y super chats | Chat en vivo: **tocar** un comentario lo recoge (máx. 2), **deslizar a la izquierda** borra un comentario malo, botón **Leer**, velocidad (R) y saltar |
| **Poketter / Internet** | Tweet o hilo seleccionado ampliado. Las **imágenes de los tweets se ven arriba a tamaño completo** | Lista de tweets / hilos / resultados de egosearch |
| **Eventos con ventanas** (diario, correo, documentos) | Ilustración del evento o la webcam reaccionando | Lector de documento con paso de página deslizando |
| **Llamada** (Amecalling) | Ame al teléfono (animación) | Pantalla de llamada entrante con *Responder* |
| **Vídeo psicodélico** | Vídeo 360×202 a pantalla completa | Escritorio distorsionado; tocar para continuar |
| **Crisis (Hakkyo / horror)** | Glitches, la webcam se corrompe | Las ventanas **huyen del lápiz**; los ojos (Medama) siguen el punto de contacto |
| **Lluvia de ventanas / Ideon** | Ventanas emergentes en la pantalla superior | Más ventanas; tocar para cerrarlas |
| **Final** | Escena final, vídeo o animación | Texto del final, *"Final conseguido"*, lista de finales vistos |
| **Pausa (START)** | Webcam atenuada con *PAUSA* | Guardar, cargar, idioma, velocidad del stream, volumen, salir |

## Reglas de interacción

1. **Todo lo que se toca está abajo.** Arriba no hay botones. Si un evento del original abre una ventana
   interactiva, se abre en la inferior y su contenido visual va arriba.
2. **Lo que se lee largo va arriba si es contenido** (imagen de un tweet, vídeo, escena) y **abajo si
   es interfaz** (lista, chat, menú).
3. **Tooltips arriba.** Mantener pulsado (0,5 s) cualquier icono o comando muestra su explicación
   en la superior. Es el equivalente táctil del *hover* del ratón.
4. **Notificaciones**: toast arriba y globo con contador en el icono de la app abajo. Tocar el
   globo abre la app.
5. **Avanzar texto** (`DelaySkippable`): tocar cualquier punto de la inferior o pulsar **A**.
6. **Botones físicos**:
   - A: confirmar · B: atrás · Cruceta / Circle Pad: mover el foco
   - L / R: app anterior / siguiente (en el stream, R = velocidad)
   - X: Poketter · Y: JINE · START: pausa · SELECT: saltar stream / registro
7. Tamaño mínimo de objetivo táctil: **32×32 px** (opciones de JINE: 300×36).

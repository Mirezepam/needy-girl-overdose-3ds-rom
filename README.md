# NEEDY GIRL OVERDOSE — extracción para estudio

Origen: instalación de Steam (`Windose.exe`, Unity 2022.3, backend **Mono**, sin ofuscar).
Material con copyright de WSS playground / xemono. Solo para uso académico personal; no redistribuir.

## Estructura

| Carpeta | Contenido |
|---|---|
| `code/Assembly-CSharp/` | Proyecto C# descompilado (ILSpy 11.1) de la lógica del juego. ~1.300 `.cs` |
| `code/Assembly-CSharp-firstpass/`, `Ngo.Effect.*`, `Kyub.EmojiSearch` | Resto de assemblies propias |
| `assets/Texture2D`, `assets/Sprite` | Imágenes PNG (rutas de Addressables cuando existen) |
| `assets/AudioClip` | Música y SFX en WAV (decodificados desde FMOD) |
| `assets/VideoClip` | 33 vídeos `.m4v` (psyche*, INTERNETOVERDOSE, ...) |
| `assets/Font` | Fuentes TTF/OTF |
| `assets/MonoBehaviour` | Datos serializados en JSON, incluidas las tablas maestras |
| `assets/AnimationClip`, `AnimatorController`, `GameObject`, `Material`, `MonoScript`, `Mesh`, `PlayableDirector` | Volcados JSON de typetree |
| `assets/_extract_report*.json` | Recuentos y errores de cada pasada |
| `raw_data/` | `.es3` (Easy Save 3) por día, `Settings.es3`, catálogo de Addressables, configuración de arranque |

## Tablas de datos clave (`assets/MonoBehaviour/`)

Textos en JP/EN/CN/KO/TW: `Line.json` (diálogos de Ame), `Tweet.json`, `KusoComment.json`,
`TenComment.json`, `MobComment.json`, `Egosa.json`, `Ending.json`, `SystemText.json`,
`Tooltip.json`, `Act.json`, `Cmd.json`, `Kitune.json`, `KRep.json`, `statuses.json`,
`SoundMaster.json`, `ResourceLocalMaster.json`, `yakujo.json`.

Las clases que las cargan están en `code/Assembly-CSharp/*Master.cs` y los enums de IDs en `code/Assembly-CSharp/NGO/`.

## Código: puntos de entrada

`code/Assembly-CSharp/ngov3/` (797 archivos) contiene el juego: `EventManager`, `StatusManager`,
`WindowManager*`, `JineManager` (chat), `PoketterManager` (red social), `Live.cs` (streams),
`EndingManager`, `CommandManager`, `AudioManager`, `NgoEx.cs` (utilidades).

## Limitaciones conocidas

- ~170 MonoBehaviour (≈1 %) no se pudieron deserializar (fallo de typetree); 17 texturas vacías sin datos.
- No se exportaron shaders compilados ni escenas como proyecto Unity reabrible (para eso: AssetRipper).

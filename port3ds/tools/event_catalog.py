"""Build a catalog of every NgoEvent / LiveScenario class in the decompiled game.

usage: python -I event_catalog.py <decompiled Assembly-CSharp dir> <out.json> <out.md>
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict

SRC, OUT_JSON, OUT_MD = sys.argv[1:4]
NGO = os.path.join(SRC, "ngov3")

CATEGORIES = [
    ("Action_", "Acción de comando"),
    ("ChipGet_", "Obtener neta (tema de stream)"),
    ("Netatip_", "Guion de stream"),
    ("Ending_", "Final"),
    ("Scenario_", "Escenario de historia"),
    ("Event_", "Evento"),
    ("YamiHi_", "Día oscuro / amor"),
    ("Status_", "Estrés"),
    ("StressHi", "Estrés"),
    ("haishin_", "Stream especial"),
    ("Haishin", "Stream especial"),
    ("Kenjo", "Escenario de historia"),
    ("TimePassing", "Sistema"),
]

# APIs whose presence means the event needs a touch-specific redesign
TOUCH_FLAGS = {
    "WristcutManager": "minijuego de corte (gesto con lápiz)",
    "InputField": "entrada de texto (teclado en pantalla)",
    "OnDrag": "arrastrar",
    "OnPointerDown": "pulsar/mantener",
    "CursorManager": "cursor del ratón",
    "Hakkyo": "pantalla de crisis (ventanas que huyen del cursor)",
    "Medama": "ojos que siguen el cursor",
    "BrowserCrasher": "lluvia de ventanas",
    "MediaPlayer": "reproductor de vídeo",
    "Psyche": "vídeo psicodélico",
    "Calling": "llamada entrante",
    "Webcam": "webcam de Ame",
    "Ideon": "multi-ventana final",
}

call_re = re.compile(r"(?:SingletonMonoBehaviour<(\w+)>|(AudioManager))\.Instance\??\.(\w+)")
enum_re = re.compile(r"\b(JineType|TweetType|AppType|SoundType|StatusType|CmdType|EndingType|AlphaType)\.(\w+)")


def classify(name):
    for prefix, cat in CATEGORIES:
        if name.startswith(prefix):
            return cat
    return "Otro"


def main():
    events = []
    for fn in sorted(os.listdir(NGO)):
        if not fn.endswith(".cs"):
            continue
        text = open(os.path.join(NGO, fn), encoding="utf-8").read()
        m = re.search(r"public class (\w+) : (NgoEvent|LiveScenario)\b", text)
        if not m:
            continue
        name, base = m.groups()
        calls = Counter(f"{a or b}.{c}" for a, b, c in call_re.findall(text))
        enums = defaultdict(set)
        for k, v in enum_re.findall(text):
            enums[k].add(v)
        status = re.findall(r"UpdateStatus\(StatusType\.(\w+), (-?\d+)\)", text)
        options = len(re.findall(r"StartOption\(", text))
        flags = sorted({desc for key, desc in TOUCH_FLAGS.items() if key in text})
        triggers = sorted(set(re.findall(r"AddEvent(?:Queue)?<(\w+)>", text)) |
                          set(re.findall(r'AddEvent(?:Queue)?\("(\w+)"', text)))
        events.append({
            "name": name,
            "base": base,
            "category": "Guion de stream" if base == "LiveScenario" else classify(name),
            "lines": text.count("\n"),
            "jine_lines": calls.get("JineManager.AddJineHistory", 0),
            "choices": options,
            "tweets": calls.get("PoketterManager.AddQueueWithKusoreps", 0) + calls.get("PoketterManager.AddTweet", 0),
            "status_changes": status,
            "windows": sorted(enums.get("AppType", [])),
            "sounds": sorted(enums.get("SoundType", [])),
            "chains_to": triggers,
            "touch_notes": flags,
            "unique_api": sorted(calls),
        })
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(events, f, ensure_ascii=False, indent=1)

    api = Counter()
    for e in events:
        api.update(e["unique_api"])
    bycat = defaultdict(list)
    for e in events:
        bycat[e["category"]].append(e)
    md = ["# Catálogo de eventos de NEEDY GIRL OVERDOSE", "",
          f"Generado automáticamente desde el código descompilado: **{len(events)} clases**.", "",
          "| Categoría | Nº | Líneas C# |", "|---|---|---|"]
    for cat, es in sorted(bycat.items(), key=lambda kv: -len(kv[1])):
        md.append(f"| {cat} | {len(es)} | {sum(e['lines'] for e in es)} |")
    md += ["", "## API distintas usadas por los eventos (a implementar en el runtime Lua)", "",
           f"{len(api)} métodos/propiedades.", "", "| API | eventos que la usan |", "|---|---|"]
    md += [f"| `{k}` | {v} |" for k, v in api.most_common()]
    md += ["", "## Eventos que necesitan adaptación táctil", ""]
    for e in events:
        if e["touch_notes"]:
            md.append(f"- **{e['name']}**: {', '.join(e['touch_notes'])}")
    for cat, es in sorted(bycat.items()):
        md += ["", f"## {cat}", "", "| Evento | líneas | JINE | elecciones | tweets | stats | encadena |", "|---|---|---|---|---|---|---|"]
        for e in es:
            st = " ".join(f"{s}{'+' if int(v) >= 0 else ''}{v}" for s, v in e["status_changes"][:6])
            md.append(f"| {e['name']} | {e['lines']} | {e['jine_lines']} | {e['choices']} | {e['tweets']} | {st} | {', '.join(e['chains_to'][:4])} |")
    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print(len(events), "events;", len(api), "distinct APIs")


main()

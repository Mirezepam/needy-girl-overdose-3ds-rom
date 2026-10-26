"""Fires every event of the game on its own (pc_harness NGO_EVENT) and reports errors and hangs.

Each event runs in a fresh harness process on an idle day 2: the bot answers the event's JINE,
dialogs and notifications but starts nothing else, so one event cannot spoil the next.
usage: python test_events.py <lua54.exe> [event ...] [-j N]
"""
import io
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
args = sys.argv[1:]
jobs = 8
if "-j" in args:
    i = args.index("-j")
    jobs = int(args[i + 1])
    del args[i:i + 2]
LUA, only = args[0], args[1:]

catalog = json.load(open(os.path.join(ROOT, "docs", "event_catalog.json"), encoding="utf-8"))
events = [e["name"] for e in catalog]
# stream scripts are not queued events: they play inside a stream, so the stream's scenario
# choice is pointed at them and a normal stream is started
SCENARIO = {e["name"] for e in catalog if e["base"] == "LiveScenario"}
if only:
    events = [e for e in events if e in only]


def run(name):
    env = {k: v for k, v in os.environ.items()
           if k not in ("NGO_TOUR", "NGO_INJECT", "NGO_EVAL", "NGO_CONT", "NGO_LINT", "NGO_BOOST", "NGO_LANG")}
    env.update(NGO_FAST="1", NGO_SEED="3", NGO_EVENT=name)
    if name in SCENARIO:
        env["NGO_INJECT"] = ('rawset(_G, "BOT_HOLD", 1e9); NotificationManager.items = {}; '
                             'Live.SetScenario_1 = function(self) return self:SetScenario_3("%s") end; '
                             'EventManager:StartHaishin("Zatudan", 1, "none"); return "%s"' % (name, name))
    try:
        p = subprocess.run([LUA, "tools/pc_harness.lua", ".", "200000", "31"], cwd=ROOT, env=env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        out = p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return name, "TIMEOUT", 0, ""
    errs = [l for l in out.splitlines() if "[error]" in l or l.startswith("ERROR:")]
    if "ENDING DIALOG" in out:
        status = "ENDING"
    elif "EVENT_DONE" in out:
        status = "DONE"
    elif "EVENT_NOSTART" in out:
        status = "NOSTART"
    elif "EVENT_HANG" in out:
        status = "HANG"
    else:
        status = "STOPPED"
    return name, status, len(errs), (errs[0].strip()[:220] if errs else "")


with ThreadPoolExecutor(jobs) as ex:
    results = list(ex.map(run, events))

bad = 0
for name, status, nerr, first in results:
    flag = nerr or status in ("HANG", "TIMEOUT", "STOPPED")
    bad += bool(flag)
    if flag or "-v" in sys.argv:
        print(f"{name:52} {status:8} errors={nerr}" + (f"\n    {first}" if first else ""))
counts = {}
for _, status, _, _ in results:
    counts[status] = counts.get(status, 0) + 1
print(f"\n{len(results)} events: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) + f" | with problems: {bad}")

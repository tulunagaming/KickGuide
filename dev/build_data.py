"""
Erzeugt Data.lua (Addon-Wurzel) aus den gesammelten Wowhead-Daten in data/*.json.

Bereinigung:
* NPCs, die in mehreren Dungeons vorkommen (Affixe, Begleiter, Trainingspuppen,
  Xal'atath ...), fliegen raus - Wowhead ordnet sie jeder Zone zu.
* dazu eine feste Sperrliste (EXCLUDE) fuer Einzelfaelle
* NPCs ohne Zauber fliegen raus
* Zauber-IDs je NPC doppelt entfernt, sortiert

Ob ein Zauber "wichtig" ist, steht NICHT in den Daten - das entscheidet im Spiel
C_Spell.IsSpellImportant. Deshalb duerfen die Daten alle Faehigkeiten enthalten.

Aufruf:  python build_data.py
"""
import csv
import glob
import re
import io
import json
import os
import urllib.request
from collections import Counter
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)

# Einzelne NPCs, die nicht zum Dungeon gehoeren (Wowhead-Zuordnung).
EXCLUDE = {
    126632,   # Corbyn (Haendler)
    199057,   # Herausforderungspuppe
    228224,   # Fenryr (Begleiter)
    229227, 230937, 236933,   # Xal'atath (Affix)
}

# Karten-IDs (uiMapID) der Dungeonebenen, fuer "aktueller Dungeon".
UIMAPS = {
    588: [2588, 2589, 2590],   # Altar of Fangs
    586: [2513, 2514, 2564],   # Den of Nalorakk
    587: [2433, 2434, 2435],   # Murder Row
    584: [2500],               # The Blinding Vale
    585: [2572, 2573, 2574],   # Voidscar Arena
    399: [2094, 2095],         # Ruby Life Pools
    250: [1038, 1043],         # Temple of Sethraliss
    249: [1004],               # Kings' Rest
}

# Kickbar? Aus Blizzards Spieldaten (Export von wago.tools):
# SpellCategories.PreventionType Bit 1 (Silence) = durch Kick unterbrechbar.
# Gegen MDT abgeglichen (785 Zauber, 7 Dungeons): 59/60 kickbare und 723/724
# nicht kickbare stimmen überein. Zauber ohne Bit mit Zauberzeit oder
# Kanalisierung = "kein Kick"; Sofortzauber ohne Bit = keine Angabe.
CACHE = os.path.join(ROOT, "dev", "cache")
WAGO = "https://wago.tools"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"}
CHANNELED = 0x44          # Attributes_1: IS_CHANNELLED | IS_SELF_CHANNELLED
DIFFICULTY_ORDER = {8: 0, 23: 1, 0: 2}   # Mythisch+ vor Mythisch vor Standard


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180).read()


def db2(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name + ".csv")
    if not os.path.exists(path):
        io.open(path, "wb").write(fetch("%s/db2/%s/csv" % (WAGO, name)))
    return path


def game_build():
    path = os.path.join(CACHE, "build.json")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        io.open(path, "wb").write(fetch(WAGO + "/api/builds/wow/latest"))
    return json.load(io.open(path, encoding="utf-8"))["version"]


def kick_table(spell_ids):
    def pick(rows):
        return sorted(rows, key=lambda r: DIFFICULTY_ORDER.get(int(r["DifficultyID"]), 9))[0] if rows else None
    cats, miscs = {}, {}
    for r in csv.DictReader(io.open(db2("SpellCategories"), encoding="utf-8")):
        if int(r["SpellID"]) in spell_ids:
            cats.setdefault(int(r["SpellID"]), []).append(r)
    for r in csv.DictReader(io.open(db2("SpellMisc"), encoding="utf-8")):
        if int(r["SpellID"]) in spell_ids:
            miscs.setdefault(int(r["SpellID"]), []).append(r)
    cast_times = {int(r["ID"]): int(r["Base"]) for r in csv.DictReader(io.open(db2("SpellCastTimes"), encoding="utf-8"))}
    result = {}
    for sid in spell_ids:
        cat, misc = pick(cats.get(sid)), pick(miscs.get(sid))
        prevention = int(cat["PreventionType"]) if cat else 0
        if prevention & 1:
            result[sid] = True
        elif misc:
            cast = cast_times.get(int(misc["CastingTimeIndex"]), 0)
            if cast > 0 or int(misc["Attributes_1"]) & CHANNELED:
                result[sid] = False
    return result


# Mob-Eigenschaften (was wirkt: Stun, Unterbrechen, Verlangsamen ...) stehen
# nicht in den Spieldaten, sondern auf Blizzards Servern. Quelle: Mythic Dungeon
# Tools von Nnoggie (GPL-2.0), dungeonEnemies[..].characteristics. Hat MDT einen
# Mob mit Eigenschaften-Liste, aber ohne "Stun", gilt er als stun-immun.
MDT_DIR = os.environ.get("MDT_DIR", r"C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/MythicDungeonTools/Midnight")


def mdt_characteristics():
    result, sources = {}, {}
    for path in sorted(glob.glob(os.path.join(MDT_DIR, "*.lua"))):
        text = io.open(path, encoding="utf-8").read()
        m = re.search(r"mapID = (\d+)", text)
        start = text.find("MDT.dungeonEnemies[dungeonIndex]")
        if not m or start < 0:
            continue
        body = text[start:]
        # Gegnerblöcke: "  [n] = {" auf zweiter Ebene
        blocks = re.split(r"\n  \[\d+\] = \{\n", body)[1:]
        for block in blocks:
            idm = re.search(r'\["id"\] = (\d+),', block)
            if not idm:
                continue
            chars = re.search(r'\["characteristics"\] = \{(.*?)\n    \},', block, re.S)
            if not chars:
                continue
            keys = set(re.findall(r'\["([^"]+)"\] = true', chars.group(1)))
            npc = int(idm.group(1))
            result.setdefault(npc, set()).update(keys)
            sources[npc] = int(m.group(1))
    return result, sources


files = sorted(glob.glob(os.path.join(ROOT, "data", "*.json")))
dungeons = [json.load(io.open(f, encoding="utf-8")) for f in files]

seen = Counter()
for d in dungeons:
    for npc_id in {n["id"] for n in d["npcs"]}:
        seen[npc_id] += 1
shared = {npc_id for npc_id, count in seen.items() if count > 1}


def cluster(points, radius=4.0):
    """Nahe Punkte (eine Mobgruppe, Laufweg) zu einem Punkt zusammenfassen."""
    groups = []
    for x, y in points:
        best, best_d = None, radius
        for g in groups:
            d = ((g[0] - x) ** 2 + (g[1] - y) ** 2) ** 0.5
            if d <= best_d:
                best, best_d = g, d
        if best:
            best[2] += x; best[3] += y; best[4] += 1
            best[0], best[1] = best[2] / best[4], best[3] / best[4]
        else:
            groups.append([x, y, x, y, 1])
    return sorted((round(g[0]), round(g[1])) for g in groups)


def lua_map(floors):
    parts = []
    for floor in sorted(floors or {}, key=int):
        pts = cluster(floors[floor])
        if pts:
            parts.append("[%d] = { %s }" % (int(floor), ", ".join("{ %d, %d }" % p for p in pts)))
    return "{ " + ", ".join(parts) + " }"


def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


out = [
    "-- Automatisch erzeugt von dev/build_data.py aus Wowhead-Daten - nicht von Hand aendern.",
    "-- Je Keystone-Karte: Gegner mit Namen (de/en), Modell-ID fuer das Bild und allen",
    "-- Zauber-IDs laut Wowhead. Welche Zauber wichtig sind, entscheidet im Spiel",
    "-- C_Spell.IsSpellImportant. ns.CC stammt aus Mythic Dungeon Tools (GPL-2.0). map = { [Wowhead-Ebene] = { {x, y}, ... } } in Prozent,",
    "-- ein Punkt je Mobgruppe.",
    "",
    "local ADDON_NAME, ns = ...",
    "",
    'ns.DATA_SOURCE = "Wowhead + Blizzard-Spieldaten %s, Stand %s"' % (game_build(), date.today().isoformat()),
    "",
    "ns.DUNGEONS = {",
]
report = []
for d in sorted(dungeons, key=lambda x: x["map"]):
    kept = []
    dropped = []
    for n in d["npcs"]:
        spells = sorted(set(n.get("spells") or []))
        if n["id"] in EXCLUDE or n["id"] in shared or not spells:
            dropped.append(n.get("en"))
            continue
        kept.append((n, spells))
    kept.sort(key=lambda x: (x[0].get("boss", False), x[0].get("en") or ""))
    uimaps = ", ".join(str(u) for u in UIMAPS.get(d["map"], []))
    out.append("    [%d] = { key = %s, en = %s, zone = %d, uimaps = { %s }, npcs = {" % (
        d["map"], lua_str(d["key"]), lua_str(d.get("en")), d["zone"], uimaps))
    for n, spells in kept:
        out.append("        { id = %d, de = %s, en = %s, boss = %s, display = %d, spells = { %s }, map = %s }," % (
            n["id"], lua_str(n.get("de")), lua_str(n.get("en")), "true" if n.get("boss") else "false",
            int(n.get("display") or 0), ", ".join(str(s) for s in spells), lua_map(n.get("floors"))))
    out.append("    } },")
    report.append("%-4s %3d NPCs uebernommen, %2d verworfen: %s" % (d["key"], len(kept), len(dropped), ", ".join(dropped)))
out.append("}")

all_spells = set()
for line in out:
    if "spells = {" in line:
        part = line.split("spells = {")[1].split("}")[0]
        all_spells.update(int(x) for x in part.replace(",", " ").split())
kicks = kick_table(all_spells)
out.append("")
out.append("-- Kickbar laut Spieldaten: true = Kick, false = Zauberzeit/Kanal, aber kein Kick.")
out.append("ns.KICK = {")
ids = sorted(kicks)
for i in range(0, len(ids), 8):
    out.append("    " + " ".join("[%d] = %s," % (sid, "true" if kicks[sid] else "false") for sid in ids[i:i + 8]))
out.append("}")
cc, _ = mdt_characteristics()
kept_npcs = set()
for line in out:
    m = re.match(r"\s*\{ id = (\d+),", line)
    if m:
        kept_npcs.add(int(m.group(1)))
out.append("")
out.append("-- Was bei einem Mob wirkt (Stun, Unterbrechen, ...). Quelle: Mythic Dungeon Tools")
out.append("-- von Nnoggie, GPL-2.0. Kein Eintrag = unbekannt.")
out.append("ns.CC = {")
matched = sorted(n for n in kept_npcs if n in cc)
for npc in matched:
    out.append("    [%d] = { %s }," % (npc, ", ".join('["%s"] = true' % k for k in sorted(cc[npc]))))
out.append("}")
report.append("CC-Angaben (MDT): %d von %d Gegnern, davon stunbar %d" % (
    len(matched), len(kept_npcs), sum(1 for n in matched if "Stun" in cc[n])))
report.append("Kick-Angaben: %d kickbar, %d nicht kickbar, %d Sofort/ohne Angabe" % (
    sum(1 for v in kicks.values() if v), sum(1 for v in kicks.values() if not v), len(all_spells) - len(kicks)))

io.open(os.path.join(ROOT, "Data.lua"), "w", encoding="utf-8", newline=NL).write(NL.join(out) + NL)
print(NL.join(report))
print("Data.lua geschrieben:", len(dungeons), "Dungeons")

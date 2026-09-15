"""
KickGuide: Fenster, Dungeon-Kacheln, Liste nur wichtiger Caster (Blizzard-Markierung),
Bosse, Zauber mit Totenkopf und Beschreibung, Zusammenfassen gleichnamiger Zauber,
Gruppen auf-/zuklappen, Liste einklappen, Instanz (geheime Werte), echte Data.lua.

Aufruf:  python test_guide.py [Pfad zum Addon-Ordner]
"""
import os
import sys
from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(HERE)
HARNESS = os.path.join(HERE, "kickguide_test.lua")
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print("  [%s] %s%s" % ("OK" if ok else "FEHLER", name, ("  -- " + str(detail)) if detail else ""))


TEST = """
SPELLS = {
  [1] = { "Massen-Giftschlag", 101, "Vergiftet alle Spieler.", true },
  [2] = { "Massen-Giftschlag", 101, "", false },
  [3] = { "Entwicklung", 102, "Wird staerker.", false },
  [4] = { "Betaeubt", 103, "", false },
  [5] = { "Stechendes Zischen", 104, "Bringt Spieler zum Schweigen.", true },
  [6] = { "Biss", 105, "Beisst.", false },
  [7] = { "Todesrasseln", 106, "Tod allen.", true },
}
TEST_KICK = { [1] = true, [2] = false, [5] = false, [7] = false }
TEST_CC = { [11] = { Stun = true, Taunt = true }, [13] = { Taunt = true } }
TEST_DATA = {
  [588] = { key = "AOF", en = "Altar of Fangs", npcs = {
    { id = 10, de = "Hochevolutionaer", en = "High Evolutionist", boss = false, display = 146663, spells = { 1, 2, 3, 4 } },
    { id = 11, de = "Urtuemliche Schlange", en = "Primal Serpent", boss = false, display = 146653, spells = { 5 } },
    { id = 12, de = "Nager", en = "Gnawer", boss = false, display = 1, spells = { 6 } },
    { id = 13, de = "Das windende Knaeuel", en = "The Writhing Coil", boss = true, display = 2, spells = { 7, 6 } },
  } },
  [586] = { key = "DON", en = "Den of Nalorakk", npcs = {
    { id = 20, de = "Harmlos", en = "Harmless", boss = false, display = 3, spells = { 6 } },
  } },
}
"""


def boot(pre=TEST, addon_dir=ADDON_DIR):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ADDON_DIR = addon_dir
    lua.execute(pre)
    api = lua.execute(open(HARNESS, encoding="utf-8").read())
    api.fire("ADDON_LOADED", "KickGuide")
    return lua, g, api


def shown(lua, cond):
    return [f for f in lua.eval("function(src) local t = load('local f = ... return ' .. src) local o = {}"
                                " for _, f in ipairs(ALL) do if f.shown and t(f) then table.insert(o, f) end end return o end")(cond).values()]


def visible_chain(f):
    p = f
    while p is not None:
        if p.shown is False:
            return False
        p = p.parent
    return True


print("\nOeffnen und Kacheln")
lua, g, api = boot()
g.SlashCmdList.KICKGUIDE("")
w = g.KickGuideFrame
check("/kg oeffnet das Fenster", w is not None and w.shown is True)
cells = [f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]
check("Kacheln in Spielreihenfolge, deutsche Namen, Bild", [c.mapID for c in cells] == [588, 586]
      and cells[0].short.text == "AOF" and cells[0].icon.texture == 1588)
check("Kacheln in einer Reihe unter der Ueberschrift", all(c.points[1][5] == -40 and c.points[1][4] == 16 + i * 46
      for i, c in enumerate(cells)), [(c.points[1][4], c.points[1][5]) for c in cells])
check("erster Dungeon gewaehlt, Streifen", cells[0].selMark.shown is True and cells[1].selMark.shown is False)

print("\nListe")
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
names = [r.name.text for r in rows]
check("nur Caster mit wichtigem Zauber, Bosse getrennt", names == ["Hochevolutionaer", "Urtuemliche Schlange", "Das windende Knaeuel"], names)
check("Nager ohne wichtigen Zauber fehlt", "Nager" not in names)
check("Zahl der wichtigen Zauber mit Totenkopf", rows[0].count.text == 1 and rows[0].skull.shown is True
      and rows[0].skull.texture.endswith("UI-RaidTargetingIcon_8"))
check("Bild aus Modell-ID", rows[0].portrait.texture == "display:146663")
headers = [f for f in shown(lua, "rawget(f, 'key') ~= nil and rawget(f, 'toggle') ~= nil")]
check("Gruppenkoepfe mit Anzahl", sorted(h.text.text for h in headers) == ["Bosse (1)", "Wichtige Caster (2)"])
d = w.detail
check("beim Oeffnen erster Caster automatisch gewaehlt", d.hint.shown is False and d.portrait.shown is True
      and d.name.text == "Hochevolutionaer" and rows[0].mark.shown is True)

print("\nDetail")
rows[0].scripts.OnClick(rows[0])
check("Name, Bild, Dungeon und Art", d.name.text == "Hochevolutionaer" and d.portrait.texture == "display:146663"
      and d.sub.text == "Altar der Fänge  ·  Trash")
spells = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("gleichnamige Zauber zusammengefasst, wichtige zuerst", [s.name.text for s in spells]
      == ["Massen-Giftschlag", "Betaeubt", "Entwicklung"], [s.name.text for s in spells])
check("wichtiger Zauber: Totenkopf, Beschreibung des wichtigen, Tooltip-ID", spells[0].skull.shown is True
      and spells[0].desc.text == "Vergiftet alle Spieler." and spells[0].spellID == 1 and "Wichtig" in spells[0].tag.text)
check("kickbar: Angabe des wichtigen Zaubers zaehlt (gruen)", "|cff33dd55Kick|r" in spells[0].tag.text
      and "Kein" not in spells[0].tag.text, spells[0].tag.text)
check("Zauber ohne Kick-Angabe: kein Hinweis", spells[2].tag.text == "", spells[2].tag.text)
luak, gk, apik = boot(TEST.replace("TEST_KICK = { [1] = true, [2] = false", "TEST_KICK = { [1] = false, [2] = true"))
grp = [x for x in apik.ns.SpellGroups(apik.ns.DUNGEONS[588].npcs[1]).values() if x.name == "Massen-Giftschlag"][0]
check("wichtiger Zauber nicht kickbar, Nebenzauber schon: 'Kein Kick'", grp.kick is False)
luau, gu, apiu = boot(TEST.replace("[11] = { Stun = true, Taunt = true }, ", ""))
check("Mob unbekannt: nur 'Kein Kick'", apiu.ns.Stunnable(apiu.ns.DUNGEONS[588].npcs[2]) is None
      and apiu.ns.Stunnable(apiu.ns.DUNGEONS[588].npcs[4]) is False)
check("normaler Zauber: ohne Totenkopf, ausgegraut", spells[2].skull.shown is False and spells[2].icon.desaturated is True)
check("ohne Beschreibung: Hinweis", spells[1].desc.text == "Keine Beschreibung.")
check("geladene Zauber: kein endloses Neuaufbauen", g.MAX_DEPTH <= 1, g.MAX_DEPTH)

lua2, g2, api2 = boot(TEST + "; UNCACHED = { [3] = true, [4] = true }")
g2.SlashCmdList.KICKGUIDE("")
r2 = [f for f in shown(lua2, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
r2[0].scripts.OnClick(r2[0])
loads = g2.LOADERS
g2.FinishSpellLoads()
check("nicht geladene Zauber: einmal angefordert, nach dem Laden einmal erneuert", loads == 2 and g2.MAX_DEPTH <= 1
      and (g2.LOADERS or 0) == loads, (loads, g2.MAX_DEPTH, g2.LOADERS))
check("keine Schriftfehler", len(list(g.PROBLEMS.values())) == 0, list(g.PROBLEMS.values()))

s11 = [r for r in [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)] if r.npc.id == 11][0]
s11.scripts.OnClick(s11)
sp11 = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("nicht kickbar: orange 'Kein Kick'", "|cffff8c1aKein Kick|r" in sp11[0].tag.text and "Wichtig" in sp11[0].tag.text, sp11[0].tag.text)
check("Kein Kick, Mob stunbar: gruen 'Stun'", sp11[0].tag.text.endswith("Kein Kick|r · |cff33dd55Stun|r"), sp11[0].tag.text)
boss = [r for r in [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)] if r.npc.id == 13][0]
boss.scripts.OnClick(boss)
spb = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("Kein Kick, Mob ohne Stun: rot 'stun-immun'", [s.tag.text for s in spb if s.spellID == 7][0].endswith("· |cffff4040stun-immun|r"),
      [s.tag.text for s in spb])

row7 = [s for s in spb if s.spellID == 7][0]
row7.scripts.OnMouseUp(row7, "LeftButton")
check("Linksklick oeffnet kein Menue", g.MENU is None)
row7.scripts.OnMouseUp(row7, "RightButton")
menu = g.MENU
radios = list(menu.radios.values())
check("Rechtsklick auf Zauberzeile: Menue mit Name und drei Optionen, 'keine Angabe' gewaehlt",
      menu.title == "Das windende Knaeuel" and [r.text for r in radios] == ["Stunbar", "stun-immun", "Keine eigene Angabe (MDT-Daten, falls vorhanden)"]
      and [r.isSelected(r.data) for r in radios] == [False, False, True])
radios[0].setSelected(radios[0].data)
spb = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("eigene Markierung 'stunbar' schlaegt MDT, gespeichert", [s.tag.text for s in spb if s.spellID == 7][0].endswith("· |cff33dd55Stun|r")
      and g.KickGuideDB.stun[13] is True)
g.MENU = None
d.stunTarget.scripts.OnClick(d.stunTarget)
radios = list(g.MENU.radios.values())
check("Rechtsklick aufs Bild: gleiches Menue, Markierung sichtbar", [r.isSelected(r.data) for r in radios] == [True, False, False])
radios[2].setSelected(radios[2].data)
spb = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("'keine eigene Angabe': wieder MDT (stun-immun)", [s.tag.text for s in spb if s.spellID == 7][0].endswith("· |cffff4040stun-immun|r")
      and g.KickGuideDB.stun[13] is None)
radios[1].setSelected(radios[1].data)
s11 = [r for r in [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)] if r.npc.id == 11][0]
check("Markierung gilt je Gegner", api.ns.Stunnable(s11.npc) is True and api.ns.Stunnable(boss.npc) is False)
radios[2].setSelected(radios[2].data)
first = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)][0]
first.scripts.OnClick(first)

print("\nAufklappen")
casters = [h for h in headers if h.key == "casters"][0]
casters.scripts.OnClick(casters)
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
check("Wichtige Caster zugeklappt: nur Boss sichtbar, Plus-Symbol", [r.name.text for r in rows] == ["Das windende Knaeuel"]
      and casters.toggle.texture.endswith("UI-PlusButton-Up"))
check("Auswahl bleibt trotz zugeklappter Gruppe", d.name.text == "Hochevolutionaer")
check("gespeichert", g.KickGuideDB.collapsed.casters is True)
casters.scripts.OnClick(casters)
check("wieder aufgeklappt", len([f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]) == 3)

print("\nKompakte Liste")
w.collapseButton.scripts.OnClick(w.collapseButton)
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
check("kompakt: schmale Liste, nur Bild und Totenkopf, gespeichert", g.KickGuideDB.listMode == "compact"
      and w.list.width == 52 and len(rows) == 3 and all(r.name.shown is False for r in rows)
      and rows[0].skull.shown is True and w.collapseButton.normal.endswith("NextPage-Up"))
lua.execute("function GameTooltip:AddLine(t) self.line = t end")
rows[1].scripts.OnEnter(rows[1])
check("kompakt: Name im Tooltip", g.GameTooltip.line == rows[1].npc.de, g.GameTooltip.line)
check("Detail bleibt beim Umschalten", d.name.text == "Hochevolutionaer")
rows[1].scripts.OnClick(rows[1])
check("kompakt: Klick wechselt das Detail weiterhin", d.name.text == "Urtuemliche Schlange")
rows[0].scripts.OnClick(rows[0])
w.collapseButton.scripts.OnClick(w.collapseButton)
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
check("volle Liste wieder da", g.KickGuideDB.listMode == "normal" and w.list.width == 270
      and rows[0].name.shown is True and w.collapseButton.normal.endswith("PrevPage-Up"))

print("\nFenster fuer den Run")
check("Esc schliesst nicht (nicht in UISpecialFrames)", "KickGuideFrame" not in list(g.UISpecialFrames.values()))
check("Groesse aenderbar mit Grenzen", w.bounds is not None and w.bounds[1] >= 515, w.bounds and list(w.bounds.values()))
g.SHIFT_DOWN = False
w.scripts.OnDragStart(w)
check("Ziehen ohne Umschalt verschiebt nicht", w.moved is None)
g.SHIFT_DOWN = True
w.scripts.OnDragStart(w)
w.scripts.OnDragStop(w)
check("Umschalt + Ziehen verschiebt, Position gespeichert", w.moved is True and g.KickGuideDB.point is not None)
w.SetWidth(w, 300)
api.ns.RefreshGuide()
check("schmales Fenster: Kacheln brechen nicht um", all(c.points[1][5] == -40 for c in
      [f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]))
check("zu schmal: auf Mindestbreite gesetzt", w.width >= w.bounds[1] and w.width >= 515, w.width)
w.grabber.scripts.OnMouseDown(w.grabber, "LeftButton")
w.grabber.scripts.OnMouseUp(w.grabber)
check("Zieh-Ecke: Groesse gespeichert", w.sizing == "BOTTOMRIGHT" and g.KickGuideDB.size[1] == w.width)
spells = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("Beschreibung bricht innerhalb der Spalte um", len(spells) == 3
      and all(s.desc.width <= s.width and s.name.width <= s.width for s in spells),
      [(s.desc.width, s.width) for s in spells])

lua3, g3, api3 = boot(TEST.replace('"Massen-Giftschlag", 101, "Vergiftet', '"' + "L" * 80 + '", 101, "Vergiftet'))
g3.SlashCmdList.KICKGUIDE("")
w3 = g3.KickGuideFrame
base = w3.bounds[1]
r3 = [f for f in shown(lua3, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
r3[0].scripts.OnClick(r3[0])
heading = 20 + 32 + 8 + 80 * 7 + 6 + len("Wichtig  Kick") * 7 + 8
check("Mindestbreite folgt der laengsten Zauberueberschrift", base >= 515
      and w3.bounds[1] == 16 + 270 + 8 + 1 + 16 + 16 + 12 + heading and w3.width >= w3.bounds[1], (base, w3.bounds[1], w3.width))
g3.KickGuideDB.listMode = "compact"
api3.ns.RefreshGuide()
check("kompakt: Mindestbreite schmaler", w3.bounds[1] == 16 + 52 + 8 + 1 + 16 + 16 + 12 + heading, w3.bounds[1])

# Langer Name: Kopf bestimmt die Mindestbreite, Name und Dungeon-Zeile passen in eine Zeile
lua5, g5, api5 = boot(TEST.replace('de = "Urtuemliche Schlange"', 'de = "' + "N" * 60 + '"'))
g5.KickGuideDB = g5.KickGuideDB
g5.SlashCmdList.KICKGUIDE("")
w5 = g5.KickGuideFrame
g5.KickGuideDB.listMode = "compact"
r5 = [f for f in shown(lua5, "rawget(f, 'npc') ~= nil") if visible_chain(f) and f.npc.id == 11][0]
r5.scripts.OnClick(r5)
w5.SetWidth(w5, 200)
api5.ns.RefreshGuide()
header = 64 + 12 + 60 * 7 + 8
d5 = w5.detail
check("langer Name: Mindestbreite deckt den Kopf ab", w5.bounds[1] == 16 + 52 + 8 + 1 + 16 + 16 + 12 + header, (w5.bounds[1], 16 + 52 + 8 + 1 + 16 + 16 + 12 + header))
check("langer Name: passt in eine Zeile, Dungeon-Zeile auch", d5.name.width >= 60 * 7 and d5.sub.width >= len(d5.sub.text) * 7,
      (d5.name.width, d5.sub.width, len(d5.sub.text) * 7))
check("Umschalter in eigener Zeile ueber dem Bild", d5.portrait.points[1][3] == -22 and d5.tabMap.points[1][4] == 0)

# Bildschirm: Fenster nie groesser als der Bildschirm, nie ausserhalb
lua6, g6, api6 = boot(TEST + "; SCREEN_W = 1280; SCREEN_H = 720")
g6.SlashCmdList.KICKGUIDE("")
w6 = g6.KickGuideFrame
w6.SetHeight(w6, 2000)
w6.SetWidth(w6, 3000)
api6.ns.RefreshGuide()
check("zu gross: auf Bildschirmgroesse begrenzt", w6.height == 720 and w6.width == 1280 and w6.bounds[4] == 720
      and w6.bounds[3] == 1280, (w6.width, w6.height, list(w6.bounds.values())))
w6.SetSize(w6, 600, 500)
w6.left, w6.top = 1000, 300
api6.ns.RefreshGuide()
p6 = w6.points[1]
check("ueber den Rand gerutscht: zurueck auf den Bildschirm, gespeichert", p6[1] == "TOPLEFT" and p6[3] == "BOTTOMLEFT"
      and p6[4] == 1280 - w6.width and p6[5] == 500 and g6.KickGuideDB.point[3] == 1280 - w6.width,
      [p6[i] for i in range(1, 6)])
w6.left, w6.top = 100, 600
w6.points[1] = None
w6.ClearAllPoints(w6)
w6.SetPoint(w6, "TOPLEFT", g6.UIParent, "BOTTOMLEFT", 100, 600)
w6.grabber.scripts.OnMouseDown(w6.grabber, "LeftButton")
check("Ecke ziehen: Grenze reicht nur bis zum Bildschirmrand ab aktueller Stelle", w6.bounds[3] == 1280 - 100
      and w6.bounds[4] == 600, list(w6.bounds.values()))
api6.ns.RefreshGuide()
check("waehrend des Ziehens bleibt die Grenze an der Stelle", w6.bounds[3] == 1280 - 100 and w6.bounds[4] == 600)
w6.left, w6.top = 900, 600
api6.ns.RefreshGuide()
check("waehrend des Ziehens wird nicht verschoben", w6.points[1][4] == 100)
w6.grabber.scripts.OnMouseUp(w6.grabber)
check("nach dem Ziehen zurueck auf den Bildschirm (nur falls ausserhalb)", w6.points[1][4] == 1280 - w6.width)
# Verschieben: WoWs Klammer haelt es auf dem Bildschirm, kein Nachschieben beim Loslassen
w6.ClearAllPoints(w6)
w6.SetPoint(w6, "TOPLEFT", g6.UIParent, "BOTTOMLEFT", 0, 720)
w6.left, w6.top = 0, 720
g6.SHIFT_DOWN = True
w6.scripts.OnDragStart(w6)
api6.ns.RefreshGuide()
w6.scripts.OnDragStop(w6)
check("Verschieben an den Rand: kein Springen beim Loslassen", w6.points[1][4] == 0 and w6.points[1][5] == 720
      and len(list(w6.points.values())) == 1)
w6.left, w6.top = 200, 700
w6.scripts.OnDragStart(w6)
w6.left, w6.top = 1200, 700
api6.ns.RefreshGuide()
check("waehrend des Verschiebens wird nicht dazwischen geschoben", w6.points[1][4] == 0)
w6.scripts.OnDragStop(w6)
w6.left, w6.top = 100, 600
w6.left, w6.top = None, None   # Attrappe rechnet die Position nicht nach
g6.SlashCmdList.KICKGUIDE("reset")
check("/kg reset: Standardgroesse, Mitte, Speicher geleert", w6.width == 820 and w6.height == 560
      and w6.points[1][1] == "CENTER" and g6.KickGuideDB.size is None and g6.KickGuideDB.point is None)

lua4, g4, api4 = boot(TEST + '; SAVED = { size = { 900, 700 }, point = { "TOPLEFT", "TOPLEFT", 50, -60 }, listMode = "compact" }')
g4.SlashCmdList.KICKGUIDE("")
w4 = g4.KickGuideFrame
check("gespeicherte Groesse, Position, Listenstufe", w4.width == 900 and w4.height == 700
      and w4.points[1][1] == "TOPLEFT" and w4.points[1][4] == 50 and w4.list.width == 52)

print("\nDungeon wechseln")
cells[1].scripts.OnClick(cells[1])
check("Nalorakks Bau: keine wichtigen Caster -> Hinweis", w.list.empty.shown is True
      and len([f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]) == 0)
check("ohne Caster: Hinweis, Dungeon gemerkt", d.hint.shown is True and g.KickGuideDB.lastDungeon == 586)
[c for c in cells if c.mapID == 588][0].scripts.OnClick([c for c in cells if c.mapID == 588][0])
check("Dungeonwechsel: erster Caster links automatisch gewaehlt", d.name.text == "Hochevolutionaer" and d.hint.shown is False)

print("\nIn der Instanz ohne gespeicherte Markierungen")
lua, g, api = boot(TEST + "; IN_INSTANCE = true; SECRET_IMPORTANT = true")
api.fire("PLAYER_ENTERING_WORLD")
check("in der Instanz wird nichts gespeichert", not api.ns.HasImportanceStore())
g.SlashCmdList.KICKGUIDE("")
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
check("kein Fehler, alle Gegner mit Zaubern sichtbar", len(rows) == 4, [r.name.text for r in rows])
check("Hinweis: erst ausserhalb Markierungen sammeln", "Noch keine gespeicherten" in g.KickGuideFrame.footer.text)
rows[0].scripts.OnClick(rows[0])
check("Detail ohne Totenkopf, ohne Fehler", all(s.skull.shown is False for s in
      [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]))

print("\nGespeicherte Markierungen (Guide nie geoeffnet)")
lua, g, api = boot(TEST)
api.fire("PLAYER_ENTERING_WORLD")
store = g.KickGuideDB.important
check("ausserhalb beim Einloggen gelesen, ohne Fenster", g.KickGuideFrame is None and store.spells[1] is True
      and store.spells[2] is False and store.spells[5] is True and store.build == "12.1.0.60000")
g.IN_INSTANCE = True
g.SECRET_IMPORTANT = True
api.fire("ZONE_CHANGED_NEW_AREA")
check("in der Instanz bleibt der Speicher", store.spells[1] is True)
g.SlashCmdList.KICKGUIDE("")
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
check("in der Instanz: gleiche Liste wie draussen", [r.name.text for r in rows]
      == ["Hochevolutionaer", "Urtuemliche Schlange", "Das windende Knaeuel"], [r.name.text for r in rows])
rows[0].scripts.OnClick(rows[0])
sp = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("in der Instanz: Totenkopf aus dem Speicher", rows[0].skull.shown is True and sp[0].skull.shown is True)
check("Fusszeile: Markierungen gespeichert", "gespeichert" in g.KickGuideFrame.footer.text)
g.IN_INSTANCE = False
g.SECRET_IMPORTANT = False
store.spells[999] = True
api.fire("ZONE_CHANGED_NEW_AREA")
check("gleiche Spielversion: Speicher bleibt", store.spells[999] is True)
g.BUILD = "60001"
api.fire("ZONE_CHANGED_NEW_AREA")
check("neue Spielversion: neu gelesen, Altes verworfen", store.build == "12.1.0.60001" and store.spells[999] is None
      and store.spells[1] is True)

print("\nAktueller Dungeon")
AUTO = TEST.replace('[586] = { key = "DON", en = "Den of Nalorakk",', '[586] = { key = "DON", en = "Den of Nalorakk", uimaps = { 2513, 2514 },')
lua, g, api = boot(AUTO + "; IN_INSTANCE = true; ACTIVE_MAP = 586")
g.SlashCmdList.KICKGUIDE("")
cells = [f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]
check("laufender Schluessel: nur seine Kachel, ausgewaehlt", [c.mapID for c in cells] == [586] and cells[0].selMark.shown is True)
lua, g, api = boot(AUTO + "; IN_INSTANCE = true; UIMAP = 2514")
g.SlashCmdList.KICKGUIDE("")
cells = [f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]
check("ohne Schluessel ueber die Kartenebene erkannt", [c.mapID for c in cells] == [586])
lua, g, api = boot(AUTO)
g.SlashCmdList.KICKGUIDE("")
check("draussen: alle Kacheln", len([f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]) == 2)
g.IN_INSTANCE = True
g.UIMAP = 2513
api.fire("ZONE_CHANGED_NEW_AREA")
cells = [f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]
check("offenes Fenster wechselt beim Betreten automatisch", [c.mapID for c in cells] == [586]
      and cells[0].selMark.shown is True and g.KickGuideFrame.list.empty.shown is True)
g.IN_INSTANCE = False
api.fire("ZONE_CHANGED_NEW_AREA")
check("beim Verlassen wieder alle Kacheln", len([f for f in shown(lua, "rawget(f, 'mapID') ~= nil")]) == 2)
check("keine Schriftfehler", len(list(g.PROBLEMS.values())) == 0, list(g.PROBLEMS.values()))

print("\nKarte")
MAP = TEST.replace('[588] = { key = "AOF", en = "Altar of Fangs",', '[588] = { key = "AOF", en = "Altar of Fangs", uimaps = { 5002, 5001 },')
MAP = MAP.replace('spells = { 1, 2, 3, 4 } }', 'spells = { 1, 2, 3, 4 }, map = { [0] = { { 10, 20 }, { 30, 40 } } } }')
MAP = MAP.replace('spells = { 5 } }', 'spells = { 5 }, map = { [1] = { { 60, 60 } } } }')
MAP = MAP.replace('spells = { 7, 6 } }', 'spells = { 7, 6 }, map = { [1] = { { 70, 52 } } } }')
MAP += "; MAP_ART = { [5001] = { 1000, 500, 256, 256 } }; ENCOUNTERS = { [5001] = { { encounterID = 1, mapX = 0.71, mapY = 0.52 } } }"
lua, g, api = boot(MAP)
fm = api.ns.FloorMaps(588)
check("Ebene ueber Boss-Position zugeordnet, Rest nach Reihenfolge", fm.maps[1] == 5001 and fm.how[1] == "boss"
      and fm.maps[0] == 5002 and fm.how[0] == "order", (fm.maps[0], fm.maps[1], fm.how[0], fm.how[1]))
g.SlashCmdList.KICKGUIDE("")
w = g.KickGuideFrame
d = w.detail
d.tabMap.scripts.OnClick(d.tabMap)
mv = w.mapView


def dots():
    return [f for f in shown(lua, "rawget(f, 'fill') ~= nil and rawget(f, 'npc') ~= nil") if visible_chain(f)]


def listrows():
    return [f for f in shown(lua, "rawget(f, 'npc') ~= nil and rawget(f, 'fill') == nil") if visible_chain(f)]


check("Umschalter: Karte statt Zauber, gespeichert", g.KickGuideDB.detailView == "map" and mv.shown is True
      and w.spells.shown is False and d.tabMap.line.shown is True and d.tabSpells.line.shown is False)
check("erster Caster gewaehlt, Karte auf seiner Ebene", d.name.text == "Hochevolutionaer"
      and sorted((p.npc.id, p.px) for p in dots()) and [p.npc.id for p in dots()] == [10, 10], [p.npc.id for p in dots()])
check("ohne Kartenbild: Hinweis, Punkte trotzdem", mv.message.shown is True and "nicht verf" in mv.message.text)
fb = [f for f in shown(lua, "rawget(f, 'floor') ~= nil") if visible_chain(f)]
check("zwei Ebenen-Knoepfe, erste aktiv", len(fb) == 2 and fb[0].line.shown is True and fb[1].line.shown is False
      and fb[0].text.text == "Ebene 1")
rows = listrows()
serpent = [r for r in rows if r.npc.id == 11][0]
serpent.scripts.OnClick(serpent)
check("Caster links gewaehlt: rechts wieder Zauber", g.KickGuideDB.detailView == "spells" and w.spells.shown is True
      and mv.shown is False and d.tabSpells.line.shown is True)
d.tabMap.scripts.OnClick(d.tabMap)
pts = dots()
sel = [p for p in pts if p.selected]
check("Caster gewaehlt: Karte wechselt auf seine Ebene", fb[1].line.shown is True and len(sel) == 1 and sel[0].npc.id == 11)
check("gewaehlter Punkt gross, cyan, oben", sel[0].width == 16 and sel[0].level > [p for p in pts if not p.selected][0].level)
check("Boss-Punkt auf derselben Ebene", sorted(p.npc.id for p in pts) == [11, 13])
tiles = [f for f in shown(lua, "f.kind == 'Texture' and type(rawget(f, 'texture')) == 'number' and rawget(f, 'texture') > 500000") if f.parent is None or True]
canvas = mv.canvas
check("Kartenbild aus Kacheln: 4x2, Seitenverhaeltnis 2:1", len([t for t in tiles if t.texture // 100 == 5001]) == 8
      and abs(canvas.width / canvas.height - 2) < 0.01 and mv.message.shown is False, (len(tiles), canvas.width, canvas.height))
check("Punktposition in Prozent der Karte", abs(sel[0].px - 0.6 * canvas.width) < 0.01 and abs(sel[0].py + 0.6 * canvas.height) < 0.01)
check("Kacheln in richtiger Reihenfolge", all(t.texture == 500100 + int(round(-t.points[1][5] / (256 * canvas.width / 1000))) * 4
      + int(round(t.points[1][4] / (256 * canvas.width / 1000))) + 1 for t in tiles if t.texture // 100 == 5001))
w.SetHeight(w, 400)
api.ns.RefreshGuide()
detailH = 400 - (16 + 24 + 42 + 8) - (16 + 28) - (18 + 4 + 64 + 16 + 1)
check("Karte passt in den Detailbereich (Hoehe begrenzt, Verhaeltnis bleibt)", canvas.height + 28 <= detailH
      and canvas.width <= w.width and abs(canvas.width / canvas.height - 2) < 0.01, (canvas.width, canvas.height, detailH))
fb[0].scripts.OnClick(fb[0])
check("Ebenen-Knopf wechselt die Ebene, Auswahl bleibt", [p.npc.id for p in dots()] == [10, 10] and d.name.text == "Urtuemliche Schlange")
check("Ebene des Casters in Cyan markiert", fb[1].text.color[1] < 0.5 and fb[0].text.color[1] > 0.5)
dp = dots()[0]
dp.scripts.OnClick(dp)
check("Punkt anklicken waehlt den Caster, Karte bleibt", d.name.text == "Hochevolutionaer" and mv.shown is True)
check("MDT-Knopf nur mit MDT", mv.mdt.shown is False)
lua.execute("MDT_OPENED = false; SlashCmdList.MYTHICDUNGEONTOOLS = function() MDT_OPENED = true end")
api.ns.RefreshGuide()
check("MDT-Befehl da, Addon aber nicht geladen: kein Knopf", mv.mdt.shown is False)
lua.execute("LOADED_ADDONS.MythicDungeonTools = true")
api.ns.RefreshGuide()
mv.mdt.scripts.OnClick(mv.mdt)
check("MDT-Knopf oeffnet MDT", mv.mdt.shown is True and g.MDT_OPENED is True)
d.tabSpells.scripts.OnClick(d.tabSpells)
check("zurueck zu den Zaubern", mv.shown is False and w.spells.shown is True and len(dots()) == 0)
d.tabMap.scripts.OnClick(d.tabMap)

g.IN_INSTANCE = True
g.ACTIVE_MAP = 588
g.UIMAP = 5001
api.fire("ZONE_CHANGED_INDOORS")
check("im Dungeon: Karte folgt der Ebene des Spielers", fb[1].line.shown is True)
g.UIMAP = 5002
api.fire("ZONE_CHANGED")
check("Ebenenwechsel im Dungeon", fb[0].line.shown is True)
check("keine Schriftfehler (Karte)", len(list(g.PROBLEMS.values())) == 0, list(g.PROBLEMS.values()))

lua, g, api = boot(TEST + "; SAVED = { detailView = 'map' }")
g.SlashCmdList.KICKGUIDE("")
check("ohne Kartendaten: Hinweis", g.KickGuideFrame.mapView.message.text == "Keine Kartendaten."
      and g.KickGuideFrame.mapView.canvas.shown is False)

print("\nEnglischer Client")
# Alle deutschen Uebersetzungen einsammeln (Werte der deDE-Tabelle)
lua_de, g_de, api_de = boot(TEST)
german = set(v for k, v in api_de.ns.L.items() if isinstance(v, str) and v != k)
lua, g, api = boot(TEST + '; LOCALE = "enUS"; SPELLS[1][3] = "Poisons all players."; TEST_DATA[588].npcs[1].map = { [0] = { { 10, 20 } } }')
lua.execute("function GameTooltip:AddLine(t) self.line = t end")
g.SlashCmdList.KICKGUIDE("")
w = g.KickGuideFrame
rows = [f for f in shown(lua, "rawget(f, 'npc') ~= nil") if visible_chain(f)]
headers = sorted(h.text.text for h in shown(lua, "rawget(f, 'key') ~= nil and rawget(f, 'toggle') ~= nil"))
check("enUS: englische Gegnernamen, Gruppenkoepfe", [r.name.text for r in rows] == ["High Evolutionist", "Primal Serpent", "The Writhing Coil"]
      and headers == ["Bosses (1)", "Important casters (2)"], ([r.name.text for r in rows], headers))
sp = [f for f in shown(lua, "rawget(f, 'spellID') ~= nil") if visible_chain(f)]
check("enUS: Hinweise englisch", "Important" in sp[0].tag.text and "|cff33dd55Kick|r" in sp[0].tag.text
      and w.detail.sub.text.endswith("Trash") and w.detail.tabSpells.text.text == "Casts" and w.detail.tabMap.text.text == "Map",
      (sp[0].tag.text, w.detail.sub.text))
w.detail.tabMap.scripts.OnClick(w.detail.tabMap)
w.collapseButton.scripts.OnEnter(w.collapseButton)
chat = []
lua.execute("DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT = m; CHATLOG = (CHATLOG or '') .. m .. '\\n' end }")
g.SlashCmdList.KICKGUIDE("map")
g.SlashCmdList.KICKGUIDE("reset")
g.SlashCmdList.KICKGUIDE("help")
texts = [f.text for f in lua.eval("ALL").values() if f.kind == "FontString" and isinstance(rawtext := f.text, str)]
texts += [g.GameTooltip.line or ""] + (g.CHATLOG or "").split(chr(10))
leaks = [t for t in texts if t in german or any(x in t for x in ("ä", "ö", "ü", "ß", "Karte", "Ebene", "Bild", "geheim"))]
check("enUS: nirgends deutscher Text (Fenster, Tooltip, Chat)", not leaks, leaks[:5])
check("enUS: Kartenpruefung ausgegeben", "0->" in (g.CHATLOG or ""), g.CHATLOG)
check("enUS: Hilfe nennt alle Befehle", "/kg reset" in g.CHAT and "/kg map" in g.CHAT, g.CHAT)
check("enUS: keine Schriftfehler", len(list(g.PROBLEMS.values())) == 0)

print("\nEchte Data.lua")
lua, g, api = boot("")
dungeons = api.ns.DUNGEONS
check("Data.lua laedt, Datenquelle gesetzt", dungeons is not None and "Wowhead" in api.ns.DATA_SOURCE)
bad = []
for mapID, dd in dungeons.items():
    for npc in dd.npcs.values():
        if not (npc.id and npc.en and npc.spells and len(list(npc.spells.values())) > 0):
            bad.append((mapID, npc.id))
check("jeder Gegner hat ID, Namen, Zauber", not bad, bad[:5])
badmap = []
for mapID, dd in dungeons.items():
    for npc in dd.npcs.values():
        for floor, pts in (npc.map.items() if npc.map else []):
            for p in pts.values():
                if not (0 <= p[1] <= 100 and 0 <= p[2] <= 100):
                    badmap.append((mapID, npc.id, floor))
check("Kartenpunkte im Bereich 0..100", not badmap, badmap[:5])
kick = api.ns.KICK
check("Kick-Angaben aus Spieldaten vorhanden, Stichproben wie MDT", kick is not None and kick[1294557] is True
      and kick[1289416] is True and kick[1306911] is False and len([v for v in kick.values() if v is True]) >= 50)
cc = api.ns.CC
check("CC-Angaben aus MDT vorhanden, Stichproben", cc is not None and len(list(cc.keys())) >= 50
      and cc[188244] is not None and cc[188244].Stun is None and cc[188244].Taunt is True)
check("jeder Dungeon hat Karten-IDs", all(dd.uimaps and len(list(dd.uimaps.values())) > 0 for dd in dungeons.values()))

print("%d von %d Pruefungen bestanden" % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)

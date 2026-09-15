# KickGuide

**Mythic+ preparation guide for World of Warcraft: Midnight (12.1).**
Pick a dungeon, see which trash mobs have casts Blizzard marks as *important*, and what you can do about each cast — kick, stun, or neither. Built to stay open during the run.

*Deutsch weiter unten.*

![KickGuide window](docs/screenshot-main.png)

## Features

- **Important casters per dungeon** — the list shows only mobs with at least one cast Blizzard flags as important (`C_Spell.IsSpellImportant`), bosses in their own group.
- **Casts with descriptions** — important casts marked with a skull, followed by:
  - **Kick** (green) — interruptible according to the game data
  - **No kick** (orange) — has a cast bar but cannot be interrupted, with **· Stun** or **· stun immune** if known
- **Works inside dungeons** — Blizzard hides the *important* flag in instances, so KickGuide reads and stores it whenever you are outside an instance (the window does not need to be open).
- **Map** — Blizzard's dungeon map per floor with one point per mob group; click a point to select the mob. Inside a dungeon the map follows your floor.
- **Run-ready window** — resizable, shift-drag to move, Esc does not close it, compact list mode (portrait and skull count only).
- **Your own stun marks** — right-click a mob portrait or cast row to mark the mob as stunnable or stun immune.
- **MDT button** — opens Mythic Dungeon Tools if it is installed.
- English and German.

## Commands

| Command | Action |
| --- | --- |
| `/kg` | Open or close the guide |
| `/kg minimap` | Show or hide the minimap button |
| `/kg reset` | Reset window size and position |
| `/kg map` | Print the map floor check |

## Data sources

| Data | Source |
| --- | --- |
| Important casts | Blizzard, live in game (`C_Spell.IsSpellImportant`) |
| Kick / no kick | Blizzard game data (SpellCategories, SpellMisc) via [wago.tools](https://wago.tools) |
| Mobs, casts per mob, spawn points | [Wowhead](https://www.wowhead.com) |
| Stun information (Ruby Life Pools, Temple of Sethraliss, Kings' Rest) | [Mythic Dungeon Tools](https://github.com/Nnoggie/MythicDungeonTools) by Nnoggie, GPL-2.0 |
| Spell names, descriptions, dungeon names, maps | the game client, in your language |

A mob that is shielded at the moment still cannot be kicked; the guide shows the normal case.

## Development

```
python dev/test_guide.py      # tests (needs: pip install lupa)
python dev/build_data.py      # rebuild Data.lua from data/*.json + game data
python dev/install.py         # copy the addon into the WoW AddOns folder
```

Releases: pushing a tag like `v0.2.0` runs the tests and uploads the package to GitHub Releases and CurseForge (`.github/workflows/release.yml`).

## License

GPL-2.0 — see [LICENSE](LICENSE). Includes LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 under their own licenses.

---

## Deutsch

**Vorbereitung auf Mythisch+ für WoW Midnight (12.1).** Dungeon wählen, sehen, welche Trash-Mobs Zauber haben, die Blizzard als *wichtig* markiert, und was man dagegen tun kann: kicken, stunnen oder keins von beidem. Das Fenster kann während des Runs offen bleiben.

- Liste nur der Mobs mit wichtigen Zaubern, Bosse getrennt
- Zauber mit Beschreibung, Totenkopf für wichtige, dazu **Kick** / **Kein Kick · Stun** / **Kein Kick · stun-immun**
- Funktioniert im Dungeon: Die Markierungen werden außerhalb von Instanzen gelesen und gespeichert, ohne dass das Fenster offen sein muss
- Karte je Ebene mit einem Punkt pro Mobgruppe, im Dungeon folgt sie deiner Ebene
- Fenster in der Größe veränderbar, Umschalt + Ziehen zum Verschieben, Esc schließt nicht, kompakte Liste
- Rechtsklick auf Bild oder Zauberzeile: Mob als stunbar oder stun-immun markieren
- Befehle: `/kg`, `/kg minimap`, `/kg reset`, `/kg karte`

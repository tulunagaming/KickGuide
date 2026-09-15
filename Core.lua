-------------------------------------------------------------------------------
-- KickGuide: Vorbereitung auf Mythisch+ - wichtige Caster je Dungeon und
-- ihre Zauber mit Beschreibung.
--
-- Core.lua: Namensraum, Sprache, gespeicherte Werte, Auswertung der Daten,
-- Minimap-Knopf, Slash-Befehle. Die Daten (welcher Gegner welche Zauber hat)
-- stehen in Data.lua, das Fenster baut Guide.lua.
--
-- "Wichtig" entscheidet Blizzard (C_Spell.IsSpellImportant). Ausserhalb von
-- Instanzen ist die Antwort lesbar (im Spiel bestätigt); in Instanzen kann sie
-- geheim sein. Deshalb wird sie ausserhalb von Instanzen automatisch für alle
-- Zauber der Daten gelesen und gespeichert (auch ohne dass der Guide offen war);
-- in Instanzen gilt der gespeicherte Wert. Neue Spielversion -> neu lesen.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

if GetLocale() == "deDE" then
    L["Important casters"]            = "Wichtige Caster"
    L["Bosses"]                       = "Bosse"
    L["Boss"]                         = "Boss"
    L["Trash"]                        = "Trash"
    L["Choose a caster on the left."] = "Links einen Caster wählen."
    L["No important casters found for this dungeon."] = "Für diesen Dungeon wurden keine wichtigen Caster gefunden."
    L["Important"]                    = "Wichtig"
    L["Other casts"]                  = "Weitere Zauber"
    L["No description."]              = "Keine Beschreibung."
    L["Important casts are marked by Blizzard. Data: %s."] = "Wichtige Zauber markiert Blizzard. Daten: %s."
    L["In instances Blizzard hides which casts are important; open the guide before the run."] =
        "In Instanzen verbirgt Blizzard, welche Zauber wichtig sind – den Guide vor dem Run öffnen."
    L["Left-click: open guide"]       = "Linksklick: Guide öffnen"
    L["Drag: move around the minimap"] = "Ziehen: um die Minimap verschieben"
    L["Commands: /kg (open guide), /kg minimap (show/hide button), /kg reset (reset window size and position), /kg map (check map floors)"] =
        "Befehle: /kg (Guide öffnen), /kg minimap (Knopf zeigen/verbergen), /kg reset (Fenstergröße und -position zurücksetzen), /kg karte (Kartenebenen prüfen)"
    L["image"]                        = "Bild"
    L["no image"]                     = "kein Bild"
    L["Player map: %s"]               = "Spieler-Karte: %s"
    L["secret/none"]                  = "geheim/keine"
    L["Window size and position reset."] = "Fenstergröße und -position zurückgesetzt."
    L["Minimap button shown."]        = "Minimap-Knopf eingeblendet."
    L["Minimap button hidden."]       = "Minimap-Knopf ausgeblendet."
    L["No stored marks yet: visit a city or the open world once, then the skulls also show in dungeons."] =
        "Noch keine gespeicherten Markierungen: einmal in eine Stadt oder die offene Welt, dann erscheinen die Totenköpfe auch im Dungeon."
    L["Marks stored outside the dungeon (%s)."] = "Markierungen außerhalb des Dungeons gespeichert (%s)."
    L["Shift-drag: move window"]      = "Umschalt + Ziehen: Fenster verschieben"
    L["Drag: resize window"]          = "Ziehen: Fenstergröße ändern"
    L["Compact list"]                 = "Kompakte Liste"
    L["Full list"]                    = "Volle Liste"
    L["Casts"]                        = "Zauber"
    L["Map"]                          = "Karte"
    L["Open MDT"]                     = "MDT öffnen"
    L["Map image not available."]     = "Kartenbild nicht verfügbar."
    L["No map data."]                 = "Keine Kartendaten."
    L["Click a point to choose a caster."] = "Punkt anklicken, um einen Caster zu wählen."
    L["Floor %d"]                     = "Ebene %d"
    L["Kick"]                         = "Kick"
    L["No kick"]                      = "Kein Kick"
    L["Stun"]                         = "Stun"
    L["Stun immune"]                  = "stun-immun"
    L["Stunnable"]                    = "Stunbar"
    L["No own mark (MDT data if available)"] = "Keine eigene Angabe (MDT-Daten, falls vorhanden)"
    L["Right-click: mark stun"]       = "Rechtsklick: Stun markieren"
end

-------------------------------------------------------------------------------
-- Gespeicherte Werte
-------------------------------------------------------------------------------

local DEFAULTS = {
    minimap = { hide = false },
    collapsed = {},               -- Gruppenschlüssel -> zugeklappt
    listMode = "normal",          -- "normal" | "compact" (nur Bild und Totenkopf)
    size = nil,                   -- { Breite, Höhe }
    point = nil,                  -- { Punkt, relPunkt, x, y }
    important = { build = nil, spells = {} },
    stun = {},                    -- eigene Markierung: Gegner-ID -> true (stunbar) / false (immun)
}

function ns.DB()
    KickGuideDB = KickGuideDB or {}
    for k, v in pairs(DEFAULTS) do
        if KickGuideDB[k] == nil then
            KickGuideDB[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
    return KickGuideDB
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fb8ffKickGuide|r: " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Auswertung
-------------------------------------------------------------------------------

local function Plain(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return true
end
ns.Plain = Plain

-- Live-Antwort des Spiels: true / false, oder nil wenn unbekannt (API fehlt,
-- Fehler, geheim).
local function LiveImportant(spellID)
    if not (C_Spell and C_Spell.IsSpellImportant) then return nil end
    local ok, important = pcall(C_Spell.IsSpellImportant, spellID)
    if not ok or not Plain(important) then return nil end
    return important == true
end

local function BuildString()
    if not GetBuildInfo then return "?" end
    local version, build = GetBuildInfo()   -- "and" davor würde den zweiten Wert abschneiden
    return tostring(version) .. "." .. tostring(build)
end

local function InInstance()
    return IsInInstance and IsInInstance() and true or false
end

-- Wichtig? Ausserhalb von Instanzen live (und gleich gespeichert), in Instanzen
-- aus dem Speicher. true / false / nil (unbekannt).
function ns.IsImportant(spellID)
    local store = ns.DB().important
    if not InInstance() then
        local live = LiveImportant(spellID)
        if live ~= nil then
            store.spells[spellID] = live
            return live
        end
    end
    local stored = store.spells[spellID]
    if stored ~= nil then return stored end
    return nil
end

-- Alle Zauber der Daten lesen und speichern. Nur ausserhalb von Instanzen;
-- neue Spielversion verwirft alte Werte.
function ns.RefreshImportanceStore()
    if InInstance() or not ns.DUNGEONS then return false end
    local store = ns.DB().important
    local build = BuildString()
    if store.build ~= build then
        store.build = build
        store.spells = {}
    end
    local read = 0
    for _, dungeon in pairs(ns.DUNGEONS) do
        for _, npc in ipairs(dungeon.npcs) do
            for _, id in ipairs(npc.spells) do
                local live = LiveImportant(id)
                if live ~= nil then
                    store.spells[id] = live
                    read = read + 1
                end
            end
        end
    end
    store.stamp = time and time() or nil
    return read > 0
end

-- Gibt es gespeicherte Markierungen (für den Hinweis im Dungeon)?
function ns.HasImportanceStore()
    return next(ns.DB().important.spells) ~= nil
end

-- Dungeon, in dem der Spieler gerade ist (Keystone-Karten-ID) oder nil.
-- Laufender Schlüssel zuerst, sonst über die Karten-IDs der Dungeonebenen.
function ns.CurrentDungeon()
    if not InInstance() then return nil end
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local active = C_ChallengeMode.GetActiveChallengeMapID()
        if active and ns.DUNGEONS[active] then return active end
    end
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not Plain(uiMap) then return nil end
    for mapID, dungeon in pairs(ns.DUNGEONS) do
        for _, id in ipairs(dungeon.uimaps or {}) do
            if id == uiMap then return mapID end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Karte: Wowhead-Ebenen -> Blizzard-Karten-IDs
-------------------------------------------------------------------------------
-- Wowhead nummeriert die Ebenen selbst. Welche Blizzard-Karte (uiMapID) dazu
-- gehört, wird im Spiel ermittelt: Das Dungeonkompendium kennt die Position
-- jedes Bosses auf jeder Karte (C_EncounterJournal.GetEncountersOnMap). Liegt
-- ein Boss der Daten auf Ebene f an derselben Stelle wie ein Boss auf Karte u,
-- gehören beide zusammen. Übrige Ebenen: nach Reihenfolge.

local BOSS_MATCH = 0.05      -- 5 % der Kartengrösse
local floorCache = {}

-- Ebenen eines Dungeons, aufsteigend.
function ns.Floors(mapID)
    local d = ns.DUNGEONS[mapID]
    local set, list = {}, {}
    for _, npc in ipairs(d and d.npcs or {}) do
        for floor in pairs(npc.map or {}) do
            if not set[floor] then set[floor] = true; table.insert(list, floor) end
        end
    end
    table.sort(list)
    return list
end

function ns.FloorMaps(mapID)
    if floorCache[mapID] then return floorCache[mapID] end
    local d = ns.DUNGEONS[mapID]
    local floors = ns.Floors(mapID)
    local result, how, usedMap = {}, {}, {}
    local uimaps = d and d.uimaps or {}
    if C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap then
        local best = {}
        for _, uiMap in ipairs(uimaps) do
            local ok, encounters = pcall(C_EncounterJournal.GetEncountersOnMap, uiMap)
            for _, e in ipairs(ok and encounters or {}) do
                for _, npc in ipairs(d.npcs) do
                    if npc.boss then
                        for floor, points in pairs(npc.map or {}) do
                            for _, p in ipairs(points) do
                                local dx, dy = p[1] / 100 - (e.mapX or -1), p[2] / 100 - (e.mapY or -1)
                                if dx * dx + dy * dy <= BOSS_MATCH * BOSS_MATCH then
                                    best[floor] = best[floor] or {}
                                    best[floor][uiMap] = (best[floor][uiMap] or 0) + 1
                                end
                            end
                        end
                    end
                end
            end
        end
        for _, floor in ipairs(floors) do
            local pick, score = nil, 0
            for uiMap, n in pairs(best[floor] or {}) do
                if n > score and not usedMap[uiMap] then pick, score = uiMap, n end
            end
            if pick then result[floor], how[floor], usedMap[pick] = pick, "boss", true end
        end
    end
    local free = {}
    for _, uiMap in ipairs(uimaps) do
        if not usedMap[uiMap] then table.insert(free, uiMap) end
    end
    local i = 1
    for _, floor in ipairs(floors) do
        if not result[floor] and free[i] then
            result[floor], how[floor] = free[i], "order"
            i = i + 1
        end
    end
    floorCache[mapID] = { maps = result, how = how }
    return floorCache[mapID]
end

-- Ebene, auf der der Spieler gerade steht (nur im Dungeon), oder nil.
function ns.PlayerFloor(mapID)
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not Plain(uiMap) then return nil end
    for floor, id in pairs(ns.FloorMaps(mapID).maps) do
        if id == uiMap then return floor end
    end
    return nil
end

-- Kartenbild einer Ebene: Kacheln wie Blizzards Weltkarte.
-- Liefert { width, height, tileW, tileH, cols, rows, textures } oder nil.
function ns.MapArt(uiMap)
    if not (uiMap and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, uiMap)
    local layer = ok and layers and layers[1]
    if not layer then return nil end
    local ok2, textures = pcall(C_Map.GetMapArtLayerTextures, uiMap, 1)
    if not ok2 or not textures or #textures == 0 then return nil end
    return {
        width = layer.layerWidth, height = layer.layerHeight,
        tileW = layer.tileWidth, tileH = layer.tileHeight,
        cols = math.ceil(layer.layerWidth / layer.tileWidth),
        rows = math.ceil(layer.layerHeight / layer.tileHeight),
        textures = textures,
    }
end

-- Eigene Markierung: "yes" / "no" / "none".
function ns.StunMark(npc)
    local v = npc and ns.DB().stun[npc.id]
    if v == true then return "yes" elseif v == false then return "no" end
    return "none"
end

function ns.SetStunMark(npc, mark)
    if not npc then return end
    local stun = ns.DB().stun
    if mark == "yes" then stun[npc.id] = true
    elseif mark == "no" then stun[npc.id] = false
    else stun[npc.id] = nil end
end

-- Stunbar? Eigene Markierung vor MDT-Daten. true / false / nil (unbekannt).
function ns.Stunnable(npc)
    if not npc then return nil end
    local own = ns.DB().stun[npc.id]
    if own ~= nil then return own end
    local cc = ns.CC and ns.CC[npc.id]
    if not cc then return nil end
    return cc.Stun == true
end

-- Name eines Gegners in der Sprache des Spiels (Daten liefern de und en).
function ns.NpcName(npc)
    if GetLocale() == "deDE" and npc.de and npc.de ~= "" then return npc.de end
    return npc.en
end

-- Zauber eines Gegners, nach Namen zusammengefasst (Wirken und Effekt haben
-- oft eigene IDs mit gleichem Namen). Liefert eine Liste von
-- { name, icon, ids = {...}, important = true/false/nil, description }.
-- Wichtige zuerst, dann alphabetisch.
function ns.SpellGroups(npc)
    local groups, byName = {}, {}
    for _, id in ipairs(npc.spells) do
        local info = C_Spell.GetSpellInfo(id)
        local name = info and info.name
        if name and name ~= "" then
            local g = byName[name]
            if not g then
                g = { name = name, icon = info.iconID, ids = {}, important = false, unknown = false }
                byName[name] = g
                table.insert(groups, g)
            end
            table.insert(g.ids, id)
            local important = ns.IsImportant(id)
            if important == nil then
                g.unknown = true
            elseif important then
                g.important = true
                g.importantID = g.importantID or id
            end
            local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)
            -- Beschreibung bevorzugt vom wichtigen Zauber, sonst die erste vorhandene.
            if desc and desc ~= "" and (not g.description or (important and g.importantID == id)) then
                g.description = desc
            end
        end
    end
    -- Kickbar (Spieldaten): Angabe des wichtigen Zaubers zählt, sonst reicht
    -- ein kickbarer; nur "kein Kick", wenn keiner kickbar ist.
    local kicks = ns.KICK or {}
    for _, g in ipairs(groups) do
        if g.importantID and kicks[g.importantID] ~= nil then
            g.kick = kicks[g.importantID]
        else
            for _, id in ipairs(g.ids) do
                if kicks[id] == true then g.kick = true break end
                if kicks[id] == false then g.kick = false end
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.important ~= b.important then return a.important end
        return a.name < b.name
    end)
    return groups
end

-- Hat der Gegner mindestens einen wichtigen Zauber? true / false / nil (unbekannt).
function ns.NpcImportance(npc)
    local unknown = false
    for _, id in ipairs(npc.spells) do
        local important = ns.IsImportant(id)
        if important then return true, 0 end
        if important == nil then unknown = true end
    end
    if unknown then return nil end
    return false
end

-- Zählt die wichtigen Zauber (nach Namen zusammengefasst).
function ns.ImportantCount(npc)
    local count = 0
    for _, g in ipairs(ns.SpellGroups(npc)) do
        if g.important then count = count + 1 end
    end
    return count
end

-- Dungeons der Saison in der Reihenfolge des Spiels, nur solche mit Daten.
function ns.SeasonDungeons()
    local list, seen = {}, {}
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if type(maps) == "table" then
        for _, mapID in ipairs(maps) do
            if ns.DUNGEONS[mapID] and not seen[mapID] then
                table.insert(list, mapID)
                seen[mapID] = true
            end
        end
    end
    -- Rückfall (Kartenliste leer, z. B. direkt nach dem Login): alle aus den Daten.
    local rest = {}
    for mapID in pairs(ns.DUNGEONS) do
        if not seen[mapID] then table.insert(rest, mapID) end
    end
    table.sort(rest)
    for _, mapID in ipairs(rest) do table.insert(list, mapID) end
    return list
end

-- Name und Bild eines Dungeons: vom Spiel (deutsch), sonst aus den Daten.
function ns.DungeonInfo(mapID)
    local name, _, _, texture
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    end
    local d = ns.DUNGEONS[mapID]
    return name or (d and d.en) or tostring(mapID), texture
end

-- Wichtige Caster (ohne Bosse) und Bosse mit wichtigen Zaubern.
-- Ist "wichtig" nicht lesbar (in Instanzen), erscheinen alle Gegner mit Zaubern.
function ns.ImportantNpcs(mapID)
    local casters, bosses = {}, {}
    local d = ns.DUNGEONS[mapID]
    if not d then return casters, bosses end
    for _, npc in ipairs(d.npcs) do
        local important = ns.NpcImportance(npc)
        if important ~= false and #npc.spells > 0 then
            table.insert(npc.boss and bosses or casters, npc)
        end
    end
    local function byName(a, b) return ns.NpcName(a) < ns.NpcName(b) end
    table.sort(casters, byName)
    table.sort(bosses, byName)
    return casters, bosses
end

-------------------------------------------------------------------------------
-- Minimap-Knopf (LibDBIcon, damit SexyMap & Co. ihn übernehmen)
-------------------------------------------------------------------------------

local ICON = "Interface\\Icons\\Ability_Kick"

local function Libs()
    if not LibStub then return end
    return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

local function SetupMinimapButton()
    local ldb, icon = Libs()
    if not (ldb and icon) or icon:IsRegistered(ADDON_NAME) then return end
    local launcher = ldb:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = ADDON_NAME,
        icon = ICON,
        OnClick = function() ns.ToggleGuide() end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(ADDON_NAME, 1, 1, 1)
            tooltip:AddLine(L["Left-click: open guide"], 0.8, 0.8, 0.8)
            tooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
        end,
    })
    icon:Register(ADDON_NAME, launcher, ns.DB().minimap)
end

local function SetMinimapButtonShown(show)
    ns.DB().minimap.hide = not show
    local _, icon = Libs()
    if not icon then return end
    if show then icon:Show(ADDON_NAME) else icon:Hide(ADDON_NAME) end
end

-------------------------------------------------------------------------------
-- Laden, Slash-Befehle
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        ns.DB()
        SetupMinimapButton()
        -- Kartenliste der Saison anfordern, damit die Reihenfolge stimmt.
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
        return
    end
    if not KickGuideDB then return end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        -- Ebenenwechsel im Dungeon: Karte folgt dem Spieler.
        if ns.OnFloorChanged then ns.OnFloorChanged() end
        return
    end
    -- Beim Zonenwechsel meldet das Spiel im ersten Moment teils noch die alte
    -- Zone; kurz warten, dann Markierungen lesen und das Fenster anpassen.
    C_Timer.After(1, function()
        ns.RefreshImportanceStore()
        if ns.OnZoneChanged then ns.OnZoneChanged() end
    end)
end)

SLASH_KICKGUIDE1 = "/kg"
SLASH_KICKGUIDE2 = "/kickguide"
SlashCmdList["KICKGUIDE"] = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "" then
        ns.ToggleGuide()
    elseif cmd == "karte" or cmd == "map" then
        -- Prüfhilfe: Zuordnung der Ebenen je Dungeon
        for _, mapID in ipairs(ns.SeasonDungeons()) do
            local fm = ns.FloorMaps(mapID)
            local parts = {}
            for _, floor in ipairs(ns.Floors(mapID)) do
                local uiMap = fm.maps[floor]
                table.insert(parts, string.format("%d->%s(%s,%s)", floor, tostring(uiMap), fm.how[floor] or "-",
                    ns.MapArt(uiMap) and L["image"] or L["no image"]))
            end
            ns.Print((ns.DUNGEONS[mapID].key or mapID) .. ": " .. table.concat(parts, " "))
        end
        local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        ns.Print(string.format(L["Player map: %s"], Plain(uiMap) and tostring(uiMap) or L["secret/none"]))
    elseif cmd == "reset" then
        ns.ResetGuideGeometry()
        ns.Print(L["Window size and position reset."])
    elseif cmd == "minimap" then
        local show = ns.DB().minimap.hide == true
        SetMinimapButtonShown(show)
        ns.Print(show and L["Minimap button shown."] or L["Minimap button hidden."])
    else
        ns.Print(L["Commands: /kg (open guide), /kg minimap (show/hide button), /kg reset (reset window size and position), /kg map (check map floors)"])
    end
end

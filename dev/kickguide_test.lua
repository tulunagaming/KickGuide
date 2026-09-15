-- Kleine WoW-Attrappe fuer KickGuide. Laedt die Dateien aus der .toc (ohne Libs).
-- Regeln: FontString:SetText ohne Schrift wird gemeldet; geheime Werte brechen
-- bei Vergleich/Rechnung ab.

local SECRETS = setmetatable({}, { __mode = "k" })
local function boom() error("geheimer Wert benutzt", 2) end
local SMT = { __eq = boom, __lt = boom, __le = boom, __add = boom, __concat = boom, __len = boom, __index = boom }
function Secret() local s = setmetatable({}, SMT); SECRETS[s] = true; return s end
function issecretvalue(v) return SECRETS[v] == true end

PROBLEMS = {}

local W = {}
W.__index = function(self, k)
    local m = rawget(W, k); if m then return m end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() return self end
end
ALL = {}
function W.new(kind, template)
    local f = setmetatable({ kind = kind, shown = true, points = {}, scripts = {}, template = template }, W)
    if kind == "FontString" and template then f.font = template end
    table.insert(ALL, f)
    return f
end
function W:Show() self.shown = true end
function W:Hide() self.shown = false end
function W:IsShown() return self.shown end
function W:SetShown(v) self.shown = v and true or false end
function W:SetText(t)
    if self.kind == "FontString" and not rawget(self, "font") then table.insert(PROBLEMS, "SetText ohne Schrift") end
    self.text = t
end
function W:GetText() return rawget(self, "text") end
function W:SetFont(p) self.font = p end
function W:SetTexture(t) self.texture = t end
function W:SetNormalTexture(t) self.normal = t end
function W:SetDesaturated(v) self.desaturated = v end
function W:SetTextColor(r, g, b) self.color = { r, g, b } end
function W:SetSize(w, h) self.width, self.height = w, h end
function W:SetWidth(w) self.width = w end
function W:SetHeight(h) self.height = h end
function W:GetWidth() return rawget(self, "width") or 400 end
function W:GetHeight() return rawget(self, "height") or 400 end
function W:GetStringHeight() return 24 end
-- Farbcodes zählen wie im Spiel nicht zur Breite.
function W:GetStringWidth()
    local t = rawget(self, "text") and tostring(self.text) or ""
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #t * 7
end
function W:GetPoint()
    local p = self.points[1]
    if not p then return nil end
    if type(p[2]) == "table" then return p[1], p[2], p[3], p[4] or 0, p[5] or 0 end
    return p[1], UIParent, p[1], p[2] or 0, p[3] or 0
end
function W:GetLeft() return rawget(self, "left") end
function W:GetTop() return rawget(self, "top") end
function W:GetFrameLevel() return rawget(self, "level") or 1 end
function W:SetFrameLevel(l) self.level = l end
function W:SetResizeBounds(a, b, c, d) self.bounds = { a, b, c, d } end
function W:StartMoving() self.moved = true end
function W:StartSizing(corner) self.sizing = corner end
function W:SetPoint(...) table.insert(self.points, { ... }) end
function W:ClearAllPoints() self.points = {} end
function W:SetScript(n, fn) self.scripts[n] = fn end
function W:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function W:UnregisterEvent(e) end
function W:CreateTexture() return W.new("Texture") end
function W:CreateFontString(_, _, template) return W.new("FontString", template) end
function W:SetScrollChild(c) self.child = c end
function W:GetVerticalScroll() return rawget(self, "vscroll") or 0 end
function W:SetVerticalScroll(v) self.vscroll = v end
function CreateFrame(kind, name, parent, template)
    local f = W.new(kind, template)
    f.name, f.parent = name, parent
    if name then _G[name] = f end
    return f
end

UIParent = W.new("Frame")
UIParent:SetSize(SCREEN_W or 1920, SCREEN_H or 1080)
UISpecialFrames = {}
GameTooltip = W.new("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT = m end }
SlashCmdList = {}
-- Timer laufen sofort; Verschachtelungstiefe zeigt Endlosschleifen.
C_Timer = { After = function(_, fn)
    REFRESH_DEPTH = REFRESH_DEPTH + 1
    MAX_DEPTH = math.max(MAX_DEPTH, REFRESH_DEPTH)
    if REFRESH_DEPTH < 50 then fn() end
    REFRESH_DEPTH = REFRESH_DEPTH - 1
end }
function GetLocale() return LOCALE or "deDE" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
function tinsert(t, v) table.insert(t, v) end
IN_INSTANCE = IN_INSTANCE or false
SHIFT_DOWN = SHIFT_DOWN or false
function IsShiftKeyDown() return SHIFT_DOWN end
BUILD = BUILD or "60000"
function GetBuildInfo() return "12.1.0", BUILD end
KickGuideDB = SAVED
-- Karten: MAP_ART[uiMap] = { w, h, tileW, tileH }; Texturen 1..n
MAP_ART = MAP_ART or {}
C_Map = {
    GetBestMapForUnit = function() return UIMAP end,
    GetMapArtLayers = function(id)
        local a = MAP_ART[id]
        return a and { { layerWidth = a[1], layerHeight = a[2], tileWidth = a[3], tileHeight = a[4] } } or {}
    end,
    GetMapArtLayerTextures = function(id)
        local a = MAP_ART[id]
        if not a then return {} end
        local t = {}
        for i = 1, math.ceil(a[1] / a[3]) * math.ceil(a[2] / a[4]) do t[i] = id * 100 + i end
        return t
    end,
}
-- Dungeonkompendium: ENCOUNTERS[uiMap] = { { encounterID, mapX, mapY } }
ENCOUNTERS = ENCOUNTERS or {}
C_EncounterJournal = { GetEncountersOnMap = function(id) return ENCOUNTERS[id] or {} end }
function IsInInstance() return IN_INSTANCE, IN_INSTANCE and "party" or "none" end
function SetPortraitTextureFromCreatureDisplayID(tex, id) tex.texture = "display:" .. id end

-- Zauber: SPELLS[id] = { name, icon, desc, important }
SPELLS = SPELLS or {}
SECRET_IMPORTANT = SECRET_IMPORTANT or false
C_Spell = {
    GetSpellInfo = function(id) local s = SPELLS[id]; return s and { name = s[1], iconID = s[2] } end,
    GetSpellDescription = function(id) local s = SPELLS[id]; return s and s[3] or "" end,
    IsSpellImportant = function(id)
        local s = SPELLS[id]
        if SECRET_IMPORTANT then return Secret() end
        return s and s[4] == true or false
    end,
}
-- Wie im Spiel: ist der Zauber schon geladen, ruft ContinueOnSpellLoad die
-- Rueckmeldung sofort auf. UNCACHED[id] = true: noch nicht geladen.
UNCACHED = UNCACHED or {}
REFRESH_DEPTH, MAX_DEPTH = 0, 0
Spell = { CreateFromSpellID = function(_, id)
    return {
        IsSpellEmpty = function() return false end,
        IsSpellDataCached = function() return not UNCACHED[id] end,
        ContinueOnSpellLoad = function(_, cb)
            LOADERS = (LOADERS or 0) + 1
            if not UNCACHED[id] then cb() else PENDING_LOADS = PENDING_LOADS or {}; table.insert(PENDING_LOADS, { id, cb }) end
        end,
    }
end }
function FinishSpellLoads()
    local list = PENDING_LOADS or {}
    PENDING_LOADS = {}
    for _, p in ipairs(list) do UNCACHED[p[1]] = nil; p[2]() end
end
MAP_TABLE = { 588, 586 }
C_ChallengeMode = {
    GetMapTable = function() return MAP_TABLE end,
    GetActiveChallengeMapID = function() return ACTIVE_MAP end,
    GetMapUIInfo = function(id)
        local names = LOCALE == "enUS" and { [588] = "Altar of Fangs", [586] = "Den of Nalorakk" } or { [588] = "Altar der Fänge", [586] = "Nalorakks Bau" }
        return names[id], id, 0, 1000 + id
    end,
}
C_MythicPlus = { RequestMapInfo = function() end }
-- Blizzard-Menü: letzte Menübeschreibung merken
MenuUtil = { CreateContextMenu = function(owner, generator)
    local menu = { owner = owner, radios = {} }
    local root = {
        CreateTitle = function(_, t) menu.title = t end,
        CreateRadio = function(_, text, isSelected, setSelected, data)
            table.insert(menu.radios, { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
        end,
    }
    generator(owner, root)
    MENU = menu
end }
LOADED_ADDONS = LOADED_ADDONS or {}
C_AddOns = { IsAddOnLoaded = function(name) return LOADED_ADDONS[name] == true end }
LibStub = nil

local ns = {}
for line in io.lines(ADDON_DIR .. "/KickGuide.toc") do
    if line:match("%.lua%s*$") and not line:match("^Libs") then
        assert(loadfile(ADDON_DIR .. "/" .. line:gsub("%s+$", "")))("KickGuide", ns)
    end
end

-- Testdaten ersetzen die echten Daten (gezielte Faelle).
if TEST_DATA then ns.DUNGEONS = TEST_DATA end
if TEST_KICK then ns.KICK = TEST_KICK end
if TEST_CC then ns.CC = TEST_CC end

local function fire(event, ...)
    for _, f in ipairs(ALL) do
        if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
return { ns = ns, fire = fire, all = ALL }

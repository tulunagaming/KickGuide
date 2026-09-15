-------------------------------------------------------------------------------
-- Guide-Fenster im Stil von KeyBar: Tooltip-Hintergrund, Dungeon-Kacheln mit
-- abgedunkeltem Kürzel-Streifen, Blizzard-Schriften, Cyan als Akzent.
--
-- Für den Run gedacht: bleibt offen (Esc schliesst nicht), Grösse per Ziehen
-- an der Ecke, verschieben mit Umschalt + Ziehen, beides gespeichert.
-- Mindestbreite: die längste Zauberüberschrift im Detailbereich passt in eine
-- Zeile; Beschreibungen brechen darunter um, das Fenster wird dafür höher.
--
--  normal                                   kompakt (im Run)
--  ┌ KickGuide                    x ┐       ┌ KickGuide       x ┐
--  │ [AOF][DON][MR][BV]…           │       │ [AOF]             │
--  │ ◂ ▾ Wichtige Caster │ [Bild]   │       │ ▸ │[Bild] Name    │
--  │   [Bild] Name   ☠2  │ Name     │       │☠2 │☠[Ik] Zauber   │
--  │ ▸ Bosse             │ ☠ Zauber │       │[B]│ Beschreibung… │
--  └────────────────────────────── ◢┘       └────────────────── ◢┘
--
-- Nichts hier ist geschützt; das Fenster darf im Kampf offen bleiben.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local L = ns.L

local CELL_SIZE, CELL_GAP, PADDING = 42, 4, 8
local DEFAULT_W, DEFAULT_H = 820, 560
local MIN_H, MAX_W, MAX_H = 320, 1600, 1300
local LIST_W = { normal = 270, compact = 52 }
local ROW_H = 38
local HEADER_H = 24
local SPELL_ICON = 32
local SPELL_INDENT = 20            -- Platz für den Totenkopf links vom Symbol
local DETAIL_PORTRAIT = 64
local MIN_DETAIL = 180
local TITLE_H = 24
local FOOTER_H = 28                -- Platz für zwei Zeilen Hinweis
local ACCENT = { 0.16, 0.83, 0.94 }          -- Cyan wie KeyBar
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local FALLBACK_PORTRAIT = "Interface\\Icons\\INV_Misc_QuestionMark"
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local COLLAPSE = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local EXPAND = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local GRABBER = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"   -- runde Maske, einfärbbar
local TAB_H = 18
local FLOOR_BAR_H = 24

-- Kürzel wie in KeyBar (Keystone-Karten-ID).
local SHORT = { [249] = "KR", [250] = "TOS", [399] = "RLP", [584] = "BV",
                [585] = "VSA", [586] = "DON", [587] = "MR", [588] = "AOF" }

local window
local SubText
local cells = {}
local selectedMap, selectedNpc
local shownFloor, floorForNpc      -- gezeigte Kartenebene; für welchen Caster sie gewählt wurde

local function Backdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, alpha or 0.6)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
end

local function Portrait(texture, npc)
    if npc and npc.display and npc.display > 0 and SetPortraitTextureFromCreatureDisplayID then
        SetPortraitTextureFromCreatureDisplayID(texture, npc.display)
    else
        texture:SetTexture(FALLBACK_PORTRAIT)
    end
end

local function ListMode() return ns.DB().listMode == "compact" and "compact" or "normal" end
local function ListWidth() return LIST_W[ListMode()] end

-------------------------------------------------------------------------------
-- Scrollbare Spalte (Mausrad)
-------------------------------------------------------------------------------

local function ScrollColumn(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (content.height or 0) - self:GetHeight())
        local v = math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(v)
    end)
    scroll.content = content
    return scroll
end

-------------------------------------------------------------------------------
-- Kartenansicht: Blizzard-Kartenbild der Ebene, ein Punkt je Mobgruppe
-------------------------------------------------------------------------------

local tiles, dots, floorButtons = {}, {}, {}

local function DetailView() return ns.DB().detailView == "map" and "map" or "spells" end

local function Dot(i)
    local dot = dots[i]
    if dot then return dot end
    local canvas = window.mapView.canvas
    dot = CreateFrame("Button", nil, canvas)
    dot.ring = dot:CreateTexture(nil, "ARTWORK", nil, 1)
    dot.ring:SetAllPoints()
    dot.ring:SetTexture(DOT)
    dot.ring:SetVertexColor(0, 0, 0, 0.9)
    dot.fill = dot:CreateTexture(nil, "ARTWORK", nil, 2)
    dot.fill:SetPoint("TOPLEFT", 2, -2)
    dot.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    dot.fill:SetTexture(DOT)
    dot:SetScript("OnClick", function(self)
        selectedNpc = self.npc and self.npc.id
        ns.RefreshGuide()
    end)
    dot:SetScript("OnEnter", function(self)
        if not self.npc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.NpcName(self.npc), 1, 1, 1)
        local count = ns.ImportantCount(self.npc)
        if count > 0 then GameTooltip:AddLine(string.format("|T%s:14|t %d", SKULL, count), 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dots[i] = dot
    return dot
end

local function FloorButton(i)
    local b = floorButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, window.mapView)
    b:SetSize(52, FLOOR_BAR_H - 4)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
    b.highlight:SetAllPoints()
    b.highlight:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnClick", function(self)
        shownFloor = self.floor
        ns.RefreshGuide()
    end)
    floorButtons[i] = b
    return b
end

-- MDT nur anbieten, wenn es geladen ist und seinen Befehl registriert hat.
local function MdtAvailable()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MythicDungeonTools")
    return loaded and SlashCmdList.MYTHICDUNGEONTOOLS ~= nil or false
end

local function HasPoints(npc, floor)
    return npc and npc.map and npc.map[floor] and #npc.map[floor] > 0 or false
end

local function ShowMap(npc, width, height)
    local view = window.mapView
    local canvas = view.canvas
    local floors = ns.Floors(selectedMap)

    -- Ebene: gewählter Caster nicht auf der gezeigten Ebene -> zu seiner wechseln.
    local valid = false
    for _, f in ipairs(floors) do if f == shownFloor then valid = true end end
    if not valid then shownFloor = floors[1] end
    if npc and floorForNpc ~= npc.id then
        floorForNpc = npc.id
        if not HasPoints(npc, shownFloor) then
            for _, f in ipairs(floors) do
                if HasPoints(npc, f) then shownFloor = f break end
            end
        end
    end

    -- Ebenen-Knöpfe (nur bei mehreren Ebenen), Ebenen des Casters in Cyan
    for i, floor in ipairs(floors) do
        local b = FloorButton(i)
        b.floor = floor
        b.text:SetText(string.format(L["Floor %d"], i))
        if HasPoints(npc, floor) then
            b.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else
            b.text:SetTextColor(0.8, 0.8, 0.8)
        end
        b.line:SetShown(floor == shownFloor)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", view, "TOPLEFT", (i - 1) * 54, 0)
        b:SetShown(#floors > 1)
    end
    for i = #floors + 1, #floorButtons do floorButtons[i]:Hide() end
    view.mdt:SetShown(MdtAvailable())

    if #floors == 0 then
        canvas:Hide()
        view.message:SetText(L["No map data."])
        view.message:Show()
        for _, t in ipairs(tiles) do t:Hide() end
        for _, dot in ipairs(dots) do dot:Hide() end
        return
    end

    local uiMap = ns.FloorMaps(selectedMap).maps[shownFloor]
    local art = ns.MapArt(uiMap)
    local aspect = art and (art.width / art.height) or 1.5
    local availH = math.max(60, height - FLOOR_BAR_H - 4)
    local w = math.min(width, availH * aspect)
    local h = w / aspect
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -FLOOR_BAR_H)
    canvas:SetSize(w, h)
    canvas:Show()

    local n = 0
    if art then
        local scale = w / art.width
        for row = 1, art.rows do
            for col = 1, art.cols do
                n = n + 1
                local t = tiles[n]
                if not t then
                    t = canvas:CreateTexture(nil, "ARTWORK")
                    tiles[n] = t
                end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (col - 1) * art.tileW * scale, -(row - 1) * art.tileH * scale)
                t:SetSize(art.tileW * scale, art.tileH * scale)
                t:SetTexture(art.textures[(row - 1) * art.cols + col])
                t:Show()
            end
        end
        view.message:Hide()
    else
        view.message:SetText(L["Map image not available."])
        view.message:Show()
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end

    -- Punkte: alle gelisteten Gegner der Ebene, der gewählte gross und oben.
    local casters, bosses = ns.ImportantNpcs(selectedMap)
    local count = 0
    local function Place(list, isBoss)
        for _, other in ipairs(list) do
            local selected = npc ~= nil and other.id == npc.id
            for _, p in ipairs(HasPoints(other, shownFloor) and other.map[shownFloor] or {}) do
                count = count + 1
                local dot = Dot(count)
                dot.npc = other
                local size = selected and 16 or (isBoss and 12 or 9)
                dot:SetSize(size, size)
                if selected then
                    dot.fill:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
                elseif isBoss then
                    dot.fill:SetVertexColor(1, 0.82, 0, 0.9)
                else
                    dot.fill:SetVertexColor(0.85, 0.85, 0.85, 0.8)
                end
                dot:SetFrameLevel(canvas:GetFrameLevel() + (selected and 5 or 2))
                dot.selected = selected
                dot.px, dot.py = p[1] / 100 * w, -p[2] / 100 * h
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", canvas, "TOPLEFT", dot.px, dot.py)
                dot:Show()
            end
        end
    end
    Place(casters, false)
    Place(bosses, true)
    for i = count + 1, #dots do dots[i]:Hide() end
end

-- Im Dungeon: Karte folgt der Ebene des Spielers.
function ns.OnFloorChanged()
    if not (window and window:IsShown()) or not selectedMap then return end
    if ns.CurrentDungeon() ~= selectedMap then return end
    local floor = ns.PlayerFloor(selectedMap)
    if floor and floor ~= shownFloor then
        shownFloor = floor
        ns.RefreshGuide()
    end
end

-------------------------------------------------------------------------------
-- Detailbereich: Bild, Name, darunter die Zauber
-------------------------------------------------------------------------------

local spellRows = {}

-- Rechtsklick-Menü: Stun für den Gegner selbst markieren (Blizzard-Menü).
local function OpenStunMenu(owner, npc)
    if not (npc and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.NpcName(npc))
        local function IsSelected(mark) return ns.StunMark(npc) == mark end
        local function SetSelected(mark)
            ns.SetStunMark(npc, mark)
            ns.RefreshGuide()
        end
        root:CreateRadio(L["Stunnable"], IsSelected, SetSelected, "yes")
        root:CreateRadio(L["Stun immune"], IsSelected, SetSelected, "no")
        root:CreateRadio(L["No own mark (MDT data if available)"], IsSelected, SetSelected, "none")
    end)
end

local function OnRightClick(self, button)
    if button == "RightButton" then OpenStunMenu(self, window.detailNpc) end
end

local function SpellRow(i)
    local row = spellRows[i]
    if row then return row end
    local content = window.spells.content
    row = CreateFrame("Frame", nil, content)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(SPELL_ICON, SPELL_ICON)
    row.icon:SetPoint("TOPLEFT", SPELL_INDENT, 0)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    row.skull = row:CreateTexture(nil, "OVERLAY")
    row.skull:SetSize(16, 16)
    row.skull:SetPoint("RIGHT", row.icon, "LEFT", -3, 0)
    row.skull:SetTexture(SKULL)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    row.tag:SetPoint("TOPLEFT", row.name, "TOPRIGHT", 6, -1)
    row.tag:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetJustifyV("TOP")
    row.desc:SetWordWrap(true)
    -- Blizzards Zauber-Tooltip beim Überfahren des Symbols.
    row.hover = CreateFrame("Frame", nil, row)
    row.hover:SetAllPoints(row.icon)
    row.hover:EnableMouse(true)
    row.hover:SetScript("OnEnter", function(self)
        if not row.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(row.spellID)
        GameTooltip:AddLine(L["Right-click: mark stun"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", OnRightClick)
    row.hover:SetScript("OnMouseUp", OnRightClick)
    row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    spellRows[i] = row
    return row
end

local pendingLoad = false
local requested = {}      -- Zauber-ID -> schon angefordert

-- Zauberdaten sind beim ersten Öffnen evtl. noch nicht im Speicher. Nur solche
-- anfordern, und jede nur einmal: ContinueOnSpellLoad ruft bei schon geladenen
-- Zaubern sofort zurück, sonst baute sich das Fenster endlos neu auf.
local function RequestSpellData(npc)
    if not (Spell and Spell.CreateFromSpellID) then return end
    for _, id in ipairs(npc.spells) do
        if not requested[id] then
            local spell = Spell:CreateFromSpellID(id)
            local cached = spell and spell.IsSpellDataCached and spell:IsSpellDataCached()
            if spell and not cached and spell.IsSpellEmpty and not spell:IsSpellEmpty() and spell.ContinueOnSpellLoad then
                requested[id] = true
                spell:ContinueOnSpellLoad(function()
                    if pendingLoad then return end
                    pendingLoad = true
                    C_Timer.After(0.1, function()
                        pendingLoad = false
                        if window and window:IsShown() then ns.RefreshGuide() end
                    end)
                end)
            end
        end
    end
end

-- Breite, die eine Zauberüberschrift braucht (Totenkopf, Symbol, Name, "Wichtig").
SubText = function(npc)
    return (ns.DungeonInfo(selectedMap)) .. "  ·  " .. (npc.boss and L["Boss"] or L["Trash"])
end

-- Hinweise hinter dem Zaubernamen: "Wichtig", "Kick" (grün) / "Kein Kick" (orange).
-- Bei "Kein Kick" dahinter, ob der Mob stunbar ist (MDT-Daten).
local function TagText(g, npc)
    local parts = {}
    if g.important then table.insert(parts, "|cff29d4f0" .. L["Important"] .. "|r") end
    if g.kick == true then
        table.insert(parts, "|cff33dd55" .. L["Kick"] .. "|r")
    elseif g.kick == false then
        local text = "|cffff8c1a" .. L["No kick"] .. "|r"
        local stun = ns.Stunnable(npc)
        if stun == true then
            text = text .. " · |cff33dd55" .. L["Stun"] .. "|r"
        elseif stun == false then
            text = text .. " · |cffff4040" .. L["Stun immune"] .. "|r"
        end
        table.insert(parts, text)
    end
    return table.concat(parts, "  ")
end

local function HeadingWidth(groups, npc)
    local measure = window.measure
    local widest = 0
    for _, g in ipairs(groups) do
        measure:SetText(g.name)
        local w = SPELL_INDENT + SPELL_ICON + 8 + math.ceil(measure:GetStringWidth() or 0)
        local tag = TagText(g, npc)
        if tag ~= "" then
            window.measureTag:SetText(tag)
            w = w + 6 + math.ceil(window.measureTag:GetStringWidth() or 0)
        end
        widest = math.max(widest, w + 8)
    end
    return widest
end

-- Breite des Kopfes: Bild, daneben Name und "Dungeon · Art" je in einer Zeile.
local function HeaderWidth(npc)
    window.measureName:SetText(ns.NpcName(npc))
    window.measureSub:SetText(SubText(npc))
    local text = math.max(window.measureName:GetStringWidth() or 0, window.measureSub:GetStringWidth() or 0)
    return DETAIL_PORTRAIT + 12 + math.ceil(text) + 8
end

local function ShowDetail(npc, width, height)
    local d = window.detail
    window.detailNpc = npc
    local view = DetailView()
    for _, row in ipairs(spellRows) do row:Hide() end
    d.tabSpells.line:SetShown(view == "spells")
    d.tabMap.line:SetShown(view == "map")
    window.spells:SetShown(view == "spells")
    window.mapView:SetShown(view == "map")
    local textW = math.max(40, width - DETAIL_PORTRAIT - 12)
    d.name:SetWidth(textW)
    d.sub:SetWidth(textW)
    if not npc then
        d.portrait:Hide()
        window.spells.content.height = 0
        window.spells.shownNpc = nil
        if view == "map" then
            -- Karte auch ohne Auswahl: Punkt anklicken wählt den Caster.
            d.hint:Hide()
            d.line:Show()
            d.name:SetText((ns.DungeonInfo(selectedMap)))
            d.sub:SetText(L["Click a point to choose a caster."])
            ShowMap(nil, width, height)
        else
            d.name:SetText("")
            d.sub:SetText("")
            d.line:Hide()
            d.hint:Show()
        end
        return
    end
    d.hint:Hide()
    d.portrait:Show()
    d.line:Show()
    Portrait(d.portrait, npc)
    d.name:SetText(ns.NpcName(npc))
    d.sub:SetText(SubText(npc))
    if view == "map" then
        ShowMap(npc, width, height)
        return
    end

    local y = 0
    for i, g in ipairs(npc._groups) do
        local row = SpellRow(i)
        row.spellID = g.importantID or g.ids[1]
        row.icon:SetTexture(g.icon)
        row.icon:SetDesaturated(not g.important)
        row.skull:SetShown(g.important)
        if g.important then
            row.name:SetTextColor(1, 0.82, 0)
        else
            row.name:SetTextColor(0.75, 0.75, 0.75)
        end
        local tag = TagText(g, npc)
        row.tag:SetText(tag)
        local tagW = tag ~= "" and (6 + math.ceil(row.tag:GetStringWidth() or 0)) or 0
        local textLeft = SPELL_INDENT + SPELL_ICON + 8
        row.name:SetWidth(math.max(40, width - textLeft - tagW - 4))
        row.name:SetText(g.name)
        row.desc:SetWidth(math.max(40, width - textLeft - 4))
        row.desc:SetText(g.description or L["No description."])
        local shade = g.important and 0.9 or 0.6
        row.desc:SetTextColor(shade, shade, shade)
        local textH = (row.name:GetStringHeight() or 14) + 3 + (row.desc:GetStringHeight() or 12)
        local h = math.max(SPELL_ICON, textH) + 12
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.spells.content, "TOPLEFT", 0, -y)
        row:SetSize(width, h)
        row:Show()
        y = y + h
    end
    window.spells.content:SetSize(width, math.max(1, y))
    window.spells.content.height = y
    if window.spells.shownNpc ~= npc.id then window.spells:SetVerticalScroll(0) end
    window.spells.shownNpc = npc.id
    RequestSpellData(npc)
end

-------------------------------------------------------------------------------
-- Liste: aufklappbare Gruppen, zwei Stufen (normal / kompakt)
-------------------------------------------------------------------------------

local npcRows, headers = {}, {}

local function NpcRow(i)
    local row = npcRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, window.list.content)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.06)
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(ROW_H - 6, ROW_H - 6)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.skull = row:CreateTexture(nil, "OVERLAY")
    row.skull:SetSize(14, 14)
    row.skull:SetTexture(SKULL)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnClick", function(self)
        selectedNpc = self.npc and self.npc.id
        -- Neuer Caster aus der Liste: rechts immer seine Zauber zeigen.
        ns.DB().detailView = "spells"
        ns.RefreshGuide()
    end)
    -- Kompakt steht kein Name da: dann im Tooltip.
    row:SetScript("OnEnter", function(self)
        if ListMode() ~= "compact" or not self.npc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.NpcName(self.npc), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    npcRows[i] = row
    return row
end

-- Anordnung einer Zeile je nach Stufe.
local function ArrangeRow(row, mode)
    row.portrait:ClearAllPoints()
    row.skull:ClearAllPoints()
    row.count:ClearAllPoints()
    row.name:ClearAllPoints()
    if mode == "compact" then
        row.portrait:SetPoint("LEFT", 4, 0)
        row.skull:SetPoint("BOTTOMRIGHT", -1, 2)
        row.count:SetPoint("TOPRIGHT", -2, -2)
        row.name:Hide()
    else
        row.portrait:SetPoint("LEFT", 18, 0)
        row.skull:SetPoint("RIGHT", -8, 0)
        row.count:SetPoint("RIGHT", row.skull, "LEFT", -2, 0)
        row.name:SetPoint("LEFT", row.portrait, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.name:Show()
    end
end

local function Header(key)
    local h = headers[key]
    if h then return h end
    h = CreateFrame("Button", nil, window.list.content)
    h:SetHeight(HEADER_H)
    h.toggle = h:CreateTexture(nil, "ARTWORK")
    h.toggle:SetSize(14, 14)
    h.toggle:SetPoint("LEFT", 2, 0)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", h.toggle, "RIGHT", 4, 0)
    h.text:SetJustifyH("LEFT")
    h.text:SetWordWrap(false)
    h.highlight = h:CreateTexture(nil, "HIGHLIGHT")
    h.highlight:SetAllPoints()
    h.highlight:SetColorTexture(1, 1, 1, 0.05)
    h.key = key
    h:SetScript("OnClick", function(self)
        local collapsed = ns.DB().collapsed
        collapsed[self.key] = not collapsed[self.key]
        ns.RefreshGuide()
    end)
    headers[key] = h
    return h
end

local function FillList(width)
    local list = window.list
    local mode = ListMode()
    for _, row in ipairs(npcRows) do row:Hide() end
    for _, h in pairs(headers) do h:Hide() end

    local casters, bosses = ns.ImportantNpcs(selectedMap)
    local collapsed = ns.DB().collapsed
    local y, n, selected = 0, 0, nil
    local function Section(key, title, npcs)
        if #npcs == 0 then return end
        local h = Header(key)
        local open = not collapsed[key]
        h.toggle:SetTexture(open and MINUS or PLUS)
        h.text:SetText(mode == "compact" and tostring(#npcs) or string.format("%s (%d)", title, #npcs))
        h.text:SetWidth(math.max(10, width - 24))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
        h:SetWidth(width)
        h:Show()
        y = y + HEADER_H + 2
        for _, npc in ipairs(npcs) do
            -- Auswahl bleibt erhalten, auch wenn ihre Gruppe zugeklappt ist.
            if selectedNpc == npc.id then selected = npc end
            if open then
                n = n + 1
                local row = NpcRow(n)
                row.npc = npc
                ArrangeRow(row, mode)
                Portrait(row.portrait, npc)
                row.name:SetText(ns.NpcName(npc))
                local count = ns.ImportantCount(npc)
                row.count:SetText(count > 0 and count or "")
                row.skull:SetShown(count > 0)
                local isSelected = selectedNpc == npc.id
                row.mark:SetShown(isSelected)
                row.bg:SetShown(isSelected)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
                row:SetWidth(width)
                row:Show()
                y = y + ROW_H + 2
            end
        end
        y = y + 6
    end
    Section("casters", L["Important casters"], casters)
    Section("bosses", L["Bosses"], bosses)

    list.empty:SetShown(#casters + #bosses == 0 and mode == "normal")
    list.empty:SetWidth(math.max(10, width - 8))
    list.content:SetSize(width, math.max(1, y))
    list.content.height = y
    return selected
end

-------------------------------------------------------------------------------
-- Dungeon-Kacheln (wie KeyBar)
-------------------------------------------------------------------------------

local function Cell(i)
    local cell = cells[i]
    if cell then return cell end
    cell = CreateFrame("Button", nil, window)
    cell:SetSize(CELL_SIZE, CELL_SIZE)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    cell.topShade = cell:CreateTexture(nil, "OVERLAY", nil, 1)
    cell.topShade:SetPoint("TOPLEFT")
    cell.topShade:SetPoint("TOPRIGHT")
    cell.topShade:SetHeight(13)
    cell.topShade:SetColorTexture(0, 0, 0, 0.7)
    cell.short = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    cell.short:SetPoint("TOPLEFT", 1, -1)
    cell.short:SetPoint("TOPRIGHT", -1, -1)
    cell.short:SetJustifyH("CENTER")
    cell.selMark = cell:CreateTexture(nil, "OVERLAY", nil, 2)
    cell.selMark:SetPoint("BOTTOMLEFT", 1, 0)
    cell.selMark:SetPoint("BOTTOMRIGHT", -1, 0)
    cell.selMark:SetHeight(3)
    cell.selMark:SetColorTexture(0.2, 0.9, 1.0, 0.9)
    cell:SetScript("OnClick", function(self)
        selectedMap = self.mapID
        selectedNpc, shownFloor, floorForNpc = nil, nil, nil
        ns.DB().lastDungeon = self.mapID
        ns.RefreshGuide()
    end)
    cell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine((ns.DungeonInfo(self.mapID)), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = cell
    return cell
end

-- Kacheln anordnen; liefert die Höhe des Kopfbereichs.
local function ShownMaps()
    -- Im Dungeon genügt die Kachel des aktuellen Dungeons.
    local current = ns.CurrentDungeon()
    if current then return { current } end
    return ns.SeasonDungeons()
end

-- Kacheln stehen immer in einer Reihe unter der Überschrift (kein Umbrechen,
-- die Mindestbreite des Fensters lässt Platz für alle).
local function FillCells()
    local maps = ShownMaps()
    for i, mapID in ipairs(maps) do
        local cell = Cell(i)
        cell.mapID = mapID
        local name, texture = ns.DungeonInfo(mapID)
        cell.icon:SetTexture(texture or FALLBACK_PORTRAIT)
        cell.short:SetText(SHORT[mapID] or string.sub(name, 1, 3))
        local isSelected = mapID == selectedMap
        cell.selMark:SetShown(isSelected)
        local shade = isSelected and 1 or 0.6
        cell.icon:SetVertexColor(shade, shade, shade)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING * 2 + (i - 1) * (CELL_SIZE + CELL_GAP),
                      -(PADDING * 2 + TITLE_H))
        cell:Show()
    end
    for i = #maps + 1, #cells do cells[i]:Hide() end
    return PADDING * 2 + TITLE_H + CELL_SIZE + PADDING
end

local function CellsWidth()
    local n = #ShownMaps()
    return PADDING * 2 + n * (CELL_SIZE + CELL_GAP) - CELL_GAP + PADDING * 2
end

-------------------------------------------------------------------------------
-- Anordnung nach Fenstergrösse
-------------------------------------------------------------------------------

local function ApplyListMode()
    local compact = ListMode() == "compact"
    window.collapseButton:SetNormalTexture(compact and EXPAND or COLLAPSE)
    window.collapseButton:SetPushedTexture(compact and EXPAND or COLLAPSE)
end

-- Mindestbreite des Fensters für den gewählten Caster.
-- Rand links neben dem Detailbereich (Liste, Abstand, Trennlinie) und rechts.
local function DetailOuter()
    return (PADDING * 2 + ListWidth() + PADDING + 1 + PADDING * 2) + PADDING * 2 + 12
end

local function MinWidth(npc)
    local detailMin = MIN_DETAIL
    if npc then detailMin = math.max(detailMin, HeadingWidth(npc._groups, npc), HeaderWidth(npc)) end
    return math.max(CellsWidth(), DetailOuter() + detailMin)
end

local ApplyResizeBounds

local function SaveGeometry()
    local db = ns.DB()
    db.size = { math.floor(window:GetWidth() + 0.5), math.floor(window:GetHeight() + 0.5) }
    local point, _, relPoint, x, y = window:GetPoint(1)
    if point then db.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

-- Fenster nie grösser als der Bildschirm und immer vollständig darauf, sonst
-- liegt die Zieh-Ecke ausserhalb und das Fenster lässt sich nicht mehr ändern.
-- Nur für Änderungen durch das Addon selbst (neuer Caster macht es breiter,
-- gespeicherte Grösse passt nicht mehr); beim Ziehen hält WoWs Klammer es auf
-- dem Bildschirm, dann wird hier nicht dazwischen geschoben.
local function FitToScreen()
    if window.moving or window.isSizing then return end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (sw and sh and sw > 0 and sh > 0) then return end
    local w = math.min(window:GetWidth(), sw)
    local h = math.min(window:GetHeight(), sh)
    local changed = false
    if w < window:GetWidth() or h < window:GetHeight() then
        window.layoutLock = true
        window:SetSize(w, h)
        window.layoutLock = false
        changed = true
    end
    local left, top = window:GetLeft(), window:GetTop()
    if left and top then
        local newLeft = math.max(0, math.min(left, sw - w))
        local newTop = math.min(sh, math.max(top, h))
        if math.abs(newLeft - left) > 0.5 or math.abs(newTop - top) > 0.5 then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
            changed = true
        end
    end
    if changed then SaveGeometry() end
end

-- Grenzen fürs Ziehen an der Ecke unten rechts: von der aktuellen Stelle bis
-- zum rechten und unteren Bildschirmrand, damit das Fenster nicht über den
-- Rand wächst (sonst läuft die Maus davon und es springt beim Loslassen).
ApplyResizeBounds = function(minW)
    if not window.SetResizeBounds then return end
    local sw, sh = UIParent:GetWidth() or MAX_W, UIParent:GetHeight() or MAX_H
    local left, top = window:GetLeft(), window:GetTop()
    local roomW = left and (sw - left) or sw
    local roomH = top or sh
    local maxW = math.max(minW, math.min(MAX_W, roomW))
    local maxH = math.max(MIN_H, math.min(MAX_H, roomH))
    window.minW = minW
    window:SetResizeBounds(minW, MIN_H, maxW, maxH)
end

-- Notausgang: Grösse und Position zurück auf Anfang.
function ns.ResetGuideGeometry()
    local db = ns.DB()
    db.size, db.point = nil, nil
    if not window then return end
    window:ClearAllPoints()
    window:SetPoint("CENTER")
    window.layoutLock = true
    window:SetSize(DEFAULT_W, DEFAULT_H)
    window.layoutLock = false
    ns.RefreshGuide()
end

function ns.RefreshGuide()
    if not window then return end
    if not selectedMap or not ns.DUNGEONS[selectedMap] then
        local current = ns.CurrentDungeon()
        local last = ns.DB().lastDungeon
        local maps = ns.SeasonDungeons()
        selectedMap = current or ((last and ns.DUNGEONS[last]) and last) or maps[1]
    end

    -- Nichts gewählt (Öffnen, Dungeonwechsel): ersten Eintrag der Liste nehmen,
    -- damit rechts nie eine leere Seite steht.
    if not selectedNpc then
        local casters, bosses = ns.ImportantNpcs(selectedMap)
        local first = casters[1] or bosses[1]
        selectedNpc = first and first.id
    end

    -- Gewählten Caster mit seinen Zaubern vorbereiten (für Mindestbreite und Anzeige).
    local d = ns.DUNGEONS[selectedMap]
    local npc
    if d and selectedNpc then
        for _, candidate in ipairs(d.npcs) do
            if candidate.id == selectedNpc then npc = candidate break end
        end
    end
    if npc then npc._groups = ns.SpellGroups(npc) end

    -- Grösse: Mindestbreite durchsetzen.
    local minW = MinWidth(npc)
    ApplyResizeBounds(minW)
    if window:GetWidth() < minW and not window.isSizing then
        window.layoutLock = true
        window:SetWidth(minW)
        window.layoutLock = false
    end
    FitToScreen()
    local width, height = window:GetWidth(), window:GetHeight()

    ApplyListMode()
    local top = FillCells()
    local listW = ListWidth()
    window.collapseButton:ClearAllPoints()
    window.collapseButton:SetPoint("TOPLEFT", PADDING * 2, -top)
    window.list:ClearAllPoints()
    window.list:SetPoint("TOPLEFT", window.collapseButton, "BOTTOMLEFT", 0, -4)
    window.list:SetPoint("BOTTOMLEFT", PADDING * 2, PADDING * 2 + FOOTER_H)
    window.list:SetWidth(listW)
    window.divider:ClearAllPoints()
    window.divider:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING * 2 + listW + PADDING, -top)
    window.divider:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PADDING * 2 + listW + PADDING, PADDING * 2 + FOOTER_H)
    window.detail:ClearAllPoints()
    window.detail:SetPoint("TOPLEFT", window.divider, "TOPRIGHT", PADDING * 2, 0)
    window.detail:SetPoint("BOTTOMRIGHT", -PADDING * 2, PADDING * 2 + FOOTER_H)
    local detailW = width - DetailOuter()

    local selected = FillList(listW - 4)
    local detailH = height - top - (PADDING * 2 + FOOTER_H) - (TAB_H + 4 + DETAIL_PORTRAIT + PADDING * 2 + 1)
    ShowDetail(selected, math.max(MIN_DETAIL, detailW), detailH)

    local inInstance = IsInInstance and IsInInstance()
    if inInstance and not ns.HasImportanceStore() then
        window.footer:SetText(L["No stored marks yet: visit a city or the open world once, then the skulls also show in dungeons."])
    elseif inInstance then
        window.footer:SetText(string.format(L["Marks stored outside the dungeon (%s)."], ns.DATA_SOURCE or "?"))
    else
        window.footer:SetText(string.format(L["Important casts are marked by Blizzard. Data: %s."], ns.DATA_SOURCE or "?"))
    end
end

-- Beim Ziehen an der Grösse: neu anordnen (höchstens einmal je Bild).
local layoutQueued = false
local function QueueLayout()
    if layoutQueued or window.layoutLock then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        if window:IsShown() then ns.RefreshGuide() end
    end)
end

-------------------------------------------------------------------------------
-- Fenster
-------------------------------------------------------------------------------

local function Build()
    local db = ns.DB()
    window = CreateFrame("Frame", "KickGuideFrame", UIParent, "BackdropTemplate")
    local size = db.size
    window:SetSize(size and size[1] or DEFAULT_W, size and size[2] or DEFAULT_H)
    if db.point then
        window:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    -- Nur mit Umschalt verschieben, damit im Kampf nichts versehentlich wandert.
    window:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.moving = true
            self:StartMoving()
        end
    end)
    window:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SaveGeometry()
        ApplyResizeBounds(self.minW or MIN_DETAIL)
    end)
    window:SetScript("OnSizeChanged", QueueLayout)
    Backdrop(window, 0.6)          -- wie KeyBar
    -- Bewusst nicht in UISpecialFrames: Esc soll das Fenster im Run nicht schliessen.

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.title:SetPoint("TOPLEFT", PADDING * 2, -PADDING * 2 - 2)
    window.title:SetText(ADDON_NAME)

    -- Unsichtbare Messschrift für die Mindestbreite.
    window.measure = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.measure:Hide()
    window.measureTag = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    window.measureTag:Hide()
    window.measureName = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.measureName:Hide()
    window.measureSub = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.measureSub:Hide()

    window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.close:SetPoint("TOPRIGHT", -2, -2)

    window.collapseButton = CreateFrame("Button", nil, window)
    window.collapseButton:SetSize(24, 24)
    window.collapseButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    window.collapseButton:SetScript("OnClick", function()
        local db2 = ns.DB()
        db2.listMode = (db2.listMode == "compact") and "normal" or "compact"
        ns.RefreshGuide()
    end)
    window.collapseButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ListMode() == "compact" and L["Full list"] or L["Compact list"], 1, 1, 1)
        GameTooltip:Show()
    end)
    window.collapseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.list = ScrollColumn(window)
    window.list.empty = window.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.list.empty:SetPoint("TOPLEFT", 4, -4)
    window.list.empty:SetJustifyH("LEFT")
    window.list.empty:SetWordWrap(true)
    window.list.empty:SetText(L["No important casters found for this dungeon."])

    window.divider = window:CreateTexture(nil, "ARTWORK")
    window.divider:SetColorTexture(0.35, 0.35, 0.35, 0.6)
    window.divider:SetWidth(1)

    -- Detailbereich: Bild und Name oben, darunter die Zauberliste
    local d = CreateFrame("Frame", nil, window)
    d.portrait = d:CreateTexture(nil, "ARTWORK")
    d.portrait:SetSize(DETAIL_PORTRAIT, DETAIL_PORTRAIT)
    d.portrait:SetPoint("TOPLEFT", 0, -(TAB_H + 4))
    -- Rechtsklick auf das Bild: Stun markieren
    d.stunTarget = CreateFrame("Button", nil, d)
    d.stunTarget:SetAllPoints(d.portrait)
    d.stunTarget:RegisterForClicks("RightButtonUp")
    d.stunTarget:SetScript("OnClick", function(self) OpenStunMenu(self, window.detailNpc) end)
    d.stunTarget:SetScript("OnEnter", function(self)
        if not window.detailNpc then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.NpcName(window.detailNpc), 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: mark stun"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    d.stunTarget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.portrait, "TOPRIGHT", 12, -6)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(true)
    d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetJustifyH("LEFT")
    d.sub:SetWordWrap(true)
    d.sub:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    d.line = d:CreateTexture(nil, "ARTWORK")
    d.line:SetColorTexture(0.35, 0.35, 0.35, 0.6)
    d.line:SetHeight(1)
    d.line:SetPoint("TOPLEFT", d.portrait, "BOTTOMLEFT", 0, -PADDING)
    d.line:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    -- Umschalter Zauber / Karte oben rechts
    local function Tab(label, key)
        local tab = CreateFrame("Button", nil, d)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(label)
        tab:SetSize(math.ceil(tab.text:GetStringWidth() or 40) + 12, TAB_H)
        tab.line = tab:CreateTexture(nil, "OVERLAY")
        tab.line:SetPoint("BOTTOMLEFT")
        tab.line:SetPoint("BOTTOMRIGHT")
        tab.line:SetHeight(2)
        tab.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
        tab.highlight:SetAllPoints()
        tab.highlight:SetColorTexture(1, 1, 1, 0.08)
        tab.view = key
        tab:SetScript("OnClick", function(self)
            ns.DB().detailView = self.view
            ns.RefreshGuide()
        end)
        return tab
    end
    d.tabMap = Tab(L["Map"], "map")
    d.tabMap:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
    d.tabSpells = Tab(L["Casts"], "spells")
    d.tabSpells:SetPoint("RIGHT", d.tabMap, "LEFT", -4, 0)
    d.tabs = d.tabMap:GetWidth() + d.tabSpells:GetWidth() + 8

    d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    d.hint:SetPoint("TOPLEFT", 0, -(TAB_H + 8))
    d.hint:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.hint:SetJustifyH("LEFT")
    d.hint:SetWordWrap(true)
    d.hint:SetText(L["Choose a caster on the left."])
    window.detail = d

    window.spells = ScrollColumn(d)
    window.spells:SetPoint("TOPLEFT", d.line, "BOTTOMLEFT", 0, -PADDING)
    window.spells:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)

    local mapView = CreateFrame("Frame", nil, d)
    mapView:SetPoint("TOPLEFT", d.line, "BOTTOMLEFT", 0, -PADDING)
    mapView:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
    mapView.canvas = CreateFrame("Frame", nil, mapView, "BackdropTemplate")
    mapView.canvas:SetClipsChildren(true)
    Backdrop(mapView.canvas, 0.5)
    mapView.message = mapView:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mapView.message:SetPoint("TOPLEFT", mapView, "TOPLEFT", 6, -FLOOR_BAR_H - 6)
    mapView.message:SetJustifyH("LEFT")
    mapView.mdt = CreateFrame("Button", nil, mapView, "UIPanelButtonTemplate")
    mapView.mdt:SetSize(90, FLOOR_BAR_H - 4)
    mapView.mdt:SetPoint("TOPRIGHT", mapView, "TOPRIGHT", 0, 0)
    mapView.mdt:SetText(L["Open MDT"])
    mapView.mdt:SetScript("OnClick", function()
        if MdtAvailable() then SlashCmdList.MYTHICDUNGEONTOOLS("") end
    end)
    mapView:Hide()
    window.mapView = mapView

    window.footer = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.footer:SetPoint("BOTTOMLEFT", PADDING * 2, PADDING + 4)
    window.footer:SetPoint("BOTTOMRIGHT", -PADDING * 2 - 16, PADDING + 4)
    window.footer:SetJustifyH("LEFT")
    window.footer:SetWordWrap(true)
    window.footer:SetMaxLines(2)

    -- Zieh-Ecke unten rechts (Blizzard-Grafik)
    window.grabber = CreateFrame("Button", nil, window)
    window.grabber:SetSize(16, 16)
    window.grabber:SetPoint("BOTTOMRIGHT", -4, 4)
    window.grabber:SetNormalTexture(GRABBER .. "Up")
    window.grabber:SetHighlightTexture(GRABBER .. "Highlight")
    window.grabber:SetPushedTexture(GRABBER .. "Down")
    window.grabber:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            ApplyResizeBounds(window.minW or MIN_DETAIL)
            window.isSizing = true
            window:StartSizing("BOTTOMRIGHT")
        end
    end)
    window.grabber:SetScript("OnMouseUp", function()
        window.isSizing = false
        window:StopMovingOrSizing()
        window:SetUserPlaced(false)
        SaveGeometry()
        ns.RefreshGuide()
    end)
    window.grabber:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Drag: resize window"], 1, 1, 1)
        GameTooltip:AddLine(L["Shift-drag: move window"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    window.grabber:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window:Hide()
end

-- Zonenwechsel: im Dungeon automatisch dessen Caster zeigen.
function ns.OnZoneChanged()
    if not (window and window:IsShown()) then return end
    local current = ns.CurrentDungeon()
    if current and current ~= selectedMap then
        selectedMap, selectedNpc, shownFloor, floorForNpc = current, nil, nil, nil
    end
    if current then shownFloor = ns.PlayerFloor(current) or shownFloor end
    ns.RefreshGuide()
end

function ns.ToggleGuide()
    if not window then Build() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        local current = ns.CurrentDungeon()
        if current and current ~= selectedMap then selectedMap, selectedNpc, shownFloor, floorForNpc = current, nil, nil, nil end
        if current then shownFloor = ns.PlayerFloor(current) or shownFloor end
        ns.RefreshGuide()
    end
end

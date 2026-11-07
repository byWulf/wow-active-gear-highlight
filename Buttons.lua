local _, ns = ...
local L = ns.L

-- Every action button we know of, from any action bar addon. Buttons are matched by the action slot they show,
-- so the bar addon doesn't matter as long as its buttons are found.
local buttons = {}
local overlays = {}
local shownState = {}

local HasAction = (C_ActionBar and C_ActionBar.HasAction) or HasAction

-- Buttons by name: Blizzard's bars, Bartender4, Dominos, EllesmereUI, ElvUI and DaylightUI.
local NAMED = {
    { "ActionButton", 12 },
    { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 },
    { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 },
    { "MultiBar7Button", 12 },
    { "BonusActionButton", 12 },
    { "BT4Button", 180 },
    { "DominosActionButton", 180 },
    { "MultiBarRightActionButton", 12 },
    { "MultiBarLeftActionButton", 12 },
    { "MultiBarBottomRightActionButton", 12 },
    { "MultiBarBottomLeftActionButton", 12 },
    { "MultiBar5ActionButton", 12 },
    { "MultiBar6ActionButton", 12 },
    { "MultiBar7ActionButton", 12 },
    { "EABButton", 180 },
}
for bar = 1, 15 do
    NAMED[#NAMED + 1] = { "ElvUI_Bar" .. bar .. "Button", 12 }
end
for bar = 1, 10 do
    NAMED[#NAMED + 1] = { "DaylightUIBar" .. bar .. "Button", 12 }
end

local LAB_MAJORS = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }

-- Values in combat may be secret in this client; treat those as unknown.
local function Readable(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return true
end

local function IsUsableFrame(frame)
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(function()
        return frame.IsForbidden and frame:IsForbidden()
    end)
    return ok and not forbidden
end

local function Add(button)
    if not buttons[button] and IsUsableFrame(button) then
        buttons[button] = true
    end
end

local function LooksLikeActionButton(frame)
    local ok, result = pcall(function()
        if frame:IsForbidden() or not frame:IsObjectType("Button") then
            return false
        end
        if frame._state_type ~= nil then
            return true -- LibActionButton
        end
        return type(frame.action) == "number" and (frame.icon ~= nil or frame.Icon ~= nil)
    end)
    return ok and result
end

-- Finds the buttons; `full` also walks all frames once, for action bar addons not listed above.
function ns.CollectButtons(full)
    for _, entry in ipairs(NAMED) do
        for index = 1, entry[2] do
            local button = _G[entry[1] .. index]
            if button then
                Add(button)
            end
        end
    end
    if ActionBarButtonEventsFrame and type(ActionBarButtonEventsFrame.frames) == "table" then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            Add(button)
        end
    end
    if LibStub then
        for _, major in ipairs(LAB_MAJORS) do
            local lab = LibStub(major, true)
            if lab and lab.GetAllButtons then
                for button in pairs(lab:GetAllButtons()) do
                    Add(button)
                end
            end
        end
    end
    if full and EnumerateFrames then
        local frame = EnumerateFrames()
        while frame do
            if not buttons[frame] and LooksLikeActionButton(frame) then
                Add(frame)
            end
            frame = EnumerateFrames(frame)
        end
    end
end

function ns.RequestButtonScan(full)
    ns.scanFull = ns.scanFull or full
    if ns.scanPending then
        return
    end
    ns.scanPending = true
    C_Timer.After(full and 2 or 1, function()
        ns.scanPending = false
        local isFull = ns.scanFull
        ns.scanFull = false
        ns.CollectButtons(isFull)
        ns.UpdateButtons()
    end)
end

function ns.RequestButtonUpdate()
    if ns.buttonUpdatePending then
        return
    end
    ns.buttonUpdatePending = true
    C_Timer.After(0.05, function()
        ns.buttonUpdatePending = false
        ns.UpdateButtons()
    end)
end

function ns.InstallLibActionButtonHooks()
    if not LibStub then
        return
    end
    for _, major in ipairs(LAB_MAJORS) do
        local lab = LibStub(major, true)
        if lab and lab.RegisterCallback then
            local owner = {}
            lab.RegisterCallback(owner, "OnButtonCreated", function(_, button)
                Add(button)
                ns.RequestButtonUpdate()
            end)
            lab.RegisterCallback(owner, "OnButtonContentsChanged", function()
                ns.RequestButtonUpdate()
            end)
        end
    end
end

---------------------------------------------------------------------------
-- What a button shows

local function ButtonSlot(button)
    local slot
    if button._state_type ~= nil then
        -- LibActionButton (Bartender4, ElvUI, ...)
        if button._state_type == "action" then
            slot = button._state_action
        end
    else
        slot = button.action
        if type(slot) ~= "number" and button.CalculateAction then
            local ok, value = pcall(button.CalculateAction, button)
            slot = ok and value or nil
        end
        if type(slot) ~= "number" and button.GetAttribute then
            local ok, value = pcall(button.GetAttribute, button, "action")
            slot = ok and tonumber(value) or nil
        end
    end
    if Readable(slot) and type(slot) == "number" and slot > 0 then
        return slot
    end
    return nil
end

-- For an action slot holding one of our macros or a Blizzard equipment set: the set ID (nil for a set that doesn't
-- exist), the kind ("macro" or "blizzard"), and whether it is the "current set" macro.
local function SetForSlot(slot)
    local ok, has = pcall(HasAction, slot)
    if not ok or not Readable(has) or not has then
        return nil
    end
    local ok2, kind, id, subType = pcall(GetActionInfo, slot)
    if not ok2 or not Readable(kind) or not Readable(id) then
        return nil
    end
    if kind == "macro" then
        if subType == "spell" or subType == "item" then
            return nil -- a macro that shows a spell or item; ours never do
        end
        local _, _, body = GetMacroInfo(id)
        local arg = ns.ParseMacro(body)
        if not arg then
            return nil
        end
        local setID, isCurrent = ns.SetForMacroArg(arg)
        return setID, "macro", isCurrent
    elseif kind == "equipmentset" and ns.db.decorateBlizzard then
        local setID = type(id) == "number" and id or ns.SetByName(id)
        return setID, "blizzard", false
    end
    return nil
end
ns.SetForSlot = SetForSlot

---------------------------------------------------------------------------
-- Border and glow

local GLOW_TEXTURE = [[Interface\SpellActivationOverlay\IconAlert]]

local function CreateOverlay(button)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 8)
    overlay.edges = {}
    for index = 1, 4 do
        overlay.edges[index] = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    end

    local glow = overlay:CreateTexture(nil, "OVERLAY", nil, 6)
    glow:SetTexture(GLOW_TEXTURE)
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.3)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.75)
    alpha:SetSmoothing("IN_OUT")
    overlay.glow, overlay.pulse = glow, pulse

    overlays[button] = overlay
    return overlay
end

local function LayoutEdges(overlay, button, thickness)
    local top, bottom, left, right = unpack(overlay.edges)
    for _, edge in ipairs(overlay.edges) do
        edge:ClearAllPoints()
    end
    -- One unit outside the button, the rest inside, so neighbouring buttons don't cover it.
    top:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, -1)
    bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, -1)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(thickness)
end

local function ApplyState(button, state)
    local overlay = overlays[button]
    if not state then
        if overlay then
            overlay.pulse:Stop()
            overlay:Hide()
        end
        return
    end
    overlay = overlay or CreateOverlay(button)
    local r, g, b = ns.StateColor(state)
    LayoutEdges(overlay, button, ns.db.thickness or 3)
    for _, edge in ipairs(overlay.edges) do
        edge:SetColorTexture(r, g, b, 1)
    end
    if ns.db.glow and state ~= "worn" then
        local width, height = button:GetSize()
        overlay.glow:SetSize(width * 1.5, height * 1.5)
        overlay.glow:SetVertexColor(r, g, b)
        overlay.glow:Show()
        if not overlay.pulse:IsPlaying() then
            overlay.pulse:Play()
        end
    else
        overlay.pulse:Stop()
        overlay.glow:Hide()
    end
    overlay:Show()
end

-- Redraws everything on the next update, e.g. after the options changed.
function ns.RestyleButtons()
    wipe(shownState)
    ns.UpdateButtons()
end

function ns.UpdateButtons()
    if not ns.db then
        return
    end
    local bySlot = {}
    for button in pairs(buttons) do
        local state
        local slot = ButtonSlot(button)
        if slot then
            local setID = bySlot[slot]
            if setID == nil then
                setID = SetForSlot(slot) or false
                bySlot[slot] = setID
            end
            if setID then
                state = ns.StateOf(setID)
            end
        end
        if shownState[button] ~= (state or false) then
            shownState[button] = state or false
            ApplyState(button, state)
        end
    end
end

---------------------------------------------------------------------------
-- Tooltip

local function AddSetTooltip(tooltip, setID, kind, isCurrent)
    tooltip:AddLine(" ")
    local name = ns.SetInfo(setID)
    if not name then
        tooltip:AddLine(isCurrent and L.TT_NO_CURRENT or L.TT_NO_SET, 1, 0.3, 0.3, true)
        tooltip:Show()
        return
    end
    local state = ns.StateOf(setID)
    if state then
        local r, g, b = ns.StateColor(state)
        tooltip:AddLine(name .. ": " .. L["STATE_" .. state], r, g, b)
        for _, entry in ipairs(ns.currentDiff or {}) do
            tooltip:AddLine(ns.DiffLine(entry), 1, 1, 1)
        end
    else
        tooltip:AddLine(name .. ": " .. L.STATE_none, 0.6, 0.6, 0.6)
    end
    if kind == "macro" then
        local db = ns.db
        if not state then
            tooltip:AddLine(L.TT_CLICK_EQUIP, 0.5, 0.8, 1)
        elseif state ~= "worn" then
            tooltip:AddLine(db.confirm and L.TT_CLICK_CHANGED or L.TT_CLICK_SAVE, 0.5, 0.8, 1)
        end
        if db.shiftSaves then
            tooltip:AddLine(L.TT_SHIFT, 0.5, 0.8, 1)
        end
        if db.ctrlRestores and state ~= "worn" then
            tooltip:AddLine(L.TT_CTRL, 0.5, 0.8, 1)
        end
    end
    tooltip:Show()
end

function ns.InstallTooltipHook()
    if ns.tooltipHooked or not GameTooltip.SetAction then
        return
    end
    ns.tooltipHooked = true
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        if not ns.db or not Readable(slot) then
            return
        end
        local setID, kind, isCurrent = SetForSlot(slot)
        if kind then
            AddSetTooltip(tooltip, setID, kind, isCurrent)
        end
    end)
end

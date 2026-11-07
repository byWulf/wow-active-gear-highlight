local ADDON, ns = ...
local L = ns.L

local ES = C_EquipmentSet
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local RequestItem = C_Item and C_Item.RequestLoadItemDataByID

ns.PREFIX = "|cff33ff99Smart Gear Switcher|r: "

ns.DEFAULTS = {
    confirm = true,
    shiftSaves = true,
    ctrlRestores = true,
    replaceDrag = true,
    chat = true,
    glow = true,
    decorateBlizzard = true,
    thickness = 3,
    colorWorn = "ff33dd33",
    colorChanged = "ffff9900",
    colorMissing = "ffff3333",
}

-- Location values of C_EquipmentSet.GetItemLocations that are not real item locations.
local LOC_MISSING = EQUIPMENT_SET_ITEM_MISSING or -1
local LOC_EMPTY = EQUIPMENT_SET_EMPTY_SLOT or 0
local LOC_IGNORED = EQUIPMENT_SET_IGNORED_SLOT or 1

-- Compared slots: head (1) to tabard (19). The ammo slot is left out, its stack runs out while you play.
local FIRST_SLOT, LAST_SLOT = 1, 19

local SLOT_NAMES = {
    "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT",
    "WRISTSLOT", "HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "BACKSLOT",
    "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT", "TABARDSLOT",
}

---------------------------------------------------------------------------
-- Output

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. msg)
end

-- Optional feedback, can be turned off in the options. Errors use ns.Print.
function ns.Info(msg)
    if ns.db.chat then
        ns.Print(msg)
    end
end

function ns.HexToRGB(hex)
    hex = type(hex) == "string" and hex or "ffffffff"
    if #hex == 8 then
        hex = hex:sub(3)
    end
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return (r or 255) / 255, (g or 255) / 255, (b or 255) / 255
end

local STATE_COLOR_KEYS = { worn = "colorWorn", changed = "colorChanged", missing = "colorMissing" }

function ns.StateColor(state)
    return ns.HexToRGB(ns.db[STATE_COLOR_KEYS[state] or "colorWorn"])
end

---------------------------------------------------------------------------
-- Equipment sets

function ns.SetIDs()
    return ES.GetEquipmentSetIDs() or {}
end

function ns.SetExists(setID)
    if not setID then
        return false
    end
    for _, id in ipairs(ns.SetIDs()) do
        if id == setID then
            return true
        end
    end
    return false
end

-- Name and icon of a set; nil for a set that doesn't exist (any more).
function ns.SetInfo(setID)
    if not ns.SetExists(setID) then
        return nil
    end
    local name, icon = ES.GetEquipmentSetInfo(setID)
    return name, icon
end

function ns.SetByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local id = ES.GetEquipmentSetID(name)
    if id and ns.SetExists(id) then
        return id
    end
    return nil
end

function ns.SetLabel(setID)
    local name = ns.SetInfo(setID)
    return "|cffffd100" .. (name or "?") .. "|r"
end

-- The slots in which your equipped gear differs from the set, and the number of slots the set cares about.
-- Each entry: slot, want (the set's item ID or nil for an empty slot), have (equipped item ID or nil),
-- missing (the set's item is neither equipped nor in your bags).
function ns.Diff(setID)
    local diff, compared = {}, 0
    if not ns.SetExists(setID) then
        return diff, compared
    end
    local ids = ES.GetItemIDs(setID) or {}
    local locations = ES.GetItemLocations(setID) or {}
    local ignored = ES.GetIgnoredSlots(setID) or {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local location = locations[slot]
        if not ignored[slot] and location ~= LOC_IGNORED then
            compared = compared + 1
            local want = ids[slot]
            if want == 0 or location == LOC_EMPTY then
                want = nil
            end
            local have = GetInventoryItemID("player", slot)
            if want ~= have then
                diff[#diff + 1] = { slot = slot, want = want, have = have, missing = (location == LOC_MISSING) }
            end
        end
    end
    return diff, compared
end

local function MatchesExactly(setID)
    local diff, compared = ns.Diff(setID)
    return compared > 0 and #diff == 0
end

function ns.FindMatchingSet(prefer)
    if prefer and MatchesExactly(prefer) then
        return prefer
    end
    for _, id in ipairs(ns.SetIDs()) do
        if MatchesExactly(id) then
            return id
        end
    end
    return nil
end

-- The set you're wearing is the one you equipped last (however you equipped it). When your gear stops matching it
-- but matches another set exactly, that set takes over.
function ns.UpdateCurrent()
    -- Wait for a running swap (with a timeout, in case its end is never reported), and for the sets to be loaded.
    if (ns.swapping and GetTime() - ns.swapping < 5) or #ns.SetIDs() == 0 then
        return
    end
    local current = ns.char.current
    if current and not ns.SetExists(current) then
        current = nil
    end
    if not current or not MatchesExactly(current) then
        current = ns.FindMatchingSet() or current
    end
    ns.char.current = current
end

function ns.SetCurrent(setID)
    ns.char.current = setID
    ns.RequestRefresh()
end

-- "worn", "changed" or "missing" for the set you're wearing, nil for every other set.
function ns.StateOf(setID)
    if setID and setID == ns.char.current then
        return ns.currentState
    end
    return nil
end

---------------------------------------------------------------------------
-- Item and slot texts

function ns.SlotName(slot)
    local key = SLOT_NAMES[slot]
    return key and (_G[key .. "_UNIQUE"] or _G[key]) or tostring(slot)
end

local function ItemText(itemID, link)
    if not itemID then
        return "|cff808080" .. L.EMPTY_SLOT .. "|r"
    end
    if not link then
        local name, itemLink = GetItemInfo(itemID)
        link = itemLink or name
        if not link and RequestItem then
            RequestItem(itemID)
        end
    end
    local icon = GetItemIcon(itemID)
    return (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. (link or L.UNKNOWN_ITEM:format(itemID))
end

function ns.DiffLine(entry)
    local have = ItemText(entry.have, entry.have and GetInventoryItemLink("player", entry.slot))
    local want = ItemText(entry.want)
    if entry.missing then
        want = want .. " |cffff4040" .. L.MISSING_SUFFIX .. "|r"
    end
    return L.DIFF_LINE:format(ns.SlotName(entry.slot), have, want)
end

---------------------------------------------------------------------------
-- Actions

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

function ns.Equip(setID)
    if not ns.SetExists(setID) then
        return
    end
    if MatchesExactly(setID) then
        ns.SetCurrent(setID)
        ns.Info(L.MSG_ALREADY:format(ns.SetLabel(setID)))
        return
    end
    if InCombat() then
        ns.pendingEquip = setID
        ns.Print(L.MSG_QUEUED:format(ns.SetLabel(setID)))
        return
    end
    ns.pendingEquip = nil
    ns.SetCurrent(setID)
    ES.UseEquipmentSet(setID)
end

-- Saves your equipped gear to the set and keeps the slots the set ignores ignored.
function ns.Save(setID)
    if not ns.SetExists(setID) then
        return
    end
    local before = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        before[slot] = ES.IsSlotIgnoredForSave(slot)
    end
    local ignored = ES.GetIgnoredSlots(setID) or {}
    for slot = FIRST_SLOT, LAST_SLOT do
        if ignored[slot] then
            ES.IgnoreSlotForSave(slot)
        else
            ES.UnignoreSlotForSave(slot)
        end
    end
    ES.SaveEquipmentSet(setID)
    -- Give the flags back, the Equipment Manager shows them for the set selected there.
    for slot = FIRST_SLOT, LAST_SLOT do
        if before[slot] then
            ES.IgnoreSlotForSave(slot)
        else
            ES.UnignoreSlotForSave(slot)
        end
    end
    ns.SetCurrent(setID)
    ns.Info(L.MSG_SAVED:format(ns.SetLabel(setID)))
end

-- Save on request: asks first when it would overwrite a set you're not wearing.
function ns.RequestSave(setID)
    if not ns.SetExists(setID) then
        return
    end
    ns.UpdateCurrent()
    if #ns.Diff(setID) == 0 then
        ns.SetCurrent(setID)
        ns.Info(L.MSG_MATCHED:format(ns.SetLabel(setID)))
        return
    end
    if setID ~= ns.char.current and ns.db.confirm then
        ns.ShowDialog(setID, "overwrite")
        return
    end
    ns.Save(setID)
end

-- The click of a set macro: equip a set you're not wearing; for the set you're wearing, save or re-equip it when
-- you changed it.
function ns.Smart(setID)
    if not ns.SetExists(setID) then
        return
    end
    if ns.db.shiftSaves and IsShiftKeyDown() then
        ns.RequestSave(setID)
        return
    end
    if ns.db.ctrlRestores and IsControlKeyDown() then
        ns.Equip(setID)
        return
    end
    ns.UpdateCurrent()
    local diff = ns.Diff(setID)
    if setID ~= ns.char.current then
        if #diff == 0 then
            ns.SetCurrent(setID)
            ns.Info(L.MSG_MATCHED:format(ns.SetLabel(setID)))
        else
            ns.Equip(setID)
        end
        return
    end
    if #diff == 0 then
        ns.Info(L.MSG_ALREADY:format(ns.SetLabel(setID)))
    elseif ns.db.confirm then
        ns.ShowDialog(setID, "changed")
    else
        ns.Save(setID)
    end
end

---------------------------------------------------------------------------
-- Refresh

function ns.Refresh()
    ns.refreshPending = false
    if not ns.char then
        return
    end
    ns.UpdateCurrent()
    local current = ns.char.current
    local state, diff = nil, nil
    if current then
        diff = ns.Diff(current)
        state = "worn"
        for _, entry in ipairs(diff) do
            state = "changed"
            if entry.missing then
                state = "missing"
                break
            end
        end
    end
    ns.currentState, ns.currentDiff = state, diff
    if current ~= ns.lastCurrent then
        ns.lastCurrent = current
        ns.RequestMacroSync()
    end
    ns.UpdateButtons()
    ns.UpdateDialog()
end

function ns.RequestRefresh()
    if ns.refreshPending then
        return
    end
    ns.refreshPending = true
    C_Timer.After(0.1, ns.Refresh)
end

---------------------------------------------------------------------------
-- Slash command

local function OpenOptions()
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    else
        for _, line in ipairs(L.HELP) do
            ns.Print(line)
        end
    end
end

-- A set named in a command; "" or "current" stands for the set you're wearing.
local function ResolveSet(text)
    if text == "" or text:lower() == "current" then
        ns.UpdateCurrent()
        if not ns.char.current then
            ns.Print(L.MSG_NO_CURRENT)
        end
        return ns.char.current
    end
    local id = ns.SetByName(text)
    if not id then
        ns.Print(L.MSG_NO_SET:format(text))
    end
    return id
end

local COMMANDS = {
    save = ns.RequestSave,
    restore = ns.Equip,
    equip = ns.Equip,
}

function ns.HandleCommand(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    if msg == "" or lower == "options" or lower == "config" then
        OpenOptions()
        return
    end
    if lower == "help" then
        for _, line in ipairs(L.HELP) do
            ns.Print(line)
        end
        return
    end
    if not ES.CanUseEquipmentSets() then
        ns.Print(L.MSG_CANT_USE)
        return
    end
    -- A set name wins over the keywords, so a set may be called "Save" or "Current".
    local id = ns.SetByName(msg)
    if id then
        ns.Smart(id)
        return
    end
    local word, rest = msg:match("^(%S+)%s*(.-)$")
    word = word:lower()
    if word == "current" and rest == "" then
        id = ResolveSet("")
        if id then
            ns.Smart(id)
        end
    elseif word == "macro" then
        if rest == "" or rest:lower() == "current" then
            ns.PickupCurrentMacro()
        else
            id = ResolveSet(rest)
            if id then
                ns.PickupSetMacro(id)
            end
        end
    elseif COMMANDS[word] then
        id = ResolveSet(rest)
        if id then
            COMMANDS[word](id)
        end
    else
        ns.Print(L.MSG_NO_SET:format(msg))
    end
end

SLASH_SMARTGEARSWITCHER1 = "/sgs"
SLASH_SMARTGEARSWITCHER2 = "/smartgear"
SlashCmdList.SMARTGEARSWITCHER = function(msg)
    ns.HandleCommand(msg)
end

---------------------------------------------------------------------------
-- Events

local function InitDB()
    SmartGearSwitcherDB = SmartGearSwitcherDB or {}
    for key, value in pairs(ns.DEFAULTS) do
        if SmartGearSwitcherDB[key] == nil then
            SmartGearSwitcherDB[key] = value
        end
    end
    SmartGearSwitcherCharDB = SmartGearSwitcherCharDB or {}
    SmartGearSwitcherCharDB.names = SmartGearSwitcherCharDB.names or {}
    ns.db = SmartGearSwitcherDB
    ns.char = SmartGearSwitcherCharDB
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON then
        InitDB()
    else
        ns.InstallPaneHook()
        ns.RequestButtonScan()
    end
end

function handlers.PLAYER_LOGIN()
    ns.InitOptions()
    ns.InstallPaneHook()
    ns.InstallTooltipHook()
    ns.InstallLibActionButtonHooks()
end

function handlers.PLAYER_ENTERING_WORLD()
    -- The walk over all frames (for unknown bar addons) only once per session.
    ns.RequestButtonScan(not ns.didFullScan)
    ns.didFullScan = true
    ns.RequestRefresh()
    ns.RequestMacroSync()
end

function handlers.EQUIPMENT_SWAP_PENDING()
    ns.swapping = GetTime()
end

function handlers.EQUIPMENT_SWAP_FINISHED(_, setID)
    ns.swapping = nil
    if setID and ns.SetExists(setID) then
        ns.char.current = setID
    end
    ns.RequestRefresh()
end

function handlers.EQUIPMENT_SETS_CHANGED()
    ns.RequestMacroSync()
    ns.RequestRefresh()
end

function handlers.PLAYER_REGEN_ENABLED()
    if ns.pendingEquip then
        local setID = ns.pendingEquip
        ns.pendingEquip = nil
        C_Timer.After(0.2, function()
            ns.Equip(setID)
        end)
    end
    ns.SyncMacros()
end

function handlers.GET_ITEM_INFO_RECEIVED()
    ns.UpdateDialog()
end

handlers.PLAYER_EQUIPMENT_CHANGED = ns.RequestRefresh
handlers.BAG_UPDATE_DELAYED = ns.RequestRefresh

local function ButtonsChanged()
    ns.RequestButtonUpdate()
end
handlers.ACTIONBAR_SLOT_CHANGED = ButtonsChanged
handlers.ACTIONBAR_PAGE_CHANGED = ButtonsChanged
handlers.UPDATE_BONUS_ACTIONBAR = ButtonsChanged
handlers.UPDATE_SHAPESHIFT_FORM = ButtonsChanged
handlers.UPDATE_MACROS = ButtonsChanged

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
    -- Not every event exists in every client build.
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and not ns.db then
        return
    end
    handlers[event](...)
end)

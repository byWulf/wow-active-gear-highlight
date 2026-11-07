local _, ns = ...
local L = ns.L

local MAX_ACCOUNT = MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER = MAX_CHARACTER_MACROS or 30
local DEFAULT_ICON = 134400 -- INV_Misc_QuestionMark
local MAX_NAME_LETTERS = 16

local SLASH_NAMES = { sgs = true, smartgear = true }

ns.CURRENT_BODY = "/sgs current"

function ns.SetMacroBody(setName)
    return "/sgs " .. setName
end

-- The argument of the first /sgs line of a macro, or nil for a macro that isn't ours.
function ns.ParseMacro(body)
    if type(body) ~= "string" then
        return nil
    end
    for line in body:gmatch("[^\r\n]+") do
        local command, arg = line:match("^%s*/(%S+)%s*(.-)%s*$")
        if command and SLASH_NAMES[command:lower()] then
            return arg
        end
    end
    return nil
end

-- The set a macro argument stands for, and whether it is the "current set" macro.
-- Mirrors ns.HandleCommand: a set name wins over the keywords.
function ns.SetForMacroArg(arg)
    local id = ns.SetByName(arg)
    if id then
        return id, false
    end
    local word, rest = arg:match("^(%S+)%s*(.-)$")
    if not word then
        return nil, false
    end
    word = word:lower()
    if word == "current" and rest == "" then
        return ns.char.current, true
    end
    if word == "save" or word == "restore" or word == "equip" then
        if rest == "" or rest:lower() == "current" then
            return ns.char.current, true
        end
        return ns.SetByName(rest), false
    end
    return nil, false
end

-- At most 16 letters, cut between UTF-8 characters.
local function MacroName(name)
    local out, count = {}, 0
    for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > MAX_NAME_LETTERS then
            break
        end
        out[count] = char
    end
    return table.concat(out)
end

local function ForEachMacro(callback)
    local numAccount, numCharacter = GetNumMacros()
    for index = 1, numAccount do
        if callback(index) then
            return
        end
    end
    for index = MAX_ACCOUNT + 1, MAX_ACCOUNT + numCharacter do
        if callback(index) then
            return
        end
    end
end

local function FindMacro(body)
    local found
    ForEachMacro(function(index)
        local _, _, macroBody = GetMacroInfo(index)
        if macroBody and strtrim(macroBody) == body then
            found = index
            return true
        end
    end)
    return found
end

-- Index of the macro with this body; creates it (as a character macro while there is room) when there is none.
local function EnsureMacro(body, name, icon)
    local index = FindMacro(body)
    if index then
        return index
    end
    if InCombatLockdown() then
        ns.Print(L.MSG_MACRO_COMBAT)
        return nil
    end
    local numAccount, numCharacter = GetNumMacros()
    local perCharacter = numCharacter < MAX_CHARACTER
    if not perCharacter and numAccount >= MAX_ACCOUNT then
        ns.Print(L.MSG_MACRO_FULL)
        return nil
    end
    local ok = pcall(CreateMacro, MacroName(name), icon or DEFAULT_ICON, body, perCharacter)
    index = ok and FindMacro(body)
    if not index then
        ns.Print(L.MSG_MACRO_FAILED)
    end
    return index
end

function ns.PickupSetMacro(setID)
    local name, icon = ns.SetInfo(setID)
    if not name then
        return false
    end
    local index = EnsureMacro(ns.SetMacroBody(name), name, icon)
    if not index then
        return false
    end
    PickupMacro(index)
    return true
end

function ns.PickupCurrentMacro()
    local name, icon = ns.SetInfo(ns.char.current)
    local index = EnsureMacro(ns.CURRENT_BODY, name or L.CURRENT_MACRO, icon)
    if index then
        PickupMacro(index)
    end
end

---------------------------------------------------------------------------
-- Keeping the macros up to date: set icons, renamed sets, and the "current set" macro's name and icon.

function ns.RequestMacroSync()
    ns.macroSyncPending = true
    if not InCombatLockdown() then
        C_Timer.After(0.2, ns.SyncMacros)
    end
end

local function RenameSetMacros()
    if #ns.SetIDs() == 0 then
        return -- not loaded yet, or no sets: keep the known names
    end
    local names, seen, renames = ns.char.names, {}, {}
    for _, id in ipairs(ns.SetIDs()) do
        local name = ns.SetInfo(id)
        if name then
            local old = names[id]
            if old and old ~= name then
                renames[#renames + 1] = { old = old, new = name }
            end
            names[id] = name
            seen[id] = true
        end
    end
    for id in pairs(names) do
        if not seen[id] then
            names[id] = nil
        end
    end
    for _, rename in ipairs(renames) do
        local oldBody = ns.SetMacroBody(rename.old)
        local index, tries = FindMacro(oldBody), 0
        while index and tries < 20 do
            local macroName, icon = GetMacroInfo(index)
            if macroName == MacroName(rename.old) then
                macroName = MacroName(rename.new)
            end
            EditMacro(index, macroName, icon, ns.SetMacroBody(rename.new))
            index, tries = FindMacro(oldBody), tries + 1
        end
    end
end

function ns.SyncMacros()
    if not ns.macroSyncPending or InCombatLockdown() or not ns.char then
        return
    end
    ns.macroSyncPending = false
    RenameSetMacros()

    local currentName, currentIcon = ns.SetInfo(ns.char.current)
    local renameCurrent = {}
    ForEachMacro(function(index)
        local macroName, icon, body = GetMacroInfo(index)
        body = body and strtrim(body)
        if body == ns.CURRENT_BODY then
            local wantName = MacroName(currentName or L.CURRENT_MACRO)
            local wantIcon = currentIcon or DEFAULT_ICON
            if macroName ~= wantName then
                -- A new name can move the macro in the list, so rename after the loop.
                renameCurrent[#renameCurrent + 1] = { name = wantName, icon = wantIcon }
            elseif icon ~= wantIcon then
                EditMacro(index, macroName, wantIcon, body)
            end
        elseif body then
            local setName = body:match("^/[Ss][Gg][Ss] (.+)$")
            local _, setIcon = ns.SetInfo(ns.SetByName(setName))
            if setIcon and icon ~= setIcon then
                EditMacro(index, macroName, setIcon, body)
            end
        end
    end)
    for _, want in ipairs(renameCurrent) do
        local index = FindMacro(ns.CURRENT_BODY)
        if index then
            EditMacro(index, want.name, want.icon, ns.CURRENT_BODY)
        end
    end
end

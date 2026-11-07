local _, ns = ...
local L = ns.L

-- The window that lists how your gear differs from a set and lets you save it or re-equip the set.
-- mode "changed": you're wearing the set and changed it (Save changes / Re-equip set / Cancel).
-- mode "overwrite": saving would overwrite a set you're not wearing (Save / Cancel).

local WIDTH = 480
local dialog

local function CreateButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Create()
    local frame = CreateFrame("Frame", "SmartGearSwitcherDialog", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -22)
    frame.title:SetWidth(WIDTH - 40)

    frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame.title, "BOTTOM", 0, -10)
    frame.text:SetWidth(WIDTH - 40)

    frame.list = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.list:SetPoint("TOP", frame.text, "BOTTOM", 0, -10)
    frame.list:SetWidth(WIDTH - 50)
    frame.list:SetJustifyH("LEFT")
    frame.list:SetSpacing(5)

    frame.save = CreateButton(frame, L.BUTTON_SAVE, function()
        local setID = frame.setID
        frame:Hide()
        ns.Save(setID)
    end)
    frame.restore = CreateButton(frame, L.BUTTON_RESTORE, function()
        local setID = frame.setID
        frame:Hide()
        ns.Equip(setID)
    end)
    frame.cancel = CreateButton(frame, CANCEL, function()
        frame:Hide()
    end)

    frame:SetScript("OnHide", function()
        frame.setID = nil
    end)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())
    return frame
end

local function Layout(frame)
    local isChanged = frame.mode == "changed"
    local label = ns.SetLabel(frame.setID)
    frame.title:SetText((isChanged and L.DIALOG_CHANGED_TITLE or L.DIALOG_OVERWRITE_TITLE):format(label))
    frame.text:SetText(isChanged and L.DIALOG_CHANGED_TEXT or L.DIALOG_OVERWRITE_TEXT)

    local lines = {}
    for _, entry in ipairs(ns.Diff(frame.setID)) do
        lines[#lines + 1] = ns.DiffLine(entry)
    end
    frame.list:SetText(table.concat(lines, "\n"))

    frame.save:SetText(isChanged and L.BUTTON_SAVE_CHANGES or L.BUTTON_SAVE)
    -- Fit the buttons to their (translated) text.
    for _, button in ipairs({ frame.save, frame.restore, frame.cancel }) do
        button:SetWidth(math.max(110, math.min(150, button:GetFontString():GetStringWidth() + 30)))
    end
    frame.save:ClearAllPoints()
    frame.restore:ClearAllPoints()
    frame.cancel:ClearAllPoints()
    if isChanged then
        frame.restore:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
        frame.save:SetPoint("RIGHT", frame.restore, "LEFT", -6, 0)
        frame.cancel:SetPoint("LEFT", frame.restore, "RIGHT", 6, 0)
        frame.restore:Show()
    else
        frame.save:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -3, 20)
        frame.cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 3, 20)
        frame.restore:Hide()
    end

    local height = 22 + frame.title:GetStringHeight() + 10 + frame.text:GetStringHeight() + 10
        + frame.list:GetStringHeight() + 18 + 22 + 20
    frame:SetHeight(height)
    return #lines
end

function ns.ShowDialog(setID, mode)
    dialog = dialog or Create()
    dialog.setID = setID
    dialog.mode = mode
    if Layout(dialog) == 0 then
        dialog:Hide()
        return
    end
    dialog:Show()
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
end

-- Keeps an open window in step with your gear; closes it when there is nothing left to save.
function ns.UpdateDialog()
    if not dialog or not dialog:IsShown() or not dialog.setID then
        return
    end
    local wornChanged = dialog.mode == "changed" and dialog.setID ~= ns.char.current
    if wornChanged or not ns.SetExists(dialog.setID) or Layout(dialog) == 0 then
        dialog:Hide()
    end
end

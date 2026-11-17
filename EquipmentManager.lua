local _, ns = ...
local L = ns.L

-- Blizzard's Equipment Manager (character window):
-- - Dragging a set gives our macro for that set instead of Blizzard's equipment set button. Shift-drag keeps
--   Blizzard's behavior.
-- - The gear (edit) button's menu gets the choice of a talent spec to switch to before the set is equipped, and a set
--   linked to a spec shows the spec's number in the ring on its icon.

local function OnDragStart(button, ...)
    if ns.db.replaceDrag and button.setID and not IsShiftKeyDown() then
        if ns.PickupSetMacro(button.setID) then
            return
        end
    end
    if button.aghOriginalDragStart then
        button.aghOriginalDragStart(button, ...)
    end
end

local function OnEnter(button)
    if not button.setID or not GameTooltip:IsOwned(button) then
        return
    end
    local group = ns.HasDualSpec() and ns.SetSpec(button.setID)
    if group or ns.db.replaceDrag then
        GameTooltip:AddLine(" ")
    end
    if group then
        GameTooltip:AddLine(L.TT_SPEC:format(ns.SpecName(group)), 0.5, 0.8, 1)
    end
    if ns.db.replaceDrag then
        GameTooltip:AddLine(L.TT_PANE_DRAG, 0.5, 0.8, 1)
        GameTooltip:AddLine(L.TT_PANE_SHIFT_DRAG, 0.5, 0.8, 1)
    end
    GameTooltip:Show()
end

-- The ring at the set icon (Blizzard's spec marker, unused in Forever) with the number of the linked spec group.
local function UpdateSpecBadge(button)
    if not button.SpecRing or not button.SpecIcon then
        return
    end
    local group = button.setID and ns.char and ns.HasDualSpec() and ns.SetSpec(button.setID)
    if not group then
        if button.aghSpecText then
            button.aghSpecText:Hide()
            -- Leave the ring to Blizzard's own spec assignment, if a set has one.
            if not button.specID then
                button.SpecIcon:Hide()
                button.SpecRing:Hide()
            end
        end
        return
    end
    if not button.aghSpecText then
        button.aghSpecText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.aghSpecText:SetDrawLayer("OVERLAY", 7)
        button.aghSpecText:SetPoint("CENTER", button.SpecIcon, "CENTER", 1, 0)
    end
    button.SpecIcon:SetColorTexture(0, 0, 0, 0.85)
    button.SpecIcon:Show()
    button.SpecRing:Show()
    button.aghSpecText:SetText(group)
    button.aghSpecText:Show()
end

local function ForEachSetButton(callback)
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    local scrollBox = pane and pane.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(callback)
    end
end

function ns.UpdatePaneSpecBadges()
    ForEachSetButton(UpdateSpecBadge)
end

local function InitButton(button)
    if not button.aghHooked then
        button.aghHooked = true
        button.aghOriginalDragStart = button:GetScript("OnDragStart")
        button:SetScript("OnDragStart", OnDragStart)
        button:HookScript("OnEnter", OnEnter)
    end
    UpdateSpecBadge(button)
end

-- The set whose gear button was clicked: the menu is built while the mouse is still on that button.
local function SetOfEditButtonUnderMouse()
    local found
    ForEachSetButton(function(button)
        if not found and button.setID and button.EditButton and button.EditButton:IsMouseOver() then
            found = button.setID
        end
    end)
    return found
end

local function AddSpecMenu(_, rootDescription)
    if not ns.char or not ns.HasDualSpec() then
        return
    end
    local setID = SetOfEditButtonUnderMouse()
    if not setID then
        return
    end
    local function IsSelected(group)
        return (ns.SetSpec(setID) or 0) == group
    end
    local function SetSelected(group)
        ns.SetSpecLink(setID, group)
    end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle(L.SPEC_MENU_TITLE)
    rootDescription:CreateRadio(L.SPEC_NONE, IsSelected, SetSelected, 0)
    for group = 1, 2 do
        rootDescription:CreateRadio(ns.SpecName(group), IsSelected, SetSelected, group)
    end
end

function ns.InstallPaneHook()
    if not ns.menuHooked and Menu and Menu.ModifyMenu then
        ns.menuHooked = true
        Menu.ModifyMenu("MENU_PAPERDOLL_FRAME", AddSpecMenu)
    end
    if ns.paneHooked or type(PaperDollEquipmentManagerPane_InitButton) ~= "function" then
        return
    end
    ns.paneHooked = true
    hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", InitButton)
    ForEachSetButton(InitButton)
end

local _, ns = ...
local L = ns.L

-- Dragging a set out of Blizzard's Equipment Manager (character window) gives our macro for that set instead of
-- Blizzard's equipment set button. Shift-drag keeps Blizzard's behavior.

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
    if ns.db.replaceDrag and button.setID and GameTooltip:IsOwned(button) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.TT_PANE_DRAG, 0.5, 0.8, 1)
        GameTooltip:AddLine(L.TT_PANE_SHIFT_DRAG, 0.5, 0.8, 1)
        GameTooltip:Show()
    end
end

local function HookSetButton(button)
    if button.aghHooked then
        return
    end
    button.aghHooked = true
    button.aghOriginalDragStart = button:GetScript("OnDragStart")
    button:SetScript("OnDragStart", OnDragStart)
    button:HookScript("OnEnter", OnEnter)
end

function ns.InstallPaneHook()
    if ns.paneHooked or type(PaperDollEquipmentManagerPane_InitButton) ~= "function" then
        return
    end
    ns.paneHooked = true
    hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", HookSetButton)
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    local scrollBox = pane and pane.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(HookSetButton)
    end
end

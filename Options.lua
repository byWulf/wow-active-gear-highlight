local _, ns = ...
local L = ns.L

-- Options page in Blizzard's settings (Options > AddOns > Active Gear Highlight).

local function OnChanged()
    ns.RestyleButtons()
end

function ns.InitOptions()
    if ns.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
    layout = layout or SettingsPanel:GetLayout(category)

    local function Header(text)
        if CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Register(key, varType, label)
        local setting = Settings.RegisterAddOnSetting(category, "ActiveGearHighlight_" .. key, key, ns.db, varType,
            label, ns.DEFAULTS[key])
        setting:SetValueChangedCallback(OnChanged)
        return setting
    end

    local function Checkbox(key, label, tooltip)
        Settings.CreateCheckbox(category, Register(key, Settings.VarType.Bool, label), tooltip)
    end

    local function Color(key, label, tooltip)
        Settings.CreateColorSwatch(category, Register(key, Settings.VarType.String, label), tooltip)
    end

    Header(L.OPT_HEADER_BEHAVIOR)
    Checkbox("confirm", L.OPT_CONFIRM, L.OPT_CONFIRM_TIP)
    Checkbox("shiftSaves", L.OPT_SHIFT, L.OPT_SHIFT_TIP)
    Checkbox("ctrlRestores", L.OPT_CTRL, L.OPT_CTRL_TIP)
    Checkbox("replaceDrag", L.OPT_DRAG, L.OPT_DRAG_TIP)
    Checkbox("chat", L.OPT_CHAT, L.OPT_CHAT_TIP)
    if CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer(L.OPT_CURRENT_MACRO, L.OPT_CURRENT_MACRO_BUTTON,
            function()
                ns.PickupCurrentMacro()
            end, L.OPT_CURRENT_MACRO_TIP, true))
    end

    Header(L.OPT_HEADER_LOOK)
    Checkbox("glow", L.OPT_GLOW, L.OPT_GLOW_TIP)
    Checkbox("decorateBlizzard", L.OPT_BLIZZARD, L.OPT_BLIZZARD_TIP)
    local sliderOptions = Settings.CreateSliderOptions(1, 8, 1)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    Settings.CreateSlider(category, Register("thickness", Settings.VarType.Number, L.OPT_THICKNESS), sliderOptions,
        L.OPT_THICKNESS_TIP)
    Color("colorWorn", L.OPT_COLOR_WORN, L.OPT_COLOR_WORN_TIP)
    Color("colorChanged", L.OPT_COLOR_CHANGED, L.OPT_COLOR_CHANGED_TIP)
    Color("colorMissing", L.OPT_COLOR_MISSING, L.OPT_COLOR_MISSING_TIP)

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

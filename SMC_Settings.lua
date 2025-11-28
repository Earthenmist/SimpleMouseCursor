--[[
Simple Mouse Cursor - settings & configuration

This module owns:
- The SMC.defaults table (all SavedVariables default values).
- User-facing option lists (ring modes, modifier actions, reticle shapes).
- Creation of the settings panel shown in the WoW Interface options.
- The ApplySettings() bridge that pushes SavedVariables into the runtime.

The runtime behaviour itself lives in SimpleMouseCursor.lua.
]]--

SMC_Settings = SMC_Settings or {}

SimpleMouseCursor = SimpleMouseCursor or {}
local SMC = SimpleMouseCursor


SMC.defaults = {
    scale = 1.0,
    innerRing = "GCD",
    mainRing = "Main Ring",
    outerRing = "Cast",
    usePowerColors = false,
    useMainRingClassColor = false,
    useGCDClassColor = false,
    useCastClassColor = false,
    enableTrail = false,
    trailUseClassColor = false,
    trailDuration = 0.5,
    trailDensity = 0.005,
    trailScale = 1.0,
    trailMinMovement = 0.5,
    frameStrata = "BACKGROUND",
    showOnlyInCombat = false,
    shiftAction = "None",
    ctrlAction = "None",
    altAction = "None",
    reticle = "Dot",
    reticleScale = 1.5,
    useReticleClassColor = false,
    transparency = 1.0,
}

SMC.ringOptions = {
    "None",
    "Main Ring",
    "Main Ring + GCD",
    "Main Ring + Cast",
    "Cast",
    "GCD",
    "Health and Power",
    "Health",
    "Power",
}

SMC.modifierOptions = {
    "None",
    "Show Rings",
    "Ping with ring",
    "Ping with area",
    "Ping with crosshair",
    "Show Crosshair",
}

SMC.reticleOptions = {
    "Dot",
    "Chevron",
    "Crosshair",
    "Diamond",
    "Flatline",
    "Star",
    "Ring",
    "Tech Arrow",
    "X",
    "No Reticle",
}

SMC.frameStrataOptions = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

SMC.reticleTextures = {
    ["Dot"] = { path = "Interface\\Addons\\SimpleMouseCursor\\Image\\Dot.tga", scale = 0.5 },
    ["Chevron"] = { path = "uitools-icon-chevron-down", scale = 1.0, isAtlas = true },
    ["Crosshair"] = { path = "uitools-icon-plus", scale = 1.0, isAtlas = true },
    ["Diamond"] = { path = "UF-SoulShard-FX-FrameGlow", scale = 1.0, isAtlas = true },
    ["Flatline"] = { path = "uitools-icon-minus", scale = 1.0, isAtlas = true },
    ["Star"] = { path = "AftLevelup-WhiteStarBurst", scale = 2.0, isAtlas = true },
    ["Ring"] = { path = "Interface\\Addons\\SimpleMouseCursor\\Image\\Circle.tga", scale = 1.0 },
    ["Tech Arrow"] = { path = "ProgLan-w-4", scale = 1.0, isAtlas = true }, -- Assuming Atlas for now
    ["X"] = { path = "uitools-icon-close", scale = 1.0, isAtlas = true },
    ["No Reticle"] = { path = nil, scale = 1.0 },
}

-- Ensure SMC_Settings exists and is fully populated with defaults.
function SMC:InitializeSettings()
    if not SMC_Settings then
        SMC_Settings = {}
    end
    
    for key, value in pairs(SMC.defaults) do
        if SMC_Settings[key] == nil then
            SMC_Settings[key] = value
        end
    end
end

-- Simple helper to expose the live settings table to other modules.
function SMC:GetConfig()
    return SMC_Settings
end

-- Build the scrollable Interface Options panel and wire all widgets.
function SMC:CreateSettingsPanel()
    local panel = CreateFrame("Frame", "SMC_SettingsPanel")
    panel.name = "Simple Mouse Cursor"
    
    function panel.OnCommit() end
    function panel.OnDefault() end
    function panel.OnRefresh() end
    
    local scrollFrame = CreateFrame("ScrollFrame", "SMC_SettingsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 3, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, 800)
    scrollFrame:SetScrollChild(content)
    
    local function CreateSeparator(parent, text, anchor, relativeFrame, xOffset, yOffset)
        local separator = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        separator:SetPoint(anchor, relativeFrame, "BOTTOMLEFT", xOffset, yOffset)
        separator:SetText(text)
        separator:SetTextColor(1.0, 0.82, 0, 1)
        
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        line:SetHeight(1)
        line:SetPoint("LEFT", separator, "RIGHT", 5, 0)
        line:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        
        return separator
    end
    
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Simple Mouse Cursor Settings")
    
    local function CreateDropdown(name, label, yOffset, defaultValue)
        local dropdown = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
        -- We will set the point later based on the section
        
        local labelText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 0)
        labelText:SetText(label)
        
        UIDropDownMenu_SetWidth(dropdown, 120)
        UIDropDownMenu_SetText(dropdown, defaultValue)
        
        return dropdown
    end

    local function OnDropdownClick(self, dropdown, configKey)
        SMC_Settings[configKey] = self.value
        UIDropDownMenu_SetText(dropdown, self.value)
        SMC:ApplySettings()
        CloseDropDownMenus()
    end

    -- 1. Ring Slot Assignment
    local ringSeparator = CreateSeparator(content, "Ring Slot Assignment", "TOPLEFT", title, 0, -20)
    
    -- Reticle Dropdown
    local reticleDropdown = CreateDropdown("SMC_ReticleDropdown", "Change Reticle", 0, SMC_Settings.reticle)
    reticleDropdown:SetPoint("TOPLEFT", ringSeparator, "BOTTOMLEFT", 0, -20)
    
    UIDropDownMenu_Initialize(reticleDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(SMC.reticleOptions) do
            info.text = option
            info.checked = (SMC_Settings.reticle == option)
            info.func = function()
                SMC_Settings.reticle = option
                UIDropDownMenu_SetText(reticleDropdown, option)
                if SMC.ApplySettings then SMC:ApplySettings() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(reticleDropdown, SMC_Settings.reticle)
    
    -- Reticle Scale Slider
    local reticleScaleSlider = CreateFrame("Slider", "SMC_ReticleScaleSlider", content, "OptionsSliderTemplate")
    reticleScaleSlider:SetPoint("LEFT", reticleDropdown, "RIGHT", 140, 2)
    reticleScaleSlider:SetMinMaxValues(0.5, 2.0)
    reticleScaleSlider:SetValue(SMC_Settings.reticleScale or 1.0)
    reticleScaleSlider:SetValueStep(0.1)
    reticleScaleSlider:SetObeyStepOnDrag(true)
    reticleScaleSlider:SetWidth(120)
    _G[reticleScaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[reticleScaleSlider:GetName() .. "High"]:SetText("2.0")
    _G[reticleScaleSlider:GetName() .. "Text"]:SetText("Size")
    
    local reticleScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    reticleScaleValue:SetPoint("TOP", reticleScaleSlider, "BOTTOM", 0, -5)
    reticleScaleValue:SetText(string.format("%.1f", SMC_Settings.reticleScale or 1.0))
    
    reticleScaleSlider:SetScript("OnValueChanged", function(self, value)
        SMC_Settings.reticleScale = value
        reticleScaleValue:SetText(string.format("%.1f", value))
        SMC:ApplySettings()
    end)

    -- Inner Ring
    local innerDropdown = CreateDropdown("SMC_InnerRingDropdown", "Inner Ring:", 0, SMC_Settings.innerRing)
    innerDropdown:SetPoint("TOPLEFT", ringSeparator, "BOTTOMLEFT", 0, -65)
    
    UIDropDownMenu_Initialize(innerDropdown, function(self, level)
        for _, option in ipairs(SMC.ringOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, innerDropdown, "innerRing") end
            info.checked = (SMC_Settings.innerRing == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Main Ring
    local mainDropdown = CreateDropdown("SMC_MainRingDropdown", "Main Ring:", 0, SMC_Settings.mainRing)
    mainDropdown:SetPoint("TOPLEFT", ringSeparator, "BOTTOMLEFT", 0, -110)
    
    UIDropDownMenu_Initialize(mainDropdown, function(self, level)
        for _, option in ipairs(SMC.ringOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, mainDropdown, "mainRing") end
            info.checked = (SMC_Settings.mainRing == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Outer Ring
    local outerDropdown = CreateDropdown("SMC_OuterRingDropdown", "Outer Ring:", 0, SMC_Settings.outerRing)
    outerDropdown:SetPoint("TOPLEFT", ringSeparator, "BOTTOMLEFT", 0, -155)
    
    UIDropDownMenu_Initialize(outerDropdown, function(self, level)
        for _, option in ipairs(SMC.ringOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, outerDropdown, "outerRing") end
            info.checked = (SMC_Settings.outerRing == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- 2. Colors
    local colorSeparator = CreateSeparator(content, "Colors", "TOPLEFT", outerDropdown, 0, -40)
    
    local reticleClassCheckbox = CreateFrame("CheckButton", "SMC_ReticleClassCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    reticleClassCheckbox:SetPoint("TOPLEFT", colorSeparator, "BOTTOMLEFT", 0, -15)
    _G[reticleClassCheckbox:GetName() .. "Text"]:SetText("Use Class Color for Reticle")
    reticleClassCheckbox:SetChecked(SMC_Settings.useReticleClassColor)
    reticleClassCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.useReticleClassColor = self:GetChecked()
        SMC:ApplySettings()
    end)
    
    local mainRingClassCheckbox = CreateFrame("CheckButton", "SMC_MainRingClassCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    mainRingClassCheckbox:SetPoint("TOPLEFT", reticleClassCheckbox, "BOTTOMLEFT", 0, -5)
    _G[mainRingClassCheckbox:GetName() .. "Text"]:SetText("Use Class Color for Main Ring")
    mainRingClassCheckbox:SetChecked(SMC_Settings.useMainRingClassColor)
    mainRingClassCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.useMainRingClassColor = self:GetChecked()
        SMC:ApplySettings()
    end)
    
    local castClassCheckbox = CreateFrame("CheckButton", "SMC_CastClassCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    castClassCheckbox:SetPoint("TOPLEFT", mainRingClassCheckbox, "BOTTOMLEFT", 0, -5)
    _G[castClassCheckbox:GetName() .. "Text"]:SetText("Use Class Color for Cast")
    castClassCheckbox:SetChecked(SMC_Settings.useCastClassColor)
    castClassCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.useCastClassColor = self:GetChecked()
        SMC:ApplySettings()
    end)
    
    local gcdClassCheckbox = CreateFrame("CheckButton", "SMC_GCDClassCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    gcdClassCheckbox:SetPoint("TOPLEFT", castClassCheckbox, "BOTTOMLEFT", 0, -5)
    _G[gcdClassCheckbox:GetName() .. "Text"]:SetText("Use Class Color for GCD")
    gcdClassCheckbox:SetChecked(SMC_Settings.useGCDClassColor)
    gcdClassCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.useGCDClassColor = self:GetChecked()
        SMC:ApplySettings()
    end)
    
    local powerColorCheckbox = CreateFrame("CheckButton", "SMC_PowerColorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    powerColorCheckbox:SetPoint("TOPLEFT", gcdClassCheckbox, "BOTTOMLEFT", 0, -5)
    _G[powerColorCheckbox:GetName() .. "Text"]:SetText("Use Power Type Color for Power Ring")
    powerColorCheckbox:SetChecked(SMC_Settings.usePowerColors)
    powerColorCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.usePowerColors = self:GetChecked()
        SMC:ApplySettings()
    end)
    
    -- 3. Mouse Trail
    local trailSeparator = CreateSeparator(content, "Mouse Trail", "TOPLEFT", powerColorCheckbox, 0, -25)
    
    local enableTrailCheckbox = CreateFrame("CheckButton", "SMC_EnableTrailCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    enableTrailCheckbox:SetPoint("TOPLEFT", trailSeparator, "BOTTOMLEFT", 0, -15)
    _G[enableTrailCheckbox:GetName() .. "Text"]:SetText("Enable Mouse Trail")
    enableTrailCheckbox:SetChecked(SMC_Settings.enableTrail)
    enableTrailCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.enableTrail = self:GetChecked()
    end)
    
    local trailClassColorCheckbox = CreateFrame("CheckButton", "SMC_TrailClassColorCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    trailClassColorCheckbox:SetPoint("TOPLEFT", enableTrailCheckbox, "BOTTOMLEFT", 0, -5)
    _G[trailClassColorCheckbox:GetName() .. "Text"]:SetText("Use Class Color for Trail")
    trailClassColorCheckbox:SetChecked(SMC_Settings.trailUseClassColor)
    trailClassColorCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.trailUseClassColor = self:GetChecked()
    end)
    
    local trailDurationLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trailDurationLabel:SetPoint("TOPLEFT", trailClassColorCheckbox, "BOTTOMLEFT", 0, -15)
    trailDurationLabel:SetText("Trail Duration:")
    
    local trailDurationSlider = CreateFrame("Slider", "SMC_TrailDurationSlider", content, "OptionsSliderTemplate")
    trailDurationSlider:SetPoint("LEFT", trailDurationLabel, "RIGHT", 10, 0)
    trailDurationSlider:SetMinMaxValues(0.2, 1.0)
    trailDurationSlider:SetValue(SMC_Settings.trailDuration or 0.4)
    trailDurationSlider:SetValueStep(0.05)
    trailDurationSlider:SetObeyStepOnDrag(true)
    trailDurationSlider:SetWidth(150)
    _G[trailDurationSlider:GetName() .. "Low"]:SetText("0.2s")
    _G[trailDurationSlider:GetName() .. "High"]:SetText("1.0s")
    
    local trailDurationValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    trailDurationValue:SetPoint("LEFT", trailDurationSlider, "RIGHT", 5, 0)
    trailDurationValue:SetText(string.format("%.2fs", SMC_Settings.trailDuration or 0.4))
    
    trailDurationSlider:SetScript("OnValueChanged", function(self, value)
        SMC_Settings.trailDuration = value
        trailDurationValue:SetText(string.format("%.2fs", value))
    end)
    
    local trailDensityLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trailDensityLabel:SetPoint("TOPLEFT", trailDurationLabel, "BOTTOMLEFT", 0, -30)
    trailDensityLabel:SetText("Trail Density:")
    
    local trailDensitySlider = CreateFrame("Slider", "SMC_TrailDensitySlider", content, "OptionsSliderTemplate")
    trailDensitySlider:SetPoint("LEFT", trailDensityLabel, "RIGHT", 10, 0)
    trailDensitySlider:SetMinMaxValues(0.004, 0.02)
    trailDensitySlider:SetValue(SMC_Settings.trailDensity or 0.008)
    trailDensitySlider:SetValueStep(0.001)
    trailDensitySlider:SetObeyStepOnDrag(true)
    trailDensitySlider:SetWidth(150)
    _G[trailDensitySlider:GetName() .. "Low"]:SetText("Dense")
    _G[trailDensitySlider:GetName() .. "High"]:SetText("Sparse")
    
    local trailDensityValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    trailDensityValue:SetPoint("LEFT", trailDensitySlider, "RIGHT", 5, 0)
    trailDensityValue:SetText(string.format("%.3fs", SMC_Settings.trailDensity or 0.008))
    
    trailDensitySlider:SetScript("OnValueChanged", function(self, value)
        SMC_Settings.trailDensity = value
        trailDensityValue:SetText(string.format("%.3fs", value))
    end)
    
    local trailScaleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trailScaleLabel:SetPoint("TOPLEFT", trailDensityLabel, "BOTTOMLEFT", 0, -30)
    trailScaleLabel:SetText("Trail Scale:")
    
    local trailScaleSlider = CreateFrame("Slider", "SMC_TrailScaleSlider", content, "OptionsSliderTemplate")
    trailScaleSlider:SetPoint("LEFT", trailScaleLabel, "RIGHT", 10, 0)
    trailScaleSlider:SetMinMaxValues(0.5, 2.0)
    trailScaleSlider:SetValue(SMC_Settings.trailScale or 1.0)
    trailScaleSlider:SetValueStep(0.1)
    trailScaleSlider:SetObeyStepOnDrag(true)
    trailScaleSlider:SetWidth(150)
    _G[trailScaleSlider:GetName() .. "Low"]:SetText("0.5x")
    _G[trailScaleSlider:GetName() .. "High"]:SetText("2.0x")
    
    local trailScaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    trailScaleValue:SetPoint("LEFT", trailScaleSlider, "RIGHT", 5, 0)
    trailScaleValue:SetText(string.format("%.1fx", SMC_Settings.trailScale or 1.0))
    
    trailScaleSlider:SetScript("OnValueChanged", function(self, value)
        SMC_Settings.trailScale = value
        trailScaleValue:SetText(string.format("%.1fx", value))
    end)

    -- 4. Visibility
    local combatSeparator = CreateSeparator(content, "Visibility", "TOPLEFT", trailScaleLabel, 0, -40)

    local combatCheckbox = CreateFrame("CheckButton", "SMC_CombatCheckbox", content, "InterfaceOptionsCheckButtonTemplate")
    combatCheckbox:SetPoint("TOPLEFT", combatSeparator, "BOTTOMLEFT", 0, -15)
    _G[combatCheckbox:GetName() .. "Text"]:SetText("Show only in combat")
    combatCheckbox:SetChecked(SMC_Settings.showOnlyInCombat)
    combatCheckbox:SetScript("OnClick", function(self)
        SMC_Settings.showOnlyInCombat = self:GetChecked()
        SMC:ApplySettings()
    end)
    


    -- Modifier Actions
    local shiftDropdown = CreateDropdown("SMC_ShiftDropdown", "When Shift is pressed:", 0, SMC_Settings.shiftAction)
    shiftDropdown:SetPoint("TOPLEFT", combatCheckbox, "BOTTOMLEFT", 0, -20)
    
    UIDropDownMenu_Initialize(shiftDropdown, function(self, level)
        for _, option in ipairs(SMC.modifierOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, shiftDropdown, "shiftAction") end
            info.checked = (SMC_Settings.shiftAction == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ctrlDropdown = CreateDropdown("SMC_CtrlDropdown", "When Ctrl is pressed:", 0, SMC_Settings.ctrlAction)
    ctrlDropdown:SetPoint("TOPLEFT", combatCheckbox, "BOTTOMLEFT", 0, -65)
    
    UIDropDownMenu_Initialize(ctrlDropdown, function(self, level)
        for _, option in ipairs(SMC.modifierOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, ctrlDropdown, "ctrlAction") end
            info.checked = (SMC_Settings.ctrlAction == option)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local altDropdown = CreateDropdown("SMC_AltDropdown", "When Alt is pressed:", 0, SMC_Settings.altAction)
    altDropdown:SetPoint("TOPLEFT", combatCheckbox, "BOTTOMLEFT", 0, -110)
    
    UIDropDownMenu_Initialize(altDropdown, function(self, level)
        for _, option in ipairs(SMC.modifierOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self) OnDropdownClick(self, altDropdown, "altAction") end
            info.checked = (SMC_Settings.altAction == option)
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Transparency Slider
    local transparencyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    transparencyLabel:SetPoint("TOPLEFT", altDropdown, "BOTTOMLEFT", 0, -40)
    transparencyLabel:SetText("Transparency:")
    
    local transparencySlider = CreateFrame("Slider", "SMC_TransparencySlider", content, "OptionsSliderTemplate")
    transparencySlider:SetPoint("LEFT", transparencyLabel, "RIGHT", 10, 0)
    transparencySlider:SetMinMaxValues(0.1, 1.0)
    transparencySlider:SetValue(SMC_Settings.transparency or 1.0)
    transparencySlider:SetValueStep(0.05)
    transparencySlider:SetObeyStepOnDrag(true)
    transparencySlider:SetWidth(150)
    _G[transparencySlider:GetName() .. "Low"]:SetText("10%")
    _G[transparencySlider:GetName() .. "High"]:SetText("100%")
    
    local transparencyValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    transparencyValue:SetPoint("LEFT", transparencySlider, "RIGHT", 5, 0)
    transparencyValue:SetText(string.format("%.0f%%", (SMC_Settings.transparency or 1.0) * 100))
    
    transparencySlider:SetScript("OnValueChanged", function(self, value)
        SMC_Settings.transparency = value
        transparencyValue:SetText(string.format("%.0f%%", value * 100))
        SMC:ApplySettings()
    end)


-- 5. Scale
    local scaleSeparator = CreateSeparator(content, "Scale", "TOPLEFT", transparencyLabel, 0, -40)
    
    local scaleSlider = CreateFrame("Slider", "SMC_ScaleSlider", content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleSeparator, "BOTTOMLEFT", 16, -20)
    scaleSlider:SetMinMaxValues(0.5, 3.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(SMC_Settings.scale)
    scaleSlider:SetWidth(200)
    _G["SMC_ScaleSliderText"]:SetText("Cursor Ring Scale")
    _G["SMC_ScaleSliderLow"]:SetText("0.5")
    _G["SMC_ScaleSliderHigh"]:SetText("3.0")
    
    local scaleValue = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    scaleValue:SetPoint("TOP", scaleSlider, "BOTTOM", 0, -5)
    scaleValue:SetText(string.format("%.1f", SMC_Settings.scale))
    
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value * 10 + 0.5) / 10
        scaleValue:SetText(string.format("%.1f", rounded))
        SMC_Settings.scale = rounded
        SMC:ApplySettings()
    end)

    -- Frame Strata (z-order)
    local strataLabel = CreateSeparator(content, "Frame Strata (layering):", "TOPLEFT", scaleSeparator, 0, -70)


    local strataDropdown = CreateDropdown("SMC_FrameStrataDropdown", "Frame Strata", 0, SMC_Settings.frameStrata or "BACKGROUND")
    strataDropdown:SetPoint("TOPLEFT", strataLabel, "BOTTOMLEFT", 16, -20)

    UIDropDownMenu_Initialize(strataDropdown, function(self, level)
        for _, option in ipairs(SMC.frameStrataOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option
            info.value = option
            info.func = function(self)
                SMC_Settings.frameStrata = option
                UIDropDownMenu_SetText(strataDropdown, option)
                SMC:ApplySettings()
                CloseDropDownMenus()
            end
            info.checked = (SMC_Settings.frameStrata == option)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(strataDropdown, SMC_Settings.frameStrata or "BACKGROUND")

    -- 7. Reset
    local resetSeparator = CreateSeparator(content, "Reset to default values", "TOPLEFT", strataLabel, 0, -70)
    
    local resetButton = CreateFrame("Button", "SMC_ResetButton", content, "UIPanelButtonTemplate")
    resetButton:SetSize(160, 25)
    resetButton:SetPoint("TOPLEFT", resetSeparator, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset to Default Values")
    resetButton:SetScript("OnClick", function(self)
        for key, value in pairs(SMC.defaults) do
            SMC_Settings[key] = value
        end
        scaleSlider:SetValue(SMC_Settings.scale)
        scaleValue:SetText(string.format("%.1f", SMC_Settings.scale))
        UIDropDownMenu_SetText(innerDropdown, SMC_Settings.innerRing)
        UIDropDownMenu_SetText(mainDropdown, SMC_Settings.mainRing)
        UIDropDownMenu_SetText(outerDropdown, SMC_Settings.outerRing)
        reticleClassCheckbox:SetChecked(SMC_Settings.useReticleClassColor)
        powerColorCheckbox:SetChecked(SMC_Settings.usePowerColors)
        mainRingClassCheckbox:SetChecked(SMC_Settings.useMainRingClassColor)
        gcdClassCheckbox:SetChecked(SMC_Settings.useGCDClassColor)
        castClassCheckbox:SetChecked(SMC_Settings.useCastClassColor)
        enableTrailCheckbox:SetChecked(SMC_Settings.enableTrail)
        trailClassColorCheckbox:SetChecked(SMC_Settings.trailUseClassColor)
        trailDurationSlider:SetValue(SMC_Settings.trailDuration)
        trailDurationValue:SetText(string.format("%.2fs", SMC_Settings.trailDuration))
        trailDensitySlider:SetValue(SMC_Settings.trailDensity)
        trailDensityValue:SetText(string.format("%.3fs", SMC_Settings.trailDensity))
        trailScaleSlider:SetValue(SMC_Settings.trailScale)
        trailScaleValue:SetText(string.format("%.1fx", SMC_Settings.trailScale))
        combatCheckbox:SetChecked(SMC_Settings.showOnlyInCombat)
        UIDropDownMenu_SetText(shiftDropdown, SMC_Settings.shiftAction)
        UIDropDownMenu_SetText(ctrlDropdown, SMC_Settings.ctrlAction)
        UIDropDownMenu_SetText(altDropdown, SMC_Settings.altAction)
        UIDropDownMenu_SetText(reticleDropdown, SMC_Settings.reticle)
        reticleScaleSlider:SetValue(SMC_Settings.reticleScale)
        reticleScaleValue:SetText(string.format("%.1f", SMC_Settings.reticleScale))
        transparencySlider:SetValue(SMC_Settings.transparency)
        transparencyValue:SetText(string.format("%.0f%%", SMC_Settings.transparency * 100))
	UIDropDownMenu_SetText(strataDropdown, SMC_Settings.frameStrata or "BACKGROUND")
        SMC:ApplySettings()
        print("|cff00ff00SMC:|r Settings reset to defaults.")
    end)
    
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category, layout = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        layout:AddAnchorPoint("TOPLEFT", 0, 0)
        layout:AddAnchorPoint("BOTTOMRIGHT", 0, 0)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
        SMC.settingsCategory = category
    else
        InterfaceOptions_AddCategory(panel)
    end
    
    SMC.settingsPanel = panel
    return panel
end


-- Push SavedVariables into the live frames (scale, alpha, ring modes, etc.).
function SMC:ApplySettings()
    if SMC_Settings.scale then
        SMC:SetGroupScale(SMC_Settings.scale)
    end
    
    if SMC_CursorFrame then
        local transparency = SMC_Settings.transparency or 1.0
        SMC_CursorFrame:SetAlpha(transparency)

        -- Apply configured frame strata to the main cursor frame
        local strata = SMC_Settings.frameStrata or "BACKGROUND"
        SMC_CursorFrame:SetFrameStrata(strata)
    end
    
    if SMC.GCDCooldownFrame then SMC.GCDCooldownFrame:Hide() end
    if SMC.GCDBackgroundFrame then SMC.GCDBackgroundFrame:Hide() end
    if SMC.CastFrame then SMC.CastFrame:Hide() end
    if SMC.CastBackgroundFrame then SMC.CastBackgroundFrame:Hide() end
    if SMC.HealthFrame then SMC.HealthFrame:Hide() end
    if SMC.HealthBackgroundFrame then SMC.HealthBackgroundFrame:Hide() end
    if SMC.PowerFrame then SMC.PowerFrame:Hide() end
    if SMC_CursorFrame and SMC_CursorFrame.MainRing then SMC_CursorFrame.MainRing:Hide() end
    
    SMC.enableGCD = false
    SMC.enableCast = false
    local trackHealth = false
    local trackPower = false
    
    local slots = {
        {config = SMC_Settings.innerRing, size = 50},
        {config = SMC_Settings.mainRing, size = 70},
        {config = SMC_Settings.outerRing, size = 90},
    }
    
    for _, slot in ipairs(slots) do
        local ringType = slot.config
        local size = slot.size
        
        if ringType == "Main Ring" then
            if SMC_CursorFrame and SMC_CursorFrame.MainRing then
                SMC_CursorFrame.MainRing:SetSize(size, size)
                SMC_CursorFrame.MainRing:Show()
            end
            
        elseif ringType == "GCD" then
            if SMC.GCDCooldownFrame then
                SMC.GCDCooldownFrame:SetSize(size, size)
                SMC.GCDCooldownFrame:Show()
                SMC.enableGCD = true
            end
            if size == 70 and SMC.GCDBackgroundFrame then
                SMC.GCDBackgroundFrame:SetSize(size, size)
                SMC.GCDBackgroundFrame:Show()
            end
            
        elseif ringType == "Cast" then
            if SMC.CastFrame then
                SMC.CastFrame:SetSize(size, size)
                SMC.CastFrame:Show()
                SMC.enableCast = true
            end
            if size == 70 and SMC.CastBackgroundFrame then
                SMC.CastBackgroundFrame:SetSize(size, size)
                SMC.CastBackgroundFrame:Show()
            end
            
        elseif ringType == "Health" then
            if SMC.HealthFrame then
                SMC.HealthFrame:SetSize(size, size)
                SMC.HealthFrame:Show()
                trackHealth = true
            end
            if SMC.HealthBackgroundFrame then
                SMC.HealthBackgroundFrame:SetSize(size, size)
                SMC.HealthBackgroundFrame:Show()
            end
            
        elseif ringType == "Power" then
            if SMC.PowerFrame then
                SMC.PowerFrame:SetSize(size, size)
                SMC.PowerFrame:Show()
                trackPower = true
            end
            
        elseif ringType == "Health and Power" then
            if SMC.HealthFrame then
                SMC.HealthFrame:SetSize(size, size)
                SMC.HealthFrame:Show()
                trackHealth = true
            end
            if SMC.HealthBackgroundFrame then
                SMC.HealthBackgroundFrame:SetSize(size, size)
                SMC.HealthBackgroundFrame:Show()
            end
            if SMC.PowerFrame then
                SMC.PowerFrame:SetSize(size + 10, size + 10)
                SMC.PowerFrame:Show()
                trackPower = true
            end
            
        elseif ringType == "Main Ring + GCD" then
            if SMC_CursorFrame and SMC_CursorFrame.MainRing then
                SMC_CursorFrame.MainRing:SetSize(size, size)
                SMC_CursorFrame.MainRing:Show()
            end
            if SMC.GCDCooldownFrame then
                SMC.GCDCooldownFrame:SetSize(size, size)
                SMC.GCDCooldownFrame:Show()
                SMC.enableGCD = true
            end
            if SMC.GCDBackgroundFrame then
                SMC.GCDBackgroundFrame:SetSize(size, size)
                SMC.GCDBackgroundFrame:Show()
            end
            
        elseif ringType == "Main Ring + Cast" then
            if SMC_CursorFrame and SMC_CursorFrame.MainRing then
                SMC_CursorFrame.MainRing:SetSize(size, size)
                SMC_CursorFrame.MainRing:Show()
            end
            if SMC.CastFrame then
                SMC.CastFrame:SetSize(size, size)
                SMC.CastFrame:Show()
                SMC.enableCast = true
            end
            if SMC.CastBackgroundFrame then
                SMC.CastBackgroundFrame:SetSize(size, size)
                SMC.CastBackgroundFrame:Show()
            end
        end
    end
    
    if SMC.TrackerFrame then
        if SMC.enableGCD then
            SMC.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
        else
            SMC.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_SENT")
        end
        
        if SMC.enableCast then
            SMC.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_START")
            SMC.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
            SMC.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
            SMC.TrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        else
            SMC.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_START")
            SMC.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
            SMC.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
            SMC.TrackerFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        end
        
        if trackHealth then
            SMC.TrackerFrame:RegisterEvent("UNIT_HEALTH")
            SMC.TrackerFrame:RegisterEvent("UNIT_MAXHEALTH")
            if SMC.HealthFrame and SMC.HealthFrame:IsShown() then
                SMC:UpdateHealthRing()
            end
        else
            SMC.TrackerFrame:UnregisterEvent("UNIT_HEALTH")
            SMC.TrackerFrame:UnregisterEvent("UNIT_MAXHEALTH")
        end
        
        if trackPower then
            SMC.TrackerFrame:RegisterEvent("UNIT_POWER_UPDATE")
            SMC.TrackerFrame:RegisterEvent("UNIT_MAXPOWER")
            if SMC.PowerFrame and SMC.PowerFrame:IsShown() then
                SMC:UpdatePowerRing()
            end
        else
            SMC.TrackerFrame:UnregisterEvent("UNIT_POWER_UPDATE")
            SMC.TrackerFrame:UnregisterEvent("UNIT_MAXPOWER")
        end
    end
    
    SMC:UpdateRingColors()
    SMC:UpdateVisibility()
    SMC:UpdateReticle()
end
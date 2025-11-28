--[[
Simple Mouse Cursor - core runtime
Author: Lanni-Alonsus

This file controls all runtime behaviour for the Simple Mouse Cursor addon:
- Keeps the cursor-attached frame positioned under the hardware mouse.
- Drives the three ring layers (GCD, main, cast) and their colours.
- Builds and updates health / power rings.
- Handles ping / crosshair helper animations driven by modifier keys.
- Manages the optional mouse trail and reticle visuals.
- Hooks game events (combat, casting, health / power updates) and forwards
  them into the visual logic.

Configuration (SavedVariables and the settings UI) lives in SMC_Settings.lua.
]]--

SimpleMouseCursor = SimpleMouseCursor or {}
local SMC = SimpleMouseCursor

-- Cache global functions / tables used frequently. This improves readability
-- and gives a tiny performance win inside tight update loops.
local CreateFrame                   = CreateFrame
local UIParent                      = UIParent
local GetCursorPosition             = GetCursorPosition
local GetTime                       = GetTime
local UnitHealth                    = UnitHealth
local UnitHealthMax                 = UnitHealthMax
local UnitPower                     = UnitPower
local UnitPowerMax                  = UnitPowerMax
local UnitClass                     = UnitClass
local UnitPowerType                 = UnitPowerType
local IsShiftKeyDown                = IsShiftKeyDown
local IsControlKeyDown              = IsControlKeyDown
local IsAltKeyDown                  = IsAltKeyDown
local C_ClassColor                  = C_ClassColor
local CombatLogGetCurrentEventInfo  = CombatLogGetCurrentEventInfo
local RAID_CLASS_COLORS             = RAID_CLASS_COLORS
local PowerBarColor                 = PowerBarColor

local TrackerFrame = CreateFrame("Frame", "SMC_TrackerFrame", UIParent)
local LoaderFrame = CreateFrame("Frame")

local GCD_DURATION = 1.5
local GCD_SPELL_ID = 61304 
local _, _, _, interfaceVersion = GetBuildInfo()
local CURRENT_API = interfaceVersion
SMC.GCDCooldownFrame = nil
SMC.GCDBackgroundFrame = nil
SMC.CastFrame = nil
SMC.CastBackgroundFrame = nil
SMC.HealthFrame = nil
SMC.HealthBackgroundFrame = nil
SMC.PowerFrame = nil

SMC.currentGroupScale = 1.0 
SMC.lastGCDTime = 0 
SMC.isGCDAnimating = false 
SMC.isCasting = false
SMC.lastHealthPercent = 1.0
SMC.lastPowerPercent = 1.0

SMC.trailElements = {}
SMC.trailActive = {}
SMC.trailTimer = 0
SMC.trailLastX = 0
SMC.trailLastY = 0

SMC.lastShiftState = false
SMC.lastCtrlState = false
SMC.lastAltState = false

SMC.pingTimer = 0
SMC.isPingAnimating = false
SMC.pingDuration = 0.5
SMC.pingStartSize = 250
SMC.pingEndSize = 70

SMC.crosshairTimer = 0
SMC.isCrosshairAnimating = false
SMC.crosshairDuration = 1.5
SMC.crosshairGap = 35 -- Radius of the ring (70/2)

-- Return the RGB colour that should be used for the given ring type.
function SMC:GetClassColor(ringType)
    local useClassColor = false
    if ringType == "main" then
        useClassColor = SMC_Settings.useMainRingClassColor
    elseif ringType == "gcd" then
        useClassColor = SMC_Settings.useGCDClassColor
    elseif ringType == "cast" then
        useClassColor = SMC_Settings.useCastClassColor
    end

    if useClassColor then
        local _, class = UnitClass("player")
        local classColor = C_ClassColor.GetClassColor(class)
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
    end

    return 1.0, 1.0, 1.0
end

-- Apply the current class / power colours to all active ring frames.
function SMC:UpdateRingColors()
    if SMC.GCDCooldownFrame then
        local r, g, b = SMC:GetClassColor("gcd")
        SMC.GCDCooldownFrame:SetSwipeColor(r, g, b, 1.0)
    end

    if SMC.CastFrame then
        local r, g, b = SMC:GetClassColor("cast")
        SMC.CastFrame:SetSwipeColor(r, g, b, 1.0)
    end

    if SMC_CursorFrame and SMC_CursorFrame.MainRing then
        local r, g, b = SMC:GetClassColor("main")
        SMC_CursorFrame.MainRing:SetVertexColor(r, g, b, 1.0)
    end
end

-- Update the central reticle texture, size, colour and visibility.
function SMC:UpdateReticle()
    if not SMC_CursorFrame or not SMC_CursorFrame.Reticle then return end
    
    local reticleName = SMC_Settings.reticle or "Dot"
    local reticleInfo = SMC.reticleTextures[reticleName]
    
    if not reticleInfo or not reticleInfo.path then
        -- No Reticle or invalid
        SMC_CursorFrame.Reticle:Hide()
    else
        SMC_CursorFrame.Reticle:Show()
        
        if reticleInfo.isAtlas then
            SMC_CursorFrame.Reticle:SetAtlas(reticleInfo.path)
        else
            SMC_CursorFrame.Reticle:SetTexture(reticleInfo.path)
        end
        
        -- Apply scale
        local globalScale = SMC_Settings.reticleScale or 1.0
        SMC_CursorFrame.Reticle:SetScale(reticleInfo.scale * globalScale)
        
        -- Apply class color if enabled
        if SMC_Settings.useReticleClassColor then
            local _, class = UnitClass("player")
            local classColor = C_ClassColor.GetClassColor(class)
            if classColor then
                SMC_CursorFrame.Reticle:SetVertexColor(classColor.r, classColor.g, classColor.b, 1.0)
            else
                SMC_CursorFrame.Reticle:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            end
        else
            SMC_CursorFrame.Reticle:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        end
    end
end

-- Update the scale of the entire cursor group and persist to settings.
function SMC:SetGroupScale(scale)
    if type(scale) == "number" and scale > 0 then
        SMC.currentGroupScale = scale
        SMC_CursorFrame:SetScale(scale)
    end
end

-- Lazily create the textures used for the mouse trail effect.
function SMC:InitializeTrail()
    for i = 1, 300 do
        local texture = UIParent:CreateTexture(nil, "ARTWORK")
        texture:SetTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Dot.tga")
        texture:SetBlendMode("ADD")
        texture:Hide()
        SMC.trailElements[i] = texture
    end
end

-- Advance / fade trail elements each frame while the trail is enabled.
function SMC:UpdateTrail(elapsed)
    -- Check if trail should be visible based on cursor visibility
    local shouldShowTrail = SMC_Settings.enableTrail and SMC_CursorFrame and SMC_CursorFrame:IsShown()
    
    if shouldShowTrail then
        local cursorX, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()

        local x = cursorX - SMC.trailLastX
        local y = cursorY - SMC.trailLastY
        local movement = math.sqrt(x * x + y * y)

        local minMovement = SMC_Settings.trailMinMovement or 0.5
        local density = SMC_Settings.trailDensity or 0.008

        SMC.trailTimer = SMC.trailTimer + elapsed

        if SMC.trailTimer >= density and movement >= minMovement and #SMC.trailElements > 0 then
            SMC.trailTimer = 0

            local element = table.remove(SMC.trailElements)
            table.insert(SMC.trailActive, element)

            element.duration = SMC_Settings.trailDuration or 0.4
            element.x = cursorX / uiScale
            element.y = cursorY / uiScale

            local r, g, b = 1.0, 1.0, 1.0
            if SMC_Settings.trailUseClassColor then
                local _, class = UnitClass("player")
                local classColor = C_ClassColor.GetClassColor(class)
                if classColor then
                    r, g, b = classColor.r, classColor.g, classColor.b
                end
            end

            element:SetVertexColor(r, g, b, 1.0)
            local baseSize = 50 * (SMC_Settings.trailScale or 1.0)
            element:SetSize(baseSize, baseSize)
            element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", element.x, element.y)
            element:SetAlpha(1.0)
            element:Show()

            SMC.trailLastX = cursorX
            SMC.trailLastY = cursorY
        end
    else
        for i = #SMC.trailActive, 1, -1 do
            local element = SMC.trailActive[i]
            element:Hide()
            table.insert(SMC.trailElements, table.remove(SMC.trailActive, i))
        end
    end

    for i = #SMC.trailActive, 1, -1 do
        local element = SMC.trailActive[i]
        element.duration = element.duration - elapsed

        if element.duration <= 0 then
            element:Hide()
            table.insert(SMC.trailElements, table.remove(SMC.trailActive, i))
        else
            local progress = element.duration / (SMC_Settings.trailDuration or 0.4)
            progress = math.min(1.0, math.max(0.0, progress))
            local baseSize = 50 * (SMC_Settings.trailScale or 1.0)
            local size = math.max(5, baseSize * progress)
            element:SetSize(size, size)
            element:SetAlpha(progress)
            element:SetPoint("CENTER", UIParent, "BOTTOMLEFT", element.x, element.y)
        end
    end
end

-- Per-frame driver: move the cursor frame, update trail and handle modifiers.
function SMC:OnUpdate(elapsed)
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetScale()
    local groupScale = SMC.currentGroupScale

    local correctedX = (cursorX / uiScale) / groupScale
    local correctedY = (cursorY / uiScale) / groupScale

    SMC_CursorFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", correctedX, correctedY)

    SMC:UpdateTrail(elapsed)

    -- Modifier Key Logic
    local shiftDown = IsShiftKeyDown()
    local ctrlDown = IsControlKeyDown()
    local altDown = IsAltKeyDown()

    -- Check for Ping/Crosshair triggers (OnPress)
    if shiftDown and not SMC.lastShiftState then
        if SMC_Settings.shiftAction == "Ping with ring" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
        elseif SMC_Settings.shiftAction == "Ping with area" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Dot.tga")
        elseif SMC_Settings.shiftAction == "Ping with crosshair" then SMC:PlayCrosshairAnimation() end
    end
    if ctrlDown and not SMC.lastCtrlState then
        if SMC_Settings.ctrlAction == "Ping with ring" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
        elseif SMC_Settings.ctrlAction == "Ping with area" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Dot.tga")
        elseif SMC_Settings.ctrlAction == "Ping with crosshair" then SMC:PlayCrosshairAnimation() end
    end
    if altDown and not SMC.lastAltState then
        if SMC_Settings.altAction == "Ping with ring" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
        elseif SMC_Settings.altAction == "Ping with area" then SMC:PlayPingAnimation("Interface\\Addons\\SimpleMouseCursor\\Image\\Dot.tga")
        elseif SMC_Settings.altAction == "Ping with crosshair" then SMC:PlayCrosshairAnimation() end
    end

    -- Check for "Show Crosshair" (OnHold)
    local showCrosshair = (shiftDown and SMC_Settings.shiftAction == "Show Crosshair") or
                          (ctrlDown and SMC_Settings.ctrlAction == "Show Crosshair") or
                          (altDown and SMC_Settings.altAction == "Show Crosshair")

    if showCrosshair then
        SMC.isCrosshairAnimating = false -- Stop animation if it was running
        SMC.CrosshairFrame:Show()
        SMC.CrosshairFrame:SetAlpha(1.0)
        SMC:UpdateCrosshairPosition()
    elseif (not shiftDown and SMC.lastShiftState and SMC_Settings.shiftAction == "Show Crosshair") or
           (not ctrlDown and SMC.lastCtrlState and SMC_Settings.ctrlAction == "Show Crosshair") or
           (not altDown and SMC.lastAltState and SMC_Settings.altAction == "Show Crosshair") then
        -- Just released "Show Crosshair", trigger fade out
        SMC:PlayCrosshairAnimation()
    end

    -- Check for Visibility triggers (OnHold)
    local showRings = false
    if shiftDown and SMC_Settings.shiftAction == "Show Rings" then showRings = true end
    if ctrlDown and SMC_Settings.ctrlAction == "Show Rings" then showRings = true end
    if altDown and SMC_Settings.altAction == "Show Rings" then showRings = true end

    if showRings then
        SMC:UpdateVisibility(true)
    elseif (not shiftDown and SMC.lastShiftState and SMC_Settings.shiftAction == "Show Rings") or
           (not ctrlDown and SMC.lastCtrlState and SMC_Settings.ctrlAction == "Show Rings") or
           (not altDown and SMC.lastAltState and SMC_Settings.altAction == "Show Rings") then
         -- Just released a "Show Rings" key, revert to normal visibility
         SMC:UpdateVisibility()
    end

    SMC.lastShiftState = shiftDown
    SMC.lastCtrlState = ctrlDown
    SMC.lastAltState = altDown

    -- Ping Animation Update
    if SMC.isPingAnimating then
        SMC.pingTimer = SMC.pingTimer + elapsed
        if SMC.pingTimer >= SMC.pingDuration then
            SMC.isPingAnimating = false
            SMC.PingFrame:Hide()
        else
            local progress = SMC.pingTimer / SMC.pingDuration
            local size = SMC.pingStartSize - ((SMC.pingStartSize - SMC.pingEndSize) * progress)
            local alpha = 1.0 - progress
            
            SMC.PingFrame:SetSize(size, size)
            SMC.PingFrame:SetAlpha(alpha)
            SMC.PingFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER") 
        end
    end

    -- Crosshair Animation Update
    if SMC.isCrosshairAnimating then
        SMC.crosshairTimer = SMC.crosshairTimer + elapsed
        if SMC.crosshairTimer >= SMC.crosshairDuration then
            SMC.isCrosshairAnimating = false
            SMC.CrosshairFrame:Hide()
        else
            local progress = SMC.crosshairTimer / SMC.crosshairDuration
            local alpha = 1.0
            if progress > 0.7 then -- Fade out in last 30%
                alpha = 1.0 - ((progress - 0.7) / 0.3)
            end
            
            SMC.CrosshairFrame:SetAlpha(alpha)
            
            SMC:UpdateCrosshairPosition()
        end
    end
end

-- Keep the crosshair frame centred on the cursor frame.
function SMC:UpdateCrosshairPosition()
    if not SMC.CrosshairFrame then return end
    
    local gap = SMC.crosshairGap * SMC.currentGroupScale
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    
    -- Top Line
    SMC.CrosshairFrame.Top:ClearAllPoints()
    SMC.CrosshairFrame.Top:SetPoint("TOP", UIParent, "TOPLEFT", cx, 0)
    SMC.CrosshairFrame.Top:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, cy + gap)
    
    -- Bottom Line
    SMC.CrosshairFrame.Bottom:ClearAllPoints()
    SMC.CrosshairFrame.Bottom:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, 0)
    SMC.CrosshairFrame.Bottom:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, cy - gap)
    
    -- Left Line
    SMC.CrosshairFrame.Left:ClearAllPoints()
    SMC.CrosshairFrame.Left:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, cy)
    SMC.CrosshairFrame.Left:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", cx - gap, cy)
    
    -- Right Line
    SMC.CrosshairFrame.Right:ClearAllPoints()
    SMC.CrosshairFrame.Right:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, cy)
    SMC.CrosshairFrame.Right:SetPoint("LEFT", UIParent, "BOTTOMLEFT", cx + gap, cy)
end

-- Spawn and play a ring ping animation at the cursor location.
function SMC:PlayPingAnimation(texturePath)
    if not SMC.PingFrame then return end
    if texturePath then
        SMC.PingFrame:SetTexture(texturePath)
    end
    SMC.isPingAnimating = true
    SMC.pingTimer = 0
    SMC.PingFrame:SetSize(SMC.pingStartSize, SMC.pingStartSize)
    SMC.PingFrame:SetAlpha(1.0)
    SMC.PingFrame:Show()
end

-- Spawn and play the expanding crosshair animation.
function SMC:PlayCrosshairAnimation()
    if not SMC.CrosshairFrame then return end
    SMC.isCrosshairAnimating = true
    SMC.crosshairTimer = 0
    SMC.CrosshairFrame:SetAlpha(1.0)
    SMC.CrosshairFrame:Show()
end

-- Kick off the global cooldown swipe animation on the GCD ring.
function SMC:StartGCDAnimation(startTime, duration)
    if CURRENT_API >= 120000  then return end
    if not SMC.enableGCD then return end
    if SMC.isGCDAnimating then return end

    SMC.isGCDAnimating = true

    local cooldownFrame = SMC.GCDCooldownFrame

    cooldownFrame:Show()
    cooldownFrame:SetCooldown(startTime, duration) 

    local function GCDUpdate(self, elapsed)

        local elapsedCD = GetTime() - startTime
        local remaining = duration - elapsedCD -- Don't max with 0 yet

        if remaining <= -0.25 then -- Wait a tiny bit after it finishes
            cooldownFrame:SetCooldown(0, 0) 
            cooldownFrame:Hide()

            SMC.isGCDAnimating = false 
        end
    end

    SMC_CursorFrame:SetScript("OnUpdate", GCDUpdate)
    GCDUpdate(SMC_CursorFrame, 0)
end

-- Stop any active cast/channel animation and hide the cast ring.
function SMC:StopCastAnimation()
    if not SMC.isCasting then return end

    local castFrame = SMC.CastFrame
    castFrame:Hide()
    SMC.isCasting = false
end

-- Start cast/channel swipe animation on the cast ring.
function SMC:StartCastAnimation(startTime, duration)
    if not SMC.enableCast then return end
    if SMC.isCasting then return end 

    SMC.isCasting = true

    local castFrame = SMC.CastFrame

    castFrame:SetCooldown(startTime, duration) 
    castFrame:Show()

    local function CastUpdate(self, elapsed)
        local elapsedCast = GetTime() - startTime
        local remaining = duration - elapsedCast

        if remaining <= -0.25 then -- Wait a tiny bit
            SMC:StopCastAnimation()
        end
    end

    CastUpdate(SMC_CursorFrame, 0)
end

-- Recompute and redraw the health ring based on the player's health.
function SMC:UpdateHealthRing()
    if CURRENT_API >= 120000 then return end
    local healthFrame = SMC.HealthFrame
    if not healthFrame then return end

    local currentHealth = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")

    if maxHealth == 0 then return end

    local healthPercent = currentHealth / maxHealth
    local missingHealthPercent = 1 - healthPercent

    local r, g, b
    if healthPercent > 0.70 then
        r, g, b = 1.0, 1.0, 1.0
    elseif healthPercent > 0.50 then
        r, g, b = 1.0, 0.788, 0.302
    elseif healthPercent > 0.35 then
        r, g, b = 1.0, 0.451, 0.184
    else
        r, g, b = 0.8, 0.0, 0.02
    end

    healthFrame:SetSwipeColor(r, g, b, 0.8)

    local hugeDuration = 86400
    local elapsed = missingHealthPercent * hugeDuration
    healthFrame:SetCooldown(GetTime() - elapsed, hugeDuration)
    healthFrame:Show()

    SMC.lastHealthPercent = healthPercent
end

-- Handle UNIT_HEALTH/UNIT_MAXHEALTH and forward into UpdateHealthRing.
function SMC:HealthEventHandler(self, event, unit)
    if unit ~= "player" then return end

    SMC:UpdateHealthRing()
end

-- Recompute and redraw the power ring based on the player's resource.
function SMC:UpdatePowerRing()
    if CURRENT_API >= 120000 then return end
    local powerFrame = SMC.PowerFrame
    if not powerFrame then return end

    local currentPower = UnitPower("player")
    local maxPower = UnitPowerMax("player")

    if maxPower == 0 then return end

    local powerPercent = currentPower / maxPower
    local missingPowerPercent = 1 - powerPercent

    local r, g, b = 0.0, 0.5, 1.0

    if SMC_Settings.usePowerColors then
        local powerType, powerToken = UnitPowerType("player")

        if powerType == 0 then
            r, g, b = 0.00, 0.00, 1.00
        elseif powerType == 1 then
            r, g, b = 1.00, 0.00, 0.00
        elseif powerType == 2 then
            r, g, b = 1.00, 0.50, 0.25
        elseif powerType == 3 then
            r, g, b = 1.00, 1.00, 0.00
        elseif powerType == 4 then
            r, g, b = 1.00, 0.96, 0.41
        elseif powerType == 5 then
            r, g, b = 0.50, 0.50, 0.50
        elseif powerType == 6 then
            r, g, b = 0.00, 0.82, 1.00
        elseif powerType == 7 then
            r, g, b = 0.50, 0.32, 0.55
        elseif powerType == 8 then
            r, g, b = 0.30, 0.52, 0.90
        elseif powerType == 9 then
            r, g, b = 0.95, 0.90, 0.60
        elseif powerType == 11 then
            r, g, b = 0.00, 0.50, 1.00
        elseif powerType == 13 then
            r, g, b = 0.40, 0.00, 0.80
        elseif powerType == 12 then
            r, g, b = 0.71, 1.00, 0.92
        elseif powerType == 16 then
            r, g, b = 0.10, 0.10, 0.98
        elseif powerType == 17 then
            r, g, b = 0.788, 0.259, 0.992
        elseif powerType == 18 then
            r, g, b = 1.00, 0.61, 0.00
        end
    end

    powerFrame:SetSwipeColor(r, g, b, 0.8)

    local hugeDuration = 86400
    local elapsed = missingPowerPercent * hugeDuration
    powerFrame:SetCooldown(GetTime() - elapsed, hugeDuration)
    powerFrame:Show()

    SMC.lastPowerPercent = powerPercent
end

-- Handle UNIT_POWER_UPDATE/UNIT_MAXPOWER and forward into UpdatePowerRing.
function SMC:PowerEventHandler(self, event, unit)
    if unit ~= "player" then return end

    SMC:UpdatePowerRing()
end

-- Listen to combat log events and detect spells that trigger the GCD.
function SMC:GCDCastHandler(self, event, unit, spellName, spellId)
    if CURRENT_API >= 120000 then return end
    if GetTime() - SMC.lastGCDTime < 0.1 then return end

    SMC.lastGCDTime = GetTime()

    local GCDInfo = C_Spell.GetSpellCooldown(GCD_SPELL_ID)

    if GCDInfo and GCDInfo.duration > 0 then
        SMC:StartGCDAnimation(GCDInfo.startTime, GCDInfo.duration)
    end

end

-- Handle UNIT_SPELLCAST_* events and manage the cast ring state.
function SMC:CastEventHandler(self, event, unit) 

    local startTime, endTime, infoValid = nil, nil, false

    if event == "UNIT_SPELLCAST_START" then
        local cName, cRank, cTarget, cStartTime, cEndTime = UnitCastingInfo("player")
        startTime, endTime = cStartTime, cEndTime
        infoValid = true

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local chName, chRank, chTarget, chStartTime, chEndTime, isMoving = UnitChannelInfo("player")
        startTime, endTime = chStartTime, chEndTime
        infoValid = true
    end

    if infoValid and startTime and endTime then
        local duration = (endTime - startTime) / 1000 

        if duration > 0.1 then 
            SMC:StartCastAnimation(startTime / 1000, duration)
        end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        SMC:StopCastAnimation()
    end
end

-- Toggle visibility of cursor elements based on combat and settings.
function SMC:UpdateVisibility(forceState)
    if not SMC_CursorFrame then return end

    -- Check Modifiers first (Override - Always Show)
    local shiftDown = IsShiftKeyDown()
    local ctrlDown = IsControlKeyDown()
    local altDown = IsAltKeyDown()
    
    local modifierShow = (shiftDown and SMC_Settings.shiftAction == "Show Rings") or
                         (ctrlDown and SMC_Settings.ctrlAction == "Show Rings") or
                         (altDown and SMC_Settings.altAction == "Show Rings")

    if modifierShow then
        SMC_CursorFrame:Show()
        return
    end

    -- Check Combat State
    local inCombat = forceState
    if inCombat == nil then
        inCombat = InCombatLockdown()
    end

    -- Determine Base Visibility
    if SMC_Settings.showOnlyInCombat then
        if inCombat then
            SMC_CursorFrame:Show()
        else
            SMC_CursorFrame:Hide()
        end
    else
        -- Show Only In Combat is FALSE (Normally Always Visible)
        -- BUT, if any key is configured to "Show Rings", we want to hide it by default
        -- so that the key press actually does something (Push-to-Show).
        
        local isAnyShowRingsConfigured = (SMC_Settings.shiftAction == "Show Rings") or
                                         (SMC_Settings.ctrlAction == "Show Rings") or
                                         (SMC_Settings.altAction == "Show Rings")
                                         
        if isAnyShowRingsConfigured then
            SMC_CursorFrame:Hide()
        else
            SMC_CursorFrame:Show()
        end
    end
end

-- Create the cooldown frames, rings, crosshair and attach them to SMC_CursorFrame.
function SMC:SetupUI()

    local transparency = SMC_Settings.transparency or 1.0
    SMC_CursorFrame:SetAlpha(transparency)

    -- Use configured strata so users can control layering vs UI & world
    local strata = SMC_Settings.frameStrata or "BACKGROUND"
    SMC_CursorFrame:SetFrameStrata(strata)
    SMC_CursorFrame:SetToplevel(false)
    SMC_CursorFrame:Show()
    SMC:SetGroupScale(SMC.currentGroupScale)
    SMC_CursorFrame.MainRing:Show()
    
    SMC:UpdateReticle()

    local gcdBgFrame = CreateFrame("Cooldown", "SMC_GCD_BG_COOLDOWN", SMC_CursorFrame)
    gcdBgFrame:SetSize(70, 70)
    gcdBgFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    gcdBgFrame:SetFrameLevel(2)
    SMC.GCDBackgroundFrame = gcdBgFrame
    gcdBgFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    gcdBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    gcdBgFrame:SetReverse(false)
    gcdBgFrame:SetHideCountdownNumbers(true)
    gcdBgFrame:SetCooldown(GetTime(), 86400)
    gcdBgFrame:Hide()

    local cooldownFrame = CreateFrame("Cooldown", "SMC_GCD_COOLDOWN", SMC_CursorFrame)
    cooldownFrame:SetSize(50, 50)
    cooldownFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    cooldownFrame:SetFrameLevel(3)
    SMC.GCDCooldownFrame = cooldownFrame
    cooldownFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    local r, g, b = SMC:GetClassColor("gcd")
    cooldownFrame:SetSwipeColor(r, g, b, 1.0) 
    cooldownFrame:Hide()

    local castBgFrame = CreateFrame("Cooldown", "SMC_CAST_BG_COOLDOWN", SMC_CursorFrame)
    castBgFrame:SetSize(70, 70)
    castBgFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    castBgFrame:SetFrameLevel(2)
    SMC.CastBackgroundFrame = castBgFrame
    castBgFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    castBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    castBgFrame:SetReverse(false)
    castBgFrame:SetHideCountdownNumbers(true)
    castBgFrame:SetCooldown(GetTime(), 86400)
    castBgFrame:Hide()

    local castFrame = CreateFrame("Cooldown", "SMC_CAST_COOLDOWN", SMC_CursorFrame)
    castFrame:SetSize(90, 90) 
    castFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    castFrame:SetFrameLevel(3)
    SMC.CastFrame = castFrame
    castFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    r, g, b = SMC:GetClassColor("cast")
    castFrame:SetSwipeColor(r, g, b, 1.0) 
    castFrame:Hide()
    castFrame:SetHideCountdownNumbers(true)

    local healthBgFrame = CreateFrame("Cooldown", "SMC_HEALTH_BG_COOLDOWN", SMC_CursorFrame)
    healthBgFrame:SetSize(70, 70)
    healthBgFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    healthBgFrame:SetFrameLevel(2)
    SMC.HealthBackgroundFrame = healthBgFrame
    healthBgFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    healthBgFrame:SetSwipeColor(0.5, 0.5, 0.5, 0.7)
    healthBgFrame:SetReverse(false)
    healthBgFrame:SetHideCountdownNumbers(true)
    healthBgFrame:SetCooldown(GetTime(), 86400)
    healthBgFrame:Hide()

    local healthFrame = CreateFrame("Cooldown", "SMC_HEALTH_COOLDOWN", SMC_CursorFrame)
    healthFrame:SetSize(70, 70)
    healthFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    healthFrame:SetFrameLevel(3)
    SMC.HealthFrame = healthFrame
    healthFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    healthFrame:SetSwipeColor(1.0, 0.0, 0.0, 0.8)
    healthFrame:SetReverse(false)
    healthFrame:SetHideCountdownNumbers(true)
    healthFrame:Hide()

    local powerFrame = CreateFrame("Cooldown", "SMC_POWER_COOLDOWN", SMC_CursorFrame)
    powerFrame:SetSize(80, 80)
    powerFrame:SetPoint("CENTER", SMC_CursorFrame, "CENTER")
    powerFrame:SetFrameLevel(1)
    SMC.PowerFrame = powerFrame
    powerFrame:SetSwipeTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    powerFrame:SetSwipeColor(0.0, 0.5, 1.0, 0.8)
    powerFrame:SetReverse(false)
    powerFrame:SetHideCountdownNumbers(true)
    powerFrame:SetHideCountdownNumbers(true)
    powerFrame:Hide()

    local pingFrame = SMC_CursorFrame:CreateTexture(nil, "OVERLAY")
    pingFrame:SetTexture("Interface\\Addons\\SimpleMouseCursor\\Image\\Main.tga")
    pingFrame:SetBlendMode("ADD")
    pingFrame:SetVertexColor(1.0, 1.0, 1.0, 0.5)
    pingFrame:Hide()
    SMC.PingFrame = pingFrame

    -- Crosshair Frame
    local crosshairFrame = CreateFrame("Frame", "SMC_CrosshairFrame", UIParent)

    -- Keep crosshair on the same frame strata as the main cursor overlay
    local strata = SMC_Settings and SMC_Settings.frameStrata or "BACKGROUND"
    crosshairFrame:SetFrameStrata(strata)
    crosshairFrame:SetAllPoints()
    crosshairFrame:EnableMouse(false)
    crosshairFrame:Hide()
    SMC.CrosshairFrame = crosshairFrame

    local function CreateLine(name)
        local line = crosshairFrame:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 1, 1, 0.5) -- Red, semi-transparent
        line:SetWidth(2) -- Thickness
        return line
    end

    crosshairFrame.Top = CreateLine("Top")
    crosshairFrame.Bottom = CreateLine("Bottom")
    crosshairFrame.Left = CreateLine("Left")
    crosshairFrame.Right = CreateLine("Right")
    
    -- Adjust line thickness for horizontal lines (height instead of width)
    crosshairFrame.Left:SetWidth(0) -- Reset width
    crosshairFrame.Left:SetHeight(2)
    crosshairFrame.Right:SetWidth(0)
    crosshairFrame.Right:SetHeight(2)



    SMC:UpdateHealthRing()
    SMC:UpdatePowerRing()

    SMC:InitializeTrail()

    if SMC.ApplySettings then
        SMC:ApplySettings()
    end

    TrackerFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

-- Wire events, OnUpdate handler and perform initial setup when the addon loads.
function SMC:OnInitialize()
    SMC.TrackerFrame = TrackerFrame

    TrackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    TrackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")


    TrackerFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            if SMC_CursorFrame then
                SMC:SetupUI()
            end

        elseif event:match("UNIT_SPELLCAST_") then 
            SMC:GCDCastHandler(self, event, ...)
            SMC:CastEventHandler(self, event, ...) 

        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            SMC:HealthEventHandler(self, event, ...)

        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            SMC:PowerEventHandler(self, event, ...)

        elseif event == "PLAYER_REGEN_DISABLED" then
            SMC:UpdateVisibility(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            SMC:UpdateVisibility(false)
        end
    end)

    TrackerFrame:SetScript("OnUpdate", SMC.OnUpdate)
    TrackerFrame:Show()
    SMC:OnUpdate(0)
end

LoaderFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "SimpleMouseCursor" then
        SMC:OnInitialize()
        SMC:InitializeSettings()
        SMC:CreateSettingsPanel()
        self:UnregisterAllEvents()
    end
end)
LoaderFrame:RegisterEvent("ADDON_LOADED")
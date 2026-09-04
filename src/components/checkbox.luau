--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A compact alternative to Toggle: same flag/config/description contract and the same
-- full/compact scaffolding, just a small check box instead of a pill + knob.

local Checkbox = {}
Checkbox.__index = Checkbox
Checkbox.__type = "Checkbox"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local lockable = require(utility.lockable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local checkIcon = constants.icons.check
local boxSize = 22

function Checkbox.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Checkbox",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,
        compact = tab.compact or false,

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Checkbox")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,

        value = if (properties.value or properties.Value) ~= nil then (properties.value or properties.Value) else false,
    }, Checkbox)

    self.window:_registerControl(self)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    self.window:_wireTooltip(self)

    if self.description and not self.compact then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

-- the box + checkmark. same in both layouts; caller places it (pinned right / flex item)
function Checkbox:_buildBox(parent)
    local window = self.window

    self.box = window:Create("Frame", {
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(boxSize, boxSize),
        BackgroundColor3 = self.value and self.window.theme.AccentColor or self.window.theme.ToggleKnobOff,

        BackgroundTransparency = 1, -- In = 0 (checked) / ToggleKnobOffTransparency (unchecked)

        Parent = parent,
    })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = self.box,
    })

    self.boxStroke = window:Create("UIStroke", {
        Color = self.value and self.window.theme.AccentStroke or Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- In = 0 (checked) / 0.7 (unchecked)
        Parent = self.box,
    })

    -- Accent glow behind the box; hidden until checked
    self.boxGlow = window:CreateGlow(self.box, "AccentColor", 16, 1)

    self.checkIcon = window:Create("ImageLabel", {
        Image = checkIcon,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ImageColor3 = Color3.fromRGB(255, 255, 255),

        -- Animation: scale-pops in with a check, fades out when unchecked
        ImageTransparency = self.value and 0 or 1,
        Parent = self.box,
    })

    self.checkIconScale = window:Create("UIScale", {
        Scale = self.value and 1 or 0.4,
        Parent = self.checkIcon,
    })

    return self.box
end

-- flip, animate, run callback (error-flash on fail), autosave. press anim is per-layout
function Checkbox:_performCheck()
    hapticEngine.click()
    soundEngine.click()
    self.value = not self.value
    self:_animateBox()

    self.window:_runGuarded(self, self.callback, self.value)
    self.window:_persist(self)
end

-- full-width: title/icon left, box pinned right, width-bounce
function Checkbox:_buildFull()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 41),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)
    self.hoverOverlay = window:CreateHoverOverlay(self.main)

    self.container = window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.main,
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })

    self.containerLayout = window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(250, 16),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        AutomaticSize = Enum.AutomaticSize.X,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(1, 0.5),
        AnchorPoint = Vector2.new(1, 0.5),
        TextTransparency = 1,
        ZIndex = 10,

        Parent = self.main,
    })

    -- box pinned to the right edge
    self:_buildBox(self.main)
    self.box.Position = UDim2.new(1, -20, 0, 20)
    self.box.AnchorPoint = Vector2.new(1, 0.5)

    self.window:_wireElementHover(self)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()
        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { Size = UDim2.new(1, -26, 0, 41) }
            )
            :Play()

        self:_performCheck()

        task.wait(0.11)

        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { Size = UDim2.new(1, -20, 0, 41) }
            )
            :Play()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = self.window.theme.ElementStrokeTransparency }
            )
            :Play()
    end)
end

-- compact (row): title left, box right (SpaceBetween)
function Checkbox:_buildCompact()
    local window = self.window

    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name, 10)
    self.hoverOverlay = self.interact

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 15),
        PaddingRight = UDim.new(0, 15),

        Parent = self.interact,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
        Padding = UDim.new(0, 10),

        Parent = self.interact,
    })

    self.container = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,

        Parent = self.interact,
    })

    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.container,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            LayoutOrder = 0,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    self:_buildBox(self.interact)
    self.box.LayoutOrder = 1

    self.window:_wireElementHover(self)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()

        self:_performCheck()

        task.wait(0.11)

        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = self.window.theme.ElementStrokeTransparency }
            )
            :Play()
    end)
end

-- checked pops with a slight overshoot; unchecked settles back flat
local checkPopIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local checkFadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local boxColorInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function Checkbox:_animateBox()
    local ts = variables.tweenService
    if self.boxGlow then
        ts:Create(self.boxGlow, boxColorInfo, { Transparency = self.value and self.window.theme.AccentGlow or 1 })
            :Play()
    end
    if self.value then
        ts:Create(self.box, boxColorInfo, {
            BackgroundColor3 = self.window.theme.AccentColor,
            BackgroundTransparency = 0,
        }):Play()
        ts:Create(self.boxStroke, boxColorInfo, { Color = self.window.theme.AccentStroke, Transparency = 0 }):Play()
        ts:Create(self.checkIcon, checkPopIn, { ImageTransparency = 0 }):Play()
        ts:Create(self.checkIconScale, checkPopIn, { Scale = 1 }):Play()
    else
        ts:Create(self.box, boxColorInfo, {
            BackgroundColor3 = self.window.theme.ToggleKnobOff,
            BackgroundTransparency = self.window.theme.ToggleKnobOffTransparency,
        }):Play()
        ts:Create(self.boxStroke, boxColorInfo, { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7 }):Play()
        ts:Create(self.checkIcon, checkFadeOut, { ImageTransparency = 1 }):Play()
        ts:Create(self.checkIconScale, checkFadeOut, { Scale = 0.4 }):Play()
    end
end

local checkboxReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local checkboxGlowReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0.35)
-- Live-caught: same ordering fix as toggle.luau's own toggleStateReveal - the box's checked-state
-- colour/checkmark faded in on the same beat as the row it sits on, so it could read as "there"
-- before the row itself looked like a real card yet. Delayed after the row (checkboxReveal via
-- _revealCommon, no delay) but before the glow (checkboxGlowReveal, 0.35s).
local checkboxStateReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0.12)

function Checkbox:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.box, {
            BackgroundColor3 = self.value and w.theme.AccentColor or w.theme.ToggleKnobOff,
            BackgroundTransparency = self.value and 0 or w.theme.ToggleKnobOffTransparency,
        }, animate, checkboxStateReveal)
        w:_reveal(self.boxStroke, {
            Color = self.value and w.theme.AccentStroke or Color3.fromRGB(255, 255, 255),
            Transparency = self.value and 0 or 0.7,
        }, animate, checkboxStateReveal)
        w:_reveal(self.boxGlow, { Transparency = self.value and w.theme.AccentGlow or 1 }, animate, checkboxGlowReveal)
        w:_reveal(self.checkIcon, { ImageTransparency = self.value and 0 or 1 }, animate, checkboxStateReveal)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.box, { BackgroundTransparency = 1 }, animate, checkboxReveal)
        w:_reveal(self.boxStroke, { Transparency = 1 }, animate, checkboxReveal)
        w:_reveal(self.boxGlow, { Transparency = 1 }, animate, checkboxGlowReveal)
        w:_reveal(self.checkIcon, { ImageTransparency = 1 }, animate, checkboxReveal)
    end
end

-- Re-apply the visuals that aren't plain themeProperties, so a runtime ChangeTheme reaches
-- the box. Called on the visible tab only.
function Checkbox:_refreshTheme()
    local t = self.window.theme
    local info = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local ts = variables.tweenService
    ts:Create(self.box, info, {
        BackgroundColor3 = self.value and t.AccentColor or t.ToggleKnobOff,
        BackgroundTransparency = self.value and 0 or t.ToggleKnobOffTransparency,
    }):Play()
    ts:Create(self.boxStroke, info, {
        Color = self.value and t.AccentStroke or Color3.fromRGB(255, 255, 255),
    }):Play()
    if self.boxGlow then
        ts:Create(self.boxGlow, info, { Transparency = self.value and t.AccentGlow or 1 }):Play()
    end
end

-- Room the compact checkbox needs: side padding + icon (and gap) if shown + title text
-- + the gap to the box + the box itself. Lets a horizontal group wrap sensibly.
function Checkbox:_minWidth()
    local w = 30 + 10 + boxSize -- 15+15 padding, 10 gap to box, box itself
    if self.icon then
        w += 21 -- 16 icon + 5 gap
    end
    w += functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(Checkbox)
lockable(Checkbox)

function Checkbox:Set(value, skipCallback)
    local changed = self.value ~= value
    self.value = value

    if changed then
        self:_animateBox()
    end

    -- fire even when unchanged: config load calls Set and relies on the callback to apply
    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self.value)
        self.window:_persist(self)
    end
end

return Checkbox

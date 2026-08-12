--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A read-only gradient bar with a percent (or "340 xp out of 500", with a custom max + suffix)
-- readout. Dev-driven only - no interact surface, no flag/config, no callback - Set() is the
-- only way its value moves, and it animates smoothly when it does.

local ProgressBar = {}
ProgressBar.__index = ProgressBar
ProgressBar.__type = "ProgressBar"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local odometer = require(utility.odometer)
local moveable = require(utility.moveable)
local locale = require(utility.locale)

local tweenInfo = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

function ProgressBar.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Progress",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,

        max = properties.max or properties.Max or 100,
        suffix = properties.suffix or properties.Suffix or "",
    }, ProgressBar)

    if self.max <= 0 then
        self.max = 100
    end

    local initialValue = if (properties.value or properties.Value) ~= nil
        then (properties.value or properties.Value)
        else 0
    self.value = math.clamp(initialValue, 0, self.max)
    self._lastValue = self.value

    self:_buildFull()

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

-- percent by default; "340 xp out of 500" once a suffix says this bar counts something instead
function ProgressBar:_format(value)
    if self.suffix ~= "" then
        return math.floor(value + 0.5) .. " " .. self.suffix .. " out of " .. math.floor(self.max + 0.5)
    end
    local pct = if self.max ~= 0 then (value / self.max) * 100 else 0
    return math.floor(pct + 0.5) .. "%"
end

function ProgressBar:_buildFull()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 60),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    -- Top row: title (+ icon) left, readout right
    self.container = window:Create("Frame", {
        Position = UDim2.new(0, 20, 0, 14),
        Size = UDim2.new(1, -40, 0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    self.containerLayout = window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,

        Parent = self.container,
    })

    -- title grows, value hugs the right - same split as the slider's narrow row
    self.titleFlex = window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Fill,
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
        Size = UDim2.new(1, 0, 0, 16),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    self.valueHost = window:Create("Frame", {
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2,

        Parent = self.container,
    })

    self.valueOdo = odometer.new(self.window, self.valueHost, {
        textSize = 15,
        alignment = Enum.HorizontalAlignment.Right,
        transparency = 1, -- revealed to 0.5 on show, matching the slider readout
        duration = 0.28,
    })
    self.valueOdo:snap(self:_format(self.value))

    -- Bottom: the track
    self.track = window:Create("Frame", {
        Position = UDim2.new(0, 20, 1, -18),
        Size = UDim2.new(1, -40, 0, 10),
        BorderSizePixel = 0,
        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    }, { BackgroundColor3 = "SliderBackground" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 10),
        Parent = self.track,
    })

    self.progress = window:Create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        BackgroundTransparency = 1, -- In = 0

        Parent = self.track,
    })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 10),
        Parent = self.progress,
    })

    window:Create("UIGradient", {
        Offset = Vector2.new(0, 0.5),
        Rotation = 2,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.85),
            NumberSequenceKeypoint.new(1, 0),
        }),

        Parent = self.progress,
    }, { Color = { "SliderProgress", functions.toColorSequence } })

    self.progressGlow = window:CreateGlow(self.progress, "AccentColor", 16, 1)

    self:_renderProgress()
end

function ProgressBar:_renderProgress(info)
    local ratio = if self.max ~= 0 then math.clamp(self.value / self.max, 0, 1) else 0
    local size = UDim2.fromScale(ratio, 1)
    if info then
        variables.tweenService:Create(self.progress, info, { Size = size }):Play()
    else
        self.progress.Size = size
    end
end

-- Animates the bar and rolls the readout to the new value. skipAnimation snaps instead, for a
-- caller restoring a known state (e.g. rebuilding a list of bars) rather than reporting progress.
function ProgressBar:Set(value, skipAnimation)
    value = math.clamp(value, 0, self.max)
    local goingUp = value >= self._lastValue -- compare against the pre-call value first
    self.value = value

    if skipAnimation then
        self:_renderProgress()
        if self.valueOdo then
            self.valueOdo:snap(self:_format(value))
        end
    else
        self:_renderProgress(tweenInfo)
        if self.valueOdo then
            self.valueOdo:to(self:_format(value), goingUp)
        end
    end

    self._lastValue = value
end

local glowReveal = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0.35)

function ProgressBar:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.track, { BackgroundTransparency = 0 }, animate)
        w:_reveal(self.progress, { BackgroundTransparency = 0 }, animate)
        if self.valueOdo then
            self.valueOdo:reveal(0.5, animate)
        end
        w:_reveal(self.progressGlow, { Transparency = math.max(0.55, w.theme.AccentGlow) }, animate, glowReveal)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.track, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.progress, { BackgroundTransparency = 1 }, animate)
        if self.valueOdo then
            self.valueOdo:reveal(1, animate)
        end
        w:_reveal(self.progressGlow, { Transparency = 1 }, animate, glowReveal)
    end
end

function ProgressBar:_refreshTheme()
    variables.tweenService
        :Create(
            self.progressGlow,
            TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Transparency = math.max(0.55, self.window.theme.AccentGlow) }
        )
        :Play()
end

moveable(ProgressBar)

return ProgressBar

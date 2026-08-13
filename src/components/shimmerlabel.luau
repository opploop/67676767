--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A big heading with a soft band of light sweeping across the text, on a loop with a small rest
-- between passes. TextLabels take a UIGradient the same way Frames do (it recolours the glyphs,
-- not a background), so this is just a gradient with a bright band riding a NumberSequence-free
-- Color rebuild, and its Offset tweened back and forth past both edges.

local ShimmerLabel = {}
ShimmerLabel.__index = ShimmerLabel
ShimmerLabel.__type = "ShimmerLabel"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local moveable = require(utility.moveable)
local locale = require(utility.locale)

-- a still moment at each end before the next pass, so it doesn't read as a nervous, continuous
-- back-and-forth loop
local restTime = 0.5

local function clamp01(n)
    return math.clamp(n, 0.02, 0.9)
end

function ShimmerLabel.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        text = properties.text or properties.Text or properties.name or properties.Name or "",
        speed = properties.speed or properties.Speed or 1.4,
        spread = clamp01(properties.spread or properties.Spread or 0.2),
        angle = properties.angle or properties.Angle or 20,
        textSize = properties.textSize or properties.TextSize or 32,
    }, ShimmerLabel)

    self:_build()
    self:_startLoop()

    return self
end

function ShimmerLabel:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, self.textSize + 24),
        BorderSizePixel = 0,
        Name = "ShimmerLabel",
        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    })

    self.label = window:Create("TextLabel", {
        Text = locale.t(self.text),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = self.textSize,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,

        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "PlaceholderColor", FontFace = "TitleFont" })

    self.gradient = window:Create("UIGradient", {
        Rotation = self.angle,
        Offset = Vector2.new(-1 - self.spread, 0),

        Parent = self.label,
    })

    self:_rebuildColors()
end

-- Base (muted) everywhere except a bright band self.spread wide, centred on the gradient's own
-- middle - the Offset sweep is what carries that band across the text, not this sequence itself.
function ShimmerLabel:_rebuildColors()
    local base = self.window.theme.PlaceholderColor
    local bright = self.window.theme.ContentColor
    local half = self.spread / 2

    self.gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, base),
        ColorSequenceKeypoint.new(0.5 - half, base),
        ColorSequenceKeypoint.new(0.5, bright),
        ColorSequenceKeypoint.new(0.5 + half, base),
        ColorSequenceKeypoint.new(1, base),
    })
end

function ShimmerLabel:_startLoop()
    task.spawn(function()
        while self.gradient.Parent do
            local reach = 1 + self.spread
            self.gradient.Offset = Vector2.new(-reach, 0)
            local tween = variables.tweenService:Create(
                self.gradient,
                TweenInfo.new(self.speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Offset = Vector2.new(reach, 0) }
            )
            tween:Play()
            tween.Completed:Wait()
            task.wait(restTime)
        end
    end)
end

-- Runtime setters - size, speed, angle and text are all adjustable per the devlog; spread too,
-- since it's shown as its own slider in the reference.
function ShimmerLabel:Set(text)
    self.text = tostring(text)
    self.label.Text = locale.resolve(self.text)
end

function ShimmerLabel:SetSpeed(seconds)
    self.speed = math.max(0.2, seconds)
end

function ShimmerLabel:SetSpread(fraction)
    self.spread = clamp01(fraction)
    self:_rebuildColors()
end

function ShimmerLabel:SetAngle(degrees)
    self.angle = degrees
    self.gradient.Rotation = degrees
end

function ShimmerLabel:SetTextSize(size)
    self.textSize = size
    self.label.TextSize = size
    self.main.Size = UDim2.new(1, -20, 0, size + 24)
end

function ShimmerLabel:_setShown(shown, animate)
    self.window:_reveal(self.label, { TextTransparency = if shown then 0 else 1 }, animate)
end

moveable(ShimmerLabel)

return ShimmerLabel

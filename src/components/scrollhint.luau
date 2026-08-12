--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A centred line of text with a bouncing arrow underneath it, for pointing a user further down
-- a page. Purely decorative - no card, no flag, no callback. Set(text) swaps the line at runtime.

local ScrollHint = {}
ScrollHint.__index = ScrollHint
ScrollHint.__type = "ScrollHint"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)

local chevronIcon = constants.icons.chevron

function ScrollHint.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        text = properties.text or properties.Text or properties.name or properties.Name or "Scroll for more",
    }, ScrollHint)

    self:_build()
    self:_startBounce()

    return self
end

function ScrollHint:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 40),
        BorderSizePixel = 0,
        Name = "ScrollHint",
        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    })

    -- the row hugs its own content and sits centred in the full-width main, rather than
    -- the usual left-anchored layout every other element uses
    self.container = window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,

        Parent = self.container,
    })

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.text),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        LayoutOrder = 0,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- layout-managed wrapper (fixed slot, sized to the icon) holding the actual icon - the
    -- bounce tweens the icon's own Position inside it, so it never fights the row's
    -- UIListLayout the way tweening a direct layout child's Position would.
    self.arrowSlot = window:Create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 1,

        Parent = self.container,
    })

    self.arrow = window:Create("ImageLabel", {
        Image = chevronIcon,
        Size = UDim2.fromScale(1, 1),
        Rotation = 180, -- chevron points down (matches the dropdown's collapsed orientation)
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        ImageTransparency = 1, -- In = 0

        Parent = self.arrowSlot,
    }, { ImageColor3 = "ContentColor" })
end

-- Gentle up/down bob, forever, purely as a "look here" cue. Exits on its own once the arrow's
-- gone (Tab:Remove tore the instances down) - matches Window's LiveAnimation loop shape, just
-- scoped to one element instead of the whole window.
local bounceInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

function ScrollHint:_startBounce()
    task.spawn(function()
        local down = true
        while self.arrow.Parent do
            local tween = variables.tweenService
                :Create(self.arrow, bounceInfo, { Position = UDim2.fromOffset(0, down and 5 or 0) })
            tween:Play()
            tween.Completed:Wait()
            down = not down
        end
    end)
end

-- Update the line at runtime.
function ScrollHint:Set(text)
    self.text = tostring(text)
    self.title.Text = locale.resolve(self.text)
end

function ScrollHint:_setShown(shown, animate)
    local w = self.window
    w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
    w:_reveal(self.arrow, { ImageTransparency = if shown then 0 else 1 }, animate)
end

moveable(ScrollHint)

return ScrollHint

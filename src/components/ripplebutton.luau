--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A Button variant whose press feedback is a ripple spreading from the exact point you press
-- (mouse or touch), clipped to the card's rounded corners, instead of Button's usual stroke-ghost
-- + width-bounce flash.

local RippleButton = {}
RippleButton.__index = RippleButton
RippleButton.__type = "RippleButton"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)

function RippleButton.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Button",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        compact = tab.compact or false,

        callback = properties.callback or properties.Callback or function() end,
    }, RippleButton)

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

function RippleButton:_runCallback()
    self.window:_runGuarded(self, self.callback)
end

-- A clipped overlay matching the card's own rounded corners. Parented right after the hover
-- overlay and before the title/icon (both default ZIndex 1, so sibling order alone puts this
-- above the faint hover tint but under the text - a ripple that reads without blurring it).
function RippleButton:_buildRippleLayer(parent)
    self.rippleClip = self.window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,

        Parent = parent,
    })

    self.window:Create("UICorner", {
        Parent = self.rippleClip,
    }, { CornerRadius = "ElementCornerRadius" })

    return self.rippleClip
end

-- Expand a circle from the press point to well past the card's far corner, fading out as it
-- grows. AbsoluteSize's diagonal is the longest any interior point can be from any corner, so
-- it's always enough regardless of where the press landed.
local rippleInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function RippleButton:_spawnRipple(screenPosition)
    local size = self.main.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return -- not laid out yet (e.g. a stray input mid-reveal)
    end

    -- screenPosition and AbsolutePosition are already in the same coordinate space (see
    -- Window:_mouseAbsolutePosition) - no GuiInset adjustment needed on top of it.
    local localPos = screenPosition - self.main.AbsolutePosition
    local diameter = size.Magnitude

    local circle = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(localPos.X, localPos.Y),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.65,
        BorderSizePixel = 0,

        Parent = self.rippleClip,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = circle,
    })

    variables.tweenService
        :Create(circle, rippleInfo, {
            Size = UDim2.fromOffset(diameter, diameter),
            BackgroundTransparency = 1,
        })
        :Play()

    -- Destroy is idempotent, so this is safe even if the element (and this circle along with
    -- it) was already torn down by a Tab:Remove mid-ripple.
    task.delay(rippleInfo.Time, function()
        circle:Destroy()
    end)
end

function RippleButton:_wireRipple()
    self.window:ConnectFor(self, self.interact.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_spawnRipple(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        self:_runCallback()
    end)
end

-- full-width: title/icon left (matches button.luau, minus the width-bounce press flash)
function RippleButton:_buildFull()
    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 43),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = 0

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.main)
    self:_buildRippleLayer(self.main)

    self.container = self.window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.main,
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })

    self.containerLayout = self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
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

    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        TextTransparency = 1,

        Parent = self.main,
    })

    self.window:_wireElementHover(self)
    self:_wireRipple()
end

-- compact (row): content-sized, centred icon + title (matches button.luau)
function RippleButton:_buildCompact()
    local window = self.window

    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name)
    self.hoverOverlay = self.interact
    self:_buildRippleLayer(self.interact)

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),

        Parent = self.interact,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),

        Parent = self.interact,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            LayoutOrder = 0,

            ImageTransparency = 1, -- In = 0

            Parent = self.interact,
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

        Parent = self.interact,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    self.window:_wireElementHover(self)
    self:_wireRipple()
end

function RippleButton:_setShown(shown, animate)
    if shown then
        self.window:_revealCommon(self, animate)
    else
        self.window:_hideCommon(self, animate)
    end
end

-- Room the compact ripple button needs before its label would clip: side padding + icon
-- (and its gap) if shown + the title text.
function RippleButton:_minWidth()
    local w = 32 -- interact padding, 16 each side
    if self.icon then
        w += 22 -- 16 icon + 6 gap to title
    end
    w += functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(RippleButton)

return RippleButton

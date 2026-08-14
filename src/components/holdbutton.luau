--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 6: a press-and-hold confirm button. A fill bar slides left -> right while held, clipped
-- to the card's own rounded corners; the callback only fires once the fill actually reaches
-- 100%. Releasing early snaps the fill back empty instead of firing anything - the point is to
-- make an accidental tap harmless for a destructive action ("Hold to wipe save" etc).

local HoldButton = {}
HoldButton.__index = HoldButton
HoldButton.__type = "HoldButton"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)

local cancelInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function HoldButton.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Hold Button",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        compact = tab.compact or false,

        -- seconds the bar takes to fill; danger = tint the fill red instead of the accent colour
        holdDuration = properties.holdDuration or properties.HoldDuration or 1,
        danger = properties.danger or properties.Danger or false,
        locked = properties.locked or properties.Locked or false,

        callback = properties.callback or properties.Callback or function() end,

        _holding = false,
    }, HoldButton)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    self:_applyLocked(false)
    self.window:_wireTooltip(self)

    if self.description and not self.compact then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

function HoldButton:_runCallback()
    self.window:_runGuarded(self, self.callback)
end

-- Clipped overlay matching the card's own rounded corners, holding the actual fill bar.
-- Parented after the hover overlay and before the title/icon (all default ZIndex 1, so
-- creation order alone keeps it above the hover tint but under the text).
function HoldButton:_buildFillLayer(parent)
    self.fillClip = self.window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,

        Parent = parent,
    })
    self.window:Create("UICorner", {
        Parent = self.fillClip,
    }, { CornerRadius = "ElementCornerRadius" })

    self.fill = self.window:Create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,

        Parent = self.fillClip,
    }, { BackgroundColor3 = if self.danger then "ErrorColor" else "AccentColor" })

    return self.fillClip
end

function HoldButton:_beginHold()
    if self.locked or self._holding then
        return
    end
    self._holding = true
    variables.tweenService:Create(self.fill, TweenInfo.new(self.holdDuration, Enum.EasingStyle.Linear), {
        Size = UDim2.fromScale(1, 1),
    }):Play()

    local holdToken = (self._holdToken or 0) + 1
    self._holdToken = holdToken
    task.delay(self.holdDuration, function()
        -- still the same hold, and it wasn't released early - completes it
        if self._holding and self._holdToken == holdToken then
            self._holding = false
            self.fill.Size = UDim2.new(0, 0, 1, 0)
            hapticEngine.click()
            self:_runCallback()
        end
    end)
end

function HoldButton:_cancelHold()
    if not self._holding then
        return
    end
    self._holding = false
    self._holdToken = (self._holdToken or 0) + 1 -- invalidate the pending completion above
    variables.tweenService:Create(self.fill, cancelInfo, { Size = UDim2.new(0, 0, 1, 0) }):Play()
end

function HoldButton:_wireHold()
    self.window:ConnectFor(self, self.interact.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self:_beginHold()
        end
    end)

    -- global, like the pickers' own drag release: a mouse-up anywhere ends the hold, not just
    -- one that lands back on the button
    self.window:ConnectFor(self, variables.userInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self:_cancelHold()
        end
    end)
end

-- full-width: title/icon left (matches button.luau's layout, minus the click flash)
function HoldButton:_buildFull()
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
    self:_buildFillLayer(self.main)

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

    self.lockIcon = self:_buildLockIcon(self.main)

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
    self:_wireHold()
end

-- compact (row): content-sized, centred icon + title
function HoldButton:_buildCompact()
    local window = self.window

    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name)
    self.hoverOverlay = self.interact
    self:_buildFillLayer(self.interact)

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

    self.lockIcon = self:_buildLockIcon(self.main)

    self.window:_wireElementHover(self)
    self:_wireHold()
end

-- A small padlock, drawn from two plain frames (no icon asset needed): a rounded body and a
-- thin rounded shackle arc sitting above it. Sits pinned to the row's right edge, only shown
-- while locked.
function HoldButton:_buildLockIcon(parent)
    local holder = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Visible = false,

        Parent = parent,
    })

    local body = self.window:Create("Frame", {
        Position = UDim2.new(0.5, 0, 1, 0),
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(14, 9),
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = holder,
    }, { BackgroundColor3 = "PlaceholderColor" })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = body })

    local shackle = self.window:Create("Frame", {
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(9, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = holder,
    })
    self.window:Create("UIStroke", {
        Thickness = 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,

        Parent = shackle,
    }, { Color = "PlaceholderColor" })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shackle })

    return holder
end

-- Dim the content, show the padlock, and stop new holds from starting - any hold already in
-- progress is cancelled outright rather than left to finish.
function HoldButton:_applyLocked(animate)
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local set = function(instance, props)
        if not instance then
            return
        end
        if animate then
            variables.tweenService:Create(instance, info, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end

    self.lockIcon.Visible = true
    set(self.title, { TextTransparency = if self.locked then 0.6 else 0 })
    if self.iconLabel then
        set(self.iconLabel, { ImageTransparency = if self.locked then 0.6 else 0 })
    end
    if not self.locked then
        task.delay(if animate then info.Time else 0, function()
            if not self.locked then
                self.lockIcon.Visible = false
            end
        end)
    end

    if self.locked and self._holding then
        self:_cancelHold()
    end
end

function HoldButton:SetLocked(locked)
    locked = locked and true or false
    if locked == self.locked then
        return
    end
    self.locked = locked
    self:_applyLocked(true)
end

function HoldButton:_setShown(shown, animate)
    if shown then
        self.window:_revealCommon(self, animate)
    else
        self.window:_hideCommon(self, animate)
        self:_cancelHold()
    end
end

-- Room the compact hold button needs before its label would clip.
function HoldButton:_minWidth()
    local w = 32
    if self.icon then
        w += 22
    end
    w += functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(HoldButton)

return HoldButton

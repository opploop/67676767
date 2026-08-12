--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Copies a string to the clipboard in one click. Title/icon left like Button; the pinned-right
-- "well" is the copy control itself - it pops, squishes, and swaps its icon for a checkmark that
-- reverts after 2s. Falls back gracefully (no error, just no copy) when the executor exposes no
-- clipboard writer.

local CopyButton = {}
CopyButton.__index = CopyButton
CopyButton.__type = "CopyButton"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local clipboard = require(utility.clipboard)
local hapticEngine = require(utility.HapticEngine)
local log = require(utility.log)

local checkIcon = constants.icons.check
local wellSize = 28
local revertDelay = 2 -- seconds the checkmark holds before reverting

function CopyButton.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Copy",
        icon = properties.icon or properties.Icon, -- shown inside the well
        description = properties.description or properties.Description,
        compact = tab.compact or false,

        text = tostring(properties.text or properties.Text or properties.value or properties.Value or ""),

        callback = properties.callback or properties.Callback or function() end,

        _copyToken = 0, -- bumped per press so a rapid re-click restarts the revert cleanly
    }, CopyButton)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    if self.description and not self.compact then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

-- the icon well: a round field with the dev's icon, swappable for a checkmark. same in both
-- layouts; caller places it (pinned right / flex item)
function CopyButton:_buildWell(parent)
    local window = self.window

    self.well = window:Create("Frame", {
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(wellSize, wellSize),

        BackgroundTransparency = 1, -- In = FieldTransparency
        Parent = parent,
    }, { BackgroundColor3 = "FieldBackground" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.well,
    })

    self.wellStroke = window:Create("UIStroke", {
        Transparency = 1, -- In = 0.85
        Parent = self.well,
    }, { Color = "SurfaceStroke" })

    self.wellGlow = window:CreateGlow(self.well, "FieldGlow", 18, 1)

    self.wellScale = window:Create("UIScale", {
        Scale = 1,
        Parent = self.well,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0
            Parent = self.well,
        }, { ImageColor3 = "ContentColor" })
    end

    self.checkIcon = window:Create("ImageLabel", {
        Image = checkIcon,
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ImageColor3 = Color3.fromRGB(255, 255, 255),

        ImageTransparency = 1, -- swapped in on a successful copy
        Parent = self.well,
    })

    return self.well
end

-- pop -> squish -> swap to the checkmark -> settle. the swap lands at the bottom of the
-- squish, where it's smallest and the crossfade reads as one motion instead of two. Kept snappy
-- end to end (checkmark lands well under a quarter second after the press) - only the 2s hold
-- before revert is meant to read as a deliberate pause.
local popInfo = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local squishInfo = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local settleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local crossfadeInfo = TweenInfo.new(0.06, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local revertInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function CopyButton:_playSuccess()
    local ts = variables.tweenService
    self._copyToken += 1
    local token = self._copyToken

    ts:Create(self.wellScale, popInfo, { Scale = 1.12 }):Play()
    task.delay(popInfo.Time, function()
        if self._copyToken ~= token then
            return
        end
        ts:Create(self.wellScale, squishInfo, { Scale = 0.82 }):Play()
        task.delay(squishInfo.Time, function()
            if self._copyToken ~= token then
                return
            end
            -- swap at the squish's low point
            if self.iconLabel then
                ts:Create(self.iconLabel, crossfadeInfo, { ImageTransparency = 1 }):Play()
            end
            ts:Create(self.checkIcon, crossfadeInfo, { ImageTransparency = 0 }):Play()
            ts:Create(self.wellScale, settleInfo, { Scale = 1 }):Play()

            task.delay(revertDelay, function()
                if self._copyToken ~= token then
                    return -- a newer press already owns the well
                end
                if self.iconLabel then
                    ts:Create(self.iconLabel, revertInfo, { ImageTransparency = 0 }):Play()
                end
                ts:Create(self.checkIcon, revertInfo, { ImageTransparency = 1 }):Play()
            end)
        end)
    end)
end

-- a copy that found no clipboard function still gets a press acknowledgement, just no checkmark
function CopyButton:_playMiss()
    local ts = variables.tweenService
    self._copyToken += 1
    local token = self._copyToken

    ts:Create(self.wellScale, popInfo, { Scale = 1.08 }):Play()
    task.delay(popInfo.Time, function()
        if self._copyToken ~= token then
            return
        end
        ts:Create(self.wellScale, squishInfo, { Scale = 0.88 }):Play()
        task.delay(squishInfo.Time, function()
            if self._copyToken ~= token then
                return
            end
            ts:Create(self.wellScale, settleInfo, { Scale = 1 }):Play()
        end)
    end)
end

function CopyButton:_performCopy()
    hapticEngine.click()
    local ok = clipboard.copy(self.text)

    if ok then
        self:_playSuccess()
    else
        self:_playMiss()
        -- once per button, not once per click - an impatient user mashing it shouldn't spam the console
        if not self._warnedNoClipboard then
            self._warnedNoClipboard = true
            log.warn(
                `Rayfield: no clipboard function exposed by this executor, the CopyButton '{self.name}' couldn't copy.`
            )
        end
    end

    self.window:_runGuarded(self, self.callback, ok)
end

-- full-width: title/description left, well pinned right, width-bounce (matches button.luau)
function CopyButton:_buildFull()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 43),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)
    self.hoverOverlay = window:CreateHoverOverlay(self.main)

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(250, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        AutomaticSize = Enum.AutomaticSize.X,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,

        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        TextTransparency = 1,

        Parent = self.main,
    })

    self:_buildWell(self.main)
    self.well.Position = UDim2.new(1, -18, 0, 21)
    self.well.AnchorPoint = Vector2.new(1, 0.5)

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
                { Size = UDim2.new(1, -26, 0, 43) }
            )
            :Play()

        self:_performCopy()

        task.wait(0.11)

        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { Size = UDim2.new(1, -20, 0, 43) }
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

-- compact (row): title left, well right (SpaceBetween)
function CopyButton:_buildCompact()
    local window = self.window

    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name, 10)
    self.hoverOverlay = self.interact

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 15),
        PaddingRight = UDim.new(0, 15),

        Parent = self.interact,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
        Padding = UDim.new(0, 10),

        Parent = self.interact,
    })

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 0,

        TextTransparency = 1, -- In = 0

        Parent = self.interact,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    self:_buildWell(self.interact)
    self.well.LayoutOrder = 1

    self.window:_wireElementHover(self)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()

        self:_performCopy()

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

-- iconLabel (the dev icon inside the well) is already handled by _revealCommon/_hideCommon
function CopyButton:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.well, { BackgroundTransparency = w.theme.FieldTransparency }, animate)
        w:_reveal(self.wellStroke, { Transparency = 0.85 }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.well, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.wellStroke, { Transparency = 1 }, animate)
    end
end

-- Re-apply the well's theme-driven fill transparency on a runtime ChangeTheme.
function CopyButton:_refreshTheme()
    variables.tweenService
        :Create(
            self.well,
            TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { BackgroundTransparency = self.window.theme.FieldTransparency }
        )
        :Play()
end

-- Update the string this button copies without rebuilding it.
function CopyButton:Set(text)
    self.text = tostring(text)
end

-- Room the compact copy button needs: side padding + title text + gap to the well + the well.
function CopyButton:_minWidth()
    local w = 30 + 10 + wellSize -- 15+15 padding, 10 gap to well, well itself
    w += functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(CopyButton)

return CopyButton

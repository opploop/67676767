--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A Button that carries two labels. Hovering flips the title between them (a clipped container
-- squishes shut, swaps text, springs back open - Roblox UI has no real 3D, so this is the fake
-- card-flip every UI kit leans on). Clicking still runs the callback like a normal Button.

local FlipButton = {}
FlipButton.__index = FlipButton
FlipButton.__type = "FlipButton"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local titleHeight = 16

function FlipButton.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Button",
        secondaryName = properties.secondaryName
            or properties.SecondaryName
            or properties.backText
            or properties.BackText,
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        compact = tab.compact or false,

        callback = properties.callback or properties.Callback or function() end,

        _showingBack = false,
    }, FlipButton)

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

-- callback + red error-flash, shared by both layouts
function FlipButton:_runCallback()
    self.window:_runGuarded(self, self.callback)
end

-- the clipped title wrapper both layouts flip. fixed to the wider of the two faces so the
-- squish/reopen never reflows anything next to it.
function FlipButton:_buildFlipContainer(parent, layoutOrder)
    local window = self.window
    local font = window.theme.Font

    self._frontWidth = functions.textWidth(font, 16, self.name)
    self._backWidth = functions.textWidth(font, 16, self.secondaryName or "")
    self._faceWidth = math.max(self._frontWidth, self._backWidth, 1)

    self.flipContainer = window:Create("Frame", {
        Size = UDim2.fromOffset(self._faceWidth, titleHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = layoutOrder,

        Parent = parent,
    })

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,

        TextTransparency = 1, -- In = 0

        Parent = self.flipContainer,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    return self.flipContainer
end

-- squish shut, swap the label at the bottom (hidden by the clip), spring back open
local closeInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local openInfo = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function FlipButton:_flip(showBack)
    if not self.secondaryName or self.secondaryName == "" then
        return -- nothing to flip to
    end
    if self._showingBack == showBack then
        return
    end
    self._showingBack = showBack

    self._flipToken = (self._flipToken or 0) + 1
    local token = self._flipToken

    local ts = variables.tweenService
    ts:Create(self.flipContainer, closeInfo, { Size = UDim2.fromOffset(0, titleHeight) }):Play()

    -- task.delay rather than Tween.Completed: a same-property tween created before this one
    -- finishes (a quick re-hover) cancels it, and a cancelled tween's Completed is unreliable
    -- across executors. A plain delay always fires, and the token guard still drops it if a
    -- newer flip has since taken over the container.
    task.delay(closeInfo.Time, function()
        if self._flipToken ~= token then
            return -- superseded by a newer flip; that one owns the container now
        end
        self.title.Text = locale.resolve(showBack and self.secondaryName or self.name)
        ts:Create(self.flipContainer, openInfo, { Size = UDim2.fromOffset(self._faceWidth, titleHeight) }):Play()
    end)
end

-- Hover flips the title for a mouse; MouseEnter/MouseLeave never fire for touch at all, so
-- without this a phone never sees the back face. A tap toggles it instead - same _flip, just a
-- different trigger. Shared by both layouts so the two builds can't drift out of sync on this.
function FlipButton:_wireFlipTrigger()
    self.window:ConnectFor(self, self.interact.MouseEnter, function()
        if not self.window:_interactive() then
            return
        end
        self:_flip(true)
    end)
    self.window:ConnectFor(self, self.interact.MouseLeave, function()
        self:_flip(false)
    end)
    self.window:ConnectFor(self, self.interact.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch or not self.window:_interactive() then
            return
        end
        self:_flip(not self._showingBack)
    end)
end

-- full-width: icon left, flipping title beside it, width-bounce on press (matches button.luau)
function FlipButton:_buildFull()
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

    self.container = self.window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.main,
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })

    self.containerLayout = self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
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

    self:_buildFlipContainer(self.container, 1)

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
    self:_wireFlipTrigger()

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
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

        self:_runCallback()

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

-- compact (row): content-sized, centred icon + flipping title, no width-bounce
function FlipButton:_buildCompact()
    local window = self.window

    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name)
    self.hoverOverlay = self.interact

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),

        Parent = self.interact,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
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

    self:_buildFlipContainer(self.interact, 1)

    self.window:_wireElementHover(self)
    self:_wireFlipTrigger()

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()

        self:_runCallback()

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

function FlipButton:_setShown(shown, animate)
    if shown then
        self.window:_revealCommon(self, animate)
    else
        self.window:_hideCommon(self, animate)
    end
end

-- Update either face without rebuilding. Pass nil to leave a face as-is. Resizes the flip
-- container (tweened, like the input/keybind pill) when the wider face changes.
function FlipButton:Set(front, back)
    if front ~= nil then
        self.name = tostring(front)
    end
    if back ~= nil then
        self.secondaryName = tostring(back)
    end

    local font = self.window.theme.Font
    self._frontWidth = functions.textWidth(font, 16, self.name)
    self._backWidth = functions.textWidth(font, 16, self.secondaryName or "")
    local faceWidth = math.max(self._frontWidth, self._backWidth, 1)

    if faceWidth ~= self._faceWidth then
        self._faceWidth = faceWidth
        variables.tweenService
            :Create(self.flipContainer, constants.pillResizeInfo, { Size = UDim2.fromOffset(faceWidth, titleHeight) })
            :Play()
    end

    self.title.Text = locale.resolve(self._showingBack and self.secondaryName or self.name)
end

-- Room the compact flip button needs before its label would clip: side padding + icon
-- (and its gap) if shown + the wider of the two faces.
function FlipButton:_minWidth()
    local w = 32 -- interact padding, 16 each side
    if self.icon then
        w += 22 -- 16 icon + 6 gap to title
    end
    w += self._faceWidth or functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(FlipButton)

return FlipButton

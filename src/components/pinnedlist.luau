--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A list of icon/title/subtitle rows. Hovering an unpinned row reveals its pin control; a
-- pinned row's stays visible. Pinning moves the row between two sub-sections ("Pinned list"
-- above, "All Items" below) and every currently-visible row glides to its new spot (a FLIP
-- animation: capture positions, reparent/reorder, then tween from the old spot to the layout's
-- new one) rather than snapping. Pinning also works from code via an item handle's Set().

local PinnedList = {}
PinnedList.__index = PinnedList
PinnedList.__type = "PinnedList"

local Item = {}
Item.__index = Item

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local constants = require(utility.constants)
local locale = require(utility.locale)
local assignOrder = require(utility.ordering)
local hapticEngine = require(utility.HapticEngine)
local moveable = require(utility.moveable)

local rowHeight = 54
local flipInfo = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local pinFadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function PinnedList.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        -- no built-in pin glyph asset ships with the library; default to the existing
        -- check/dot pair (already cached - see constants.icons) so pinned/unpinned still
        -- reads clearly without one. Pass pinIcon/unpinIcon for a real thumbtack glyph.
        pinIcon = properties.pinIcon or properties.PinIcon or constants.icons.check,
        unpinIcon = properties.unpinIcon or properties.UnpinIcon or constants.icons.dot,

        items = {},
    }, PinnedList)

    self:_build()

    for _, itemDef in properties.items or properties.Items or {} do
        self:AddItem(itemDef)
    end

    return self
end

function PinnedList:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Name = "PinnedList",

        Parent = self.tab.tabPage,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),

        Parent = self.main,
    })

    self.pinnedHeader = self:_buildHeader(self.main, "Pinned list", 0)
    self.pinnedContainer = self:_buildContainer(self.main, 1)
    self.allHeader = self:_buildHeader(self.main, "All Items", 2)
    self.allContainer = self:_buildContainer(self.main, 3)
end

-- A muted section-style label. Hidden (both header and its own top spacing) while its group
-- has nothing in it, e.g. "Pinned list" before anything's been pinned.
function PinnedList:_buildHeader(parent, text, layoutOrder)
    local window = self.window

    local header = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = layoutOrder,

        Parent = parent,
    })

    local label = window:Create("TextLabel", {
        Text = locale.t(text),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 0.6,

        Parent = header,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    return { main = header, label = label }
end

function PinnedList:_buildContainer(parent, layoutOrder)
    local window = self.window

    local container = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = layoutOrder,

        Parent = parent,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),

        Parent = container,
    })

    return container
end

-- Show a group's header only once it holds something - an empty "Pinned list" above nothing
-- would just read as a stray label.
function PinnedList:_updateHeaders()
    local pinnedCount, allCount = 0, 0
    for _, item in self.items do
        if item.pinned then
            pinnedCount += 1
        else
            allCount += 1
        end
    end
    self.pinnedHeader.main.Visible = pinnedCount > 0
    self.allHeader.main.Visible = allCount > 0
end

function PinnedList:_reorder(container, pinned)
    local order = 0
    for _, item in self.items do
        if item.pinned == pinned then
            assignOrder(item, order * 10)
            order += 1
        end
    end
end

function Item:_buildRow(list)
    local window = list.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, rowHeight),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.pinned and list.pinnedContainer or list.allContainer,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)
    self.hoverOverlay = window:CreateHoverOverlay(self.main)

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(28, 28),
            Position = UDim2.new(0, 16, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.main,
        }, { ImageColor3 = "ContentColor" })
    end

    self.textContainer = window:Create("Frame", {
        Position = UDim2.new(0, self.icon and 56 or 16, 0.5, 0),
        Size = UDim2.new(1, (self.icon and -56 or -16) - 50, 0, 34),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),

        Parent = self.textContainer,
    })

    self.titleLabel = window:Create("TextLabel", {
        Text = locale.t(self.title),
        Size = UDim2.new(1, 0, 0, 17),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 0,

        TextTransparency = 1, -- In = 0

        Parent = self.textContainer,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.subtitleLabel = window:Create("TextLabel", {
        Text = locale.t(self.subtitle),
        Size = UDim2.new(1, 0, 0, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,
        Visible = self.subtitle ~= "",

        TextTransparency = 1, -- In = 0.5

        Parent = self.textContainer,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- pin control: a small circle, filled + a checkmark while pinned, a faint hollow dot
    -- (hover-only) while not
    self.pinButton = window:Create("Frame", {
        Size = UDim2.fromOffset(26, 26),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BorderSizePixel = 0,
        BackgroundColor3 = self.pinned and window.theme.AccentColor or window.theme.ToggleKnobOff,

        BackgroundTransparency = 1,

        Parent = self.main,
    })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.pinButton,
    })

    self.pinIconLabel = window:Create("ImageLabel", {
        Image = self.pinned and list.pinIcon or list.unpinIcon,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ImageColor3 = Color3.fromRGB(255, 255, 255),

        ImageTransparency = 1,

        Parent = self.pinButton,
    })

    self.pinInteract = window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,
        ZIndex = 10,

        Parent = self.pinButton,
    })

    window:ConnectFor(list, self.pinInteract.MouseButton1Click, function()
        hapticEngine.click()
        self:SetPinned(not self.pinned)
    end)

    window:ConnectFor(list, self.main.MouseEnter, function()
        if not window:_interactive() then
            return
        end
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = window.theme.ElementStrokeHoverTransparency, Color = window.theme.ElementStrokeHover }
            )
            :Play()
        variables.tweenService
            :Create(self.hoverOverlay, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                BackgroundTransparency = 0.97,
            })
            :Play()
        if not self.pinned then
            variables.tweenService:Create(self.pinIconLabel, pinFadeInfo, { ImageTransparency = 0.3 }):Play()
        end
    end)

    window:ConnectFor(list, self.main.MouseLeave, function()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = window.theme.ElementStrokeTransparency, Color = window.theme.ElementStroke }
            )
            :Play()
        variables.tweenService
            :Create(self.hoverOverlay, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1,
            })
            :Play()
        if not self.pinned then
            variables.tweenService:Create(self.pinIconLabel, pinFadeInfo, { ImageTransparency = 1 }):Play()
        end
    end)

    self:_setShown(not window.hidden, not window.hidden)
end

-- Snapshot every visible row's AbsolutePosition, run `mutate` (a reparent + reorder), then
-- glide every row that actually moved from its old spot to wherever the layout settled it -
-- the FLIP technique: capture, reparent (layout jumps instantly), tween the resulting jump away.
local function flipReflow(list, mutate)
    local before = {}
    for _, item in list.items do
        if item.main then
            before[item] = item.main.AbsolutePosition
        end
    end

    mutate()

    task.defer(function()
        for item, fromPos in before do
            if not item.main or not item.main.Parent then
                continue -- removed mid-transition
            end
            local toPos = item.main.AbsolutePosition
            local delta = fromPos - toPos
            if math.abs(delta.X) > 0.5 or math.abs(delta.Y) > 0.5 then
                local settled = item.main.Position
                item.main.Position = settled + UDim2.fromOffset(delta.X, delta.Y)
                variables.tweenService:Create(item.main, flipInfo, { Position = settled }):Play()
            end
        end
    end)
end

-- Move this item between the Pinned list and All Items groups, gliding every visible row
-- (not just this one) to its new spot. skipAnimation snaps instead, for a caller restoring a
-- known state rather than reacting to a user/dev action.
function Item:SetPinned(pinned, skipAnimation)
    if self.pinned == pinned or not self.list then
        return
    end

    local list = self.list
    local function mutate()
        self.pinned = pinned
        self.main.Parent = pinned and list.pinnedContainer or list.allContainer
        list:_reorder(list.pinnedContainer, true)
        list:_reorder(list.allContainer, false)
        list:_updateHeaders()
    end

    if skipAnimation then
        mutate()
    else
        flipReflow(list, mutate)
    end

    local window = list.window
    variables.tweenService:Create(self.pinButton, pinFadeInfo, {
        BackgroundColor3 = pinned and window.theme.AccentColor or window.theme.ToggleKnobOff,
        BackgroundTransparency = pinned and 0 or window.theme.ToggleKnobOffTransparency,
    }):Play()
    variables.tweenService
        :Create(self.pinIconLabel, pinFadeInfo, { ImageTransparency = pinned and 0 or 1 })
        :Play()
    self.pinIconLabel.Image = pinned and list.pinIcon or list.unpinIcon
end

function Item:Pin()
    self:SetPinned(true)
end

function Item:Unpin()
    self:SetPinned(false)
end

function Item:_setShown(shown, animate)
    local w = self.list.window
    if shown then
        w:_reveal(self.stroke, { Transparency = w.theme.ElementStrokeTransparency }, animate)
        w:_reveal(self.main, { BackgroundTransparency = w.theme.ElementTransparency or 0 }, animate)
        w:_reveal(self.titleLabel, { TextTransparency = 0 }, animate)
        w:_reveal(self.subtitleLabel, { TextTransparency = 0.5 }, animate)
        if self.iconLabel then
            w:_reveal(self.iconLabel, { ImageTransparency = 0 }, animate)
        end
        w:_reveal(self.pinButton, {
            BackgroundTransparency = self.pinned and 0 or w.theme.ToggleKnobOffTransparency,
        }, animate)
        w:_reveal(self.pinIconLabel, { ImageTransparency = self.pinned and 0 or 1 }, animate)
    else
        w:_reveal(self.stroke, { Transparency = 1 }, animate)
        w:_reveal(self.main, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.titleLabel, { TextTransparency = 1 }, animate)
        w:_reveal(self.subtitleLabel, { TextTransparency = 1 }, animate)
        if self.iconLabel then
            w:_reveal(self.iconLabel, { ImageTransparency = 1 }, animate)
        end
        w:_reveal(self.pinButton, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.pinIconLabel, { ImageTransparency = 1 }, animate)
    end
end

function PinnedList:AddItem(itemDef)
    itemDef = if typeof(itemDef) == "table" then itemDef else {}

    local item = setmetatable({
        list = self,
        icon = itemDef.icon or itemDef.Icon,
        title = itemDef.title or itemDef.Title or "",
        subtitle = itemDef.subtitle or itemDef.Subtitle or "",
        pinned = itemDef.pinned or itemDef.Pinned or false,
    }, Item)

    item:_buildRow(self)
    table.insert(self.items, item)

    self:_reorder(self.pinnedContainer, true)
    self:_reorder(self.allContainer, false)
    self:_updateHeaders()

    return item
end

function PinnedList:_setShown(shown, animate)
    for _, item in self.items do
        item:_setShown(shown, animate)
    end
end

function PinnedList:_refreshTheme()
    for _, item in self.items do
        variables.tweenService:Create(item.pinButton, pinFadeInfo, {
            BackgroundColor3 = item.pinned and self.window.theme.AccentColor or self.window.theme.ToggleKnobOff,
        }):Play()
    end
end

-- Reorders the whole list within its tab; individual rows aren't independently moveable.
moveable(PinnedList)

return PinnedList

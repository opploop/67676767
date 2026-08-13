--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A list of icon/title/subtitle rows. Hovering an unpinned row reveals its pin control; a
-- pinned row's stays visible. Pinning moves the row between two sub-sections ("Pinned list"
-- above, "All Items" below) - the toggled row glides from its old screen position to its new
-- one (see Item:SetPinned for why that's a floating visual clone rather than the real row's
-- Position), while any other row it displaces just snaps to its new spot. Pinning also works
-- from code via an item handle's Set().

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
-- Back rather than Quint: a touch of overshoot-then-settle so a whole list reflowing reads as
-- spring-like motion instead of a flat ease, closer to the reference build's reorder. Longer
-- than it looks like it needs to be (0.45 still read as "almost instant" - a one-row glide is
-- a small distance, so it needs the extra time just to be perceptible at all).
local flipInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local pinFadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function PinnedList.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,

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
        -- a well behind the icon, same idea as the copy button's - a raised square (rounded
        -- corners, not a full circle) so the glyph doesn't just float bare against the row
        self.iconWell = window:Create("Frame", {
            Size = UDim2.fromOffset(34, 34),
            Position = UDim2.new(0, 16, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BorderSizePixel = 0,

            BackgroundTransparency = 1, -- In = FieldTransparency

            Parent = self.main,
        }, { BackgroundColor3 = "FieldBackground" })

        window:Create("UICorner", {
            CornerRadius = UDim.new(0, 10),
            Parent = self.iconWell,
        })

        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.iconWell,
        }, { ImageColor3 = "ContentColor" })
    end

    -- well ends at 16 + 34 = 50; text starts at 60, a tighter 10px gap (18px read as too
    -- spacious once the well itself grew from the original bare 28px icon)
    self.textContainer = window:Create("Frame", {
        Position = UDim2.new(0, self.icon and 60 or 16, 0.5, 0),
        Size = UDim2.new(1, (self.icon and -60 or -16) - 50, 0, 34),
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

        TextTransparency = 1, -- In = 0.6

        Parent = self.textContainer,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- pin control: a small circle holding a pin glyph - a neutral filled background while
    -- pinned, a faint hollow one (hover-only) while not; SetPinned re-tweens this color
    -- directly, so it's a plain resolved value here rather than a live-bound theme key
    self.pinButton = window:Create("Frame", {
        Size = UDim2.fromOffset(26, 26),
        Position = UDim2.new(1, -16, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BorderSizePixel = 0,
        BackgroundColor3 = self.pinned and window.theme.FieldBackground or window.theme.ToggleKnobOff,

        BackgroundTransparency = 1,

        Parent = self.main,
    })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.pinButton,
    })

    self.pinIconLabel = window:Create("ImageLabel", {
        Image = constants.icons.pin,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,

        ImageTransparency = 1, -- In = 0

        Parent = self.pinButton,
    }, { ImageColor3 = "ContentColor" })

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
        self._hovering = true
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
            variables.tweenService:Create(self.pinButton, pinFadeInfo, {
                BackgroundTransparency = window.theme.ToggleKnobOffTransparency,
            }):Play()
        end
    end)

    window:ConnectFor(list, self.main.MouseLeave, function()
        self._hovering = false
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
            variables.tweenService:Create(self.pinButton, pinFadeInfo, { BackgroundTransparency = 1 }):Play()
        end
    end)

    self:_setShown(not window.hidden, not window.hidden)
end

-- Move this item between the Pinned list and All Items groups. skipAnimation snaps instead,
-- for a caller restoring a known state rather than reacting to a user/dev action.
--
-- Several attempts at a true FLIP reorder (animating the real row's Position, or every
-- displaced row's) all fought UIListLayout in one way or another - re-asserting Position on
-- top of the tween, breaking AutomaticSize on the containers when detached (collapsing them
-- and clipping rows/leaking the game world behind), and racing when two rows were toggled in
-- quick succession (completely normal usage) despite queuing attempts. Each fix confirmed live
-- only to surface the next failure mode under real interaction (rapid clicks, window drags/
-- resizes mid-animation).
--
-- This never touches a layout at all: the real row reparents and re-sorts instantly through
-- the layouts it was already always attached to (which cannot get that wrong - there's nothing
-- to fight when nothing is disabled or detached), hidden for one frame while that settles. A
-- plain visual clone, parented outside any layout, glides from the row's old screen position to
-- its new one on top of where the hidden real row will land. Other displaced rows still just
-- snap to their new spot with no glide of their own - a real trade-off against the fully
-- animated reorder that kept breaking, but a stable one.
function Item:SetPinned(pinned, skipAnimation)
    if self.pinned == pinned or not self.list then
        return
    end

    local list = self.list
    local window = list.window

    if skipAnimation then
        self.pinned = pinned
        self.main.Parent = pinned and list.pinnedContainer or list.allContainer
        list:_reorder(list.pinnedContainer, true)
        list:_reorder(list.allContainer, false)
        list:_updateHeaders()
    else
        local fromPos = self.main.AbsolutePosition
        local size = self.main.AbsoluteSize

        local ghost = self.main:Clone()
        ghost.Name = "PinGhost"
        ghost.AnchorPoint = Vector2.zero
        ghost.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
        ghost.Size = UDim2.fromOffset(size.X, size.Y)
        -- the window uses ZIndexBehavior.Global, so a descendant's ZIndex is compared against
        -- every other GuiObject in the whole tree regardless of nesting - setting only the
        -- ghost's own ZIndex does nothing for its (mostly default-ZIndex-1) children, which
        -- would still render wherever ZIndex 1 falls among the rest of the window's content.
        -- Bump every descendant by the same offset instead, preserving their relative stacking
        -- (e.g. pinInteract's own +10 over its siblings) just shifted as a whole into the clear.
        ghost.ZIndex += constants.zIndex.pinnedListGhost
        for _, descendant in ghost:GetDescendants() do
            if descendant:IsA("GuiObject") then
                descendant.ZIndex += constants.zIndex.pinnedListGhost
            end
        end
        ghost.Parent = window.screenGui

        self.main.Visible = false
        self.pinned = pinned
        self.main.Parent = pinned and list.pinnedContainer or list.allContainer
        list:_reorder(list.pinnedContainer, true)
        list:_reorder(list.allContainer, false)
        list:_updateHeaders()

        task.spawn(function()
            -- two frames for the (untouched, still fully in control) layout to settle the real
            -- row into its new spot before reading it back as the glide's target
            task.wait()
            task.wait()

            if self.main and self.main.Parent then
                local toPos = self.main.AbsolutePosition
                variables.tweenService
                    :Create(ghost, flipInfo, { Position = UDim2.fromOffset(toPos.X, toPos.Y) })
                    :Play()
            end

            task.delay(flipInfo.Time, function()
                ghost:Destroy()
                if self.main then
                    self.main.Visible = true
                end
            end)
        end)
    end

    -- unpinning while still hovered (the common case - this is usually reached by clicking the
    -- button itself) rests at the hover-faint level rather than vanishing out from under the
    -- cursor; unpinning from code with nothing hovering it goes fully hidden, like at rest.
    local restTransparency = if pinned
        then window.theme.FieldTransparency
        elseif self._hovering then window.theme.ToggleKnobOffTransparency
        else 1
    variables.tweenService:Create(self.pinButton, pinFadeInfo, {
        BackgroundColor3 = pinned and window.theme.FieldBackground or window.theme.ToggleKnobOff,
        BackgroundTransparency = restTransparency,
    }):Play()
    variables.tweenService
        :Create(self.pinIconLabel, pinFadeInfo, { ImageTransparency = pinned and 0 or 1 })
        :Play()
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
        w:_reveal(self.subtitleLabel, { TextTransparency = 0.6 }, animate)
        if self.iconLabel then
            w:_reveal(self.iconWell, { BackgroundTransparency = w.theme.FieldTransparency }, animate)
            w:_reveal(self.iconLabel, { ImageTransparency = 0 }, animate)
        end
        -- unpinned starts fully hidden (not just faint) - only a hover reveals it; pinned
        -- rests at the same soft translucent fill as other inset fields (Input, search box)
        w:_reveal(self.pinButton, {
            BackgroundTransparency = self.pinned and w.theme.FieldTransparency or 1,
        }, animate)
        w:_reveal(self.pinIconLabel, { ImageTransparency = self.pinned and 0 or 1 }, animate)
    else
        w:_reveal(self.stroke, { Transparency = 1 }, animate)
        w:_reveal(self.main, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.titleLabel, { TextTransparency = 1 }, animate)
        w:_reveal(self.subtitleLabel, { TextTransparency = 1 }, animate)
        if self.iconLabel then
            w:_reveal(self.iconWell, { BackgroundTransparency = 1 }, animate)
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

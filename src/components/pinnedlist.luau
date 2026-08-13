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
    self.pinnedContainer, self.pinnedLayout = self:_buildContainer(self.main, 1)
    self.allHeader = self:_buildHeader(self.main, "All Items", 2)
    self.allContainer, self.allLayout = self:_buildContainer(self.main, 3)
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

    local layout = window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),

        Parent = container,
    })

    return container, layout
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

-- Snapshot every visible row's AbsolutePosition, run `mutate` (a reparent + reorder), then
-- glide every row that actually moved from its old spot to wherever the layout settled it -
-- the FLIP technique: capture, reparent (layout jumps instantly), tween the resulting jump away.
-- primaryItem (the one that was actually clicked/Set) leads immediately; every other displaced
-- row starts a little behind it, staggered by how far down the list it sits from the primary -
-- so the reorder reads as that row pushing the rest of the stack out of its way, not everything
-- just teleporting into a new spot at once.
local function flipReflow(list, mutate, primaryItem)
    local before = {}
    local indexOf = {}
    local primaryIndex = 1
    for index, item in list.items do
        indexOf[item] = index
        if item.main then
            before[item] = item.main.AbsolutePosition
        end
        if item == primaryItem then
            primaryIndex = index
        end
    end

    mutate()

    -- task.defer resumes before this executor's UIListLayout has actually recalculated the new
    -- AbsolutePosition (same timing gap RenderStepped connections fall into elsewhere in this
    -- library) - "before" and "after" would read identical, delta ~0, and every row would just
    -- snap with no visible glide. task.wait() already proved reliable for exactly this
    -- (_startLoop's follow loop), so use that instead of trusting deferral timing here too.
    task.spawn(function()
        -- Serialize the animation phase: clicking multiple rows quickly (completely normal
        -- usage) fires overlapping flipReflow calls, and a reference count on the detach/
        -- reattach alone wasn't enough - each call was ALSO freezing the containers' Size from
        -- their own AbsoluteSize.Y, so a second call starting mid-animation would freeze from a
        -- first call's still-mid-tween (not yet settled) height, locking in a wrong value for
        -- both. That's the "everything piles up, then leaves gaps where rows used to be" - each
        -- overlapping call was capturing and freezing a different, momentarily-wrong height.
        -- Only one flip may own the shared layout/container state at a time; mutate() above
        -- still always runs immediately so pin state and button visuals never wait on this.
        while list._flipping do
            task.wait()
        end
        list._flipping = true

        -- two frames, not one: this reflow can move a row across containers (pinned <-> all
        -- items) plus toggle the section headers' visibility, more for the layout to settle
        -- than the single-container reorder task.wait() was first proven against
        task.wait()
        task.wait()

        -- Confirmed live: a UIListLayout re-asserts its own children's Position essentially
        -- every step, so the tween below was losing that fight instantly - the row would jump
        -- straight to its settled spot within ~90ms and sit there for the rest of flipInfo's
        -- duration, reading as no animation at all. UIListLayout.Enabled doesn't exist on this
        -- client (setting it throws "not a valid member" - silently swallowed since this runs
        -- inside task.spawn, which is why that fix looked like it worked in isolated testing
        -- but never actually ran the loop below it), so detach the layout instead: unparenting
        -- it stops it managing children just as well, and reparenting it back afterward makes
        -- it recompute fresh - AddItem/_reorder already set every child's final LayoutOrder
        -- before this runs, so that recompute just confirms the same positions.
        --
        -- Both containers use AutomaticSize.Y, which measures its UIListLayout's content
        -- height - detach that layout and there's nothing left to measure, so the container
        -- collapses for as long as it's gone. Confirmed live too: the whole list's height
        -- shrinks mid-glide, clipping rows out and leaking the game world behind them, then
        -- the clipped rows "pop" back in once the layout reattaches - not the rows disappearing,
        -- the container they're clipped against disappearing out from under them. Freeze each
        -- container at its own already-settled height (captured now, before detaching) and
        -- switch off AutomaticSize for the same window, so nothing downstream even notices the
        -- layout is briefly gone.
        for _, entry in {
            { container = list.pinnedContainer, layout = list.pinnedLayout },
            { container = list.allContainer, layout = list.allLayout },
        } do
            entry.container.Size = UDim2.new(1, 0, 0, entry.container.AbsoluteSize.Y)
            entry.container.AutomaticSize = Enum.AutomaticSize.None
            entry.layout.Parent = nil
        end

        local maxStagger = 0
        for item, fromPos in before do
            if not item.main or not item.main.Parent then
                continue -- removed mid-transition
            end
            local toPos = item.main.AbsolutePosition
            local delta = fromPos - toPos
            if math.abs(delta.X) > 0.5 or math.abs(delta.Y) > 0.5 then
                local settled = item.main.Position
                item.main.Position = settled + UDim2.fromOffset(delta.X, delta.Y)

                -- the clicked row leads; everything it displaces follows a beat behind, later
                -- the further down the list it sits from that row - reads as the click pushing
                -- the rest of the stack out of the way rather than the whole list teleporting
                local distance = math.abs((indexOf[item] or primaryIndex) - primaryIndex)
                local stagger = item == primaryItem and 0 or math.min(distance * 0.035, 0.18)
                maxStagger = math.max(maxStagger, stagger)

                if stagger == 0 then
                    variables.tweenService:Create(item.main, flipInfo, { Position = settled }):Play()
                else
                    task.delay(stagger, function()
                        if item.main and item.main.Parent then
                            variables.tweenService:Create(item.main, flipInfo, { Position = settled }):Play()
                        end
                    end)
                end
            end
        end

        task.delay(flipInfo.Time + maxStagger, function()
            list.pinnedLayout.Parent = list.pinnedContainer
            list.allLayout.Parent = list.allContainer
            list.pinnedContainer.AutomaticSize = Enum.AutomaticSize.Y
            list.allContainer.AutomaticSize = Enum.AutomaticSize.Y
            list._flipping = false
        end)
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
        flipReflow(list, mutate, self)
    end

    local window = list.window
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

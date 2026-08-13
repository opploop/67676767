--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A pill bar split into equal segments, with a white indicator that slides to whichever one is
-- active. A segment can itself hold a couple of nested options (e.g. "Premium" holding "Monthly"
-- / "Annual") - picking it expands those inline, sharing the same slot the collapsed label sat
-- in, rather than growing the bar. Every segment's own width comes from HorizontalFlex.Fill, so
-- the indicator's target Position/Size is plain fraction math (index/count) - no AbsolutePosition
-- reads, no waiting on a layout to settle, nothing for it to race with.

local SegmentedPicker = {}
SegmentedPicker.__index = SegmentedPicker
SegmentedPicker.__type = "SegmentedPicker"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)

local fadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local barHeight = 40
-- text sitting directly on the white indicator (a selected top-level segment, or an inactive
-- child once expanded - the outer white shows through behind it) needs dark ink to read; text
-- on the dark bar itself, or on the childIndicator's own dark inset, needs the theme's light one
local darkTextColor = Color3.fromRGB(20, 20, 20)
local childIndicatorColor = Color3.fromRGB(20, 20, 20)
local childIndicatorInset = 3 -- px of white margin left showing around the childIndicator

-- Squish & stretch, in two tweens rather than one: a quick stretch into a shape spanning both
-- the old and new bounds (so the pill briefly smears in the direction of travel, like it's
-- being dragged rather than teleported), then a springy settle - Back overshoots slightly past
-- the exact target size before easing back, reading as a soft bounce rather than a hard stop.
local stretchInfo = TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local settleInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function slideIndicator(pill, targetPos, targetSize, skipAnimation)
    if skipAnimation then
        pill.Position, pill.Size = targetPos, targetSize
        return
    end

    local fromPos, fromSize = pill.Position, pill.Size
    local fromLeft = fromPos.X.Scale
    local fromRight = fromLeft + fromSize.X.Scale
    local toLeft = targetPos.X.Scale
    local toRight = toLeft + targetSize.X.Scale

    local stretchLeft = math.min(fromLeft, toLeft)
    local stretchRight = math.max(fromRight, toRight)

    -- offset components (the childIndicator's inset margin) carry over unchanged - only the
    -- scale portion actually needs to stretch across the gap between old and new position
    local stretchPos = UDim2.new(stretchLeft, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset)
    local stretchSize =
        UDim2.new(stretchRight - stretchLeft, targetSize.X.Offset, targetSize.Y.Scale, targetSize.Y.Offset)

    local stretchTween =
        variables.tweenService:Create(pill, stretchInfo, { Position = stretchPos, Size = stretchSize })
    stretchTween:Play()

    -- :Once() isn't guaranteed on every client this session has run into - :Connect() + manual
    -- disconnect is the one form of "run this once" every client here has actually supported
    local connection
    connection = stretchTween.Completed:Connect(function()
        connection:Disconnect()
        variables.tweenService:Create(pill, settleInfo, { Position = targetPos, Size = targetSize }):Play()
    end)
end

-- Accepts a bare string ("Low") or a table ({ text = "Premium", options = {...} }); always
-- returns the table shape internally so every other function only has one case to handle.
local function normalizeOption(option)
    if typeof(option) == "table" then
        return {
            text = option.text or option.Text or "",
            options = option.options or option.Options,
        }
    end
    return { text = tostring(option) }
end

function SegmentedPicker.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local rawOptions = properties.options or properties.Options or {}
    local options = {}
    for _, option in rawOptions do
        table.insert(options, normalizeOption(option))
    end

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        options = options,
        description = properties.description or properties.Description,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,
        callback = properties.callback or properties.Callback or function() end,

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "SegmentedPicker")
                or nil
            ),
    }, SegmentedPicker)

    self.window:_registerControl(self)

    self:_build()

    -- resolve the initial value: a leaf's own text (nested or not), defaulting to the first
    -- top-level option's first available leaf
    local initial = properties.value or properties.Value
    local index, childIndex = self:_find(initial)
    if not index then
        index, childIndex = 1, (options[1] and options[1].options) and 1 or nil
    end
    if childIndex then
        self.segments[index].activeChild = childIndex
        self.segments[index].collapsedLabel.Text = locale.resolve(self:_childText(index, childIndex))
    end
    self:_select(index, childIndex, true)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    self.window:_restoreLate(self)

    return self
end

function SegmentedPicker:_childText(index, childIndex)
    local child = self.options[index].options[childIndex]
    return if typeof(child) == "table" then child.text or child.Text else tostring(child)
end

-- Locate a leaf by its text; returns (topLevelIndex, childIndex?) or nil if it isn't in
-- self.options at all (e.g. a stale saved value from before the options list changed).
function SegmentedPicker:_find(text)
    if text == nil then
        return nil
    end
    for i, option in self.options do
        if option.text == text then
            return i, nil
        end
        if option.options then
            for j, child in option.options do
                local childText = if typeof(child) == "table" then child.text or child.Text else tostring(child)
                if childText == text then
                    return i, j
                end
            end
        end
    end
    return nil
end

function SegmentedPicker:_build()
    local window = self.window

    -- self.main is the outer, tabPage-parented frame - assignOrder (shared by every Tab/Group)
    -- sets element.main.LayoutOrder directly, so this has to be the actual tabPage child or the
    -- picker's position among the tab's other elements would silently stop tracking creation
    -- order. A darker frame here, the same idea as the icon well behind PinnedList's icons - a
    -- dedicated background specifically surrounding this element rather than just the ordinary
    -- card treatment every other element gets, for a more "premium" look. self.bar (below) is
    -- the actual pill everything else in this file already assumes "main" means.
    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, barHeight + 34),
        BorderSizePixel = 0,
        Name = "SegmentedPicker",
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),

        BackgroundTransparency = 1, -- In = 0.5

        Parent = self.tab.tabPage,
    })

    window:Create("UICorner", {
        Parent = self.main,
    }, { CornerRadius = "ElementCornerRadius" })

    self.bar = window:Create("Frame", {
        Size = UDim2.new(1, -16, 0, barHeight),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        Name = "Bar",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.main,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.bar)

    window:Create("UICorner", {
        Parent = self.bar,
    }, { CornerRadius = "PillCornerRadius" })

    self.row = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.bar,
    })

    -- the sliding indicator - a free Frame with no layout of its own, so tweening its Position/
    -- Size directly never has anything to fight (see toggle.luau's knob, same idea). No explicit
    -- ZIndex on this or the two siblings below - confirmed live that staggering explicit ZIndex
    -- (1/2/3/4) here broke real click completion on the buttons entirely (hover still fired,
    -- MouseButton1Click never did), while button.luau's interact - which relies purely on being
    -- the last-created sibling, no explicit ZIndex anywhere - has always clicked fine. Creation
    -- order alone (indicator, then childIndicator, then segmentsRow-with-the-actual-buttons last)
    -- reproduces that same reliable layering without whatever the explicit-ZIndex path breaks.
    self.indicator = window:Create("Frame", {
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.row,
    }, { BackgroundColor3 = "FieldGlow" })

    window:Create("UICorner", {
        Parent = self.indicator,
    }, { CornerRadius = "PillCornerRadius" })

    -- the dark inset pill marking the active child while a nested segment is expanded - sits on
    -- top of self.indicator's white (which, expanded, just stays at the whole segment's size and
    -- reads as that pair's shared background) with a few px of inset on every side so the white
    -- shows through as a thin ring around it, same as the reference. Shared across every nested
    -- segment since only one can ever be expanded at a time.
    self.childIndicator = window:Create("Frame", {
        BorderSizePixel = 0,
        BackgroundColor3 = childIndicatorColor,
        Visible = false,

        BackgroundTransparency = 1,

        Parent = self.row,
    })

    window:Create("UICorner", {
        Parent = self.childIndicator,
    }, { CornerRadius = "PillCornerRadius" })

    self.segmentsRow = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.row,
    })

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),

        Parent = self.segmentsRow,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.segmentsRow,
    })

    self.segments = {}
    for i, option in self.options do
        self.segments[i] = self:_buildSegment(option, i)
    end
end

-- One top-level slot: a plain button if it has no children, or a collapsed label + an expanded
-- row of child buttons (crossfaded, both occupying the same slot) if it does.
function SegmentedPicker:_buildSegment(option, index)
    local window = self.window

    -- Confirmed live with GetGuiObjectsAtPosition: this slot's AbsoluteSize was 213x0 - zero
    -- height, an unclickable sliver, while its child TextButton still rendered its text at
    -- full size regardless (Roblox doesn't clip text to a 0-height parent) - looked completely
    -- normal, wasn't clickable at all. HorizontalFlex.Fill only stretches the main (horizontal)
    -- axis; it never touches height, so a child with no Size of its own collapses to 0 on the
    -- cross axis. Explicit full-height Size fixes it - width is still overridden by Fill flex.
    local slot = window:Create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = index,

        Parent = self.segmentsRow,
    })

    local segment = { option = option, slot = slot, children = {} }

    if not option.options then
        segment.button = window:Create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            Text = locale.t(option.text),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 15,

            Parent = slot,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })

        window:ConnectFor(self, segment.button.MouseButton1Click, function()
            self:_pick(index, nil)
        end)

        return segment
    end

    -- which child this segment represents when collapsed - starts on the first one, remembered
    -- across collapsing/re-expanding and across switching to another top-level segment and back
    segment.activeChild = 1

    -- collapsed shows the active child's own name ("Monthly"), not option.text ("Premium") -
    -- there's no separate parent label at rest, just whichever child is currently picked
    segment.collapsedLabel = window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        Text = locale.t(self:_childText(index, 1)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,

        Parent = slot,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- selecting this segment (from the collapsed label, only ever shown/clickable while it
    -- isn't the active one) is what reveals its siblings - _render expands it automatically
    -- for as long as it stays the selected top-level segment
    window:ConnectFor(self, segment.collapsedLabel.MouseButton1Click, function()
        self:_pick(index, segment.activeChild)
    end)

    segment.expandedRow = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,

        Parent = slot,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = segment.expandedRow,
    })

    for j, child in option.options do
        local childText = if typeof(child) == "table" then child.text or child.Text else tostring(child)
        local childButton = window:Create("TextButton", {
            -- same fix as slot above: HorizontalFlex.Fill only stretches width, an explicit
            -- Size is still needed for height or this collapses to an unclickable 0
            Size = UDim2.new(0, 0, 1, 0),
            Text = locale.t(childText),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 15,
            LayoutOrder = j,

            Parent = segment.expandedRow,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })

        window:ConnectFor(self, childButton.MouseButton1Click, function()
            self:_pick(index, j)
        end)

        segment.children[j] = childButton
    end

    return segment
end

-- Where the outer (white) indicator belongs for a top-level segment: plain fraction-of-the-bar
-- math, since HorizontalFlex.Fill already guarantees every slot is exactly 1/count of the row -
-- nothing here needs to read anything back off an actual Instance to be correct. Always the full
-- segment width, expanded or not.
function SegmentedPicker:_indicatorGoal(index)
    local segmentScale = 1 / #self.options
    return UDim2.new((index - 1) * segmentScale, 0, 0, 0), UDim2.new(segmentScale, 0, 1, 0)
end

-- Where the inset childIndicator belongs: the same sub-fraction math as the old single-indicator
-- version used, but pulled in by childIndicatorInset on every side so the outer white shows
-- through as a thin ring around it.
function SegmentedPicker:_childIndicatorGoal(index, childIndex)
    local segmentScale = 1 / #self.options
    local childCount = #self.segments[index].option.options
    local childScale = segmentScale / childCount
    local x = (index - 1) * segmentScale + (childIndex - 1) * childScale

    local inset = childIndicatorInset
    return UDim2.new(x, inset, 0, inset), UDim2.new(childScale, -inset * 2, 1, -inset * 2)
end

-- No separate "expanded" toggle state anymore - a nested segment is expanded exactly when it's
-- the selected one, full stop. Selecting it (from anywhere else) is what reveals its siblings;
-- picking a specific child inside it changes which one's marked without collapsing anything;
-- only picking a genuinely different top-level segment collapses it back to its remembered
-- child's name. Matches the actual ask: click "Monthly", "Annual" appears and stays right there
-- until you pick "Free" again.
function SegmentedPicker:_select(index, childIndex, skipAnimation)
    self.selectedIndex, self.selectedChildIndex = index, childIndex
    self:_render(skipAnimation)
end

function SegmentedPicker:_render(skipAnimation)
    local index, childIndex = self.selectedIndex, self.selectedChildIndex

    for i, segment in self.segments do
        local active = i == index
        if segment.button then
            self.window:_reveal(segment.button, {
                TextColor3 = active and darkTextColor or self.window.theme.ContentColor,
            }, not skipAnimation, fadeInfo)
        else
            local expanded = active
            if expanded then
                segment.expandedRow.Visible = true
            end
            self.window:_reveal(segment.collapsedLabel, {
                TextTransparency = expanded and 1 or 0,
            }, not skipAnimation, fadeInfo)
            for j, childButton in segment.children do
                local childActive = expanded and childIndex == j
                -- expanded, the outer white indicator becomes this pair's shared background - an
                -- inactive child sits right on that white, so it needs dark text now; the active
                -- one sits on the dark childIndicator inset instead, so it flips to light
                self.window:_reveal(childButton, {
                    TextTransparency = expanded and 0 or 1,
                    TextColor3 = childActive and self.window.theme.ContentColor or darkTextColor,
                }, not skipAnimation, fadeInfo)
            end
            if not expanded then
                -- a generation token guards against collapsing then re-expanding the same
                -- segment within fadeInfo.Time, where this delayed hide would otherwise fire
                -- after the re-expand already turned Visible back on and yank it away again
                segment._collapseGen = (segment._collapseGen or 0) + 1
                local gen = segment._collapseGen
                task.delay(if skipAnimation then 0 else fadeInfo.Time, function()
                    if segment.expandedRow and segment._collapseGen == gen then
                        segment.expandedRow.Visible = false
                    end
                end)
            end
        end
    end

    -- the outer white indicator always sits at the whole top-level segment's size, expanded or
    -- not - expanded, that's exactly the shared white background the reference shows behind both
    -- children; the childIndicator (below) is what actually marks which one is picked
    local goalPosition, goalSize = self:_indicatorGoal(index)
    slideIndicator(self.indicator, goalPosition, goalSize, skipAnimation)

    local expandedSegment = index and self.segments[index]
    if expandedSegment and expandedSegment.option.options then
        local childPosition, childSize = self:_childIndicatorGoal(index, childIndex)
        -- going from hidden to shown, snap straight to the target instead of stretching - it was
        -- last positioned wherever it happened to be left (or its layout default, 0,0/0,0) and
        -- has no meaningful "old spot" to smear from yet
        local wasHidden = not self.childIndicator.Visible
        self.childIndicator.Visible = true
        if skipAnimation or wasHidden then
            self.childIndicator.Position, self.childIndicator.Size = childPosition, childSize
        else
            slideIndicator(self.childIndicator, childPosition, childSize, false)
        end
        self.window:_reveal(self.childIndicator, { BackgroundTransparency = 0 }, not skipAnimation, fadeInfo)
    elseif self.childIndicator.BackgroundTransparency == 0 then
        local tween = variables.tweenService:Create(self.childIndicator, fadeInfo, { BackgroundTransparency = 1 })
        tween:Play()
        -- :Once() isn't guaranteed on every client this session has run into (UIListLayout.Enabled
        -- not existing at all on one was the earlier surprise) - :Connect() + manual disconnect is
        -- the one form of "run this once" every client here has actually supported
        local connection
        connection = tween.Completed:Connect(function()
            connection:Disconnect()
            local stillCollapsed = not (self.segments[self.selectedIndex] or {}).option
                or not self.segments[self.selectedIndex].option.options
            if stillCollapsed then
                self.childIndicator.Visible = false
            end
        end)
    end
end

function SegmentedPicker:_pick(index, childIndex)
    local segment = self.segments[index]
    if segment.option.options and childIndex then
        segment.activeChild = childIndex
        segment.collapsedLabel.Text = locale.resolve(self:_childText(index, childIndex))
    end

    if self.selectedIndex == index and self.selectedChildIndex == childIndex then
        return
    end
    hapticEngine.click()
    self:_select(index, childIndex)

    local value = segment.option.text
    if childIndex and segment.option.options then
        value = self:_childText(index, childIndex)
    end
    self.value = value

    self.window:_runGuarded(self, self.callback, self.value)
    self.window:_persist(self)
end

-- Programmatic select, by a leaf's text (same value a callback receives).
function SegmentedPicker:Set(value, skipCallback)
    local index, childIndex = self:_find(value)
    if not index then
        return
    end
    self.value = value
    local segment = self.segments[index]
    if childIndex and segment.option.options then
        segment.activeChild = childIndex
        segment.collapsedLabel.Text = locale.resolve(self:_childText(index, childIndex))
    end
    self:_select(index, childIndex)

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self.value)
        self.window:_persist(self)
    end
end

function SegmentedPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_reveal(self.main, { BackgroundTransparency = 0.5 }, animate)
        w:_reveal(self.stroke, { Transparency = w.theme.ElementStrokeTransparency }, animate)
        w:_reveal(self.bar, { BackgroundTransparency = w.theme.ElementTransparency or 0 }, animate)
        w:_reveal(self.indicator, { BackgroundTransparency = 0 }, animate)
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 0.7 }, animate)
        end
    else
        w:_reveal(self.main, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.stroke, { Transparency = 1 }, animate)
        w:_reveal(self.bar, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.indicator, { BackgroundTransparency = 1 }, animate)
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 1 }, animate)
        end
    end
end

moveable(SegmentedPicker)

return SegmentedPicker

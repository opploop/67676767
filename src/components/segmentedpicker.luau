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

local slideInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local fadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local barHeight = 48
local activeTextColor = Color3.fromRGB(20, 20, 20)

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
    self:_select(index, childIndex, true)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    self.window:_restoreLate(self)

    return self
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

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, barHeight),
        BorderSizePixel = 0,
        Name = "SegmentedPicker",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    window:Create("UICorner", {
        Parent = self.main,
    }, { CornerRadius = "PillCornerRadius" })

    self.row = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    -- the sliding indicator - a free Frame with no layout of its own, so tweening its Position/
    -- Size directly never has anything to fight (see toggle.luau's knob, same idea)
    self.indicator = window:Create("Frame", {
        BorderSizePixel = 0,
        ZIndex = 1,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.row,
    }, { BackgroundColor3 = "FieldGlow" })

    window:Create("UICorner", {
        Parent = self.indicator,
    }, { CornerRadius = "PillCornerRadius" })

    self.segmentsRow = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,

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

    local slot = window:Create("Frame", {
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

    segment.collapsedLabel = window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        Text = locale.t(option.text),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,

        Parent = slot,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    window:ConnectFor(self, segment.collapsedLabel.MouseButton1Click, function()
        self:_pick(index, 1)
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

-- Where the indicator belongs for (index, childIndex): plain fraction-of-the-bar math, since
-- HorizontalFlex.Fill already guarantees every top-level slot (and every child within an
-- expanded one) is exactly 1/count of its row - nothing here needs to read anything back off
-- an actual Instance to be correct.
function SegmentedPicker:_indicatorGoal(index, childIndex)
    local count = #self.options
    local segmentScale = 1 / count
    local x, width = (index - 1) * segmentScale, segmentScale

    local segment = self.segments[index]
    if childIndex and segment.option.options then
        local childCount = #segment.option.options
        local childScale = segmentScale / childCount
        x += (childIndex - 1) * childScale
        width = childScale
    end

    return UDim2.new(x, 0, 0, 0), UDim2.new(width, 0, 1, 0)
end

function SegmentedPicker:_select(index, childIndex, skipAnimation)
    self.selectedIndex, self.selectedChildIndex = index, childIndex

    for i, segment in self.segments do
        local active = i == index
        if segment.button then
            self.window:_reveal(segment.button, {
                TextColor3 = active and activeTextColor or self.window.theme.ContentColor,
            }, not skipAnimation, fadeInfo)
        else
            local expanded = active
            if expanded then
                segment.expandedRow.Visible = true
            end
            self.window:_reveal(segment.collapsedLabel, { TextTransparency = expanded and 1 or 0 }, not skipAnimation, fadeInfo)
            for j, childButton in segment.children do
                local childActive = active and childIndex == j
                self.window:_reveal(childButton, {
                    TextTransparency = expanded and 0 or 1,
                    TextColor3 = childActive and activeTextColor or self.window.theme.ContentColor,
                }, not skipAnimation, fadeInfo)
            end
            if not expanded then
                -- a generation token, not just "this segment isn't the active one" (always true
                -- here) - guards against collapsing then re-expanding the same segment within
                -- fadeInfo.Time, where this delayed hide would otherwise fire after the re-select
                -- already turned Visible back on and yank it away again
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

    local goalPosition, goalSize = self:_indicatorGoal(index, childIndex)
    if skipAnimation then
        self.indicator.Position, self.indicator.Size = goalPosition, goalSize
    else
        variables.tweenService:Create(self.indicator, slideInfo, { Position = goalPosition, Size = goalSize }):Play()
    end
end

function SegmentedPicker:_pick(index, childIndex)
    if self.selectedIndex == index and self.selectedChildIndex == childIndex then
        return
    end
    hapticEngine.click()
    self:_select(index, childIndex)

    local leaf = self.segments[index].option
    local value = leaf.text
    if childIndex and leaf.options then
        local child = leaf.options[childIndex]
        value = if typeof(child) == "table" then child.text or child.Text else tostring(child)
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
    self:_select(index, childIndex)

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self.value)
        self.window:_persist(self)
    end
end

function SegmentedPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_reveal(self.stroke, { Transparency = w.theme.ElementStrokeTransparency }, animate)
        w:_reveal(self.main, { BackgroundTransparency = w.theme.ElementTransparency or 0 }, animate)
        w:_reveal(self.indicator, { BackgroundTransparency = 0 }, animate)
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 0.7 }, animate)
        end
    else
        w:_reveal(self.stroke, { Transparency = 1 }, animate)
        w:_reveal(self.main, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.indicator, { BackgroundTransparency = 1 }, animate)
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 1 }, animate)
        end
    end
end

moveable(SegmentedPicker)

return SegmentedPicker

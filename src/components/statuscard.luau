--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A compact, collapsible multi-row status widget - live "Currently Doing / Dungeon / Phase /
-- Room / Enemies" style readouts, one line per row, packed close together (label, a dim dot,
-- then the value) rather than spread across the card the way Stat's own single title+value
-- layout is. Stat is built for one headline number with a trend; this is for several small,
-- frequently-updated facts about what a script is doing right now (an auto-farm's live state),
-- which a single Stat card or the floating HUD (one line, no room for more than a couple of
-- readouts before it gets unreadable) don't fit well.
--
-- Fixed-width by design (not full tab width like every other element) - it's meant to read as a
-- self-contained widget, and fits inside a row Group next to other compact elements for exactly
-- that reason (see group.luau's own compactCapable table).

local StatusCard = {}
StatusCard.__index = StatusCard
StatusCard.__type = "StatusCard"

local utility = script.Parent.Parent.utility
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local constants = require(utility.constants)
local locale = require(utility.locale)
local log = require(utility.log)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

-- main's own UIPadding eats outerPad on every side - collapsed height is outerPad*2 +
-- headerRowHeight, NOT just one flat "header height" constant (that was the actual bug: an
-- arbitrary 30 that didn't leave room for the 14px padding above *and* below a 24px icon badge,
-- so the collapsed card came out shorter than its own header content and the icon visibly
-- poked out - live-caught, "quando fecha o icone fica pra fora").
local outerPad = 14
local headerRowHeight = 24 -- matches the icon badge's own height; title/chevron centre within it
local headerGap = 10 -- breathing room between the header and the first row, only present when expanded
local chevronInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local heightInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local function keyOf(row)
    return row.key or row.Key or row.label or row.Label
end

function StatusCard.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Status",
        icon = properties.icon or properties.Icon,
        width = properties.width or properties.Width or 260,
        collapsible = if properties.collapsible ~= nil
            then properties.collapsible
            elseif properties.Collapsible ~= nil then properties.Collapsible
            else true,
        glow = if properties.glow ~= nil then properties.glow elseif properties.Glow ~= nil then properties.Glow else true,
        expanded = if properties.expanded ~= nil
            then properties.expanded
            elseif properties.Expanded ~= nil then properties.Expanded
            else true,

        _rows = {}, -- ordered list of { key, label, value, muted, frame, labelLabel, valueLabel }
    }, StatusCard)

    if not self.collapsible then
        self.expanded = true
    end

    local window = self.window

    self.main = window:Create("Frame", {
        Name = self.name,
        Size = UDim2.fromOffset(self.width, outerPad * 2 + headerRowHeight),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Active = true, -- Devlog 7 fix - see Window:StyleElementBody's own comment on why

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundColor3 = "StatBackground", BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    if self.glow then
        self.shadow = window:CreateGlow(self.main, "AccentColor", 16, 1) -- In = 0.88
    end

    self.padding = window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, outerPad),
        PaddingRight = UDim.new(0, outerPad),
        PaddingTop = UDim.new(0, outerPad),
        PaddingBottom = UDim.new(0, outerPad),

        Parent = self.main,
    })

    -- Header: icon badge + title, chevron on the right if collapsible. Sized to headerRowHeight
    -- exactly (matches the icon badge's own 24px, the tallest thing in it) - main's own height
    -- accounts for this plus outerPad above *and* below explicitly (see _setHeight), so the
    -- collapsed card is never shorter than its own padding + header actually need.
    self.header = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, headerRowHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    self.titleContainer = window:Create("Frame", {
        Size = UDim2.new(1, -20, 1, 0), -- leaves room for the chevron on the right
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.header,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),

        Parent = self.titleContainer,
    })

    if self.icon then
        -- A small tinted chip rather than a bare glyph - reads as a deliberate badge instead of
        -- a plain icon floating next to text, the same "accent chip" language a premium widget
        -- like this calls for.
        self.iconBadge = window:Create("Frame", {
            Size = UDim2.fromOffset(24, 24),
            BorderSizePixel = 0,
            LayoutOrder = 0,

            BackgroundTransparency = 1, -- In = 0.85

            Parent = self.titleContainer,
        }, { BackgroundColor3 = "AccentColor" })
        window:Create("UICorner", {
            CornerRadius = UDim.new(0, 7),
            Parent = self.iconBadge,
        })
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(14, 14),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = 0

            Parent = self.iconBadge,
        }, { ImageColor3 = "AccentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.titleContainer,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    if self.collapsible then
        self.chevron = window:Create("ImageLabel", {
            Image = constants.icons.chevron,
            Size = UDim2.fromOffset(12, 12),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Rotation = if self.expanded then 0 else 180,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = 0.4

            Parent = self.header,
        }, { ImageColor3 = "ContentColor" })

        self.headerInteract = window:Create("TextButton", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "",

            Parent = self.header,
        })
        window:Connect(self.headerInteract.MouseButton1Click, function()
            hapticEngine.click()
            soundEngine.click()
            self:Toggle()
        end)
    end

    -- Content: clips so the collapse never shows a half-cut row, height tweens between 0 and
    -- rowsContainer's own real AbsoluteSize.Y - same shape collapsible.luau's own contentWrapper
    -- uses, for the same reason (see _setHeight below).
    self.contentWrapper = window:Create("Frame", {
        Position = UDim2.fromOffset(0, headerRowHeight),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,

        Parent = self.main,
    })

    -- headerGap lives *inside* the clipped wrapper (not as a fixed offset outside it) so it
    -- collapses away to nothing along with the rows when hidden, instead of leaving a bare gap
    -- floating under the header with nothing below it.
    self.rowsContainer = window:Create("Frame", {
        Position = UDim2.fromOffset(0, headerGap),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.contentWrapper,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 6),

        Parent = self.rowsContainer,
    })

    local initialRows = properties.rows or properties.Rows or {}
    for _, row in initialRows do
        self:_buildRow(row)
    end

    if self.expanded then
        self:_setHeight(self:_contentHeight(), false)
    end

    window:ConnectFor(self, self.rowsContainer:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.expanded then
            self:_setHeight(self:_contentHeight(), true)
        end
    end)

    return self
end

-- contentWrapper's own target height when expanded: the gap down to the first row, plus every
-- row stacked (rowsContainer's real AbsoluteSize.Y already accounts for the rows' own padding).
function StatusCard:_contentHeight()
    return headerGap + self.rowsContainer.AbsoluteSize.Y
end

-- Drives contentWrapper's height AND main's own height together, exactly like Collapsible's own
-- _setHeight - confirmed live on this executor that AutomaticSize.Y on a parent doesn't reliably
-- follow a *tweened* child Size change, so main's height is driven explicitly here instead of
-- left on AutomaticSize. main's own height is outerPad on both sides of the header, PLUS
-- contentWrapper's current height - forgetting the padding here is exactly what made the
-- collapsed card shorter than its own header content (see outerPad's own comment above).
function StatusCard:_setHeight(targetContentHeight, animate)
    local contentSize = UDim2.new(1, 0, 0, targetContentHeight)
    local mainSize = UDim2.fromOffset(self.width, outerPad * 2 + headerRowHeight + targetContentHeight)
    if animate then
        variables.tweenService:Create(self.contentWrapper, heightInfo, { Size = contentSize }):Play()
        variables.tweenService:Create(self.main, heightInfo, { Size = mainSize }):Play()
    else
        self.contentWrapper.Size = contentSize
        self.main.Size = mainSize
    end
end

function StatusCard:_buildRow(row)
    local window = self.window
    local key = keyOf(row)
    if not key then
        log.warn("Rayfield: a StatusCard row needs a `label` (or explicit `key`), skipping one on '" .. self.name .. "'.")
        return
    end

    local frame = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        -- Roblox's real default SortOrder is Name (alphabetical), not LayoutOrder - rowsContainer's
        -- own UIListLayout sets SortOrder = LayoutOrder explicitly (see its own Create call
        -- below) specifically so this actually controls order instead of silently being ignored.
        LayoutOrder = #self._rows + 1,

        Parent = self.rowsContainer,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 5),

        Parent = frame,
    })

    local labelLabel = window:Create("TextLabel", {
        Text = locale.t(row.label or row.Label or key),
        Size = UDim2.fromOffset(0, 14),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 0.45, -- a fixed dim, not theme-tweened - a label is never the accent
        LayoutOrder = 0,

        Parent = frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    local dotLabel = window:Create("TextLabel", {
        Text = "\194\183", -- middle dot "·" (U+00B7)
        Size = UDim2.fromOffset(6, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextTransparency = 0.6,
        LayoutOrder = 1,

        Parent = frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    local valueLabel = window:Create("TextLabel", {
        Text = tostring(row.value or row.Value or ""),
        Size = UDim2.fromOffset(0, 14),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        FontFace = variables.brandFont(Enum.FontWeight.SemiBold),
        LayoutOrder = 2,

        Parent = frame,
    })
    self:_paintValue(valueLabel, row.muted or row.Muted or false)

    if not self.window.hidden then
        window:_reveal(labelLabel, { TextTransparency = 0.45 }, true)
        window:_reveal(dotLabel, { TextTransparency = 0.6 }, true)
        window:_reveal(valueLabel, { TextTransparency = 0 }, true)
    else
        labelLabel.TextTransparency = 0.45
        dotLabel.TextTransparency = 0.6
        valueLabel.TextTransparency = 0
    end

    table.insert(self._rows, {
        key = key,
        frame = frame,
        labelLabel = labelLabel,
        dotLabel = dotLabel,
        valueLabel = valueLabel,
        muted = row.muted or row.Muted or false,
    })
end

-- muted (e.g. "none"/"0"/an inactive readout) reads as a plain, unremarkable value; anything
-- else rides the live theme accent so a glance at the card tells you which lines actually matter
-- right now, the same "colour carries meaning" idea Stat's own accent follows.
function StatusCard:_paintValue(valueLabel, muted)
    if muted then
        valueLabel.TextColor3 = self.window.theme.PlaceholderColor
    else
        valueLabel.TextColor3 = self.window.theme.AccentColor
    end
end

function StatusCard:_findRow(key)
    for _, entry in self._rows do
        if entry.key == key then
            return entry
        end
    end
    return nil
end

-- Update one row's value (and optionally whether it reads as muted) by key. No-ops quietly on an
-- unknown key rather than throwing - a live readout calling this every tick shouldn't need to
-- guard against a key that hasn't been added yet.
function StatusCard:SetRow(key, value, muted)
    local entry = self:_findRow(key)
    if not entry then
        return
    end
    entry.valueLabel.Text = tostring(value)
    if muted ~= nil then
        entry.muted = muted
        self:_paintValue(entry.valueLabel, muted)
    end
end

-- Appends a new row (or inserts at `index`, matching MoveTo's own 1-based indexing) after
-- construction - a script whose readouts aren't all known up front (an auto-farm that only shows
-- "Chests ready" once it's actually found one, say) can grow the card instead of pre-declaring
-- every possible row hidden. Doesn't call _setHeight itself - adding/removing a row always
-- changes rowsContainer's own AbsoluteSize, and the constructor's own
-- GetPropertyChangedSignal("AbsoluteSize") listener already reacts to that; calling _setHeight
-- again here raced that same listener's own call (both landing a tween on the same instance
-- within the same frame, one interrupting the other) - live-caught as the card settling at the
-- wrong height after Add/Remove.
function StatusCard:AddRow(row, index)
    self:_buildRow(row)
    if index then
        local entry = self._rows[#self._rows]
        table.remove(self._rows, #self._rows)
        table.insert(self._rows, math.clamp(index, 1, #self._rows + 1), entry)
        -- re-sync every row's LayoutOrder to its new position - same reason _buildRow assigns
        -- one at all instead of leaving the Roblox default (see its own comment).
        for i, e in self._rows do
            e.frame.LayoutOrder = i
        end
    end
end

function StatusCard:RemoveRow(key)
    for i, entry in self._rows do
        if entry.key == key then
            self.window:DestroySubtree(entry.frame)
            table.remove(self._rows, i)
            return
        end
    end
end

-- Bulk replace: clears every existing row and rebuilds from `rows`, for a script that's easier
-- to write as "here's the whole current state" each update rather than a stream of SetRow calls.
-- Same "don't also call _setHeight here" reasoning as AddRow/RemoveRow above - the constructor's
-- own AbsoluteSize-changed listener reacts to the row-count change on its own. The one edge case
-- this leaves uncovered - a Set() whose new rows net the exact same total height as the old ones
-- (e.g. clearing to zero rows when there already were none) - never actually needs a resize
-- either, since nothing about the real height changed.
function StatusCard:Set(rows)
    for _, entry in self._rows do
        self.window:DestroySubtree(entry.frame)
    end
    table.clear(self._rows)
    for _, row in rows or {} do
        self:_buildRow(row)
    end
end

function StatusCard:SetExpanded(expanded)
    if not self.collapsible then
        return
    end
    expanded = expanded and true or false
    if expanded == self.expanded then
        return
    end
    self.expanded = expanded

    self:_setHeight(if expanded then self:_contentHeight() else 0, true)
    if self.chevron then
        variables.tweenService:Create(self.chevron, chevronInfo, { Rotation = if expanded then 0 else 180 }):Play()
    end
end

function StatusCard:Toggle()
    self:SetExpanded(not self.expanded)
end

function StatusCard:_minWidth()
    return self.width
end

function StatusCard:_setShown(shown, animate)
    local w = self.window
    w:_reveal(self.main, { BackgroundTransparency = if shown then (w.theme.ElementTransparency or 0) else 1 }, animate)
    w:_reveal(self.stroke, { Transparency = if shown then w.theme.ElementStrokeTransparency else 1 }, animate)
    if self.shadow then
        w:_reveal(self.shadow, { Transparency = if shown then 0.88 else 1 }, animate)
    end
    if self.iconBadge then
        w:_reveal(self.iconBadge, { BackgroundTransparency = if shown then 0.85 else 1 }, animate)
    end
    if self.iconLabel then
        w:_reveal(self.iconLabel, { ImageTransparency = if shown then 0 else 1 }, animate)
    end
    w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
    if self.chevron then
        w:_reveal(self.chevron, { ImageTransparency = if shown then 0.4 else 1 }, animate)
    end
    for _, entry in self._rows do
        w:_reveal(entry.labelLabel, { TextTransparency = if shown then 0.45 else 1 }, animate)
        w:_reveal(entry.dotLabel, { TextTransparency = if shown then 0.6 else 1 }, animate)
        w:_reveal(entry.valueLabel, { TextTransparency = if shown then 0 else 1 }, animate)
    end
end

-- Row values' TextColor3 is a plain assignment (AccentColor vs PlaceholderColor depends on each
-- row's own `muted` flag, which a single themeProperty binding can't express), so a live
-- Settings > Color theme swap needs telling explicitly here - everything else on the card
-- (ContentColor labels, the AccentColor icon badge/glow) already rides a themeProperty binding
-- and refreshes itself through the normal ChangeTheme loop.
function StatusCard:_refreshTheme()
    for _, entry in self._rows do
        self:_paintValue(entry.valueLabel, entry.muted)
    end
end

moveable(StatusCard)

return StatusCard

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 6: an inline "Update Log" card - a title + version/date header, a divider, then a list
-- of entries each tagged ADDED/FIXED/CHANGED/REMOVED (or any custom tag) in a semantic colour.
-- Static once built (no add/remove API) - it's meant to be authored once per release, the same
-- way the devlog text itself is.

local Changelog = {}
Changelog.__index = Changelog
Changelog.__type = "Changelog"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local moveable = require(utility.moveable)
local locale = require(utility.locale)

-- Semantic tag colours, git-status-log convention: green add, blue fix, amber change, red remove.
-- Kept soft/pastel on purpose - the original fully-saturated set read as neon against the card.
-- A custom tag not in this table falls back to the theme's own accent colour.
local tagColors = {
    ADDED = Color3.fromRGB(125, 209, 155),
    FIXED = Color3.fromRGB(130, 179, 235),
    CHANGED = Color3.fromRGB(230, 178, 110),
    REMOVED = Color3.fromRGB(224, 130, 128),
}

local rowGap = 10
local entryGap = 14
local prefixWidth = 80
local dotSize = 6

function Changelog.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Update Log",
        version = properties.version or properties.Version,
        date = properties.date or properties.Date,
        entries = properties.entries or properties.Entries or {},
    }, Changelog)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)

    self.window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 20),
        PaddingRight = UDim.new(0, 20),
        PaddingTop = UDim.new(0, 16),
        PaddingBottom = UDim.new(0, 16),

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, rowGap),

        Parent = self.main,
    })

    self:_buildHeader()
    self:_buildDivider()
    self._rows = {}
    for index, entry in self.entries do
        self:_buildEntry(entry, index)
    end

    return self
end

function Changelog:_buildHeader()
    local header = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 1,

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,

        Parent = header,
    })

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 1, -- In = 0

        Parent = header,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    if (self.version and self.version ~= "") or (self.date and self.date ~= "") then
        local parts = {}
        if self.version and self.version ~= "" then
            table.insert(parts, self.version)
        end
        if self.date and self.date ~= "" then
            table.insert(parts, self.date)
        end
        self.meta = self.window:Create("TextLabel", {
            Text = locale.t(table.concat(parts, "  \u{00B7}  ")),
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Right,

            TextTransparency = 1, -- In = 0.5

            Parent = header,
        }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })
    end
end

function Changelog:_buildDivider()
    self.divider = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        LayoutOrder = 2,

        BackgroundTransparency = 1, -- In = 0.9

        Parent = self.main,
    }, { BackgroundColor3 = "SurfaceStroke" })
end

-- One row: a fixed-width colour tag left, the description filling the rest. Wraps onto its own
-- height if the description needs more than one line.
function Changelog:_buildEntry(entry, order)
    entry = if typeof(entry) == "table" then entry else { text = tostring(entry) }
    local tag = string.upper(tostring(entry.tag or entry.Tag or ""))
    local color = tagColors[tag] or self.window.theme.AccentColor
    local text = entry.text or entry.Text or entry.description or entry.Description or ""

    local row = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2 + order,

        Parent = self.main,
    })

    -- fixed-width prefix so every row's description starts at the same x regardless of how
    -- long its own tag word is - dot + tag flow left inside it via their own mini row
    local prefix = self.window:Create("Frame", {
        Size = UDim2.fromOffset(prefixWidth, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = row,
    })

    self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),

        Parent = prefix,
    })

    local dot = self.window:Create("Frame", {
        Size = UDim2.fromOffset(dotSize, dotSize),
        BackgroundColor3 = color,
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = 0

        Parent = prefix,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })

    local tagLabel = self.window:Create("TextLabel", {
        Text = locale.t(tag),
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = color,

        TextTransparency = 1, -- In = 0

        Parent = prefix,
    })

    local desc = self.window:Create("TextLabel", {
        Text = locale.t(text),
        Position = UDim2.fromOffset(prefixWidth + entryGap, 0),
        Size = UDim2.new(1, -(prefixWidth + entryGap), 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,

        TextTransparency = 1, -- In = 0

        Parent = row,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    table.insert(self._rows, { row = row, dot = dot, tagLabel = tagLabel, desc = desc })
end

function Changelog:_setShown(shown, animate)
    local w = self.window
    w:_reveal(self.stroke, { Transparency = if shown then w.theme.ElementStrokeTransparency else 1 }, animate)
    w:_reveal(self.main, { BackgroundTransparency = if shown then (w.theme.ElementTransparency or 0) else 1 }, animate)
    w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
    if self.meta then
        w:_reveal(self.meta, { TextTransparency = if shown then 0.5 else 1 }, animate)
    end
    w:_reveal(self.divider, { BackgroundTransparency = if shown then 0.9 else 1 }, animate)
    for _, entry in self._rows do
        w:_reveal(entry.dot, { BackgroundTransparency = if shown then 0 else 1 }, animate)
        w:_reveal(entry.tagLabel, { TextTransparency = if shown then 0 else 1 }, animate)
        w:_reveal(entry.desc, { TextTransparency = if shown then 0 else 1 }, animate)
    end
end

moveable(Changelog)

return Changelog

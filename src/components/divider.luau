--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 10 "Divider": a subtle horizontal rule that splits a page into groups without the
-- weight of a full Section header. Three shapes:
--   1. Plain line spanning the row.
--   2. Line with a centred caption, the line broken into two independently-flexed halves either
--      side of it (see the row's UIListLayout below) so it stays balanced regardless of how long
--      or short the caption is - a short word like "Tight" leaves long stretches of line either
--      side, not a fixed even split.
--   3. "Spacing only": no visible line at all, just a fixed-height gap - line = false.
-- Vertical padding around the line comes from a named spacing preset (tight/normal/loose)
-- rather than a raw pixel prop, so it reads the same way across every divider in a page.

local Divider = {}
Divider.__index = Divider
Divider.__type = "Divider"

local utility = script.Parent.Parent.utility
local moveable = require(utility.moveable)
local locale = require(utility.locale)

-- Live-caught too roomy at "normal" (14/14) - read as a much bigger gap than the reference
-- around a captioned line. Tightened across the board; loose still stays clearly the most open
-- of the three, just from a smaller base.
local spacingPresets = {
    tight = { top = 4, bottom = 4 },
    normal = { top = 8, bottom = 8 },
    loose = { top = 18, bottom = 18 },
}

local defaultSpacerHeight = 24

function Divider.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local text = properties.text or properties.Text or ""
    local showLine = if properties.line ~= nil
        then properties.line
        elseif properties.Line ~= nil then properties.Line
        else true
    local spacingKey = string.lower(properties.spacing or properties.Spacing or "normal")
    local preset = spacingPresets[spacingKey] or spacingPresets.normal
    local spacerHeight = properties.height or properties.Height or defaultSpacerHeight

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        line = showLine,
    }, Divider)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Name = "Divider",

        Parent = self.tab.tabPage,
    })

    if not showLine then
        -- Spacing-only: just a fixed-height invisible gap, no row/line/title to build or reveal.
        self.window:Create("Frame", {
            Size = UDim2.fromOffset(0, spacerHeight),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            Parent = self.main,
        })

        return self
    end

    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, preset.top),
        PaddingBottom = UDim.new(0, preset.bottom),

        Parent = self.main,
    })

    self.row = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    self.rowLayout = self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, if text ~= "" then 8 else 0),
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.row,
    })

    local function buildLineHalf(layoutOrder)
        local half = self.window:Create("Frame", {
            Size = UDim2.fromOffset(0, 1),
            BorderSizePixel = 0,
            LayoutOrder = layoutOrder,

            -- Animation
            BackgroundTransparency = 1, -- In = 0.88

            Parent = self.row,
        }, { BackgroundColor3 = "SurfaceStroke" })

        -- Opts this half into the row's Fill flex - the other non-flexed child (the title, when
        -- there is one) keeps its own natural width, so the two halves split whatever's left
        -- over evenly instead of the row forcing three equal thirds.
        self.window:Create("UIFlexItem", {
            FlexMode = Enum.UIFlexMode.Fill,
            Parent = half,
        })

        return half
    end

    self.leftLine = buildLineHalf(0)
    self.rightLine = buildLineHalf(2)

    if text ~= "" then
        self:_buildTitle(text)
    end

    return self
end

-- Built lazily - either at construction (if the divider started with a caption) or the first
-- time Set() gives a blank divider one. LayoutOrder 1 sits it between the two line halves.
function Divider:_buildTitle(text)
    self.title = self.window:Create("TextLabel", {
        Text = locale.t(text),

        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 1,

        -- Animation
        TextTransparency = 1, -- In = 0.5

        Parent = self.row,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })
end

-- Swap (or add/remove) the centred caption without breaking the line's alignment - the row's
-- Padding just collapses to 0 when there's no caption, so the two halves meet in the middle as
-- one continuous line instead of leaving a gap where the title used to be.
function Divider:Set(text)
    text = text or ""
    if not self.row then
        return -- spacing-only divider has no line/title to update
    end

    if text == "" then
        if self.title then
            self.title.Visible = false
        end
        self.rowLayout.Padding = UDim.new(0, 0)
        return
    end

    if not self.title then
        self:_buildTitle(text)
        if not self.window.hidden then
            self.window:_reveal(self.title, { TextTransparency = 0.5 }, false)
        end
    else
        self.title.Visible = true
        -- Direct assignment, not locale.t() - that returns a wrapper table meant for Window:
        -- Create's own property loop (which unwraps it via _bindLocale) and would fail if
        -- assigned straight onto Text like this. Every other element's dynamic Set() has the
        -- same rule (see Tag:SetText) - only the construction-time value round-trips through
        -- translation.
        self.title.Text = text
    end
    self.rowLayout.Padding = UDim.new(0, 10)
end

function Divider:_setShown(shown, animate)
    local w = self.window
    if self.leftLine then
        w:_reveal(self.leftLine, { BackgroundTransparency = if shown then 0.88 else 1 }, animate)
        w:_reveal(self.rightLine, { BackgroundTransparency = if shown then 0.88 else 1 }, animate)
    end
    if self.title then
        w:_reveal(self.title, { TextTransparency = if shown then 0.5 else 1 }, animate)
    end
end

moveable(Divider)

return Divider

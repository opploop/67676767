--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 9 "Paragraph": a styled card for copy too long to hang off an element as a description
-- (that's Descriptor, only ever built internally by another element's own `description`
-- property) - longform notices, docs, changelog-adjacent writeups. Title and body are
-- independently optional; whichever one's empty just isn't shown in the card's own UIListLayout
-- (Visible = false skips it entirely), and AutomaticSize.Y reflows the card's height around
-- whatever's left - so passing just a body (or just a title) never leaves a blank line where the
-- other would've been.

local Paragraph = {}
Paragraph.__index = Paragraph
Paragraph.__type = "Paragraph"

local utility = script.Parent.Parent.utility
local moveable = require(utility.moveable)
local locale = require(utility.locale)

function Paragraph.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local titleText = properties.title or properties.Title or ""
    local contentText = properties.content or properties.Content or ""

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        icon = properties.icon or properties.Icon,
    }, Paragraph)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Name = "Paragraph",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        -- Devlog 7 fix: stays clickable/hoverable even at ElementTransparency 1 (a fully "glass"
        -- window) - every card-shaped element needs this directly, see StyleElementBody's own
        -- comment for why it isn't handled there instead.
        Active = true,

        -- Animation
        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)

    self.window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 18),
        PaddingRight = UDim.new(0, 18),
        PaddingTop = UDim.new(0, 16),
        PaddingBottom = UDim.new(0, 16),

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),

        Parent = self.main,
    })

    -- Header: icon (optional) + title, same layout section.luau uses. A Frame of its own
    -- (rather than parenting icon/title straight to main) so hiding an empty title also hides
    -- the icon beside it for free, and the card's own UIListLayout skips the whole row in one go.
    self.headerRow = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        Visible = titleText ~= "",

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,

        Parent = self.headerRow,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            LayoutOrder = 0,

            -- Animation
            ImageTransparency = 1, -- In = 0

            Parent = self.headerRow,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(titleText),

        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,

        -- Animation
        TextTransparency = 1, -- In = 0

        Parent = self.headerRow,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    self.body = self.window:Create("TextLabel", {
        Text = locale.t(contentText),

        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        LayoutOrder = 1,
        Visible = contentText ~= "",

        -- Animation
        TextTransparency = 1, -- In = 0.3

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    return self
end

function Paragraph:SetTitle(text)
    text = text or ""
    self.headerRow.Visible = text ~= ""
    self.title.Text = text
end

function Paragraph:SetContent(text)
    text = text or ""
    self.body.Visible = text ~= ""
    self.body.Text = text
end

-- Accepts either key casing, same as every other CreateX properties table. Updates whichever
-- half is present - Set({ Content = "..." }) alone leaves the title untouched.
function Paragraph:Set(properties)
    properties = if typeof(properties) == "table" then properties else {}
    local title = properties.title or properties.Title
    local content = properties.content or properties.Content
    if title ~= nil then
        self:SetTitle(title)
    end
    if content ~= nil then
        self:SetContent(content)
    end
end

function Paragraph:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.body, { TextTransparency = 0.3 }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.body, { TextTransparency = 1 }, animate)
    end
end

moveable(Paragraph)

return Paragraph

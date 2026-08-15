--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 9 "Label": a bare line of text on the page, no card behind it - for copy that doesn't
-- belong hanging off a button/toggle as a description (that's Descriptor, only ever built
-- internally by another element's own `description` property) but also isn't substantial enough
-- to earn its own Paragraph card (see paragraph.luau). Wraps onto further lines on its own as the
-- window narrows, same as every other element's text - explicit width math (the row's own width
-- minus the icon's, if there is one) rather than UIListLayout + UIFlexItem, which only reliably
-- grows/shrinks a sibling's width, not wraps text inside it.

local Label = {}
Label.__index = Label
Label.__type = "Label"

local moveable = require(script.Parent.Parent.utility.moveable)
local locale = require(script.Parent.Parent.utility.locale)

local iconSize = 16
local iconGap = 8

function Label.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local text = properties.text or properties.Text or ""

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        icon = properties.icon or properties.Icon,
    }, Label)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.tab.tabPage,
    })

    local titleInset = if self.icon then iconSize + iconGap else 0

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(iconSize, iconSize),
            Position = UDim2.fromOffset(0, 1), -- nudged down a hair to sit on the first line's baseline
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            -- Animation
            ImageTransparency = 1, -- In = 0

            Parent = self.main,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(text),

        Position = UDim2.fromOffset(titleInset, 0),
        Size = UDim2.new(1, -titleInset, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,

        -- Animation
        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    return self
end

-- Swap the copy - main's AutomaticSize.Y reflows the row to the new height on its own, no
-- manual height math needed.
function Label:Set(text)
    self.title.Text = text or ""
end

function Label:_setShown(shown, animate)
    local w = self.window
    w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
    if self.iconLabel then
        w:_reveal(self.iconLabel, { ImageTransparency = if shown then 0 else 1 }, animate)
    end
end

moveable(Label)

return Label

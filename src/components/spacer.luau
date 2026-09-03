--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 7: an invisible gap with a configurable height, for custom breathing room between
-- elements/sections beyond whatever the tab page's own UIListLayout gap already gives.

local Spacer = {}
Spacer.__index = Spacer
Spacer.__type = "Spacer"

local utility = script.Parent.Parent.utility
local variables = require(utility.variables)
local moveable = require(utility.moveable)

local heightInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

function Spacer.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = "Spacer",
        height = properties.height or properties.Height or 12,
    }, Spacer)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, self.height),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Name = self.name,

        Parent = self.tab.tabPage,
    })

    return self
end

-- Nothing to fade in/out - a spacer has no visual content of its own. Still needs the method:
-- Tab:_register's reveal pass, and a runtime SetVisible, both call it unconditionally.
function Spacer:_setShown(shown, animate) end

-- Changes the gap's height, tweened by default (pass animate = false to snap instantly).
function Spacer:SetHeight(height, animate)
    self.height = height
    local target = UDim2.new(1, -20, 0, height)
    if animate == false then
        self.main.Size = target
    else
        variables.tweenService:Create(self.main, heightInfo, { Size = target }):Play()
    end
end

moveable(Spacer)

return Spacer

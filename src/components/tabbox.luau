--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Nested tab switcher, usable inside a Tab or a Group - Fluent's own :AddTabbox(). Built for a
-- section with many parallel, similarly-shaped categories (a hub's own "Auto Farm Mob A/B/C",
-- say) where a flat list would just be one long scroll with no way to jump between categories.
--
-- Each page is a real Group instance (Vertical direction), built against a small fake "host"
-- table shaped like the Tab fields Group.new itself already reads (window/tabPage/direction/
-- forgetState - see group.luau's own header comment on this exact contract) - reuses every
-- CreateToggle/CreateButton/etc a page needs for free rather than reimplementing that machinery
-- a second time. Page switching is a plain Visible toggle (this is a small nested control, not
-- the window's own cross-fading UIPageLayout tab system - no reveal animation needed here).

local Tabbox = {}
Tabbox.__index = Tabbox
Tabbox.__type = "Tabbox"

local utility = script.Parent.Parent.utility
local assignOrder = require(utility.ordering)

local pillHeight = 26
local pillPadding = 4

function Tabbox.new(host, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        host = assert(host, "Missing argument #1 (Tab or Group expected)"),
        window = host.window,
        forgetState = host.forgetState,
        pages = {},
        selectedIndex = nil,
    }, Tabbox)

    local window = self.window

    self.main = window:Create("Frame", {
        Name = properties.name or properties.Name or "Tabbox",
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = host.tabPage,
    })

    -- children of a Group-hosted Tabbox share the row's flex the same way a nested Group does
    if host.direction == Enum.FillDirection.Horizontal then
        window:Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = self.main })
    end

    self.pillRow = window:Create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, pillHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        LayoutOrder = 1,

        Parent = self.main,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, pillPadding),

        Parent = self.pillRow,
    })

    self.pageContainer = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2,

        Parent = self.main,
    })

    window:Create("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        Parent = self.pageContainer,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = self.main,
    })

    return self
end

function Tabbox:_selectIndex(index)
    if self.selectedIndex == index then
        return
    end
    self.selectedIndex = index
    for i, page in self.pages do
        local selected = i == index
        page.frame.Visible = selected
        local pill = page.pill
        pill.BackgroundColor3 = self.window.theme.AccentColor
        pill.BackgroundTransparency = if selected then 0.1 else 0.85
        pill.TextTransparency = if selected then 0 else 0.4
    end
end

-- One tab: a pill in the row + a page Group (direction "column") built against a fake Tab/Group
-- host so it gets every CreateX call for free. Returns the page (a real Group) directly - a dev
-- calls :CreateToggle/:CreateButton/etc on it exactly like any other Group.
function Tabbox:CreateTab(properties)
    properties = if typeof(properties) == "table" then properties else {}
    local name = properties.name or properties.Name or ("Tab " .. (#self.pages + 1))

    local pill = self.window:Create("TextButton", {
        Text = name,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, pillHeight),
        BorderSizePixel = 0,
        TextSize = 13,
        Active = true,

        Parent = self.pillRow,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = pill,
    })
    self.window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = pill,
    })

    local pageFrame = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,

        Parent = self.pageContainer,
    })
    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = pageFrame,
    })

    -- fake host: exactly the fields Group.new itself reads off a Tab (see its own header
    -- comment) - window/tabPage/direction/forgetState. Vertical direction, same as any ordinary
    -- full-width column, so every element type builds normally inside a page.
    local fakeHost = {
        window = self.window,
        tabPage = pageFrame,
        direction = Enum.FillDirection.Vertical,
        forgetState = self.forgetState,
    }
    local page = require(script.Parent.group).new(fakeHost, { direction = "column" })
    page.frame = pageFrame
    page.pill = pill

    local index = #self.pages + 1
    table.insert(self.pages, page)
    assignOrder(page, index * 10)
    pill.LayoutOrder = index * 10

    self.window:Connect(pill.MouseButton1Click, function()
        self:_selectIndex(index)
    end)

    if index == 1 then
        self:_selectIndex(1)
    else
        pill.BackgroundColor3 = self.window.theme.AccentColor
        pill.BackgroundTransparency = 0.85
        pill.TextTransparency = 0.4
    end

    return page
end

-- forwards reveal/theme calls the same shape Group itself uses, so a Tabbox nested inside
-- another Group's reveal/theme pass reaches every page (and everything inside it)
function Tabbox:_setShown(shown, animate)
    for _, page in self.pages do
        page:_setShown(shown, animate)
    end
end

function Tabbox:_refreshTheme()
    for _, page in self.pages do
        if page._refreshTheme then
            page:_refreshTheme()
        end
    end
end

return Tabbox

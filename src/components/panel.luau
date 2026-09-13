--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A card with pages, where the header says which page you are on and offers the others. The shape
-- a hub uses for one feature and its settings: a "Trial" view with the status, a difficulty and
-- the auto toggle, and a "Config" view one click away with everything that tunes it - instead of
-- every knob stacked in one long column.
--
-- The header's left side is the CURRENT page (its icon and name); the right side is a pill for
-- every OTHER page. Clicking a pill makes that page current, so on a two-page panel the header
-- simply flips between "Trial  [··· Config]" and "Config  [Trial]". That reads as "where you are"
-- plus "where you can go", which a row of equal pills (Tabbox's shape) does not.
--
-- Tabbox is the sibling for many parallel categories; this is for a feature and its few views.
-- Each page is a real column Group, built against a small fake host exactly like Tabbox's pages
-- (see tabbox.luau), so every CreateX works inside a page for free.
--
-- Heights are written here rather than left to AutomaticSize, same as Collapsible and ItemGrid:
-- the card is the header plus the CURRENT page's real height, and it follows that page as its
-- contents grow.

local Panel = {}
Panel.__index = Panel
Panel.__type = "Panel"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local assignOrder = require(utility.ordering)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local sidePadding = 15
local headerTop = 12
local headerHeight = 26
local headerGap = 8
local bottomPadding = 10
local iconSize = 16

local pillHeight = 24
local pillPadX = 10
local pillIconSize = 14
local pillIconGap = 5
local pillGap = 6
local pillTextSize = 13
local pillCorner = 8

local titleTextSize = 16

local hoverInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local pillRestText = 0.35
local pillHoverText = 0.05
local pillRestIcon = 0.4
local pillHoverIcon = 0.1

function Panel.new(host, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(host, "Missing argument #1 (Tab or Group expected)"),
        window = host.window,
        name = properties.name or properties.Name or "Panel",
        forgetState = host.forgetState,
        onPageChanged = properties.onPageChanged or properties.OnPageChanged,

        pages = {},
        selectedIndex = nil,
    }, Panel)

    local window = self.window

    self.main = window:Create("Frame", {
        Name = self.name,
        Size = UDim2.new(1, -20, 0, headerTop + headerHeight + bottomPadding),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = containerTransparency(ElementTransparency)

        Parent = host.tabPage,
    }, { BackgroundTransparency = { "ElementTransparency", functions.containerTransparency } })

    -- a Panel in a row shares the row's flex the way a nested Group does
    if host.direction == Enum.FillDirection.Horizontal then
        window:Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = self.main })
    end

    self.stroke = window:StyleElementBody(self.main)

    -- the current page's icon: only shown when that page has one
    self.iconLabel = window:Create("ImageLabel", {
        Size = UDim2.fromOffset(iconSize, iconSize),
        Position = UDim2.fromOffset(sidePadding, headerTop + (headerHeight - iconSize) / 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,

        ImageTransparency = 1, -- In = 0

        Parent = self.main,
    }, { ImageColor3 = "ContentColor" })

    self.title = window:Create("TextLabel", {
        Text = "",
        Size = UDim2.new(1, -(sidePadding * 2), 0, headerHeight),
        Position = UDim2.fromOffset(sidePadding, headerTop),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = titleTextSize,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,

        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.pageContainer = window:Create("Frame", {
        Name = "Pages",
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, headerTop + headerHeight + headerGap),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    return self
end

-- The visible width of a pill, measured rather than left to AutomaticSize: the header lays the
-- pills out from the right edge and the title needs to know how much room they leave it.
function Panel:_pillWidth(page): number
    local textWidth = functions.textWidth(self.window.theme.Font, pillTextSize, locale.resolve(page.pageName))
    local iconWidth = if page.pageIcon then pillIconSize + pillIconGap else 0
    return math.ceil(pillPadX * 2 + iconWidth + textWidth)
end

function Panel:_buildPill(page)
    local window = self.window
    local pill = {}

    pill.frame = window:Create("Frame", {
        Name = "Pill",
        Size = UDim2.fromOffset(self:_pillWidth(page), pillHeight),
        AnchorPoint = Vector2.new(1, 0),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = FieldTransparency

        Parent = self.main,
    }, { BackgroundColor3 = "FieldBackground" })
    window:Create("UICorner", { CornerRadius = UDim.new(0, pillCorner), Parent = pill.frame })

    local left = pillPadX
    if page.pageIcon then
        pill.icon = window:Create("ImageLabel", {
            Image = page.pageIcon,
            Size = UDim2.fromOffset(pillIconSize, pillIconSize),
            Position = UDim2.new(0, left, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = pillRestIcon

            Parent = pill.frame,
        }, { ImageColor3 = "ContentColor" })
        left += pillIconSize + pillIconGap
    end

    pill.label = window:Create("TextLabel", {
        Text = locale.t(page.pageName),
        Size = UDim2.new(1, -(left + pillPadX), 1, 0),
        Position = UDim2.fromOffset(left, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = pillTextSize,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 1, -- In = pillRestText

        Parent = pill.frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    pill.interact = window:Create("TextButton", {
        Name = "Interact",
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = pill.frame,
    })

    window:ConnectFor(self, pill.interact.MouseEnter, function()
        if not window:_interactive() then
            return
        end
        variables.tweenService:Create(pill.label, hoverInfo, { TextTransparency = pillHoverText }):Play()
        if pill.icon then
            variables.tweenService:Create(pill.icon, hoverInfo, { ImageTransparency = pillHoverIcon }):Play()
        end
    end)
    window:ConnectFor(self, pill.interact.MouseLeave, function()
        variables.tweenService:Create(pill.label, hoverInfo, { TextTransparency = pillRestText }):Play()
        if pill.icon then
            variables.tweenService:Create(pill.icon, hoverInfo, { ImageTransparency = pillRestIcon }):Play()
        end
    end)
    window:ConnectFor(self, pill.interact.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
        self:SelectPage(page)
    end)

    return pill
end

-- One page: a pill in the header, and a column Group built against a fake host so every CreateX
-- works on it. Returns the page itself - a dev builds into it exactly like any Group.
function Panel:CreatePage(properties)
    properties = if typeof(properties) == "table" then properties else {}
    local index = #self.pages + 1
    local window = self.window

    local pageFrame = window:Create("Frame", {
        Name = "Page",
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,

        Parent = self.pageContainer,
    })
    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = pageFrame,
    })

    -- the same four fields Group.new reads off a Tab - see group.luau's header and tabbox.luau
    local fakeHost = {
        window = window,
        tabPage = pageFrame,
        direction = Enum.FillDirection.Vertical,
        forgetState = self.forgetState,
    }
    local page = require(script.Parent.group).new(fakeHost, { direction = "column" })
    page.frame = pageFrame
    page.pageName = properties.name or properties.Name or ("Page " .. index)
    page.pageIcon = properties.icon or properties.Icon
    page.panel = self

    table.insert(self.pages, page)
    assignOrder(page, index * 10)
    page.pill = self:_buildPill(page)

    -- the card follows whichever page is current as that page's contents grow or shrink
    window:ConnectFor(self, page.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.pages[self.selectedIndex] == page then
            self:_syncHeight()
        end
    end)

    if index == 1 then
        -- the first page is where a panel opens; selecting it is not a change anyone asked for
        self:SelectPage(1, true)
    else
        self:_layoutHeader()
    end

    -- pages added after the window is open have to reveal themselves, or their pill stays clear
    if not window.hidden and self._shown then
        self:_setShown(true, true)
    end

    return page
end

function Panel:_resolve(target)
    if type(target) == "number" then
        return if self.pages[target] then target else nil
    elseif type(target) == "string" then
        for index, page in self.pages do
            if page.pageName == target then
                return index
            end
        end
    elseif type(target) == "table" then
        return table.find(self.pages, target)
    end
    return nil
end

-- Make a page current, by index, by name, or by the page object CreatePage returned. Returns false
-- for a page this panel does not have.
function Panel:SelectPage(target, skipCallback)
    local index = self:_resolve(target)
    if not index then
        return false
    end
    local changed = self.selectedIndex ~= index
    self.selectedIndex = index

    for i, page in self.pages do
        page.frame.Visible = i == index
    end

    local page = self.pages[index]
    self.title.Text = locale.resolve(page.pageName)
    self.iconLabel.Visible = page.pageIcon ~= nil
    if page.pageIcon then
        self.iconLabel.Image = page.pageIcon
    end

    self:_layoutHeader()
    self:_syncHeight()

    if changed and not skipCallback and self.onPageChanged then
        self.window:_runGuarded(self, self.onPageChanged, page.pageName)
    end
    return true
end

-- The current page's name, or nil before any page exists.
function Panel:GetPage(): string?
    local page = self.pages[self.selectedIndex]
    return page and page.pageName
end

-- Pills for every page but the current one, packed against the right edge in creation order; the
-- title takes whatever width they leave.
function Panel:_layoutHeader()
    local right = sidePadding
    for i = #self.pages, 1, -1 do
        local page = self.pages[i]
        local pill = page.pill
        local visible = i ~= self.selectedIndex
        pill.frame.Visible = visible
        if visible then
            local width = self:_pillWidth(page)
            pill.frame.Size = UDim2.fromOffset(width, pillHeight)
            pill.frame.Position = UDim2.new(1, -right, 0, headerTop + (headerHeight - pillHeight) / 2)
            right += width + pillGap
        end
    end

    local current = self.pages[self.selectedIndex]
    local iconOffset = if current and current.pageIcon then iconSize + 7 else 0
    self.title.Position = UDim2.fromOffset(sidePadding + iconOffset, headerTop)
    self.title.Size = UDim2.new(1, -(sidePadding + iconOffset + right + 4), 0, headerHeight)
end

function Panel:_syncHeight()
    local page = self.pages[self.selectedIndex]
    local content = if page then page.main.AbsoluteSize.Y else 0
    local contentTop = headerTop + headerHeight + headerGap

    self.pageContainer.Size = UDim2.new(1, 0, 0, content)
    self.main.Size = UDim2.new(
        1,
        -20,
        0,
        if content > 0 then contentTop + content + bottomPadding else headerTop + headerHeight + bottomPadding
    )
end

function Panel:_setShown(shown, animate)
    local w = self.window
    self._shown = shown
    -- not _revealCommon for the card itself: that fades a card to the FULL element fill, and a
    -- panel is a container other cards sit on (functions.containerTransparency)
    w:_reveal(self.main, {
        BackgroundTransparency = if shown then functions.containerTransparency(w.theme.ElementTransparency) else 1,
    }, animate)
    w:_reveal(self.stroke, { Transparency = if shown then w.theme.ElementStrokeTransparency else 1 }, animate)
    w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
    w:_reveal(self.iconLabel, { ImageTransparency = if shown then 0 else 1 }, animate)

    for _, page in self.pages do
        local pill = page.pill
        w:_reveal(pill.frame, { BackgroundTransparency = if shown then w.theme.FieldTransparency else 1 }, animate)
        w:_reveal(pill.label, { TextTransparency = if shown then pillRestText else 1 }, animate)
        if pill.icon then
            w:_reveal(pill.icon, { ImageTransparency = if shown then pillRestIcon else 1 }, animate)
        end
        page:_setShown(shown, animate)
    end
end

function Panel:_refreshTheme()
    -- pill widths are measured in the theme's font, so a font swap has to re-pack the header
    self:_layoutHeader()
    for _, page in self.pages do
        if page._refreshTheme then
            page:_refreshTheme()
        end
    end
end

moveable(Panel)

return Panel

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 6: a clickable header (title + a chevron that rotates) that expands to reveal its own
-- children, collapsing their height smoothly instead of a hard cut. Doesn't reimplement element
-- building itself - it hosts an internal column Group (group.luau) and forwards every CreateX
-- call to it, exposing the same Tab-like surface (window/tabPage/elements/compact/direction)
-- Group itself expects from its own host. tabPage points at this collapsible's own inner frame,
-- so the group's normal full-width column just becomes this section's expandable content.

local Collapsible = {}
Collapsible.__index = Collapsible
Collapsible.__type = "Collapsible"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)

local heightInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local chevronInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local headerHeight = 43

-- breathing room around the nested group: without it, the first child sits glued to the header
-- and the last one gets squeezed against the clip's bottom edge the instant the section opens
local contentPadTop = 8
local contentPadBottom = 8

function Collapsible.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Section",
        icon = properties.icon or properties.Icon,
        forgetState = tab.forgetState,
        compact = false,
        direction = nil,
        elements = {}, -- the inner group's own elements list (Group fills this in)

        expanded = if properties.expanded ~= nil
            then properties.expanded
            elseif properties.Expanded ~= nil then properties.Expanded
            else false,
    }, Collapsible)

    -- the -20 inset happens once here (matches every other tabPage-level card, e.g.
    -- colorpicker.luau's own outer main) - header/contentWrapper below are full width of this.
    -- No AutomaticSize here on purpose: confirmed live that main's AutomaticSize.Y doesn't
    -- reliably follow a *tweened* child Size change on this executor (same class of bug as
    -- UIListLayout never writing back a tweened child's Position) - main sat stuck at whatever
    -- height it last was, collapsed or not, leaving dead space below the header forever. main's
    -- own height is driven explicitly instead, in lockstep with contentWrapper's, by _setHeight
    -- below - every call site that used to resize just contentWrapper resizes both together now.
    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Name = self.name,

        Parent = self.tab.tabPage,
    })

    self:_buildHeader()

    -- content: clips so the collapse never shows a half-cut child, height tweens between 0 and
    -- the inner group's own real AbsoluteSize.Y
    self.contentWrapper = self.window:Create("Frame", {
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,

        Parent = self.main,
    })

    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, contentPadTop),
        PaddingBottom = UDim.new(0, contentPadBottom),

        Parent = self.contentWrapper,
    })

    self.tabPage = self.contentWrapper

    -- children build through here - see file header. Requiring by relative path (not a name
    -- string) since this isn't Group's own _add dispatch table.
    self._group = require(script.Parent.group).new(self, { direction = "column" })

    self.window:ConnectFor(self, self._group.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.expanded then
            self:_setHeight(self:_contentHeight(), true)
        end
    end)

    -- start at the right height instantly - no animating in from 0 on first build
    if self.expanded then
        self:_setHeight(self:_contentHeight(), false)
        self.chevron.Rotation = 0
    end

    return self
end

-- the group's own real height plus the breathing room above/below it (UIPadding doesn't count
-- toward a sibling's AbsoluteSize, so it has to be added back in by hand here)
function Collapsible:_contentHeight()
    return self._group.main.AbsoluteSize.Y + contentPadTop + contentPadBottom
end

-- Drives contentWrapper's height AND main's own height together (see the comment on self.main's
-- own Create() call above for why main can't just auto-follow this itself). targetContentHeight
-- is contentWrapper's own target - main's is headerHeight taller, header + content stacked.
function Collapsible:_setHeight(targetContentHeight, animate)
    local contentSize = UDim2.new(1, 0, 0, targetContentHeight)
    local mainSize = UDim2.new(1, -20, 0, headerHeight + targetContentHeight)
    if animate then
        variables.tweenService:Create(self.contentWrapper, heightInfo, { Size = contentSize }):Play()
        variables.tweenService:Create(self.main, heightInfo, { Size = mainSize }):Play()
    else
        self.contentWrapper.Size = contentSize
        self.main.Size = mainSize
    end
end

function Collapsible:_buildHeader()
    self.header = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 43),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.main,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.header)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.header)

    self.container = self.window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.header,
        Size = UDim2.new(1, -70, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })

    self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- chevron: 180deg = closed (matches dropdown.luau's own convention), tweens to 0 on open
    self.chevron = self.window:Create("ImageLabel", {
        Image = constants.icons.chevron,
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -20, 0.5, 0),
        Rotation = 180,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,

        ImageTransparency = 1, -- In = 0.4

        Parent = self.header,
    }, { ImageColor3 = "ContentColor" })

    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,

        Parent = self.header,
    })

    self.window:_wireElementHover({ main = self.header, stroke = self.stroke, title = self.title, hoverOverlay = self.hoverOverlay })

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        self:Toggle()
    end)
end

function Collapsible:Toggle()
    self:SetExpanded(not self.expanded)
end

function Collapsible:SetExpanded(expanded)
    expanded = expanded and true or false
    if expanded == self.expanded then
        return
    end
    self.expanded = expanded

    self:_setHeight(if expanded then self:_contentHeight() else 0, true)
    variables.tweenService:Create(self.chevron, chevronInfo, { Rotation = if expanded then 0 else 180 }):Play()
end

-- Forward every CreateX to the inner column group, so a Collapsible reads exactly like a Tab
-- or Group to a dev using it.
for _, name in {
    "CreateButton", "CreateFlipButton", "CreateCopyButton", "CreateRippleButton", "CreateToggle",
    "CreateSwitch", "CreateCheckbox", "CreateStat", "CreateSlider", "CreateDropdown", "CreateSection",
    "CreateLabel", "CreateParagraph", "CreateGroup",
} do
    Collapsible[name] = function(self, properties)
        return self._group[name](self._group, properties)
    end
end

function Collapsible:_setShown(shown, animate)
    local w = self.window
    local proxy = { stroke = self.stroke, title = self.title, main = self.header, iconLabel = self.iconLabel }
    if shown then
        w:_revealCommon(proxy, animate)
        w:_reveal(self.chevron, { ImageTransparency = 0.4 }, animate)
    else
        w:_hideCommon(proxy, animate)
        w:_reveal(self.chevron, { ImageTransparency = 1 }, animate)
    end
    self._group:_setShown(shown, animate)
end

function Collapsible:_refreshTheme()
    self._group:_refreshTheme()
end

moveable(Collapsible)

return Collapsible

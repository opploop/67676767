--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Dropdown = {}
Dropdown.__index = Dropdown
Dropdown.__type = "Dropdown"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local image = require(utility.image)
local constants = require(utility.constants)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)
local moveable = require(utility.moveable)

local chevronIcon = constants.icons.chevron
local checkIcon = constants.icons.check
local dotIcon = constants.icons.dot
local searchIconAsset = constants.icons.search

-- Per-corner radii: an option's edge is rounded when nothing sits next to it, sharp otherwise
local roundRadius = UDim.new(0, 12)
local flatRadius = UDim.new(0, 7)

local searchCollapsedHeight = 30
local searchExpandedHeight = 38

-- Devlog 8: the panel opens tall enough to show this many full option rows before it caps out
-- and the list scrolls internally instead - was capped at a flat 180px, tall enough for barely
-- 2 rows once the header/search/padding overhead was subtracted.
local maxVisibleOptionRows = 4
local optionRowHeight = 38
local rowGap = 5
-- height of `maxVisibleOptionRows` option rows plus the gaps between them, no header/search/
-- padding included - that part (the "base") varies per dropdown (multiSelect adds a row), so
-- _openHeight adds this on top of its own base rather than this baking in a fixed total.
local capRowsHeight = maxVisibleOptionRows * optionRowHeight + math.max(0, maxVisibleOptionRows - 1) * rowGap + 2

local quickActionsRowHeight = 20
local quickActionsRowGap = 5
local searchTween = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

local function dedupStrings(arr)
    local seen = {}
    local out = {}
    for _, v in arr do
        if typeof(v) == "string" and not seen[v] then
            seen[v] = true
            table.insert(out, v)
        end
    end
    return out
end

local function normalizeValue(value, multi)
    if value == nil then
        return {}
    end
    if typeof(value) == "string" then
        return { value }
    end
    if typeof(value) == "table" then
        local out = dedupStrings(value)
        if not multi and #out > 1 then
            return { out[1] }
        end
        return out
    end
    return {}
end

-- The visible selection is always the intent narrowed to options that currently exist.
local function intersectWithOptions(value, options)
    local out = {}
    for _, v in value do
        if table.find(options, v) then
            table.insert(out, v)
        end
    end
    return out
end

local function sameSelection(a, b)
    if #a ~= #b then
        return false
    end
    for _, v in a do
        if not table.find(b, v) then
            return false
        end
    end
    return true
end

function Dropdown.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local options = properties.options or properties.Options or {}
    local multiSelect = properties.multiSelect or properties.MultiSelect or properties.MultipleOptions or false

    -- Optional section headers: { {name="MELEE", options={"Sword","Axe"}}, {name="RANGED", ...} }.
    -- When given, they take over from a flat `options` list - self.options is derived by
    -- flattening them in order, and every option is mapped back to its section name so
    -- rendering can insert a header before the first option of each run and re-group on filter.
    local sections = properties.sections or properties.Sections
    local sectionStarts = {} -- optionName -> section name, only the FIRST option of each section
    local sectionOf = {} -- optionName -> section name, every option
    if sections then
        local flat = {}
        for _, section in sections do
            local sectionName = section.name or section.Name or ""
            local sectionOptions = section.options or section.Options or {}
            local startedSection = false
            for _, optName in sectionOptions do
                table.insert(flat, optName)
                sectionOf[optName] = sectionName
                if not startedSection then
                    sectionStarts[optName] = sectionName
                    startedSection = true
                end
            end
        end
        options = flat
    end

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Dropdown",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState, -- dont save config for this element if true.
        locked = properties.locked or properties.Locked or false,

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Dropdown")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,

        options = dedupStrings(options),
        multiSelect = multiSelect,
        placeholderText = locale.resolve(properties.placeholder or properties.Placeholder or "None"),
        value = normalizeValue(
            properties.value or properties.Value or properties.currentOption or properties.CurrentOption,
            multiSelect
        ),

        _isOpen = false,
        _optionFrames = {},
        _headerFrames = {},
        _sectionStarts = sectionStarts,
        _sectionOf = sectionOf,
    }, Dropdown)

    -- Remember the full intent so a selection survives options that only load later (via
    -- Refresh), while self.value stays narrowed to options that currently exist.
    self._desiredValue = self.value
    self.value = intersectWithOptions(self.value, self.options)

    -- Register as a saveable control if flagged
    self.window:_registerControl(self)

    -- Outer wrapper: transparent, just holds the two cards and animates its height
    -- open <-> closed. Clips so the options card is hidden while collapsed.
    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 41),
        BorderSizePixel = 0,
        Name = self.name,
        ClipsDescendants = true,
        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    })

    -- Header card: the always-visible pill (icon + title + selected value + chevron)
    self.top = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 41),
        Position = UDim2.fromScale(0, 0),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        ZIndex = 1,

        Parent = self.main,
    }, { BackgroundTransparency = "ElementTransparency" })

    -- flat themed stroke, same as every other element's card (StyleElementPanel's gradient
    -- sheen read as an inconsistent/"improper" outline next to them - see StyleElementPanel's
    -- own doc comment; Popup still uses it deliberately for its changelog cards)
    self.stroke = self.window:StyleElementBody(self.top)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.top)
    self.flashTarget = self.top -- main is a transparent wrapper, so the error-flash tints the pill
    self.tooltipTarget = self.top -- same reason: hover on the actual pill, not the wrapper

    self.container = self.window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.top,
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        ZIndex = 5,
    })

    self.containerLayout = self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
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

            -- Animation
            ImageTransparency = 1, -- In = 0

            ZIndex = 5,
            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        -- Configurables
        Text = locale.t(self.name),

        Size = UDim2.fromOffset(150, 16),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        AutomaticSize = Enum.AutomaticSize.X,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,

        -- Animation
        TextTransparency = 1, -- In = 0

        ZIndex = 5,
        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.selectedLabel = self.window:Create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -41, 0.5, 0),
        Size = UDim2.fromOffset(168, 15),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextWrapped = true,

        -- Animation
        TextTransparency = 1, -- In = 0.5

        ZIndex = 5,
        Parent = self.top,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.chevron = self.window:Create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -18, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        Image = "rbxassetid://" .. tostring(chevronIcon),
        Rotation = 180,

        -- Animation
        ImageTransparency = 1, -- In = 0.5

        ZIndex = 5,
        Parent = self.top,
    }, { ImageColor3 = "ContentColor" })

    -- Covers only the header, so option clicks in the open panel below don't hit it.
    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 41),
        Position = UDim2.fromScale(0, 0),
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,
        ZIndex = 10,
        AutoButtonColor = false,

        Parent = self.main,
    })

    -- Options card: a second (full-width) pill below the header, revealed as the wrapper
    -- grows. Anchored to the wrapper's bottom (top edge sits 6px under the header) so the
    -- clip hides it while collapsed.
    self.panel = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 0, 1, 0),
        Size = UDim2.new(1, 0, 1, -47),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        ZIndex = 1,

        BackgroundTransparency = 1, -- Open = ElementTransparency

        Parent = self.main,
    })

    self.panelStroke = self.window:StyleElementBody(self.panel)

    -- The card stacks the search bar over the list. The search bar is always present in
    -- the layout (it just grows/shrinks), so the gap under it is stable; the list is a
    -- flex-fill item, so it takes whatever height is left and slides down as search grows.
    self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.panel,
    })

    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, 7),
        PaddingBottom = UDim.new(0, 6),

        Parent = self.panel,
    })

    self:_buildSearch()
    self:_buildQuickActions()

    self.list = self.window:Create("ScrollingFrame", {
        Active = true,
        Size = UDim2.new(1, 0, 0, 0), -- height comes from the UIFlexItem below
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarImageColor3 = Color3.fromRGB(240, 240, 240),
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 1, -- scrollbar kept fully transparent
        ScrollingDirection = Enum.ScrollingDirection.Y,
        LayoutOrder = 3,
        ZIndex = 1,

        Parent = self.panel,
    })

    self.window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Fill,

        Parent = self.list,
    })

    self.listLayout = self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,

        Parent = self.list,
    })

    self.window:Create("UIPadding", {
        PaddingBottom = UDim.new(0, 2),

        Parent = self.list,
    })

    -- Devlog 8: shown instead of the (now empty) option list when a search query matches
    -- nothing. A normal row in the same list/layout, sized the same as an option row so
    -- _openHeight's row math (which counts it in when visible) stays accurate.
    self.emptyLabel = self.window:Create("TextLabel", {
        Text = locale.t("No results found"),
        Size = UDim2.new(1, -12, 0, optionRowHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextTransparency = 0.5,
        Visible = false,

        Parent = self.list,
    }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })

    local function isOptionSelected(name)
        return table.find(self.value, name) ~= nil
    end

    local function renderOptionState(data, animate)
        local selected = isOptionSelected(data.name)
        local bgT = if self._isOpen then (selected and 0.9 or 0.95) else 1
        local titleT = if self._isOpen then (selected and 0 or 0.3) else 1
        -- Selected shows a bright check; unselected shows a faint dot
        local iconT = if self._isOpen then (selected and 0 or 0.7) else 1
        local strokeT = if self._isOpen then (selected and 0.85 or 0.93) else 1

        image.assign(data.checkIcon, "Image", if selected then checkIcon else dotIcon)

        if animate then
            local info = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
            variables.tweenService:Create(data.frame, info, { BackgroundTransparency = bgT }):Play()
            variables.tweenService:Create(data.title, info, { TextTransparency = titleT }):Play()
            variables.tweenService:Create(data.checkIcon, info, { ImageTransparency = iconT }):Play()
            variables.tweenService:Create(data.stroke, info, { Transparency = strokeT }):Play()
        else
            data.frame.BackgroundTransparency = bgT
            data.title.TextTransparency = titleT
            data.checkIcon.ImageTransparency = iconT
            data.stroke.Transparency = strokeT
        end
    end

    local function updateSelectedLabel()
        if self.multiSelect then
            local n = #self.value
            if n == 0 then
                self.selectedLabel.Text = self.placeholderText
            elseif n == 1 then
                self.selectedLabel.Text = self.value[1]
            else
                self.selectedLabel.Text = locale.resolve("Various")
            end
        else
            self.selectedLabel.Text = self.value[1] or self.placeholderText
        end
    end

    self._renderOptionState = renderOptionState
    self._updateSelectedLabel = updateSelectedLabel

    local function buildOption(optionName)
        local frame = self.window:Create("Frame", {
            Size = UDim2.new(1, -12, 0, 38),
            BorderSizePixel = 0,

            BackgroundTransparency = 1,

            Parent = self.list,
        }, { BackgroundColor3 = "DropdownHighlight" })

        -- Radius is driven by adjacency in _updateCorners (7 flat / 12 rounded)
        local corner = self.window:Create("UICorner", {
            CornerRadius = flatRadius,
            Parent = frame,
        })

        -- Subtle stroke, only shown on the selected option
        local optionStroke = self.window:Create("UIStroke", {
            Color = Color3.fromRGB(255, 255, 255),
            Transparency = 1, -- selected = 0.85
            Parent = frame,
        })

        local interact = self.window:Create("TextButton", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            TextTransparency = 1,
            ZIndex = 50,
            Parent = frame,
        })

        local container = self.window:Create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(170, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 5,
            Parent = frame,
        })

        self.window:Create("UIListLayout", {
            Padding = UDim.new(0, 5),
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = container,
        })

        local checkIcon = self.window:Create("ImageLabel", {
            Image = "rbxassetid://" .. tostring(checkIcon),
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ImageTransparency = 1,
            ZIndex = 5,
            Parent = container,
        }, { ImageColor3 = "ContentColor" })

        local title = self.window:Create("TextLabel", {
            Text = optionName,
            Size = UDim2.fromOffset(170, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            TextSize = 16,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 1,
            TextTransparency = 1,
            ZIndex = 5,
            Parent = container,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })

        local data = {
            name = optionName,
            frame = frame,
            interact = interact,
            title = title,
            checkIcon = checkIcon,
            container = container,
            stroke = optionStroke,
            corner = corner,
            -- tracked per option so a rebuild tears them down with the frame
            connections = {},
        }

        table.insert(
            data.connections,
            self.window:ConnectFor(self, frame.MouseEnter, function()
                if not self._isOpen or not self.window:_interactive() then
                    return
                end
                if isOptionSelected(optionName) then
                    return
                end
                variables.tweenService
                    :Create(
                        frame,
                        TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { BackgroundTransparency = 0.9 }
                    )
                    :Play()
                variables.tweenService
                    :Create(
                        title,
                        TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { TextTransparency = 0.15 }
                    )
                    :Play()
            end)
        )

        table.insert(
            data.connections,
            self.window:ConnectFor(self, frame.MouseLeave, function()
                if not self._isOpen then
                    return
                end
                if isOptionSelected(optionName) then
                    return
                end
                variables.tweenService
                    :Create(
                        frame,
                        TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { BackgroundTransparency = 0.95 }
                    )
                    :Play()
                variables.tweenService
                    :Create(
                        title,
                        TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { TextTransparency = 0.3 }
                    )
                    :Play()
            end)
        )

        table.insert(
            data.connections,
            self.window:ConnectFor(self, interact.MouseButton1Click, function()
                -- options stay visible through the close tween; a click mid-fade must not land.
                -- locked forces the panel closed itself (see _applyLocked), but guard here too
                -- in case a click is already in flight the same frame it locks.
                if not self._isOpen or self.locked then
                    return
                end
                hapticEngine.click()
                soundEngine.click()
                local sel = isOptionSelected(optionName)

                if not self.multiSelect then
                    if sel then
                        self:_close()
                        return
                    end
                    table.clear(self.value)
                    table.insert(self.value, optionName)
                else
                    if sel then
                        local idx = table.find(self.value, optionName)
                        if idx then
                            table.remove(self.value, idx)
                        end
                    else
                        table.insert(self.value, optionName)
                    end
                end

                -- the visible selection is now the player's intent; a later Refresh must build
                -- on this, not revert to whatever was restored before they touched it
                self._desiredValue = table.clone(self.value)

                for _, d in self._optionFrames do
                    renderOptionState(d, true)
                end

                updateSelectedLabel()

                self.window:_runGuarded(self, self.callback, self:_callbackValue())
                self.window:_persist(self)

                if not self.multiSelect then
                    task.wait(0.1)
                    self:_close()
                end
            end)
        )

        return data
    end

    self._buildOption = buildOption

    -- Non-interactive section header row - only built for an option that's the first of its
    -- section (see self._sectionStarts above). Static transparency rather than tracking open/
    -- close like an option's own title does: self.main clips everything below 41px while
    -- closed regardless, so there's nothing to actually leak while collapsed.
    local function buildHeader(sectionName)
        local frame = self.window:Create("Frame", {
            Size = UDim2.new(1, -12, 0, 24),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            Parent = self.list,
        })
        local label = self.window:Create("TextLabel", {
            Text = locale.t(sectionName),
            Size = UDim2.new(1, -14, 1, 0),
            Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTransparency = 0.55,

            Parent = frame,
        }, { TextColor3 = "PlaceholderColor" })
        return { name = sectionName, frame = frame, label = label }
    end

    -- Builds every option (and, when sectioned, the header ahead of each section's first
    -- option) from self.options/self._sectionStarts, in order. Doesn't paint open/closed state
    -- or resize anything - callers (the initial build below, and Refresh) do that themselves
    -- afterward since they need it at different points in their own sequence.
    local function buildAllOptions()
        for _, opt in self.options do
            local sectionName = self._sectionStarts[opt]
            if sectionName then
                table.insert(self._headerFrames, buildHeader(sectionName))
            end
            local data = buildOption(opt)
            table.insert(self._optionFrames, data)
        end
    end
    self._buildAllOptions = buildAllOptions

    buildAllOptions()

    updateSelectedLabel()
    self:_updateCorners()

    -- Function
    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        hapticEngine.click()
        soundEngine.click()
        if self._isOpen then
            self:_close()
        else
            self:_open()
        end
    end)

    -- Hover feedback via the overlay + title only (stroke stays put - unlike _wireElementHover's
    -- elements, the header's stroke transparency also has to track open/close, so leaving hover
    -- out of it keeps those two animations from fighting over the same property).
    self.window:ConnectFor(self, self.main.MouseEnter, function()
        if self._isOpen or not self.window:_interactive() then
            return
        end
        variables.tweenService
            :Create(
                self.title,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextColor3 = self.window.theme.ElementTextHoverColor }
            )
            :Play()
        variables.tweenService
            :Create(
                self.hoverOverlay,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0.97 }
            )
            :Play()
    end)

    self.window:ConnectFor(self, self.main.MouseLeave, function()
        variables.tweenService
            :Create(
                self.title,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextColor3 = self.window.theme.ContentColor }
            )
            :Play()
        variables.tweenService
            :Create(
                self.hoverOverlay,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { BackgroundTransparency = 1 }
            )
            :Play()
    end)

    self.window:_wireTooltip(self)

    -- pinned to the header's right edge, same spot the chevron sits - _applyLocked hides the
    -- chevron/selected-value text in favour of this + the padlock, there isn't room for both
    self.lockIcon = self.window:_buildLockIcon(self.top, UDim2.new(1, -18, 0.5, 0), Vector2.new(1, 0.5))
    self.prohibitedIcon = self.window:_buildProhibitedIcon(self.container)
    self:_applyLocked(false)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

-- Search bar: collapsed it's just the icon (centred, no bar); tapping expands it into a
-- full field. It's always in the card's layout - only its height/fills animate - so the
-- list below just flexes down as it grows.
-- what the dev's callback receives. multiSelect hands out a copy: the live table is our
-- selection state, and a dev who keeps or mutates it would corrupt the dropdown.
function Dropdown:_callbackValue()
    if self.multiSelect then
        return table.clone(self.value)
    end
    return self.value[1]
end

function Dropdown:_buildSearch()
    self._searchOpen = false

    self.searchbar = self.window:Create("Frame", {
        Name = "Search",
        Size = UDim2.new(1, -12, 0, searchCollapsedHeight),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, -- expanded = 0.92
        LayoutOrder = 1,
        ClipsDescendants = false,
        ZIndex = 1,

        Parent = self.panel,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = self.searchbar,
    })

    self.searchStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- expanded = 0.86
        Parent = self.searchbar,
    })

    self.searchShadow = self.window:CreateGlow(self.searchbar, Color3.fromRGB(255, 255, 255), 20, 1) -- expanded = 0.92

    -- Full-bar tap target: expands the bar while it's collapsed. Kept above the option
    -- hit-targets (ZIndex 50) so taps here never bleed through to an option under them.
    self.searchToggle = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        TextTransparency = 1,
        ZIndex = 51,
        Parent = self.searchbar,
    })

    self.searchInput = self.window:Create("TextBox", {
        Text = "",
        PlaceholderText = locale.t("Search..."),
        Size = UDim2.new(1, -58, 0, 16),
        Position = UDim2.new(0, 44, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextEditable = false, -- enabled on expand
        Interactable = false, -- collapsed: let taps fall through to the toggle
        ZIndex = 52,

        TextTransparency = 1, -- expanded = 0.3

        Parent = self.searchbar,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    self.searchIcon = self.window:Create("ImageButton", {
        Image = "rbxassetid://" .. tostring(searchIconAsset),
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(0, 24, 0.5, 0), -- left-aligned (centre at x=24, edge at 14)
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        AutoButtonColor = false,
        ZIndex = 53,

        ImageTransparency = 1, -- In = 0.5

        Parent = self.searchbar,
    }, { ImageColor3 = "ContentColor" })

    self.window:ConnectFor(self, self.searchToggle.MouseButton1Click, function()
        if not self._searchOpen then
            self:_expandSearch()
        end
    end)
    self.window:ConnectFor(self, self.searchIcon.MouseButton1Click, function()
        if self._searchOpen then
            self:_collapseSearch()
        else
            self:_expandSearch()
        end
    end)
    self.window:ConnectFor(self, self.searchInput:GetPropertyChangedSignal("Text"), function()
        self:_applyFilter(self.searchInput.Text)
    end)
    self.window:ConnectFor(self, self.searchInput.FocusLost, function()
        if self.searchInput.Text == "" then
            self:_collapseSearch()
        end
    end)
end

function Dropdown:_expandSearch()
    if self._searchOpen then
        return
    end
    self._searchOpen = true
    self.searchInput.TextEditable = true
    self.searchInput.Interactable = true

    variables.tweenService
        :Create(
            self.searchbar,
            searchTween,
            { Size = UDim2.new(1, -12, 0, searchExpandedHeight), BackgroundTransparency = 0.92 }
        )
        :Play()
    variables.tweenService:Create(self.searchStroke, searchTween, { Transparency = 0.86 }):Play()
    variables.tweenService:Create(self.searchShadow, searchTween, { Transparency = 0.92 }):Play()
    variables.tweenService:Create(self.searchInput, searchTween, { TextTransparency = 0.3 }):Play()

    self.searchInput:CaptureFocus()
end

function Dropdown:_collapseSearch()
    if not self._searchOpen then
        return
    end
    self._searchOpen = false
    self.searchInput.TextEditable = false
    self.searchInput.Interactable = false
    self.searchInput:ReleaseFocus()
    self.searchInput.Text = "" -- fires the filter, showing everything again

    variables.tweenService
        :Create(
            self.searchbar,
            searchTween,
            { Size = UDim2.new(1, -12, 0, searchCollapsedHeight), BackgroundTransparency = 1 }
        )
        :Play()
    variables.tweenService:Create(self.searchStroke, searchTween, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.searchShadow, searchTween, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.searchInput, searchTween, { TextTransparency = 1 }):Play()
end

-- Quick text-button row between the search bar and the option list. "Clear" shows on every
-- dropdown (a one-tap way to empty the selection without hunting for whichever option is
-- currently checked); "Select all" only makes sense once there can be more than one selected
-- option, so it's multiSelect-only. Both act on whatever's currently VISIBLE, so an active search
-- filter scopes them to just the filtered options rather than the dropdown's full option set.
function Dropdown:_buildQuickActions()
    self.quickActionsRow = self.window:Create("Frame", {
        Name = "QuickActions",
        Size = UDim2.new(1, -12, 0, quickActionsRowHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2,

        Parent = self.panel,
    })

    self.window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 14),
        VerticalAlignment = Enum.VerticalAlignment.Center,

        Parent = self.quickActionsRow,
    })

    local function buildQuickAction(text, order)
        local button = self.window:Create("TextButton", {
            Text = locale.t(text),
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = false,
            LayoutOrder = order,

            TextTransparency = 1, -- In = 0.35 (see _open/_close)

            Parent = self.quickActionsRow,
        }, { TextColor3 = "PlaceholderColor" })

        self.window:ConnectFor(self, button.MouseEnter, function()
            if not self._isOpen or not self.window:_interactive() then
                return
            end
            variables.tweenService
                :Create(
                    button,
                    TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                    { TextColor3 = self.window.theme.ElementTextHoverColor }
                )
                :Play()
        end)
        self.window:ConnectFor(self, button.MouseLeave, function()
            variables.tweenService
                :Create(
                    button,
                    TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                    { TextColor3 = self.window.theme.PlaceholderColor }
                )
                :Play()
        end)

        return button
    end

    if self.multiSelect then
        self.selectAllButton = buildQuickAction("Select all", 1)
        self.window:ConnectFor(self, self.selectAllButton.MouseButton1Click, function()
            if not self._isOpen or self.locked then
                return
            end
            hapticEngine.click()
            soundEngine.click()
            self:_selectAllVisible()
        end)
    end

    self.clearButton = buildQuickAction("Clear", 2)
    self.window:ConnectFor(self, self.clearButton.MouseButton1Click, function()
        if not self._isOpen or self.locked then
            return
        end
        hapticEngine.click()
        soundEngine.click()
        self:_clearVisible()
    end)
end

-- Shared tail for _selectAllVisible/_clearVisible: repaint, tell the dev, and save - the same
-- three steps a single option click already does after touching self.value.
function Dropdown:_afterValueChanged()
    self._desiredValue = table.clone(self.value)
    for _, data in self._optionFrames do
        self._renderOptionState(data, true)
    end
    self._updateSelectedLabel()
    self.window:_runGuarded(self, self.callback, self:_callbackValue())
    self.window:_persist(self)
end

function Dropdown:_selectAllVisible()
    local changed = false
    for _, data in self._optionFrames do
        if data.frame.Visible and not table.find(self.value, data.name) then
            table.insert(self.value, data.name)
            changed = true
        end
    end
    if changed then
        self:_afterValueChanged()
    end
end

function Dropdown:_clearVisible()
    local changed = false
    for _, data in self._optionFrames do
        if data.frame.Visible then
            local idx = table.find(self.value, data.name)
            if idx then
                table.remove(self.value, idx)
                changed = true
            end
        end
    end
    if changed then
        self:_afterValueChanged()
    end
end

function Dropdown:_applyFilter(query)
    query = string.lower(query or "")
    local anyOptionVisible = false
    for _, data in self._optionFrames do
        local visible = query == "" or string.find(string.lower(data.name), query, 1, true) ~= nil
        data.frame.Visible = visible
        anyOptionVisible = anyOptionVisible or visible
    end
    -- a header shows only while at least one option in its own section still matches
    for _, header in self._headerFrames do
        local anyVisible = false
        for _, data in self._optionFrames do
            if self._sectionOf[data.name] == header.name and data.frame.Visible then
                anyVisible = true
                break
            end
        end
        header.frame.Visible = anyVisible
    end
    self.emptyLabel.Visible = query ~= "" and not anyOptionVisible
    self:_updateCorners()
    self:_resizeToOptions()
end

-- match the panel to whats visible. only while open: closed height is the header alone.
function Dropdown:_resizeToOptions()
    if not self._isOpen then
        return
    end
    variables.tweenService:Create(self.main, searchTween, { Size = UDim2.new(1, -20, 0, self:_openHeight()) }):Play()
end

-- Per-corner rounding: an option's top corners round off only when nothing sits above it,
-- and its bottom corners only when nothing sits below - so a run of options reads as one
-- grouped block with rounded outer edges and sharp seams (a lone option is fully rounded).
-- Runs over the currently VISIBLE options, so it re-groups correctly while searching. A
-- section header breaks the run too (self._sectionStarts), so each section rounds off on its
-- own instead of reading as one continuous block across a header.
function Dropdown:_updateCorners()
    local visible = {}
    for _, data in self._optionFrames do
        if data.frame.Visible then
            table.insert(visible, data)
        end
    end

    for i, data in visible do
        local startsRun = i == 1 or self._sectionStarts[data.name] ~= nil
        local nextStartsRun = visible[i + 1] and self._sectionStarts[visible[i + 1].name] ~= nil
        local endsRun = i == #visible or nextStartsRun
        local topR = if startsRun then roundRadius else flatRadius
        local botR = if endsRun then roundRadius else flatRadius
        data.corner.TopLeftRadius = topR
        data.corner.TopRightRadius = topR
        data.corner.BottomLeftRadius = botR
        data.corner.BottomRightRadius = botR
    end
end

-- Open height sized to the options (header + search + paddings + rows + any section headers),
-- capped so long lists scroll instead of running off the window - the cap itself is sized to
-- maxVisibleOptionRows full rows (see above), not a flat number, so it still guarantees that many
-- rows show even when the multi-select controls row adds its own height on top. Short lists open
-- just tall enough, no dead space. Sized from what's actually on screen, so a search filter (or
-- an Add/Remove while open) grows and shrinks the panel to fit rather than leaving dead space.
function Dropdown:_openHeight()
    local n = 0
    for _, data in self._optionFrames do
        if data.frame.Visible then
            n += 1
        end
    end
    local h = 0
    for _, header in self._headerFrames do
        if header.frame.Visible then
            h += 1
        end
    end
    if self.emptyLabel and self.emptyLabel.Visible then
        n += 1 -- the "no results" row takes the same space a normal option row would
    end
    local rows = n * optionRowHeight + h * 24 + math.max(0, n + h - 1) * rowGap + 2
    local base = 95 + quickActionsRowHeight + quickActionsRowGap -- the Clear row is always built now
    return math.min(base + capRowsHeight, base + rows)
end

function Dropdown:_open()
    if self._isOpen or self.locked then
        return
    end
    self._isOpen = true

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
    end
    self._outsideClickConn = self.window:Connect(variables.userInputService.InputBegan, function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        local pos = input.Position
        local mainPos = self.main.AbsolutePosition
        local mainSize = self.main.AbsoluteSize
        if
            pos.X < mainPos.X
            or pos.X > mainPos.X + mainSize.X
            or pos.Y < mainPos.Y
            or pos.Y > mainPos.Y + mainSize.Y
        then
            self:_close()
        end
    end)

    local targetHeight = self:_openHeight()

    variables.tweenService
        :Create(
            self.main,
            TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Size = UDim2.new(1, -20, 0, targetHeight) }
        )
        :Play()
    variables.tweenService
        :Create(
            self.chevron,
            TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Rotation = 0 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.panel,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { BackgroundTransparency = self.window.theme.ElementTransparency or 0 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.panelStroke,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Transparency = self.window.theme.ElementStrokeTransparency }
        )
        :Play()
    variables.tweenService
        :Create(
            self.searchIcon,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { ImageTransparency = 0.5 }
        )
        :Play()

    if self.selectAllButton then
        variables.tweenService
            :Create(
                self.selectAllButton,
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextTransparency = 0.35 }
            )
            :Play()
    end
    if self.clearButton then
        variables.tweenService
            :Create(
                self.clearButton,
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextTransparency = 0.35 }
            )
            :Play()
    end

    for _, data in self._optionFrames do
        self._renderOptionState(data, true)
    end

    self:_scrollIntoView(targetHeight)
end

-- Devlog 8: if opening would push the panel's bottom edge below what's actually on screen (the
-- dropdown sits near the end of a tab/page), nudge the parent ScrollingFrame's CanvasPosition
-- down just enough to bring it fully into view instead of opening cut off past the viewport.
-- Walks up to the nearest ScrollingFrame ancestor rather than assuming self.tab.tabPage directly
-- - a dropdown nested in a Group/Collapsible sits inside a plain Frame, not the tab's own page.
function Dropdown:_scrollIntoView(targetHeight)
    local page = self.main:FindFirstAncestorWhichIsA("ScrollingFrame")
    if not page then
        return
    end

    local viewTop = page.AbsolutePosition.Y
    local viewBottom = viewTop + page.AbsoluteWindowSize.Y
    local dropdownTop = self.main.AbsolutePosition.Y
    local dropdownBottom = dropdownTop + targetHeight

    local overflow = dropdownBottom - viewBottom
    if overflow <= 0 then
        return
    end

    -- No manual max-scroll clamp: page.CanvasSize can still read stale/zero right after a tab
    -- switch (AutomaticCanvasSize hasn't caught up to the just-shown content yet - live-caught
    -- this capping every scroll to 0). Roblox already clamps CanvasPosition itself when it's set
    -- past what the canvas actually has, so handing it a generous target is safe either way.
    local margin = 10
    local targetY = page.CanvasPosition.Y + overflow + margin

    variables.tweenService
        :Create(
            page,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { CanvasPosition = Vector2.new(page.CanvasPosition.X, targetY) }
        )
        :Play()
end

function Dropdown:_close()
    if not self._isOpen then
        return
    end
    self._isOpen = false

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end

    self:_collapseSearch()

    variables.tweenService
        :Create(
            self.chevron,
            TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Rotation = 180 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.panel,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.panelStroke,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Transparency = 1 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.searchIcon,
            TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { ImageTransparency = 1 }
        )
        :Play()

    if self.selectAllButton then
        variables.tweenService
            :Create(
                self.selectAllButton,
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextTransparency = 1 }
            )
            :Play()
    end
    if self.clearButton then
        variables.tweenService
            :Create(
                self.clearButton,
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { TextTransparency = 1 }
            )
            :Play()
    end

    for _, data in self._optionFrames do
        self._renderOptionState(data, true)
    end

    variables.tweenService
        :Create(
            self.main,
            TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Size = UDim2.new(1, -20, 0, 41) }
        )
        :Play()
end

-- tear an option down through the window registries, so rebuild churn doesnt leak tracked
-- instances (which would slow ChangeTheme forever) or dead connections
function Dropdown:_destroyOption(data)
    if data.connections then
        for _, connection in data.connections do
            local idx = table.find(self.connections, connection)
            if idx then
                table.remove(self.connections, idx)
            end
            self.window:Disconnect(connection)
        end
        data.connections = nil
    end
    self.window:DestroySubtree(data.frame)
end

-- Replaces the option pool with a plain flat list. Any section grouping the dropdown was built
-- with is dropped here, since a bare name list gives no way to know which section a name
-- belongs to - a sectioned dropdown that needs to reload its options would need a dedicated
-- API this doesn't attempt to be.
function Dropdown:Refresh(newOptions)
    self.options = dedupStrings(newOptions or {})
    self._sectionStarts = {}
    self._sectionOf = {}

    for _, data in self._optionFrames do
        self:_destroyOption(data)
    end
    table.clear(self._optionFrames)
    for _, header in self._headerFrames do
        self.window:DestroySubtree(header.frame)
    end
    table.clear(self._headerFrames)

    -- re-derive the visible selection from the full intent: an option that loads now (or
    -- comes back) re-selects, one that's genuinely gone drops out. self.value only ever holds
    -- real options, so the saved config never carries a stale selection across sessions.
    local previous = self.value
    self.value = intersectWithOptions(self._desiredValue or self.value, self.options)
    local selectionChanged = not sameSelection(self.value, previous)

    self:_buildAllOptions()
    -- fresh frames default to the closed look, so paint the open state if the panel is
    -- already open (otherwise they'd sit blank until hovered)
    if self._isOpen then
        for _, data in self._optionFrames do
            self._renderOptionState(data, false)
        end
    end

    self._updateSelectedLabel()
    -- reconcile with any active search (also refreshes corners); empty query shows all
    self:_applyFilter(if self._searchOpen then self.searchInput.Text else "")

    -- the visible selection changed (options arrived or dropped): tell the dev and save it
    if selectionChanged then
        self.window:_runGuarded(self, self.callback, self:_callbackValue())
        self.window:_persist(self)
    end
end

function Dropdown:Add(option)
    if typeof(option) ~= "string" or option == "" then
        return
    end
    if table.find(self.options, option) then
        return
    end

    table.insert(self.options, option)
    local data = self._buildOption(option)
    table.insert(self._optionFrames, data)

    if self._isOpen then
        self._renderOptionState(data, true)
    end

    -- reconcile with any active search rather than showing an option the query excludes,
    -- and resize for the new row (also refreshes corners)
    self:_applyFilter(if self._searchOpen then self.searchInput.Text else "")
end

function Dropdown:Remove(option)
    local idx = table.find(self.options, option)
    if not idx then
        return
    end

    table.remove(self.options, idx)

    for i, data in self._optionFrames do
        if data.name == option then
            self:_destroyOption(data)
            table.remove(self._optionFrames, i)
            break
        end
    end

    local valueIdx = table.find(self.value, option)
    if valueIdx then
        table.remove(self.value, valueIdx)
        self._desiredValue = table.clone(self.value)
        self._updateSelectedLabel()
        -- removing a selected option changes the selection; surface and save that
        self.window:_runGuarded(self, self.callback, self:_callbackValue())
        self.window:_persist(self)
    end

    -- one row shorter; resize and re-corner around whats left
    self:_applyFilter(if self._searchOpen then self.searchInput.Text else "")
end

function Dropdown:Set(value, skipCallback)
    local newValue = normalizeValue(value, self.multiSelect)
    -- keep the full request so options that arrive later can restore it (see Refresh)
    self._desiredValue = newValue
    self.value = intersectWithOptions(newValue, self.options)

    for _, data in self._optionFrames do
        self._renderOptionState(data, true)
    end
    self._updateSelectedLabel()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:_callbackValue())
        self.window:_persist(self) -- skipCallback means apply quietly, so dont autosave either
    end
end

-- Clears the active selection back to the placeholder - a plain Set(nil) under the hood, since
-- an empty self.value is exactly what already makes updateSelectedLabel fall back to it.
function Dropdown:Reset(skipCallback)
    self:Set(nil, skipCallback)
end

-- Dim the header, show the padlock (see window.luau's shared _buildLockIcon/_applyLockedVisual)
-- and the "no entry" glyph, hide the chevron/selected-value text in favour of the padlock (no
-- room for both), and force-close if it's open when locked.
function Dropdown:_applyLocked(animate)
    self.window:_applyLockedVisual(self, animate)
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local set = function(instance, props)
        if animate then
            variables.tweenService:Create(instance, info, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end
    set(self.chevron, { ImageTransparency = if self.locked then 1 else 0.5 })
    set(self.selectedLabel, { TextTransparency = if self.locked then 1 else 0.5 })
    if self.locked and self._isOpen then
        self:_close()
    end
end

function Dropdown:SetLocked(locked)
    locked = locked and true or false
    if locked == self.locked then
        return
    end
    self.locked = locked
    self:_applyLocked(true)
end

function Dropdown:_setShown(shown, animate)
    -- Custom reveal: main is a transparent wrapper, so reveal the header card (self.top)
    -- rather than main. The options card fades in on open, not here.
    -- Locked-aware title/chevron/selected-value targets, computed as this call's own target
    -- rather than a second tween chasing it in afterward - two simultaneous tweens on the same
    -- property fight each other frame to frame instead of one cleanly winning (the same class
    -- of bug as the tab indicator's own tween race).
    local w = self.window
    local titleTransparency = if self.locked then 0.6 else 0
    local sideTransparency = if self.locked then 1 else 0.5 -- chevron + selected-value text
    w:_reveal(self.stroke, { Transparency = if shown then w.theme.ElementStrokeTransparency else 1 }, animate)
    w:_reveal(self.title, { TextTransparency = if shown then titleTransparency else 1 }, animate)
    w:_reveal(self.top, { BackgroundTransparency = if shown then (w.theme.ElementTransparency or 0) else 1 }, animate)
    if self.iconLabel then
        w:_reveal(self.iconLabel, { ImageTransparency = if shown then titleTransparency else 1 }, animate)
    end
    if self.descriptor then
        w:_reveal(self.descriptor.titleLabel, { TextTransparency = if shown then 0.7 else 1 }, animate)
    end
    w:_reveal(self.selectedLabel, { TextTransparency = if shown then sideTransparency else 1 }, animate)
    w:_reveal(self.chevron, { ImageTransparency = if shown then sideTransparency else 1 }, animate)

    -- lockIcon/prohibitedIcon.Visible aren't touched by any of the above, so they don't need
    -- re-asserting here - only _applyLocked/SetLocked ever change them

    -- if the window hides while we're open, collapse so we dont reopen mid-air
    if not shown and self._isOpen then
        self:_close()
    end
end

-- Devlog 7: was five hand-rolled Move* methods identical to every other component's own
-- copy-paste - consolidated onto the shared mixin (also picks up :SetVisible for free).
moveable(Dropdown)

return Dropdown

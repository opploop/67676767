--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Tab = {}
Tab.__index = Tab
Tab.__type = "Tab"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local locale = require(utility.locale)
local assignOrder = require(utility.ordering)
local hapticEngine = require(utility.HapticEngine)
local search = require(script.Parent.search)

-- Walk a tab or group's children (groups nest) and tear each element down: drop its flag from
-- the window registry and disconnect every connection it owns, so nothing outlives the
-- instances we're about to destroy.
local function teardownElements(window, elements)
    for _, element in elements do
        if element.__type == "Group" then
            teardownElements(window, element.elements)
        else
            window:_unregisterControl(element)
        end

        -- persistent connections filed via window:ConnectFor
        if element.connections then
            for _, connection in element.connections do
                window:Disconnect(connection)
            end
            element.connections = nil
        end

        -- transient, self-managed connections that may still be live if removed mid-interaction
        if element._dragConnection then
            element._dragConnection:Disconnect()
            element._dragConnection = nil
        end
        if element._outsideClickConn then
            window:Disconnect(element._outsideClickConn)
            element._outsideClickConn = nil
        end
    end
end

-- Icon/text transparency per state. No more per-tab background/stroke to animate - Devlog 5's
-- shared self.window.tabIndicator pill supplies the "selected" background now, sliding to
-- whichever tab is active instead of each one fading its own pill in.
local tabStates = {
    selected = { content = 0 },
    hover = { content = 0.3 },
    unselected = { content = 0.5 },
    hidden = { content = 1 },
}

local selectTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local hoverTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function Tab.new(window, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        window = assert(window, "Missing argument #1 (Window expected)"),
        name = properties.name or properties.Name,
        icon = properties.icon or properties.Icon,
        neglectSelector = properties.neglectSelector or properties.NeglectSelector or false,
        customOrder = properties.customOrder or properties.CustomOrder or 0,
        -- when true, controls on this tab default to not persisting to config (the settings tab)
        forgetState = properties.forgetState or properties.ForgetState or false,

        elements = {},
        connections = {}, -- tracked so Remove can drop them without waiting for Unload
    }, Tab)

    -- a tab needs at least one of a name or an icon to show in the selector
    assert(self.name or self.icon, "A tab needs a name or an icon.")

    if not self.neglectSelector then -- Allow for tabs to be hidden from the tab selector, for Rayfield Settings.
        -- Topbar Item - purely a sizing/click surface now. It never paints its own background;
        -- the window's single shared tabIndicator pill (see window.luau) slides behind whichever
        -- one of these is selected, reading this frame's own resolved Position/AbsoluteSize.
        self.topbarItem = self.window:Create("Frame", {
            Name = self.name,
            Size = UDim2.fromOffset(0, 34), -- min size, grows with content
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            Visible = false, -- In = true

            LayoutOrder = self.customOrder or 0,

            Parent = self.window.tabList,
        })

        self.topbarItemInteract = self.window:Create("TextButton", {
            Active = false,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            BorderSizePixel = 0,
            Text = "",
            TextTransparency = 1,
            -- explicit, above the shared indicator's ZIndex 1 (window.luau): ZIndex isn't
            -- inherited from a parent under Global behavior, and the indicator now lives in a
            -- different branch of the tree (tabDock, not tabList) since it moved out of the
            -- ScrollingFrame, so this can't lean on creation order to stay clickable above it
            ZIndex = 2,

            Parent = self.topbarItem,
        })

        self.topbarItemContainer = self.window:Create("Frame", {
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            Parent = self.topbarItem,
        })

        self.window:Create("UIPadding", {
            PaddingLeft = UDim.new(0, 13),
            PaddingRight = UDim.new(0, 14),

            Parent = self.topbarItemContainer,
        })

        self.topbarItemLayout = self.window:Create("UIListLayout", {
            Padding = UDim.new(0, 6),
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,

            Parent = self.topbarItemContainer,
        })

        if self.icon then
            self.topbarItemIcon = self.window:Create("ImageLabel", {
                -- Configurables
                -- raw value: Create routes Image through image.resolve, which already handles
                -- numbers and rbxassetid strings (concat here would double the prefix)
                Image = self.icon,

                Size = UDim2.fromOffset(16, 16),
                BorderSizePixel = 0,
                BackgroundTransparency = 1,
                ZIndex = 2, -- see topbarItemInteract for why this needs to be explicit now

                -- Animation
                ImageTransparency = 1, -- In = 0 / 0.5

                Parent = self.topbarItemContainer,
            }, { ImageColor3 = "TabColor" })
        end

        if self.name then
            self.topbarItemTitle = self.window:Create("TextLabel", {
                -- Configurables
                Text = locale.t(self.name), -- tab name

                Size = UDim2.fromOffset(0, 16),
                BorderSizePixel = 0,
                BackgroundTransparency = 1,
                TextSize = 16,
                AutomaticSize = Enum.AutomaticSize.XY,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                LayoutOrder = 1,
                ZIndex = 2, -- see topbarItemInteract for why this needs to be explicit now

                -- Animation
                TextTransparency = 1, -- In = 0 / 0.5

                Parent = self.topbarItemContainer,
            }, { TextColor3 = "TabColor", FontFace = "Font" })
        end
    end

    -- Tab Page
    self.tabPage = self.window:Create("ScrollingFrame", {
        Name = self.name,
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 68),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,

        LayoutOrder = self.customOrder or 0,

        Parent = self.window.elements,
    })

    self.tabPageLayout = self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 7),
        FillDirection = Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.tabPage,
    })

    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 33),

        Parent = self.tabPage,
    })

    if not self.neglectSelector then
        table.insert(
            self.connections,
            self.window:Connect(self.topbarItemInteract.MouseButton1Click, function()
                hapticEngine.click()
                self:Select()
            end)
        )

        table.insert(
            self.connections,
            self.window:Connect(self.topbarItemInteract.MouseEnter, function()
                if not self.window:_interactive() then
                    return -- window still revealing/hiding: dont light up mid-animation
                end
                if self.window.selectedTab ~= self then
                    self:_applyVisual("hover", hoverTweenInfo)
                end
            end)
        )

        table.insert(
            self.connections,
            self.window:Connect(self.topbarItemInteract.MouseLeave, function()
                if self.window.selectedTab ~= self then
                    self:_applyVisual("unselected", hoverTweenInfo)
                end
            end)
        )

    end

    -- Auto-select is handled by Window:CreateTab after insertion

    return self
end

-- selected: contrast-computed against whatever colour the shared pill currently is (white, or
-- the live accent colour) so the label always reads on top of it. Every other state uses the
-- theme's plain TabColor - only the transparency actually varies between hover/unselected/hidden.
function Tab:_applyVisual(stateName, tweenInfo)
    if self.neglectSelector or not self.topbarItem then
        return
    end

    local state = tabStates[stateName]
    if not state then
        return
    end

    local color
    if stateName == "selected" then
        -- defensive fallback: contrastText would error on a nil color, and a custom theme
        -- (or a window mid-construction) might not have an AccentColor to fall back on either
        local pillColor = if self.window.tabStyle == "white" then Color3.fromRGB(255, 255, 255) else self.window.tabAccentColor
        pillColor = pillColor or self.window.theme.AccentColor or Color3.fromRGB(255, 255, 255)
        color = functions.contrastText(pillColor)
    else
        color = self.window.theme.TabColor
    end

    if tweenInfo then
        if self.topbarItemIcon then
            variables.tweenService
                :Create(self.topbarItemIcon, tweenInfo, { ImageTransparency = state.content, ImageColor3 = color })
                :Play()
        end
        if self.topbarItemTitle then
            variables.tweenService
                :Create(self.topbarItemTitle, tweenInfo, { TextTransparency = state.content, TextColor3 = color })
                :Play()
        end
    else
        if self.topbarItemIcon then
            self.topbarItemIcon.ImageTransparency = state.content
            self.topbarItemIcon.ImageColor3 = color
        end
        if self.topbarItemTitle then
            self.topbarItemTitle.TextTransparency = state.content
            self.topbarItemTitle.TextColor3 = color
        end
    end
end

function Tab:Select(noAnimation)
    -- selecting a tab (e.g. via the settings action) leaves search: bring the strip back,
    -- but let the navigation below pick the page.
    if self.window._searching then
        search.close(self.window, { showTabs = true, jumpTo = false })
    end

    self.window.selectedTab = self
    self.window:_jumpTo(self.tabPage)

    -- noAnimation = initial selection, the pill is still hidden and the window reveal shows it.
    -- a dev calling Navigate/Select before the first Show() hits the same case even without
    -- passing it explicitly - a tween played now would resolve while main is invisible, so the
    -- icon it targets would just pop straight to its end state the moment the window appears
    local skipAnimation = noAnimation or not self.window:_interactive()

    if not self.neglectSelector then
        if not skipAnimation then
            self:_applyVisual("selected", selectTweenInfo)
        end
        self.window:_updateTabIndicator(self, not skipAnimation)
    end

    for _, tab in self.window.tabs do
        if tab ~= self.window.selectedTab then
            tab:Deselect(skipAnimation)
        end
    end

    if self ~= self.window.rfSettings and self.window.settingsAction and not skipAnimation then
        variables.tweenService
            :Create(
                self.window.settingsAction.iconLabel,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { ImageTransparency = 0.6 }
            )
            :Play()
    end
end

function Tab:Deselect(noAnimation)
    if not self.neglectSelector and not noAnimation then
        self:_applyVisual("unselected", selectTweenInfo)
    end
end

-- shared tail for every CreateX: track it, order it, and reveal it if the window is
-- already open. without this, elements added after Window:Show stay fully transparent.
function Tab:_register(element)
    table.insert(self.elements, element)
    assignOrder(element, #self.elements * 10)
    self.window:_restoreLate(element)

    if not self.window.hidden then
        element:_setShown(true, true)
    end

    return element
end

-- Button
function Tab:CreateButton(properties)
    return self:_register(require(script.Parent.button).new(self, properties))
end

-- Flip button: a two-faced Button whose title flips on hover
function Tab:CreateFlipButton(properties)
    return self:_register(require(script.Parent.flipbutton).new(self, properties))
end

-- Copy button: title left, a checkmark-swapping icon well right that copies to the clipboard
function Tab:CreateCopyButton(properties)
    return self:_register(require(script.Parent.copybutton).new(self, properties))
end

-- Ripple button: a Button whose press feedback is a ripple from the press point
function Tab:CreateRippleButton(properties)
    return self:_register(require(script.Parent.ripplebutton).new(self, properties))
end

-- Switch/Toggle
function Tab:CreateToggle(properties)
    return self:_register(require(script.Parent.toggle).new(self, properties))
end

function Tab:CreateSwitch(properties)
    return self:CreateToggle(properties)
end

-- Checkbox: a compact alternative to Toggle
function Tab:CreateCheckbox(properties)
    return self:_register(require(script.Parent.checkbox).new(self, properties))
end

-- Section
function Tab:CreateSection(properties)
    return self:_register(require(script.Parent.section).new(self, properties))
end

-- Stat
function Tab:CreateStat(properties)
    return self:_register(require(script.Parent.stat).new(self, properties))
end

-- Slider
function Tab:CreateSlider(properties)
    return self:_register(require(script.Parent.slider).new(self, properties))
end

-- Dropdown
function Tab:CreateDropdown(properties)
    return self:_register(require(script.Parent.dropdown).new(self, properties))
end

-- Progress bar: read-only gradient fill + readout, animates on Set
function Tab:CreateProgressBar(properties)
    return self:_register(require(script.Parent.progressbar).new(self, properties))
end

-- Scroll hint: centred text + bouncing arrow, points further down a page
function Tab:CreateScrollHint(properties)
    return self:_register(require(script.Parent.scrollhint).new(self, properties))
end

-- Segmented picker: pill bar with a sliding indicator, segments can nest a couple of sub-options
function Tab:CreateSegmentedPicker(properties)
    return self:_register(require(script.Parent.segmentedpicker).new(self, properties))
end

-- Shimmer label: a big heading with a light band sweeping across the text on a loop
function Tab:CreateShimmerLabel(properties)
    return self:_register(require(script.Parent.shimmerlabel).new(self, properties))
end

-- Input
function Tab:CreateInput(properties)
    return self:_register(require(script.Parent.input).new(self, properties))
end

-- Keybind
function Tab:CreateKeybind(properties)
    return self:_register(require(script.Parent.keybind).new(self, properties))
end

-- Color picker
function Tab:CreateColorPicker(properties)
    return self:_register(require(script.Parent.colorpicker).new(self, properties))
end

-- Gradient picker: a collapsible stops-rail editor producing a real ColorSequence
function Tab:CreateGradientPicker(properties)
    return self:_register(require(script.Parent.gradientpicker).new(self, properties))
end

-- Group (layout container). A row that wraps by default; pass direction="column" for a
-- column. Nest a row of columns for a grid. Add elements via group:CreateX.
function Tab:CreateGroup(properties)
    return self:_register(require(script.Parent.group).new(self, properties))
end

function Tab:_moveElement(element, targetIndex)
    local idx = table.find(self.elements, element)
    if not idx then
        return
    end
    table.remove(self.elements, idx)
    targetIndex = math.clamp(targetIndex, 1, #self.elements + 1)
    table.insert(self.elements, targetIndex, element)
    for i, el in self.elements do
        assignOrder(el, i * 10)
    end
end

function Tab:Remove()
    local window = self.window

    -- search reparents elements into its results page; close it first so this tabs
    -- units go home before their page is destroyed under them
    if window._searching then
        search.close(window, { showTabs = true, jumpTo = window.selectedTab and window.selectedTab.tabPage })
    end

    local idx = table.find(window.tabs, self)
    if idx then
        table.remove(window.tabs, idx)
    end

    -- If this was the active tab, hand selection to the next visible tab
    if window.selectedTab == self then
        window.selectedTab = nil
        for _, tab in ipairs(window.tabs) do
            if not tab.neglectSelector then
                tab:Select()
                break
            end
        end
    end

    -- Tear every element down (flags + connections) so nothing points at, or fires on, what
    -- we're about to destroy. Groups nest, so walk their children too.
    teardownElements(window, self.elements)

    -- Tear down the UI; nil the refs so _applyVisual (which guards on self.topbarItem)
    -- no-ops instead of touching a destroyed instance.
    for _, connection in self.connections do
        window:Disconnect(connection)
    end
    self.connections = {}

    if self.topbarItem then
        window:DestroySubtree(self.topbarItem)
    end
    if self.tabPage then
        window:DestroySubtree(self.tabPage)
    end
    self.topbarItem = nil
    self.tabPage = nil
    self.elements = {}
end

return Tab

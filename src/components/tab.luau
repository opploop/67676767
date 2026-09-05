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
local locale = require(utility.locale)
local assignOrder = require(utility.ordering)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)
local search = require(script.Parent.search)
local tabSelector = require(script.Parent.tabSelector)

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
        locked = properties.locked or properties.Locked or false,

        elements = {},
        connections = {}, -- tracked so Remove can drop them without waiting for Unload
    }, Tab)

    -- a tab needs at least one of a name or an icon to show in the selector
    assert(self.name or self.icon, "A tab needs a name or an icon.")

    if not self.neglectSelector then -- Allow for tabs to be hidden from the tab selector, for Rayfield Settings.
        -- Builds topbarItem/topbarItemInteract/topbarItemStroke/topbarItemShadow/
        -- topbarItemContainer/topbarItemIcon/topbarItemTitle - a row in Sidebar mode, a pill in
        -- Top mode. Ported from upstream Rayfield Gen2 1.2's own tabSelector.luau: each one owns
        -- and fades its own background/stroke/shadow on selection now (see _applyVisual below),
        -- not a single shared pill sliding between them.
        local sidebarTabs = self.window.tabsMode == "Sidebar"
        require(script.Parent.tabSelector).build(self, sidebarTabs)

        -- "New"/"updated" indicator - a small dot pinned to the icon's own top-right corner
        -- rather than a layout sibling, so it tracks the icon's own size for free instead of
        -- needing its own re-position pass every frame. Built hidden and always present when
        -- there's an icon to pin it to, so SetBadge can turn it on any time after the tab exists
        -- (e.g. a hub flagging "Priority System" as updated this patch) without a dev needing to
        -- predict that at CreateTab time.
        if self.topbarItemIcon then
            self.badgeDot = self.window:Create("Frame", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 3, 0, -3),
                Size = UDim2.fromOffset(7, 7),
                BorderSizePixel = 0,
                ZIndex = 3, -- above the icon (2)
                Visible = properties.badge or properties.Badge or false,

                Parent = self.topbarItemIcon,
            }, { BackgroundColor3 = "AccentColor" })
            self.window:Create("UICorner", {
                CornerRadius = UDim.new(1, 0),
                Parent = self.badgeDot,
            })
        end

        -- flows after icon/title via topbarItemContainer's own UIListLayout - the position/
        -- anchor _buildLockIcon takes don't matter here, a list-managed child's Position is
        -- overridden by the layout regardless of what it's created with
        self.lockIcon = self.window:_buildLockIcon(self.topbarItemContainer)
        self:_applyLocked()
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
        -- Devlog 7: the gap under the tab dock read as glued to it (13px measured live) -
        -- widened so the first section/element always gets real breathing room below the dock.
        PaddingTop = UDim.new(0, 22),
        PaddingBottom = UDim.new(0, 33),

        Parent = self.tabPage,
    })

    if not self.neglectSelector then
        table.insert(
            self.connections,
            self.window:Connect(self.topbarItemInteract.MouseButton1Click, function()
                if self.locked then
                    return
                end
                hapticEngine.click()
                soundEngine.click()
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

-- Each row/pill owns and fades its own background/stroke/shadow now - ported from upstream
-- Rayfield Gen2 1.2's own tabSelector.applyVisual, ambient states table included. TabColor stays
-- the text/icon colour throughout (no contrast computation against a shared pill colour needed,
-- since there's no shared pill anymore).
function Tab:_applyVisual(stateName, tweenInfo)
    if self.neglectSelector or not self.topbarItem then
        return
    end

    local mode = if self.window.tabsMode == "Sidebar" then "sidebar" else "top"
    local states = tabSelector.states[mode]
    local state = states[stateName]
    if not state then
        return
    end

    -- locked reads as (at least) unselected-dim no matter which state was actually asked for -
    -- computed here rather than in a separate pass afterward, so there's only ever one tween per
    -- property instead of two racing each other.
    if self.locked and state.content < states.unselected.content then
        state = states.unselected
    end

    tabSelector.applyVisual(self, state, tweenInfo)
end

-- Show/hide the padlock and re-paint with whatever visual is already active, so the dim baked
-- into _applyVisual above takes effect immediately.
function Tab:_applyLocked()
    if self.lockIcon then
        self.lockIcon.Visible = self.locked
    end
    self:_applyVisual(if self.window.selectedTab == self then "selected" else "unselected")
end

function Tab:SetLocked(locked)
    locked = locked and true or false
    if locked == self.locked then
        return
    end
    self.locked = locked
    self:_applyLocked()
end

function Tab:Select(noAnimation)
    -- selecting a tab (e.g. via the settings action) leaves search: bring the strip back,
    -- but let the navigation below pick the page.
    if self.window._searching then
        search.close(self.window, { showTabs = true, jumpTo = false })
    end

    self.window.selectedTab = self
    self.window:_jumpTo(self.tabPage)

    -- Opening a tab is what "new"/"updated" is meant to track - clear the dot the moment the
    -- player actually looks, same as a notification badge on any other app. A dev wanting it to
    -- persist across visits can just call SetBadge(true) again afterward.
    self:SetBadge(false)

    -- noAnimation = initial selection, the pill is still hidden and the window reveal shows it.
    -- a dev calling Navigate/Select before the first Show() hits the same case even without
    -- passing it explicitly - a tween played now would resolve while main is invisible, so the
    -- icon it targets would just pop straight to its end state the moment the window appears
    local skipAnimation = noAnimation or not self.window:_interactive()

    if not self.neglectSelector and not skipAnimation then
        self:_applyVisual("selected", selectTweenInfo)
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

-- Label: a bare line of text, no card - for copy too slight for its own Paragraph
function Tab:CreateLabel(properties)
    return self:_register(require(script.Parent.label).new(self, properties))
end

-- Paragraph: a title + body card, for copy too long to hang off an element as a description
function Tab:CreateParagraph(properties)
    return self:_register(require(script.Parent.paragraph).new(self, properties))
end

-- Divider: a subtle rule (plain, captioned, or spacing-only) that splits a page into groups
-- without a full Section header
function Tab:CreateDivider(properties)
    return self:_register(require(script.Parent.divider).new(self, properties))
end

-- Stat
function Tab:CreateStat(properties)
    return self:_register(require(script.Parent.stat).new(self, properties))
end

-- Compact, collapsible multi-row status widget - see statuscard.luau's own header comment.
function Tab:CreateStatusCard(properties)
    return self:_register(require(script.Parent.statuscard).new(self, properties))
end

-- Slider
function Tab:CreateSlider(properties)
    return self:_register(require(script.Parent.slider).new(self, properties))
end

-- Dropdown
function Tab:CreateDropdown(properties)
    return self:_register(require(script.Parent.dropdown).new(self, properties))
end

-- Dropdown pre-filled with the server's players, kept in step with joins and leaves
function Tab:CreatePlayerDropdown(properties)
    return self:_register(require(script.Parent.playerdropdown).new(self, properties))
end

-- Progress bar: read-only gradient fill + readout, animates on Set
function Tab:CreateProgressBar(properties)
    return self:_register(require(script.Parent.progressbar).new(self, properties))
end

-- A monospaced, self-scrolling block for code or log output. See console.luau's own header
-- comment. Ported from upstream Rayfield Gen2 1.2.
function Tab:CreateConsole(properties)
    return self:_register(require(script.Parent.console).new(self, properties))
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

-- Nested tab switcher - see tabbox.luau's own header comment. Routed through _register like any
-- other element (LayoutOrder among its siblings, late-add reveal if the window's already open) -
-- it has the same main/_setShown shape _register expects even though it carries no flag of its
-- own (each of its own pages' children register their own flags independently).
function Tab:CreateTabbox(properties)
    return self:_register(require(script.Parent.tabbox).new(self, properties))
end

-- Hold button: press-and-hold confirm, fill bar completes the callback only at 100%
function Tab:CreateHoldButton(properties)
    return self:_register(require(script.Parent.holdbutton).new(self, properties))
end

-- Collapsible section: a header that expands/collapses to reveal its own nested elements,
-- built via the same CreateX surface as a Tab or Group (collapsible:CreateToggle, etc).
function Tab:CreateCollapsible(properties)
    return self:_register(require(script.Parent.collapsible).new(self, properties))
end

-- Changelog / update log: a title + version/date header over a list of ADDED/FIXED/CHANGED/
-- REMOVED tagged entries. Static once built.
function Tab:CreateChangelog(properties)
    return self:_register(require(script.Parent.changelog).new(self, properties))
end

-- Spacer: an invisible gap with a configurable height, for custom breathing room between
-- elements/sections.
function Tab:CreateSpacer(properties)
    return self:_register(require(script.Parent.spacer).new(self, properties))
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

-- Public wrapper - lets a consumer script (e.g. one adding its own control onto Rayfield's own
-- Window.rfSettings tab, alongside the built-in toggles) place it at a specific position instead
-- of always landing after everything the tab already had, which is all a plain CreateX call after
-- the fact can ever do.
function Tab:MoveElement(element, targetIndex: number)
    self:_moveElement(element, targetIndex)
end

-- Toggle the "new"/"updated" dot pinned to this tab's icon (see Tab.new). No-ops quietly on a
-- tab built without an icon - there's nowhere for the dot to attach - so a dev flagging several
-- tabs as updated after a patch doesn't need to special-case the icon-less ones.
function Tab:SetBadge(shown: boolean)
    if self.badgeDot then
        self.badgeDot.Visible = shown and true or false
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

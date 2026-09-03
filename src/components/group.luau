--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Group = {}
Group.__index = Group
Group.__type = "Group"

-- A layout container. Lays its children along one axis and nests, so a row of columns
-- gives you a grid. A row wraps when it runs out of width instead of shrinking forever.
-- Mimics the Tab fields components read (window, tabPage, elements, compact, direction,
-- _moveElement) so the exact same element code builds inside it, and flags still register
-- on window.controls through the nesting.
--
-- row    -> children build compact and share the width, wrapping to new rows as needed
-- column -> children build full width, stacked top to bottom
-- The public API calls these "row"/"column"; "horizontal"/"vertical" work too.

local moveable = require(script.Parent.Parent.utility.moveable)
local log = require(script.Parent.Parent.utility.log)
local assignOrder = require(script.Parent.Parent.utility.ordering)

local elementPadding = 8

-- these render fine side by side in a row: the compact builds (button/toggle/stat), the
-- newer compact builds (checkbox/copybutton/flipbutton/ripplebutton/holdbutton), and the slider
-- (it reflows to its narrow layout). Everything else added below (dropdown/section/colorpicker/
-- gradientpicker/input/keybind/progressbar/scrollhint/segmentedpicker/shimmerlabel/changelog/
-- spacer/collapsible) has no compact build of its own and stays full-only, same as
-- Section/Label already did.
local compactCapable = {
    button = true,
    toggle = true,
    stat = true,
    slider = true,
    checkbox = true,
    copybutton = true,
    flipbutton = true,
    ripplebutton = true,
    holdbutton = true,
}

function Group.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local dir = string.lower(properties.direction or properties.Direction or "row")
    local vertical = dir == "column" or dir == "vertical"
    local horizontal = not vertical
    local direction = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"), -- host: a Tab or a parent Group
        window = tab.window,
        direction = direction,
        compact = horizontal, -- row children pack side by side
        forgetState = tab.forgetState, -- inherit the host's config-persistence stance
        elements = {},
        -- assume shown until _setShown says otherwise (a group built before the window's first
        -- reveal has nothing to conflict with yet)
        _windowWantsShown = true,
    }, Group)

    -- Dependency group: dependsOn is anything with a .value and a .callback (a toggle, a
    -- dropdown, a checkbox, ...) - every element type already stores its user callback under
    -- that name and invokes it uniformly, so wrapping it is a generic hook that works across all
    -- of them without each element needing its own "value changed" signal. condition defaults to
    -- a plain truthy check (built for a toggle); pass one explicitly for a dropdown/slider-driven
    -- group (e.g. function(v) return v == "Advanced" end).
    local dependsOn = properties.dependsOn or properties.DependsOn
    if dependsOn then
        self._dependsOn = dependsOn
        self._condition = properties.condition or properties.Condition or function(value)
            return value == true
        end

        local originalCallback = dependsOn.callback
        dependsOn.callback = function(...)
            if originalCallback then
                originalCallback(...)
            end
            self:_applyDependency(true)
        end
    end

    -- if our host is a row we're a column, so we hand our width to its flex
    local nestedInRow = tab.direction == Enum.FillDirection.Horizontal

    self.main = self.window:Create("Frame", {
        Name = "Group",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        -- row matches a normal element's inset (1,-20). column is full width so its
        -- full-build children (1,-20) line up with the rest of the tab.
        Size = if horizontal then UDim2.new(1, -20, 0, 0) else UDim2.new(1, 0, 0, 0),

        Parent = self.tab.tabPage,
    })

    if nestedInRow then
        -- let the parent row divide its width between columns
        self.main.Size = UDim2.new(0, 0, 0, 0)
        self.window:Create("UIFlexItem", {
            FlexMode = Enum.UIFlexMode.Fill,
            Parent = self.main,
        })
    end

    -- children parent here
    self.tabPage = self.main

    self.layout = self.window:Create("UIListLayout", {
        FillDirection = direction,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, elementPadding),
        VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
        HorizontalAlignment = if horizontal then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,

        Parent = self.main,
    })

    return self
end

function Group:_add(componentName, properties)
    if self.compact and not compactCapable[componentName] then
        log.warn(
            `Rayfield: a row only holds compact elements `
                .. `(button/toggle/stat/slider/checkbox/copybutton/flipbutton/ripplebutton), `
                .. `ignoring '{componentName}'. Use a column for it.`
        )
        return nil
    end

    local element = require(script.Parent[componentName]).new(self, properties)
    table.insert(self.elements, element)
    assignOrder(element, #self.elements * 10)
    self.window:_restoreLate(element)

    if self.compact then
        self:_wrapChild(element)
    end
    self:_reflowRow() -- a leaf landing in a row of columns has to widen the gap back out

    -- same as Tab:_register: elements added after Window:Show must be revealed here
    -- or they stay fully transparent
    if not self.window.hidden then
        element:_setShown(self:_actualShown(true), true)
    end

    return element
end

-- true if `shown` should actually render given self._dependsOn's current value - shared by
-- _add's own late-reveal above and _setShown/_applyDependency below, so all three agree on the
-- same logic rather than each re-deriving it slightly differently.
function Group:_actualShown(shown)
    if not self._dependsOn then
        return shown
    end
    return shown and self._condition(self._dependsOn.value)
end

-- Re-applies the dependency condition against whatever self._dependsOn.value currently is,
-- against self._windowWantsShown (whatever _setShown last set) rather than assuming the window
-- is up - the wrapped callback below can fire from a control changed while the window itself is
-- hidden or mid-reveal, and this must not fight that.
function Group:_applyDependency(animate)
    local shown = self:_actualShown(self._windowWantsShown)
    for _, el in self.elements do
        el:_setShown(shown, animate)
    end
end

-- Padding is one property for the whole row, so it has to suit whatever the row ends up
-- holding. Columns carry their own 10px side margin (the 1,-20), so where two meet the gutter
-- is 10+10=20, twice the 10px outer margin - pull them together by one margin's worth to match.
-- Leaves carry no margin, so the same pull would just overlap them: a row holding any leaf
-- keeps the leaf gap and lets the columns sit a touch wider apart.
function Group:_reflowRow()
    if self.direction ~= Enum.FillDirection.Horizontal then
        return
    end

    local onlyGroups = #self.elements > 0
    for _, element in self.elements do
        if element.__type ~= "Group" then
            onlyGroups = false
            break
        end
    end

    self.layout.Padding = if onlyGroups then UDim.new(0, -10) else UDim.new(0, elementPadding)
end

-- A row wraps instead of shrinking forever. Each child is frozen to the width it actually
-- needs (element:_minWidth counts its icon, text, control + padding), so the row breaks on
-- real bounds, and HorizontalFlex grows each row's items to fill it.
function Group:_wrapChild(element)
    self.layout.Wraps = true
    self.layout.HorizontalFlex = Enum.UIFlexAlignment.Fill

    -- tells a width-owning element (the slider) that we drive its width now, so its own
    -- reflow stops fighting us. plain compact elements ignore the flag.
    element._widthManaged = true

    local minWidth = if element._minWidth then element:_minWidth() else 0
    if minWidth > 0 then
        element.main.AutomaticSize = Enum.AutomaticSize.None
        element.main.Size = UDim2.new(0, minWidth, element.main.Size.Y.Scale, element.main.Size.Y.Offset)
    end
end

function Group:CreateButton(properties)
    return self:_add("button", properties)
end
function Group:CreateFlipButton(properties)
    return self:_add("flipbutton", properties)
end
function Group:CreateCopyButton(properties)
    return self:_add("copybutton", properties)
end
function Group:CreateRippleButton(properties)
    return self:_add("ripplebutton", properties)
end
function Group:CreateToggle(properties)
    return self:_add("toggle", properties)
end
function Group:CreateSwitch(properties)
    return self:_add("toggle", properties)
end
function Group:CreateCheckbox(properties)
    return self:_add("checkbox", properties)
end
function Group:CreateStat(properties)
    return self:_add("stat", properties)
end
function Group:CreateSlider(properties)
    return self:_add("slider", properties)
end
function Group:CreateDropdown(properties)
    return self:_add("dropdown", properties)
end
function Group:CreateSection(properties)
    return self:_add("section", properties)
end
function Group:CreateLabel(properties)
    return self:_add("label", properties)
end
function Group:CreateParagraph(properties)
    return self:_add("paragraph", properties)
end
function Group:CreateDivider(properties)
    return self:_add("divider", properties)
end
function Group:CreateProgressBar(properties)
    return self:_add("progressbar", properties)
end
function Group:CreateScrollHint(properties)
    return self:_add("scrollhint", properties)
end
function Group:CreateSegmentedPicker(properties)
    return self:_add("segmentedpicker", properties)
end
function Group:CreateShimmerLabel(properties)
    return self:_add("shimmerlabel", properties)
end
function Group:CreateInput(properties)
    return self:_add("input", properties)
end
function Group:CreateKeybind(properties)
    return self:_add("keybind", properties)
end
function Group:CreateColorPicker(properties)
    return self:_add("colorpicker", properties)
end
function Group:CreateGradientPicker(properties)
    return self:_add("gradientpicker", properties)
end
function Group:CreateHoldButton(properties)
    return self:_add("holdbutton", properties)
end
function Group:CreateChangelog(properties)
    return self:_add("changelog", properties)
end
function Group:CreateSpacer(properties)
    return self:_add("spacer", properties)
end
function Group:CreateTabbox(properties)
    return self:_add("tabbox", properties)
end

-- Collapsible reads window/tabPage/forgetState off whatever host it's given (see its own header
-- comment - same minimal contract Tabbox's fake-host trick relies on), so a Group already
-- satisfies it with no changes needed there. Not compact-capable (a collapsible's header/chevron
-- and its own expanding content don't fit a row's inline layout), so this only actually works
-- inside a column - exactly like CreateSection/CreateLabel above. That's what makes two
-- independently-expanding "Basic"/"Advanced" panels side by side possible: a row of two columns,
-- one CreateCollapsible each.
function Group:CreateCollapsible(properties)
    return self:_add("collapsible", properties)
end

-- a nested group: a column (for a grid) or another row inside this one
function Group:_addGroup(properties)
    properties = if typeof(properties) == "table" then table.clone(properties) else {}

    -- adapt a row that's about to hold columns instead of compact leaves:
    if self.direction == Enum.FillDirection.Horizontal then
        -- top-align, not centre: a column growing (e.g. a dropdown opening) must push down,
        -- not re-centre and shove the other column around.
        self.layout.VerticalAlignment = Enum.VerticalAlignment.Top
        -- full width (unless we're ourselves a nested column sharing a parent's flex) so
        -- column content lines up with the tab's normal elements instead of sitting 10px in.
        if self.tab.direction ~= Enum.FillDirection.Horizontal then
            self.main.Size = UDim2.new(1, 0, 0, 0)
        end
    end

    local group = Group.new(self, properties)
    table.insert(self.elements, group)
    group.main.LayoutOrder = #self.elements * 10
    self:_reflowRow()
    return group
end

function Group:CreateGroup(properties)
    return self:_addGroup(properties)
end

-- reorder a child within this group
function Group:_moveElement(element, targetIndex)
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

-- children live in group.elements, not tab.elements, so forward the reveal down.
-- nested groups forward it again, so a whole grid reveals in one call. Remembers `shown` as
-- self._windowWantsShown regardless of _dependsOn, so a later dependency change (the wrapped
-- callback calling _applyDependency) knows whether the window even wants this group up at all,
-- not just the condition's own state.
function Group:_setShown(shown, animate)
    self._windowWantsShown = shown
    local actual = self:_actualShown(shown)
    for _, el in self.elements do
        el:_setShown(actual, animate)
    end
end

-- same reason: forward a runtime theme refresh down to the children (nested groups recurse).
function Group:_refreshTheme()
    for _, el in self.elements do
        if el._refreshTheme then
            el:_refreshTheme()
        end
    end
end

-- reorder the group within its host
moveable(Group)

return Group

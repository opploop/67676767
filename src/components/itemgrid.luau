--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A scrolling grid of selectable cards - a cosmetic picker, an item filter, a loadout screen.
-- The long-list case a Dropdown handles badly: a few hundred entries the player wants to SEE and
-- tick several of, not open a menu and hunt through one at a time.
--
-- The search box and the filter chips live INSIDE the element rather than being separate controls
-- a hub wires up itself: the filter only ever drives this one grid, so making the caller own a
-- CreateInput, remember to call grid:Filter from its callback, and keep a chip row in sync was
-- three places to get wrong for something with exactly one correct behaviour. `search = true` and
-- `filters = { ... }` turn them on; the dev supplies the tag set, since only they know whether
-- the axis is rarity, slot, or source.
--
-- Selection is the value: `flag` persists the ticked ids like any other control.

local ItemGrid = {}
ItemGrid.__index = ItemGrid
ItemGrid.__type = "ItemGrid"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local lockable = require(utility.lockable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local sidePadding = 15
local headerTop = 15
local headerHeight = 16
local headerGap = 12
local rowGap = 8
local searchHeight = 32
local chipHeight = 26
local chipRowHeight = 30 -- chipHeight plus the padding that gives its strokes room
local chipGap = 6
local quickRowHeight = 16 -- the bare text buttons have no fill, so this is just the line box
local chipPadding = 12
local cellGap = 10
-- A UIStroke is drawn OUTSIDE its frame's bounds, so a cell flush against the scrolling frame's
-- edge has its outline clipped away on that side - most visible on the accent stroke a selected
-- card wears. Inset the canvas by more than the thickness and every edge has room to draw.
local strokeInset = 3
local boxSize = 18
local dotSize = 7
local defaultColumns = 4
local defaultHeight = constants.listMaxHeight -- shared with ListPicker
local emptyRoom = 28 -- the panel a grid keeps when it has nothing to show, for the empty label
local defaultCellHeight = 56
local stackedCellHeight = 128 -- room for a thumbnail plus its name underneath

-- Below this a card can't hold a two-word name, so the grid drops a column instead of letting
-- every label truncate. Checked against the real width, so a collapsed window reflows.
--
-- Sized off what's actually left for the name, not the card: the tick, the rarity dot and the
-- padding eat ~60px before a letter is drawn, so a 132px card left 73px of text and broke
-- "Evil Beastmaster" across three crammed lines. Readable beats dense - a narrow window gets
-- two proper columns rather than three unreadable ones.
local minCellWidth = 148

local stateInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local cellRest = 0.94
local cellHover = 0.88

-- Accepts "Banana", or { id, name, icon, image, color, tag }. A bare string is its own id.
local function normalise(entry)
    if type(entry) == "string" then
        return { id = entry, name = entry }
    elseif type(entry) == "table" then
        local id = entry.id or entry.Id or entry.name or entry.Name
        if id == nil then
            return nil
        end
        return {
            id = tostring(id),
            name = tostring(entry.name or entry.Name or id),
            icon = entry.icon or entry.Icon,
            image = entry.image or entry.Image,
            color = entry.color or entry.Color,
            tag = entry.tag or entry.Tag,
        }
    end
    return nil
end

-- A filter chip: { tag = "LEGENDARY", color = ..., name = "Legendary" }, or just the tag string
-- when the dev is happy with the tag as its own label.
local function normaliseFilter(entry)
    if type(entry) == "string" then
        return { tag = entry, name = entry }
    elseif type(entry) == "table" then
        local tag = entry.tag or entry.Tag or entry.name or entry.Name
        if tag == nil then
            return nil
        end
        return {
            tag = tostring(tag),
            name = tostring(entry.name or entry.Name or tag),
            color = entry.color or entry.Color,
        }
    end
    return nil
end

function ItemGrid.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local search = properties.search
    if search == nil then
        search = properties.Search
    end

    local imageLayout = string.lower(tostring(properties.imageLayout or properties.ImageLayout or "left"))
    if imageLayout ~= "top" then
        imageLayout = "left"
    end

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Items",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        columns = math.clamp(tonumber(properties.columns or properties.Columns) or defaultColumns, 1, 8),
        -- The ceiling. `maxHeight` is the name that says what it does; `height` is the original
        -- spelling and still works, since a ceiling is what it always meant here.
        height = math.max(
            tonumber(properties.maxHeight or properties.MaxHeight or properties.height or properties.Height)
                or defaultHeight,
            80
        ),
        imageLayout = imageLayout,
        multiSelect = functions.readBool(properties, "multiSelect", true),
        -- The "Select all / Clear" line above the grid. On by default, because a multi-select
        -- grid of any size wants it, but it does cost a row of height in a small grid that does
        -- not - unlike Dropdown's, this element is always on the page rather than in a panel.
        quickActions = functions.readBool(properties, "quickActions", true),
        -- A cap on a multi-select grid: "pick up to 3 of these 40". nil means no cap, and it is
        -- meaningless on a single-select grid (multiSelect = false is already a cap of one).
        maxSelected = (function()
            local max = tonumber(properties.maxSelected or properties.MaxSelected)
            return if max and max >= 1 then math.floor(max) else nil
        end)(),
        -- A standing restriction ANDed with every other filter, and the piece `Filter` could not
        -- express: a predicate passed to Filter REPLACES the text/tag matching and is cleared the
        -- moment the player types (deliberately - see the search input's own handler). A scope is
        -- the opposite intent, "these are the only rows that exist for this player at all", so it
        -- survives typing and composes with it. Keep them as two slots rather than one.
        scopeFilter = if type(properties.scope or properties.Scope) == "function"
            then properties.scope or properties.Scope
            else nil,
        emptyText = properties.emptyText or properties.EmptyText or "Nothing matches that filter.",

        -- `search = true` for the default placeholder, or pass the placeholder string itself
        searchEnabled = search ~= nil and search ~= false,
        searchPlaceholder = if type(search) == "string" then search else "Search",

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Items")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,
        onFilterChanged = properties.onFilterChanged or properties.OnFilterChanged,

        entries = {},
        cells = {}, -- keyed by id
        chips = {}, -- keyed by tag
        filters = {}, -- ordered chip descriptors
        selected = {}, -- id -> true
        activeTags = {}, -- tag -> true; empty means "every tag"
        searchText = "",
        customFilter = nil,
        value = {},
    }, ItemGrid)

    self.cellHeight = math.max(
        tonumber(properties.cellHeight or properties.CellHeight)
            or (if imageLayout == "top" then stackedCellHeight else defaultCellHeight),
        30
    )

    -- the author's column count is the ceiling; a narrow window only ever drops below it
    self.requestedColumns = self.columns

    for _, entry in (properties.items or properties.Items or {}) do
        local normalised = normalise(entry)
        if normalised then
            table.insert(self.entries, normalised)
        end
    end

    for _, entry in (properties.filters or properties.Filters or {}) do
        local normalised = normaliseFilter(entry)
        if normalised then
            table.insert(self.filters, normalised)
        end
    end

    self.window:_registerControl(self)
    self:_build()
    self:_rebuildCells()

    local initial = functions.readValue(properties, { "value", "Value" })
    if initial ~= nil then
        self:Set(initial, true)
    end

    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

-- Where the grid starts, once the header and whichever filter rows exist are accounted for.
function ItemGrid:_gridTop(): number
    local top = headerTop + headerHeight + headerGap
    if self.searchEnabled then
        top += searchHeight + rowGap
    end
    if #self.filters > 0 then
        top += chipRowHeight + rowGap
    end
    if self.quickActions then
        top += quickRowHeight + rowGap
    end
    return top
end

function ItemGrid:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 60),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.new(0, sidePadding, 0, headerTop),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.main,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.new(1, -(sidePadding * 2 + 70), 0, headerHeight),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.new(0, sidePadding + (if self.icon then 21 else 0), 0, headerTop),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- "3 / 48" - the one number a picker this size is always asked for
    self.counter = window:Create("TextLabel", {
        Text = "",
        Size = UDim2.fromOffset(70, headerHeight),
        Position = UDim2.new(1, -sidePadding, 0, headerTop),
        AnchorPoint = Vector2.new(1, 0),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,

        TextTransparency = 1, -- In = 0.45

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    local nextTop = headerTop + headerHeight + headerGap

    if self.searchEnabled then
        self:_buildSearch(nextTop)
        nextTop += searchHeight + rowGap
    end
    if #self.filters > 0 then
        self:_buildChips(nextTop)
        nextTop += chipRowHeight + rowGap
    end
    if self.quickActions then
        -- last in the stack, immediately above the grid: both buttons act on what is currently
        -- VISIBLE, which is the result of the search box AND the chips together, so sitting
        -- directly on top of that result is what makes the relationship readable. With no chips
        -- (the common case) that is the row straight under the search box.
        self:_buildQuickActions(nextTop)
        nextTop += quickRowHeight + rowGap
    end

    self.scroll = window:Create("ScrollingFrame", {
        Name = "Grid",
        Size = UDim2.new(1, -(sidePadding * 2), 0, self.height),
        Position = UDim2.new(0, sidePadding, 0, nextTop),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.6,
        ScrollingDirection = Enum.ScrollingDirection.Y,

        Parent = self.main,
    }, { ScrollBarImageColor3 = "ContentColor" })

    -- room for the outward stroke on the cells that sit against each edge
    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, strokeInset),
        PaddingRight = UDim.new(0, strokeInset),
        PaddingTop = UDim.new(0, strokeInset),
        PaddingBottom = UDim.new(0, strokeInset),

        Parent = self.scroll,
    })

    self.gridLayout = window:Create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(cellGap, cellGap),
        CellSize = UDim2.fromOffset(100, self.cellHeight), -- real size set by _applyColumns
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirectionMaxCells = self.columns,

        Parent = self.scroll,
    })

    self.emptyLabel = window:Create("TextLabel", {
        Text = locale.t(self.emptyText),
        Size = UDim2.new(1, -(sidePadding * 2), 0, 20),
        Position = UDim2.new(0, sidePadding, 0, nextTop + 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Visible = false,

        TextTransparency = 1, -- In = 0.55

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- Reflow when the real width changes: the author's column count is a ceiling, and a
    -- collapsed window drops below it rather than truncating every label.
    self.window:ConnectFor(self, self.scroll:GetPropertyChangedSignal("AbsoluteSize"), function()
        self:_applyColumns()
    end)
    self:_applyColumns()
end

function ItemGrid:_buildSearch(top)
    local window = self.window

    self.searchBox = window:Create("Frame", {
        Name = "Search",
        Size = UDim2.new(1, -(sidePadding * 2), 0, searchHeight),
        Position = UDim2.new(0, sidePadding, 0, top),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = FieldTransparency

        Parent = self.main,
    }, { BackgroundColor3 = "FieldBackground" })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.searchBox })

    self.searchIcon = window:Create("ImageLabel", {
        Image = constants.icons.search,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, 11, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        ImageTransparency = 1, -- In = 0.5

        Parent = self.searchBox,
    }, { ImageColor3 = "ContentColor" })

    self.searchInput = window:Create("TextBox", {
        Text = "",
        PlaceholderText = locale.t(self.searchPlaceholder),
        Size = UDim2.new(1, -44, 1, 0),
        Position = UDim2.new(0, 33, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,

        TextTransparency = 1, -- In = 0.15

        Parent = self.searchBox,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    self.window:ConnectFor(self, self.searchInput:GetPropertyChangedSignal("Text"), function()
        if self.locked then
            return
        end
        self.searchText = self.searchInput.Text
        self.customFilter = nil -- typing overrides a predicate a caller set programmatically
        self:_applyFilter()
    end)
end

function ItemGrid:_buildChips(top)
    local window = self.window

    -- A horizontal scroller rather than a wrapping layout: a dev can define ten tags, and the row
    -- has to stay one row tall whatever they define (the shape tabbox's own pill row uses).
    self.chipRow = window:Create("ScrollingFrame", {
        Name = "Filters",
        Size = UDim2.new(1, -(sidePadding * 2), 0, chipRowHeight),
        Position = UDim2.new(0, sidePadding, 0, top),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,

        Parent = self.main,
    })

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 2),
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 2),

        Parent = self.chipRow,
    })

    self.chipLayout = window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, chipGap),
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.chipRow,
    })

    for order, descriptor in self.filters do
        self.chips[descriptor.tag] = self:_buildChip(descriptor, order)
    end
end

function ItemGrid:_buildChip(descriptor, order)
    local window = self.window
    local chip = { descriptor = descriptor }

    local width = functions.textWidth(window.theme.Font, 13, descriptor.name) + chipPadding * 2

    chip.frame = window:Create("Frame", {
        Name = descriptor.tag,
        LayoutOrder = order,
        Size = UDim2.fromOffset(math.ceil(width), chipHeight),
        BackgroundColor3 = descriptor.color or Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = inactive

        Parent = self.chipRow,
    })
    -- offset, not UDim.new(1, 0): a scale radius on a pill leaves the Border-mode stroke with
    -- visible seams where it wraps the fully-rounded ends
    window:Create("UICorner", { CornerRadius = UDim.new(0, math.floor(chipHeight / 2)), Parent = chip.frame })

    chip.stroke = window:Create("UIStroke", {
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = descriptor.color or Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- In = inactive

        Parent = chip.frame,
    })

    chip.title = window:Create("TextLabel", {
        Text = locale.t(descriptor.name),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,

        TextTransparency = 1, -- In = inactive

        Parent = chip.frame,
    }, { FontFace = "Font" })
    chip.title.TextColor3 = descriptor.color or window.theme.ContentColor

    chip.interact = window:Create("TextButton", {
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = chip.frame,
    })

    self.window:ConnectFor(self, chip.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        self:ToggleTag(descriptor.tag)
    end)

    return chip
end

function ItemGrid:_applyChip(chip, animate)
    local active = self.activeTags[chip.descriptor.tag] == true
    local color = chip.descriptor.color or self.window.theme.ContentColor

    local goals = {
        frame = { BackgroundTransparency = if active then 0.75 else 1 },
        stroke = { Transparency = if active then 0.15 else 0.65 },
        title = { TextColor3 = color, TextTransparency = if active then 0 else 0.35 },
    }

    for part, properties in goals do
        if animate then
            variables.tweenService:Create(chip[part], stateInfo, properties):Play()
        else
            for property, value in properties do
                chip[part][property] = value
            end
        end
    end
end

-- Fit `columns` cells across the real width, dropping columns while they'd come out too narrow.
function ItemGrid:_applyColumns()
    -- AbsoluteWindowSize, not AbsoluteSize: the latter counts the vertical scrollbar's strip, so
    -- sizing cells off it pushes the last column past the card's rounded edge by exactly
    -- ScrollBarThickness the moment the content becomes long enough to scroll.
    local width = self.scroll.AbsoluteWindowSize.X
    if width <= 0 then
        width = self.scroll.AbsoluteSize.X - self.scroll.ScrollBarThickness
    end
    width -= strokeInset * 2 -- the UIPadding above; cells lay out inside it
    if width <= 0 then
        return
    end

    local columns = self.requestedColumns
    while columns > 1 and (width - cellGap * (columns - 1)) / columns < minCellWidth do
        columns -= 1
    end

    local cellWidth = math.floor((width - cellGap * (columns - 1)) / columns)
    local columnsChanged = self.columns ~= columns
    self.columns = columns
    self.gridLayout.FillDirectionMaxCells = columns
    self.gridLayout.CellSize = UDim2.fromOffset(cellWidth, self.cellHeight)

    -- Fewer columns means more rows means a taller grid. Guarded on an actual change: _syncHeight
    -- writes scroll.Size, which re-fires the AbsoluteSize listener that called us, and an
    -- unguarded call would bounce between the two every frame.
    if columnsChanged and self._built then
        self:_syncHeight()
    end
end

function ItemGrid:_cellConnect(cell, signal, handler)
    table.insert(cell.connections, self.window:ConnectFor(self, signal, handler))
end

-- Bare text buttons rather than filled ones, matching Dropdown's own quick-action row (see
-- dropdown.luau's _buildQuickActions) so the two pickers read the same. "Select all" is
-- multi-select only; "Clear" is useful either way, as a one-tap way to empty the selection
-- without hunting for whichever card is ticked.
function ItemGrid:_buildQuickActions(top)
    local window = self.window

    self.quickRow = window:Create("Frame", {
        Name = "QuickActions",
        Size = UDim2.new(1, -(sidePadding * 2), 0, quickRowHeight),
        Position = UDim2.new(0, sidePadding, 0, top),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 14),
        VerticalAlignment = Enum.VerticalAlignment.Center,

        Parent = self.quickRow,
    })

    local function buildAction(text, order, onClick)
        local button = window:Create("TextButton", {
            Text = locale.t(text),
            Size = UDim2.fromOffset(0, quickRowHeight),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = false,
            LayoutOrder = order,

            TextTransparency = 1, -- In = 0.35

            Parent = self.quickRow,
        }, { TextColor3 = "PlaceholderColor" })

        local hover = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        window:ConnectFor(self, button.MouseEnter, function()
            if self.locked or not window:_interactive() then
                return
            end
            variables.tweenService:Create(button, hover, { TextColor3 = window.theme.ElementTextHoverColor }):Play()
        end)
        window:ConnectFor(self, button.MouseLeave, function()
            variables.tweenService:Create(button, hover, { TextColor3 = window.theme.PlaceholderColor }):Play()
        end)
        window:ConnectFor(self, button.MouseButton1Click, function()
            if self.locked then
                return
            end
            hapticEngine.click()
            soundEngine.click()
            onClick()
        end)

        return button
    end

    if self.multiSelect then
        self.selectAllButton = buildAction("Select all", 1, function()
            self:SelectAll()
        end)
    end
    self.clearButton = buildAction("Clear", 2, function()
        self:Clear()
    end)
end

function ItemGrid:_buildCell(entry, order)
    local window = self.window
    local cell = { connections = {}, entry = entry }
    cell.stacked = self.imageLayout == "top" and entry.image ~= nil

    cell.frame = window:Create("Frame", {
        Name = entry.name,
        LayoutOrder = order,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = cellRest

        Parent = self.scroll,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = cell.frame })

    -- Neutral, like every other card in the library. The rarity is NOT this stroke: a coloured
    -- outline around every card is loud at a glance and, on ApplyStrokeMode.Border, is drawn
    -- OUTSIDE the frame's bounds - so it bled over the neighbouring cell, past the panel's own
    -- rounded edge, and broke visibly at the corners. The colour lives on a dot instead, which
    -- has no geometry to fight. Leaving ApplyStrokeMode at its default keeps this identical to
    -- StyleElementBody's own stroke.
    cell.stroke = window:Create("UIStroke", {
        Thickness = 1,

        Transparency = 1, -- In = the unselected edge

        Parent = cell.frame,
    }, { Color = "ElementStroke" })

    -- The rarity/category, as a dot rather than an outline.
    cell.dot = window:Create("Frame", {
        Name = "Rarity",
        Size = UDim2.fromOffset(dotSize, dotSize),
        BackgroundColor3 = entry.color or Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Visible = entry.color ~= nil,

        BackgroundTransparency = 1, -- In = 0.05

        Parent = cell.frame,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cell.dot })

    if entry.image then
        cell.image = window:Create("ImageLabel", {
            Name = "Preview",
            Image = entry.image,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Fit, -- never distort a cosmetic's proportions

            ImageTransparency = 1, -- In = 0

            Parent = cell.frame,
        })
        -- rounds itself rather than relying on the card clipping it: ClipsDescendants on a card
        -- that also carries a UIStroke is what chewed the corners up
        window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = cell.image })
    end

    cell.box = window:Create("Frame", {
        Name = "Box",
        Size = UDim2.fromOffset(boxSize, boxSize),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1,

        Parent = cell.frame,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = cell.box })

    cell.boxStroke = window:Create("UIStroke", {
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- In = 0.7

        Parent = cell.box,
    })

    cell.check = window:Create("ImageLabel", {
        Image = constants.icons.check,
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        ImageTransparency = 1,

        Parent = cell.box,
    })

    cell.title = window:Create("TextLabel", {
        Text = locale.t(entry.name),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 1, -- In = 0.1

        Parent = cell.frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    if entry.icon and not entry.image then
        cell.iconLabel = window:Create("ImageLabel", {
            Image = entry.icon,
            Size = UDim2.fromOffset(16, 16),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = 0.2

            Parent = cell.frame,
        }, { ImageColor3 = "ContentColor" })
    end

    cell.interact = window:Create("TextButton", {
        Name = "Interact",
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = cell.frame,
    })

    self:_layoutCell(cell)

    self:_cellConnect(cell, cell.interact.MouseEnter, function()
        cell.hovered = true
        if not self.locked then
            self:_applyCell(cell, true)
        end
    end)
    self:_cellConnect(cell, cell.interact.MouseLeave, function()
        cell.hovered = false
        self:_applyCell(cell, true)
    end)
    self:_cellConnect(cell, cell.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        self:Toggle(entry.id)
    end)

    return cell
end

-- Places the parts inside one card. Two shapes: a row (tick, optional thumbnail, name) and a
-- stacked card (thumbnail filling the top, tick floating in its corner, name underneath).
function ItemGrid:_layoutCell(cell)
    if cell.stacked then
        local nameHeight = 28
        cell.image.Size = UDim2.new(1, -20, 1, -(nameHeight + 20))
        cell.image.Position = UDim2.new(0.5, 0, 0, 10)
        cell.image.AnchorPoint = Vector2.new(0.5, 0)

        -- floats over the thumbnail's corner, so it needs to outrank it explicitly: this
        -- project's ZIndexBehavior is Global, so a child does not inherit its parent's order
        cell.box.Position = UDim2.new(1, -8, 0, 8)
        cell.box.AnchorPoint = Vector2.new(1, 0)
        cell.box.ZIndex = 4
        cell.boxStroke.ZIndex = 4
        cell.check.ZIndex = 5
        cell.interact.ZIndex = 6

        local nameLeft = 10
        if cell.dot.Visible then
            cell.dot.Position = UDim2.new(0, nameLeft, 1, -(nameHeight / 2) - 8)
            cell.dot.AnchorPoint = Vector2.new(0, 0.5)
            cell.dot.ZIndex = 4
            nameLeft += dotSize + 7
        end

        cell.title.Size = UDim2.new(1, -(nameLeft + 10), 0, nameHeight)
        cell.title.Position = UDim2.new(0, nameLeft, 1, -8)
        cell.title.AnchorPoint = Vector2.new(0, 1)
        return
    end

    cell.box.Position = UDim2.new(0, 11, 0.5, 0)
    cell.box.AnchorPoint = Vector2.new(0, 0.5)

    local left = 11 + boxSize + 9

    if cell.image then
        local thumb = math.max(self.cellHeight - 18, 16)
        cell.image.Size = UDim2.fromOffset(thumb, thumb)
        cell.image.Position = UDim2.new(0, left, 0.5, 0)
        cell.image.AnchorPoint = Vector2.new(0, 0.5)
        left += thumb + 10
    elseif cell.iconLabel then
        cell.iconLabel.Position = UDim2.new(0, left, 0.5, 0)
        left += 22
    end

    if cell.dot.Visible then
        cell.dot.Position = UDim2.new(0, left, 0.5, 0)
        cell.dot.AnchorPoint = Vector2.new(0, 0.5)
        left += dotSize + 6
    end

    cell.title.Size = UDim2.new(1, -(left + 11), 1, -8)
    cell.title.Position = UDim2.new(0, left, 0.5, 0)
    cell.title.AnchorPoint = Vector2.new(0, 0.5)
end

-- One place that decides what a cell looks like, so hover/selection/theme can't disagree.
function ItemGrid:_applyCell(cell, animate)
    local theme = self.window.theme
    local isSelected = self.selected[cell.entry.id] == true

    local goals = {
        frame = { BackgroundTransparency = if cell.hovered then cellHover else cellRest },
        stroke = {
            Color = if isSelected then theme.AccentStroke else theme.ElementStroke,
            Transparency = if isSelected then 0.15 else 0.85,
        },
        dot = { BackgroundTransparency = if isSelected then 0 else 0.15 },
        box = {
            BackgroundColor3 = if isSelected then theme.AccentColor else theme.ToggleKnobOff,
            BackgroundTransparency = if isSelected then 0 else theme.ToggleKnobOffTransparency,
        },
        boxStroke = {
            Color = if isSelected then theme.AccentStroke else Color3.fromRGB(255, 255, 255),
            Transparency = if isSelected then 0 else 0.7,
        },
        check = { ImageTransparency = if isSelected then 0 else 1 },
        title = {
            TextColor3 = if isSelected then theme.AccentStroke else theme.ContentColor,
            TextTransparency = if isSelected then 0 else 0.1,
        },
    }

    for part, properties in goals do
        if animate then
            variables.tweenService:Create(cell[part], stateInfo, properties):Play()
        else
            for property, value in properties do
                cell[part][property] = value
            end
        end
    end
end

function ItemGrid:_selectedCount(): number
    local count = 0
    for _ in self.selected do
        count += 1
    end
    return count
end

-- Replace the standing scope. nil drops it. Re-filters immediately, so a scope narrowed while
-- rows are on screen takes effect without waiting for the next Refresh.
function ItemGrid:SetScope(predicate)
    self.scopeFilter = if type(predicate) == "function" then predicate else nil
    self:_applyFilter()
end

function ItemGrid:_syncValue()
    -- ordered by the item list, not by click order: a persisted selection should round-trip to
    -- the same array regardless of which order the player happened to tick things in
    local ids = {}
    for _, entry in self.entries do
        if self.selected[entry.id] then
            table.insert(ids, entry.id)
        end
    end
    self.value = ids

    -- The counter describes what is ON SCREEN: ticked-and-visible / visible.
    --
    -- It used to read selected / TOTAL, so narrowing a fully ticked 24-item grid to three
    -- categories kept saying "24 / 24" - describing cards the player could no longer see. Reported
    -- live. Counting the screen fixes that and still avoids the lie the total was guarding against
    -- (a filter down to two cards with two hidden ticks now reads "0 / 2", not "2 / 2").
    --
    -- Ticks the filter or scope hides are deliberately not shown in the counter: a "· N hidden"
    -- suffix was tried and rejected as clutter in the header. They are still kept, still saved,
    -- and reappear ticked when the filter lifts.
    --
    -- With a cap the denominator is the cap and the numerator is EVERY tick, since every tick
    -- uses a slot - "how many picks are left" is the number a capped player needs.
    local visible, visibleTicked = 0, 0
    for _, entry in self.entries do
        if self:_matches(entry) then
            visible += 1
            if self.selected[entry.id] then
                visibleTicked += 1
            end
        end
    end

    self.counter.Text = if self.maxSelected then `{#ids} / {self.maxSelected}` else `{visibleTicked} / {visible}`
end

-- Does this entry survive the current filter?
function ItemGrid:_matches(entry): boolean
    -- scope first and unconditionally: unlike Filter's predicate, nothing the player does clears
    -- it, and a row it rejects is not reachable by searching for it either
    if self.scopeFilter and self.scopeFilter(entry) ~= true then
        return false
    end

    if self.customFilter then
        return self.customFilter(entry) == true
    end

    if self.searchText ~= "" then
        if not string.find(string.lower(entry.name), string.lower(self.searchText), 1, true) then
            return false
        end
    end

    -- no chip active means every tag passes, which is what an untouched chip row should do
    if next(self.activeTags) ~= nil then
        if entry.tag == nil or not self.activeTags[entry.tag] then
            return false
        end
    end
    return true
end

function ItemGrid:_applyFilter()
    local anyVisible = false
    for _, entry in self.entries do
        local cell = self.cells[entry.id]
        if cell then
            -- an invisible child is skipped by UIGridLayout, so hiding is the whole filter
            local visible = self:_matches(entry)
            cell.frame.Visible = visible
            anyVisible = anyVisible or visible
        end
    end

    self.emptyLabel.Visible = not anyVisible
    self.scroll.Visible = anyVisible
    self:_syncValue()

    if self.onFilterChanged then
        self.window:_runGuarded(self, self.onFilterChanged, self:GetFilter())
    end
end

function ItemGrid:_rebuildCells()
    for _, cell in self.cells do
        for _, connection in cell.connections do
            self.window:Disconnect(connection)
        end
        self.window:DestroySubtree(cell.frame)
    end
    table.clear(self.cells)

    for order, entry in self.entries do
        local cell = self:_buildCell(entry, order)
        self.cells[entry.id] = cell
        self:_applyCell(cell, false)
    end

    self:_syncHeight()
    self:_applyColumns()
    self:_applyFilter()

    if self._built and not self.window.hidden then
        self:_setShown(true, true)
    end
    self._built = true
end

-- `height` is the tallest the grid may get, not the space it always takes: a grid of two items
-- reserving 210px of empty panel is just a hole in the page. The content height is measured off
-- the FULL item count rather than the filtered one, so typing in the search box narrows the cards
-- without the panel resizing under the cursor on every keystroke.
function ItemGrid:_contentHeight(): number
    local count = #self.entries
    if count == 0 then
        return 0
    end
    local rows = math.ceil(count / math.max(self.columns, 1))
    local inset = if self.scroll:IsA("ScrollingFrame") then strokeInset * 2 else 0
    return rows * self.cellHeight + (rows - 1) * cellGap + inset
end

function ItemGrid:_syncHeight()
    local top = self:_gridTop()
    local content = self:_contentHeight()
    -- an empty grid still needs room for the empty label
    local viewport = if content == 0 then emptyRoom else math.min(self.height, content)

    self.scroll.Size = UDim2.new(1, -(sidePadding * 2), 0, viewport)
    self.scroll.Position = UDim2.new(0, sidePadding, 0, top)
    self.emptyLabel.Position = UDim2.new(0, sidePadding, 0, top + 8)
    self.main.Size = UDim2.new(1, -20, 0, top + viewport + sidePadding)
end

moveable(ItemGrid)
lockable(ItemGrid)

-- The ticked ids, as a fresh array in item order.
function ItemGrid:Get(): { string }
    return table.clone(self.value)
end

-- Replace the whole selection. Accepts one id or an array of them.
function ItemGrid:Set(ids, skipCallback)
    if type(ids) == "string" then
        ids = { ids }
    end
    if type(ids) ~= "table" then
        return
    end

    table.clear(self.selected)
    local known = {}
    for _, entry in self.entries do
        known[entry.id] = true
    end

    for _, id in ids do
        id = tostring(id)
        if known[id] then
            self.selected[id] = true
            if not self.multiSelect then
                break -- a single-select grid restoring a multi-entry config takes the first
            end
            if self.maxSelected and self:_selectedCount() >= self.maxSelected then
                break -- a config saved before the cap was lowered must not restore over it
            end
        end
    end

    for _, cell in self.cells do
        self:_applyCell(cell, true)
    end
    self:_syncValue()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

function ItemGrid:Toggle(id, skipCallback)
    id = tostring(id)
    local cell = self.cells[id]
    if not cell then
        return false
    end

    local turningOn = not self.selected[id]
    if turningOn and self.multiSelect and self.maxSelected and self:_selectedCount() >= self.maxSelected then
        -- at the cap: refuse the pick rather than silently dropping someone else's. The player
        -- unticks something first, which is the only unambiguous reading of what they meant.
        return false
    end
    if turningOn and not self.multiSelect then
        table.clear(self.selected)
        for _, other in self.cells do
            self:_applyCell(other, true)
        end
    end

    self.selected[id] = turningOn or nil
    self:_applyCell(cell, true)
    self:_syncValue()

    hapticEngine.click()
    soundEngine.click()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
    return turningOn
end

function ItemGrid:Select(id, skipCallback)
    if not self.selected[tostring(id)] then
        self:Toggle(id, skipCallback)
    end
end

function ItemGrid:Deselect(id, skipCallback)
    if self.selected[tostring(id)] then
        self:Toggle(id, skipCallback)
    end
end

-- Tick everything the filter currently shows - "select all" on a filtered view meaning the whole
-- catalogue would be a nasty surprise.
function ItemGrid:SelectAll(skipCallback)
    if not self.multiSelect then
        return
    end
    for _, entry in self.entries do
        if self:_matches(entry) then
            if self.maxSelected and self:_selectedCount() >= self.maxSelected then
                break -- "all" means "as many as the cap allows", not a way around the cap
            end
            self.selected[entry.id] = true
        end
    end
    for _, cell in self.cells do
        self:_applyCell(cell, true)
    end
    self:_syncValue()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

function ItemGrid:Clear(skipCallback)
    self:Set({}, skipCallback)
end

-- What the filter currently is, in the same shape Filter() accepts.
function ItemGrid:GetFilter()
    local tags = {}
    for tag in self.activeTags do
        table.insert(tags, tag)
    end
    table.sort(tags)
    return { text = self.searchText, tags = tags }
end

-- Turn one chip on or off. Also the programmatic half of clicking it, so a hub can drive the
-- chips from a keybind or restore them itself.
function ItemGrid:ToggleTag(tag)
    tag = tostring(tag)
    self.activeTags[tag] = (not self.activeTags[tag]) or nil
    self.customFilter = nil

    local chip = self.chips[tag]
    if chip then
        self:_applyChip(chip, true)
        hapticEngine.click()
        soundEngine.click()
    end

    self:_applyFilter()
end

-- Narrow the visible cards. Takes a plain search string, a { text = , tags = } table (tags as an
-- array or a set), or a predicate over the entry. nil clears everything, chips included.
function ItemGrid:Filter(query)
    if query == nil then
        self.customFilter = nil
        self.searchText = ""
        table.clear(self.activeTags)
    elseif type(query) == "string" then
        self.customFilter = nil
        self.searchText = query
    elseif type(query) == "function" then
        self.customFilter = query
    elseif type(query) == "table" then
        self.customFilter = nil
        self.searchText = query.text or query.Text or ""
        table.clear(self.activeTags)
        for key, value in (query.tags or query.Tags or {}) do
            -- an array of tags and a set of them both land here
            self.activeTags[if value == true then tostring(key) else tostring(value)] = true
        end
    end

    -- keep the visible controls honest about the filter they represent
    if self.searchInput and self.searchInput.Text ~= self.searchText then
        self.searchInput.Text = self.searchText
    end
    for _, chip in self.chips do
        self:_applyChip(chip, true)
    end

    self:_applyFilter()
end

-- Replace the item set, keeping the ticks of anything that survives.
function ItemGrid:Refresh(items, skipCallback)
    local rebuilt, seen = {}, {}
    for _, entry in (items or {}) do
        local normalised = normalise(entry)
        if normalised and not seen[normalised.id] then
            seen[normalised.id] = true
            table.insert(rebuilt, normalised)
        end
    end

    self.entries = rebuilt
    for id in self.selected do
        if not seen[id] then
            self.selected[id] = nil
        end
    end

    self:_rebuildCells()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

function ItemGrid:SetHeight(height)
    self.height = math.max(tonumber(height) or defaultHeight, 80)
    self:_syncHeight()
end

-- Same as SetHeight, under the name that says it sets a ceiling rather than a fixed height.
function ItemGrid:SetMaxHeight(height)
    self:SetHeight(height)
end

function ItemGrid:SetColumns(columns)
    self.requestedColumns = math.clamp(tonumber(columns) or defaultColumns, 1, 8)
    self:_applyColumns()
end

function ItemGrid:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.counter, { TextTransparency = 0.45 }, animate)
        w:_reveal(self.emptyLabel, { TextTransparency = 0.55 }, animate)

        if self.searchBox then
            w:_reveal(self.searchBox, { BackgroundTransparency = w.theme.FieldTransparency }, animate)
            w:_reveal(self.searchIcon, { ImageTransparency = 0.5 }, animate)
            w:_reveal(self.searchInput, { TextTransparency = 0.15 }, animate)
        end
        if self.selectAllButton then
            w:_reveal(self.selectAllButton, { TextTransparency = 0.35 }, animate)
        end
        if self.clearButton then
            w:_reveal(self.clearButton, { TextTransparency = 0.35 }, animate)
        end
        for _, chip in self.chips do
            local active = self.activeTags[chip.descriptor.tag] == true
            w:_reveal(chip.frame, { BackgroundTransparency = if active then 0.75 else 1 }, animate)
            w:_reveal(chip.stroke, { Transparency = if active then 0.15 else 0.65 }, animate)
            w:_reveal(chip.title, { TextTransparency = if active then 0 else 0.35 }, animate)
        end

        for _, cell in self.cells do
            local isSelected = self.selected[cell.entry.id] == true
            w:_reveal(cell.frame, { BackgroundTransparency = cellRest }, animate)
            w:_reveal(cell.stroke, { Transparency = if isSelected then 0.15 else 0.85 }, animate)
            w:_reveal(cell.dot, { BackgroundTransparency = if isSelected then 0 else 0.15 }, animate)
            w:_reveal(cell.box, {
                BackgroundTransparency = if isSelected then 0 else w.theme.ToggleKnobOffTransparency,
            }, animate)
            w:_reveal(cell.boxStroke, { Transparency = if isSelected then 0 else 0.7 }, animate)
            w:_reveal(cell.check, { ImageTransparency = if isSelected then 0 else 1 }, animate)
            w:_reveal(cell.title, { TextTransparency = if isSelected then 0 else 0.1 }, animate)
            if cell.image then
                w:_reveal(cell.image, { ImageTransparency = 0 }, animate)
            end
            if cell.iconLabel then
                w:_reveal(cell.iconLabel, { ImageTransparency = 0.2 }, animate)
            end
        end
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.counter, { TextTransparency = 1 }, animate)
        w:_reveal(self.emptyLabel, { TextTransparency = 1 }, animate)

        if self.searchBox then
            w:_reveal(self.searchBox, { BackgroundTransparency = 1 }, animate)
            w:_reveal(self.searchIcon, { ImageTransparency = 1 }, animate)
            w:_reveal(self.searchInput, { TextTransparency = 1 }, animate)
        end
        if self.selectAllButton then
            w:_reveal(self.selectAllButton, { TextTransparency = 1 }, animate)
        end
        if self.clearButton then
            w:_reveal(self.clearButton, { TextTransparency = 1 }, animate)
        end
        for _, chip in self.chips do
            w:_reveal(chip.frame, { BackgroundTransparency = 1 }, animate)
            w:_reveal(chip.stroke, { Transparency = 1 }, animate)
            w:_reveal(chip.title, { TextTransparency = 1 }, animate)
        end

        for _, cell in self.cells do
            w:_reveal(cell.frame, { BackgroundTransparency = 1 }, animate)
            w:_reveal(cell.stroke, { Transparency = 1 }, animate)
            w:_reveal(cell.dot, { BackgroundTransparency = 1 }, animate)
            w:_reveal(cell.box, { BackgroundTransparency = 1 }, animate)
            w:_reveal(cell.boxStroke, { Transparency = 1 }, animate)
            w:_reveal(cell.check, { ImageTransparency = 1 }, animate)
            w:_reveal(cell.title, { TextTransparency = 1 }, animate)
            if cell.image then
                w:_reveal(cell.image, { ImageTransparency = 1 }, animate)
            end
            if cell.iconLabel then
                w:_reveal(cell.iconLabel, { ImageTransparency = 1 }, animate)
            end
        end
    end
end

-- Re-apply what isn't a plain themeProperty, so a runtime ChangeTheme reaches every cell.
function ItemGrid:_refreshTheme()
    for _, cell in self.cells do
        self:_applyCell(cell, true)
    end
    for _, chip in self.chips do
        self:_applyChip(chip, true)
    end
end

function ItemGrid:_minWidth()
    return math.min(sidePadding * 2 + minCellWidth * math.min(self.requestedColumns, 2), 340)
end

function ItemGrid:Remove()
    if self.descriptor then
        self.descriptor:Remove()
    end
    self.main:Destroy()
end

return ItemGrid

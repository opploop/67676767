--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A scrolling grid of selectable cards - a cosmetic picker, an item filter, a loadout screen.
-- The long-list case a Dropdown handles badly: a few hundred entries the player wants to SEE
-- and tick several of, not open a menu and hunt through one at a time.
--
-- Each item can carry a `color` (its rarity/category) which tints the card's edge while
-- unselected, and a `tag` the filter can narrow on - so a search box and a row of rarity chips
-- drive one `grid:Filter({ text = ..., tags = { ... } })` call between them.
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
local cellGap = 8
local boxSize = 18
local defaultColumns = 4
local defaultHeight = 210
local defaultCellHeight = 46

-- Below this a card can't hold a two-word name, so the grid drops a column instead of letting
-- every label truncate. Checked against the real width, so a collapsed window reflows.
local minCellWidth = 132

local stateInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local cellRest = 0.94
local cellHover = 0.88

-- Accepts "Banana", or { id, name, icon, color, tag }. A bare string is its own id.
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
            color = entry.color or entry.Color,
            tag = entry.tag or entry.Tag,
        }
    end
    return nil
end

function ItemGrid.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Items",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        columns = math.clamp(tonumber(properties.columns or properties.Columns) or defaultColumns, 1, 8),
        height = math.max(tonumber(properties.height or properties.Height) or defaultHeight, 80),
        cellHeight = math.max(tonumber(properties.cellHeight or properties.CellHeight) or defaultCellHeight, 30),
        multiSelect = (properties.multiSelect or properties.MultiSelect) ~= false,
        emptyText = properties.emptyText or properties.EmptyText or "Nothing matches that filter.",

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Items")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,

        entries = {},
        cells = {}, -- keyed by id
        selected = {}, -- keyed by id -> true
        value = {}, -- ordered ids; what persists
        filter = nil,
    }, ItemGrid)

    -- the author's column count is the ceiling; a narrow window only ever drops below it
    self.requestedColumns = self.columns

    for _, entry in (properties.items or properties.Items or {}) do
        local normalised = normalise(entry)
        if normalised then
            table.insert(self.entries, normalised)
        end
    end

    self.window:_registerControl(self)
    self:_build()
    self:_rebuildCells()

    local initial = properties.value or properties.Value
    if initial ~= nil then
        self:Set(initial, true)
    end

    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
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
        Size = UDim2.new(1, -(sidePadding * 2 + 60), 0, headerHeight),
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
        Size = UDim2.fromOffset(60, headerHeight),
        Position = UDim2.new(1, -sidePadding, 0, headerTop),
        AnchorPoint = Vector2.new(1, 0),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,

        TextTransparency = 1, -- In = 0.45

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.scroll = window:Create("ScrollingFrame", {
        Name = "Grid",
        Size = UDim2.new(1, -(sidePadding * 2), 0, self.height),
        Position = UDim2.new(0, sidePadding, 0, headerTop + headerHeight + headerGap),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.6,
        ScrollingDirection = Enum.ScrollingDirection.Y,

        Parent = self.main,
    }, { ScrollBarImageColor3 = "ContentColor" })

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
        Position = UDim2.new(0, sidePadding, 0, headerTop + headerHeight + headerGap + 8),
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

-- Fit `columns` cells across the real width, dropping columns while they'd come out too narrow.
function ItemGrid:_applyColumns()
    local width = self.scroll.AbsoluteSize.X
    if width <= 0 then
        return
    end

    local columns = self.requestedColumns
    while columns > 1 and (width - cellGap * (columns - 1)) / columns < minCellWidth do
        columns -= 1
    end

    local cellWidth = math.floor((width - cellGap * (columns - 1)) / columns)
    self.columns = columns
    self.gridLayout.FillDirectionMaxCells = columns
    self.gridLayout.CellSize = UDim2.fromOffset(cellWidth, self.cellHeight)
end

function ItemGrid:_cellConnect(cell, signal, handler)
    table.insert(cell.connections, self.window:ConnectFor(self, signal, handler))
end

function ItemGrid:_buildCell(entry, order)
    local window = self.window
    local cell = { connections = {}, entry = entry }

    cell.frame = window:Create("Frame", {
        Name = entry.name,
        LayoutOrder = order,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = cellRest

        Parent = self.scroll,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = cell.frame })

    cell.stroke = window:Create("UIStroke", {
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = entry.color or Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- In = the unselected edge

        Parent = cell.frame,
    })

    cell.box = window:Create("Frame", {
        Name = "Box",
        Size = UDim2.fromOffset(boxSize, boxSize),
        Position = UDim2.new(0, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
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

    local textLeft = 10 + boxSize + 8
    local iconRoom = if entry.icon then 20 else 0

    if entry.icon then
        cell.iconLabel = window:Create("ImageLabel", {
            Image = entry.icon,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.new(0, textLeft, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = 0.2

            Parent = cell.frame,
        }, { ImageColor3 = "ContentColor" })
    end

    cell.title = window:Create("TextLabel", {
        Text = locale.t(entry.name),
        Size = UDim2.new(1, -(textLeft + iconRoom + 10), 1, -6),
        Position = UDim2.new(0, textLeft + iconRoom, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,

        TextTransparency = 1, -- In = 0.1

        Parent = cell.frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    cell.interact = window:Create("TextButton", {
        Name = "Interact",
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = cell.frame,
    })

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

-- One place that decides what a cell looks like, so hover/selection/theme can't disagree.
function ItemGrid:_applyCell(cell, animate)
    local theme = self.window.theme
    local isSelected = self.selected[cell.entry.id] == true
    local edge = cell.entry.color or theme.ElementStroke

    local goals = {
        frame = { BackgroundTransparency = if cell.hovered then cellHover else cellRest },
        stroke = {
            Color = if isSelected then theme.AccentStroke else edge,
            Transparency = if isSelected then 0.1 elseif cell.entry.color then 0.45 else 0.8,
        },
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

    if not animate then
        for part, properties in goals do
            for property, value in properties do
                cell[part][property] = value
            end
        end
        return
    end

    for part, properties in goals do
        variables.tweenService:Create(cell[part], stateInfo, properties):Play()
    end
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

    local shown = 0
    for _, cell in self.cells do
        if cell.frame.Visible then
            shown += 1
        end
    end
    self.counter.Text = `{#ids} / {shown}`
end

-- Does this entry survive the current filter? nil filter means everything does.
function ItemGrid:_matches(entry): boolean
    local filter = self.filter
    if filter == nil then
        return true
    end
    if type(filter) == "function" then
        return filter(entry) == true
    end

    if filter.text and filter.text ~= "" then
        if not string.find(string.lower(entry.name), string.lower(filter.text), 1, true) then
            return false
        end
    end
    if filter.tags and next(filter.tags) ~= nil then
        if entry.tag == nil or not filter.tags[entry.tag] then
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
            local visible = self:_matches(entry)
            cell.frame.Visible = visible
            anyVisible = anyVisible or visible
        end
    end

    -- an invisible child is skipped by UIGridLayout, so hiding is the whole filter
    self.emptyLabel.Visible = not anyVisible
    self.scroll.Visible = anyVisible
    self:_syncValue()
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

function ItemGrid:_syncHeight()
    self.scroll.Size = UDim2.new(1, -(sidePadding * 2), 0, self.height)
    self.main.Size = UDim2.new(1, -20, 0, headerTop + headerHeight + headerGap + self.height + sidePadding)
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

-- Tick everything the filter currently shows - "select all" on a filtered view meaning the
-- whole catalogue would be a nasty surprise.
function ItemGrid:SelectAll(skipCallback)
    if not self.multiSelect then
        return
    end
    for _, entry in self.entries do
        if self:_matches(entry) then
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

-- Narrow the visible cards. Takes a plain search string, a { text = , tags = } table (tags as an
-- array or a set), or a predicate over the entry. nil clears the filter.
function ItemGrid:Filter(query)
    if query == nil then
        self.filter = nil
    elseif type(query) == "string" then
        self.filter = { text = query }
    elseif type(query) == "function" then
        self.filter = query
    elseif type(query) == "table" then
        local tags = nil
        if query.tags or query.Tags then
            tags = {}
            for key, value in (query.tags or query.Tags) do
                -- an array of tags and a set of them both land here
                if value == true then
                    tags[tostring(key)] = true
                else
                    tags[tostring(value)] = true
                end
            end
        end
        self.filter = { text = query.text or query.Text, tags = tags }
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
        for _, cell in self.cells do
            local isSelected = self.selected[cell.entry.id] == true
            w:_reveal(cell.frame, { BackgroundTransparency = cellRest }, animate)
            w:_reveal(cell.stroke, {
                Transparency = if isSelected then 0.1 elseif cell.entry.color then 0.45 else 0.8,
            }, animate)
            w:_reveal(cell.box, {
                BackgroundTransparency = if isSelected then 0 else w.theme.ToggleKnobOffTransparency,
            }, animate)
            w:_reveal(cell.boxStroke, { Transparency = if isSelected then 0 else 0.7 }, animate)
            w:_reveal(cell.check, { ImageTransparency = if isSelected then 0 else 1 }, animate)
            w:_reveal(cell.title, { TextTransparency = if isSelected then 0 else 0.1 }, animate)
            if cell.iconLabel then
                w:_reveal(cell.iconLabel, { ImageTransparency = 0.2 }, animate)
            end
        end
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.counter, { TextTransparency = 1 }, animate)
        w:_reveal(self.emptyLabel, { TextTransparency = 1 }, animate)
        for _, cell in self.cells do
            w:_reveal(cell.frame, { BackgroundTransparency = 1 }, animate)
            w:_reveal(cell.stroke, { Transparency = 1 }, animate)
            w:_reveal(cell.box, { BackgroundTransparency = 1 }, animate)
            w:_reveal(cell.boxStroke, { Transparency = 1 }, animate)
            w:_reveal(cell.check, { ImageTransparency = 1 }, animate)
            w:_reveal(cell.title, { TextTransparency = 1 }, animate)
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

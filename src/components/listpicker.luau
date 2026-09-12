--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A vertical single-select list: a category rail beside the thing it filters. The shape a
-- cosmetics screen puts down the left ("Armors / Weapons / Enchants / Titles") to choose what the
-- panel next to it is showing.
--
-- SegmentedPicker is the horizontal answer to the same question and stays the right one for two
-- or three short options. This exists for the cases that one handles badly: more options than fit
-- across, names long enough to crowd a strip, or a layout that wants the chooser stacked beside
-- the content rather than above it - typically as the narrow column of a `row` Group.
--
-- Positions are computed here rather than left to AutomaticSize: the list knows its own row count
-- and writes its own height, so it never negotiates size with a parent layout (see this repo's
-- history of AutomaticSize-inside-a-list-layout growth loops).

local ListPicker = {}
ListPicker.__index = ListPicker
ListPicker.__type = "ListPicker"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local lockable = require(utility.lockable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local sidePadding = 15
local headerTop = 15
local headerHeight = 16
local headerGap = 12
local rowGap = 4
local defaultRowHeight = 34
local rowInset = 12
local rowCorner = 9
local iconSize = 16
local iconGap = 9

-- A UIStroke draws outside its frame, so a row flush against a scrolling edge loses that side of
-- its outline. Same inset the item grid uses, for the same reason.
local strokeInset = 3

local stateInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local rowRest = 1 -- unselected rows are bare text; the fill is what marks the selection
local rowHover = 0.9

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
            color = entry.color or entry.Color, -- overrides the accent for this row's fill
        }
    end
    return nil
end

function ListPicker.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Category",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        rowHeight = math.max(tonumber(properties.rowHeight or properties.RowHeight) or defaultRowHeight, 24),
        -- when set the list scrolls inside that height instead of growing with its options
        height = tonumber(properties.height or properties.Height),
        showHeader = functions.readBool(properties, "showHeader", true),
        emptyText = properties.emptyText or properties.EmptyText or "Nothing to pick.",

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Category")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,

        entries = {},
        rows = {},
        value = nil, -- the selected id; this is what persists
    }, ListPicker)

    for _, entry in (properties.options or properties.Options or properties.items or properties.Items or {}) do
        local normalised = normalise(entry)
        if normalised then
            table.insert(self.entries, normalised)
        end
    end

    self.window:_registerControl(self)
    self:_build()
    self:_rebuildRows()

    -- default to the first option rather than nothing: a category rail with no category chosen
    -- shows a panel with no reason to be showing anything
    local initial = properties.value or properties.Value
    if initial == nil and self.entries[1] then
        initial = self.entries[1].id
    end
    if initial ~= nil then
        self:Set(initial, true)
    end

    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

function ListPicker:_slot(): number
    return self.rowHeight + rowGap
end

function ListPicker:_listTop(): number
    return if self.showHeader then headerTop + headerHeight + headerGap else headerTop
end

function ListPicker:_build()
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

    if self.showHeader then
        if self.icon then
            self.iconLabel = window:Create("ImageLabel", {
                Image = self.icon,
                Size = UDim2.fromOffset(iconSize, iconSize),
                Position = UDim2.new(0, sidePadding, 0, headerTop),
                BorderSizePixel = 0,
                BackgroundTransparency = 1,

                ImageTransparency = 1, -- In = 0

                Parent = self.main,
            }, { ImageColor3 = "ContentColor" })
        end

        -- The header reads as a section label, not another row: small and dimmer than the options
        -- under it. Rendered exactly as given rather than forced uppercase - locale.t returns a
        -- translation TOKEN that Create resolves on assignment, so there is no string to upper
        -- here, and uppercasing the source first would change the key a translation table is
        -- looked up by. Pass name = "COSMETIC TYPE" if you want that look.
        self.title = window:Create("TextLabel", {
            Text = locale.t(self.name),
            Size = UDim2.new(1, -(sidePadding * 2), 0, headerHeight),
            Position = UDim2.new(0, sidePadding + (if self.icon then iconSize + 5 else 0), 0, headerTop),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,

            TextTransparency = 1, -- In = 0.45

            Parent = self.main,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })
    end

    local container = if self.height then "ScrollingFrame" else "Frame"
    self.list = window:Create(container, {
        Name = "Options",
        Size = UDim2.new(1, -(sidePadding * 2), 0, 0),
        Position = UDim2.new(0, sidePadding, 0, self:_listTop()),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    if self.height then
        self.list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        self.list.CanvasSize = UDim2.new()
        self.list.ScrollBarThickness = 3
        self.list.ScrollBarImageTransparency = 0.6
        self.list.ScrollingDirection = Enum.ScrollingDirection.Y
        window:Create("UIPadding", {
            PaddingLeft = UDim.new(0, strokeInset),
            PaddingRight = UDim.new(0, strokeInset),
            PaddingTop = UDim.new(0, strokeInset),
            PaddingBottom = UDim.new(0, strokeInset),

            Parent = self.list,
        })
    end

    self.listLayout = window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, rowGap),
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.list,
    })

    self.emptyLabel = window:Create("TextLabel", {
        Text = locale.t(self.emptyText),
        Size = UDim2.new(1, -(sidePadding * 2), 0, 20),
        Position = UDim2.new(0, sidePadding, 0, self:_listTop() + 4),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Visible = false,

        TextTransparency = 1, -- In = 0.55

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })
end

function ListPicker:_rowConnect(row, signal, handler)
    table.insert(row.connections, self.window:ConnectFor(self, signal, handler))
end

function ListPicker:_buildRow(entry, order)
    local window = self.window
    local row = { connections = {}, entry = entry }

    row.frame = window:Create("Frame", {
        Name = entry.name,
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, self.rowHeight),
        BackgroundColor3 = entry.color or window.theme.AccentColor,
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = rowRest

        Parent = self.list,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, rowCorner), Parent = row.frame })

    row.stroke = window:Create("UIStroke", {
        Thickness = 1,

        Transparency = 1,

        Parent = row.frame,
    }, { Color = "ElementStroke" })

    local left = rowInset

    if entry.icon then
        row.iconLabel = window:Create("ImageLabel", {
            Image = entry.icon,
            Size = UDim2.fromOffset(iconSize, iconSize),
            Position = UDim2.new(0, left, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1,

            Parent = row.frame,
        })
        left += iconSize + iconGap
    end

    row.title = window:Create("TextLabel", {
        Text = locale.t(entry.name),
        Size = UDim2.new(1, -(left + rowInset), 1, 0),
        Position = UDim2.new(0, left, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,

        TextTransparency = 1,

        Parent = row.frame,
    }, { FontFace = "Font" })

    row.interact = window:Create("TextButton", {
        Name = "Interact",
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = row.frame,
    })

    self:_rowConnect(row, row.interact.MouseEnter, function()
        row.hovered = true
        if not self.locked then
            self:_applyRow(row, true)
        end
    end)
    self:_rowConnect(row, row.interact.MouseLeave, function()
        row.hovered = false
        self:_applyRow(row, true)
    end)
    self:_rowConnect(row, row.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        self:Set(entry.id)
    end)

    return row
end

-- One place that decides what a row looks like. The selected row is the only filled one, so
-- selection reads at a glance down the column.
function ListPicker:_applyRow(row, animate)
    local theme = self.window.theme
    local selected = self.value == row.entry.id
    local fill = row.entry.color or theme.AccentColor

    local goals = {
        frame = {
            BackgroundColor3 = fill,
            BackgroundTransparency = if selected then 0 elseif row.hovered then rowHover else rowRest,
        },
        stroke = {
            Color = if selected then (row.entry.color or theme.AccentStroke) else theme.ElementStroke,
            Transparency = if selected then 0.2 elseif row.hovered then 0.75 else 1,
        },
        title = {
            -- on a solid fill the label has to pick its own colour by luminance, or an accent a
            -- theme makes pale renders white-on-white
            TextColor3 = if selected then functions.contrastText(fill) else theme.ContentColor,
            TextTransparency = if selected then 0 elseif row.hovered then 0.05 else 0.35,
        },
    }

    for part, props in goals do
        if animate then
            variables.tweenService:Create(row[part], stateInfo, props):Play()
        else
            for property, value in props do
                row[part][property] = value
            end
        end
    end

    if row.iconLabel then
        local iconGoal = {
            ImageColor3 = if selected then functions.contrastText(fill) else self.window.theme.ContentColor,
            ImageTransparency = if selected then 0 elseif row.hovered then 0.1 else 0.4,
        }
        if animate then
            variables.tweenService:Create(row.iconLabel, stateInfo, iconGoal):Play()
        else
            for property, value in iconGoal do
                row.iconLabel[property] = value
            end
        end
    end
end

function ListPicker:_syncHeight()
    local count = #self.rows
    local content = if count == 0 then 20 else count * self.rowHeight + (count - 1) * rowGap
    local listHeight = self.height or content
    if self.height then
        content = listHeight
    end

    self.list.Size = UDim2.new(1, -(sidePadding * 2), 0, listHeight)
    self.main.Size = UDim2.new(1, -20, 0, self:_listTop() + listHeight + sidePadding)
    self.emptyLabel.Visible = count == 0
    self.list.Visible = count > 0
end

function ListPicker:_rebuildRows()
    for _, row in self.rows do
        for _, connection in row.connections do
            self.window:Disconnect(connection)
        end
        self.window:DestroySubtree(row.frame)
    end
    table.clear(self.rows)

    for order, entry in self.entries do
        local row = self:_buildRow(entry, order)
        table.insert(self.rows, row)
        self:_applyRow(row, false)
    end

    self:_syncHeight()

    -- rows built after the window is already open have to be revealed here, or they stay fully
    -- transparent. Not on the construction pass: the container reveals the whole element itself
    -- once it has registered it, and doing it here too would race that.
    if self._built and not self.window.hidden then
        self:_setShown(true, true)
    end
    self._built = true
end

moveable(ListPicker)
lockable(ListPicker)

-- The selected id, or nil when the list is empty.
function ListPicker:Get(): string?
    return self.value
end

function ListPicker:Set(id, skipCallback)
    id = if id == nil then nil else tostring(id)

    local known = false
    for _, entry in self.entries do
        if entry.id == id then
            known = true
            break
        end
    end
    if id ~= nil and not known then
        return false
    end

    local changed = self.value ~= id
    self.value = id

    for _, row in self.rows do
        self:_applyRow(row, true)
    end

    if changed then
        hapticEngine.click()
        soundEngine.click()
    end

    -- fire even when unchanged: a config load calls Set and relies on the callback to apply,
    -- exactly like Toggle does
    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self.value)
        self.window:_persist(self)
    end
    return true
end

-- Replace the options, keeping the current pick when it survives - a category rail rebuilding
-- around a new category should not throw the player back to the first one.
function ListPicker:Refresh(options, skipCallback)
    local rebuilt, seen = {}, {}
    for _, entry in (options or {}) do
        local normalised = normalise(entry)
        if normalised and not seen[normalised.id] then
            seen[normalised.id] = true
            table.insert(rebuilt, normalised)
        end
    end

    self.entries = rebuilt
    local previous = self.value
    self:_rebuildRows()

    if previous ~= nil and seen[previous] then
        self:Set(previous, true)
    else
        self:Set(if rebuilt[1] then rebuilt[1].id else nil, skipCallback)
    end
end

function ListPicker:SetHeight(height)
    self.height = tonumber(height)
    self:_syncHeight()
end

function ListPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_reveal(self.stroke, { Transparency = w.theme.ElementStrokeTransparency }, animate)
        w:_reveal(self.main, { BackgroundTransparency = w.theme.ElementTransparency or 0 }, animate)
        if self.title then
            w:_reveal(self.title, { TextTransparency = 0.45 }, animate)
        end
        if self.iconLabel then
            w:_reveal(self.iconLabel, { ImageTransparency = 0 }, animate)
        end
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 0.7 }, animate)
        end
        w:_reveal(self.emptyLabel, { TextTransparency = 0.55 }, animate)

        for _, row in self.rows do
            local selected = self.value == row.entry.id
            local fill = row.entry.color or w.theme.AccentColor
            w:_reveal(
                row.frame,
                { BackgroundTransparency = if selected then 0 elseif row.hovered then rowHover else rowRest },
                animate
            )
            w:_reveal(row.stroke, { Transparency = if selected then 0.2 else 1 }, animate)
            w:_reveal(row.title, { TextTransparency = if selected then 0 else 0.35 }, animate)
            if row.iconLabel then
                w:_reveal(row.iconLabel, { ImageTransparency = if selected then 0 else 0.4 }, animate)
            end
            if selected then
                row.title.TextColor3 = functions.contrastText(fill)
            end
        end
    else
        w:_reveal(self.stroke, { Transparency = 1 }, animate)
        w:_reveal(self.main, { BackgroundTransparency = 1 }, animate)
        if self.title then
            w:_reveal(self.title, { TextTransparency = 1 }, animate)
        end
        if self.iconLabel then
            w:_reveal(self.iconLabel, { ImageTransparency = 1 }, animate)
        end
        if self.descriptor then
            w:_reveal(self.descriptor.titleLabel, { TextTransparency = 1 }, animate)
        end
        w:_reveal(self.emptyLabel, { TextTransparency = 1 }, animate)

        for _, row in self.rows do
            w:_reveal(row.frame, { BackgroundTransparency = 1 }, animate)
            w:_reveal(row.stroke, { Transparency = 1 }, animate)
            w:_reveal(row.title, { TextTransparency = 1 }, animate)
            if row.iconLabel then
                w:_reveal(row.iconLabel, { ImageTransparency = 1 }, animate)
            end
        end
    end
end

-- Re-apply what isn't a plain themeProperty, so a runtime ChangeTheme reaches every row.
function ListPicker:_refreshTheme()
    for _, row in self.rows do
        self:_applyRow(row, true)
    end
end

-- Narrow on purpose: this is built to be the slim column of a `row` Group, beside the panel it
-- drives, so it asks for the widest option plus its chrome and no more.
function ListPicker:_minWidth()
    local widest = if self.showHeader then functions.textWidth(self.window.theme.Font, 12, self.name) else 0
    for _, entry in self.entries do
        widest = math.max(widest, functions.textWidth(self.window.theme.Font, 15, entry.name))
    end
    local chrome = sidePadding * 2 + rowInset * 2
    for _, entry in self.entries do
        if entry.icon then
            chrome += iconSize + iconGap
            break
        end
    end
    return math.clamp(chrome + widest, 120, 280)
end

function ListPicker:Remove()
    if self.descriptor then
        self.descriptor:Remove()
    end
    self.main:Destroy()
end

return ListPicker

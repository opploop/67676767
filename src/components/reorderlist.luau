--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A list whose order the player sets by dragging a row into place - a feature priority order, a
-- queue, an execution sequence. The order IS the value: it persists through `flag` like any
-- other control, and the callback hands back the id array.
--
-- WHY THERE IS NO UIListLayout IN HERE, AND WHY THERE MUST NEVER BE ONE
--
-- Animating a row's Position while a UIListLayout also owns that row is unreliable on this
-- project's test executor: the layout writes the row back mid-tween, so a drag reads as jitter,
-- snap-back, or a row landing one index off. Two features in this codebase's own history
-- (CursorTag and PinnedList) were built that way, failed live, were fixed repeatedly, kept
-- surfacing new failure modes, and were ultimately deleted rather than shipped.
--
-- So this list owns every row's Position itself. There is no layout object anywhere in the row
-- stack; _layout() computes each row's Y from its index and writes it. Nothing else can move a
-- row, so nothing can fight the drag. That is the entire reason this component is viable where
-- PinnedList wasn't - do not "tidy" it into a UIListLayout later.

local ReorderList = {}
ReorderList.__index = ReorderList
ReorderList.__type = "ReorderList"

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

local defaultRowHeight = 38
local rowGap = 6
local sidePadding = 15
local headerTop = 15
local headerHeight = 16
local headerGap = 14
local emptyHeight = 30
local gripDotSize = 3
local gripDotGap = 3
local badgeSize = 20

-- A displaced row settles fast and Quint-Out, so it's already where the eye expects by the time
-- the cursor arrives. The dragged row itself never tweens - see _follow.
local settleInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local liftInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Row surface transparencies. A dragged row is the only one that reads as solid, which is what
-- makes it legible as "the thing in your hand" while it passes over the others.
local rowRest = 0.93
local rowHover = 0.88
local rowLift = 0.82

-- Accepts "Auto Farm", or { id = "farm", name = "Auto Farm", icon = ..., color = ... }. A bare
-- string is its own id: the common case shouldn't need a table.
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
        }
    end
    return nil
end

function ReorderList.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Order",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        rowHeight = math.max(tonumber(properties.rowHeight or properties.RowHeight) or defaultRowHeight, 26),
        showIndex = (properties.showIndex or properties.ShowIndex) ~= false,
        removable = (properties.removable or properties.Removable) == true,
        emptyText = properties.emptyText or properties.EmptyText or "Nothing here yet.",

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Order")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,
        onRemove = properties.onRemove or properties.OnRemove,

        entries = {}, -- ordered { id, name, icon?, color? }
        rows = {}, -- parallel to entries, same index
        value = {}, -- ordered ids; this is what persists
    }, ReorderList)

    for _, entry in (properties.items or properties.Items or {}) do
        local normalised = normalise(entry)
        if normalised then
            table.insert(self.entries, normalised)
        end
    end

    self.window:_registerControl(self)
    self:_build()
    self:_rebuildRows()
    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    return self
end

function ReorderList:_slot(): number
    return self.rowHeight + rowGap
end

function ReorderList:_build()
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
        Size = UDim2.new(1, -(sidePadding * 2), 0, headerHeight),
        Position = UDim2.new(0, sidePadding + (if self.icon then 21 else 0), 0, headerTop),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- The row stack. Deliberately layout-free (see this file's header): _layout writes every
    -- child's Position and nothing else ever touches it.
    self.stack = window:Create("Frame", {
        Name = "Stack",
        Size = UDim2.new(1, -(sidePadding * 2), 0, 0),
        Position = UDim2.new(0, sidePadding, 0, headerTop + headerHeight + headerGap),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.main,
    })

    self.emptyLabel = window:Create("TextLabel", {
        Text = locale.t(self.emptyText),
        Size = UDim2.new(1, 0, 0, emptyHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Visible = false,

        TextTransparency = 1, -- In = 0.55

        Parent = self.stack,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- A drag that ends anywhere - off the row, off the window, off the screen - has to land.
    -- InputEnded on the row itself never fires once the cursor has left it.
    self.window:ConnectFor(self, variables.userInputService.InputEnded, function(input)
        if
            (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
            and self._dragIndex
        then
            self:_endDrag()
        end
    end)
end

-- Six dots in two columns: the universally-read "grab me" affordance, drawn rather than an
-- image asset so it inherits ContentColor and needs nothing preloaded.
function ReorderList:_buildGrip(row)
    local window = self.window

    local grip = window:Create("Frame", {
        Name = "Grip",
        Size = UDim2.fromOffset(gripDotSize * 2 + gripDotGap, gripDotSize * 3 + gripDotGap * 2),
        Position = UDim2.new(0, 12, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = row,
    })

    local dots = {}
    for column = 0, 1 do
        for dotRow = 0, 2 do
            local dot = window:Create("Frame", {
                Size = UDim2.fromOffset(gripDotSize, gripDotSize),
                Position = UDim2.fromOffset(column * (gripDotSize + gripDotGap), dotRow * (gripDotSize + gripDotGap)),
                BorderSizePixel = 0,

                BackgroundTransparency = 1, -- In = 0.45

                Parent = grip,
            }, { BackgroundColor3 = "ContentColor" })
            window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
            table.insert(dots, dot)
        end
    end

    return grip, dots
end

-- Rows are torn down and rebuilt on every Add/RemoveItem/Refresh, so their connections are
-- tracked per row rather than only on the element: window:ConnectFor files them for teardown at
-- Unload, which is far too late for a list that rebuilds a dozen times a session.
function ReorderList:_rowConnect(row, signal, handler)
    table.insert(row.connections, self.window:ConnectFor(self, signal, handler))
end

function ReorderList:_buildRow(entry, index)
    local window = self.window
    local row = { connections = {} }

    row.entry = entry

    row.frame = window:Create("Frame", {
        Name = entry.name,
        Size = UDim2.new(1, 0, 0, self.rowHeight),
        Position = UDim2.new(0, 0, 0, (index - 1) * self:_slot()),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = rowRest

        Parent = self.stack,
    })

    window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = row.frame })

    row.stroke = window:Create("UIStroke", {
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,

        Transparency = 1, -- In = 0.85

        Parent = row.frame,
    }, { Color = "ElementStroke" })

    row.grip, row.gripDots = self:_buildGrip(row.frame)

    local contentX = 12 + gripDotSize * 2 + gripDotGap + 10

    if self.showIndex then
        row.badge = window:Create("Frame", {
            Name = "Index",
            Size = UDim2.fromOffset(badgeSize, badgeSize),
            Position = UDim2.new(0, contentX, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = entry.color or Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,

            BackgroundTransparency = 1, -- In = 0.88 (or 0.78 when the entry carries a colour)

            Parent = row.frame,
        })
        window:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = row.badge })

        row.badgeLabel = window:Create("TextLabel", {
            Text = tostring(index),
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 13,

            TextTransparency = 1, -- In = 0.25

            Parent = row.badge,
        }, {
            TextColor3 = if entry.color then nil else "ContentColor",
            FontFace = "Font",
        })
        if entry.color then
            row.badgeLabel.TextColor3 = entry.color
        end

        contentX += badgeSize + 10
    end

    if entry.icon then
        row.iconLabel = window:Create("ImageLabel", {
            Image = entry.icon,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.new(0, contentX, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,

            ImageTransparency = 1, -- In = 0.15

            Parent = row.frame,
        }, { ImageColor3 = "ContentColor" })
        contentX += 22
    end

    local rightInset = if self.removable then 38 else 12

    row.title = window:Create("TextLabel", {
        Text = locale.t(entry.name),
        Size = UDim2.new(1, -(contentX + rightInset), 1, 0),
        Position = UDim2.new(0, contentX, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,

        TextTransparency = 1, -- In = 0.1

        Parent = row.frame,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    if self.removable then
        row.removeButton = window:Create("TextButton", {
            Name = "Remove",
            Text = "",
            Size = UDim2.fromOffset(22, 22),
            Position = UDim2.new(1, -10, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,

            Parent = row.frame,
        })
        window:Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = row.removeButton })

        row.removeGlyph = window:Create("TextLabel", {
            Text = "\u{00D7}",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 18,

            TextTransparency = 1, -- In = 0.55

            Parent = row.removeButton,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })

        self:_rowConnect(row, row.removeButton.MouseEnter, function()
            variables.tweenService:Create(row.removeGlyph, liftInfo, { TextTransparency = 0.1 }):Play()
        end)
        self:_rowConnect(row, row.removeButton.MouseLeave, function()
            variables.tweenService:Create(row.removeGlyph, liftInfo, { TextTransparency = 0.55 }):Play()
        end)
        self:_rowConnect(row, row.removeButton.MouseButton1Click, function()
            if self.locked then
                return
            end
            self:RemoveItem(entry.id)
        end)
    end

    -- Covers the row minus the remove button, which sits above it on ZIndex.
    row.interact = window:Create("TextButton", {
        Name = "Interact",
        Text = "",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,

        Parent = row.frame,
    })
    if row.removeButton then
        row.removeButton.ZIndex = row.interact.ZIndex + 1
        row.removeGlyph.ZIndex = row.removeButton.ZIndex
    end

    self:_rowConnect(row, row.interact.MouseEnter, function()
        row.hovered = true
        if not self._dragIndex and not self.locked then
            self:_applyRowVisual(row, "hover")
        end
    end)
    self:_rowConnect(row, row.interact.MouseLeave, function()
        row.hovered = false
        if not self._dragIndex then
            self:_applyRowVisual(row, "rest")
        end
    end)
    self:_rowConnect(row, row.interact.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            -- no pointer argument: grab offset and follow must read the SAME source, or they
            -- disagree by the GUI inset (input.Position and AbsolutePosition have different
            -- origins). slider.luau reads GetMouseLocation on both sides for exactly this reason.
            self:_beginDrag(row)
        end
    end)

    return row
end

-- rest / hover / lift, as one place so a drag never leaves a row half-styled.
function ReorderList:_applyRowVisual(row, state)
    if not row.frame or not row.frame.Parent then
        return
    end
    local ts = variables.tweenService
    local background = if state == "lift" then rowLift elseif state == "hover" then rowHover else rowRest
    local stroke = if state == "lift" then 0.35 elseif state == "hover" then 0.7 else 0.85

    ts:Create(row.frame, liftInfo, { BackgroundTransparency = background }):Play()
    ts:Create(row.stroke, liftInfo, {
        Transparency = stroke,
        Color = if state == "lift" then self.window.theme.AccentStroke else self.window.theme.ElementStroke,
    }):Play()

    local dotTransparency = if state == "rest" then 0.45 else 0.15
    for _, dot in row.gripDots do
        ts:Create(dot, liftInfo, { BackgroundTransparency = dotTransparency }):Play()
    end
end

-- Write every row's Position from its index. `skip` is the row the cursor owns: its position is
-- the mouse's business until the drag ends.
function ReorderList:_layout(skip, instant)
    local slot = self:_slot()
    for index, row in self.rows do
        if row.badgeLabel then
            row.badgeLabel.Text = tostring(index)
        end
        if row ~= skip then
            local goal = UDim2.new(0, 0, 0, (index - 1) * slot)
            if instant then
                row.frame.Position = goal
            else
                variables.tweenService:Create(row.frame, settleInfo, { Position = goal }):Play()
            end
        end
    end
end

function ReorderList:_syncHeight()
    local count = #self.rows
    local stackHeight = if count == 0 then emptyHeight else count * self.rowHeight + (count - 1) * rowGap

    self.stack.Size = UDim2.new(1, -(sidePadding * 2), 0, stackHeight)
    self.main.Size = UDim2.new(1, -20, 0, headerTop + headerHeight + headerGap + stackHeight + sidePadding)
    self.emptyLabel.Visible = count == 0
end

function ReorderList:_syncValue()
    local ids = {}
    for _, entry in self.entries do
        table.insert(ids, entry.id)
    end
    self.value = ids
end

function ReorderList:_rebuildRows()
    -- a rebuild mid-drag would leave _dragRow pointing at a destroyed frame
    if self._dragIndex then
        self:_endDrag()
    end

    for _, row in self.rows do
        for _, connection in row.connections do
            self.window:Disconnect(connection)
        end
        self.window:DestroySubtree(row.frame)
    end
    table.clear(self.rows)

    for index, entry in self.entries do
        table.insert(self.rows, self:_buildRow(entry, index))
    end

    self:_syncValue()
    self:_syncHeight()
    self:_layout(nil, true)

    -- Rows built after the window is already open have to be revealed here or they stay fully
    -- transparent, the same way a late element does. Not on the construction pass though: the
    -- container reveals the whole element itself once it has registered it, and revealing here
    -- first would race that with a second tween on the same properties.
    if self._built and not self.window.hidden then
        self:_setShown(true, true)
    end
    self._built = true
end

-- Where the pointer is, in screen space. Split out (and threaded through _beginDrag/_follow as
-- an argument) so the drag maths can be driven from a known position instead of only from the
-- live cursor - which is what makes the reorder behaviour testable at all, and what lets a
-- touch drag pass its own contact point rather than the mouse's.
function ReorderList:_pointerY(): number
    return variables.userInputService:GetMouseLocation().Y
end

function ReorderList:_beginDrag(row, pointerY)
    if self.locked or self._dragIndex then
        return
    end

    local index = table.find(self.rows, row)
    if not index or #self.rows < 2 then
        return
    end

    hapticEngine.click()
    soundEngine.click()

    self._dragIndex = index
    self._dragRow = row
    -- grab offset, so the row doesn't jump its centre to the cursor on pickup
    self._grabOffset = (pointerY or self:_pointerY()) - row.frame.AbsolutePosition.Y

    -- above every other row, so the dragged one passes over them rather than under
    row.frame.ZIndex = 30
    if row.removeButton then
        row.removeButton.ZIndex = 32
        row.removeGlyph.ZIndex = 32
    end
    self:_applyRowVisual(row, "lift")

    if self._dragConnection then
        self._dragConnection:Disconnect()
    end
    -- Self-terminates if the window unloads mid-drag: InputEnded won't fire to clean us up then.
    self._dragConnection = variables.runService.RenderStepped:Connect(function()
        if self.window.unloaded or not self._dragIndex then
            if self._dragConnection then
                self._dragConnection:Disconnect()
                self._dragConnection = nil
            end
            return
        end
        self:_follow()
    end)
end

function ReorderList:_follow(pointerY)
    local row = self._dragRow
    if not row or not row.frame.Parent then
        return
    end

    local slot = self:_slot()
    local count = #self.rows
    local top = (pointerY or self:_pointerY()) - self._grabOffset - self.stack.AbsolutePosition.Y
    top = math.clamp(top, 0, math.max((count - 1) * slot, 0))

    -- written, never tweened: a tween here trails the cursor by its own duration, which reads as
    -- the row being on a rubber band
    row.frame.Position = UDim2.new(0, 0, 0, top)

    local target = math.clamp(math.floor(top / slot + 0.5) + 1, 1, count)
    if target ~= self._dragIndex then
        table.remove(self.rows, self._dragIndex)
        table.insert(self.rows, target, row)
        table.remove(self.entries, self._dragIndex)
        table.insert(self.entries, target, row.entry)
        self._dragIndex = target
        hapticEngine.click() -- one tick per slot crossed, so reordering is felt, not just seen
        self:_layout(row)
    end
end

function ReorderList:_endDrag()
    local row = self._dragRow
    self._dragIndex = nil
    self._dragRow = nil

    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    if not row then
        return
    end

    row.frame.ZIndex = 1
    if row.removeButton then
        row.removeButton.ZIndex = 3
        row.removeGlyph.ZIndex = 3
    end
    self:_applyRowVisual(row, if row.hovered then "hover" else "rest")
    self:_layout(nil)

    soundEngine.click()

    local before = self.value
    self:_syncValue()

    local changed = #before ~= #self.value
    if not changed then
        for index, id in self.value do
            if before[index] ~= id then
                changed = true
                break
            end
        end
    end

    if changed then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

moveable(ReorderList)
lockable(ReorderList)

-- The current order, as a fresh array of ids. A copy: handing out the live table would let a
-- caller reorder the list behind its own back without any of the rows moving.
function ReorderList:Get(): { string }
    return table.clone(self.value)
end

-- Reorder to match `order`. Ids not in the list are ignored; entries the order doesn't mention
-- keep their relative order at the end, so a saved config from before a new item existed still
-- loads cleanly instead of dropping it.
function ReorderList:Set(order, skipCallback)
    if type(order) ~= "table" then
        return
    end

    local byId = {}
    for _, entry in self.entries do
        byId[entry.id] = entry
    end

    local reordered, taken = {}, {}
    for _, id in order do
        local entry = byId[tostring(id)]
        if entry and not taken[entry.id] then
            taken[entry.id] = true
            table.insert(reordered, entry)
        end
    end
    for _, entry in self.entries do
        if not taken[entry.id] then
            table.insert(reordered, entry)
        end
    end

    self.entries = reordered
    self:_rebuildRows()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

-- Append one item. Ignored if its id is already in the list - two rows with one id would make
-- the order ambiguous and RemoveItem non-deterministic.
function ReorderList:Add(entry, skipCallback)
    local normalised = normalise(entry)
    if not normalised then
        return false
    end
    for _, existing in self.entries do
        if existing.id == normalised.id then
            return false
        end
    end

    table.insert(self.entries, normalised)
    self:_rebuildRows()

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
    return true
end

-- Drop one item by id. Named RemoveItem, not Remove, because Remove() destroys the element
-- itself here the same way it does on every other component.
function ReorderList:RemoveItem(id, skipCallback)
    id = tostring(id)
    for index, entry in self.entries do
        if entry.id == id then
            table.remove(self.entries, index)
            self:_rebuildRows()

            if self.onRemove then
                self.window:_runGuarded(self, self.onRemove, id)
            end
            if not skipCallback then
                self.window:_runGuarded(self, self.callback, self:Get())
                self.window:_persist(self)
            end
            return true
        end
    end
    return false
end

-- Replace the whole item set, keeping the current relative order of anything that survives -
-- the list rebuilding around a feature that registered late shouldn't reshuffle the player's
-- own arrangement of the others.
function ReorderList:Refresh(items, skipCallback)
    local order = {}
    for _, entry in self.entries do
        table.insert(order, entry.id)
    end

    local rebuilt = {}
    for _, entry in (items or {}) do
        local normalised = normalise(entry)
        if normalised then
            local duplicate = false
            for _, existing in rebuilt do
                if existing.id == normalised.id then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                table.insert(rebuilt, normalised)
            end
        end
    end

    self.entries = rebuilt
    self:Set(order, true)

    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self:Get())
        self.window:_persist(self)
    end
end

function ReorderList:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.emptyLabel, { TextTransparency = 0.55 }, animate)
        for _, row in self.rows do
            local entry = row.entry
            w:_reveal(row.frame, { BackgroundTransparency = if row.hovered then rowHover else rowRest }, animate)
            w:_reveal(row.stroke, { Transparency = if row.hovered then 0.7 else 0.85 }, animate)
            w:_reveal(row.title, { TextTransparency = 0.1 }, animate)
            if row.badge then
                w:_reveal(row.badge, { BackgroundTransparency = if entry.color then 0.78 else 0.88 }, animate)
                w:_reveal(row.badgeLabel, { TextTransparency = 0.25 }, animate)
            end
            if row.iconLabel then
                w:_reveal(row.iconLabel, { ImageTransparency = 0.15 }, animate)
            end
            if row.removeGlyph then
                w:_reveal(row.removeGlyph, { TextTransparency = 0.55 }, animate)
            end
            for _, dot in row.gripDots do
                w:_reveal(dot, { BackgroundTransparency = if row.hovered then 0.15 else 0.45 }, animate)
            end
        end
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.emptyLabel, { TextTransparency = 1 }, animate)
        for _, row in self.rows do
            w:_reveal(row.frame, { BackgroundTransparency = 1 }, animate)
            w:_reveal(row.stroke, { Transparency = 1 }, animate)
            w:_reveal(row.title, { TextTransparency = 1 }, animate)
            if row.badge then
                w:_reveal(row.badge, { BackgroundTransparency = 1 }, animate)
                w:_reveal(row.badgeLabel, { TextTransparency = 1 }, animate)
            end
            if row.iconLabel then
                w:_reveal(row.iconLabel, { ImageTransparency = 1 }, animate)
            end
            if row.removeGlyph then
                w:_reveal(row.removeGlyph, { TextTransparency = 1 }, animate)
            end
            for _, dot in row.gripDots do
                w:_reveal(dot, { BackgroundTransparency = 1 }, animate)
            end
        end
    end
end

-- Room for the grip, the badge, the longest row title, and the remove button.
function ReorderList:_minWidth()
    local widest = functions.textWidth(self.window.theme.Font, 16, self.name)
    for _, entry in self.entries do
        widest = math.max(widest, functions.textWidth(self.window.theme.Font, 15, entry.name))
    end
    local chrome = sidePadding * 2 + 12 + gripDotSize * 2 + gripDotGap + 10
    if self.showIndex then
        chrome += badgeSize + 10
    end
    if self.removable then
        chrome += 38
    end
    return math.min(chrome + widest, 320)
end

function ReorderList:Remove()
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end
    if self.descriptor then
        self.descriptor:Remove()
    end
    self.main:Destroy()
end

return ReorderList

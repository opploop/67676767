--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 5: a collapsed header pill (name + a live gradient swatch + optional glow) that opens
-- into a stops rail (drag to reposition, add/remove) and the shared hsvEditor (hsvEditor.luau,
-- also used by ColorPicker) bound to whichever stop is selected. Value is a real ColorSequence,
-- built fresh from the stop list on every change.

local GradientPicker = {}
GradientPicker.__index = GradientPicker
GradientPicker.__type = "GradientPicker"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)
local hsvEditor = require(utility.hsvEditor)

local headerHeight = 44
local squareSize = 140
local narrowWidth = 380
local glowOnTransparency = 0.55
local minStops = 2
local maxStops = 8
local swatchSize = UDim2.fromOffset(44, 22)

local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- closing fades faster than it opens, and faster than the card shrinks, so the content is
-- gone before (or right as) the height tween finishes instead of visibly cutting off mid-fade
local closeFadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local openInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
-- closing height: Quart out, quick and clean, no overshoot (a shrink bouncing past its target
-- and back would read as jittery, not springy)
local heightInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
-- opening height: Back out - grows slightly past the final height then eases back, a little
-- bounce of "life" instead of a mechanical stop
local heightOpenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local chevronInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local dragInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local heldInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- header swatch "pop" on click - a quick squash out, a springier settle back
local popOutInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local popBackInfo = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- glow pulse on open: flashes brighter than the steady-state glow, then relaxes back down to it
local glowPulseInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local glowRelaxInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- preview bar wipe-reveal cover
local wipeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
-- stop handles popping in with a spring, staggered per handle
local handleSpringInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- delay between each staggered reveal group/handle when opening
local staggerStep = 0.05

local function clamp01(n)
    return math.clamp(n, 0, 1)
end

-- Sort by time, clamp the outer keypoints to exactly 0/1 (Roblox requires it), and nudge any
-- collapsed duplicates apart so ColorSequence.new never sees two keypoints at the same Time.
local function buildSequence(stops)
    local sorted = table.clone(stops)
    table.sort(sorted, function(a, b)
        return a.time < b.time
    end)

    local keypoints = {}
    for i, stop in sorted do
        local t = stop.time
        if i == 1 then
            t = 0
        elseif i == #sorted then
            t = 1
        end
        table.insert(keypoints, { time = t, color = stop.color })
    end
    for i = 2, #keypoints do
        if keypoints[i].time <= keypoints[i - 1].time then
            keypoints[i].time = math.min(1, keypoints[i - 1].time + 0.001)
        end
    end

    local built = {}
    for _, kp in keypoints do
        table.insert(built, ColorSequenceKeypoint.new(kp.time, kp.color))
    end
    return ColorSequence.new(built)
end

-- Roblox doesn't expose a Luau-side "sample this ColorSequence at t" helper (that's baked into
-- UIGradient's own renderer), so a new stop's starting colour is interpolated by hand between
-- its two nearest sorted neighbours.
local function colorAt(stops, t)
    local sorted = table.clone(stops)
    table.sort(sorted, function(a, b)
        return a.time < b.time
    end)
    if #sorted == 0 then
        return Color3.fromRGB(255, 255, 255)
    end
    if t <= sorted[1].time then
        return sorted[1].color
    end
    if t >= sorted[#sorted].time then
        return sorted[#sorted].color
    end
    for i = 1, #sorted - 1 do
        local a, b = sorted[i], sorted[i + 1]
        if t >= a.time and t <= b.time then
            local span = b.time - a.time
            local alpha = if span > 0 then (t - a.time) / span else 0
            return a.color:Lerp(b.color, alpha)
        end
    end
    return sorted[#sorted].color
end

-- Accepts a ColorSequence, or a plain list of {time, color} / {Color3, Color3, ...} (evenly
-- spread), or nil for a sensible default two-stop gradient.
local function normalizeStops(value)
    if typeof(value) == "ColorSequence" then
        local stops = {}
        for _, kp in value.Keypoints do
            table.insert(stops, { time = kp.Time, color = kp.Value })
        end
        return stops
    end
    if typeof(value) == "table" and #value > 0 then
        local stops = {}
        local isColorList = typeof(value[1]) == "Color3"
        for i, entry in value do
            if isColorList then
                table.insert(stops, { time = (i - 1) / math.max(1, #value - 1), color = entry })
            else
                table.insert(stops, {
                    time = clamp01(entry.time or entry.Time or 0),
                    color = entry.color or entry.Color or Color3.fromRGB(255, 255, 255),
                })
            end
        end
        -- ColorSequence.new needs at least 2 keypoints; a single-colour list still has to make
        -- a valid (if flat) gradient rather than error the whole element out.
        if #stops == 1 then
            table.insert(stops, { time = 1, color = stops[1].color })
        end
        return stops
    end
    return {
        { time = 0, color = Color3.fromRGB(52, 199, 89) },
        { time = 1, color = Color3.fromRGB(10, 132, 255) },
    }
end

function GradientPicker.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Gradient Picker",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        callback = properties.callback or properties.Callback or function() end,

        _isOpen = false,
        showGlow = if properties.glow ~= nil
            then properties.glow
            elseif properties.Glow ~= nil then properties.Glow
            else true,
    }, GradientPicker)

    self.stops = normalizeStops(
        properties.gradient or properties.Gradient or properties.value or properties.Value or properties.colors
    )
    self.selected = self.stops[1]
    self.value = buildSequence(self.stops)

    self.flag = properties.flag
        or properties.Flag
        or (not self.forgetState and functions.deriveFlagFromName(self.name) or nil)
    self.window:_registerControl(self)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, headerHeight),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.main)

    -- UIShadow only takes one flat Color3 - a single glow can't actually shimmer with the whole
    -- gradient. Layering three, sampled at 0/0.5/1 across the current stops and each softly
    -- blurred+transparent, blends into a real multi-hue halo instead of one flat tint.
    self.previewGlows = {}
    for _ = 1, 3 do
        table.insert(self.previewGlows, self.window:CreateGlow(self.main, self.stops[1].color, 26, 1))
    end

    self:_buildHeader()
    self:_buildBody()

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
        self:_popSwatch()
        if self._isOpen then
            self:_close()
        else
            self:_open()
        end
    end)

    self.window:ConnectFor(self, self.main.MouseEnter, function()
        if self._isOpen or not self.window:_interactive() then
            return
        end
        local theme = self.window.theme
        variables.tweenService
            :Create(self.stroke, fadeInfo, { Transparency = theme.ElementStrokeHoverTransparency, Color = theme.ElementStrokeHover })
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ElementTextHoverColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 0.97 }):Play()
    end)

    self.window:ConnectFor(self, self.main.MouseLeave, function()
        local theme = self.window.theme
        variables.tweenService
            :Create(self.stroke, fadeInfo, { Transparency = theme.ElementStrokeTransparency, Color = theme.ElementStroke })
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ContentColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 1 }):Play()
    end)

    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    self:_applyBodyVisibility(false, false)
    self:_setControlsVisible(false)

    self.window:ConnectFor(self, self.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.window.animating or (self.window.hidden and self.window.hasShownOnce) then
            return
        end
        self:_applyLayout()
    end)
    self:_applyLayout()

    self:_render("instant")

    return self
end

function GradientPicker:_buildHeader()
    local container = self.window:Create("Frame", {
        Size = UDim2.new(1, -90, 0, 16),
        Position = UDim2.new(0, 20, 0, headerHeight / 2),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 5,

            ImageTransparency = 1, -- In = 0

            Parent = container,
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
        LayoutOrder = 1,
        ZIndex = 5,

        TextTransparency = 1, -- In = 0

        Parent = container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- header swatch: a small pill painted with the live gradient itself (a real UIGradient), so
    -- the collapsed row already reads as "this is a gradient", not just a flat colour
    self.swatch = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0, headerHeight / 2),
        Size = swatchSize,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.swatch })
    self.swatchGradient = self.window:Create("UIGradient", { Color = self.value, Parent = self.swatch })

    -- chevron: 180deg = closed (matches dropdown.luau's own convention), tweens to 0 on open
    self.chevron = self.window:Create("ImageLabel", {
        Image = constants.icons.chevron,
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -68, 0, headerHeight / 2),
        Rotation = 180,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ZIndex = 3,

        ImageTransparency = 1, -- In = 0.4

        Parent = self.main,
    }, { ImageColor3 = "ContentColor" })

    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, headerHeight),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,

        Parent = self.main,
    })
end

function GradientPicker:_buildBody()
    -- live preview bar: the same gradient, big, full width, above the rail
    self.preview = self.window:Create("Frame", {
        Size = UDim2.new(1, -40, 0, 44),
        Position = UDim2.new(0, 20, 0, headerHeight),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = self.preview })
    self.previewStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- Open = 0.9

        Parent = self.preview,
    })
    self.previewGradient = self.window:Create("UIGradient", { Color = self.value, Parent = self.preview })

    -- wipe-reveal cover: a plain surface sitting over the preview, right-anchored so shrinking
    -- its width uncovers the gradient left-to-right instead of just fading in place. Reset to
    -- fully-covering (no animation) whenever the card closes, ready for the next open.
    self.previewCover = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,

        Parent = self.preview,
    }, { BackgroundColor3 = "StatBackground" })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = self.previewCover })

    -- stops rail: a thin track with a draggable circular handle per stop
    self.rail = self.window:Create("Frame", {
        Size = UDim2.fromOffset(0, 4),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.85

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.rail })

    self.railInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 20),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,

        Parent = self.rail,
    })

    self.stopHandles = {} -- stop -> { frame, ring }

    -- add / remove stop buttons, stacked under the rail
    -- plain text, no glyph: an emoji/icon-font symbol isn't guaranteed to rasterize on every
    -- client's font (unverified this session), and "+"/"-" alone read fine without one
    self.addButton = self:_buildStopButton("+  Add stop", 0)
    self.removeButton = self:_buildStopButton("-  Remove stop", 1)

    self.window:ConnectFor(self, self.addButton.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
        self:_addStop()
    end)
    self.window:ConnectFor(self, self.removeButton.MouseButton1Click, function()
        hapticEngine.click()
        soundEngine.click()
        self:_removeSelectedStop()
    end)

    for _, stop in self.stops do
        self:_createStopHandle(stop)
    end

    -- shared HSV editor, bound to whichever stop is selected
    local initHue, initSat, initVal = self.selected.color:ToHSV()
    self.hsv = hsvEditor.build(self.window, self, self.main, {
        squareSize = squareSize,
        hueHeight = 14,
        gap = 14,
        hue = initHue,
        sat = initSat,
        val = initVal,
        onChange = function(h, s, v)
            if not self.selected then
                return
            end
            self.selected.color = Color3.fromHSV(h, s, v)
            self:_render("drag")
            self:_fireCallback()
        end,
        onCommit = function()
            self.window:_persist(self)
        end,
    })

    self.window:ConnectFor(self, self.railInteract.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            -- a bare click on the track (not a handle) adds a stop right there
            local width = self.rail.AbsoluteSize.X
            if width <= 0 then
                return
            end
            local mouse = self:_mouseLocation()
            local t = clamp01((mouse.X - self.rail.AbsolutePosition.X) / width)
            self:_addStop(t)
        end
    end)
end

function GradientPicker:_buildStopButton(text, order)
    local button = self.window:Create("TextButton", {
        Size = UDim2.fromOffset(0, 32),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Text = text,
        TextSize = 14,
        AutoButtonColor = false,
        LayoutOrder = order,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.9
        TextTransparency = 1, -- Open = 0.15

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = button })
    return button
end

function GradientPicker:_mouseLocation()
    local mouse = variables.userInputService:GetMouseLocation()
    local screenGui = self.window.screenGui
    if screenGui and screenGui.IgnoreGuiInset then
        return mouse - variables.guiService:GetGuiInset()
    end
    return mouse
end

function GradientPicker:_createStopHandle(stop)
    local handle = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(stop.time, 0, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = stop.color,
        BorderSizePixel = 0,
        ZIndex = 3,

        -- a stop created while already open (Set()/_addStop from an open picker) has to start
        -- visible - nothing else is going to reveal it, since _applyBodyVisibility only fires
        -- on _open()/_close()
        BackgroundTransparency = if self._isOpen then 0 else 1,

        Parent = self.rail,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
    local ring = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,

        Transparency = 1, -- managed by _render (selection ring)

        Parent = handle,
    })
    local grabber = self.window:Create("TextButton", {
        Size = UDim2.fromOffset(30, 30),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,

        Parent = handle,
    })

    self.stopHandles[stop] = { frame = handle, ring = ring }

    self.window:ConnectFor(self, grabber.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self:_selectStop(stop)
            self:_beginDrag(stop, input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    return handle
end

function GradientPicker:_beginDrag(stop, isMouse)
    self._drag = stop
    self._dragIsMouse = isMouse
    local handle = self.stopHandles[stop]
    if handle then
        variables.tweenService:Create(handle.frame, heldInfo, { Size = UDim2.fromOffset(26, 26) }):Play()
    end

    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    self._dragConnection = variables.runService.RenderStepped:Connect(function()
        local mouseReleased = self._dragIsMouse
            and not variables.userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if self.window.unloaded or not self._drag or mouseReleased then
            if mouseReleased then
                self:_endDrag()
                return
            end
            if self._dragConnection then
                self._dragConnection:Disconnect()
                self._dragConnection = nil
            end
            return
        end
        self:_pumpDrag()
    end)
end

function GradientPicker:_pumpDrag()
    local width = self.rail.AbsoluteSize.X
    if width <= 0 or not self._drag then
        return
    end
    local mouse = self:_mouseLocation()
    local t = clamp01((mouse.X - self.rail.AbsolutePosition.X) / width)
    if t == self._drag.time then
        return
    end
    self._drag.time = t
    self.value = buildSequence(self.stops)
    self:_render("drag")
    self:_fireCallback()
end

function GradientPicker:_endDrag()
    local stop = self._drag
    self._drag = nil
    if stop then
        local handle = self.stopHandles[stop]
        if handle then
            variables.tweenService:Create(handle.frame, heldInfo, { Size = UDim2.fromOffset(20, 20) }):Play()
        end
    end
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end
    self.window:_persist(self)
end

function GradientPicker:_selectStop(stop)
    self.selected = stop
    local h, s, v = stop.color:ToHSV()
    self.hsv:SetColor(h, s, v, true)
    self:_render("animate")
end

-- Insert a new stop at `atTime` (defaults to the midpoint of the widest gap between existing
-- stops), coloured by interpolating the sequence at that point, then selects it.
function GradientPicker:_addStop(atTime)
    if #self.stops >= maxStops then
        return
    end

    if not atTime then
        local sorted = table.clone(self.stops)
        table.sort(sorted, function(a, b)
            return a.time < b.time
        end)
        local bestGap, bestMid = 0, 0.5
        for i = 1, #sorted - 1 do
            local gap = sorted[i + 1].time - sorted[i].time
            if gap > bestGap then
                bestGap = gap
                bestMid = (sorted[i].time + sorted[i + 1].time) / 2
            end
        end
        atTime = bestMid
    end

    local color = colorAt(self.stops, atTime)
    local stop = { time = clamp01(atTime), color = color }
    table.insert(self.stops, stop)
    self:_createStopHandle(stop)
    hapticEngine.click()
    soundEngine.click()
    self:_selectStop(stop)

    self.value = buildSequence(self.stops)
    self:_render("animate")
    self:_fireCallback()
    self.window:_persist(self)
end

function GradientPicker:_removeSelectedStop()
    if not self.selected or #self.stops <= minStops then
        return
    end

    local idx = table.find(self.stops, self.selected)
    if not idx then
        return
    end

    local handle = self.stopHandles[self.selected]
    if handle then
        handle.frame:Destroy()
    end
    self.stopHandles[self.selected] = nil
    table.remove(self.stops, idx)

    self.selected = self.stops[math.max(1, idx - 1)]
    if self.selected then
        local h, s, v = self.selected.color:ToHSV()
        self.hsv:SetColor(h, s, v, true)
    end

    self.value = buildSequence(self.stops)
    self:_render("animate")
    self:_fireCallback()
    self.window:_persist(self)
end

function GradientPicker:_render(mode)
    self.swatchGradient.Color = self.value
    self.previewGradient.Color = self.value

    -- sample the live gradient at 0/0.5/1 so the three stacked glows actually track whatever
    -- colours are currently at each end and the middle, not just whichever stop was leftmost
    self.previewGlows[1].Color = colorAt(self.stops, 0)
    self.previewGlows[2].Color = colorAt(self.stops, 0.5)
    self.previewGlows[3].Color = colorAt(self.stops, 1)

    for stop, handle in self.stopHandles do
        local pos = UDim2.new(stop.time, 0, 0.5, 0)
        if mode == "drag" or mode == "animate" then
            variables.tweenService
                :Create(handle.frame, if mode == "drag" then dragInfo else openInfo, { Position = pos, BackgroundColor3 = stop.color })
                :Play()
        else
            handle.frame.Position = pos
            handle.frame.BackgroundColor3 = stop.color
        end
        handle.ring.Transparency = if stop == self.selected and self._isOpen then 0 else 1
    end

    -- _removeSelectedStop already refuses to drop below minStops; this is just the visual cue
    variables.tweenService
        :Create(self.removeButton, fadeInfo, { TextTransparency = if #self.stops > minStops then 0.15 else 0.6 })
        :Play()
end

function GradientPicker:_fireCallback()
    self.window:_runGuarded(self, self.callback, self.value)
end

-- Quick tactile feedback on the header swatch the instant it's clicked, independent of (and
-- faster than) the open/close animation that follows - squashes narrower, then springs back
-- past its resting width before settling (Back easing) for a little bounce.
function GradientPicker:_popSwatch()
    local squashed = UDim2.fromOffset(swatchSize.X.Offset * 0.85, swatchSize.Y.Offset * 0.85)
    local outTween = variables.tweenService:Create(self.swatch, popOutInfo, { Size = squashed })
    outTween:Play()
    local connection
    connection = outTween.Completed:Connect(function()
        connection:Disconnect()
        variables.tweenService:Create(self.swatch, popBackInfo, { Size = swatchSize }):Play()
    end)
end

-- Stop handles pop in from a tiny point with a spring (Back easing), staggered left-to-right
-- by each stop's time so they read as a little cascade rather than popping in all at once.
-- animate = false/nil snaps instantly (used for the initial hidden state and on close).
function GradientPicker:_revealStopHandles(open, animate)
    if not animate then
        for _, handle in self.stopHandles do
            handle.frame.BackgroundTransparency = if open then 0 else 1
            handle.frame.Size = UDim2.fromOffset(20, 20)
            if not open then
                handle.ring.Transparency = 1
            end
        end
        return
    end

    if not open then
        for _, handle in self.stopHandles do
            variables.tweenService:Create(handle.frame, animate, { BackgroundTransparency = 1 }):Play()
            handle.ring.Transparency = 1
        end
        return
    end

    local sorted = table.clone(self.stops)
    table.sort(sorted, function(a, b)
        return a.time < b.time
    end)
    for i, stop in sorted do
        local handle = self.stopHandles[stop]
        if handle then
            handle.frame.Size = UDim2.fromOffset(2, 2)
            handle.frame.BackgroundTransparency = 0
            task.delay((i - 1) * 0.04, function()
                if self._isOpen then
                    variables.tweenService:Create(handle.frame, handleSpringInfo, { Size = UDim2.fromOffset(20, 20) }):Play()
                end
            end)
        end
    end
end

function GradientPicker:_open()
    if self._isOpen then
        return
    end
    self._isOpen = true
    self._openSeq = (self._openSeq or 0) + 1
    local seq = self._openSeq
    self:_setControlsVisible(true)

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
    end
    self._outsideClickConn = self.window:Connect(variables.userInputService.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local pos = input.Position
        local mainPos = self.main.AbsolutePosition
        local mainSize = self.main.AbsoluteSize
        if pos.X < mainPos.X or pos.X > mainPos.X + mainSize.X or pos.Y < mainPos.Y or pos.Y > mainPos.Y + mainSize.Y then
            self:_close()
        end
    end)

    -- 1) card grows with a slight bounce past its final height instead of a flat stop
    variables.tweenService:Create(self.main, heightOpenInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    if self.chevron then
        variables.tweenService:Create(self.chevron, chevronInfo, { Rotation = 0 }):Play()
    end

    -- 4) glow pulse: flashes past its steady-state glow, then relaxes back down to it
    if self.showGlow then
        for _, glow in self.previewGlows do
            variables.tweenService:Create(glow, glowPulseInfo, { Transparency = math.max(0, glowOnTransparency - 0.3) }):Play()
        end
        task.delay(glowPulseInfo.Time, function()
            if self._isOpen and self._openSeq == seq then
                for _, glow in self.previewGlows do
                    variables.tweenService:Create(glow, glowRelaxInfo, { Transparency = glowOnTransparency }):Play()
                end
            end
        end)
    end

    -- 2) + 5) staggered reveal: preview bar (wiping its cover away) first, then the rail +
    -- buttons + stop handles (spring-popping in, see _revealStopHandles), then the HSV editor
    variables.tweenService:Create(self.preview, fadeInfo, { BackgroundTransparency = 0 }):Play()
    variables.tweenService:Create(self.previewStroke, fadeInfo, { Transparency = 0.9 }):Play()
    variables.tweenService:Create(self.previewCover, wipeInfo, { Size = UDim2.fromScale(0, 1) }):Play()

    task.delay(staggerStep, function()
        if not self._isOpen or self._openSeq ~= seq then
            return
        end
        variables.tweenService:Create(self.rail, fadeInfo, { BackgroundTransparency = 0.85 }):Play()
        variables.tweenService:Create(self.addButton, fadeInfo, { BackgroundTransparency = 0.9, TextTransparency = 0.15 }):Play()
        variables.tweenService:Create(self.removeButton, fadeInfo, { BackgroundTransparency = 0.9, TextTransparency = 0.15 }):Play()
        self:_revealStopHandles(true, fadeInfo)
    end)

    task.delay(staggerStep * 2, function()
        if not self._isOpen or self._openSeq ~= seq then
            return
        end
        self.hsv:SetVisible(true, true)
    end)

    self:_render("animate")
end

function GradientPicker:_close()
    if not self._isOpen then
        return
    end
    self._isOpen = false
    self._openSeq = (self._openSeq or 0) + 1 -- invalidates any staggered/delayed open steps still pending

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end
    if self._drag then
        self:_endDrag()
    end

    -- everything fades out together (no stagger) on the quicker closeFadeInfo, so the content
    -- is gone before (or right as) the height tween below finishes instead of cutting off mid-fade
    variables.tweenService:Create(self.preview, closeFadeInfo, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(self.previewStroke, closeFadeInfo, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.rail, closeFadeInfo, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(self.addButton, closeFadeInfo, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
    variables.tweenService:Create(self.removeButton, closeFadeInfo, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
    self:_revealStopHandles(false, closeFadeInfo)
    self.previewCover.Size = UDim2.fromScale(1, 1) -- reset instantly, ready to wipe again next open
    self.hsv:SetVisible(false, true)
    self:_render("animate") -- also drops the selection ring now that _isOpen is false
    variables.tweenService:Create(self.main, heightInfo, { Size = UDim2.new(1, -20, 0, headerHeight) }):Play()
    if self.chevron then
        variables.tweenService:Create(self.chevron, chevronInfo, { Rotation = 180 }):Play()
    end

    task.delay(closeFadeInfo.Time, function()
        if not self._isOpen then
            self:_setControlsVisible(false)
        end
    end)
end

-- Only the instant (open = init/close) snap path now - the animated open sequence lives inline
-- in _open() so it can stagger; _close() plays its own (simultaneous, not staggered) tweens.
function GradientPicker:_applyBodyVisibility(open, animate)
    local set = {
        [self.preview] = { BackgroundTransparency = if open then 0 else 1 },
        [self.previewStroke] = { Transparency = if open then 0.9 else 1 },
        [self.rail] = { BackgroundTransparency = if open then 0.85 else 1 },
        [self.addButton] = { BackgroundTransparency = if open then 0.9 else 1, TextTransparency = if open then 0.15 else 1 },
        [self.removeButton] = { BackgroundTransparency = if open then 0.9 else 1, TextTransparency = if open then 0.15 else 1 },
    }

    for instance, props in set do
        if animate then
            variables.tweenService:Create(instance, animate, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end
    self:_revealStopHandles(open, animate)
    if not open then
        self.previewCover.Size = UDim2.fromScale(1, 1)
    end
end

function GradientPicker:_setControlsVisible(visible)
    for _, frame in { self.preview, self.rail, self.addButton, self.removeButton } do
        frame.Visible = visible
    end
end

-- Wide: rail + buttons left, square+hue right, side by side under the preview bar.
-- Narrow: stacked, editor centred underneath.
function GradientPicker:_applyLayout()
    local width = self.main.AbsoluteSize.X
    local mode = if width > 0 and width < narrowWidth then "narrow" else "wide"
    if mode == self._layoutMode then
        return
    end
    self._layoutMode = mode

    local leftWidth = if mode == "wide" then UDim.new(1, -(20 + squareSize + 16 + 20)) else UDim.new(1, -40)
    local y = headerHeight + 44 + 16 -- under the preview bar

    self.rail.Position = UDim2.new(0, 20 + 10, 0, y + 13)
    self.rail.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset - 20, 0, 4)

    y += 34
    self.addButton.Position = UDim2.new(0, 20, 0, y)
    self.addButton.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 32)
    y += 32 + 8
    self.removeButton.Position = UDim2.new(0, 20, 0, y)
    self.removeButton.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 32)
    local leftBottom = y + 32

    if mode == "wide" then
        self.hsv.root.Position = UDim2.new(1, -20 - squareSize, 0, headerHeight + 44 + 16)
        self._openHeight = math.max(leftBottom, headerHeight + 44 + 16 + squareSize + 14 + 14) + 20
    else
        local hsvY = leftBottom + 16
        self.hsv.root.Position = UDim2.new(0.5, -squareSize / 2, 0, hsvY)
        self._openHeight = hsvY + squareSize + 14 + 14 + 20
    end

    if self._isOpen then
        variables.tweenService:Create(self.main, heightInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    end
end

-- value: ColorSequence, or a plain list (Color3s evenly spread, or {time, color} tables)
function GradientPicker:Set(value, skipCallback)
    self.stops = normalizeStops(value)
    for _, handle in self.stopHandles do
        handle.frame:Destroy()
    end
    self.stopHandles = {}
    for _, stop in self.stops do
        self:_createStopHandle(stop)
    end
    self.selected = self.stops[1]
    local h, s, v = self.selected.color:ToHSV()
    self.hsv:SetColor(h, s, v, false)

    self.value = buildSequence(self.stops)
    self:_render(if skipCallback then "instant" else "animate")

    if not skipCallback then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

function GradientPicker:SetGlow(shown)
    self.showGlow = shown and true or false
    for _, glow in self.previewGlows do
        variables.tweenService:Create(glow, fadeInfo, { Transparency = if self.showGlow then glowOnTransparency else 1 }):Play()
    end
end

-- Persistence: "time:hex,time:hex,..." - a plain flat string like every other flag value.
function GradientPicker:_serialize()
    local parts = {}
    for _, stop in self.stops do
        table.insert(parts, string.format("%.4f:%s", stop.time, stop.color:ToHex()))
    end
    return table.concat(parts, ",")
end

function GradientPicker:_deserialize(raw)
    local stops = {}
    for part in tostring(raw):gmatch("[^,]+") do
        local t, hex = part:match("^([%d%.]+):(%x+)$")
        if t and hex then
            local ok, color = pcall(Color3.fromHex, hex)
            if ok then
                table.insert(stops, { time = clamp01(tonumber(t)), color = color })
            end
        end
    end
    if #stops >= minStops then
        self:Set(stops)
    end
end

function GradientPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.swatch, { BackgroundTransparency = 0 }, animate)
        w:_reveal(self.chevron, { ImageTransparency = 0.4 }, animate)
        for _, glow in self.previewGlows do
            w:_reveal(glow, { Transparency = if self.showGlow then glowOnTransparency else 1 }, animate)
        end
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.swatch, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.chevron, { ImageTransparency = 1 }, animate)
        for _, glow in self.previewGlows do
            w:_reveal(glow, { Transparency = 1 }, animate)
        end
        if self._isOpen then
            self:_close()
        end
    end
end

moveable(GradientPicker)

return GradientPicker

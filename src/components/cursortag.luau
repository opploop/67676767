--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A hover area where a small chip trails the cursor, like a designer name tag on a canvas.
-- Hovering the card activates it; every frame it eases toward the mouse and clamps to its
-- scope's bounds so it never leaves that container - `area` is its own card, `window` is the
-- whole window, `screen` is the full viewport. SetEnabled opts into following anywhere within
-- those bounds instead of only while the card itself is hovered (handy for window/screen
-- scope, which has no card-sized area of its own to hover), but it still hides once the
-- cursor actually leaves them.

local CursorTag = {}
CursorTag.__index = CursorTag
CursorTag.__type = "CursorTag"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)

local defaultHeight = 70
local defaultEase = 0.22 -- per-frame Lerp factor toward the target; not a Tween, a continuous chase
local scopes = { area = true, window = true, screen = true }

function CursorTag.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local scope = string.lower(tostring(properties.scope or properties.Scope or "area"))
    if not scopes[scope] then
        scope = "area"
    end

    local offset = properties.offset or properties.Offset or Vector2.new(14, 14)
    if typeof(offset) == "table" then
        offset = Vector2.new(offset.x or offset.X or 0, offset.y or offset.Y or 0)
    end

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        text = properties.text or properties.Text or "You",
        placeholder = properties.placeholder or properties.Placeholder or "Move your mouse over this area",
        scope = scope,
        offset = offset,
        height = properties.height or properties.Height or defaultHeight,
        ease = properties.ease or properties.Ease or defaultEase,

        _active = false,
    }, CursorTag)

    self:_build()

    return self
end

function CursorTag:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, self.height),
        BorderSizePixel = 0,
        Name = "CursorTag",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    self.placeholderLabel = window:Create("TextLabel", {
        Text = locale.t(self.placeholder),
        Size = UDim2.new(1, -30, 1, -20),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,

        TextTransparency = 1, -- In = 0.55

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,

        Parent = self.main,
    })

    -- Self-calibrating mouse position: GuiObject.MouseMoved reports (x, y) already in
    -- AbsolutePosition's coordinate space by construction (it's Roblox's own hit-test, not
    -- ours to get wrong), so comparing it against GetMouseLocation() at the same instant gives
    -- the exact correction needed - whatever it is on this client/executor - without hardcoding
    -- a GuiInset guess that turned out to be wrong here. Learned fresh each time the mouse
    -- crosses the card; good enough to carry outside it for window/screen scope afterward.
    self._calibration = Vector2.zero
    window:ConnectFor(self, self.interact.MouseMoved, function(x, y)
        local raw = variables.userInputService:GetMouseLocation()
        self._calibration = Vector2.new(x, y) - raw
    end)

    -- The chip lives at the top of the screenGui, not nested under main: a tab page is a
    -- ScrollingFrame and clips its own content, which would cut the chip off the moment
    -- window/screen scope lets it roam past the page's edge.
    self.chip = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 28),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = constants.zIndex.cursorTag,

        Parent = window.screenGui,
    }, { BackgroundColor3 = "AccentColor" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.chip,
    })

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),

        Parent = self.chip,
    })

    self.chipLabel = window:Create("TextLabel", {
        Text = locale.t(self.text),
        Size = UDim2.fromOffset(0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextColor3 = functions.contrastColor(window.theme.AccentColor),
        ZIndex = constants.zIndex.cursorTag,

        Parent = self.chip,
    }, { FontFace = "Font" })

    -- Driven by a continuous per-frame bounds check (see _tick) rather than main.MouseEnter/
    -- MouseLeave: a placeholder-only card has nothing else to steal hover from it, but once a
    -- dev nests real controls inside one, THEIR MouseEnter fires a MouseLeave on the frame
    -- underneath it first, flickering the chip off and on every time the cursor crosses a
    -- child. A plain "is the mouse inside my bounds right now" check every frame has no such
    -- event ordering to fight, so it fades out only once the cursor truly leaves the container.
    self:_startLoop()
end

function CursorTag:_bounds()
    local window = self.window
    if self.scope == "window" and window.main then
        return window.main.AbsolutePosition, window.main.AbsoluteSize
    elseif self.scope == "screen" and window.screenGui then
        return Vector2.zero, window.screenGui.AbsoluteSize
    end
    return self.main.AbsolutePosition, self.main.AbsoluteSize
end

local function pointInside(point, pos, size)
    return point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
end

-- One background loop for the element's whole life, started once at build. Cheap (a couple of
-- comparisons) even while idle, and it's what lets activation be a plain "is the mouse inside
-- right now" check instead of a MouseEnter/MouseLeave pair a nested child's own hover can
-- interrupt. task.wait() rather than a RenderStepped:Connect - the same shape Window's own
-- LiveAnimation loop uses - since a couple of executors don't reliably drive a plain
-- RenderStepped connection made from injected code, leaving it looking connected but never
-- actually firing.
function CursorTag:_startLoop()
    if self._looping then
        return
    end
    self._looping = true
    task.spawn(function()
        -- self.main.Parent stops the loop the same way ScrollHint's bounce does: once
        -- Tab:Remove tears the instances down there's nothing left to check bounds against
        while self._looping and self.main.Parent do
            self:_tick()
            task.wait()
        end
    end)
end

function CursorTag:_mousePos()
    return self.window:_mouseAbsolutePosition() + self._calibration
end

function CursorTag:_tick()
    if not self.window:_interactive() or not self.main.Visible or self.main.AbsoluteSize.Magnitude == 0 then
        self:_setActive(false) -- e.g. its tab isn't the one on screen, or the window's hidden
        return
    end

    local mouse = self:_mousePos()
    local boundsPos, boundsSize = self:_bounds()

    -- _forced is nil (no override, hover over the card decides), true (follow anywhere within
    -- the scope's bounds, e.g. a toggle enabling a window-scope tag with nothing to hover), or
    -- false (forced off, wins even while still hovering the card so it doesn't spring back on
    -- a tick later)
    local active
    if self._forced == false then
        active = false
    elseif self._forced == true then
        active = pointInside(mouse, boundsPos, boundsSize)
    else
        active = pointInside(mouse, self.main.AbsolutePosition, self.main.AbsoluteSize)
    end

    self:_setActive(active)
    if active then
        self:_followMouse(mouse, boundsPos, boundsSize)
    end
end

function CursorTag:_followMouse(mouse, boundsPos, boundsSize)
    local targetX, targetY = mouse.X + self.offset.X, mouse.Y + self.offset.Y

    local chipSize = self.chip.AbsoluteSize
    local minX, maxX = boundsPos.X, boundsPos.X + boundsSize.X - chipSize.X
    local minY, maxY = boundsPos.Y, boundsPos.Y + boundsSize.Y - chipSize.Y
    targetX = math.clamp(targetX, minX, math.max(minX, maxX))
    targetY = math.clamp(targetY, minY, math.max(minY, maxY))

    local current = self.chip.AbsolutePosition
    local eased = current:Lerp(Vector2.new(targetX, targetY), self.ease)
    self.chip.Position = UDim2.fromOffset(eased.X, eased.Y)
end

local fadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Cross-fades the chip in/out. Only fires on an actual state change, so the per-frame tick
-- calling this every frame while active is a no-op past the first one.
function CursorTag:_setActive(active)
    if self._active == active then
        return
    end
    self._active = active

    if active then
        -- land on the mouse immediately rather than easing in from wherever it last was
        local mouse = self:_mousePos()
        self.chip.Position = UDim2.fromOffset(mouse.X + self.offset.X, mouse.Y + self.offset.Y)
        self.chip.Visible = true
        self.chip.BackgroundTransparency = 1
        self.chipLabel.TextTransparency = 1
        variables.tweenService:Create(self.chip, fadeInfo, { BackgroundTransparency = 0 }):Play()
        variables.tweenService:Create(self.chipLabel, fadeInfo, { TextTransparency = 0 }):Play()
    else
        self._fadeToken = (self._fadeToken or 0) + 1
        local token = self._fadeToken
        variables.tweenService:Create(self.chip, fadeInfo, { BackgroundTransparency = 1 }):Play()
        variables.tweenService:Create(self.chipLabel, fadeInfo, { TextTransparency = 1 }):Play()
        task.delay(fadeInfo.Time, function()
            if self._fadeToken == token then
                self.chip.Visible = false
            end
        end)
    end
end

-- Opts into following the cursor anywhere within the scope's bounds, not just while hovering
-- the card - useful for window/screen scope, which has no natural "hover to activate" trigger
-- of its own otherwise. Still hides once the cursor actually leaves those bounds; it isn't a
-- permanent show. false forces it off outright, winning even while the card's hovered. The
-- next tick (a frame away at most) applies either state. Call ClearEnabled to hand control
-- back to plain hover-the-card.
function CursorTag:SetEnabled(enabled)
    self._forced = enabled and true or false
end

-- Hands control back to hover-driven activation after a SetEnabled override.
function CursorTag:ClearEnabled()
    self._forced = nil
end

-- Update the chip's label at runtime.
function CursorTag:Set(text)
    self.text = tostring(text)
    self.chipLabel.Text = locale.resolve(self.text)
end

function CursorTag:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.placeholderLabel, { TextTransparency = 0.55 }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.placeholderLabel, { TextTransparency = 1 }, animate)
        self:_setActive(false)
    end
end

-- The chip's colour rides a themeProperty already; only its contrast-computed text needs a
-- manual refresh when AccentColor changes.
function CursorTag:_refreshTheme()
    self.chipLabel.TextColor3 = functions.contrastColor(self.window.theme.AccentColor)
end

moveable(CursorTag)

return CursorTag

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Toggle = {}
Toggle.__index = Toggle
Toggle.__type = "Toggle"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)
local log = require(utility.log)

local defaultLoopInterval = 0.5

function Toggle.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Switch",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState, -- dont save config for this element if true.
        compact = tab.compact or false, -- true when the host is a Row
        locked = properties.locked or properties.Locked or false,

        flag = properties.flag
            or properties.Flag
            or (
                not (properties.forgetState or properties.ForgetState or tab.forgetState)
                    and functions.deriveFlagFromName(properties.name or properties.Name or "Switch")
                or nil
            ),

        callback = properties.callback or properties.Callback or function() end,

        value = if (properties.value or properties.Value) ~= nil then (properties.value or properties.Value) else false,
    }, Toggle)

    -- register as a saveable control if flagged (works in a row too)
    self.window:_registerControl(self)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    -- centred on the switch pill itself (works for both the fixed-offset full layout and the
    -- flex-positioned compact one, since functionContainer's own position tracks either way)
    self.lockIcon = self.window:_buildLockIcon(self.functionContainer, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
    self.prohibitedIcon = self.window:_buildProhibitedIcon(self.container)
    self:_applyLocked(false)

    self.window:_wireTooltip(self)

    if self.description and not self.compact then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    -- Loop() below uses task.spawn/task.wait, not a Window:Connect signal, so Window:Unload's
    -- own connection-teardown never reaches it on its own - this closes that gap unconditionally
    -- (cheap no-op on a toggle that never calls Loop at all).
    self.window:OnUnload(function()
        self:_stopLoop()
    end)

    return self
end

-- Runs `fn(toggle)` on a repeating timer for as long as this toggle is on - starts immediately
-- if it's already on when this is called (e.g. autoLoad already restored `true` before your
-- script gets a chance to call this), stops the moment it's turned off, and restarts fresh every
-- time it's turned back on. fn can return a number to wait before the next call instead of
-- `interval` (default 0.5s) - the same "return your own next-tick delay" shape a hand-rolled
-- `while` loop already uses in most feature scripts, just managed.
--
-- The point of this over a hand-rolled `while toggle.value do task.wait() ... end` in the
-- toggle's own callback: an uncaught error in a raw loop like that kills its coroutine silently
-- (task.spawn swallows it) with nothing to restart it and nothing telling the toggle it's now
-- lying about the feature's real state - exactly the "turn it on and it does nothing, or it runs
-- for a while then quietly stops" symptom a hand-rolled loop is prone to. Loop() below pcalls
-- every single iteration instead of the whole loop, so one bad tick logs a warning and tries
-- again next tick rather than ending the feature for the rest of the session.
function Toggle:Loop(fn: (toggle: any) -> number?, interval: number?)
    self._loopFn = fn
    self._loopInterval = interval or defaultLoopInterval
    if self.value then
        self:_startLoop()
    end
end

function Toggle:_startLoop()
    if self._loopRunning or not self._loopFn then
        return
    end
    self._loopRunning = true
    -- stamped so a stale iteration that's mid-task.wait when the loop is stopped (and possibly
    -- restarted before that wait resumes) can tell it's no longer the current run and exit
    -- instead of doubling up with the fresh one.
    self._loopGeneration = (self._loopGeneration or 0) + 1
    local generation = self._loopGeneration
    task.spawn(function()
        while self._loopRunning and self._loopGeneration == generation do
            local ok, result = pcall(self._loopFn, self)
            if not ok then
                log.warn("Rayfield: Toggle '" .. tostring(self.name) .. "' loop errored - " .. tostring(result))
            end
            if self._loopGeneration ~= generation then
                break -- stopped (or restarted) while fn itself was running
            end
            local delay = if ok and typeof(result) == "number" then result else self._loopInterval
            task.wait(math.max(delay, 0.03))
        end
    end)
end

function Toggle:_stopLoop()
    self._loopRunning = false
    self._loopGeneration = (self._loopGeneration or 0) + 1
end

-- the pill switch. same in both layouts; caller places it (pinned right / flex item)
function Toggle:_buildSwitch(parent)
    local window = self.window

    self.functionContainer = window:Create("Frame", {
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(50, 21),

        BackgroundTransparency = 1, -- In = ToggleTrackTransparency

        Parent = parent,
    }, { BackgroundColor3 = "ToggleTrack" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = self.functionContainer,
    })

    self.containerStroke = window:Create("UIStroke", {
        Transparency = 1, -- In = 0.85
        Parent = self.functionContainer,
    }, { Color = "SurfaceStroke" })

    self.indicator = window:Create("Frame", {
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(25, 17),
        Position = self.value and UDim2.new(1, -28, 0.5, 0) or UDim2.new(1, -47, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = self.value and self.window.theme.AccentColor or self.window.theme.ToggleKnobOff,

        BackgroundTransparency = 1, -- In = 0.8

        Parent = self.functionContainer,
    })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.indicator,
    })

    self.indicatorStroke = window:Create("UIStroke", {
        Color = self.value and self.window.theme.AccentStroke or Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- In = 0.7
        Parent = self.indicator,
    })

    -- Accent glow behind the selector; hidden until on (gated by Transparency: 1 hidden, AccentGlow shown)
    self.indicatorGlow = window:CreateGlow(self.indicator, "AccentColor", 20, 1)

    -- Dark wash over the switch for light themes (hidden on dark themes via DarkToggleOverlay).
    self.overlay = window:Create("Frame", {
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0, 0),
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = 0

        Parent = self.functionContainer,
    }, { Visible = "DarkToggleOverlay" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = self.overlay,
    })

    self.overlayGradient = window:Create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0.35),
        }),

        Parent = self.overlay,
    })

    return self.functionContainer
end

-- flip, animate, run callback (error-flash on fail), autosave. press anim is per-layout
function Toggle:_performToggle()
    hapticEngine.click()
    soundEngine.click()
    self.value = not self.value
    self:_animateIndicator()

    self.window:_runGuarded(self, self.callback, self.value)
    self.window:_persist(self)
end

-- full-width: title/icon left, pill pinned right, width-bounce
function Toggle:_buildFull()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 41),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)
    self.hoverOverlay = window:CreateHoverOverlay(self.main)

    self.container = window:Create("Frame", {
        BorderSizePixel = 0,

        Parent = self.main,
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    })

    self.containerLayout = window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(250, 16),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        AutomaticSize = Enum.AutomaticSize.X,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(1, 0.5),
        AnchorPoint = Vector2.new(1, 0.5),
        TextTransparency = 1,
        ZIndex = 10,

        Parent = self.main,
    })

    -- pill pinned to the right edge
    self:_buildSwitch(self.main)
    self.functionContainer.Position = UDim2.new(1, -15, 0, 20)
    self.functionContainer.AnchorPoint = Vector2.new(1, 0.5)

    self.window:_wireElementHover(self)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()
        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { Size = UDim2.new(1, -26, 0, 41) }
            )
            :Play()

        self:_performToggle()

        task.wait(0.11)

        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { Size = UDim2.new(1, -20, 0, 41) }
            )
            :Play()
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = self.window.theme.ElementStrokeTransparency }
            )
            :Play()
    end)
end

-- compact (row): title left, pill right (SpaceBetween)
function Toggle:_buildCompact()
    local window = self.window

    -- interact sits at ZIndex 10 so the switch pill layers cleanly over the row (see button.luau)
    self.main, self.stroke, self.interact = window:_buildCompactRow(self.tab, self.name, 10)
    self.hoverOverlay = self.interact

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 15),
        PaddingRight = UDim.new(0, 15),

        Parent = self.interact,
    })

    -- title left, pill right
    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
        Padding = UDim.new(0, 10),

        Parent = self.interact,
    })

    self.container = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,

        Parent = self.interact,
    })

    -- text gives up room to the pill when tight
    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.container,
    })

    window:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            LayoutOrder = 0,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- grows to its text, shrinks + ellipsizes when tight
    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    -- pill as the right-hand flex item
    self:_buildSwitch(self.interact)
    self.functionContainer.LayoutOrder = 1

    self.window:_wireElementHover(self)

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        if self.locked then
            return
        end
        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = 1 }
            )
            :Play()

        self:_performToggle()

        task.wait(0.11)

        variables.tweenService
            :Create(
                self.stroke,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Transparency = self.window.theme.ElementStrokeTransparency }
            )
            :Play()
    end)
end

function Toggle:_applyLocked(animate)
    self.window:_applyLockedVisual(self, animate)
end

function Toggle:SetLocked(locked)
    locked = locked and true or false
    if locked == self.locked then
        return
    end
    self.locked = locked
    self:_applyLocked(true)
end

function Toggle:_animateIndicator()
    local info = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
    if self.indicatorGlow then
        variables.tweenService
            :Create(self.indicatorGlow, info, { Transparency = self.value and self.window.theme.AccentGlow or 1 })
            :Play()
    end
    if self.value then
        variables.tweenService
            :Create(self.indicator, info, {
                Position = UDim2.new(1, -28, 0.5, 0),
                BackgroundColor3 = self.window.theme.AccentColor,
                BackgroundTransparency = 0,
            })
            :Play()
        variables.tweenService
            :Create(self.indicatorStroke, info, { Color = self.window.theme.AccentStroke, Transparency = 0 })
            :Play()
    else
        variables.tweenService
            :Create(self.indicator, info, {
                Position = UDim2.new(1, -47, 0.5, 0),
                BackgroundColor3 = self.window.theme.ToggleKnobOff,
                BackgroundTransparency = self.window.theme.ToggleKnobOffTransparency,
            })
            :Play()
        variables.tweenService
            :Create(self.indicatorStroke, info, { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7 })
            :Play()
    end
end

local toggleReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
-- glow delayed so it doesn't bleed through the fill fade-in on window open
local toggleGlowReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0.35)
-- Live-caught: the knob (the actual on/off state - colour + position) faded in on the exact same
-- beat as the track it sits on, so a lit green knob could read as "there" before the track
-- underneath it had faded in enough to look like a real switch yet. A small delay - after the
-- track (toggleReveal, no delay) but before the glow (toggleGlowReveal, 0.35s) - puts the reveal
-- in the order it's actually built: track, then the knob sitting on it, then its glow.
local toggleStateReveal = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0.12)

function Toggle:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        -- carry the state colours here too, so revealing on a tab switch also picks up the theme
        w:_reveal(self.indicator, {
            BackgroundColor3 = self.value and w.theme.AccentColor or w.theme.ToggleKnobOff,
            BackgroundTransparency = self.value and 0 or w.theme.ToggleKnobOffTransparency,
        }, animate, toggleStateReveal)
        w:_reveal(self.indicatorStroke, {
            Color = self.value and w.theme.AccentStroke or Color3.fromRGB(255, 255, 255),
            Transparency = self.value and 0 or 0.7,
        }, animate, toggleStateReveal)
        w:_reveal(
            self.indicatorGlow,
            { Transparency = self.value and w.theme.AccentGlow or 1 },
            animate,
            toggleGlowReveal
        )
        w:_reveal(self.overlay, { BackgroundTransparency = 0 }, animate, toggleReveal)
        w:_reveal(self.containerStroke, { Transparency = 0.85 }, animate, toggleReveal)
        w:_reveal(
            self.functionContainer,
            { BackgroundTransparency = w.theme.ToggleTrackTransparency },
            animate,
            toggleReveal
        )
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.indicator, { BackgroundTransparency = 1 }, animate, toggleReveal)
        w:_reveal(self.indicatorStroke, { Transparency = 1 }, animate, toggleReveal)
        w:_reveal(self.indicatorGlow, { Transparency = 1 }, animate, toggleGlowReveal)
        w:_reveal(self.overlay, { BackgroundTransparency = 1 }, animate, toggleReveal)
        w:_reveal(self.containerStroke, { Transparency = 1 }, animate, toggleReveal)
        w:_reveal(self.functionContainer, { BackgroundTransparency = 1 }, animate, toggleReveal)
    end
end

-- Re-apply the visuals that aren't plain themeProperties (the knob's state colour + the reveal
-- transparencies) so a runtime ChangeTheme reaches the switch. Called on the visible tab only.
function Toggle:_refreshTheme()
    local t = self.window.theme
    local info = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local ts = variables.tweenService
    ts:Create(self.functionContainer, info, { BackgroundTransparency = t.ToggleTrackTransparency }):Play()
    ts:Create(self.indicator, info, {
        BackgroundColor3 = self.value and t.AccentColor or t.ToggleKnobOff,
        BackgroundTransparency = self.value and 0 or t.ToggleKnobOffTransparency,
    }):Play()
    ts:Create(self.indicatorStroke, info, {
        Color = self.value and t.AccentStroke or Color3.fromRGB(255, 255, 255),
    }):Play()
    if self.indicatorGlow then
        ts:Create(self.indicatorGlow, info, { Transparency = self.value and t.AccentGlow or 1 }):Play()
    end
end

-- Room the compact toggle needs: side padding + icon (and gap) if shown + title text
-- + the gap to the pill + the pill itself. Lets a horizontal group wrap sensibly.
function Toggle:_minWidth()
    local w = 30 + 10 + 50 -- 15+15 padding, 10 gap to pill, 50 pill
    if self.icon then
        w += 21 -- 16 icon + 5 gap
    end
    w += functions.textWidth(self.window.theme.Font, 16, self.name)
    return w
end

moveable(Toggle)

-- Live status line: like `description`, but meant to be updated repeatedly (an automation loop
-- reporting "12/48 claimed" every tick) rather than set once at creation. Reuses the same
-- descriptor slot description already uses - lazily creates one if this toggle didn't start with
-- a description, and reveals it immediately if the toggle's already on screen (a plain text swap
-- on an existing label, not a fresh element needing the tab's own reveal pass).
function Toggle:SetStatus(text)
    if self.compact then
        return -- no room for a status line in a row layout
    end
    if not self.descriptor then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = text })
        self.descriptor.main.LayoutOrder = self.main.LayoutOrder + 1
        if not self.window.hidden then
            self.window:_reveal(self.descriptor.titleLabel, { TextTransparency = 0.7 }, false)
        end
    else
        self.descriptor.description = text
        self.descriptor.titleLabel.Text = text
    end
end

function Toggle:Set(value, skipCallback)
    local changed = self.value ~= value
    self.value = value

    if changed then
        self:_animateIndicator()
        if self._loopFn then
            if value then
                self:_startLoop()
            else
                self:_stopLoop()
            end
        end
    end

    -- fire even when unchanged: config load calls Set and relies on the callback to apply
    if not skipCallback then
        self.window:_runGuarded(self, self.callback, self.value)
        self.window:_persist(self) -- skipCallback means apply quietly, so dont autosave either
    end
end

return Toggle

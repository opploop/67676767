--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 8 "corner grip": a small drag handle in the window's bottom-right corner that resizes
-- self.main freely (clamped, see windowSizing.clampUserSize). self.main's AnchorPoint is
-- (0.5, 0.5), so a naive Size change would grow/shrink the window from its centre - every resize
-- here also nudges Position by half the size delta in the same direction, so the top-left corner
-- stays put and only the bottom-right edge (where the grip lives) actually moves, matching how an
-- OS window resize handle behaves.
--
-- Committed on release, not live every frame: self.size/self.customSize only take the new size
-- once the drag ends, so every other system that reads them mid-drag (the reveal target,
-- _applyWindowSize's own viewport refit, the drag bar's position calc) isn't fighting a value
-- that's changing 60 times a second. Persisted to disk on release too, so it survives a restart.
-- Double-click snaps back to the window's original screen-fit size (self.window.defaultSize, the
-- dev-supplied/built-in size from construction - never overwritten by a later resize) rather than
-- whatever the most recent drag happened to land on.

local Resize = {}
Resize.__index = Resize
Resize.__type = "Resize"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local windowSizing = require(utility.windowSizing)

-- Touch-friendly hit target; the visible arc inside it stays smaller (see below) so it doesn't
-- read as a huge corner blob on a compact window.
local gripSize = 40

-- The arc's own design, mocked up and confirmed in Figma before porting here (none of
-- lucide/solar/sfsymbols/gravity/geist/craft had a matching curved glyph, and a shape this
-- simple doesn't need one anyway): a quarter-circle, rounded ends, small and fairly thick, a
-- muted grey rather than a bright white.
local arcBoxSize = 34
local arcStrokeWeight = 8
local arcColorKey = "PlaceholderColor"
local arcRestTransparency = 0.25
local arcHoverTransparency = 0.05
local arcRestOffset = Vector2.new(-3, -3) -- iconGroup's resting Position, AnchorPoint (1,1)

local snapBackInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local hoverInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Two clicks this close together are a double-click; anything slower is two separate
-- single clicks (the second one just starts a fresh drag).
local doubleClickWindow = 0.4

-- "Animated resize grip": how far (in pixels) the arc can nudge toward the pointer from its
-- resting spot, and how fast it settles there - exponential smoothing per second, same technique
-- (and same reasoning) as drag.luau's own mainRemaining/barRemaining: a per-frame lerp toward the
-- target instead of a fresh tween every frame, smaller = snappier.
local maxNudge = 4
local nudgeRemaining = 1e-4

local function currentViewport(): Vector2?
    local camera = variables.workspace.CurrentCamera
    return camera and camera.ViewportSize
end

function Resize.new(window)
    local self = setmetatable({
        window = assert(window, "Missing argument #1 (Window expected)"),
        resizing = false,
        animated = window.settings.resizeGripAnimated,
        _lastClickAt = nil :: number?,
    }, Resize)

    -- Parented straight onto self.main rather than a free-floating sibling like the drag bar -
    -- main's own AnchorPoint/Position math already keeps it glued to the corner for free as the
    -- window moves or resizes, no separate position-sync connection needed.
    self.grip = self.window:Create("Frame", {
        Name = "ResizeGrip",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(gripSize, gripSize),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 20,
        Visible = self.window.settings.resizeGripEnabled,

        Parent = self.window.main,
    })

    -- The arc is the same "clip a full circle" trick used elsewhere in this codebase: a circle
    -- twice iconGroup's own size, corner-anchored so its own bottom-right point lands on the clip
    -- box's bottom-right point - only the quarter of the circle inside the box ever renders.
    -- Where that clip cuts the stroke off (both open ends of the visible arc) reads as a flat,
    -- square cut - UIStroke has no equivalent of a rounded line cap on a closed shape like this -
    -- so two small round dots are added by hand at those exact two points to fake it.
    self.iconGroup = self.window:Create("Frame", {
        Name = "IconGroup",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, arcRestOffset.X, 1, arcRestOffset.Y),
        Size = UDim2.fromOffset(arcBoxSize, arcBoxSize),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,

        Parent = self.grip,
    })

    local arcCircle = self.window:Create("Frame", {
        Name = "Arc",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.fromOffset(arcBoxSize * 2, arcBoxSize * 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.iconGroup,
    })
    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0.5, 0),
        Parent = arcCircle,
    })
    self.arcStroke = self.window:Create("UIStroke", {
        Thickness = arcStrokeWeight,
        Transparency = arcRestTransparency,

        Parent = arcCircle,
    }, { Color = arcColorKey })

    self.arcCaps = {}
    for _, point in { Vector2.new(arcBoxSize, 0), Vector2.new(0, arcBoxSize) } do
        local cap = self.window:Create("Frame", {
            Name = "ArcCap",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(point.X, point.Y),
            Size = UDim2.fromOffset(arcStrokeWeight, arcStrokeWeight),
            BackgroundTransparency = arcRestTransparency,
            BorderSizePixel = 0,

            Parent = self.iconGroup,
        }, { BackgroundColor3 = arcColorKey })
        self.window:Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = cap })
        table.insert(self.arcCaps, cap)
    end

    self.interact = self.window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextTransparency = 1,

        Parent = self.grip,
    })

    -- Brighten on hover so the grip reads as interactive without shouting for attention at rest.
    local function setHoverBrightness(hovering)
        local target = if hovering then arcHoverTransparency else arcRestTransparency
        variables.tweenService:Create(self.arcStroke, hoverInfo, { Transparency = target }):Play()
        for _, cap in self.arcCaps do
            variables.tweenService:Create(cap, hoverInfo, { BackgroundTransparency = target }):Play()
        end
    end

    self.window:Connect(self.interact.MouseEnter, function()
        if not self.resizing then
            setHoverBrightness(true)
        end
    end)
    self.window:Connect(self.interact.MouseLeave, function()
        if not self.resizing then
            setHoverBrightness(false)
        end
    end)

    local screenGui = self.window.screenGui
    local dragStartMouse = Vector2.zero
    local dragStartSize = Vector2.zero
    local dragStartCentreAbs = Vector2.zero

    local function insetOffset(): Vector2
        if screenGui and screenGui.IgnoreGuiInset then
            return variables.guiService:GetGuiInset()
        end
        return Vector2.zero
    end

    local function applyResize(mouseLocation: Vector2)
        local delta = mouseLocation - dragStartMouse
        local clamped = windowSizing.clampUserSize(currentViewport(), dragStartSize + delta)
        local consumed = clamped - dragStartSize -- how much of the drag survived clamping

        self.window.main.Size = UDim2.fromOffset(clamped.X, clamped.Y)

        local newCentrePositionSpace = dragStartCentreAbs + consumed / 2 + insetOffset()
        local target = self.window:_clampedPosition(
            UDim2.fromOffset(newCentrePositionSpace.X, newCentrePositionSpace.Y)
        )
        self.window.main.Position = target
    end

    -- Bank the drag into self.size/self.customSize (everything downstream - the reveal target,
    -- _applyWindowSize's viewport refit, the drag bar's own math - reads those, not main.Size
    -- directly) and persist it.
    local function commitResize()
        local size = self.window.main.Size
        self.window.size = size
        self.window.customSize = Vector2.new(size.X.Offset, size.Y.Offset)
        self.window.settings.customWindowSize = { X = size.X.Offset, Y = size.Y.Offset }
        self.window:_clampToScreen()
        self.window:_syncDragBar()
        self.window:SaveSettings()
    end

    local function releaseResize()
        if not self.resizing then
            return
        end
        self.resizing = false
        commitResize()
        setHoverBrightness(false)
    end

    -- Double-click: snap back to the window's original screen-fit size instead of starting a
    -- drag. Tweens main and the drag bar together (same shape as the "Reset Window Position"
    -- settings button) so the bar doesn't lag a frame behind and read as detached mid-tween.
    function self:_snapToDefault()
        local target = windowSizing.fit(currentViewport(), self.window.defaultSize)

        local centreAbs = self.window.main.AbsolutePosition + self.window.main.AbsoluteSize * self.window.main.AnchorPoint
        local centrePositionSpace = centreAbs + insetOffset()
        local targetPosition =
            self.window:_clampedPosition(UDim2.fromOffset(centrePositionSpace.X, centrePositionSpace.Y))

        variables.tweenService:Create(self.window.main, snapBackInfo, { Size = target, Position = targetPosition })
            :Play()
        if self.window.drag and self.window.drag.drag then
            local barTarget = UDim2.new(
                targetPosition.X.Scale,
                targetPosition.X.Offset,
                targetPosition.Y.Scale,
                targetPosition.Y.Offset + target.Y.Offset / 2 + 15
            )
            variables.tweenService:Create(self.window.drag.drag, snapBackInfo, { Position = barTarget }):Play()
        end

        self.window.size = target
        self.window.customSize = self.window.defaultSize
        self.window.settings.customWindowSize = nil
        self.window:SaveSettings()
    end

    self.window:Connect(self.interact.InputBegan, function(input, processed)
        if processed then
            return
        end
        local inputType = input.UserInputType.Name
        if inputType ~= "MouseButton1" and inputType ~= "Touch" then
            return
        end
        -- _interactive() alone doesn't cover a *steady* minimised window (it only tracks
        -- animating/hidden) - a collapsed bar isn't something you'd resize, and Window:
        -- ToggleMinimise already hides the grip once collapsed, but the mouse can still be
        -- sitting where the grip used to be the instant the collapse starts.
        if not self.window:_interactive() or self.window.minimised then
            return
        end

        local now = os.clock()
        if self._lastClickAt and now - self._lastClickAt < doubleClickWindow then
            self._lastClickAt = nil
            self:_snapToDefault()
            return
        end
        self._lastClickAt = now

        self.resizing = true
        setHoverBrightness(true)
        dragStartMouse = variables.userInputService:GetMouseLocation()
        dragStartSize = Vector2.new(self.window.main.Size.X.Offset, self.window.main.Size.Y.Offset)
        dragStartCentreAbs = self.window.main.AbsolutePosition
            + self.window.main.AbsoluteSize * self.window.main.AnchorPoint
    end)

    self.window:Connect(variables.runService.RenderStepped, function()
        if not self.resizing then
            return
        end
        if not self.window:_interactive() then
            releaseResize()
            return
        end
        applyResize(variables.userInputService:GetMouseLocation())
    end)

    self.window:Connect(variables.userInputService.InputEnded, function(input)
        local inputType = input.UserInputType.Name
        if inputType == "MouseButton1" or inputType == "Touch" then
            releaseResize()
        end
    end)
    -- alt-tabbing mid-drag never delivers InputEnded, same story as the window-drag handle
    self.window:Connect(variables.userInputService.WindowFocusReleased, releaseResize)

    -- "Animated resize grip": continuous, not hover-gated - the whole point is it reads as
    -- reacting to the pointer from a distance, not just once the mouse actually lands on it.
    -- Paused mid-drag (the resize itself is the thing to look at then).
    --
    -- Nudges iconGroup's Position toward the pointer rather than rotating it - live-caught
    -- ClipsDescendants breaking the moment its own frame has a non-zero Rotation (the full circle
    -- shows through, clip ignored entirely, confirmed across several angles on this project's
    -- test client, not a one-off glitch). A rotated arc would mean rotating the very frame that
    -- makes it an arc in the first place, so this sidesteps the bug rather than working around it.
    self.window:Connect(variables.runService.RenderStepped, function(dt)
        if not self.animated or self.resizing or not self.grip.Visible then
            return
        end
        if not self.window:_interactive() or self.window.minimised then
            return
        end
        local gripCentre = self.grip.AbsolutePosition + self.grip.AbsoluteSize / 2
        local toMouse = variables.userInputService:GetMouseLocation() - gripCentre
        if toMouse.Magnitude < 1 then
            return
        end

        local targetOffset = arcRestOffset + toMouse.Unit * maxNudge
        local pos = self.iconGroup.Position
        local current = Vector2.new(pos.X.Offset, pos.Y.Offset)
        local settled = current + (targetOffset - current) * (1 - nudgeRemaining ^ dt)
        self.iconGroup.Position = UDim2.new(1, settled.X, 1, settled.Y)
    end)

    return self
end

function Resize:SetEnabled(enabled: boolean)
    self.grip.Visible = enabled and true or false
    if not self.grip.Visible and self.resizing then
        self.resizing = false
    end
end

function Resize:SetAnimated(enabled: boolean)
    self.animated = enabled and true or false
    if not self.animated then
        -- settle back to the resting spot rather than freezing wherever it last nudged to
        variables.tweenService
            :Create(self.iconGroup, hoverInfo, { Position = UDim2.new(1, arcRestOffset.X, 1, arcRestOffset.Y) })
            :Play()
    end
end

-- Public wrapper for the Settings "Reset Window Size" button - the exact same snap the grip's
-- own double-click already does.
function Resize:ResetSize()
    self:_snapToDefault()
end

return Resize

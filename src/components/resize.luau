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
local icons = require(utility.icons)

-- Touch-friendly hit target; the visible glyph inside it stays smaller (see the icon/fallback
-- below) so it doesn't read as a huge corner blob on a compact window.
local gripSize = 34

local snapBackInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local hoverInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Two clicks this close together are a double-click; anything slower is two separate
-- single clicks (the second one just starts a fresh drag).
local doubleClickWindow = 0.4

local function currentViewport(): Vector2?
    local camera = variables.workspace.CurrentCamera
    return camera and camera.ViewportSize
end

function Resize.new(window)
    local self = setmetatable({
        window = assert(window, "Missing argument #1 (Window expected)"),
        resizing = false,
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

    -- craft's expand-corner-02-stroke (a NW/SE double-headed diagonal arrow) over lucide's own
    -- resize-shaped icons (maximize-2/move-diagonal-2) - lucide doesn't have the one asked for.
    -- Falls back through a couple of near-equivalents from other packs before the hand-drawn bars.
    local glyph = icons.find("expand-corner-02-stroke", "craft")
        or icons.find("expand-corner-01-stroke", "craft")
        or icons.find("corner-down-right", "lucide")
    if glyph then
        -- craft is a spritesheet pack (see icons.luau) - the icon's actual pixels are a rect cut
        -- out of a shared sheet image, not the whole file, so ImageRectSize/Offset matter here
        -- and not just Image the way a flat-pack icon (lucide etc.) would.
        self.icon = self.window:Create("ImageLabel", {
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -4, 1, -4),
            Size = UDim2.fromOffset(28, 28),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = glyph.Image,
            ImageRectSize = glyph.ImageRectSize or Vector2.zero,
            ImageRectOffset = glyph.ImageRectOffset or Vector2.zero,
            ImageTransparency = 0,

            Parent = self.grip,
        }, { ImageColor3 = "PlaceholderColor" })
    else
        -- Hand-drawn fallback if the icon pack didn't resolve (offline, repo down): the classic
        -- two-short-diagonal-bars resize cue, same shape every OS uses for this affordance.
        self.icon = nil
        self.fallbackBars = {}
        for i, inset in { 0, 7 } do
            local bar = self.window:Create("Frame", {
                AnchorPoint = Vector2.new(1, 1),
                Position = UDim2.new(1, -5 - inset, 1, -5),
                Rotation = -45,
                Size = UDim2.fromOffset(11 - i * 3, 3),
                BorderSizePixel = 0,
                BackgroundTransparency = 0,

                Parent = self.grip,
            }, { BackgroundColor3 = "PlaceholderColor" })
            self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })
            table.insert(self.fallbackBars, bar)
        end
    end

    self.interact = self.window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextTransparency = 1,

        Parent = self.grip,
    })

    -- Already fully opaque at rest, so hover doesn't brighten it further - a slight scale pop
    -- is the interactive cue here instead.
    local function setHoverTransparency(hovering)
        local scale = if hovering then 1.15 else 1
        if self.icon then
            variables.tweenService
                :Create(self.icon, hoverInfo, { Size = UDim2.fromOffset(28 * scale, 28 * scale) })
                :Play()
        elseif self.fallbackBars then
            for i, bar in self.fallbackBars do
                local length = 11 - i * 3 -- matches the Size each bar was created with above
                variables.tweenService
                    :Create(bar, hoverInfo, { Size = UDim2.fromOffset(length * scale, 3 * scale) })
                    :Play()
            end
        end
    end

    self.window:Connect(self.interact.MouseEnter, function()
        if not self.resizing then
            setHoverTransparency(true)
        end
    end)
    self.window:Connect(self.interact.MouseLeave, function()
        if not self.resizing then
            setHoverTransparency(false)
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
        setHoverTransparency(false)
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
        setHoverTransparency(true)
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

    return self
end

function Resize:SetEnabled(enabled: boolean)
    self.grip.Visible = enabled and true or false
    if not self.grip.Visible and self.resizing then
        self.resizing = false
    end
end

return Resize

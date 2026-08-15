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
--
-- Devlog 12: sits straddling the window's own corner point now (half on the card, half over
-- whatever's behind it) instead of tucked a few px inside it - checked WindUI's own resize
-- handle for reference (same idea as this window's own drag bar sitting fully outside main: a
-- window control doesn't have to live entirely inside the frame it controls). Still parented to
-- self.main rather than a free-floating sibling like the drag bar, though - main has no
-- ClipsDescendants, so a child is free to render past its edge with no extra position-sync
-- connection needed, and main's own AnchorPoint/Position math keeps it glued to the corner for
-- free as the window moves or resizes.

local Resize = {}
Resize.__index = Resize
Resize.__type = "Resize"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local windowSizing = require(utility.windowSizing)
local constants = require(utility.constants)

-- Touch-friendly hit target, centred on the corner it straddles.
local gripSize = 40

-- WindUI's own resize glyph, checked directly in their source (ResizeHandle's ImageLabel) - a
-- curved diagonal swoosh mark. Downloaded and measured the actual asset: the visible stroke only
-- fills a 130x130 box inside the image's full 420x420 canvas (WindUI itself renders it at 96px
-- inside a 32px hit box, i.e. already 3x oversized on purpose) - rendering it anywhere near our
-- old 26-34px range left the *visible mark* at an unreadable ~8-10px, which is what kept reading
-- as tiny no matter how much the outer box grew. Sized up to match roughly the same overshoot
-- WindUI itself uses, and the visible stroke also isn't centred in its own canvas (its own
-- bounding box centres about 9.3% of the render size toward the bottom-right) - arcIconOffset
-- below corrects for that so the *stroke*, not the image's empty canvas, centres on the corner.
local arcImageSize = 80
local arcImageHoverSize = 92
local arcImageDragSize = 86
local arcIconOffset = -8 -- pulls the visibly-offset stroke back onto the corner point, both axes
local arcImage = "rbxassetid://120997033468887"
-- WindUI's own three-state opacity: quite faint at rest, brighter on hover, fully opaque while
-- actually dragging. Fainter than this grip needed at rest when it lived inside the card - it's
-- not sitting on a solid background anymore, it's half over whatever's behind the window.
local arcRestTransparency = 0.8
local arcHoverTransparency = 0.35
local arcDragTransparency = 0

local snapBackInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Same feel as the drag bar's own hover/grab animation (dragCosmetic in drag.luau) - a small
-- Back/Out pop rather than a plain linear-ish ease, so growing on hover reads as a springy nudge.
local hoverInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

    -- Dead-centre on main's own bottom-right corner point (AnchorPoint 0.5,0.5 at Position
    -- 1,0,1,0) rather than inset from it - straddles the edge instead of sitting inside it.
    self.grip = self.window:Create("Frame", {
        Name = "ResizeGrip",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 0, 1, 0),
        Size = UDim2.fromOffset(gripSize, gripSize),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        -- above bottomFade (100) - live-caught the fade's own gradient painting straight over
        -- the grip's arc at a lower ZIndex, tinting it with a grey diagonal wash
        ZIndex = constants.zIndex.resizeGrip,
        Visible = self.window.settings.resizeGripEnabled,

        Parent = self.window.main,
    })

    -- AnchorPoint (0.5, 0.5) means growing/shrinking Size on hover/drag never moves this point,
    -- so the small constant arcIconOffset correction stays valid across all three size states
    -- without needing its own tween.
    self.icon = self.window:Create("ImageLabel", {
        Name = "Glyph",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, arcIconOffset, 0.5, arcIconOffset),
        Size = UDim2.fromOffset(arcImageSize, arcImageSize),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = arcImage,
        ImageTransparency = arcRestTransparency,

        Parent = self.grip,
    }, { ImageColor3 = "ContentColor" })

    self.interact = self.window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextTransparency = 1,

        Parent = self.grip,
    })

    -- Three states, matching WindUI's own opacity scheme, plus the drag bar's own "grows a
    -- little on hover/grab" pop (dragCosmetic's MouseEnter/InputBegan tweens in drag.luau) - so
    -- the grip reads as interactive without shouting for attention sitting over the game behind
    -- it, and covers touch (which never fires MouseEnter/MouseLeave) the same way the bar does.
    local function setIconState(transparency, size)
        variables.tweenService:Create(self.icon, hoverInfo, {
            ImageTransparency = transparency,
            Size = UDim2.fromOffset(size, size),
        }):Play()
    end

    self.window:Connect(self.interact.MouseEnter, function()
        if not self.resizing then
            setIconState(arcHoverTransparency, arcImageHoverSize)
        end
    end)
    self.window:Connect(self.interact.MouseLeave, function()
        if not self.resizing then
            setIconState(arcRestTransparency, arcImageSize)
        end
    end)
    -- MouseEnter/MouseLeave don't fire for touch - a tap both starts the drag AND should pop the
    -- icon the same way a hover would, so touch gets the same cue via the drag start itself
    -- below rather than a dedicated touch event.

    local screenGui = self.window.screenGui
    local dragStartMouse = Vector2.zero
    local dragStartSize = Vector2.zero
    local dragStartCentreAbs = Vector2.zero

    -- The exact same exponential-smoothing constant drag.luau's own mainRemaining uses, for the
    -- same "weighted, slightly elastic" follow feel on the window itself while its size changes -
    -- requested outright ("a mesma animação do drag handle"). A per-frame lerp toward the target
    -- instead of a fresh tween every frame, same technique and same reasoning as the drag handle.
    local resizeRemaining = 1e-7

    -- The exact target this frame resolved to, before the lerp above eases main toward it -
    -- commitResize banks and settles onto this on release rather than whatever main's own
    -- Size/Position happen to be lerped to that frame, so a resize let go mid-ease still saves
    -- (and lands on) the size you actually dragged to, not a slightly-behind snapshot of it.
    local lastTargetSize = Vector2.zero
    local lastTargetPosition = UDim2.new()

    local function insetOffset(): Vector2
        if screenGui and screenGui.IgnoreGuiInset then
            return variables.guiService:GetGuiInset()
        end
        return Vector2.zero
    end

    -- Window:_clampedPosition() itself clamps against self.window.size - the COMMITTED size,
    -- only updated on release (see this file's own header comment on why). Live-caught: calling
    -- it as-is mid-drag keeps the half-width/half-height bound pinned to whatever size the window
    -- was *before* this drag started, so as it actually grows/shrinks the clamp thinks it's still
    -- the old size and reins the position back in to fit that - reading as the window barely
    -- moving off its starting spot no matter how far you drag, while the size itself still
    -- visibly (if erratically, fighting that same wrong clamp) changes. Mirrors the exact same
    -- math by hand against the size actually being dragged to instead.
    local function clampedPositionForSize(position: UDim2, sizeVec: Vector2): UDim2
        local window = self.window
        if not window.settings or not window.settings.keepOnScreen then
            return position
        end
        if position.X.Scale ~= 0 or position.Y.Scale ~= 0 then
            return position
        end
        local screen = window.screenGui.AbsoluteSize
        local halfX, halfY = sizeVec.X / 2, sizeVec.Y / 2
        local margin = 8
        local x = math.clamp(position.X.Offset, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
        local y = math.clamp(position.Y.Offset, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
        if x == position.X.Offset and y == position.Y.Offset then
            return position
        end
        return UDim2.fromOffset(x, y)
    end

    local function applyResize(mouseLocation: Vector2, dt: number)
        local delta = mouseLocation - dragStartMouse
        local clamped = windowSizing.clampUserSize(currentViewport(), dragStartSize + delta)
        local consumed = clamped - dragStartSize -- how much of the drag survived clamping

        local newCentrePositionSpace = dragStartCentreAbs + consumed / 2 + insetOffset()
        local target = clampedPositionForSize(
            UDim2.fromOffset(newCentrePositionSpace.X, newCentrePositionSpace.Y),
            clamped
        )

        lastTargetSize = clamped
        lastTargetPosition = target

        local targetSize = UDim2.fromOffset(clamped.X, clamped.Y)
        local settle = 1 - resizeRemaining ^ dt
        self.window.main.Size = self.window.main.Size:Lerp(targetSize, settle)
        self.window.main.Position = self.window.main.Position:Lerp(target, settle)

        -- Live-follow the drag bar too, not just once the resize commits. It used to only move
        -- via commitResize's own _syncDragBar call on release, so it visibly stayed put for the
        -- whole drag and only snapped into place the instant you let go - live-caught reading as
        -- "doesn't move while resizing" and, on a big enough shrink, as the bar ending up stuck
        -- *inside* the now-smaller window (its stale position was still where the old, bigger
        -- bottom edge used to be) until grabbing it forced a fresh, correct getTargets() read.
        -- _syncDragBar itself reads self.window.size, which is deliberately NOT live mid-drag
        -- (see this file's own header comment on why) - so this mirrors its exact math by hand
        -- against main's own eased Size/Position instead of calling it or the raw target, so the
        -- bar never gets ahead of the window it's actually hanging under.
        if self.window.drag and self.window.drag.drag then
            local mainPos = self.window.main.Position
            local mainSize = self.window.main.Size
            self.window.drag.drag.Position = UDim2.new(
                mainPos.X.Scale,
                mainPos.X.Offset,
                mainPos.Y.Scale,
                mainPos.Y.Offset + mainSize.Y.Offset / 2 + 15
            )
        end
    end

    -- Bank the drag into self.size/self.customSize (everything downstream - the reveal target,
    -- _applyWindowSize's viewport refit, the drag bar's own math - reads those, not main.Size
    -- directly) and persist it.
    local function commitResize()
        local size = UDim2.fromOffset(lastTargetSize.X, lastTargetSize.Y)
        self.window.size = size
        self.window.customSize = lastTargetSize
        self.window.settings.customWindowSize = { X = lastTargetSize.X, Y = lastTargetSize.Y }

        -- Settle the live ease onto the exact final target with a visible glide, same easing as
        -- drag.luau's own releaseDrag settle tween - persistence above already banked the target
        -- directly rather than reading main's own (still mid-ease) Size/Position, so there's
        -- nothing for this tween to race. This was the actually-missing piece live-caught as "the
        -- resize doesn't move like the drag handle" - the in-drag ease alone (matching
        -- mainRemaining's own snappy 1e-7) reads as basically instant on its own; the release
        -- glide is what the drag handle itself is actually recognisable by. Skips _clampToScreen/
        -- _syncDragBar deliberately (same as releaseDrag) - both would read main's still-old
        -- Position synchronously and instantly overwrite it, fighting the tween just started.
        local settle = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        variables.tweenService:Create(self.window.main, settle, { Size = size, Position = lastTargetPosition }):Play()
        if self.window.drag and self.window.drag.drag then
            local barTarget = UDim2.new(
                lastTargetPosition.X.Scale,
                lastTargetPosition.X.Offset,
                lastTargetPosition.Y.Scale,
                lastTargetPosition.Y.Offset + lastTargetSize.Y / 2 + 15
            )
            variables.tweenService:Create(self.window.drag.drag, settle, { Position = barTarget }):Play()
        end

        self.window:SaveSettings()
    end

    local function releaseResize()
        if not self.resizing then
            return
        end
        self.resizing = false
        commitResize()
        setIconState(arcRestTransparency, arcImageSize)
    end

    -- Double-click: snap back to the window's original screen-fit size instead of starting a
    -- drag. Tweens main and the drag bar together (same shape as the "Reset Window Position"
    -- settings button) so the bar doesn't lag a frame behind and read as detached mid-tween.
    function self:_snapToDefault()
        local target = windowSizing.fit(currentViewport(), self.window.defaultSize)

        local centreAbs = self.window.main.AbsolutePosition + self.window.main.AbsoluteSize * self.window.main.AnchorPoint
        local centrePositionSpace = centreAbs + insetOffset()
        -- Same stale-size clamp trap as applyResize above - clamp against the size we're
        -- snapping *to* (target), not self.window.size (still whatever it was before the snap).
        local targetPosition = clampedPositionForSize(
            UDim2.fromOffset(centrePositionSpace.X, centrePositionSpace.Y),
            Vector2.new(target.X.Offset, target.Y.Offset)
        )

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
        setIconState(arcDragTransparency, arcImageDragSize)
        dragStartMouse = variables.userInputService:GetMouseLocation()
        dragStartSize = Vector2.new(self.window.main.Size.X.Offset, self.window.main.Size.Y.Offset)
        dragStartCentreAbs = self.window.main.AbsolutePosition
            + self.window.main.AbsoluteSize * self.window.main.AnchorPoint
    end)

    self.window:Connect(variables.runService.RenderStepped, function(dt)
        if not self.resizing then
            return
        end
        if not self.window:_interactive() then
            releaseResize()
            return
        end
        applyResize(variables.userInputService:GetMouseLocation(), dt)
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

-- Public wrapper for the Settings "Reset Window Size" button - the exact same snap the grip's
-- own double-click already does.
function Resize:ResetSize()
    self:_snapToDefault()
end

return Resize

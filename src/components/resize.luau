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

    -- Not glowing self.icon directly - it's a mostly-empty 80px+ square with one small stroke in
    -- the corner of it (see the sizing comment above), so a shadow shaped to its own bounds reads
    -- as a flat square smear behind a tiny mark instead of a glow around it. A small round frame
    -- sized to the *stroke*, not the image's canvas, gives the same soft halo the drag bar's own
    -- rounded pill gets from the same CreateGlow call.
    local glowAnchor = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, arcIconOffset, 0.5, arcIconOffset),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = self.grip,
    })
    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0.5, 0),
        Parent = glowAnchor,
    })
    self.window:CreateGlow(glowAnchor, Color3.fromRGB(255, 255, 255), 10, 0.5)

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
        setIconState(arcRestTransparency, arcImageSize)
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
        setIconState(arcDragTransparency, arcImageDragSize)
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

-- Public wrapper for the Settings "Reset Window Size" button - the exact same snap the grip's
-- own double-click already does.
function Resize:ResetSize()
    self:_snapToDefault()
end

return Resize

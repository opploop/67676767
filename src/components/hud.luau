--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A small draggable status chip, independent of the main window - stays on screen (and keeps
-- updating) even while the window itself is hidden or minimised, for something a player wants
-- visible at a glance the whole session (FPS/ping, a running automation's headline status).
-- Parented straight to window.screenGui rather than window.main, since Window:Hide/Show only
-- ever animate main - a HUD parented there rides along for free without needing its own
-- show/hide wiring.
--
-- Deliberately its own tiny component rather than a Label/Stat repurposed: those both live
-- inside a Tab's page and follow the tab's own reveal/hide lifecycle, which is exactly the
-- coupling this is meant to escape.
--
-- Sized and weighted like the "watermark" HUDs most executor UIs ship (bold text, a coloured
-- accent tick, generous padding) rather than a slim inline label - the first two passes read as
-- too small/flat next to one of those on screen at the same time, live-caught (user: "ta feio,
-- pequeno").

local Hud = {}
Hud.__index = Hud
Hud.__type = "Hud"

local utility = script.Parent.Parent.utility
local variables = require(utility.variables)
local functions = require(utility.functions)
local image = require(utility.image)

local revealInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local dragStrokeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function Hud.new(window, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        window = assert(window, "Missing argument #1 (Window expected)"),
        text = properties.text or properties.Text or "",
    }, Hud)

    local hasIcon = (properties.icon or properties.Icon) ~= nil
    -- A user id: shows that user's headshot as a small circular avatar ahead of everything else -
    -- same rbxthumb:// URI trick toast.luau's own avatar variant and utility/image.luau's
    -- image.avatar both already use, no HTTP round trip needed.
    local avatarUserId = properties.avatar or properties.Avatar

    local startPosition = properties.position or properties.Position or UDim2.new(0, 20, 0, 20)

    self.main = self.window:Create("Frame", {
        Name = "Hud",
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        Position = startPosition,
        AnchorPoint = Vector2.new(0, 0),
        BorderSizePixel = 0,
        Active = true,

        -- reveal: grows in from a slightly smaller/transparent state instead of just popping in
        BackgroundTransparency = 1, -- In = 0 (the gradient below carries the real look)

        Parent = self.window.screenGui,
    })

    self.window:Create("UIGradient", {
        Rotation = 270,
        Offset = Vector2.new(0, -0.1),

        Parent = self.main,
    }, { Color = { "WindowColor", functions.toColorSequence } })

    -- fixed rather than the theme's own CornerRoundness: this chip is meant to read the same
    -- (comfortably rounded, not the window's own pill-ish 20px default) regardless of whatever
    -- corner style a particular window happens to be using.
    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = self.main,
    })

    self.stroke = self.window:Create("UIStroke", {
        Thickness = 1,
        Transparency = 1, -- In = 0.8

        Parent = self.main,
    }, { Color = "SurfaceStroke" })

    self.shadow = self.window:CreateGlow(self.main, "ShadowColor", 14, 1) -- In = 0.6

    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, 7),
        PaddingBottom = UDim.new(0, 7),
        PaddingLeft = UDim.new(0, 9),
        PaddingRight = UDim.new(0, 11),
        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.main,
    })

    -- The accent tick (a small coloured bar between the icon/avatar and the text) that used to
    -- live here is gone - live-reported as "essa porra de barra colorida... só atrapalhando", not
    -- needed now that the chip carries real content (avatar, name, colour-coded readouts) instead
    -- of needing its own identity mark.
    if hasIcon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = image.resolve(properties.icon or properties.Icon),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 0,

            ImageTransparency = 1, -- In = 0

            Parent = self.main,
        }, { ImageColor3 = "ContentColor" })
    end

    if avatarUserId then
        self.avatarImage = self.window:Create("ImageLabel", {
            Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(avatarUserId),
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,

            ImageTransparency = 1, -- In = 0

            Parent = self.main,
        })
        self.window:Create("UICorner", {
            CornerRadius = UDim.new(1, 0),
            Parent = self.avatarImage,
        })
    end

    self.label = self.window:Create("TextLabel", {
        Text = self.text,
        -- A dev building a multi-segment readout (player name, hub name, colour-coded ping/fps -
        -- see the hub template's own use of this) needs real inline colour, which only renders
        -- through RichText - plain text with a literal "<font...>" in it would otherwise show
        -- those tags as text instead of parsing them.
        RichText = true,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 3,

        -- Animation
        TextTransparency = 1, -- In = 0

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    -- Fired once per drag (on release, not per-frame - see the release() local in _wireDrag)
    -- with the chip's landed Position, so a consumer script can persist a player's dragged
    -- position across sessions (see Window:RegisterFlag in windowExtra.luau) without polling.
    self._positionChangedCallbacks = {}

    self:_reveal(hasIcon)
    self:_wireDrag()

    return self
end

-- Grow-and-fade-in, same beat as a notification card's own entrance.
function Hud:_reveal(hasIcon)
    local ts = variables.tweenService
    ts:Create(self.main, revealInfo, { BackgroundTransparency = 0 }):Play()
    ts:Create(self.stroke, revealInfo, { Transparency = 0.8 }):Play()
    ts:Create(self.shadow, revealInfo, { Transparency = 0.6 }):Play()
    if hasIcon and self.iconLabel then
        ts:Create(self.iconLabel, revealInfo, { ImageTransparency = 0 }):Play()
    end
    if self.avatarImage then
        ts:Create(self.avatarImage, revealInfo, { ImageTransparency = 0 }):Play()
    end
    ts:Create(self.label, revealInfo, { TextTransparency = 0 }):Play()
end

function Hud:SetText(text)
    self.text = text
    self.label.Text = text
end

-- Toggle the whole chip on/off - a dev wiring this to a player Settings toggle (e.g. "show FPS/
-- ping") doesn't need to Destroy()/recreate it just to let a player hide it and bring it back.
function Hud:SetVisible(visible: boolean)
    self.main.Visible = visible and true or false
end

-- Move the chip directly (e.g. restoring a player's last dragged position from a saved flag -
-- see Window:RegisterFlag). Doesn't itself fire OnPositionChanged: that hook is specifically "the
-- player just dragged this", not "something moved it", so a restore here can't loop back into
-- whatever's listening for the drag.
function Hud:SetPosition(position: UDim2)
    self.main.Position = position
end

-- Fires once per drag, right when the player lets go (not continuously while dragging - see
-- notifyPositionSettled in _wireDrag), with the chip's landed Position. For persisting a dragged
-- position across sessions.
function Hud:OnPositionChanged(callback: (position: UDim2) -> ())
    table.insert(self._positionChangedCallbacks, callback)
end

-- Plain mouse/touch drag, clamped to stay fully on screen. Same grab-relative-offset +
-- GetMouseLocation() + GuiInset approach window.luau's own _bindTopbarDrag uses (see its
-- comments for why: main.Position lives in inset-shifted space even though the ScreenGui
-- ignores the inset itself), just simpler since there's no lagging bar to also drag along.
function Hud:_wireDrag()
    local uis = variables.userInputService
    local dragging = false
    local relative = Vector2.zero
    local offset = Vector2.zero
    if self.window.screenGui and self.window.screenGui.IgnoreGuiInset then
        offset = variables.guiService:GetGuiInset()
    end

    local function target()
        local position = uis:GetMouseLocation() + relative + offset
        local size = self.main.AbsoluteSize
        local screen = self.window.screenGui.AbsoluteSize
        local margin = 4
        local x = math.clamp(position.X, margin, math.max(margin, screen.X - size.X - margin))
        local y = math.clamp(position.Y, margin, math.max(margin, screen.Y - size.Y - margin))
        return UDim2.fromOffset(x, y)
    end

    -- brightens the stroke while held, same tactile cue drag.luau's own bar uses, so the chip
    -- doesn't just silently teleport around with nothing acknowledging the grab
    local function setGrabbed(grabbed)
        variables.tweenService
            :Create(self.stroke, dragStrokeInfo, { Transparency = grabbed and 0.35 or 0.8 })
            :Play()
    end

    self.window:ConnectFor(self, self.main.InputBegan, function(input, processed)
        if processed then
            return
        end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
            return
        end
        dragging = true
        setGrabbed(true)
        if self.window.screenGui and self.window.screenGui.IgnoreGuiInset then
            offset = variables.guiService:GetGuiInset()
        end
        relative = self.main.AbsolutePosition - uis:GetMouseLocation()
    end)

    local function notifyPositionSettled()
        for _, callback in self._positionChangedCallbacks do
            task.spawn(callback, self.main.Position)
        end
    end

    local function release(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            if dragging then
                setGrabbed(false)
                notifyPositionSettled()
            end
            dragging = false
        end
    end
    self.window:ConnectFor(self, uis.InputEnded, release)
    self.window:ConnectFor(self, uis.WindowFocusReleased, function()
        if dragging then
            setGrabbed(false)
            notifyPositionSettled()
        end
        dragging = false
    end)

    self.window:ConnectFor(self, variables.runService.RenderStepped, function()
        if dragging then
            self.main.Position = target()
        end
    end)
end

function Hud:Destroy()
    if self._pulseTween then
        self._pulseTween:Cancel()
        self._pulseTween = nil
    end
    if self.connections then
        for _, connection in self.connections do
            self.window:Disconnect(connection)
        end
        table.clear(self.connections)
    end
    self.window:DestroySubtree(self.main)
end

return Hud

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Notification = {}
Notification.__index = Notification
Notification.__type = "Notification"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local constants = require(utility.constants)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

-- Timings/easings copied from Rayfield Gen1 (all Exponential, Out).
local growInfo = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local fadeLong = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out) -- bg + stroke
local fadeShort = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out) -- title/icon/desc/shadow
-- entry: card slides in from the right as the slot opens
local swipeInInfo = TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
-- exit "scale": shrink width + collapse height while it fades
local shrinkInfo = TweenInfo.new(0.9, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

local offscreenRight = UDim2.new(0.5, 360, 0.5, 0)
local centred = UDim2.new(0.5, 0, 0.5, 0)

-- Roughly what fits in the 800px stack. Past this the oldest is retired early rather than
-- left to march off the top of the screen still running its own dwell loop.
local maxLive = 6

-- Gap between stacked notifications. Applied INSIDE each notification (as top
-- padding on the outer frame) rather than on the container's UIListLayout, so
-- removing one collapses its gap with it instead of dropping an external gap
-- and making the notifications above jump up.
local stackPadding = 8

-- Auto duration from content length, clamped to a sensible window (Gen1-style)
local function autoDuration(content)
    return math.clamp(#content * 0.06 + 3, 3, 9)
end

-- Height of the optional progress bar (see SetProgress) - lazily built, so most notifications
-- never pay for it.
local progressHeight = 4

function Notification.new(window, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        window = assert(window, "Missing argument #1 (Window expected)"),
        title = properties.title or properties.Title or "Notification",
        -- Description is Fluent's own name for this same field - accepted here too so the
        -- typed NotifySuccess/Warning/Info/Error wrappers (see window.luau) can just forward
        -- whatever shape a script already calls them with, Fluent-style or not.
        content = properties.content or properties.Content or properties.description or properties.Description or "",
        icon = properties.icon or properties.Icon,
        -- optional per-instance override for the icon's own colour - the typed wrappers pass
        -- their preset accent through here; plain Window:Notify calls leave it nil and get the
        -- ordinary themed ContentColor, same as before this existed.
        accentColor = properties.accentColor or properties.AccentColor,
        _hovered = false,
        _dismissed = false,
        Destroyed = false, -- public mirror of _dismissed, for a caller polling a held reference
    }, Notification)

    -- Persist: skip the auto-dismiss dwell entirely - the caller owns this notification's
    -- lifetime and must call :Destroy() themselves. For a long-running job's progress card
    -- (see SetProgress below) rather than an ordinary toast that should just go away on its own.
    self.persist = properties.persist or properties.Persist or false

    -- Time is Fluent's own name for this field, same reasoning as content/Description above.
    self.duration = if self.persist
        then math.huge
        else properties.duration or properties.Duration or properties.time or properties.Time or autoDuration(
            self.content
        )

    local hasIcon = self.icon ~= nil and self.icon ~= 0 and self.icon ~= ""

    -- Outer frame: the stack layout item. Invisible itself; only its height is
    -- animated (grow in / collapse the gap on exit).
    self.main = self.window:Create("Frame", {
        Name = "Notification",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.notification,

        Parent = self.window.notifications,
    })

    -- Inter-notification gap lives here (not on the stack layout) so it collapses
    -- with the card and its neighbours don't jump when it's removed.
    self.window:Create("UIPadding", {
        PaddingTop = UDim.new(0, stackPadding),

        Parent = self.main,
    })

    -- Inner body: the visible card. Centred so the exit width-shrink pulls in
    -- symmetrically from both sides.
    self.body = self.window:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Size = UDim2.new(1, 0, 1, 0),
        Position = offscreenRight, -- starts off to the right; _show slides it in
        AnchorPoint = Vector2.new(0.5, 0.5),
        Active = true, -- receives input for click-to-dismiss
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.notification,

        -- Animation
        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })

    self.window:Create("UIGradient", {
        Rotation = 270,
        Offset = Vector2.new(0, -0.1),

        Parent = self.body,
    }, { Color = { "WindowColor", functions.toColorSequence } })

    self.window:Create("UICorner", {
        Parent = self.body,
    }, { CornerRadius = "CornerRoundness" })

    self.stroke = self.window:Create("UIStroke", {
        Transparency = 1, -- In = 0.95

        Parent = self.body,
    }, { Color = "SurfaceStroke" })

    self.shadow = self.window:CreateGlow(self.body, "ShadowColor", 20, 1) -- In = 0.6

    -- Horizontal insets; vertical padding comes from centering the row in the grown height
    self.window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 20),
        PaddingRight = UDim.new(0, 20),

        Parent = self.body,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 14),

        Parent = self.body,
    })

    if hasIcon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(24, 24),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            ZIndex = constants.zIndex.notification,

            -- Animation
            ImageTransparency = 1, -- In = 0

            Parent = self.body,
        }, { ImageColor3 = "ContentColor" })

        -- Plain instance property, set once, after the theme binding above rather than through
        -- it - only ImageTransparency ever gets tweened on this label (see _show/_dismiss), so
        -- there's nothing later that would fight or overwrite a colour set here.
        if self.accentColor then
            self.iconLabel.ImageColor3 = self.accentColor
        end
    end

    -- Text column fills the row minus icon + padding (container is 300 wide)
    self.container = self.window:Create("Frame", {
        Size = UDim2.fromOffset(hasIcon and 222 or 260, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        ZIndex = constants.zIndex.notification,

        Parent = self.body,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),

        Parent = self.container,
    })

    self.titleLabel = self.window:Create("TextLabel", {
        Text = self.title,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = constants.zIndex.notification,

        -- Animation
        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    if self.content ~= "" then
        self.descriptionLabel = self.window:Create("TextLabel", {
            Text = self.content,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            TextSize = 15,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
            ZIndex = constants.zIndex.notification,

            -- Animation
            TextTransparency = 1, -- In = 0.35

            Parent = self.container,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })
    end

    -- Newest sits at the bottom of the (bottom-anchored) stack
    self.window._notificationCount = (self.window._notificationCount or 0) + 1
    self.main.LayoutOrder = self.window._notificationCount

    -- a callback that notifies in a loop would stack cards forever, so retire the oldest once
    -- theres more than the stack can show
    local live = self.window._liveNotifications
    if not live then
        live = {}
        self.window._liveNotifications = live
    end
    table.insert(live, self)
    while #live > maxLive do
        local oldest = table.remove(live, 1)
        if oldest and oldest ~= self then
            task.spawn(oldest._dismiss, oldest)
        end
    end

    -- tracked so _dismiss can drop them; notifications come and go so we cant let their
    -- connections/instances sit in the window lists until Unload
    self._connections = {
        self.window:Connect(self.body.MouseEnter, function()
            self._hovered = true
        end),
        self.window:Connect(self.body.MouseLeave, function()
            self._hovered = false
        end),
        self.window:Connect(self.body.InputBegan, function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                self:_dismiss()
            end
        end),
    }

    task.spawn(function()
        self:_show()
    end)

    return self
end

-- Height the card needs, measured without rendering (so nothing flickers into
-- the stack before it's ready to animate).
function Notification:_measure()
    local colWidth = self.iconLabel and 222 or 260

    local contentH = functions.textHeight(self.window.theme.TitleFont, 16, self.title, colWidth)
    if self.descriptionLabel then
        contentH = contentH + 4 + functions.textHeight(self.window.theme.Font, 15, self.content, colWidth)
    end
    if self.progressTrack then
        contentH = contentH + 4 + progressHeight
    end

    return math.max(contentH, self.iconLabel and 24 or 0) + 28
end

-- Re-measures and tweens the outer slot to the new height - anything that changes the card's
-- text/progress after it's already on screen (ChangeTitle/ChangeDescription/SetProgress) needs
-- this, since (unlike the inner labels) the outer frame's height is a one-shot tween from _show,
-- not AutomaticSize - see _show's own comment on why (no flicker before the grow-in starts).
function Notification:_resize()
    if self._dismissed or not self.main.Parent then
        return
    end
    local target = self:_measure() + stackPadding
    variables.tweenService:Create(self.main, fadeLong, { Size = UDim2.new(1, 0, 0, target) }):Play()
end

-- Update the title/description after the card is already showing - a progress card started with
-- Notify({ persist = true }) calls these each step instead of firing a new toast per tick.
function Notification:ChangeTitle(text)
    if self._dismissed then
        return
    end
    self.title = text
    self.titleLabel.Text = text
    self:_resize()
end

function Notification:ChangeDescription(text)
    if self._dismissed then
        return
    end
    self.content = text
    self:_ensureDescriptionLabel()
    self.descriptionLabel.Text = text
    self:_resize()
end

-- Lazily builds the description label for a card that started with no content (title-only) -
-- ChangeDescription can still be the first thing that gives it one.
function Notification:_ensureDescriptionLabel()
    if self.descriptionLabel then
        return
    end
    self.descriptionLabel = self.window:Create("TextLabel", {
        Text = "",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
        ZIndex = constants.zIndex.notification,

        TextTransparency = 0.35,

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })
end

-- Thin accent-coloured bar under the text, lazily built on first use - most notifications never
-- call this, so it costs nothing for the ordinary toast path.
function Notification:_ensureProgressBar()
    if self.progressTrack then
        return
    end
    self.progressTrack = self.window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, progressHeight),
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        LayoutOrder = 3,
        ClipsDescendants = true,
        ZIndex = constants.zIndex.notification,

        Parent = self.container,
    }, { BackgroundColor3 = "SurfaceStroke" })
    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.progressTrack,
    })
    self.progressFill = self.window:Create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.notification,

        Parent = self.progressTrack,
    }, { BackgroundColor3 = "AccentColor" })
    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.progressFill,
    })
end

-- 0-1. A long-running batch action (redeeming N codes, importing M entries) calls this each
-- step instead of firing a fresh toast per item - one card, updated in place.
function Notification:SetProgress(fraction)
    if self._dismissed then
        return
    end
    fraction = math.clamp(fraction or 0, 0, 1)
    local firstUse = not self.progressTrack
    self:_ensureProgressBar()
    if firstUse then
        self:_resize()
    end
    variables.tweenService:Create(self.progressFill, fadeShort, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()
end

-- Public alias for _dismiss - a persist notification has no dwell timer to end it, so the
-- caller ends it explicitly (a batch job finishing, an error aborting it) via this name.
function Notification:Destroy()
    self:_dismiss()
end

-- Enter: grow the height, then stagger the fades (Gen1 timing).
function Notification:_show()
    -- All sizing done before anything is visible: outer is height 0 and the body
    -- is fully transparent until the grow tween starts, so there's no flicker.
    -- +stackPadding because the outer's top padding holds the inter-card gap.
    local target = self:_measure() + stackPadding
    if not self.main.Parent then
        return
    end

    hapticEngine.notify()
    soundEngine.notify()

    -- Open the slot and slide the card in from the right (body starts off-right), fading as it comes
    variables.tweenService:Create(self.main, growInfo, { Size = UDim2.new(1, 0, 0, target) }):Play()
    variables.tweenService:Create(self.body, swipeInInfo, { Position = centred }):Play()
    variables.tweenService:Create(self.body, fadeLong, { BackgroundTransparency = 0 }):Play()
    variables.tweenService:Create(self.titleLabel, fadeShort, { TextTransparency = 0 }):Play()
    variables.tweenService:Create(self.stroke, fadeLong, { Transparency = 0.95 }):Play()
    variables.tweenService:Create(self.shadow, fadeShort, { Transparency = 0.6 }):Play()

    task.wait(0.05)
    if self._dismissed or not self.main.Parent then
        return -- dismissed mid-stagger; dont fight the exit fade
    end
    if self.iconLabel then
        variables.tweenService:Create(self.iconLabel, fadeShort, { ImageTransparency = 0 }):Play()
    end

    task.wait(0.05)
    if self._dismissed or not self.main.Parent then
        return
    end
    if self.descriptionLabel then
        variables.tweenService:Create(self.descriptionLabel, fadeShort, { TextTransparency = 0.35 }):Play()
    end

    -- Dwell, pausing while hovered
    local elapsed = 0
    while elapsed < self.duration and not self._dismissed and self.main.Parent do
        local dt = task.wait()
        if not self._hovered then
            elapsed += dt
        end
    end

    self:_dismiss()
end

-- Exit: fade out while the card shrinks (width + height) - Gen1's exit.
function Notification:_dismiss()
    if self._dismissed then
        return
    end
    self._dismissed = true
    self.Destroyed = true

    local live = self.window._liveNotifications
    local index = live and table.find(live, self)
    if live and index then
        table.remove(live, index)
    end

    if not self.main.Parent then
        return
    end

    -- Fade everything out (runs during the shrink -> "goes transparent as it scales")
    variables.tweenService:Create(self.body, fadeLong, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(self.stroke, fadeLong, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.shadow, fadeShort, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.titleLabel, fadeShort, { TextTransparency = 1 }):Play()
    if self.descriptionLabel then
        variables.tweenService:Create(self.descriptionLabel, fadeShort, { TextTransparency = 1 }):Play()
    end
    if self.iconLabel then
        variables.tweenService:Create(self.iconLabel, fadeShort, { ImageTransparency = 1 }):Play()
    end
    -- Live-caught: these two were never included here, so a progress card's bar just sat fully
    -- opaque while everything else around it faded in ~0.3-0.4s, only actually disappearing once
    -- the 0.9s shrink below finally clipped it out of view - reads as "the bar takes way longer
    -- to go than the rest of the card", not a synchronized exit.
    if self.progressTrack then
        variables.tweenService:Create(self.progressTrack, fadeShort, { BackgroundTransparency = 1 }):Play()
    end
    if self.progressFill then
        variables.tweenService:Create(self.progressFill, fadeShort, { BackgroundTransparency = 1 }):Play()
    end

    -- Shrink: narrow the card (width -90) and collapse the slot (height 0) together
    variables.tweenService:Create(self.body, shrinkInfo, { Size = UDim2.new(1, -90, 1, 0) }):Play()
    local collapse = variables.tweenService:Create(self.main, shrinkInfo, { Size = UDim2.new(1, 0, 0, 0) })
    collapse:Play()
    collapse.Completed:Wait()

    if not self.main.Parent then
        return
    end

    for _, connection in self._connections do
        self.window:Disconnect(connection)
    end
    self.window:DestroySubtree(self.main)
end

return Notification

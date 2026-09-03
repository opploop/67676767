--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Guided onboarding tour: a dev-supplied sequence of steps, each pointing at a real element
-- (whatever CreateToggle/CreateButton/etc handed back), played once automatically on a window's
-- first show (see Window:_firstShow's own tour block) and re-playable from Settings. Each step
-- gets a bright accent ring around its target plus a description bubble with Back/Next/Skip -
-- no true dim-with-cutout mask (a much heavier UI trick, and this project's own resize/drag work
-- this session is a long track record of how expensive getting screen-space math wrong is to
-- live-debug) - a dimmed backdrop plus a glowing ring around the real element already reads as
-- "look here" without needing to punch an actual hole in an overlay.
--
-- Cross-tab steps: a step's target can live on any tab, not just whichever one happens to be
-- open when the tour reaches it - findOwningTab below walks the target's own ancestry to find
-- which tab actually owns it and auto-Selects that tab first, so a dev writing a tour that spans
-- multiple tabs doesn't have to manually Select() before each block of steps just to keep the
-- ring pointed at something actually on screen.

local Tour = {}
Tour.__index = Tour
Tour.__type = "Tour"

local utility = script.Parent.Parent.utility
local variables = require(utility.variables)
local constants = require(utility.constants)
local locale = require(utility.locale)
local functions = require(utility.functions)

local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local moveInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local ringPad = 8 -- px the ring sits outside the target's own edges, each side
local bubbleGap = 14 -- px between the ring and the bubble
local bubbleWidth = 280

-- Walk up from a step's target to whichever of the window's tabs actually owns it, if any -
-- nil for a target that isn't parented under any tab's page at all (the floating HUD, a Popup,
-- window chrome itself), which just skips the auto-switch below and behaves exactly as before.
local function findOwningTab(window, target)
    if not target or not target.main then
        return nil
    end
    local instance = target.main
    while instance do
        for _, tab in window.tabs do
            if tab.tabPage == instance then
                return tab
            end
        end
        instance = instance.Parent
    end
    return nil
end

-- Force open any collapsed Collapsible section sitting between a step's target and its tab page,
-- so the ring never ends up pointing at something still hidden inside a closed one. Walks every
-- collapsible the window knows about (collapsible.luau's own window.collapsibles) and expands
-- (instantly, not the section's own animated toggle - popping a section open while the tour's own
-- dim/ring reveal is also animating in doesn't need two overlapping motions competing) any whose
-- content wrapper actually contains the target. Returns whether anything was actually expanded,
-- so the caller knows whether a settle frame is needed before trusting geometry off of it.
local function expandAncestors(window, target): boolean
    if not target or not target.main then
        return false
    end
    local expandedAny = false
    for _, collapsible in window.collapsibles or {} do
        if not collapsible.expanded and collapsible.contentWrapper then
            local ancestor = target.main
            while ancestor do
                if ancestor == collapsible.contentWrapper then
                    collapsible:SetExpanded(true, true)
                    expandedAny = true
                    break
                end
                ancestor = ancestor.Parent
            end
        end
    end
    return expandedAny
end

-- Scroll a tab's own scrolling page so a step's target actually sits inside the visible viewport
-- before the ring tries to point at it - most tab pages auto-grow past one screen, so a target
-- further down could still be off-screen even after the tab-switch/section-expand above land on
-- the right tab and section. Only moves the canvas when the target isn't already fully visible,
-- so revisiting a step whose target is already on screen doesn't cause a needless jump. Returns
-- whether it actually scrolled, for the same "does the caller need to wait a frame" reason as
-- expandAncestors above.
local function scrollIntoView(tab, target): boolean
    local tabPage = tab and tab.tabPage
    if not tabPage or not tabPage:IsA("ScrollingFrame") then
        return false
    end
    local viewTop = tabPage.AbsolutePosition.Y
    local viewBottom = viewTop + tabPage.AbsoluteSize.Y
    local targetTop = target.AbsolutePosition.Y
    local targetBottom = targetTop + target.AbsoluteSize.Y
    if targetTop >= viewTop and targetBottom <= viewBottom then
        return false
    end

    -- Centre the target in the viewport rather than just nudging it to the nearest edge - reads
    -- better with the ring's own padding/glow around it than the target sitting flush against
    -- the very top or bottom edge of the visible area.
    local canvasY = tabPage.CanvasPosition.Y + (targetTop - viewTop) - (tabPage.AbsoluteSize.Y - target.AbsoluteSize.Y) / 2
    -- Confirmed live: AutomaticCanvasSize doesn't keep CanvasSize itself readable - it stays
    -- whatever was explicitly set at construction (UDim2.new(0,0,0,0) here), never the computed
    -- content height, so clamping against it always clamped to 0 and silently ate every scroll.
    -- The tab page's own UIListLayout.AbsoluteContentSize is the real content height instead.
    local contentHeight = if tab.tabPageLayout then tab.tabPageLayout.AbsoluteContentSize.Y else tabPage.AbsoluteSize.Y
    local maxCanvasY = math.max(0, contentHeight - tabPage.AbsoluteSize.Y)
    tabPage.CanvasPosition = Vector2.new(tabPage.CanvasPosition.X, math.clamp(canvasY, 0, maxCanvasY))
    return true
end

local function insetOffset(window): Vector2
    -- same correction drag.luau/resize.luau already use: main/absolute screen-space offsets are
    -- shifted from AbsolutePosition by the gui inset even though the ScreenGui ignores it.
    local screenGui = window.screenGui
    if screenGui and screenGui.IgnoreGuiInset then
        return variables.guiService:GetGuiInset()
    end
    return Vector2.zero
end

function Tour.new(window)
    local self = setmetatable({
        window = window,
        active = false,
        steps = {},
        index = 0,
    }, Tour)

    local screenGui = window.screenGui

    self.dim = window:Create("Frame", {
        Name = "TourDim",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.tourDim,
        Active = true, -- swallows clicks to whatever's behind a step instead of leaking through
        Visible = false,

        BackgroundTransparency = 1, -- shown = 0.55

        Parent = screenGui,
    })

    self.ring = window:Create("Frame", {
        Name = "TourRing",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.tourDim + 1,
        Visible = false,

        Parent = screenGui,
    })
    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = self.ring,
    })
    self.ringStroke = window:Create("UIStroke", {
        Thickness = 2,
        Transparency = 0,
        Parent = self.ring,
    }, { Color = "AccentColor" })
    self.ringGlow = window:CreateGlow(self.ring, "AccentColor", 18, 0.4)

    -- Bubble: same visual language as a toast pill (WindowColor gradient card), just a rectangle
    -- instead of a hug-width capsule since this holds a title + a full description + buttons.
    self.bubble = window:Create("Frame", {
        Name = "TourBubble",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Size = UDim2.fromOffset(bubbleWidth, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = constants.zIndex.tourBubble,
        Visible = false,

        Parent = screenGui,
    })

    window:Create("UIGradient", {
        Rotation = 270,
        Parent = self.bubble,
    }, { Color = { "WindowColor", functions.toColorSequence } })

    window:Create("UICorner", {
        CornerRadius = UDim.new(0, 16),
        Parent = self.bubble,
    })

    self.bubbleStroke = window:Create("UIStroke", {
        Thickness = 1,
        Parent = self.bubble,
    }, { Color = "SurfaceStroke", Transparency = "ElementStrokeTransparency" })

    self.bubbleShadow = window:CreateGlow(self.bubble, "ShadowColor", 20, 0.6)

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 18),
        PaddingRight = UDim.new(0, 18),
        PaddingTop = UDim.new(0, 16),
        PaddingBottom = UDim.new(0, 16),
        Parent = self.bubble,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = self.bubble,
    })

    self.progressLabel = window:Create("TextLabel", {
        Text = "",
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = constants.zIndex.tourBubble,
        Parent = self.bubble,
    }, { TextColor3 = "AccentColor", FontFace = "Font" })

    self.titleLabel = window:Create("TextLabel", {
        Text = "",
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 2,
        ZIndex = constants.zIndex.tourBubble,
        Parent = self.bubble,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    self.descriptionLabel = window:Create("TextLabel", {
        Text = "",
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 3,
        ZIndex = constants.zIndex.tourBubble,
        Parent = self.bubble,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })
    self.descriptionLabel.TextTransparency = 0.3

    self.buttonRow = window:Create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = 4,
        ZIndex = constants.zIndex.tourBubble,
        Parent = self.bubble,
    })
    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 8),
        -- Roblox's real default here is Enum.SortOrder.Name, not LayoutOrder - this row happened
        -- to still read right with just Skip/Next (both plain unnamed TextButtons, so Name-sort's
        -- tie-break fell back to creation order, which matched anyway). Adding Back as a third
        -- button before them would be trusting that same luck a third time - explicit instead,
        -- same fix the player card needed for exactly this (see buildPlayerCard's own comment).
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = self.buttonRow,
    })

    local function makeButton(order, primary)
        -- Window:Create applies themeProperties *first*, literal properties second - a literal
        -- BackgroundColor3 here would permanently win over the themed Accent/NeutralButton
        -- colour below instead of just seeding a start-state, the exact mistake this project's
        -- own tabDock background fix ran into earlier this session. No literal BackgroundColor3
        -- in this table at all; the theme binding is the only thing that ever sets it.
        local btn = window:Create("TextButton", {
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, 28),
            BorderSizePixel = 0,
            Text = "",
            TextSize = 13,
            LayoutOrder = order,
            ZIndex = constants.zIndex.tourBubble,
            Parent = self.buttonRow,
        }, if primary
            then { BackgroundColor3 = "AccentColor", TextColor3 = "ContentColor", FontFace = "Font" }
            else { BackgroundColor3 = "NeutralButton", TextColor3 = "ContentColor", FontFace = "Font" })
        window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = btn })
        window:Create("UIPadding", {
            PaddingLeft = UDim.new(0, 14),
            PaddingRight = UDim.new(0, 14),
            Parent = btn,
        })
        return btn
    end

    -- Back sits leftmost of the right-aligned cluster (Back / Skip / Next) - hidden on step 1
    -- (see :_show), since there's nothing behind the first step to go back to.
    self.backButton = makeButton(0, false)
    self.skipButton = makeButton(1, false)
    self.nextButton = makeButton(2, true)

    window:Connect(self.backButton.MouseButton1Click, function()
        self:_back()
    end)
    window:Connect(self.skipButton.MouseButton1Click, function()
        self:finish()
    end)
    window:Connect(self.nextButton.MouseButton1Click, function()
        self:_advance()
    end)

    return self
end

-- Position the ring around, and the bubble beside, whatever step.target currently is - called
-- once per step and again if the window itself moves/resizes mid-tour (see :_reposition).
function Tour:_layout()
    local step = self.steps[self.index]
    if not step or not step.target or not step.target.main then
        return
    end

    local target = step.target.main
    local abs = target.AbsolutePosition
    local size = target.AbsoluteSize
    local offset = insetOffset(self.window)

    local ringPos = abs - Vector2.new(ringPad, ringPad) + offset
    local ringSize = size + Vector2.new(ringPad * 2, ringPad * 2)
    self.ring.Position = UDim2.fromOffset(ringPos.X, ringPos.Y)
    self.ring.Size = UDim2.fromOffset(ringSize.X, ringSize.Y)

    -- Prefer sitting to the right of the target; flip to the left if that would run the bubble
    -- off the screen, same "flip if it doesn't fit" idea as a dropdown menu opening upward.
    local screen = self.window.screenGui.AbsoluteSize
    local spaceRight = screen.X - (ringPos.X + ringSize.X)
    local bubbleX = if spaceRight >= bubbleWidth + bubbleGap
        then ringPos.X + ringSize.X + bubbleGap
        else ringPos.X - bubbleWidth - bubbleGap
    local bubbleY = math.clamp(ringPos.Y, 10, math.max(10, screen.Y - 200))

    local targetPos = UDim2.fromOffset(bubbleX, bubbleY)
    if self.bubble.Visible then
        variables.tweenService:Create(self.bubble, moveInfo, { Position = targetPos }):Play()
    else
        self.bubble.Position = targetPos
    end
end

-- Shared by _advance/_back below - jumps straight to a given step index rather than only ever
-- stepping +/-1, so both directions (and a future "jump to step N" if one's ever needed) share
-- one path instead of duplicating the tab-switch/copy/layout logic per direction.
function Tour:_show(index: number)
    self.index = index
    local step = self.steps[self.index]
    if not step then
        self:finish()
        return
    end

    -- Auto-switch to whichever tab actually owns this step's target, if it isn't the one
    -- already open (see findOwningTab above), and force open any collapsed section standing
    -- between the target and its page (expandAncestors). task.wait() once after either: the
    -- new tab/section's layout needs a frame to actually settle before anything below - the
    -- scroll math, then _layout's own ring placement - trusts its AbsolutePosition/AbsoluteSize,
    -- the same "read geometry one frame late" rule the sidebar drag's own release handler
    -- already follows for the exact same reason.
    local owningTab = findOwningTab(self.window, step.target)
    local switched = false
    if owningTab and self.window.selectedTab ~= owningTab then
        owningTab:Select()
        switched = true
    end
    local expanded = expandAncestors(self.window, step.target)
    if switched or expanded then
        task.wait()
    end

    -- Scroll the target into view within its own tab's page, now that the right tab/section is
    -- actually showing. Same settle-then-trust-geometry reasoning if it actually had to move the
    -- canvas: _layout below reads the target's AbsolutePosition, which the scroll itself just
    -- changed.
    if owningTab and step.target and step.target.main and scrollIntoView(owningTab, step.target.main) then
        task.wait()
    end

    self.progressLabel.Text = string.format(locale.resolve("Step %d of %d"), self.index, #self.steps)
    self.titleLabel.Text = locale.resolve(step.title or "")
    self.descriptionLabel.Text = locale.resolve(step.description or "")
    self.nextButton.Text = if self.index == #self.steps then locale.resolve("Finish") else locale.resolve("Next")
    self.skipButton.Text = locale.resolve("Skip")
    self.backButton.Text = locale.resolve("Back")
    -- Nothing to go back to from the first step.
    self.backButton.Visible = self.index > 1

    self:_layout()

    self.ring.Visible = true
    self.bubble.Visible = true
end

function Tour:_advance()
    self:_show(self.index + 1)
end

-- Revisit the previous step - re-runs the same tab-switch/layout path _advance uses, just -1
-- instead of +1, so stepping back across a tour boundary lands back on the right tab too.
function Tour:_back()
    if self.index > 1 then
        self:_show(self.index - 1)
    end
end

-- Play a dev-supplied step list. steps = { { target, title, description }, ... } - target is
-- whatever CreateToggle/CreateButton/etc itself returned (anything with a .main).
function Tour:start(steps)
    if self.active or type(steps) ~= "table" or #steps == 0 then
        return
    end
    self.active = true
    self.steps = steps
    self.index = 0

    self.dim.Visible = true
    variables.tweenService:Create(self.dim, fadeInfo, { BackgroundTransparency = 0.55 }):Play()

    self:_advance()
end

function Tour:finish()
    if not self.active then
        return
    end
    self.active = false

    variables.tweenService:Create(self.dim, fadeInfo, { BackgroundTransparency = 1 }):Play()
    self.ring.Visible = false
    self.bubble.Visible = false
    task.delay(fadeInfo.Time, function()
        if not self.active then
            self.dim.Visible = false
        end
    end)

    if self.window.settings then
        self.window.settings.tourSeen = true
        self.window:SaveSettings()
    end
end

-- Re-run the layout math against wherever the current step's target is *now* - called if the
-- window itself moves/resizes mid-tour, so the ring doesn't drift off the element it's pointing
-- at. Cheap enough to just call unconditionally; it no-ops without an active step.
function Tour:reposition()
    if self.active and self.index >= 1 then
        self:_layout()
    end
end

return Tour

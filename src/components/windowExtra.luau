--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Part of the Window class - see window.luau's own header comment for why this file exists
-- (Roblox's 200,000 character ModuleScript Source limit) and windowCore.luau's for how the split
-- actually holds together (a shared core module, not a circular require). Every `function
-- Window:X` below attaches to the exact same table window.luau's Window.new builds instances
-- against - this file is required purely for that side effect, from window.luau's own tail.

local core = require(script.Parent.windowCore)
local Window = core.Window

-- Utility (aliased off windowCore so every split file shares the exact same module instances -
-- see windowCore.luau's own header comment)
local image = core.image
local functions = core.functions
local persistence = core.persistence
local constants = core.constants
local locale = core.locale
local log = core.log
local hapticEngine = core.hapticEngine
local soundEngine = core.soundEngine
local windowSizing = core.windowSizing
local icons = core.icons
local acrylic = core.acrylic
local clipboard = core.clipboard
local chrome = core.chrome
local search = core.search
local filesystem = core.filesystem
local path = core.path
local variables = core.variables
local themes = core.themes

-- Shared constants/helpers (see windowCore.luau)
local revealInfo = core.revealInfo
local collapsedSize = core.collapsedSize
local collapsedTop = core.collapsedTop
local maxToastWidth = core.maxToastWidth
local compactRowHeight = core.compactRowHeight
local viewportReconcileInterval = core.viewportReconcileInterval
local fitWindowSize = core.fitWindowSize
local resolveCustomSize = core.resolveCustomSize
local fontChoices = core.fontChoices
local fontOptionNames = core.fontOptionNames
local fontAtWeight = core.fontAtWeight
local gradientKeys = core.gradientKeys
local coerceThemeValue = core.coerceThemeValue
local firstColor = core.firstColor
local edgeShade = core.edgeShade
local deriveStrokes = core.deriveStrokes
local themeOverrides = core.themeOverrides
local resolveTheme = core.resolveTheme
local WINDOW_REGISTRY_KEY = core.WINDOW_REGISTRY_KEY
local windowRegistry = core.windowRegistry

function Window:SaveSettings()
    return persistence.saveSettings(self)
end

function Window:LoadSettings()
    return persistence.loadSettings(self)
end

-- Fade the open tab's elements out - the only ones actually on screen, since the page
-- navigation keeps the other tabs' elements invisible. Shared by Hide and minimise.
function Window:_fadeSelectedElementsOut()
    if self.selectedTab then
        for _, element in ipairs(self.selectedTab.elements) do
            element:_setShown(false, true)
        end
    end
end

-- Reveal the open tab's elements with a quick top-to-bottom stagger, but only for the ones
-- actually within the scroll viewport - whatever's scrolled off (above or below) just snaps in,
-- since nobody's looking at it. So reopening a page scrolled halfway down animates from where
-- you left off, not from the very top. Everything is measured live off the scrolling frame's
-- real viewport + each element's real position, so it's correct at any window size, any scroll.
-- Other tabs snap ready off-screen too. `budget` caps how long the stagger runs before the
-- remaining on-screen elements come in together, so a tall viewport doesn't crawl.
function Window:_revealElements(perElementDelay, budget)
    for _, tab in pairs(self.tabs) do
        if tab ~= self.selectedTab then
            for _, element in ipairs(tab.elements) do
                element:_setShown(true, false)
            end
        end
    end

    local tab = self.selectedTab
    if not tab then
        return
    end

    local page = tab.tabPage
    local viewTop = page.AbsolutePosition.Y
    local viewBottom = viewTop + page.AbsoluteWindowSize.Y

    local maxStaggered = math.floor(budget / perElementDelay)
    local staggered = 0
    for _, element in ipairs(tab.elements) do
        local top = element.main.AbsolutePosition.Y
        local onScreen = (top + element.main.AbsoluteSize.Y) > viewTop and top < viewBottom
        if onScreen then
            element:_setShown(true, true)
            staggered += 1
            if staggered <= maxStaggered then
                task.wait(perElementDelay)
            end
        else
            element:_setShown(true, false) -- off-screen: no point animating what isn't visible
        end
    end
end

function Window:Show()
    -- idempotent: replaying the restore on a visible window teleports it to a stale position
    if self.animating or not self.hidden then
        return
    end
    self.animating = true
    self._revealing = true

    -- autoLoad reflects the saved config once, on first open. Re-loading on every show would
    -- wipe any changes the user made and closed without saving. a load that throws must not
    -- strand animating=true, or the window could never open again.
    -- Auto Load Config (see the Configurations section in windowMethods.luau's
    -- _buildSettingsUI): its own button already calls _applyNamedConfig, which both applies the
    -- chosen configuration live and re-saves the default file to match - so the plain Load right
    -- here already restores whatever that button last committed, with nothing extra needed on
    -- this end.
    if self.configuration.autoLoad and not self._autoLoaded then
        self._autoLoaded = true
        local ok, err = pcall(self.Load, self)
        if not ok then
            log.warn("Rayfield: Failed to load configuration - " .. tostring(err))
        end
    end

    self.hidden = false
    self.minimised = false

    -- a ChangeTheme landed while we were collapsed; apply it before anything fades back in
    if self._themeRefreshPending then
        self._themeRefreshPending = false
        self:_refreshElementThemes()
    end

    self.collapsedInteract.Visible = false -- first thing on click: stop it eating any more input

    if self._freeMouse then
        self._freeMouse()
    end

    if self.hasShownOnce then
        self:_quickRestore()
    else
        self.hasShownOnce = true
        self:_firstShow()
    end
end

function Window:_quickRestore()
    -- the screen can have changed while we were hidden, so where it sat may no longer fit
    local target = self:_clampedPosition(self._restorePosition or UDim2.new(0.5, 0, 0.5, 0))
    self._restorePosition = target

    -- slowed down from 0.35/0.28 (read as too fast, opening almost instantly) - kept in named
    -- locals so the task.delay staging below stays in step with the new pacing
    local growDuration, fadeDuration = 0.5, 0.38
    -- "Open from Pill": the mirror of Hide's own Quint/Out collapse - same curve family so the
    -- open and close read as one continuous motion reversed, not two differently-paced animations
    local growInfo = TweenInfo.new(growDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local cornerInfo = TweenInfo.new(growDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

    -- Phase 1: nothing but the pill morphing back into the window frame. The collapsed face
    -- fades off, main grows + un-rounds. No chrome, no content - so you never see the topbar,
    -- tabs or bottom fade floating over a frame that isn't a window yet.
    chrome.setCollapsedShown(self, false, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    self:_setTopToastPosition(TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    variables.tweenService:Create(self.main, growInfo, { Size = self.size, Position = target }):Play()
    -- squircle mode has no windowCorner to un-round back from the pill's fully-round corner -
    -- the squircle shape just stays at its own normal radius throughout the restore (a known,
    -- disclosed gap: the pill-collapse animation isn't squircle-aware yet, see Hide's own note).
    if self.windowCorner then
        variables.tweenService:Create(self.windowCorner, cornerInfo, { CornerRadius = self.theme.CornerRoundness }):Play()
    end

    -- Phase 2: once the frame actually reads as a window, fade its chrome in and stagger the
    -- open tab's elements. Other tabs snap ready off-screen - nobody's looking, so no animation.
    task.delay(growDuration * 0.63, function()
        -- respects the setting rather than hardcoding true, same as the minimise restore path
        self.resize.grip.Visible = self.settings.resizeGripEnabled
        if self.profile then
            self.profile.Visible = self.settings.showProfile
        end
        self.topbar.Visible = true
        self.tabList.Visible = true
        self.tabDock.Visible = true
        self.elements.Visible = true
        self:_setTabIndicatorVisible(true, fadeInfo)

        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = self._shadowTransparency or 0.6 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 0 }):Play()
        variables.tweenService:Create(self.topFade, fadeInfo, { BackgroundTransparency = 0 }):Play()

        if self.topbarIcon then
            variables.tweenService:Create(self.topbarIcon, fadeInfo, { ImageTransparency = 0 }):Play()
        end
        if self.title then
            variables.tweenService:Create(self.title, fadeInfo, { TextTransparency = 0 }):Play()
        end
        if self.subtitle then
            variables.tweenService:Create(self.subtitle, fadeInfo, { TextTransparency = 0.7 }):Play()
        end

        for _, action in ipairs(self.actionContainer:GetChildren()) do
            if action:IsA("Frame") then
                variables.tweenService:Create(action.ImageLabel, fadeInfo, { ImageTransparency = 0.6 }):Play()
            end
        end

        -- if we were hidden with the settings page open, bring its cog back lit (its open
        -- state) rather than the default resting brightness the loop above just set
        if self.settingsAction and self.selectedTab == self.rfSettings then
            variables.tweenService:Create(self.settingsAction.iconLabel, fadeInfo, { ImageTransparency = 0.2 }):Play()
        end

        for _, tag in self.tags do
            tag:_setShown(true, fadeInfo)
        end

        for _, tab in pairs(self.tabs) do
            if not tab.neglectSelector and tab.topbarItem then
                tab.topbarItem.Visible = true
                tab:_applyVisual(if self.selectedTab == tab then "selected" else "unselected", fadeInfo)
            end
        end
        self:_setTabSectionsVisible(true)
        self:_setTabSectionsShown(true, fadeInfo)
        task.wait() -- let UIListLayout resolve the tabs that just went Visible = true
        self:_updateTabIndicator(self.selectedTab, false)

        self:_revealElements(0.035, 0.4)
    end)

    -- Drag handle grows in with the chrome, same width sweep it uses on first reveal. Position
    -- is recalculated against the full restored size - if the window was minimised (a shorter
    -- bar-hang offset) before hiding, it would otherwise reappear at the old, wrong height.
    task.delay(growDuration * 0.63, function()
        self.drag.drag.Position =
            UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale, target.Y.Offset + self.size.Y.Offset / 2 + 15)
        self.drag.dragCosmetic.Size = UDim2.fromOffset(0, 4)
        self.drag.dragCosmetic.BackgroundTransparency = 1
        self.drag.drag.Visible = true
        variables.tweenService
            :Create(self.drag.dragCosmetic, growInfo, { Size = UDim2.fromOffset(100, 4), BackgroundTransparency = 0.7 })
            :Play()
    end)

    task.delay(growDuration * 1.71, function()
        self.animating = false
        self._revealing = false
    end)
end

local loadingFadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- Back/Out overshoots past the target then settles back - the "pop" on the icon. Safe to animate
-- Size here specifically because this overlay is a free-floating Frame with hand-placed
-- (Position-offset, not UIListLayout) children - nothing here reflows a sibling the way animating
-- Size inside a UIListLayout-managed row would (see resize.luau/label.luau's own notes on that
-- class of bug elsewhere in this codebase). None of that risk applies to a one-off splash with
-- three fixed-position children.
local loadingPopInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local loadingTipSlideInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local loadingIconSize = 48
local loadingIconStartSize = 22

-- Vertical rhythm for the splash's stacked text - fixed pixel box heights with top-aligned text,
-- not the UDim2.fromScale heights this had before. Live-caught: a Scale height ties the box to
-- the *whole window's* height, not the font, so at a normal window size the box came out far
-- taller than the one line of text inside it - and with the default TextYAlignment (Center), the
-- glyphs sat in the middle of that oversized box while every offset below still assumed a small,
-- tightly-wrapping one. The visible symptom was the progress bar reading as glued to the tip
-- above it: the bar's own Y already accounted for a gap that existed in the data, just not on
-- screen, because the tip's real glyphs extended further down than the box's "size" implied.
local loadingTitleHeight = 26
local loadingTipHeight = 18
local loadingBarGap = 18 -- deliberately roomy - requested outright, was reading as glued before

-- The dev-configured loading splash (see self.loading, set from WindowProps.loading in .new):
-- icon pops in (scale bounce + a soft accent glow) over the still-blank window card, the title
-- fades in with it, an optional tip line cycles under them - crossfading with a slight upward
-- slide, like a ticker - while a thin progress bar underneath fills across the splash's real
-- total duration. Everything fades back out before _firstShow's own staged reveal takes over.
-- Unlike PlayGreeting there's no shrink/corner-round wipe here - nothing underneath is visible
-- yet for one to reveal, so a plain fade in and back out is the whole trick.
function Window:_playLoadingSplash()
    local config = self.loading
    local icon = config.icon or self.icon
    local title = config.title or self.name
    local tips = config.tips

    -- Opaque, not just "on top" - live-caught toggle tracks and other resting-state chrome (not
    -- part of the staged reveal's own fade-in chain, styled visible at construction regardless
    -- of self.hidden) showing straight through a transparent-background overlay, and the overlay
    -- not filling the full card the way PlayGreeting's own opaque one does. Same white-base +
    -- WindowColor-gradient recipe main itself uses (see main's own creation above) so this reads
    -- as "the window itself, just showing loading content" rather than a mismatched flash, and
    -- its own UICorner matches the window's rounding so a square overlay corner never pokes past
    -- main's rounded one.
    local overlay = self:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.loading,

        Parent = self.main,
    })

    self:Create("UICorner", {
        Parent = overlay,
    }, { CornerRadius = "CornerRoundness" })

    -- the gradient (not BackgroundColor3 itself) is what actually recolours the white base to
    -- the theme's WindowColor - a Frame's BackgroundColor3 wants a Color3, not the ColorSequence
    -- toColorSequence produces, same reason main's own gradient is a separate child instead
    self:Create("UIGradient", {
        Rotation = 270,
        Offset = Vector2.new(0, -0.1),

        Parent = overlay,
    }, { Color = { "WindowColor", functions.toColorSequence } })

    local iconLabel, iconGlow
    if icon then
        iconLabel = self:Create("ImageLabel", {
            Image = icon,
            Size = UDim2.fromOffset(loadingIconStartSize, loadingIconStartSize),
            Position = UDim2.new(0.5, 0, 0.5, -18),
            AnchorPoint = Vector2.new(0.5, 1),
            BackgroundTransparency = 1,
            ImageTransparency = 1,
            ZIndex = constants.zIndex.loading,

            Parent = overlay,
        }, { ImageColor3 = "ContentColor" })

        -- soft glow behind the icon, same helper every other accent glow in this codebase uses
        iconGlow = self:CreateGlow(iconLabel, "AccentColor", 22, 1)
    end

    local titleY = if icon then 4 else -10
    local titleLabel = self:Create("TextLabel", {
        Text = locale.t(title or ""),

        Size = UDim2.new(0.85, 0, 0, loadingTitleHeight),
        Position = UDim2.new(0.5, 0, 0.5, titleY),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundTransparency = 1,
        TextSize = 22,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextTransparency = 1,
        FontFace = self.theme.TitleFont,
        ZIndex = constants.zIndex.loading,

        Parent = overlay,
    }, { TextColor3 = "ContentColor" })

    local tipRestY = titleY + loadingTitleHeight + 8
    local tipLabel
    if #tips > 0 then
        tipLabel = self:Create("TextLabel", {
            Size = UDim2.new(0.8, 0, 0, loadingTipHeight),
            Position = UDim2.new(0.5, 0, 0.5, tipRestY + 6), -- starts a hair low, slides up as it fades in
            AnchorPoint = Vector2.new(0.5, 0),
            BackgroundTransparency = 1,
            TextSize = 14,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextTransparency = 1,
            FontFace = self.theme.Font,
            ZIndex = constants.zIndex.loading,

            Parent = overlay,
        }, { TextColor3 = "ContentColor" })
    end

    -- Thin fill bar under everything else, tracking real elapsed time against the splash's own
    -- total duration - an actual progress readout, not just a decorative loop. barY starts from
    -- whichever text actually sits above it (tip if there is one, title otherwise) plus a
    -- deliberately roomy gap, rather than the cramped one this had before.
    local barY = (if #tips > 0 then tipRestY + loadingTipHeight else titleY + loadingTitleHeight) + loadingBarGap
    local progressTrack = self:Create("Frame", {
        Size = UDim2.fromOffset(120, 3),
        Position = UDim2.new(0.5, 0, 0.5, barY),
        AnchorPoint = Vector2.new(0.5, 0),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.loading,

        BackgroundTransparency = 1, -- In = 0.85

        Parent = overlay,
    }, { BackgroundColor3 = "SurfaceStroke" })
    self:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = progressTrack })

    local progressFill = self:Create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BorderSizePixel = 0,
        ZIndex = constants.zIndex.loading,

        BackgroundTransparency = 1, -- In = 0

        Parent = progressTrack,
    }, { BackgroundColor3 = "AccentColor" })
    self:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = progressFill })

    -- Soft sheen riding across the fill, same loop technique shimmerlabel.luau uses for its own
    -- sweep (a tween back and forth on a UIGradient's Offset, re-armed via Completed:Wait() - not
    -- RenderStepped, and self-terminating the moment progressFill is gone, which overlay:Destroy()
    -- at the very end of this function takes care of).
    local fillShimmer = self:Create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.4, 1),
            NumberSequenceKeypoint.new(0.5, 0.5),
            NumberSequenceKeypoint.new(0.6, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Offset = Vector2.new(-1, 0),

        Parent = progressFill,
    })
    task.spawn(function()
        while fillShimmer.Parent do
            fillShimmer.Offset = Vector2.new(-1, 0)
            local tween = variables.tweenService:Create(
                fillShimmer,
                TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Offset = Vector2.new(1, 0) }
            )
            tween:Play()
            tween.Completed:Wait()
            task.wait(0.15)
        end
    end)

    -- Percentage readout, right of the track - a plain task.wait loop against a wall-clock
    -- start time (not RenderStepped), so it's cheap and self-terminates the same way the shimmer
    -- above does once the overlay (and this label with it) is destroyed.
    local percentLabel = self:Create("TextLabel", {
        Text = "0%",
        Size = UDim2.fromOffset(34, 14),
        Position = UDim2.new(1, 10, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 1,
        FontFace = self.theme.Font,
        ZIndex = constants.zIndex.loading,

        Parent = progressTrack,
    }, { TextColor3 = "PlaceholderColor" })

    -- Real total time the splash stays up: the tip cycle's own length, floored by `duration` so
    -- a single (or zero) tip doesn't flash by. The fill bar's own tween is timed to this exact
    -- number, so it always finishes right as the splash starts fading out, never early or late.
    local tipCycleTime = if #tips > 0 then #tips * config.tipHoldTime + (#tips - 1) * 0.15 else 0
    local totalTime = math.max(config.duration, tipCycleTime)

    task.spawn(function()
        local start = os.clock()
        while percentLabel.Parent and os.clock() - start < totalTime do
            percentLabel.Text = math.floor(math.clamp((os.clock() - start) / totalTime, 0, 1) * 100) .. "%"
            task.wait(0.1)
        end
        if percentLabel.Parent then
            percentLabel.Text = "100%"
        end
    end)

    if iconLabel then
        variables.tweenService
            :Create(iconLabel, loadingPopInfo, { Size = UDim2.fromOffset(loadingIconSize, loadingIconSize) })
            :Play()
        variables.tweenService:Create(iconLabel, loadingFadeInfo, { ImageTransparency = 0 }):Play()
        if iconGlow then
            variables.tweenService:Create(iconGlow, loadingFadeInfo, { Transparency = 0.75 }):Play()
        end
    end
    variables.tweenService:Create(titleLabel, loadingFadeInfo, { TextTransparency = 0 }):Play()
    variables.tweenService:Create(progressTrack, loadingFadeInfo, { BackgroundTransparency = 0.85 }):Play()
    variables.tweenService:Create(progressFill, loadingFadeInfo, { BackgroundTransparency = 0 }):Play()
    variables.tweenService:Create(percentLabel, loadingFadeInfo, { TextTransparency = 0.3 }):Play()
    variables.tweenService
        :Create(progressFill, TweenInfo.new(totalTime, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
        :Play()

    -- Cycle the tips (if any) the same way PlayGreeting cycles its texts, crossfading with a
    -- slight upward slide (ticker feel) instead of a plain opacity swap. Tracks how long this
    -- actually took so the wait below only ever makes up the difference to `totalTime`.
    local elapsed = 0
    if tipLabel then
        for i, tip in tips do
            tipLabel.Text = locale.resolve(tostring(tip))
            tipLabel.Position = UDim2.new(0.5, 0, 0.5, tipRestY + 6)
            variables.tweenService:Create(tipLabel, loadingTipSlideInfo, {
                TextTransparency = 0.4,
                Position = UDim2.new(0.5, 0, 0.5, tipRestY),
            }):Play()
            task.wait(config.tipHoldTime)
            elapsed += config.tipHoldTime
            if i < #tips then
                variables.tweenService:Create(tipLabel, loadingTipSlideInfo, {
                    TextTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, tipRestY - 6),
                }):Play()
                task.wait(0.15)
                elapsed += 0.15
            end
        end
    end

    if elapsed < totalTime then
        task.wait(totalTime - elapsed)
    end

    if iconLabel then
        variables.tweenService:Create(iconLabel, loadingFadeInfo, { ImageTransparency = 1 }):Play()
        if iconGlow then
            variables.tweenService:Create(iconGlow, loadingFadeInfo, { Transparency = 1 }):Play()
        end
    end
    variables.tweenService:Create(titleLabel, loadingFadeInfo, { TextTransparency = 1 }):Play()
    variables.tweenService:Create(progressTrack, loadingFadeInfo, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(progressFill, loadingFadeInfo, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(percentLabel, loadingFadeInfo, { TextTransparency = 1 }):Play()
    if tipLabel then
        variables.tweenService:Create(tipLabel, loadingFadeInfo, { TextTransparency = 1 }):Play()
    end
    task.wait(loadingFadeInfo.Time)

    overlay:Destroy()
end

function Window:_firstShow()
    -- Intro animation
    self.elements.Visible = true
    self.tabList.Visible = true
    self.tabDock.Visible = true
    self.drag.drag.Visible = false
    self.main.Visible = true

    if self.loading and self.settings.loadingAnimationEnabled then
        -- Loading splash: main snaps straight to its resting size/opacity instead of growing in
        -- - nothing else on it is visible yet anyway (every bit of chrome below is still at its
        -- hidden transparency, untouched until the splash clears), so there's nothing to hide
        -- and nothing lost by skipping the grow tween here. The splash plays centred on that
        -- otherwise-blank card, then fades itself out, and the rest of this function's own
        -- staged reveal (shadow, icon, title, tabs, elements, ...) runs exactly as it always did.
        local target, prop = self:_mainVisual()
        target[prop] = 1 - self.windowOpacity
        self.main.Size = self.size
        self:_playLoadingSplash()
    else
        -- Size always animates on self.main itself (mainSquircle just fills it via
        -- Size = fromScale(1,1) and rides along) - only the opacity property/target differs
        -- between plain and squircle mode, via _mainVisual.
        local target, prop = self:_mainVisual()
        local growInfo = TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
        variables.tweenService:Create(self.main, growInfo, { Size = self.size }):Play()
        variables.tweenService:Create(target, growInfo, { [prop] = 1 - self.windowOpacity }):Play()
        task.wait(0.85) -- let the frame actually read as a window before anything shows on top of it
    end

    -- Live-caught: drag.luau computes the bar's very first rest position once, at construction,
    -- against whatever self.size happened to be *then* - if a persisted custom size loads and
    -- changes self.size afterward (the normal case: settings load after Drag.new runs), main
    -- ends up at that larger/smaller size above but the bar is never told to recompute, so it
    -- stays parked wherever the construction-time size put it - which, for a saved size bigger
    -- than the default, lands it well inside the window instead of hanging under its real bottom
    -- edge. Read as "the drag bar sometimes ends up inside the UI" (regrabbing it "fixes" it only
    -- because InputBegan's own getTargets() call forces a fresh read). Resyncing here, now that
    -- main is actually at its true resting size, is the first point that value is reliably known.
    self:_syncDragBar()
    variables.tweenService
        :Create(
            self.windowShadow,
            TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Transparency = self._shadowTransparency or 0.6 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.bottomFade,
            TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.topFade,
            TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        )
        :Play()
    task.wait(0.3)

    if self.icon then
        variables.tweenService
            :Create(
                self.topbarIcon,
                TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { ImageTransparency = 0 }
            )
            :Play()
    end
    if self.title then
        variables.tweenService
            :Create(
                self.title,
                TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { TextTransparency = 0 }
            )
            :Play()
    end
    task.wait(0.1)
    if self.subtitle then
        variables.tweenService
            :Create(
                self.subtitle,
                TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { TextTransparency = 0.7 }
            )
            :Play()
    end

    for _, action in ipairs(self.actionContainer:GetChildren()) do
        if action:IsA("Frame") then
            task.wait(0.02)
            variables.tweenService
                :Create(
                    action.ImageLabel,
                    TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                    { ImageTransparency = 0.6 }
                )
                :Play()
        end
    end

    for _, tag in self.tags do
        tag:_setShown(true, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out))
    end

    task.wait(0.2)

    task.spawn(function()
        for _, tab in pairs(self.tabs) do
            if not tab.neglectSelector then
                tab.topbarItem.Visible = true
                tab:_applyVisual(
                    if self.selectedTab == tab then "selected" else "unselected",
                    TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                )
                if self.selectedTab == tab then
                    task.wait() -- let UIListLayout resolve this tab now that it's Visible = true
                    self:_updateTabIndicator(tab, false)
                end

                task.wait(0.15)
            end
        end
        self:_setTabSectionsVisible(true)
        self:_setTabSectionsShown(true, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    end)

    self:_revealElements(0.03, 2)

    task.wait(1)

    self.drag.drag.Visible = true
    variables.tweenService
        :Create(
            self.drag.dragCosmetic,
            TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.7 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.drag.dragCosmetic,
            TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(100, 4) }
        )
        :Play()
    -- Same grow-and-fade, same moment - explicit ask to have the resize corner wake up
    -- alongside the drag bar instead of just always having been there.
    if self.resize then
        self.resize:_reveal()
    end

    self.animating = false
    self._revealing = false

    -- Welcome the user once if this is a new/changed account on this device (unless they've
    -- turned it off in settings). Just a toast now - the profile chip is a toast like any other.
    local localPlayer = variables.localPlayer
    if localPlayer and self.settings.welcomeToast and chrome.isNewUser() then
        self:Toast({
            title = localPlayer.DisplayName,
            subtitle = locale.resolve("Signed in as"),
            subtitleAbove = true, -- reads "Signed in as" / name, label over value
            avatar = localPlayer.UserId,
            minWidth = 220, -- match the old license card's width for that roomy right-hand space
        })
    end

    -- Guided tour, after everything else has finished revealing (animating/_revealing both
    -- false above) so it isn't racing the staged fade-in for the very elements it's about to
    -- point at. Once per player - self.settings.tourSeen flips true the moment the tour ends
    -- (finished or skipped, see Tour:finish) and persists from there.
    if self.tourSteps and not self.settings.tourSeen then
        self.tour:start(self.tourSteps)
    end
end

function Window:GetPath()
    return persistence.getPath(self)
end

-- name saves to a specific config; omit it to save the default file.
function Window:Save(name)
    if name ~= nil and (type(name) ~= "string" or name == "") then
        return false
    end
    return persistence.save(self, name)
end

-- name loads a specific config; omit it to load the default file.
function Window:Load(name)
    if name ~= nil and (type(name) ~= "string" or name == "") then
        return false
    end
    return persistence.load(self, name)
end

-- Load a named config and make it the live state autoLoad restores next session. Loading only
-- applies to the running UI; writing it back to the default file is what carries it across
-- sessions, so the config manager can pick a config once and have it stick.
function Window:_applyNamedConfig(name)
    if not self:Load(name) then
        return false
    end
    self:Save()
    return true
end

-- Public name for _applyNamedConfig - Fluent calls this shape "autoload" (SaveManager:
-- LoadAutoloadConfig, picking one saved config to be what loads automatically next session).
-- _applyNamedConfig already *is* that: load the named config live, then Save() to the default
-- file so it's what a plain Load()/autoLoad picks up from here on. This is just the
-- discoverable public name for calling that on demand, same as the Settings "Load" button does.
function Window:SetAutoloadConfig(name)
    return self:_applyNamedConfig(name)
end

-- Play a guided tour on demand - the same thing that plays automatically on first show if the
-- dev configured one (see _firstShow), just callable any time (a "Replay Tour" settings button,
-- a help menu, whatever). Omit steps to replay whatever was configured at CreateWindow.
function Window:StartTour(steps)
    self.tour:start(steps or self.tourSteps)
end

function Window:ListConfigs()
    return persistence.list(self)
end

function Window:DeleteConfig(name)
    return persistence.delete(self, name)
end

-- Encode every control's current value to a JSON string and, best-effort, put it on the
-- clipboard (silently a no-op copy if the executor has no setclipboard-shaped function - see
-- clipboard.luau). Always returns the string too, so a dev can hand it to the player some other
-- way (a text box to select-all-copy from) when the clipboard write itself didn't take.
function Window:ExportConfig(): (boolean, string?)
    local ok, encoded = persistence.encode(self)
    if not ok or not encoded then
        return false, nil
    end
    clipboard.copy(encoded)
    return true, encoded
end

-- Parse a pasted config string (the exact shape ExportConfig produces) and apply it to every
-- currently-built control. Doesn't touch the config *file* - same relationship Load() has to
-- Save(), importing only changes the running UI unless the caller also calls Save() to carry it
-- across sessions the way the Settings "Configurations" UI's own Load button does.
function Window:ImportConfig(raw: string): boolean
    local flags = persistence.decode(raw)
    if not flags then
        return false
    end
    return persistence.applyFlags(self, flags)
end

-- Read a flag's current value, or nil if nothing is registered under it.
function Window:Get(flag)
    local control = self.controls[flag]
    return control and control.value
end

-- Set a flag's value, routing through the control so the UI updates and the callback fires.
-- Returns false if no control is registered under the flag.
function Window:Set(flag, value)
    local control = self.controls[flag]
    if not control then
        return false
    end
    control:Set(value)
    return true
end

-- Register a plain value under a flag so it rides the window's own config persistence
-- (Save/Load/autoSave/autoLoad) exactly like a visible control's value, without needing an
-- on-screen toggle/slider to hang the flag off of - e.g. a consumer script's own dragged sidebar
-- width or a floating HUD's dragged position, both real per-player state with nothing built-in
-- to persist them. onChanged (optional) fires with the value any time it changes - both from a
-- live Window:Set(flag, ...)/control:Set(...) call and from a config Load() restoring a saved
-- one - so the caller has one place to apply it back onto whatever it actually controls.
-- The returned control's own :Set(value) is what a consumer wires its live changes through (see
-- Window:OnSidebarWidthChanged/Hud:OnPositionChanged for the pattern) so those changes get saved.
function Window:RegisterFlag(flag: string, initial: unknown, onChanged: ((unknown) -> ())?)
    local window = self
    local control = { value = initial, flag = flag }
    function control:Set(value)
        self.value = value
        if onChanged then
            onChanged(value)
        end
        window:_persist(self)
    end
    window:_registerControl(control)
    return control
end

-- Jump to a tab by handle, name, or its page instance. No-ops on an unknown tab rather
-- than handing JumpTo something it cant resolve.
-- Move the page view only. Tab:Select owns the selection state and the pill, and calls this
-- for the scroll; nothing else should jump pages without going through it.
function Window:_jumpTo(page)
    if page then
        self.elementsLayout:JumpTo(page)
    end
end

-- Go to a tab, by name or by the tab itself. Routes through Tab:Select so the selection,
-- the pill and the page all agree; jumping the page alone would leave the wrong tab lit and
-- the reveal animations pointed at the wrong elements.
function Window:Navigate(tab)
    if tab == nil then
        return
    end

    local target
    for _, candidate in self.tabs do
        -- by name, by the tab itself, or by the page instance a caller held onto
        if candidate == tab or candidate.name == tab or candidate.tabPage == tab then
            target = candidate
            break
        end
    end

    if not target then
        return
    end
    target:Select()
end

function Window:Create(className, properties, themeProperties)
    assert(typeof(className) == "string", "Invalid argument #1 (string expected)")
    local instance = Instance.new(className)

    -- Themed properties apply first so animation start-states in `properties` (e.g. a hidden
    -- BackgroundTransparency = 1) still win at build; the theme value is the reveal target.
    if themeProperties and self.theme then
        for property, value in themeProperties do
            instance[property] = (
                if typeof(value) == "table" then value[2](self.theme[value[1]]) else self.theme[value]
            )
        end

        self.themeProperties[instance] = themeProperties
    end

    if properties then
        for property, value in properties do
            if locale.isToken(value) then
                self:_bindLocale(instance, property, locale.sourceOf(value))
            else
                image.assign(instance, property, value)
            end
        end
    end

    table.insert(self.instances, instance)
    return instance
end

-- Bind instance[property] to a source string: set it to the active locale's form now and remember
-- it so SetLocale can re-resolve in place without rebuilding anything. Mirrors how themeProperties
-- lets ChangeTheme re-apply themed values later.
function Window:_bindLocale(instance, property, source)
    instance[property] = locale.resolve(source)

    local entries = self.localeProperties[instance]
    if not entries then
        entries = {}
        self.localeProperties[instance] = entries
    end
    entries[property] = source
end

-- Swap every localized label to `localeId` in place. Element values, slider readouts and other
-- data aren't copy, so they're untouched. AutomaticSize reflows widths for us; the few manually
-- measured labels (toasts) are transient enough not to need a re-measure.
function Window:SetLocale(localeId)
    locale.setActive(localeId)
    for instance, entries in self.localeProperties do
        for property, source in entries do
            instance[property] = locale.resolve(source)
        end
    end
end

-- Swap the dev translation hook (source, localeId) -> string?. Follow with SetLocale (or pass the
-- same locale back) to re-resolve everything already on screen through the new hook.
function Window:SetTranslator(translator)
    locale.translator = translator
end

-- Merge more translation tables in at runtime ({ [localeId] = { [source] = translated } }) and
-- re-apply the active locale, so a language pack added after the UI is built lands immediately.
function Window:RegisterTranslations(tables)
    locale.register(tables)
    self:SetLocale(locale.current)
end

-- Soft glow behind a GuiObject via a native UIShadow (no image). ZIndex -1 keeps it behind.
-- `color` is a Color3 for a fixed glow, or a theme key (string) for a shadow that tracks the
-- theme and re-tints on ChangeTheme - a ColorSequence key resolves to its first keypoint.
function Window:CreateGlow(parent, color, blur, transparency)
    local properties = {
        BlurRadius = UDim.new(0, blur),
        Transparency = transparency,
        ZIndex = -1,

        Parent = parent,
    }

    if typeof(color) == "string" then
        return self:Create("UIShadow", properties, {
            Color = {
                color,
                function(value)
                    return if typeof(value) == "ColorSequence" then value.Keypoints[1].Value else value
                end,
            },
        })
    end

    properties.Color = color
    return self:Create("UIShadow", properties)
end

-- Flash an element's inset box + glow to signal a set landed: green for a good set, red for a
-- rejected one, then settle back to the box's idle look. green/red are our universal accents.
-- The element supplies `box`, an optional `glow`, and its idle transparencies (_boxIdle/_glowIdle).
function Window:_flashResult(element, ok)
    local box = element.box
    if not box then
        return
    end
    local glow = element.glow
    local stroke = element.boxStroke
    local fill = ok and constants.accent.on or self.theme.ErrorColor
    local edge = ok and constants.accent.onStroke or self.theme.ErrorStrokeColor
    local inInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local outInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    -- a quick coloured pulse: box fill tints (transparency untouched), edge + glow brighten
    variables.tweenService:Create(box, inInfo, { BackgroundColor3 = fill }):Play()
    if stroke then
        variables.tweenService:Create(stroke, inInfo, { Color = edge, Transparency = 0.4 }):Play()
    end
    if glow then
        variables.tweenService:Create(glow, inInfo, { Color = edge, Transparency = 0.6 }):Play()
    end

    -- token so a quick re-set restarts the flash instead of an old revert cutting it short
    element._flashToken = (element._flashToken or 0) + 1
    local token = element._flashToken
    task.delay(0.22, function()
        if element._flashToken ~= token then
            return
        end
        variables.tweenService:Create(box, outInfo, { BackgroundColor3 = self.theme.FieldBackground }):Play()
        if stroke then
            variables.tweenService
                :Create(stroke, outInfo, { Color = self.theme.SurfaceStroke, Transparency = 0.85 })
                :Play()
        end
        if glow then
            variables.tweenService
                :Create(glow, outInfo, { Color = self.theme.FieldGlow, Transparency = element._glowIdle or 1 })
                :Play()
        end
    end)
end

-- Additive white hover-brighten overlay filling an element (fill colour comes from the gradient).
-- Tween its BackgroundTransparency 1 -> ~0.97 on hover.
function Window:CreateHoverOverlay(parent)
    local overlay = self:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        ZIndex = 1,

        Parent = parent,
    })

    self:Create("UICorner", {
        Parent = overlay,
    }, { CornerRadius = "ElementCornerRadius" })

    return overlay
end

-- hover: brighten stroke + title (+ overlay). shared by button/toggle
function Window:_wireElementHover(element)
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local theme = self.theme

    self:Connect(element.main.MouseEnter, function()
        if not self:_interactive() then
            return -- window still revealing/hiding: dont light up mid-animation
        end
        variables.tweenService
            :Create(
                element.stroke,
                info,
                { Transparency = theme.ElementStrokeHoverTransparency, Color = theme.ElementStrokeHover }
            )
            :Play()
        variables.tweenService:Create(element.title, info, { TextColor3 = theme.ElementTextHoverColor }):Play()
        if element.hoverOverlay then
            variables.tweenService:Create(element.hoverOverlay, info, { BackgroundTransparency = 0.97 }):Play()
        end
    end)

    self:Connect(element.main.MouseLeave, function()
        variables.tweenService
            :Create(
                element.stroke,
                info,
                { Transparency = theme.ElementStrokeTransparency, Color = theme.ElementStroke }
            )
            :Play()
        variables.tweenService:Create(element.title, info, { TextColor3 = theme.ContentColor }):Play()
        if element.hoverOverlay then
            variables.tweenService:Create(element.hoverOverlay, info, { BackgroundTransparency = 1 }):Play()
        end
    end)
end

-- Tooltip: one shared bubble per window, repositioned and reused for whichever element is
-- currently hovered. Held white regardless of theme - it needs to read clearly against any
-- card colour, not blend into it.
local tooltipShowDelay = 0.5
local tooltipFadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tooltipFadeOut = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tooltipMaxWidth = 220
local tooltipCursorGap = 14 -- clears the cursor's own hotspot/hand icon

-- Screen-space mouse position, in the same coordinate space as our GuiObjects' AbsolutePosition.
-- Sounds like it should just be GetMouseLocation() as-is: our ScreenGui sets IgnoreGuiInset =
-- true, so its children's AbsolutePosition is inset-free, and GetMouseLocation() is documented
-- to already exclude the inset too - two things already in the same space needing no correction
-- between them. Measured wrong on the live test client though: with no correction at all, a
-- GuiObject's rendered AbsolutePosition still comes out exactly GetGuiInset().Y (58px) SMALLER
-- than the Y its own Position was set to - i.e. this ScreenGui is silently still applying the
-- inset shift on this executor regardless of IgnoreGuiInset. Confirmed the fix the same way:
-- placed the tooltip with no correction, read its real AbsolutePosition back, and it was short
-- by exactly GetGuiInset().Y - so it has to be ADDED back on the way in to land where intended,
-- the opposite of the subtraction this used to do (which made the shortfall twice as bad).
function Window:_mouseAbsolutePosition()
    local mouse = variables.userInputService:GetMouseLocation()
    local topLeftInset = variables.guiService:GetGuiInset()
    return Vector2.new(mouse.X, mouse.Y + topLeftInset.Y)
end

function Window:_ensureTooltip()
    if self.tooltipFrame then
        return
    end

    self.tooltipFrame = self:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        Visible = false,
        ZIndex = constants.zIndex.tooltip,

        Parent = self.screenGui,
    })

    self:Create("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = self.tooltipFrame,
    })

    self:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),

        Parent = self.tooltipFrame,
    })

    self.tooltipLabel = self:Create("TextLabel", {
        Text = "",
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        TextSize = 13,
        TextWrapped = true,
        TextColor3 = Color3.fromRGB(25, 25, 25),
        ZIndex = constants.zIndex.tooltip,

        TextTransparency = 1,

        Parent = self.tooltipFrame,
    }, { FontFace = "Font" })

    -- caps the wrap width so long copy wraps onto more lines instead of one wide bubble
    self:Create("UISizeConstraint", {
        MaxSize = Vector2.new(tooltipMaxWidth, math.huge),
        Parent = self.tooltipLabel,
    })
end

function Window:_showTooltip(text)
    self:_ensureTooltip()

    self.tooltipLabel.Text = locale.resolve(text)

    local mouse = self:_mouseAbsolutePosition()
    self.tooltipFrame.AnchorPoint = Vector2.new(0.5, 1)
    self.tooltipFrame.Position = UDim2.fromOffset(mouse.X, mouse.Y - tooltipCursorGap)
    self.tooltipFrame.Visible = true
    self.tooltipFrame.BackgroundTransparency = 1
    self.tooltipLabel.TextTransparency = 1

    self._tooltipToken = (self._tooltipToken or 0) + 1

    variables.tweenService:Create(self.tooltipFrame, tooltipFadeIn, { BackgroundTransparency = 0.05 }):Play()
    variables.tweenService:Create(self.tooltipLabel, tooltipFadeIn, { TextTransparency = 0 }):Play()
end

function Window:_hideTooltip()
    if not self.tooltipFrame or not self.tooltipFrame.Visible then
        return
    end

    self._tooltipToken = (self._tooltipToken or 0) + 1
    local token = self._tooltipToken

    variables.tweenService:Create(self.tooltipFrame, tooltipFadeOut, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(self.tooltipLabel, tooltipFadeOut, { TextTransparency = 1 }):Play()

    task.delay(tooltipFadeOut.Time, function()
        if self._tooltipToken == token and self.tooltipFrame then
            self.tooltipFrame.Visible = false
        end
    end)
end

-- Wires a hover-hold tooltip onto element.main (or element.tooltipTarget, for an element whose
-- main is a transparent wrapper - see the dropdown) if element.tooltip is set. Independent of
-- _wireElementHover so it applies uniformly whether or not the element wires its own hover
-- tint (the slider, dropdown, colorpicker etc. all do that separately).
function Window:_wireTooltip(element)
    if not element.tooltip or element.tooltip == "" then
        return
    end

    local target = element.tooltipTarget or element.main
    local pending = 0

    self:ConnectFor(element, target.MouseEnter, function()
        if not self:_interactive() then
            return -- window still revealing/hiding: dont pop a tooltip mid-animation
        end
        pending += 1
        local token = pending
        task.delay(tooltipShowDelay, function()
            if pending == token then
                self:_showTooltip(element.tooltip)
            end
        end)
    end)

    self:ConnectFor(element, target.MouseLeave, function()
        pending += 1 -- invalidates any pending show, whether or not it had already fired
        self:_hideTooltip()
    end)
end

-- run a callback with the red error-flash on failure, debounced via element._errored so a
-- slider firing every frame flashes once. shared by every interactive element. elements whose
-- `main` is a transparent wrapper (the dropdown) set `flashTarget` to the frame to tint.
function Window:_runGuarded(element, fn, ...)
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(function()
            return fn(table.unpack(args, 1, args.n))
        end)
        if ok or element._errored then
            return
        end
        element._errored = true

        local flashFrame = element.flashTarget or element.main
        local quickOut = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        variables.tweenService:Create(flashFrame, quickOut, { BackgroundColor3 = self.theme.ErrorColor }):Play()
        variables.tweenService:Create(element.stroke, quickOut, { Color = self.theme.ErrorStrokeColor }):Play()
        -- minimal elements build without a label, and the flash must survive that
        if element.title then
            element.title.Text = locale.resolve("Error, log recorded in console.")
        end

        log.warn(
            `Rayfield encountered an error, with the callback for a {element.__type} component named '{element.name}':`
        )
        log.print(err)

        task.wait(1)

        if element.title then
            element.title.Text = locale.resolve(element.name)
        end
        variables.tweenService
            :Create(
                flashFrame,
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }
            )
            :Play()
        variables.tweenService
            :Create(
                element.stroke,
                TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Color = self.theme.ElementStroke }
            )
            :Play()
        element._errored = false
    end)
end

-- Runs fn(...) in a pcall and logs a warning on failure instead of letting it fail silently or
-- propagate uncaught - the general-purpose version of the same "never let an error just
-- disappear" principle _runGuarded/Toggle:Loop apply to a callback/loop tick specifically. Meant
-- for any one-off risky call a feature makes on its own (an instance lookup that might not
-- exist, a remote invoke) that isn't already wrapped by one of those. Returns exactly what pcall
-- returns (ok, result...) - this doesn't swallow the failure, just makes sure it's never
-- invisible, so the caller can still branch on `ok` itself.
function Window:Safe(fn, ...)
    local results = table.pack(pcall(fn, ...))
    if not results[1] then
        log.warn("Rayfield: Window:Safe call errored - " .. tostring(results[2]))
    end
    return table.unpack(results, 1, results.n)
end

-- Retries fn(attempt) up to options.attempts times (default 3), waiting
-- options.baseDelay * 2^(attempt-1) seconds between each (default 1s base: 1s, 2s, 4s, ...),
-- capped at options.maxDelay (default 10s) - exponential backoff so a flaky remote call/HTTP
-- request gets a few real chances to recover from a transient hiccup without hammering it (or a
-- rate limit) on a tight retry loop. Returns the same (ok, result) shape pcall/Safe do: true plus
-- fn's own result the moment it succeeds, or false plus the last error once every attempt is
-- spent. Only for something worth retrying at all - a resource that's actually gone for good
-- (an instance that got destroyed, a bad argument) just fails the same way every attempt and
-- burns the whole backoff for nothing; reach for Window:Safe instead for those.
function Window:RetryWithBackoff(fn, options: { attempts: number?, baseDelay: number?, maxDelay: number? }?)
    options = if typeof(options) == "table" then options else {}
    local attempts = options.attempts or 3
    local baseDelay = options.baseDelay or 1
    local maxDelay = options.maxDelay or 10

    local lastError
    for attempt = 1, attempts do
        local ok, result = pcall(fn, attempt)
        if ok then
            return true, result
        end
        lastError = result
        if attempt < attempts then
            task.wait(math.min(baseDelay * (2 ^ (attempt - 1)), maxDelay))
        end
    end
    log.warn(
        "Rayfield: Window:RetryWithBackoff gave up after " .. attempts .. " attempts - " .. tostring(lastError)
    )
    return false, lastError
end

-- Standard element body: white base + gradient fill + rounded corner + flat stroke (hidden until shown).
-- Returns the stroke; call after creating `main` with a white BackgroundColor3.
function Window:StyleElementBody(main)
    -- Devlog 7 fix: every card's fill rides ElementTransparency, which SetTransparency now
    -- scales all the way to 1 on purpose (a fully "glass" window) - a plain Frame's default
    -- Active is false, and per Roblox's own rule that stops it blocking/capturing input in its
    -- own bounds the instant BackgroundTransparency actually reaches 1, same as self.main's own
    -- fix. Centralized here rather than touching every component's own main creation, since
    -- every card-shaped element already calls this right after building main.
    (main :: any).Active = true

    self:Create("UIGradient", {
        Rotation = 270,

        Parent = main,
    }, { Color = "ElementGradient" })

    self:Create("UICorner", {
        Parent = main,
    }, { CornerRadius = "ElementCornerRadius" })

    return self:Create("UIStroke", {
        Transparency = 1,

        Parent = main,
    }, { Color = "ElementStroke", Transparency = "ElementStrokeTransparency" })
end

-- Devlog 6 lock system -------------------------------------------------------------------
-- A small padlock. Tries the real Lucide "lock" icon first (see icons.luau - fetched from this
-- project's own pinned-commit GitHub mirror, the same HttpGet + loadstring approach every other
-- dev-loadstring asset in this codebase already uses, not a server RemoteFunction like WindUI's
-- own loader leans on, since an executor-injected library can't stand one of those up in
-- someone else's game). Falls back to drawing one from two plain frames (a rounded body + a
-- thin rounded shackle arc) if the
-- pack isn't reachable, so a dead repo dims a locked element's glyph in quality, never removes
-- it outright. Shared by every lockable element (Button, Toggle, Dropdown, Tab, HoldButton) so
-- the glyph and its math live in exactly one place.
function Window:_buildLockIcon(parent, position, anchorPoint)
    local holder = self:Create("Frame", {
        AnchorPoint = anchorPoint or Vector2.new(1, 0.5),
        Position = position or UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Visible = false,

        Parent = parent,
    })

    local lockIcon = icons.find("lock", "lucide")
    if lockIcon then
        self:Create("ImageLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = lockIcon.Image,
            ZIndex = 5,

            Parent = holder,
        }, { ImageColor3 = "PlaceholderColor" })

        return holder
    end

    local body = self:Create("Frame", {
        Position = UDim2.new(0.5, 0, 1, 0),
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(14, 9),
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = holder,
    }, { BackgroundColor3 = "PlaceholderColor" })
    self:Create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = body })

    local shackle = self:Create("Frame", {
        Position = UDim2.new(0.5, 0, 1, -8),
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(9, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = holder,
    })
    self:Create("UIStroke", {
        Thickness = 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,

        Parent = shackle,
    }, { Color = "PlaceholderColor" })
    self:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shackle })

    return holder
end

-- The "no entry" glyph shown to the left of a locked element's title. Tries the real Lucide
-- "ban" icon first, same fallback story as the padlock above (a hand-drawn ring + diagonal
-- slash if the pack isn't reachable). A plain flowed child of `parent`'s own icon/title row:
-- toggling .Visible re-flows the row around it automatically, no absolute positioning to keep
-- in sync.
function Window:_buildProhibitedIcon(parent, layoutOrder)
    local holder = self:Create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = layoutOrder or -1,
        Visible = false,

        Parent = parent,
    })

    local banIcon = icons.find("ban", "lucide")
    if banIcon then
        self:Create("ImageLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = banIcon.Image,

            Parent = holder,
        }, { ImageColor3 = "PlaceholderColor" })

        return holder
    end

    local ring = self:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = holder,
    })
    self:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
    self:Create("UIStroke", {
        Thickness = 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,

        Parent = ring,
    }, { Color = "PlaceholderColor" })

    self:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 2),
        Rotation = 45,
        BorderSizePixel = 0,

        Parent = holder,
    }, { BackgroundColor3 = "PlaceholderColor" })

    return holder
end

-- Dim title/icon, show/hide the padlock built above (and the "no entry" glyph, if the caller
-- built one too). `element` needs .locked, .title, .lockIcon, and optionally .iconLabel/
-- .prohibitedIcon. Doesn't touch input - callers guard their own click/drag handlers with
-- `if element.locked then return end`.
function Window:_applyLockedVisual(element, animate)
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local set = function(instance, props)
        if not instance then
            return
        end
        if animate then
            variables.tweenService:Create(instance, info, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end

    if element.lockIcon then
        element.lockIcon.Visible = true
    end
    if element.prohibitedIcon then
        element.prohibitedIcon.Visible = element.locked
    end
    set(element.title, { TextTransparency = if element.locked then 0.6 else 0 })
    if element.iconLabel then
        set(element.iconLabel, { ImageTransparency = if element.locked then 0.6 else 0 })
    end
    if not element.locked and element.lockIcon then
        task.delay(if animate then info.Time else 0, function()
            if not element.locked and element.lockIcon then
                element.lockIcon.Visible = false
            end
        end)
    end
end

-- Shared scaffold for the compact button/toggle row: the white body + stroke, the fill flex
-- so it shares the row width, and the click surface. Callers add their own padding + content
-- into the returned interact, keeping the two elements identical where they should be.
function Window:_buildCompactRow(host, name, interactZIndex)
    local main = self:Create("Frame", {
        Name = name,
        Size = UDim2.fromOffset(0, compactRowHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        ClipsDescendants = true, -- overflow guard
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = host.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    local stroke = self:StyleElementBody(main)

    -- share the row width (grow + shrink)
    self:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Fill,
        Parent = main,
    })

    -- main flows + fills the interact
    self:Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,

        Parent = main,
    })

    -- clickable wrapper, doubles as the hover-brighten surface
    local interact = self:Create("TextButton", {
        Text = "",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, -- hover fades to 0.97
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, compactRowHeight),
        BorderSizePixel = 0,
        TextTransparency = 1,
        ZIndex = interactZIndex or 1,

        Parent = main,
    })

    self:Create("UICorner", {
        Parent = interact,
    }, { CornerRadius = "ElementCornerRadius" })

    return main, stroke, interact
end

-- Like StyleElementBody but with a gradient stroke (subtle sheen) instead of a flat one.
-- White stroke base tinted by the ElementStrokeGradient. Used by the dropdown's header +
-- options cards. Returns the stroke.
function Window:StyleElementPanel(frame)
    self:Create("UIGradient", {
        Rotation = 270,

        Parent = frame,
    }, { Color = "ElementGradient" })

    self:Create("UICorner", {
        Parent = frame,
    }, { CornerRadius = "ElementCornerRadius" })

    local stroke = self:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- In = ElementStrokeTransparency

        Parent = frame,
    })

    self:Create("UIGradient", {
        Rotation = 270,

        Parent = stroke,
    }, { Color = "ElementStrokeGradient" })

    return stroke
end

-- Reveal a single instance: instantly set props when animate is false, else tween them with info.
function Window:_reveal(instance, props, animate, info)
    if not instance then
        return
    end
    if animate then
        variables.tweenService:Create(instance, info or revealInfo, props):Play()
    else
        for property, value in props do
            instance[property] = value
        end
    end
end

-- Reveal the parts every non-Section element shares (fill/stroke/title/icon/descriptor).
function Window:_revealCommon(element, animate)
    -- locked-aware: an element flagged .locked dims to the same 0.6 _applyLockedVisual uses,
    -- computed as this call's own target instead of a second tween chasing it in afterward -
    -- two simultaneous tweens on the same property fight each other frame to frame instead of
    -- one cleanly winning (the same class of bug as the tab indicator's own tween race), which
    -- is exactly what calling _applyLocked right after this used to do.
    local titleTransparency = if element.locked then 0.6 else 0
    self:_reveal(element.stroke, { Transparency = self.theme.ElementStrokeTransparency }, animate)
    self:_reveal(element.title, { TextTransparency = titleTransparency }, animate)
    self:_reveal(element.main, { BackgroundTransparency = self.theme.ElementTransparency or 0 }, animate)
    if element.iconLabel then
        self:_reveal(element.iconLabel, { ImageTransparency = titleTransparency }, animate)
    end
    if element.descriptor then
        self:_reveal(element.descriptor.titleLabel, { TextTransparency = 0.7 }, animate)
    end
end

-- The reverse of _revealCommon: fade the same shared parts back out to fully transparent.
function Window:_hideCommon(element, animate)
    self:_reveal(element.stroke, { Transparency = 1 }, animate)
    self:_reveal(element.title, { TextTransparency = 1 }, animate)
    self:_reveal(element.main, { BackgroundTransparency = 1 }, animate)
    if element.iconLabel then
        self:_reveal(element.iconLabel, { ImageTransparency = 1 }, animate)
    end
    if element.descriptor then
        self:_reveal(element.descriptor.titleLabel, { TextTransparency = 1 }, animate)
    end
end

-- The rect main morphs into once collapsed: the same top-centre spot the old standalone
-- restore pill used to sit at, translated into main's own centre-anchored space (main never
-- changes AnchorPoint, so its Position always addresses its centre, not its top edge).
function Window:_collapsedRect()
    local size = collapsedSize
    local home = UDim2.new(
        collapsedTop.X.Scale,
        collapsedTop.X.Offset,
        collapsedTop.Y.Scale,
        collapsedTop.Y.Offset + size.Y.Offset / 2
    )
    return home, size
end

-- true only when the window is fully shown and idle. hover/press animations gate on this so
-- nothing lights up mid show/hide/minimise reveal, while elements are still tweening in.
function Window:_interactive()
    return not self.animating and not self.hidden
end

-- Touch-primary heuristic: TouchEnabled with no mouse says "phone/tablet" more reliably than
-- TouchEnabled alone (a touch-screen laptop has both). Exposed publicly so a dev's own script
-- can branch on it too, not just the library's own resize-grip scaling (see mobileHitScale).
function Window:IsMobile(): boolean
    local uis = variables.userInputService
    return uis.TouchEnabled and not uis.MouseEnabled
end

-- Detects a frozen render thread: RenderStepped stops firing while Heartbeat keeps ticking (a
-- stalled render is often invisible to a plain "is the game still running" check, since
-- physics/server-driven Heartbeat can carry on fine while the screen itself is stuck). Fires
-- `callback(secondsSinceLastRender)` once RenderStepped has been silent for longer than
-- thresholdSeconds (default 5) while the window is actually focused - a legitimately unfocused
-- client (alt-tabbed, minimized) throttles RenderStepped on its own and that's not a freeze, so
-- it's exempted rather than tripping a false positive. This only detects; it never acts on its
-- own (no forced rejoin, no teleport) - what to do about a freeze (log it, notify the player,
-- attempt a reconnect) is entirely the caller's call.
function Window:OnRenderFreeze(callback, thresholdSeconds)
    thresholdSeconds = thresholdSeconds or 5
    local lastRender = os.clock()
    local focused = true
    local tripped = false

    self:Connect(variables.userInputService.WindowFocused, function()
        focused = true
    end)
    self:Connect(variables.userInputService.WindowFocusReleased, function()
        focused = false
    end)
    self:Connect(variables.runService.RenderStepped, function()
        lastRender = os.clock()
        tripped = false
    end)
    self:Connect(variables.runService.Heartbeat, function()
        if not focused then
            lastRender = os.clock() -- dont accumulate frozen-time while legitimately unfocused
            return
        end
        local frozenFor = os.clock() - lastRender
        if frozenFor >= thresholdSeconds and not tripped then
            tripped = true
            task.spawn(callback, frozenFor)
        end
    end)
end

-- true when the window is up and not mid reveal or hide. action icons settle on this rather
-- than _interactive: minimise animates too, but it never repaints the icons the way show and
-- hide do, so an icon settling during it has nothing to fight and would otherwise stay lit.
function Window:_settled()
    return not self.hidden and not self._revealing
end

function Window:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.connections, connection)
    return connection
end

-- Like Connect, but also files the connection on the element that owns it, so Tab:Remove can
-- tear an element's connections down instead of leaving them tracked until Unload. Every
-- persistent element connection funnels through here.
function Window:ConnectFor(owner, signal, callback)
    local connection = self:Connect(signal, callback)
    owner.connections = owner.connections or {}
    table.insert(owner.connections, connection)
    return connection
end

-- Disconnect a connection from Window:Connect and drop it from the tracked list.
-- Transient UI (dropdown popups, removed tabs) calls this so open/close churn doesnt
-- pile up dead entries that only get cleared at Unload.
function Window:Disconnect(connection)
    if not connection then
        return
    end
    local index = table.find(self.connections, connection)
    if index then
        table.remove(self.connections, index)
    end
    connection:Disconnect()
end

-- Destroy a subtree and forget every tracked instance inside it. Transient elements
-- (notifications) use this instead of a bare Destroy so self.instances doesnt grow
-- for the whole session.
function Window:DestroySubtree(root)
    if not root then
        return
    end

    local inSubtree = { [root] = true }
    for _, descendant in root:GetDescendants() do
        inSubtree[descendant] = true
    end
    for i = #self.instances, 1, -1 do
        local instance = self.instances[i]
        if inSubtree[instance] then
            table.remove(self.instances, i)
            self.themeProperties[instance] = nil
            self.localeProperties[instance] = nil
        end
    end

    root:Destroy()
end

function Window:Unload()
    -- Run every OnUnload callback first, while every instance is still alive and self.unloaded is
    -- still false - a callback that reads window state (a toggle's own .value, an element still
    -- on screen) sees it exactly as it was the moment Unload was called. pcall'd individually so
    -- one throwing dev callback can't stop the rest from running or strand the real teardown below.
    for _, callback in self._unloadCallbacks do
        local ok, err = pcall(callback)
        if not ok then
            log.warn("Rayfield: an OnUnload callback errored - " .. tostring(err))
        end
    end

    self.unloaded = true
    -- drop our own slot in the singleton registry, but only if it's still us - a newer window
    -- with the same name may have already replaced us there (that's what called us in the first
    -- place), and we mustn't clobber its entry.
    local registry = windowRegistry()
    if registry[self.name] == self then
        registry[self.name] = nil
    end
    if self._localeRefresh then
        locale.removeListener(self._localeRefresh)
        self._localeRefresh = nil
    end
    -- Acrylic is a global Lighting effect, not scoped to this window's own ScreenGui - leaving
    -- it on here would leak a permanent blur into the game with nothing left to ever turn it
    -- back off.
    if self.acrylicEnabled then
        acrylic.setEnabled(false)
    end
    -- drop our effects and release the gui they hung on, but leave the enabled flag alone -
    -- another window may still be open and haptics arent ours to switch off for it
    hapticEngine.teardown()
    hapticEngine.releaseContainer(self.screenGui)
    soundEngine.releaseContainer(self.screenGui)
    if self._liveTween then
        self._liveTween:Cancel() -- unparks the LiveAnimation loop before we destroy the gradient
        self._liveTween = nil
    end
    for i = #self.connections, 1, -1 do
        self.connections[i]:Disconnect()
    end
    for i = #self.instances, 1, -1 do
        self.instances[i]:Destroy()
    end

    -- destroying isnt forgetting: a hub that loads and unloads repeatedly would keep the whole
    -- dead instance graph reachable through the handle it still holds. DestroySubtree already
    -- clears as it goes, so match it here.
    table.clear(self.connections)
    table.clear(self.instances)
    table.clear(self.themeProperties)
    table.clear(self.localeProperties)
    table.clear(self.controls)
    table.clear(self.tabs)
end

-- Register cleanup for your own state that Window:Unload has no way to know about on its own -
-- stopping a loop's flag, putting the character back at spawn, dropping a highlight, whatever a
-- feature needs undone. Fires synchronously, in registration order, right as Unload starts -
-- before self.unloaded flips true and before any instance is torn down, so a callback can still
-- safely read anything (a toggle's own .value, an element still on screen) exactly as it was the
-- moment Unload was called. A throwing callback is caught and logged, not left to strand the
-- real teardown that follows it.
function Window:OnUnload(callback: () -> ())
    table.insert(self._unloadCallbacks, callback)
end

return Window

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Window.new lives here; every Window:X method lives in windowMethods.luau or windowExtra.luau
-- instead, split off once this file alone tripped Roblox's 200,000 character Source limit on a
-- ModuleScript (see windowCore.luau's own header comment for the full story and why a shared
-- core module, not a circular require, is what stitches the three back into one class). This
-- file requiring the other two at its own tail - after Window.new is fully defined, right before
-- returning - is what guarantees every method is attached before anyone holding the returned
-- Window table can ever call .new on it.

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
local squircle = core.squircle
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


function Window.new(properties)
    properties = if typeof(properties) == "table" then properties else {}

    -- Localization is global to the running UI: a dev translator (if any) and the active locale
    -- live on the locale module. Default the locale to the player's language unless the dev pins
    -- one. Set before any label is built so the first render is already in the right language.
    if properties.translations or properties.Translations then
        locale.register(properties.translations or properties.Translations)
    end
    if properties.translator or properties.Translator then
        locale.translator = properties.translator or properties.Translator
    end
    -- autoTranslate: live machine translation for every dev string, zero manual table-writing
    -- (see locale.resolve's own comment on where this sits in the resolution order). Only ever
    -- turns it ON here, same as translator above - a second window built without the property
    -- shouldn't silently disable what an earlier one already opted into.
    do
        local auto = properties.autoTranslate
        if auto == nil then
            auto = properties.AutoTranslate
        end
        if auto ~= nil then
            locale.autoTranslate = auto and true or false
        end
    end
    locale.setActive(properties.locale or properties.Locale or locale.detect())

    -- a dev can pick the stand-in font shown while the brand font downloads in secure mode; set it
    -- before resolveTheme below so the theme's brandFont picks it up
    local fallbackFont = properties.fallbackFont or properties.FallbackFont
    if fallbackFont then
        variables.setFallbackFont(fallbackFont)
    end

    local customSize = resolveCustomSize(properties.size or properties.Size)

    local self = setmetatable({
        name = properties.name or properties.Name or "Rayfield Window",
        subheading = properties.subtitle or properties.Subtitle,
        size = fitWindowSize(customSize),
        customSize = customSize,
        -- Devlog 8 corner grip: the dev-supplied/built-in size from construction, kept untouched
        -- by any later resize-grip drag so double-clicking the grip always has the *original*
        -- target to snap back to, not whatever the most recent drag happened to land on.
        defaultSize = customSize,
        fontChoice = "auto",
        windowOpacity = 1, -- Devlog 7 "window transparency": 1 = fully opaque (default)
        acrylicEnabled = false,
        instances = {},
        connections = {},

        icon = properties.icon or properties.Icon,
        showName = properties.showName or properties.ShowName or "Rayfield",
        showIcon = properties.showIcon or properties.ShowIcon or constants.icons.rayfield,

        -- "Loading animation": a dev-configured splash (icon/title/optional cycling tip text)
        -- played once on the very first Show(), before the window's own staged content reveal.
        -- Dev-only surface by design - present only if the dev opts in by passing `loading` at
        -- all, so the player's Settings toggle (added below, same conditional) only exists when
        -- there's actually something for it to turn on or off.
        loading = (function()
            local cfg = properties.loading or properties.Loading
            if not cfg then
                return nil
            end
            return {
                enabled = cfg.enabled ~= false and cfg.Enabled ~= false,
                icon = cfg.icon or cfg.Icon,
                title = cfg.title or cfg.Title,
                tips = cfg.tips or cfg.Tips or {},
                tipHoldTime = cfg.tipHoldTime or cfg.TipHoldTime or 0.9,
                duration = cfg.duration or cfg.Duration or 1.1,
            }
        end)(),

        -- Guided onboarding tour: a dev-supplied sequence of { target, title, description } steps
        -- (target is whatever CreateToggle/CreateButton/etc itself returned), played once
        -- automatically on the very first Show() - see _firstShow's own tour block - and
        -- re-playable from Settings. Dev-only surface, same reasoning as loading above: only
        -- present (and only shown in Settings) if the dev actually passed one.
        tourSteps = properties.tour or properties.Tour,

        -- Escape closes the window, on top of the normal toggle key - dev-set at CreateWindow
        -- (Fluent's own EnableEscapeToClose), not a player Settings toggle, since it's a fixed
        -- convention a dev opts an experience into rather than a per-player preference.
        escapeToClose = properties.escapeToClose or properties.EscapeToClose or false,

        themeProperties = {},
        localeProperties = {},
        tabs = {},
        tags = {},
        selectedTab = nil,
        theme = resolveTheme(properties.theme or properties.Theme),

        controls = {},

        configuration = (function()
            local cfg = properties.configuration or properties.Configuration
            if not cfg then
                return {}
            end
            return {
                autoSave = cfg.autoSave or cfg.AutoSave,
                autoLoad = cfg.autoLoad or cfg.AutoLoad,
                fileName = cfg.fileName or cfg.FileName,
                customFolder = cfg.customFolder or cfg.CustomFolder,
                ignoreFlags = cfg.ignoreFlags or cfg.IgnoreFlags,
                scopeByPlace = cfg.scopeByPlace or cfg.ScopeByPlace,
            }
        end)(),
    }, Window)

    -- Direct per-window visual overrides (see WindowProps' own comment on each) - applied by
    -- mutating self.theme itself, right after it's resolved and before anything reads it to
    -- build, rather than poking instance properties after the fact. CornerRoundness/SurfaceStroke
    -- Color/WindowColor/ShadowColor are all already theme-bound properties every relevant
    -- instance picks up naturally through the normal binding path this way - no separate
    -- override step needed for those four. The rest (gradient rotation, border/shadow thickness,
    -- whether the border shows at all) aren't theme fields, just plain literals at their own
    -- construction sites below - stashed on self here so those sites can read them instead of a
    -- hardcoded number.
    --
    -- Stashed as fields, not just applied once here, so a later Window:ChangeTheme() call
    -- (including the player's own Settings "Color theme" dropdown) can re-apply them after it
    -- re-resolves self.theme from scratch - see Window:_applyThemeOverrides (windowMethods.luau),
    -- called right below and again from ChangeTheme itself. Previously documented as a known
    -- limitation that silently dropped these on any theme swap; this is the actual fix.
    self._cornerRadiusOverride = properties.cornerRadius or properties.CornerRadius
    self._borderColorOverride = properties.borderColor or properties.BorderColor
    self._gradientColorOverride = if (properties.gradient or properties.Gradient)
        then (properties.gradientColorSequence or properties.GradientColorSequence)
        else nil
    self._shadowColorOverride = properties.shadowColor or properties.ShadowColor
    self:_applyThemeOverrides()

    self._borderThickness = properties.borderThickness or properties.BorderThickness
    self._gradientRotation = properties.gradientRotation or properties.GradientRotation
    self._shadowBlur = properties.shadowThickness or properties.ShadowThickness
    self._shadowTransparency = properties.shadowTransparency or properties.ShadowTransparency
    self._rainbowBorder = properties.rainbowBorder or properties.RainbowBorder or false
    self._rainbowBorderSpeed = properties.rainbowBorderSpeed or properties.RainbowBorderSpeed or 0.14
    if self._rainbowBorder then
        self._showBorder = true
    end
    -- Squircle corners: the window body's own fill switches from a plain Frame+UICorner (a
    -- circular arc) to an image-based squircle (see utility/squircle.luau for what that actually
    -- means and why it can't just be an Instance property). Opt-in and scoped to the window body
    -- only for now, not every rounded corner in the library - see squircle.luau's own header for
    -- the reused-asset story, and self.main's construction below for what combining this with an
    -- explicit border color doesn't handle yet (the stroke still outlines a plain rounded rect,
    -- not the squircle curve).
    self._squircleCorners = properties.squircleCorners or properties.SquircleCorners or false
    -- The Settings tab's own "Session" card (player name/players online/uptime/FPS, refreshed
    -- every second - see _buildSessionDashboard) is on by default, but a hub that already shows
    -- most of that on its own Dashboard tab ends up with the same numbers twice, one click apart.
    self._showSessionDashboard = if properties.sessionDashboard ~= nil
        then properties.sessionDashboard
        elseif properties.SessionDashboard ~= nil then properties.SessionDashboard
        else true
    -- A consumer script that bakes self.theme.AccentColor into its own RichText (e.g. accentTag
    -- helpers like the hub template's own) has no way to hear about a later Settings > Color
    -- theme swap - ChangeTheme retints every Rayfield-built element on its own, but a plain
    -- TextLabel a dev built by hand with a literal <font color="..."> baked into its Text string
    -- is invisible to that. OnThemeChanged(callback) - see windowMethods.luau - gives it a hook to
    -- rebuild that text instead.
    self._themeChangedCallbacks = {}
    -- A consumer script that wants to persist a player's dragged sidebar width across sessions
    -- (see Window:RegisterFlag in windowExtra.luau) needs to hear about every real width change,
    -- not just the ones it made itself - OnSidebarWidthChanged (windowMethods.luau) is that hook.
    -- Fired from _applySidebarWidth itself so drag, SetSidebarWidth, and CreateTab's own
    -- re-application all reach it through the one funnel.
    self._sidebarWidthChangedCallbacks = {}
    -- Window:Unload() already tears down every instance/connection it owns on its own - this is
    -- for the part it has no way to know about: a consumer script's own state that needs
    -- resetting (stop a loop's flag, put the character back at spawn, drop a highlight) rather
    -- than just disconnected. Fired synchronously, before anything is torn down, so a callback
    -- can still safely read/use every instance the window built.
    self._unloadCallbacks = {}
    -- Settings > General toggles a hub can hide when it wants that behaviour pinned rather than
    -- player-adjustable (e.g. a "Welcome toast" a dev always wants on, or "Haptics"/"Sound
    -- Effects" it never wants on at all) - hiding the toggle doesn't itself change
    -- self.settings.X's own default, only whether a player can flip it from here.
    self._showWelcomeToastToggle = if properties.showWelcomeToastToggle ~= nil
        then properties.showWelcomeToastToggle
        elseif properties.ShowWelcomeToastToggle ~= nil then properties.ShowWelcomeToastToggle
        else true
    self._showHapticsToggle = if properties.showHapticsToggle ~= nil
        then properties.showHapticsToggle
        elseif properties.ShowHapticsToggle ~= nil then properties.ShowHapticsToggle
        else true
    self._showSoundEffectsToggle = if properties.showSoundEffectsToggle ~= nil
        then properties.showSoundEffectsToggle
        elseif properties.ShowSoundEffectsToggle ~= nil then properties.ShowSoundEffectsToggle
        else true
    self._showLoadingAnimationToggle = if properties.showLoadingAnimationToggle ~= nil
        then properties.showLoadingAnimationToggle
        elseif properties.ShowLoadingAnimationToggle ~= nil then properties.ShowLoadingAnimationToggle
        else true
    -- Opt-in (default false, unlike the toggles above) since this one is destructive rather
    -- than a preference - a "Destroy UI" hold-button in Settings that fully Unload()s the
    -- window. Off unless a dev explicitly wants players able to tear the whole thing down
    -- themselves (e.g. a hub that would rather a player fully close it than leave it running
    -- half-configured).
    self._showUnloadButton = properties.showUnloadButton or properties.ShowUnloadButton or false
    self.notifySide = properties.notifySide or properties.NotifySide or "Right"
    -- "Top" (default, everything this file always did) or "Sidebar" - a vertical tab list down
    -- the left edge instead of the horizontal strip under the header, for a section list too
    -- long to read comfortably as a single scrolling row of pills. Dev-only, set once at
    -- CreateWindow (Fluent's own TabsMode) - not a runtime/player Settings toggle, since
    -- switching layout live would mean re-deriving every position below from scratch anyway.
    self.tabsMode = properties.tabsMode or properties.TabsMode or "Top"
    -- mobileHitScale: multiplies a handful of touch-target sizes (the window's own resize grip -
    -- see resize.luau's own gripSize - and the sidebar's resize grip below) when Window:IsMobile()
    -- reads true. Scoped to hit areas specifically rather than a full mobile/desktop pass over
    -- every button's size across the whole library - a much bigger retrofit than this pass.
    self.mobileHitScale = properties.mobileHitScale or properties.MobileHitScale or 1.4

    -- Public, always-live view of every saved control, keyed by flag. Reading returns the
    -- control's current value; assigning routes through its Set so the UI and callback fire.
    self.Flags = setmetatable({}, {
        __index = function(_, flag)
            local control = self.controls[flag]
            return control and control.value
        end,
        __newindex = function(_, flag, value)
            local control = self.controls[flag]
            if not control then
                log.warn("Rayfield: no flag '" .. tostring(flag) .. "' to set")
                return
            end
            control:Set(value)
        end,
        __iter = function()
            local flag
            return function()
                local control
                flag, control = next(self.controls, flag)
                if flag then
                    return flag, control.value
                end
                return nil
            end
        end,
    })

    -- Auto-unload a same-named window left over from an earlier run of this script (or an
    -- earlier reload) before building this one - see windowRegistry's own comment above. A dev
    -- who genuinely wants two windows open at once just gives them different names; nothing here
    -- fires unless a name collides with one still alive.
    do
        local registry = windowRegistry()
        local previous = registry[self.name]
        if previous and previous ~= self and previous.Unload then
            pcall(previous.Unload, previous)
        end
        registry[self.name] = self
    end

    -- A live translation lands async, well after resolve() already had to answer with a
    -- fallback (see locale.resolve's own comment) - this is how this window hears about it and
    -- re-applies (SetLocale already re-resolves every localeProperties entry in place, so a
    -- landed translation upgrades the exact labels showing the fallback, with no rebuild).
    -- Deregistered in Unload so a dead window's closure doesn't linger in locale's listener list.
    self._localeRefresh = function()
        if not self.unloaded then
            self:SetLocale(locale.current)
        end
    end
    locale.addListener(self._localeRefresh)

    -- Rayfield Gen2 Screen
    self.screenGui = self:Create("ScreenGui", {
        Name = variables.httpService:GenerateGUID(false),
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        Enabled = true,
        DisplayOrder = constants.displayOrder.window,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
        -- Roblox auto-translates plain Text/PlaceholderText on any descendant that hasn't set
        -- its own AutoLocalize, using its own generic crowd-sourced word list, entirely outside
        -- Rayfield's own locale system - live-caught this turning "Delete"/"Haptics" into
        -- "Excluir"/"Vibrar ao tocar" on a pt-BR client with nothing in locale.luau's own tables
        -- asking for that. AutoLocalize is inherited down the tree, so false here on the root
        -- covers every descendant that doesn't explicitly override it - which is everything
        -- Rayfield builds. locale.luau stays the only thing that ever translates this UI.
        AutoLocalize = false,

        Parent = variables.guiContainer,
    })

    -- Window
    self.main = self:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Name = self.name,
        ZIndex = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        -- Devlog 7 fix: without this, a plain Frame's default Active (false) means it stops
        -- blocking/capturing input in its own bounds the moment BackgroundTransparency actually
        -- reaches 1 - which SetTransparency(100) does on purpose now that this exists. Explicit
        -- Active = true keeps the window (and everything inside it) clickable at any
        -- transparency, glass or not.
        Active = true,
        -- Animations
        Size = UDim2.fromOffset((self.size.X.Offset - 50), 0),
        BackgroundTransparency = 1, -- In = 0
        Visible = false, -- In == true

        Parent = self.screenGui,
    })

    self.drag = require(script.Parent.drag).new(self)

    -- Squircle mode: no UICorner at all on self.main - it stays permanently transparent (see
    -- _mainVisual below, which is what every reveal/opacity call site now goes through instead
    -- of touching self.main.BackgroundTransparency directly) and a separate image-backed frame
    -- carries the actual fill, rounded by utility/squircle.luau instead of a circular arc.
    if self._squircleCorners then
        self.mainSquircle = self:Create("ImageLabel", {
            Name = "Squircle",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ImageColor3 = Color3.fromRGB(255, 255, 255),
            ZIndex = 0, -- behind every real child of self.main, which all default to ZIndex 1+

            ImageTransparency = 1, -- In = 0, same reveal convention self.main's fill used to carry

            Parent = self.main,
        })
        squircle.apply(self.mainSquircle, self.theme.CornerRoundness.Offset)

        -- Border in squircle mode: a plain UIStroke (below) can only ever draw a straight-edged
        -- rectangle - it has no way to follow an image-based curve - which previously left a
        -- sharp-cornered outline sitting visibly outside this fill's own rounded corners whenever
        -- a dev combined squircleCorners with borderColor (documented as unhandled, never fixed
        -- until now). Fixed the same way a stroke gets faked behind any image-masked shape: a
        -- second copy of the exact same squircle image, tinted with the border colour, sized
        -- outward by the stroke thickness on every side and sitting behind the real fill - only
        -- the thin ring that pokes out past the fill's own edge ends up visible.
        if self._showBorder then
            local thickness = self._borderThickness or 1
            self.mainSquircleStroke = self:Create("ImageLabel", {
                Name = "SquircleStroke",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, thickness * 2, 1, thickness * 2),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = -1, -- behind the fill (ZIndex 0 on mainSquircle above)

                Parent = self.main,
            }, { ImageColor3 = "SurfaceStroke" })
            squircle.apply(self.mainSquircleStroke, self.theme.CornerRoundness.Offset + thickness)
        end
    else
        self.windowCorner = self:Create("UICorner", {

            Parent = self.main,
        }, { CornerRadius = "CornerRoundness" })
    end

    self.windowStroke = self:Create("UIStroke", {
        Thickness = self._borderThickness or 1,
        -- Live-caught reading this file: nothing else ever tweens this Transparency toward the
        -- "In = 0.95" the old comment here promised - it's never referenced anywhere past this
        -- one construction. Shown outright (0) when a dev explicitly asked for a border at all
        -- (self._showBorder, set alongside borderColor above) and squircle mode isn't drawing its
        -- own border instead (mainSquircleStroke above); otherwise left exactly as before,
        -- permanently at 1 (invisible), so this fix doesn't change anything for a window that
        -- never opted in.
        Transparency = if self._showBorder and not self._squircleCorners then 0 else 1,

        Parent = self.main,
    }, { Color = "SurfaceStroke" })

    -- Rainbow border: continuously cycles the stroke's own Color through the hue wheel instead
    -- of the themed SurfaceStroke it'd otherwise ride. Plain RenderStepped read/write, not a
    -- tween - there's no fixed destination color to tween toward, just a clock-driven hue that
    -- never stops moving. self.windowStroke.Parent guards the loop the same way shimmerlabel.luau's
    -- own shimmer loop guards on its gradient's Parent - it winds down on its own once the
    -- window's torn down, nothing else has to explicitly stop it.
    if self._rainbowBorder then
        self:Connect(variables.runService.RenderStepped, function()
            if not self.windowStroke.Parent then
                return
            end
            local hue = (os.clock() * self._rainbowBorderSpeed) % 1
            self.windowStroke.Color = Color3.fromHSV(hue, 1, 1)
        end)
    end

    self.windowGradient = self:Create("UIGradient", {
        Rotation = self._gradientRotation or 270,
        Offset = Vector2.new(0, -0.1),

        Parent = self.mainSquircle or self.main,
    }, { Color = { "WindowColor", functions.toColorSequence } })

    -- Bottom fade - gradient overlay so elements scroll out softly at the window's base
    self.bottomFade = self:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, -0.093, 100),
        ZIndex = constants.zIndex.bottomFade,

        -- Animation
        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })

    self:Create("UICorner", {
        Parent = self.bottomFade,
    }, { CornerRadius = "CornerRoundness" })

    self.bottomFadeGradient = self:Create("UIGradient", {
        Rotation = 270,
        Offset = Vector2.new(0, 0.2),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.4414, 0),
            NumberSequenceKeypoint.new(0.7007, 0.631),
            NumberSequenceKeypoint.new(1, 1),
        }),

        Parent = self.bottomFade,
    }, {
        -- Track the window's colour at its base (keypoint 0 sits at the bottom under Rotation 270)
        -- so elements dissolve into the window instead of a fixed dark smudge on light themes.
        Color = {
            "WindowColor",
            function(color)
                return ColorSequence.new(functions.toColorSequence(color).Keypoints[1].Value)
            end,
        },
    })

    -- Top fade - same softening, mirrored: content scrolling up under the tab dock got a hard
    -- ClipsDescendants edge with nothing to ease it, while the bottom of that same list already
    -- dissolved gently into the window. Sits right at the tab dock's own bottom edge (65+38=103)
    -- rather than at main's literal top edge, since it's the content clip that needs softening,
    -- not the header/dock above it - no UICorner here, unlike bottomFade: this frame isn't
    -- sitting on any of main's own rounded corners.
    --
    -- First attempt copied bottomFade's Size formula wholesale (1, 0, -0.093, 100) without
    -- noticing the -0.093 *scale* term was there to make bottomFade shrink from the anchored
    -- bottom edge, not something to carry over - on a top anchor it added instead of subtracting,
    -- so this rendered at ~160px tall instead of a reasonable transition strip, eating a big
    -- chunk of actual content space. Second attempt overcorrected the other way - shrank it to
    -- 24px *and* swapped in a plain two-point linear fade, which at that size read as a visible
    -- cut/seam rather than a dissolve (that turned out to also be a colour mismatch against
    -- tabDock, not just size/curve - see topFadeGradient's own comment). 34px with
    -- bottomFadeGradient's own eased keypoint shape is the settled middle ground - small enough
    -- not to eat the content area, tall enough for that curve to still read as gradual.
    -- Sidebar mode has no such seam to hide in the first place - its dock runs down the left
    -- edge, not across the top, so content never scrolls "under" it the way Top mode's
    -- horizontal strip requires softening for. Left unconditional, this rendered anyway: a flat
    -- full-width dark band frozen at y=103 (Top mode's dock-to-content handoff point) that in
    -- Sidebar mode just cuts across the sidebar and content pane alike with nothing to justify
    -- it - the exact "bgl that's supposed to fade away doesn't fade away over here" seam the
    -- Sidebar layout was live-reported to show. Sized to nothing rather than skipped outright so
    -- every other reference to self.topFade/topFadeGradient below still resolves to a real
    -- (just invisible and zero-size) instance instead of nil.
    local isSidebarMode = self.tabsMode == "Sidebar"

    self.topFade = self:Create("Frame", {
        -- Flat colour, same literal RGB as tabDock (24,24,24) - not a themed WindowColor, and
        -- not a gradient into one either (that was tried and looked worse: a colour ramp toward
        -- the theme reads as "the fade is the wrong colour" right where it meets the dock, since
        -- the dock itself never ramps - it's one flat colour throughout, transparency aside).
        -- Matching that flat colour exactly and only ever varying transparency (see
        -- topFadeGradient) is what actually makes the seam disappear.
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0, 0, 0, 103),
        Size = if isSidebarMode then UDim2.new() else UDim2.new(1, 0, 0, 34),
        ZIndex = constants.zIndex.bottomFade,

        -- Animation
        BackgroundTransparency = 1, -- In = 0.2, matching tabDock's own resting transparency

        Parent = self.main,
    })

    self.topFadeGradient = self:Create("UIGradient", {
        -- Rotation 90 instead of bottomFade's 270 - flips which end keypoint 0 sits at (top
        -- instead of bottom), so this fades the *same* shape (opaque where it meets the header,
        -- transparent by the time it reaches open content) rather than reusing 270 and getting
        -- the mapping backwards for a frame anchored to the top instead of the bottom. Starts at
        -- 0.2, not fully opaque (0) - matches tabDock's own resting BackgroundTransparency, so
        -- the seam between them is two things at the same opacity, not a jump from "however
        -- opaque the dock reads" to "fully solid". Same eased Transparency shape as
        -- bottomFadeGradient past that point. Transparency only - no Color property here at all,
        -- see self.topFade's own comment on why a colour ramp made this look worse, not better.
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.4414, 0.2),
            NumberSequenceKeypoint.new(0.7007, 0.7),
            NumberSequenceKeypoint.new(1, 1),
        }),

        Parent = self.topFade,
    })

    -- Topbar
    self.topbar = self:Create("Frame", {

        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 66),
        -- Active so empty topbar space can catch input directly - tabs/actions/search sit on
        -- top and still get first pick, this is just the backdrop becoming a drag handle
        Active = true,

        Parent = self.main,
    })

    self.topContainer = self:Create("Frame", {
        Size = UDim2.new(0, 300, 0, 24),
        Position = UDim2.new(0, 25, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,

        Parent = self.topbar,
    })

    self.topContainerLayout = self:Create("UIListLayout", {
        Padding = UDim.new(0, 8),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.topContainer,
    })

    self.titleContainer = self:Create("Frame", {
        Size = UDim2.fromOffset(50, 24),
        Position = UDim2.new(0, 25, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        LayoutOrder = 1,

        Parent = self.topContainer,
    })

    self.titleContainerLayout = self:Create("UIListLayout", {
        Padding = UDim.new(0, 3),
        FillDirection = Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.titleContainer,
    })

    if self.name then
        self.title = self:Create("TextLabel", {
            -- Configurables
            Text = locale.t(self.name), -- window name

            FontFace = variables.brandFont(Enum.FontWeight.Medium),

            Size = UDim2.fromOffset(50, 20),
            AutomaticSize = Enum.AutomaticSize.X,

            BackgroundTransparency = 1,
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,

            -- Animations
            TextTransparency = 1, -- In = 0

            Parent = self.titleContainer,
        }, { FontFace = "Font", TextColor3 = "TitlingColor" })
    end

    if self.icon then
        self.topbarIcon = self:Create("ImageLabel", {
            Image = self.icon,

            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(32, 32),

            -- Animation
            ImageTransparency = 1, -- In = 0

            Parent = self.topContainer,
        }, { ImageColor3 = "TitlingColor" })
    end

    if self.subheading then
        self.subtitle = self:Create("TextLabel", {
            -- Configurables
            Text = locale.t(self.subheading), -- window name

            Size = UDim2.fromOffset(50, 12),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,

            -- Animations
            TextTransparency = 1, -- In = 0.7

            Parent = self.titleContainer,
        }, { TextColor3 = "TitlingColor", FontFace = "Font" })
    end

    self.tagContainer = self:Create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 25, 0.5, 0),
        Size = UDim2.fromOffset(50, 24),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Visible = false,

        Parent = self.topContainer,
    })

    self.tagContainerLayout = self:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.tagContainer,
    })

    -- Shadow (Transparency 1 here, tweened to self._shadowTransparency/0.6 on show)
    self.windowShadow = self:CreateGlow(self.main, "ShadowColor", self._shadowBlur or 20, 1)

    -- Elements Preparation

    -- Same isSidebar this whole block computes again further down for tabDock's own
    -- construction (self.elements is built first, before that local exists yet) - cheap to
    -- recompute rather than hoist the whole tabDock block above this one just to share it.
    local elementsSidebar = self.tabsMode == "Sidebar"
    -- Live-reported as too chunky at 160 alongside the corner-radius fix above (see tabDock's own
    -- UICorner comment) - trimmed for a slimmer rail, then found too tight on its own for a longer
    -- tab name ("Priority System" clipped) even after shrinking the sidebar row's own text/icon/
    -- padding (see tab.luau) - settled at 150. A live field now, not a local - the drag handle
    -- (see sidebarResize.luau) changes this at runtime, and both this block and tabDock's own
    -- construction further down read the one shared value instead of two literals that used to
    -- have to be kept in sync by hand.
    self.sidebarMinWidth = 60 -- icon-only rail: just wide enough for one centred icon + padding
    self.sidebarMaxWidth = 260
    -- Below this, a tab's own title label hides - matches sidebarMinWidth's own icon-only look
    -- kicking in before the text has any room left to sit next to the icon at all.
    self.sidebarCollapseWidth = 96
    -- Dev-settable starting width - properties.sidebarCollapsed opts straight into the icon-only
    -- rail from the first frame (a hub that wants that as its own default look, rather than a
    -- player having to drag down to it manually every session) without needing to know the exact
    -- pixel width that lands below sidebarCollapseWidth.
    self.sidebarWidth = if properties.sidebarWidth ~= nil then properties.sidebarWidth
        elseif properties.SidebarWidth ~= nil then properties.SidebarWidth
        elseif properties.sidebarCollapsed or properties.SidebarCollapsed then self.sidebarMinWidth
        else 150
    self.sidebarWidth = math.clamp(self.sidebarWidth, self.sidebarMinWidth, self.sidebarMaxWidth)

    -- Reserves 118px at the top for the header + tabDock (which itself ends at 65+38=103) - was
    -- 106, only a ~3px gap below the dock. Live-caught: harmless while the dock's own background
    -- was nearly invisible (StatBackground, since fixed - see tabDock's own comment), but once it
    -- reads as an actual dark card, that 3px gap wasn't enough to keep it from looking welded
    -- straight onto the first section's content below it. 118 opens the same ~15px breathing room
    -- other card-to-card spacing in this file uses.
    --
    -- Sidebar mode: content fills the remaining space to the *right* of the sidebar instead of
    -- everything below the header - top-left anchored fill rather than the bottom-anchored fill
    -- Top mode uses, since there's no separate horizontal tab strip height to reserve above it,
    -- just the header.
    self.elements = self:Create("Frame", {
        Size = if elementsSidebar
            then UDim2.new(1, -(self.sidebarWidth + 40), 1, -80)
            else UDim2.new(1, 0, 1, -118),
        Position = if elementsSidebar then UDim2.new(0, self.sidebarWidth + 30, 0, 70) else UDim2.fromScale(0.5, 1),
        AnchorPoint = if elementsSidebar then Vector2.new(0, 0) else Vector2.new(0.5, 1),
        BackgroundTransparency = 1,
        ClipsDescendants = true,

        Parent = self.main,
    })

    -- UI Scale setting: parented to self.elements specifically, not self.main - main itself
    -- (and everything measured directly off it: resize.luau's corner math, drag.luau's own
    -- follow target, _clampedPosition, _syncDragBar) stays completely unscaled, so none of that
    -- carefully-tuned physics has to become scale-aware. Only the tab content visually grows/
    -- shrinks. Deliberately NOT giving self.main its own ClipsDescendants to cap an oversized
    -- scale at the window's edge - the resize grip depends on main staying unclipped to straddle
    -- the corner (see resize.luau's own header comment: "main has no ClipsDescendants, so a
    -- child is free to render past its edge"), and clipping main would cut that grip in half.
    -- The slider's own range (see the Settings toggle below) is kept modest specifically so this
    -- never needs testing at a scale extreme enough for the overflow to matter in practice.
    self.contentScale = self:Create("UIScale", {
        Scale = 1,
        Parent = self.elements,
    })

    self.elementsLayout = self:Create("UIPageLayout", {
        Padding = UDim.new(0, 0),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        -- Tabs switch via the topbar only. Kill the built-in input so scrolling a long page
        -- (or a nudge on a controller) never flips to another tab under you.
        ScrollWheelInputEnabled = false,
        GamepadInputEnabled = false,
        TouchInputEnabled = false,

        EasingStyle = Enum.EasingStyle.Exponential,
        TweenTime = 0.4,

        Parent = self.elements,
    })

    -- Tabs Preparation
    -- Devlog 5: every tab now lives inside one dock surface, with a single pill
    -- (self.tabIndicator) sliding behind whichever one is selected instead of each tab pill
    -- fading its own background in/out. tabList itself is unchanged (still the horizontally
    -- scrolling UIListLayout row); the dock is just a background wrapper around it, and the
    -- indicator is a free sibling inside tabList that reads the selected tab's own resolved
    -- Position/AbsoluteSize rather than participating in the layout - the same "free-floating
    -- overlay" shape segmentedpicker.luau's sliding indicator already uses successfully.
    -- Sidebar mode: everything below branches on this rather than a separate code path per
    -- mode, so "Top" (the default every line here already served before this existed) reaches
    -- the exact same construction it always did whenever isSidebar is false.
    local isSidebar = self.tabsMode == "Sidebar"

    self.tabDock = self:Create("Frame", {
        Name = "TabDock",
        -- 20px total inset, same margin every other card-shaped element on the window uses -
        -- flush edge-to-edge (the original tabList's own sizing) read as glued to the window's
        -- corner once it had a visible fill behind it. Sidebar: a vertical strip down the left
        -- edge instead, from just under the header to just above the bottom fade - still this
        -- full height in Sidebar mode even though the *visible* card no longer is (see
        -- tabDockCard below): the resize grip is parented here and stays grabbable anywhere down
        -- the whole strip, not just alongside however many tabs happen to exist.
        Size = if isSidebar then UDim2.new(0, self.sidebarWidth, 1, -85) else UDim2.new(1, -40, 0, 38),
        Position = if isSidebar then UDim2.new(0, 20, 0, 65) else UDim2.new(0.5, 0, 0, 65),
        AnchorPoint = if isSidebar then Vector2.new(0, 0) else Vector2.new(0.5, 0),
        BorderSizePixel = 0,
        -- Without this, selecting (or scrolling to) a tab near either end of the strip let the
        -- indicator render fully outside the dock - even outside the window entirely, not just
        -- past the rounded corners. The un-clipped glow's own hard-edged blur line was the
        -- lesser problem; brought clipping back and shrank the glow instead (see CreateGlow
        -- call below) so its blur has less reach to clip in the first place.
        ClipsDescendants = true,
        -- same reasoning as self.main's own Active = true - stays clickable at any transparency
        Active = true,

        -- In Top mode this frame IS the visible card (background set directly below). In Sidebar
        -- mode it's a plain invisible structural container instead - see tabDockCard, a child
        -- sized to just the tab list's own content, for why: painting this fill directly on a
        -- frame that spans almost the full window height, live-reported as "puta espaço" once
        -- there were only 1-2 tabs, is exactly the dead-card look that was trying to fix.
        BackgroundTransparency = if isSidebar then 1 else 0.2,
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),

        Parent = self.main,
    })

    if isSidebar then
        -- The actual visible card, sized to the tab list's own content instead of the full
        -- height self.tabDock (its parent, purely structural now) still reserves for the resize
        -- grip. AutomaticSize.Y here hugs tabList below (also AutomaticSize.Y, hugging its own
        -- UIListLayout content) - no circularity: tabDock itself stays a fixed, non-automatic
        -- height, so nothing here ever measures itself against its own automatic size.
        self.tabDockCard = self:Create("Frame", {
            Name = "TabDockCard",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            -- Same live-caught opacity story as Top mode's own card - see this block's own
            -- original comment on why 0.2 (80% opaque), copied verbatim since the fix was about
            -- *where* the fill lives, not what value reads right against the theme.
            BackgroundColor3 = Color3.fromRGB(24, 24, 24),
            BackgroundTransparency = 0.2,

            Parent = self.tabDock,
        })
    end

    -- PillCornerRadius is UDim.new(1, 0) - scale-based, so it rounds to a full pill relative to
    -- whichever side is shorter. Top mode's dock is a short horizontal bar, so that's the right
    -- look. Sidebar mode's card is a narrow column instead - the same scale-1 radius rounds off
    -- of its (short) width, ballooning it into a giant capsule blob rather than a slim rounded
    -- panel. Use the window's ordinary fixed-offset corner there instead.
    self:Create("UICorner", {
        Parent = self.tabDockCard or self.tabDock,
    }, { CornerRadius = if isSidebar then "CornerRoundness" else "PillCornerRadius" })

    self.tabList = self:Create("ScrollingFrame", {
        Name = "Tabs",
        Active = true,
        -- Sidebar: hugs its own UIListLayout content (see tabListLayout below) instead of filling
        -- a parent - tabDockCard above then hugs *this*, which is what actually shrinks the
        -- visible card to just however many tabs exist rather than the dock's full reserved
        -- height.
        Size = if isSidebar then UDim2.new(1, 0, 0, 0) else UDim2.fromScale(1, 1),
        AutomaticSize = if isSidebar then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
        Position = if isSidebar then UDim2.new(0, 0, 0, 0) else UDim2.fromScale(0.5, 0.5),
        AnchorPoint = if isSidebar then Vector2.new(0, 0) else Vector2.new(0.5, 0.5),

        BackgroundTransparency = 1,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 0,
        ScrollBarImageTransparency = 1,
        -- Scrolling (and the AutomaticCanvasSize that made it track content) doesn't apply once
        -- Sidebar mode hugs full content height instead of a fixed viewport - Top mode is
        -- unchanged, still a fixed-height strip that can genuinely overflow and need to scroll.
        AutomaticCanvasSize = if isSidebar then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
        ScrollingDirection = if isSidebar then Enum.ScrollingDirection.Y else Enum.ScrollingDirection.X,

        Parent = self.tabDockCard or self.tabDock,
    })

    self.tabListLayout = self:Create("UIListLayout", {
        -- Devlog 7: tighter gap between tabs (was 4) - closer, more "Segmented Picker" feel
        Padding = UDim.new(0, 2),
        FillDirection = if isSidebar then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
        -- Center is right for Top mode - it centers a short horizontal row within the (equally
        -- short) dock. Sidebar's dock runs almost the full window height though, so the same
        -- Center vertically centered the *whole column* of tabs inside that tall space - live-
        -- reported as tabs "starting from the middle" instead of stacking down from the top the
        -- way every reference sidebar (Discord, VS Code, the reference framework's own) does.
        VerticalAlignment = if isSidebar then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.tabList,
    })

    self:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 5),
        PaddingRight = UDim.new(0, 5),

        Parent = self.tabList,
    })

    -- the sliding pill: a free Frame with no layout of its own (same idea as segmentedpicker's
    -- indicator / toggle's knob), created before any tab so creation order alone keeps it
    -- behind every tab's own icon/text/click surface with no explicit ZIndex needed anywhere.
    -- Parented to tabDock, NOT tabList: confirmed live that this executor never actually
    -- re-renders a plain (non-layout) child's AbsolutePosition after a later Position write
    -- once it's nested inside a ScrollingFrame - the property itself updates, AbsolutePosition
    -- (and the real on-screen render) just silently never follows it again after the first
    -- placement. tabDock is a plain Frame with no such quirk. Position is computed relative to
    -- tabDock's own AbsolutePosition instead of tabList's; since the indicator is no longer a
    -- scrolling-frame child itself, it also needs the CanvasPosition listener below to keep
    -- riding along when the strip is scrolled without a new tab being selected.
    self.tabIndicator = self:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 0),
        ZIndex = 1, -- explicit: each tab's own icon/text/click-catcher sits at ZIndex 2 to
        -- guarantee it stays above this now that they're in different branches of the tree

        Parent = self.tabDock,
    })
    self:Create("UICorner", {
        Parent = self.tabIndicator,
    }, { CornerRadius = "PillCornerRadius" })
    -- Always present: BackgroundColor3 alone can't render a multi-stop gradient, so
    -- tabAccentColor (Color3 or ColorSequence) always goes through this - a flat colour just
    -- becomes a uniform "gradient", indistinguishable from a plain fill.
    self.tabIndicatorGradient = self:Create("UIGradient", { Parent = self.tabIndicator })
    -- Smaller blur than most glows in this file on purpose: tabDock clips its children (see
    -- above) and the dock only has ~2px of margin above/below the pill, so a wide blur has
    -- nowhere to fade out before hitting that clip and would just redraw the same hard-edge
    -- line problem clipping was reintroduced to fix.
    self.tabIndicatorGlow = self:CreateGlow(self.tabIndicator, Color3.fromRGB(255, 255, 255), 6, 1)

    self.tabStyle = properties.tabStyle or properties.TabStyle or "accent"
    self.tabAccentColor = self.theme.AccentColor
    self.tabAccentGlow = if properties.tabAccentGlow ~= nil
        then properties.tabAccentGlow
        elseif properties.TabAccentGlow ~= nil then properties.TabAccentGlow
        else true

    -- The indicator only tracks the selected tab's AbsolutePosition at the moment it's told to
    -- (_updateTabIndicator) - now that it lives outside tabList (see above), it no longer rides
    -- along automatically as a real scrolling-frame child would when the strip is dragged to
    -- reveal tabs that don't fit. Re-snap (no animation - this is just following the scroll,
    -- not a new selection) whenever the visible window shifts.
    self:Connect(self.tabList:GetPropertyChangedSignal("CanvasPosition"), function()
        self:_updateTabIndicator(self.selectedTab, false)
    end)

    -- Sidebar-only drag handle on the dock's right edge - live-resizes the whole rail (see
    -- self:_applySidebarWidth) down to an icon-only strip or back up to full width, the same
    -- "drag the border" interaction resize.luau's own corner grip and drag.luau's own title bar
    -- already use elsewhere in this file. Sits fully inside tabDock's own ClipsDescendants bounds
    -- (not straddling the edge the way resize.luau's corner grip does) - nothing behind the dock
    -- needs half of a handle to poke out into it here, so there's no reason to fight the clip.
    if isSidebar then
        -- Live-reported as "mt grosso, feio" at 6px square-cornered - thinned to a proper hairline
        -- and rounded into a small pill (centred vertically within its own row height doesn't
        -- apply here since it already spans tabDock's full height; the rounding alone is what
        -- reads as a deliberate handle rather than a stray rectangle glued to the edge).
        local sidebarGrip = self:Create("Frame", {
            Name = "SidebarResizeGrip",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -2, 0.5, 0),
            Size = UDim2.new(0, 3, 1, -16),
            BorderSizePixel = 0,
            ZIndex = 3, -- above tab rows (ZIndex 2) so it's still grabbable right at the edge
            BackgroundTransparency = 1, -- In = 0.6 on hover/drag, see setGripVisual below

            Parent = self.tabDock,
        }, { BackgroundColor3 = "SurfaceStroke" })
        self:Create("UICorner", {
            CornerRadius = UDim.new(1, 0),
            Parent = sidebarGrip,
        })

        -- Scaled up on a touch-primary device (window.mobileHitScale, same knob resize.luau's own
        -- corner grip uses) - 12px is fine for a mouse pointer's precision but tight for a
        -- fingertip trying to grab a 3px-visible hairline.
        local sidebarGripHitWidth = if self:IsMobile() then 12 * self.mobileHitScale else 12
        local sidebarGripInteract = self:Create("TextButton", {
            -- A little wider than the visible 6px line (easier to grab) but still fully inside
            -- tabDock's own ClipsDescendants bounds, not straddling past its edge - unlike
            -- resize.luau's corner grip, there's no need to poke outside the dock here, and
            -- keeping the hit area fully inside sidesteps ever having to check whether
            -- ClipsDescendants affects input hit-testing the same way it affects rendering.
            Size = UDim2.new(0, sidebarGripHitWidth, 1, 0),
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = "",
            TextTransparency = 1,
            -- Every tab row's own click-catcher (topbarItemInteract) spans the row's full width,
            -- which overlaps this exact strip at the row's own right edge - above that at ZIndex
            -- 2, this would never actually be reachable; a click there would always hit the tab
            -- underneath instead of grabbing the resize handle.
            ZIndex = 4,

            Parent = self.tabDock,
        })

        local gripHoverInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        local resizingSidebar = false
        -- Three states rather than just a transparency fade - rest is a short, barely-there sliver
        -- (SurfaceStroke, near-invisible); hover grows it taller and tints it toward the theme's
        -- own AccentColor instead of a neutral grey, so it reads as "this is interactive" rather
        -- than just "slightly less transparent"; drag goes further still (full height, solid
        -- accent, a hair thicker) - the same rest/hover/drag escalation resize.luau's own corner
        -- grip uses, just as a colour+length shift instead of an icon scale.
        local function setGripVisual(state: "rest" | "hover" | "drag")
            local color = if state == "rest" then self.theme.SurfaceStroke else self.theme.AccentColor
            local transparency = if state == "rest" then 1 elseif state == "hover" then 0.45 else 0.1
            local height = if state == "rest" then UDim2.new(0, 3, 1, -16)
                elseif state == "hover" then UDim2.new(0, 3, 1, -8)
                else UDim2.new(0, 4, 1, 0)
            variables.tweenService:Create(sidebarGrip, gripHoverInfo, {
                BackgroundTransparency = transparency,
                BackgroundColor3 = color,
                Size = height,
            }):Play()
        end
        self:Connect(sidebarGripInteract.MouseEnter, function()
            if not resizingSidebar then
                setGripVisual("hover")
            end
        end)
        self:Connect(sidebarGripInteract.MouseLeave, function()
            if not resizingSidebar then
                setGripVisual("rest")
            end
        end)

        local dragStartMouseX = 0
        local dragStartWidth = 0
        local quickFade = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        local function releaseSidebarResize()
            if not resizingSidebar then
                return
            end
            resizingSidebar = false
            setGripVisual("rest")
            self:_setTabIndicatorVisible(true, quickFade)
            task.wait() -- let tabDock/tab rows settle at the final width before reading geometry
            self:_updateTabIndicator(self.selectedTab, false)
            -- Not persisted by the library itself - self.sidebarWidth would reset to its
            -- construction-time default next session on its own. Window:OnSidebarWidthChanged
            -- (windowMethods.luau) fires right below, from the one real funnel (_applySidebarWidth)
            -- every width change already passes through - a consumer script mirrors that into its
            -- own Window:RegisterFlag'd value to survive a restart (see the hub template's own use
            -- of both).
        end

        self:Connect(sidebarGripInteract.InputBegan, function(input, processed)
            if processed or not self:_interactive() then
                return
            end
            local inputType = input.UserInputType.Name
            if inputType ~= "MouseButton1" and inputType ~= "Touch" then
                return
            end
            resizingSidebar = true
            setGripVisual("drag")
            dragStartMouseX = variables.userInputService:GetMouseLocation().X
            dragStartWidth = self.sidebarWidth
            -- Hidden for the whole drag rather than live-tracked: the pill's own positioning
            -- depends on AbsoluteSize/AbsolutePosition (see _updateTabIndicator's own comment on
            -- why), which only reflects reality once the layout settles - not something to trust
            -- on every single frame of a fast, continuous drag. One clean resync on release
            -- (below) instead of fighting that every frame.
            self:_setTabIndicatorVisible(false, quickFade)
        end)

        self:Connect(variables.runService.RenderStepped, function()
            if not resizingSidebar then
                return
            end
            if not self:_interactive() then
                releaseSidebarResize()
                return
            end
            local mouseX = variables.userInputService:GetMouseLocation().X
            self:_applySidebarWidth(dragStartWidth + (mouseX - dragStartMouseX))
        end)

        self:Connect(variables.userInputService.InputEnded, function(input)
            local inputType = input.UserInputType.Name
            if inputType == "MouseButton1" or inputType == "Touch" then
                releaseSidebarResize()
            end
        end)
        -- alt-tabbing mid-drag never delivers InputEnded, same story as resize.luau's own grip
        self:Connect(variables.userInputService.WindowFocusReleased, releaseSidebarResize)
    end

    -- Actions
    self.actionContainer = self:Create("Frame", {

        AnchorPoint = Vector2.new(1, 0.5),
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 24),
        Position = UDim2.new(1, -20, 0.5, 0),
        BackgroundTransparency = 1,

        Parent = self.topbar,
    })

    self.actionsListLayout = self:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.actionContainer,
    })

    self.rfSettings = self:CreateTab({
        name = "Rayfield Settings",
        customOrder = 1000,

        neglectSelector = true,
        -- everything here is ephemeral: these controls persist to rayfield.rfld via SaveSettings,
        -- never the user's config. children inherit this, so none of them opt out individually.
        forgetState = true,
    })

    require(script.Parent.action).new(self, {
        name = "Close",
        icon = constants.icons.close,
        order = 1,

        callback = function()
            self:ToggleHide()
        end,
    })

    self.minimiseAction = require(script.Parent.action).new(self, {
        name = "Minimise",
        icon = constants.icons.minimise,
        order = 2,

        callback = function()
            self:ToggleMinimise()
        end,
    })

    self.settingsAction = require(script.Parent.action).new(self, {
        name = "Settings",
        icon = constants.icons.settings,
        order = 3,
        linkedTab = self.rfSettings,

        callback = function()
            self.rfSettings:Select()
        end,
    })

    search.build(self)

    self.unloaded = false
    self.minimised = false
    self.hidden = true
    self.animating = false
    self._revealing = false
    self.hasShownOnce = false

    self.settings = {
        toggleKeybind = Enum.KeyCode.K,
        mouseOverride = true, -- free the cursor while the menu is open (for FPS games that lock it)
        keepOnScreen = true, -- clamp the drag so the window cant be pulled off screen
        welcomeToast = true, -- the "signed in as" toast on first open for a new/changed account
        haptics = false, -- off by default; opt in from settings (buzzes on presses/notifications)
        soundEffects = false, -- off by default, same reasoning as haptics above - opt in from
        -- settings rather than a sound just starting the moment a window opens
        resizeGripEnabled = true, -- Devlog 8: shows the corner drag-to-resize handle
        debugLogging = false, -- off by default; gates Window:DebugLog - a player flips this (or
        -- presses F9) only when asked to reproduce a bug, so a dev's DebugLog calls stay silent
        -- for everyone else the rest of the time
        -- only meaningful when self.loading exists (the Settings toggle is conditional on that
        -- too) - defaults to whatever the dev set, the player can still flip it off from there
        loadingAnimationEnabled = if self.loading then self.loading.enabled else false,
        uiScale = 100, -- percent; self.contentScale.Scale = uiScale / 100
        tourSeen = false, -- flips true once the guided tour (if the dev configured one) has
        -- played through or been skipped - see _firstShow's own tour block
        -- customWindowSize starts absent (nil): no saved drag yet, so sizing still comes from
        -- self.defaultSize/customSize the normal way. Set once the resize grip is dragged, see
        -- resize.luau, and read right below once a saved one exists.
    }

    self:LoadSettings()
    self.contentScale.Scale = self.settings.uiScale / 100

    -- Devlog 8 corner grip: a size saved from a previous session becomes the new basis for every
    -- size decision from here on (the reveal target, _applyWindowSize's own viewport refit) -
    -- self.defaultSize is deliberately left alone so double-clicking the grip can still get back
    -- to the window's original size after this.
    if self.settings.customWindowSize then
        self.customSize = Vector2.new(self.settings.customWindowSize.X, self.settings.customWindowSize.Y)
        self.size = fitWindowSize(self.customSize)
    end

    hapticEngine.setContainer(self.screenGui) -- effects live with the interface, not the workspace
    hapticEngine.setEnabled(self.settings.haptics) -- honour a saved off before any interaction
    soundEngine.setContainer(self.screenGui)
    soundEngine.setEnabled(self.settings.soundEffects)
    chrome.buildCollapsedFace(self)
    self.resize = require(script.Parent.resize).new(self)
    self.tour = require(script.Parent.tour).new(self)
    self:_bindKeybind()
    self:_bindMouseOverride()
    self:_bindTopbarDrag()
    self:_watchViewport()
    self:_buildSettingsUI()

    self:_syncLiveAnimation()

    return self
end

-- The instance + property every reveal/hide/opacity call site targets for "the window body's
-- own fill", instead of every one of them hardcoding self.main/BackgroundTransparency directly -
-- in squircle mode self.main itself stays permanently transparent (see its own construction
-- above) and self.mainSquircle's ImageTransparency carries the fill instead. Centralising this
-- here is what let squircleCorners slot in without touching Show/Hide/SetTransparency's own
-- logic at each of their several call sites, just the one line at each that used to say
-- `self.main, "BackgroundTransparency"`.
function Window:_mainVisual(): (GuiObject, string)
    if self.mainSquircle then
        return self.mainSquircle, "ImageTransparency"
    end
    return self.main, "BackgroundTransparency"
end

-- Every Window:X method past this point lives in one of these two files (pure side effect:
-- attaching more methods onto the same shared Window table from windowCore) - see this file's
-- own header comment and windowCore.luau's for why.
require(script.Parent.windowMethods)
require(script.Parent.windowExtra)

return Window

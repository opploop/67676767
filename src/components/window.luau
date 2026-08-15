--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Utility
local utility = script.Parent.Parent.utility
local image = require(utility.image)
local functions = require(utility.functions)
local persistence = require(utility.persistence)
local constants = require(utility.constants)
local locale = require(utility.locale)
local log = require(utility.log)
local hapticEngine = require(utility.HapticEngine)
local windowSizing = require(utility.windowSizing)
local icons = require(utility.icons)
local acrylic = require(utility.acrylic)
local chrome = require(script.Parent.chrome)
local search = require(script.Parent.search)

-- Variables
local variables = require(utility.variables)

-- Themes
local themes = script.Parent.Parent.themes

-- Module
local Window = {}
Window.__index = Window

-- Default entrance-reveal tween (elements override with their own where needed)
local revealInfo = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

-- The collapsed "pill" main morphs into on Hide, top-anchored the way the old standalone
-- restore button used to sit.
local collapsedSize = UDim2.fromOffset(185, 50)
local collapsedTop = UDim2.new(0.5, 0, 0, 20)

-- Width of the top-centre toast stack container. Toasts hug their own content and centre
-- within it, so this just needs to be at least the toast's own max width.
local maxToastWidth = 320

-- Standard element row height, shared by the compact button/toggle scaffold.
local compactRowHeight = 41

-- How often the backstop re-checks the fit, for anything the viewport signal misses.
local viewportReconcileInterval = 2

-- The size the current screen calls for. Everything downstream (the reveal target, drag
-- clamp, collapse) reads self.size, so it all inherits whatever this returns.
local function fitWindowSize(customSize: Vector2?): UDim2
    local camera = variables.workspace.CurrentCamera
    return windowSizing.fit(camera and camera.ViewportSize, customSize)
end

-- WindowProps.size: a dev-supplied starting size, still screen-fit the same way the built-in
-- default is (see windowSizing.fit). Accepts a Vector2, a UDim2 (its offset component), or a
-- plain {width, height}/{X, Y}/{x, y} table so a dev doesn't have to reach for Vector2.new.
local function resolveCustomSize(value): Vector2?
    if typeof(value) == "Vector2" then
        return value
    end
    if typeof(value) == "UDim2" then
        return Vector2.new(value.X.Offset, value.Y.Offset)
    end
    if typeof(value) == "table" then
        local x = value.width or value.Width or value.X or value.x or value[1]
        local y = value.height or value.Height or value.Y or value.y or value[2]
        if typeof(x) == "number" and typeof(y) == "number" then
            return Vector2.new(x, y)
        end
    end
    return nil
end

-- Devlog 6/7 Settings > Font picker. "auto" is the brand font (the default - a custom-downloaded
-- family via variables.brandFont); every other entry is a plain built-in Roblox font, all of
-- them (Devlog 7 "complete font picker", was just 4) via Enum.Font:GetEnumItems(). Keyed
-- lowercase so SetFont can match case-insensitively the same way ChangeTheme's theme names do;
-- fontOptionNames keeps the proper-cased names for the Settings dropdown, which already has its
-- own live search built in - exactly what "filter by name" asks for, no new search UI needed.
local fontChoices: { [string]: Enum.Font } = {}
local fontOptionNames = { "Auto" }
for _, item in Enum.Font:GetEnumItems() do
    fontChoices[string.lower(item.Name)] = item
    table.insert(fontOptionNames, item.Name)
end
table.sort(fontOptionNames, function(a, b)
    if a == "Auto" then
        return true
    elseif b == "Auto" then
        return false
    end
    return a < b
end)

-- Same family, a different weight - Font.fromEnum only ever gives the enum's own default
-- weight, so re-derive a Font at the weight we actually want from its family name instead.
local function fontAtWeight(enumFont: Enum.Font, weight: Enum.FontWeight): Font
    return Font.new(Font.fromEnum(enumFont).Family, weight)
end

-- Keys that drive a UIGradient and so want a ColorSequence. A dev may pass a plain Color3 for
-- any of these and we widen it to a flat sequence, so a theme reads the same either way.
local gradientKeys = {
    WindowColor = true,
    ElementGradient = true,
    ElementStrokeGradient = true,
    TabBackground = true,
    TabStroke = true,
    SliderProgress = true,
}

local function coerceThemeValue(key, value)
    if gradientKeys[key] and typeof(value) == "Color3" then
        return ColorSequence.new(value)
    end
    return value
end

local function firstColor(value)
    return if typeof(value) == "ColorSequence" then value.Keypoints[1].Value else value
end

-- A subtle raised edge for a fill: lighten a dark fill, darken a light one.
local function edgeShade(color, amount)
    local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    local target = if luminance > 0.5 then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
    return color:Lerp(target, amount)
end

-- Give a custom theme sensible strokes for free: when it recolours a surface but leaves the
-- matching stroke unset, derive one from the fill so a colours-only theme still reads coherently.
local function deriveStrokes(resolved, overrides)
    if overrides.ElementGradient then
        local fill = firstColor(resolved.ElementGradient)
        if overrides.ElementStroke == nil then
            resolved.ElementStroke = edgeShade(fill, 0.28)
        end
        if overrides.ElementStrokeGradient == nil then
            resolved.ElementStrokeGradient = ColorSequence.new(edgeShade(fill, 0.4))
        end
        if overrides.ElementStrokeHover == nil then
            resolved.ElementStrokeHover = edgeShade(fill, 0.52)
        end
    end
    if overrides.TabBackground and overrides.TabStroke == nil then
        resolved.TabStroke = ColorSequence.new(edgeShade(firstColor(resolved.TabBackground), 0.4))
    end
end

-- Resolve a theme arg to its raw key set: a table is taken as-is (partial is fine), a known
-- name is required, anything else falls back to default. Read-only - callers never mutate it,
-- so the require()-cached module stays clean for other windows.
local function themeOverrides(value)
    if typeof(value) == "table" then
        return value
    elseif typeof(value) == "string" then
        local named = themes:FindFirstChild(string.lower(value))
        if named then
            return require(named)
        end
        -- a typo'd name shouldnt crash the menu; warn and fall back so the UI still builds
        log.warn("Rayfield: unknown theme '" .. value .. "', using default")
    elseif value ~= nil then
        log.warn("Rayfield: invalid theme (expected a built-in name or a theme table), using default")
    end
    return require(themes["default"])
end

-- A complete theme for first paint: default filled in with the given overrides, so a partial
-- custom theme only needs the keys it wants to change and the rest fall back to default.
local function resolveTheme(value)
    local resolved = table.clone(require(themes["default"]))
    local overrides = themeOverrides(value)
    for key, override in overrides do
        resolved[key] = coerceThemeValue(key, override)
    end
    -- only a hand-written table gets derived strokes; a named built-in ships its own.
    if typeof(value) == "table" then
        deriveStrokes(resolved, overrides)
    end

    -- theme modules call brandFont at first require and are cached from then on, so a
    -- fallbackFont set afterwards would never reach them. recompute against the current
    -- stand-in, unless the dev named a font themselves.
    local userTable = if typeof(value) == "table" then value else nil
    if not (userTable and (userTable.Font or userTable.font)) then
        resolved.Font = variables.brandFont(Enum.FontWeight.Medium)
    end
    if not (userTable and (userTable.TitleFont or userTable.titleFont)) then
        resolved.TitleFont = variables.brandFont(Enum.FontWeight.SemiBold)
    end

    return resolved
end

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
            }
        end)(),
    }, Window)

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

    -- Rayfield Gen2 Screen
    self.screenGui = self:Create("ScreenGui", {
        Name = variables.httpService:GenerateGUID(false),
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        Enabled = true,
        DisplayOrder = constants.displayOrder.window,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,

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

    self.windowCorner = self:Create("UICorner", {

        Parent = self.main,
    }, { CornerRadius = "CornerRoundness" })

    self.windowStroke = self:Create("UIStroke", {
        -- Animations
        Transparency = 1, -- In = 0.95

        Parent = self.main,
    }, { Color = "SurfaceStroke" })

    self.windowGradient = self:Create("UIGradient", {
        Rotation = 270,
        Offset = Vector2.new(0, -0.1),

        Parent = self.main,
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

    -- Shadow (Transparency 1 here, tweened to 0.6 on show)
    self.windowShadow = self:CreateGlow(self.main, "ShadowColor", 20, 1)

    -- Elements Preparation

    self.elements = self:Create("Frame", {
        Size = UDim2.new(1, 0, 1, -106),
        Position = UDim2.fromScale(0.5, 1),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundTransparency = 1,
        ClipsDescendants = true,

        Parent = self.main,
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
    self.tabDock = self:Create("Frame", {
        Name = "TabDock",
        -- 20px total inset, same margin every other card-shaped element on the window uses -
        -- flush edge-to-edge (the original tabList's own sizing) read as glued to the window's
        -- corner once it had a visible fill behind it
        Size = UDim2.new(1, -40, 0, 38),
        Position = UDim2.new(0.5, 0, 0, 65),
        AnchorPoint = Vector2.new(0.5, 0),
        BorderSizePixel = 0,
        -- Without this, selecting (or scrolling to) a tab near either end of the strip let the
        -- indicator render fully outside the dock - even outside the window entirely, not just
        -- past the rounded corners. The un-clipped glow's own hard-edged blur line was the
        -- lesser problem; brought clipping back and shrank the glow instead (see CreateGlow
        -- call below) so its blur has less reach to clip in the first place.
        ClipsDescendants = true,
        -- same reasoning as self.main's own Active = true - stays clickable at any transparency
        Active = true,

        -- Live-caught (round 2): the colour fix alone still read as barely-there on most themes -
        -- self.main itself is dark/near-black on most of them too, so even a matching near-black
        -- dock at 0.55 transparency (45% opaque) was too thin a wash to read as a distinct card
        -- against a background that's already close to the same shade. Dropped to 0.2 (80%
        -- opaque) - segmentedpicker's own dedicated backdrop (see its self.main) reads clearly at
        -- 0.5, but that card sits on ordinary tab-page content, not directly on self.main's own
        -- background the way this dock does, so it needed to go noticeably darker than
        -- segmentedpicker's own value to actually separate from what's behind it here.
        -- SetTransparency's "glass window" feature (below) tweens this via
        -- 1 - dockOpacityFactor * windowOpacity - kept that formula's own resting value in sync
        -- with this baseline (both now target 0.2 at the default full-opacity windowOpacity of 1)
        -- so it doesn't get silently overwritten back the next time that runs.
        BackgroundColor3 = Color3.fromRGB(24, 24, 24),
        BackgroundTransparency = 0.2,

        Parent = self.main,
    })

    self:Create("UICorner", {
        Parent = self.tabDock,
    }, { CornerRadius = "PillCornerRadius" })

    self.tabList = self:Create("ScrollingFrame", {
        Name = "Tabs",
        Active = true,
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),

        BackgroundTransparency = 1,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 0,
        ScrollBarImageTransparency = 1,
        ScrollingDirection = Enum.ScrollingDirection.X,

        Parent = self.tabDock,
    })

    self.tabListLayout = self:Create("UIListLayout", {
        -- Devlog 7: tighter gap between tabs (was 4) - closer, more "Segmented Picker" feel
        Padding = UDim.new(0, 2),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
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
        resizeGripEnabled = true, -- Devlog 8: shows the corner drag-to-resize handle
        -- only meaningful when self.loading exists (the Settings toggle is conditional on that
        -- too) - defaults to whatever the dev set, the player can still flip it off from there
        loadingAnimationEnabled = if self.loading then self.loading.enabled else false,
        -- customWindowSize starts absent (nil): no saved drag yet, so sizing still comes from
        -- self.defaultSize/customSize the normal way. Set once the resize grip is dragged, see
        -- resize.luau, and read right below once a saved one exists.
    }

    self:LoadSettings()

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
    chrome.buildCollapsedFace(self)
    self.resize = require(script.Parent.resize).new(self)
    self:_bindKeybind()
    self:_bindMouseOverride()
    self:_bindTopbarDrag()
    self:_watchViewport()
    self:_buildSettingsUI()

    self:_syncLiveAnimation()

    return self
end

-- start or stop the gradient drift to match the current theme. called on build and on every
-- ChangeTheme, so switching into or out of an animated theme takes effect either way.
function Window:_syncLiveAnimation()
    if not self.theme.LiveAnimation then
        self._liveAnimating = false -- the running loop sees this and stops after its current leg
        return
    end
    if self._liveAnimating then
        return -- already drifting
    end

    self._liveAnimating = true
    -- generation stamp: an old loop parked in Completed:Wait() through a static->animated
    -- swap wakes up stale and exits, instead of drifting alongside the new loop
    self._liveGeneration = (self._liveGeneration or 0) + 1
    local generation = self._liveGeneration
    task.spawn(function()
        local out = true
        local tweenInfo = TweenInfo.new(10, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        while self._liveGeneration == generation and self._liveAnimating and not self.unloaded do
            local tweenW = variables.tweenService:Create(self.windowGradient, tweenInfo, {
                Offset = Vector2.new(if out then 0.4 else -0.2, 0),
                Rotation = (if out then 220 else 280),
            })

            self._liveTween = tweenW
            tweenW:Play()
            tweenW.Completed:Wait()
            out = not out
        end
        if self._liveGeneration == generation then
            self._liveAnimating = false
            self._liveTween = nil
        end
    end)
end

function Window:ChangeTheme(theme)
    -- A named theme fully switches: resolve against default so keys it omits reset rather than
    -- lingering from the previous theme. A partial table just overrides the keys it names.
    local overrides = if typeof(theme) == "table" then theme else resolveTheme(theme)
    for name, value in overrides do
        self.theme[name] = coerceThemeValue(name, value)
    end
    -- match the constructor: a hand-written table gets derived strokes for the keys it changes
    if typeof(theme) == "table" then
        deriveStrokes(self.theme, overrides)
    end

    for instance, properties in self.themeProperties do
        for property, value in properties do
            local targetValue = if typeof(value) == "table" then value[2](self.theme[value[1]]) else self.theme[value]

            if typeof(targetValue) == "Color3" or typeof(targetValue) == "number" then
                variables.tweenService
                    :Create(
                        instance,
                        TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { [property] = targetValue }
                    )
                    :Play()
            else
                instance[property] = targetValue
            end
        end
    end

    -- themeProperties above only carry plain colours; reveal-driven transparencies and state
    -- colours (the toggle knob, field fills, glows) aren't, so refresh the elements to reach
    -- them on a live swap. Every tab's elements stay shown (just page-clipped), settings
    -- included, so refresh them all; groups forward the call to their children.
    if self.hidden then
        -- a hidden window has nothing to animate into, so defer the refresh to the next Show
        -- rather than dropping it and reopening with the old themes state colours
        self._themeRefreshPending = true
    else
        self:_refreshElementThemes()
    end

    -- tabAccentColor isn't itself a themeProperty (it's live-settable independent of the theme
    -- via SetTabAccentColor), but it starts out just a snapshot of the old theme's AccentColor -
    -- follow the new one on a swap unless a dev has explicitly pinned it to something else.
    if not self._tabAccentOverridden then
        self.tabAccentColor = self.theme.AccentColor
    end
    -- the pill's own colour + the selected tab's contrast text are outside themeProperties too
    self:_paintTabIndicator(not self.hidden)

    self:_syncLiveAnimation()
end

-- Devlog 6/7 Settings > Font picker: "Auto" (the brand font) or any built-in Roblox font by
-- name. Just a partial ChangeTheme under the hood - Font/TitleFont are already ordinary
-- themeProperties (every FontFace = "Font"/"TitleFont" binding made via Create), so swapping
-- them through here reaches every live element the same way any other theme change does.
function Window:SetFont(name)
    local key = string.lower(tostring(name or "auto"))
    if key ~= "auto" and fontChoices[key] == nil then
        log.warn("Rayfield: unknown font '" .. tostring(name) .. "', using Auto")
        key = "auto"
    end
    self.fontChoice = key

    local titleFont, bodyFont
    if key == "auto" then
        titleFont = variables.brandFont(Enum.FontWeight.SemiBold)
        bodyFont = variables.brandFont(Enum.FontWeight.Medium)
    else
        local enumFont = fontChoices[key]
        titleFont = fontAtWeight(enumFont, Enum.FontWeight.SemiBold)
        bodyFont = fontAtWeight(enumFont, Enum.FontWeight.Medium)
    end

    self:ChangeTheme({ Font = bodyFont, TitleFont = titleFont })
end

-- Devlog 7 "glass window": 0 (fully opaque, default) to 100 (fully invisible). Scales the
-- window frame, the tab dock, and every card uniformly so it all reads as one sheet of glass
-- rather than a stack of independently-faded pieces. Cards ride along for free: ElementTransparency
-- is an ordinary themeProperty already, so pushing a scaled value through ChangeTheme reaches
-- every card the same way any other live theme change does. self.main and self.tabDock aren't
-- theme-bound (their own baselines - fully opaque and 0.2 - are plain literals set once at
-- creation, not read from the theme), so those two get tweened directly instead.
--
-- Reaching literal BackgroundTransparency 1 is safe: a plain Frame's default Active is false,
-- and per Roblox's own rule that stops it blocking/capturing input in its own bounds the moment
-- transparency hits exactly 1 - live-caught this at 100%, the whole window (and every card,
-- ElementTransparency-bound the same way) went click-through to the game behind it, which is
-- what "can't drag the handle back" and "the UI goes into the game's background" both were.
-- Fixed at the source instead of just avoiding the value: self.main, self.tabDock, and every
-- card (via Window:StyleElementBody, or directly where a component styles its own card outside
-- that helper) now set Active = true explicitly, so they stay clickable at any transparency.
function Window:SetTransparency(percent)
    percent = math.clamp(percent, 0, 100)
    self.windowOpacity = 1 - percent / 100

    self:ChangeTheme({ ElementTransparency = 1 - self.windowOpacity })

    local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    variables.tweenService:Create(self.main, info, { BackgroundTransparency = 1 - self.windowOpacity }):Play()
    variables.tweenService
        :Create(self.tabDock, info, { BackgroundTransparency = 1 - 0.8 * self.windowOpacity })
        :Play()
end

-- Devlog 7 "Acrylic Blur": frosts the game behind the window via a Lighting.BlurEffect (see
-- acrylic.luau for why that, and not the DepthOfFieldEffect trick some other UI libraries lean
-- on, is the right tool here). size is BlurEffect.Size (roughly 0-56); omit for a sane default.
function Window:SetAcrylic(enabled, size)
    self.acrylicEnabled = enabled and true or false
    acrylic.setEnabled(self.acrylicEnabled, size)
end

function Window:_refreshElementThemes()
    for _, tab in self.tabs do
        for _, element in tab.elements do
            if element._refreshTheme then
                element:_refreshTheme()
            end
        end
    end
end

function Window:CreateTab(properties)
    local newTab = require(script.Parent.tab).new(self, properties)

    table.insert(self.tabs, newTab)

    if not newTab.neglectSelector then
        local isFirstVisible = true
        for _, tab in self.tabs do
            if tab ~= newTab and not tab.neglectSelector then
                isFirstVisible = false
                break
            end
        end
        if isFirstVisible then
            newTab:Select(true)
        end

        -- a tab built after the window is already open reveals its pill right away, the
        -- same way _register shows late elements. hidden/minimised windows reveal on restore.
        if not self.hidden and not self.minimised then
            newTab.topbarItem.Visible = true
            newTab:_applyVisual(
                if self.selectedTab == newTab then "selected" else "unselected",
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            )
        end
    end

    return newTab
end

-- Squish & stretch, same technique segmentedpicker.luau's slideIndicator uses: a quick stretch
-- into a shape spanning both the old and new bounds, then a springy settle onto the exact
-- target (Back overshoots slightly before easing back). Offset-based rather than scale-based,
-- since tab pills are sized to their own content, not equal fractions of a shared bar.
local tabStretchInfo = TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local tabSettleInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- A Window method (not a free function) so it can track the in-flight tween/connection on
-- self: a plain closure-local couldn't survive between calls, which is exactly what let two
-- calls in quick succession (selecting a tab, then scrolling before its slide finished) race
-- each other - the scroll's snap would land the pill correctly, but the *first* call's still-
-- pending "stretch finished, now settle" callback fired moments later and dragged it right
-- back to the pre-scroll target. Every call now cancels whatever the previous one left running
-- (tween and callback both - disconnecting the callback alone leaves the old tween free to keep
-- animating toward its own stale goal) before doing anything else.
function Window:_slideTabIndicator(targetPos, targetSize, skipAnimation)
    local pill = self.tabIndicator

    if self._tabIndicatorSettleConn then
        self._tabIndicatorSettleConn:Disconnect()
        self._tabIndicatorSettleConn = nil
    end
    if self._tabIndicatorTween then
        self._tabIndicatorTween:Cancel()
        self._tabIndicatorTween = nil
    end

    if skipAnimation then
        pill.Position, pill.Size = targetPos, targetSize
        return
    end

    local fromLeft = pill.Position.X.Offset
    local fromRight = fromLeft + pill.Size.X.Offset
    local toLeft = targetPos.X.Offset
    local toRight = toLeft + targetSize.X.Offset

    local stretchLeft = math.min(fromLeft, toLeft)
    local stretchRight = math.max(fromRight, toRight)

    local stretchPos = UDim2.fromOffset(stretchLeft, targetPos.Y.Offset)
    local stretchSize = UDim2.fromOffset(stretchRight - stretchLeft, targetSize.Y.Offset)

    local stretchTween = variables.tweenService:Create(pill, tabStretchInfo, { Position = stretchPos, Size = stretchSize })
    self._tabIndicatorTween = stretchTween
    stretchTween:Play()

    -- :Once() isn't guaranteed on every client this session has run into - :Connect() + manual
    -- disconnect is the one form of "run this once" every client here has actually supported
    self._tabIndicatorSettleConn = stretchTween.Completed:Connect(function()
        self._tabIndicatorSettleConn = nil
        local settleTween = variables.tweenService:Create(pill, tabSettleInfo, { Position = targetPos, Size = targetSize })
        self._tabIndicatorTween = settleTween
        settleTween:Play()
    end)
end

-- Repaint the indicator's colour (+ its glow) from the current tabStyle/tabAccentColor/
-- tabAccentGlow, and recolour the selected tab's own text/icon to match (auto-contrast). Pure
-- colour - never touches Position/Size, so it's safe to call from a style/accent setter without
-- disturbing wherever the pill currently sits.
function Window:_paintTabIndicator(animate)
    -- pillColor can be a flat Color3 or a full ColorSequence (SetTabAccentColor accepts either,
    -- e.g. wired straight to a GradientPicker's own value) - White mode is always flat.
    local pillColor = if self.tabStyle == "white" then Color3.fromRGB(255, 255, 255) else self.tabAccentColor
    local pillSequence = functions.toColorSequence(pillColor)
    local flatColor = functions.flattenColor(pillColor) -- for the glow (Color3-only) + contrast text
    local glowOn = self.tabStyle == "accent" and self.tabAccentGlow
    local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    local function set(instance, props)
        if animate then
            variables.tweenService:Create(instance, info, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end

    -- ColorSequence isn't a tweenable type - the gradient itself always snaps, only the flat
    -- BackgroundColor3 underneath it (visible for an instant on the very first paint, and as
    -- whatever peeks past the gradient's own edges) and the glow actually ease.
    self.tabIndicatorGradient.Color = pillSequence
    set(self.tabIndicator, { BackgroundColor3 = flatColor })
    set(self.tabIndicatorGlow, { Color = flatColor, Transparency = if glowOn then 0.5 else 1 })

    -- re-run the selected tab's own "selected" paint so its text/icon re-derive contrast
    -- against whatever the pill colour just became - _applyVisual computes that itself
    if self.selectedTab and not self.selectedTab.neglectSelector then
        self.selectedTab:_applyVisual("selected", if animate then info else nil)
    end
end

-- Fade the shared accent pill in/out alongside the tab strip itself. It lives outside tabList
-- (see its creation above, and _paintTabIndicator never touches its transparency) so hiding
-- tabList/tabDock alone left it sitting fully opaque through a search-open swap or a minimise/
-- hide's mid-shrink, ghosting over whatever ended up on top of it.
function Window:_setTabIndicatorVisible(shown, info)
    local pill = self.tabIndicator
    if not pill then
        return
    end
    if shown then
        pill.Visible = true
        local glowOn = self.tabStyle == "accent" and self.tabAccentGlow
        variables.tweenService:Create(pill, info, { BackgroundTransparency = 0 }):Play()
        if self.tabIndicatorGlow then
            variables.tweenService
                :Create(self.tabIndicatorGlow, info, { Transparency = if glowOn then 0.5 else 1 })
                :Play()
        end
    else
        variables.tweenService:Create(pill, info, { BackgroundTransparency = 1 }):Play()
        if self.tabIndicatorGlow then
            variables.tweenService:Create(self.tabIndicatorGlow, info, { Transparency = 1 }):Play()
        end
        task.delay(info.Time, function()
            if pill then
                pill.Visible = false
            end
        end)
    end
end

-- Slide the pill to `tab`'s own resolved geometry. Reads AbsolutePosition/AbsoluteSize rather
-- than the tab's own Position/Size - confirmed live that this executor's UIListLayout updates
-- the Absolute* read-outs correctly but never actually writes the settable Position property
-- back (it stays frozen at its unlaid-out (0,0) forever), so trusting Position left the pill
-- stuck in the corner no matter what. Measured against tabDock (the indicator's own parent,
-- see its creation above), not tabList - a second live-probe found that once a plain Position
-- write lands on a child nested inside tabList's ScrollingFrame, this executor never actually
-- re-renders it (the property itself reads back correctly; AbsolutePosition and the real pixel
-- just silently stop following it). tab.topbarItem's own AbsolutePosition already reflects
-- wherever tabList is currently scrolled to, so this stays correct without depending on
-- CanvasPosition at all.
function Window:_updateTabIndicator(tab, animate)
    if not tab or tab.neglectSelector or not tab.topbarItem then
        return
    end
    local item = tab.topbarItem
    local dockOrigin = self.tabDock.AbsolutePosition
    local itemPos = item.AbsolutePosition
    local targetPos = UDim2.fromOffset(itemPos.X - dockOrigin.X, itemPos.Y - dockOrigin.Y)
    local targetSize = UDim2.fromOffset(item.AbsoluteSize.X, item.AbsoluteSize.Y)
    self:_slideTabIndicator(targetPos, targetSize, not animate)
    self:_paintTabIndicator(animate)
end

-- Live switch between a plain white pill and one tinted to the accent colour with a soft glow.
function Window:SetTabStyle(style)
    self.tabStyle = if style == "white" then "white" else "accent"
    self:_paintTabIndicator(true)
end

-- Live-recolour the accent pill (and its glow), e.g. wiring it to a ColorPicker/GradientPicker.
-- Accepts a flat Color3 or a full ColorSequence - wire a GradientPicker's own :value straight
-- in and the pill actually renders that gradient instead of flattening it to one colour.
function Window:SetTabAccentColor(color)
    if typeof(color) ~= "Color3" and typeof(color) ~= "ColorSequence" then
        return
    end
    self.tabAccentColor = color
    self._tabAccentOverridden = true
    if self.tabStyle == "accent" then
        self:_paintTabIndicator(true)
    end
end

-- Toggle the soft glow under the accent pill at runtime. No-op look while in White mode (no
-- glow there either way) - still stored, so switching back to Accent respects it immediately.
function Window:SetTabAccentGlow(shown)
    self.tabAccentGlow = shown and true or false
    self:_paintTabIndicator(true)
end

function Window:CreateTag(properties)
    local newTag = require(script.Parent.tag).new(self, properties)
    table.insert(self.tags, newTag)
    return newTag
end

-- Register a saveable control under its flag. Keeps flags unique so two same-named
-- elements dont clobber each other's saved value. Updates control.flag to the key we
-- actually stored under and returns it.
function Window:_registerControl(control)
    if not control.flag or control.flag == "" or control.forgetState then
        return
    end

    local flag = control.flag
    if self.controls[flag] then
        local n = 2
        while self.controls[flag .. n] do
            n += 1
        end
        flag = flag .. n
        log.warn(
            "Rayfield: duplicate config flag '"
                .. control.flag
                .. "', saving this one as '"
                .. flag
                .. "'. Set a unique flag to keep it stable across sessions."
        )
    end

    control.flag = flag
    self.controls[flag] = control
    return flag
end

-- Restore an element built after the config was already loaded. autoLoad only fires once on
-- first Show, so without this a late element (one built after a remote fetch, say) keeps its
-- default and the next autosave writes that default over the saved value.
-- Called from the CreateX tails once the element is fully built, since _registerControl runs
-- mid-construction and :Set would touch instances that dont exist yet.
function Window:_restoreLate(element)
    if not self._loadedConfig or not element.flag or element.forgetState then
        return
    end

    local wasLoading = self._loading
    self._loading = true -- dont autosave the value we just read back
    persistence.applyTo(element, self._loadedConfig[element.flag])
    self._loading = wasLoading
end

-- Autosave a control's value after an interactive or programmatic change, when the window is
-- set to autoSave and the control opts into persistence. Every Set/commit path funnels here so
-- persistence stays uniform across elements.
function Window:_persist(control)
    -- _loading: a config restore fires every control's callback, but must not autosave back over
    -- the file it's reading (or storm Save once per control)
    if control.flag and not control.forgetState and self.configuration.autoSave and not self._loading then
        task.spawn(self.Save, self)
    end
end

-- Drop a control from the flag registry when its element is removed, so Save/Load and the
-- Flags view never touch a destroyed instance.
function Window:_unregisterControl(control)
    if control.flag and self.controls[control.flag] == control then
        self.controls[control.flag] = nil
    end
end

-- find a keybind element currently bound to `key`, skipping `exclude` and unbound keys. lets
-- the menu-toggle keybind refuse a key an element keybind already owns. keybinds only live at
-- tab level (groups dont hold them), so a scan over each tab's elements catches them all.
function Window:_keybindUsing(key, exclude)
    if typeof(key) ~= "EnumItem" or key == Enum.KeyCode.Unknown then
        return nil
    end
    for _, tab in self.tabs do
        for _, element in tab.elements do
            if element ~= exclude and element.__type == "Keybind" and element.value == key then
                return element
            end
        end
    end
    return nil
end

function Window:Notify(properties)
    if self.unloaded then
        return -- nothing to parent into once the ScreenGui is gone
    end
    if not self.notifications then
        self.notifications = self:Create("Frame", {
            Name = "Notifications",
            Size = UDim2.new(0, 300, 0, 800),
            Position = UDim2.new(1, -20, 1, -20),
            AnchorPoint = Vector2.new(1, 1),
            BackgroundTransparency = 1,

            Parent = self.screenGui,
        })

        self:Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            -- No padding here: the gap lives inside each notification so removing
            -- one doesn't drop an external gap and jolt the stack.
            Padding = UDim.new(0, 0),

            Parent = self.notifications,
        })
    end

    return require(script.Parent.notification).new(self, properties)
end

-- Top-centre / bottom-centre toast stack. Like Notify but for brief, centred messages that drop
-- in from the top (or rise from the bottom) of the screen (newest on top). Each toast takes
-- { title, subtitle?, icon?, duration?, position? }.
function Window:Toast(properties)
    if self.unloaded then
        return
    end

    local position = (properties or {}).position or "Top"
    local isTop = position == "Top"
    local containerKey = if isTop then "_toastsTop" else "_toastsBottom"
    local container = self[containerKey]

    if not container then
        container = self:Create("Frame", {
            Name = "Toasts",
            Size = UDim2.new(0, maxToastWidth, 1, -24),
            Position = if isTop then UDim2.new(0.5, 0, 0, 12) else UDim2.new(0.5, 0, 1, -12),
            AnchorPoint = if isTop then Vector2.new(0.5, 0) else Vector2.new(0.5, 1),
            BackgroundTransparency = 1,
            ZIndex = constants.zIndex.toast,

            Parent = self.screenGui,
        })

        self:Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = if isTop then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            -- gap lives inside each toast so removing one collapses its gap with it
            Padding = UDim.new(0, 0),

            Parent = container,
        })

        self[containerKey] = container
    end

    return require(script.Parent.toast).new(self, properties, container)
end

-- Centred modal over a dimmed backdrop. Takes { title, subtitle?, icon?, content?, boxes?,
-- options?, dismissable? } - give it options for a choice dialog, or boxes for a changelog.
-- Returns the popup handle (call :Close() to dismiss it yourself).
function Window:Popup(properties)
    if self.unloaded then
        return
    end
    return require(script.Parent.popup).new(self, properties)
end

local greetingFadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- A white overlay, matching the window's own rounded corners, that cycles a short greeting in
-- each of `texts` and then sweeps away in a curved (circular) wipe to reveal the menu - the
-- overlay shrinks toward its centre while its own corner radius grows to fully round at the same
-- time, so a plain rectangle becomes an iris closing rather than needing any actual masking.
-- Takes { texts = {"Hello", "Bonjour", ...}, holdTime?, wipeTime? }. Safe to call on demand (a
-- "Play greeting" button) as well as once on first show - re-entrant calls no-op while one's
-- already running rather than fighting it for the same overlay.
function Window:PlayGreeting(properties)
    if self.unloaded or self._greetingPlaying then
        return
    end
    properties = if typeof(properties) == "table" then properties else {}
    local texts = properties.texts or properties.Texts or { "Hello" }
    local holdTime = properties.holdTime or properties.HoldTime or 0.85
    local wipeTime = properties.wipeTime or properties.WipeTime or 0.7
    if #texts == 0 then
        return
    end
    self._greetingPlaying = true

    if not self._greetingOverlay then
        self._greetingOverlay = self:Create("Frame", {
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            ZIndex = constants.zIndex.greeting,

            Parent = self.main,
        })

        self._greetingCorner = self:Create("UICorner", {
            Parent = self._greetingOverlay,
        })

        self._greetingLabel = self:Create("TextLabel", {
            Size = UDim2.fromScale(0.85, 0.3),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 28,
            TextColor3 = Color3.fromRGB(20, 20, 20),
            TextTransparency = 1,
            FontFace = self.theme.TitleFont,
            -- ZIndexBehavior is Global, so this child doesn't inherit/get elevated by the
            -- overlay's own high ZIndex - without its own explicit bump above the overlay's,
            -- the overlay's opaque white background paints right over it (confirmed live: the
            -- whole thing just read as a blank white card, the text was there the whole time,
            -- just painted under its own background).
            ZIndex = constants.zIndex.greeting + 1,

            Parent = self._greetingOverlay,
        })
    end

    local overlay, corner, label = self._greetingOverlay, self._greetingCorner, self._greetingLabel
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0.5, 0.5)
    overlay.BackgroundTransparency = 0
    corner.CornerRadius = self.theme.CornerRoundness
    label.TextTransparency = 1
    overlay.Visible = true

    for i, text in texts do
        label.Text = locale.resolve(tostring(text))
        variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 0 }):Play()
        task.wait(holdTime)
        if i < #texts then
            variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 1 }):Play()
            task.wait(0.15)
        end
    end

    variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 1 }):Play()
    local wipeInfo = TweenInfo.new(wipeTime, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
    variables.tweenService:Create(overlay, wipeInfo, { Size = UDim2.fromScale(0, 0) }):Play()
    variables.tweenService:Create(corner, wipeInfo, { CornerRadius = UDim.new(1, 0) }):Play()
    task.wait(wipeTime)

    overlay.Visible = false
    self._greetingPlaying = false
end

function Window:Hide()
    -- idempotent: a second Hide while collapsed would capture the pill spot as the
    -- restore position and teleport the window there on the next Show
    if self.animating or self.hidden then
        return
    end

    -- drop out of search first so we grow back into the normal tab view on next show. tabList
    -- stays hidden here since the collapse hides it anyway; Show re-enables it.
    if self._searching then
        search.close(self, { showTabs = false, jumpTo = self.selectedTab and self.selectedTab.tabPage })
    end

    self.animating = true
    self._revealing = true
    self.hidden = true
    self.collapsedInteract.Visible = false -- re-shown once the collapse settles, below

    -- main morphs straight into the collapsed pill rather than handing off to a separate
    -- instance - the resize grip is parented to main too, so without this it rides along and
    -- sits there over the "Tap to show" pill, live-caught as a stray corner glyph with nothing
    -- to resize while hidden.
    self.resize.grip.Visible = false

    -- closing while minimised closes properly rather than leaving a stale minimised state -
    -- Show always grows back to the full (non-minimised) layout, so the flag and icon need
    -- to agree with that
    if self.minimised then
        self.minimised = false
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.minimise) -- back to the minimise icon
    end

    -- remember where the window sat so Show grows it back to the same spot
    self._restorePosition = self.main.Position

    local home, size = self:_collapsedRect()

    -- named so the task.delay staging below can stay in lockstep with however long these
    -- actually run - slowed down from 0.18/0.35 (read as too fast, closing almost instantly)
    local fadeDuration, moveDuration = 0.26, 0.5
    local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    -- "Closing to the pill": one continuous move for the whole collapse, size and position
    -- tweening together on the same curve so they stay perfectly in sync, no seam between
    -- separate legs. Quint/Out (was Exponential/InOut) reads as the window getting sucked
    -- straight into the pill - fast off the mark, settling smoothly into place, rather than
    -- easing gently out of its starting size the way InOut does.
    local moveInfo = TweenInfo.new(moveDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local cornerInfo = TweenInfo.new(moveDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local faceInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    -- shrink the drag bar back down the same way it grows in on first reveal, instead of
    -- just cutting it
    variables.tweenService
        :Create(self.drag.dragCosmetic, fadeInfo, { Size = UDim2.fromOffset(0, 4), BackgroundTransparency = 1 })
        :Play()
    task.delay(fadeDuration, function()
        if not self.hidden then
            return
        end
        self.drag.drag.Visible = false
    end)

    -- fade the window's own chrome out; main keeps its own background/gradient/corner the
    -- whole time, it just reshapes underneath - there's nothing to hand off to
    variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 1 }):Play()

    if self.title then
        variables.tweenService:Create(self.title, fadeInfo, { TextTransparency = 1 }):Play()
    end
    if self.subtitle then
        variables.tweenService:Create(self.subtitle, fadeInfo, { TextTransparency = 1 }):Play()
    end
    if self.topbarIcon then
        variables.tweenService:Create(self.topbarIcon, fadeInfo, { ImageTransparency = 1 }):Play()
    end

    for _, action in ipairs(self.actionContainer:GetChildren()) do
        if action:IsA("Frame") then
            variables.tweenService:Create(action.ImageLabel, fadeInfo, { ImageTransparency = 1 }):Play()
        end
    end

    for _, tag in self.tags do
        tag:_setShown(false, fadeInfo)
    end

    for _, tab in pairs(self.tabs) do
        if not tab.neglectSelector and tab.topbarItem then
            tab:_applyVisual("hidden", fadeInfo)
        end
    end
    self:_setTabIndicatorVisible(false, fadeInfo)

    self:_fadeSelectedElementsOut()

    -- collapse into the pill in one continuous move - size and position tweened together
    -- so they stay perfectly in sync throughout
    variables.tweenService:Create(self.main, moveInfo, { Size = size, Position = home }):Play()
    variables.tweenService:Create(self.windowCorner, cornerInfo, { CornerRadius = UDim.new(1, 0) }):Play()

    -- once the chrome's faded, drop it and the scrolling content so nothing squashes/pokes
    -- out as the frame shrinks around it, then bring the collapsed face up over the top
    task.delay(fadeDuration, function()
        if not self.hidden then
            return
        end
        self.topbar.Visible = false
        self.elements.Visible = false
        self.tabList.Visible = false
        self.tabDock.Visible = false
        chrome.setCollapsedShown(self, true, faceInfo)
    end)

    -- once the move's settled the pill is done morphing: hand clicks to it
    task.delay(moveDuration, function()
        if not self.hidden then
            return
        end
        self.collapsedInteract.Visible = true
        self.animating = false
        self._revealing = false
    end)
end

function Window:ToggleHide()
    if self.animating then
        return
    end
    if self.hidden then
        self:Show()
    else
        self:Hide()
    end
end

function Window:ToggleMinimise()
    if self.animating or self.hidden then
        return
    end

    -- minimising drops out of search back to the tab view first, so it grows back normally
    if self._searching then
        search.close(self, { showTabs = true })
    end

    self.animating = true

    local sizeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
    local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

    if self.minimised then
        self.minimised = false
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.minimise) -- back to the minimise icon

        variables.tweenService:Create(self.main, sizeInfo, { Size = self.size }):Play()
        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 0.6 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 0 }):Play()

        variables.tweenService
            :Create(self.drag.drag, sizeInfo, {
                Position = UDim2.new(
                    self.main.Position.X.Scale,
                    self.main.Position.X.Offset,
                    self.main.Position.Y.Scale,
                    self.main.Position.Y.Offset + self.size.Y.Offset / 2 + 15
                ),
            })
            :Play()

        -- once the window's grown back, fade the content and tab pills in rather than
        -- snapping them visible
        task.delay(0.2, function()
            if self.minimised or self.hidden then
                return -- re-minimised or hidden mid animation
            end
            self.elements.Visible = true
            self.tabList.Visible = true
            self.tabDock.Visible = true
            self.resize.grip.Visible = self.settings.resizeGripEnabled
            for _, tab in pairs(self.tabs) do
                if not tab.neglectSelector and tab.topbarItem then
                    tab.topbarItem.Visible = true
                    tab:_applyVisual(if self.selectedTab == tab then "selected" else "unselected", fadeInfo)
                end
            end
            self:_setTabIndicatorVisible(true, fadeInfo)

            -- one extra step so UIListLayout actually resolves Position/AbsoluteSize for tabs
            -- that just went Visible = true, before the indicator reads them
            task.wait()
            self:_updateTabIndicator(self.selectedTab, false)

            self:_revealElements(0.035, 0.4)
        end)

        task.delay(0.5, function()
            self.animating = false
        end)
    else
        self.minimised = true
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.maximise) -- maximise icon while minimised

        -- fade the content + tab pills out instead of cutting them, then hide them once faded
        -- so they don't sit clipped under the collapsed bar
        self:_fadeSelectedElementsOut()
        for _, tab in pairs(self.tabs) do
            if not tab.neglectSelector and tab.topbarItem then
                tab:_applyVisual("hidden", fadeInfo)
            end
        end
        self:_setTabIndicatorVisible(false, fadeInfo)

        task.delay(0.3, function()
            if not self.minimised then
                return -- restored mid animation
            end
            self.elements.Visible = false
            self.tabList.Visible = false
            self.tabDock.Visible = false
            -- a collapsed bar isn't something you'd resize, and the grip would otherwise sit
            -- oversized on its now much shorter (66px) height
            self.resize.grip.Visible = false
            for _, tab in pairs(self.tabs) do
                if not tab.neglectSelector and tab.topbarItem then
                    tab.topbarItem.Visible = false
                end
            end
        end)

        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 1 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 1 }):Play()
        variables.tweenService:Create(self.main, sizeInfo, { Size = UDim2.fromOffset(self.size.X.Offset, 66) }):Play()

        variables.tweenService
            :Create(self.drag.drag, sizeInfo, {
                Position = UDim2.new(
                    self.main.Position.X.Scale,
                    self.main.Position.X.Offset,
                    self.main.Position.Y.Scale,
                    self.main.Position.Y.Offset + 66 / 2 + 15
                ),
            })
            :Play()

        task.delay(0.5, function()
            self.animating = false
        end)
    end
end

-- Park the drag bar under the window's bottom edge, matching whichever positioning the window
-- itself uses so a centred window stays centred and a dragged one stays where it was left.
function Window:_syncDragBar()
    local bar = self.drag and self.drag.drag
    if not bar then
        return
    end
    local position = self.main.Position
    local below = self.size.Y.Offset / 2 + 15
    bar.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + below)
end

-- Pull a dragged window back on screen after a re-fit, the same way a drag clamps. A window
-- parked near an edge would otherwise end up half off it when the viewport shrinks underneath.
-- Where a position ends up once the current size has to fit on the current screen. Returns it
-- unchanged when theres nothing to do, so callers can compare.
function Window:_clampedPosition(position: UDim2): UDim2
    if not self.settings or not self.settings.keepOnScreen then
        return position
    end
    -- untouched windows sit on scale and are centred, so theyre on screen by construction -
    -- clamping would only freeze them to offsets and stop them recentring later
    if position.X.Scale ~= 0 or position.Y.Scale ~= 0 then
        return position
    end

    local screen = self.screenGui.AbsoluteSize
    local halfX, halfY = self.size.X.Offset / 2, self.size.Y.Offset / 2
    local margin = 8
    -- math.max in case the window is bigger than the screen
    local x = math.clamp(position.X.Offset, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
    local y = math.clamp(position.Y.Offset, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
    if x == position.X.Offset and y == position.Y.Offset then
        return position
    end
    return UDim2.fromOffset(x, y)
end

function Window:_clampToScreen()
    self.main.Position = self:_clampedPosition(self.main.Position)
end

-- Take the size the current screen calls for. Only a live window is resized on the spot;
-- hidden, minimised or mid-animation ones just bank the size and pick it up on their next
-- show, so a rotation cant yank a collapsed pill back open.
function Window:_applyWindowSize()
    if self.unloaded then
        return
    end

    local size = fitWindowSize(self.customSize)
    local changed = size ~= self.size
    self.size = size

    -- a window mid-animation is already tweening toward the old size, so bank the change and
    -- let the reconcile apply it once the tween is done rather than fighting it
    if self.hidden or self.minimised or self.animating or self._revealing then
        self._pendingResize = self._pendingResize or changed
        return
    end

    if not changed and not self._pendingResize then
        return
    end
    self._pendingResize = false

    self.main.Size = size
    self:_clampToScreen()
    self:_syncDragBar()
end

-- Follow the screen. The property signal is the fast path, but CurrentCamera gets swapped
-- (respawn, or a game replacing it) and a listener bound to the old camera dies silently, so
-- rebind on the swap and keep a slow reconcile behind it as the backstop.
function Window:_watchViewport()
    local cameraConnection: RBXScriptConnection? = nil
    local pending = false

    local function request()
        -- a rotation fires a burst of intermediate sizes, so settle on the last one
        if pending then
            return
        end
        pending = true
        task.defer(function()
            pending = false
            self:_applyWindowSize()
        end)
    end

    local function bind()
        if cameraConnection then
            self:Disconnect(cameraConnection)
            cameraConnection = nil
        end
        local camera = variables.workspace.CurrentCamera
        if camera then
            cameraConnection = self:Connect(camera:GetPropertyChangedSignal("ViewportSize"), request)
        end
        request()
    end

    self:Connect(variables.workspace:GetPropertyChangedSignal("CurrentCamera"), bind)
    bind()

    -- Backstop for anything the signals miss. Heartbeat rather than a wait loop so it rides the
    -- normal connection cleanup and cant spin if the scheduler hands back a wait that never yields.
    local sinceReconcile = 0
    self:Connect(variables.runService.Heartbeat, function(delta: number)
        sinceReconcile += delta
        if sinceReconcile < viewportReconcileInterval then
            return
        end
        sinceReconcile = 0
        self:_applyWindowSize()
    end)
end

function Window:_bindKeybind()
    self:Connect(variables.userInputService.InputBegan, function(input, processed)
        if processed or self._recordingKeybind then
            return -- a keybind element is mid-rebind, dont eat its capture
        end
        if input.KeyCode == self.settings.toggleKeybind or input.UserInputType == self.settings.toggleKeybind then
            self:ToggleHide()
        end
    end)
end

function Window:_bindMouseOverride()
    local uis = variables.userInputService

    local function active()
        return self.settings.mouseOverride and not self.hidden and not self.minimised
    end

    local function free()
        if not active() then
            return
        end
        -- hands off while the right button is held: thats the camera panning in third person,
        -- and it needs to lock the mouse to do it. we free again the moment it lets go.
        if uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            return
        end
        if uis.MouseBehavior ~= Enum.MouseBehavior.Default then
            uis.MouseBehavior = Enum.MouseBehavior.Default
        end
        if not uis.MouseIconEnabled then
            uis.MouseIconEnabled = true
        end
    end

    -- react to the game re-locking instead of racing it each frame. it sets LockCenter, we set
    -- it back, so we always get the last word. same deal if it hides the mouse icon.
    self:Connect(uis:GetPropertyChangedSignal("MouseBehavior"), free)
    self:Connect(uis:GetPropertyChangedSignal("MouseIconEnabled"), free)

    -- right-release doesnt always flip MouseBehavior back (so the signals above wouldnt fire),
    -- so re-free explicitly once the pan ends
    self:Connect(uis.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            free()
        end
    end)

    -- Show calls this on open to free the cursor immediately (the signals above only fire on change)
    self._freeMouse = free
end

-- Grabbing the topbar drags the whole window too, its own separate handle from the bar
-- underneath - tracks the cursor 1:1 with no lag, unlike the bars own deliberate smoothing, and
-- the bar just glues to wherever main currently is each frame so it never drifts off on its own
function Window:_bindTopbarDrag()
    local uis = variables.userInputService
    local dragging = false
    local relative = Vector2.zero

    -- main.Position lives in a space shifted from AbsolutePosition by the gui inset, even
    -- though the ScreenGui ignores it - add it back or the window jumps on the first move
    local offset = Vector2.zero
    if self.screenGui and self.screenGui.IgnoreGuiInset then
        offset = variables.guiService:GetGuiInset()
    end

    local function getTarget()
        local position = uis:GetMouseLocation() + relative + offset
        local x, y = position.X, position.Y

        if self.settings and self.settings.keepOnScreen then
            local size = self.main.AbsoluteSize
            local screen = self.screenGui.AbsoluteSize
            local margin = 8
            local halfX, halfY = size.X / 2, size.Y / 2
            x = math.clamp(x, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
            y = math.clamp(y, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
        end

        return UDim2.fromOffset(x, y)
    end

    -- Global ZIndexBehavior still delivers InputBegan to an Active ancestor even when a child
    -- button covers that exact pixel, so checking the event alone isnt enough - a press over the
    -- tabs or the actions has to be rejected by where it actually landed, not just left to bubble
    local function overInteractiveChild(x, y)
        for _, region in { self.tabList, self.actionContainer } do
            local position, size = region.AbsolutePosition, region.AbsoluteSize
            if x >= position.X and x <= position.X + size.X and y >= position.Y and y <= position.Y + size.Y then
                return true
            end
        end
        return false
    end

    self:Connect(self.topbar.InputBegan, function(input, processed)
        if processed then
            return
        end

        local inputType = input.UserInputType.Name
        if inputType ~= "MouseButton1" and inputType ~= "Touch" then
            return
        end

        if overInteractiveChild(input.Position.X, input.Position.Y) then
            return
        end

        -- a grab started mid-reveal would fight the tween thats still moving the window
        if not self:_interactive() then
            return
        end

        dragging = true

        if self.screenGui and self.screenGui.IgnoreGuiInset then
            offset = variables.guiService:GetGuiInset()
        end

        relative = self.main.AbsolutePosition + self.main.AbsoluteSize * self.main.AnchorPoint - uis:GetMouseLocation()
    end)

    self:Connect(uis.InputEnded, function(input)
        local inputType = input.UserInputType.Name
        if inputType == "MouseButton1" or inputType == "Touch" then
            dragging = false
        end
    end)

    -- alt-tabbing with the button still down never delivers InputEnded, so without this the
    -- grab stays armed and the window snaps to the cursor the moment youre back
    self:Connect(uis.WindowFocusReleased, function()
        dragging = false
    end)

    self:Connect(variables.runService.RenderStepped, function()
        if not dragging then
            return
        end

        -- hidden or mid-animation means the grab went stale under us, so drop it here rather
        -- than let it wake up later and yank the window to wherever the cursor drifted
        if not self:_interactive() then
            dragging = false
            return
        end

        self.main.Position = getTarget()

        if self.drag and self.drag.drag then
            local mainPosition = self.main.Position
            self.drag.drag.Position = UDim2.new(
                mainPosition.X.Scale,
                mainPosition.X.Offset,
                mainPosition.Y.Scale,
                mainPosition.Y.Offset + (self.main.Size.Y.Offset / 2 + 15)
            )
        end
    end)
end

function Window:_buildSettingsUI()
    self.rfSettings:CreateSection({ name = "General" })

    self.rfSettings:CreateKeybind({
        name = "Toggle Keybind",
        icon = constants.icons.search,
        value = self.settings.toggleKeybind,
        isMenuToggle = true, -- reject keys already owned by an element keybind
        onChanged = function(key)
            self.settings.toggleKeybind = key
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Unlock cursor while open",
        description = "Unlocks the cursor while the menu is open so you can configure in FPS games that lock it.",
        value = self.settings.mouseOverride,
        callback = function(state)
            self.settings.mouseOverride = state
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Welcome toast",
        description = "Shows a 'Signed in as' toast the first time you open the menu on a new account.",
        value = self.settings.welcomeToast,
        callback = function(state)
            self.settings.welcomeToast = state
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Haptics",
        description = "A subtle tap as you interact, on devices that support haptics.",
        value = self.settings.haptics,
        callback = function(state)
            self.settings.haptics = state
            hapticEngine.setEnabled(state)
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateSection({ name = "Appearance" })

    -- "Amber" is the one preset name that doesn't match its theme file 1:1 (ember.luau) - every
    -- other option here is both the picker label and the real theme name, case-insensitively.
    local themeFileFor = { Amber = "ember" }

    self.rfSettings:CreateDropdown({
        name = "Color theme",
        options = { "Default", "Ocean", "Amber", "Rose", "Emerald", "Amethyst", "Midnight" },
        value = "Default",
        callback = function(value)
            self:ChangeTheme(themeFileFor[value] or value)
        end,
    })

    self.rfSettings:CreateDropdown({
        name = "Font",
        placeholder = "Search fonts...",
        options = fontOptionNames,
        value = "Auto",
        callback = function(value)
            self:SetFont(value)
        end,
    })

    self.rfSettings:CreateSlider({
        name = "Window transparency",
        range = { 0, 100 },
        value = 0,
        suffix = "%",
        callback = function(value)
            self:SetTransparency(value)
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Acrylic blur",
        description = "Frost the game behind a see-through window.",
        value = false,
        callback = function(value)
            self:SetAcrylic(value)
        end,
    })

    self.rfSettings:CreateSection({ name = "Window" })

    self.rfSettings:CreateToggle({
        name = "Keep window on screen",
        description = "Stops the window being dragged off the edge of the screen and lost.",
        value = self.settings.keepOnScreen,
        callback = function(state)
            self.settings.keepOnScreen = state
            self:SaveSettings()
        end,
    })

    -- Only shown when the dev actually configured a loading splash (self.loading) - otherwise
    -- there's nothing for this to turn on or off.
    if self.loading then
        self.rfSettings:CreateToggle({
            name = "Loading Animation",
            description = "Shows a brief splash the first time the window opens.",
            value = self.settings.loadingAnimationEnabled,
            callback = function(state)
                self.settings.loadingAnimationEnabled = state
                self:SaveSettings()
            end,
        })
    end

    self.rfSettings:CreateToggle({
        name = "Resizable window",
        description = "Shows a grip in the bottom-right corner that drags the window's size.",
        value = self.settings.resizeGripEnabled,
        callback = function(state)
            self.settings.resizeGripEnabled = state
            self.resize:SetEnabled(state)
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateButton({
        name = "Reset Window Size",
        callback = function()
            self.resize:ResetSize()
        end,
    })

    self.rfSettings:CreateButton({
        name = "Reset Window Position",
        callback = function()
            variables.tweenService
                :Create(self.main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                })
                :Play()
            variables.tweenService
                :Create(self.drag.drag, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
                    Position = UDim2.new(0.5, 0, 0.5, self.size.Y.Offset / 2 + 15),
                })
                :Play()
        end,
    })

    -- Configurations: save the current setup under a name and switch between saved ones.
    -- Only shown once the developer opts into config saving.
    if next(self.configuration) ~= nil then
        self.rfSettings:CreateSection({ name = "Configurations" })

        local selected = self:ListConfigs()[1]
        local configDropdown, nameInput

        local function refreshConfigs()
            local names = self:ListConfigs()
            configDropdown:Refresh(names)
            if selected and not table.find(names, selected) then
                selected = names[1]
            end
            if selected then
                configDropdown:Set(selected, true)
            end
        end

        configDropdown = self.rfSettings:CreateDropdown({
            name = "Saved Configurations",
            icon = constants.icons.config,
            options = self:ListConfigs(),
            value = selected,
            placeholder = "No saved configurations",
            callback = function(value)
                selected = value
            end,
        })

        nameInput = self.rfSettings:CreateInput({
            name = "Configuration Name",
            description = "Name a new configuration, or leave blank to overwrite the selected one.",
            placeholder = "e.g. PvP Loadout",
            clearOnFocus = false,
        })

        local actions = self.rfSettings:CreateGroup()

        actions:CreateButton({
            name = "Save",
            icon = constants.icons.config,
            callback = function()
                local name = nameInput.value
                if name == "" then
                    name = selected
                end
                if not name or name == "" then
                    self:Toast({ title = locale.resolve("Name your configuration first") })
                    return
                end
                if self:Save(name) then
                    nameInput:Set("")
                    selected = name
                    refreshConfigs()
                    self:Toast({
                        title = locale.resolve("Saved configuration"),
                        subtitle = name,
                        icon = constants.icons.config,
                    })
                else
                    self:Toast({ title = locale.resolve("Couldn't save configuration"), subtitle = name })
                end
            end,
        })

        actions:CreateButton({
            name = "Load",
            callback = function()
                if not selected or selected == "" then
                    self:Toast({ title = locale.resolve("Pick a configuration to load") })
                    return
                end
                if self:_applyNamedConfig(selected) then
                    self:Toast({ title = locale.resolve("Loaded configuration"), subtitle = selected })
                else
                    self:Toast({ title = locale.resolve("Couldn't load configuration"), subtitle = selected })
                end
            end,
        })

        actions:CreateButton({
            name = "Delete",
            callback = function()
                local deleting = selected
                if not deleting or deleting == "" then
                    self:Toast({ title = locale.resolve("Pick a configuration to delete") })
                    return
                end
                if self:DeleteConfig(deleting) then
                    refreshConfigs()
                    self:Toast({ title = locale.resolve("Deleted configuration"), subtitle = deleting })
                else
                    self:Toast({ title = locale.resolve("Couldn't delete configuration"), subtitle = deleting })
                end
            end,
        })
    end

    self:_buildSessionDashboard()
end

-- Devlog 7 "live session dashboard": player name, players on the server, uptime, and FPS,
-- refreshed every second. A plain card built straight onto rfSettings.tabPage rather than
-- through Tab:_register - it's a settings-only utility display, not a real element type devs
-- create, so it skips the reveal-fade system entirely and just renders opaque from the start.
function Window:_buildSessionDashboard()
    self.rfSettings:CreateSection({ name = "Session" })

    local card = self:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Name = "SessionDashboard",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0,

        Parent = self.rfSettings.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })
    self:StyleElementBody(card)

    self:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 20),
        PaddingRight = UDim.new(0, 20),
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),

        Parent = card,
    })

    self:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),

        Parent = card,
    })

    local function buildRow(order, labelText)
        local row = self:Create("Frame", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = order,

            Parent = card,
        })
        self:Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,

            Parent = row,
        })
        self:Create("TextLabel", {
            Text = locale.t(labelText),
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,

            Parent = row,
        }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })
        local value = self:Create("TextLabel", {
            Text = "-",
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            LayoutOrder = 1,

            Parent = row,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })
        return value
    end

    local playerValue = buildRow(1, "Player")
    local playersValue = buildRow(2, "Players online")
    local uptimeValue = buildRow(3, "Uptime")
    local fpsValue = buildRow(4, "FPS")

    local playersService = game:GetService("Players")
    local localPlayer = playersService.LocalPlayer
    local sessionStart = os.clock()
    local frameCount = 0

    self:Connect(variables.runService.RenderStepped, function()
        frameCount += 1
    end)

    local function formatUptime(seconds)
        seconds = math.floor(seconds)
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        if h > 0 then
            return string.format("%d:%02d:%02d", h, m, s)
        end
        return string.format("%d:%02d", m, s)
    end

    task.spawn(function()
        while not self.unloaded do
            playerValue.Text = if localPlayer then localPlayer.Name else "-"
            playersValue.Text = tostring(#playersService:GetPlayers())
            uptimeValue.Text = formatUptime(os.clock() - sessionStart)
            fpsValue.Text = tostring(frameCount) -- frames counted over the last ~1s window
            frameCount = 0
            task.wait(1)
        end
    end)
end

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
    variables.tweenService:Create(self.main, growInfo, { Size = self.size, Position = target }):Play()
    variables.tweenService:Create(self.windowCorner, cornerInfo, { CornerRadius = self.theme.CornerRoundness }):Play()

    -- Phase 2: once the frame actually reads as a window, fade its chrome in and stagger the
    -- open tab's elements. Other tabs snap ready off-screen - nobody's looking, so no animation.
    task.delay(growDuration * 0.63, function()
        -- respects the setting rather than hardcoding true, same as the minimise restore path
        self.resize.grip.Visible = self.settings.resizeGripEnabled
        self.topbar.Visible = true
        self.tabList.Visible = true
        self.tabDock.Visible = true
        self.elements.Visible = true
        self:_setTabIndicatorVisible(true, fadeInfo)

        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 0.6 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 0 }):Play()

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
        self.main.BackgroundTransparency = 1 - self.windowOpacity
        self.main.Size = self.size
        self:_playLoadingSplash()
    else
        variables.tweenService
            :Create(
                self.main,
                TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
                { BackgroundTransparency = 1 - self.windowOpacity, Size = self.size }
            )
            :Play()
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
            { Transparency = 0.6 }
        )
        :Play()
    variables.tweenService
        :Create(
            self.bottomFade,
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

function Window:ListConfigs()
    return persistence.list(self)
end

function Window:DeleteConfig(name)
    return persistence.delete(self, name)
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
    self.unloaded = true
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

return Window

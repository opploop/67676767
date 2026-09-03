--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Shared foundation for window.luau/windowMethods.luau/windowExtra.luau - the Window class got
-- split across those three files because a single window.luau finally tripped Roblox's 200,000
-- character Source limit on a ModuleScript (confirmed live: `Unable to assign property Source.
-- Provided string length (202980) is greater than or equal to max length (200000)` - the dev
-- loader couldn't even inject it anymore, so this wasn't a someday problem, it was already
-- broken). Splitting by top-level function is easy; the part that isn't is that a good few
-- module-locals (constants, theme/font helpers, the singleton registry) are read by methods on
-- both sides of every split point. Rather than duplicate them (and risk one copy drifting from
-- the other) or thread them through a real circular require (window.luau -> windowMethods.luau
-- -> window.luau, which neither Roblox's require nor this project's own dev-loader customRequire
-- - see scripts/dev-loadstring.luau - actually supports), every one of them lives here instead:
-- one shared, dependency-free module every split file requires, holding the empty Window table
-- itself plus everything that used to be a bare local at the top of the old window.luau.
--
-- Window.new (window.luau) explicitly requires windowMethods.luau and windowExtra.luau at its
-- own tail, purely for their side effect of attaching more `function Window:X` methods to this
-- same shared table - by the time anyone can actually call Window.new (which requires having
-- required window.luau itself first, which only finishes after both those requires do), every
-- method from all three files is already attached. See window.luau's own closing comment.

local utility = script.Parent.Parent.utility

local core = {}

core.image = require(utility.image)
core.functions = require(utility.functions)
core.persistence = require(utility.persistence)
core.constants = require(utility.constants)
core.locale = require(utility.locale)
core.log = require(utility.log)
core.hapticEngine = require(utility.HapticEngine)
core.soundEngine = require(utility.sound)
core.windowSizing = require(utility.windowSizing)
core.icons = require(utility.icons)
core.acrylic = require(utility.acrylic)
core.clipboard = require(utility.clipboard)
core.chrome = require(script.Parent.chrome)
core.search = require(script.Parent.search)
core.filesystem = require(utility.filesystem)
core.path = require(utility.path)
core.squircle = require(utility.squircle)
core.variables = require(utility.variables)
core.themes = script.Parent.Parent.themes

local variables = core.variables
local windowSizing = core.windowSizing
local log = core.log
local themes = core.themes

-- Module
local Window = {}
Window.__index = Window
core.Window = Window

-- Default entrance-reveal tween (elements override with their own where needed)
core.revealInfo = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

-- The collapsed "pill" main morphs into on Hide, top-anchored the way the old standalone
-- restore button used to sit.
core.collapsedSize = UDim2.fromOffset(185, 50)
core.collapsedTop = UDim2.new(0.5, 0, 0, 20)

-- Width of the top-centre toast stack container. Toasts hug their own content and centre
-- within it, so this just needs to be at least the toast's own max width.
core.maxToastWidth = 320

-- Standard element row height, shared by the compact button/toggle scaffold.
core.compactRowHeight = 41

-- How often the backstop re-checks the fit, for anything the viewport signal misses.
core.viewportReconcileInterval = 2

-- The size the current screen calls for. Everything downstream (the reveal target, drag
-- clamp, collapse) reads self.size, so it all inherits whatever this returns.
function core.fitWindowSize(customSize: Vector2?): UDim2
    local camera = variables.workspace.CurrentCamera
    return windowSizing.fit(camera and camera.ViewportSize, customSize)
end

-- WindowProps.size: a dev-supplied starting size, still screen-fit the same way the built-in
-- default is (see windowSizing.fit). Accepts a Vector2, a UDim2 (its offset component), or a
-- plain {width, height}/{X, Y}/{x, y} table so a dev doesn't have to reach for Vector2.new.
function core.resolveCustomSize(value): Vector2?
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
core.fontChoices = {} :: { [string]: Enum.Font }
core.fontOptionNames = { "Auto" }
for _, item in Enum.Font:GetEnumItems() do
    core.fontChoices[string.lower(item.Name)] = item
    table.insert(core.fontOptionNames, item.Name)
end
table.sort(core.fontOptionNames, function(a, b)
    if a == "Auto" then
        return true
    elseif b == "Auto" then
        return false
    end
    return a < b
end)

-- Same family, a different weight - Font.fromEnum only ever gives the enum's own default
-- weight, so re-derive a Font at the weight we actually want from its family name instead.
function core.fontAtWeight(enumFont: Enum.Font, weight: Enum.FontWeight): Font
    return Font.new(Font.fromEnum(enumFont).Family, weight)
end

-- Keys that drive a UIGradient and so want a ColorSequence. A dev may pass a plain Color3 for
-- any of these and we widen it to a flat sequence, so a theme reads the same either way.
core.gradientKeys = {
    WindowColor = true,
    ElementGradient = true,
    ElementStrokeGradient = true,
    TabBackground = true,
    TabStroke = true,
    SliderProgress = true,
}

function core.coerceThemeValue(key, value)
    if core.gradientKeys[key] and typeof(value) == "Color3" then
        return ColorSequence.new(value)
    end
    return value
end

function core.firstColor(value)
    return if typeof(value) == "ColorSequence" then value.Keypoints[1].Value else value
end

-- A subtle raised edge for a fill: lighten a dark fill, darken a light one.
function core.edgeShade(color, amount)
    local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    local target = if luminance > 0.5 then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
    return color:Lerp(target, amount)
end

-- Give a custom theme sensible strokes for free: when it recolours a surface but leaves the
-- matching stroke unset, derive one from the fill so a colours-only theme still reads coherently.
function core.deriveStrokes(resolved, overrides)
    if overrides.ElementGradient then
        local fill = core.firstColor(resolved.ElementGradient)
        if overrides.ElementStroke == nil then
            resolved.ElementStroke = core.edgeShade(fill, 0.28)
        end
        if overrides.ElementStrokeGradient == nil then
            resolved.ElementStrokeGradient = ColorSequence.new(core.edgeShade(fill, 0.4))
        end
        if overrides.ElementStrokeHover == nil then
            resolved.ElementStrokeHover = core.edgeShade(fill, 0.52)
        end
    end
    if overrides.TabBackground and overrides.TabStroke == nil then
        resolved.TabStroke = ColorSequence.new(core.edgeShade(core.firstColor(resolved.TabBackground), 0.4))
    end
end

-- Resolve a theme arg to its raw key set: a table is taken as-is (partial is fine), a known
-- name is required, anything else falls back to default. Read-only - callers never mutate it,
-- so the require()-cached module stays clean for other windows.
function core.themeOverrides(value)
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
function core.resolveTheme(value)
    local resolved = table.clone(require(themes["default"]))
    local overrides = core.themeOverrides(value)
    for key, override in overrides do
        resolved[key] = core.coerceThemeValue(key, override)
    end
    -- only a hand-written table gets derived strokes; a named built-in ships its own.
    if typeof(value) == "table" then
        core.deriveStrokes(resolved, overrides)
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

-- Singleton window registry, keyed by window name. Deliberately lives in _G rather than a plain
-- module-local: a dev-loader/executor re-run of the whole script rebuilds this entire file as a
-- brand new module (fresh table, fresh Window class) - a module-local would forget every window
-- from the previous run instantly. _G is the one thing that actually survives that boundary, the
-- same trick a hot-reloaded hub script needs for its own UI. See Window.new's own use of this
-- for what it's for: auto-unloading a same-named window left over from an earlier run, so
-- re-running a script twice can't leave its old window's connections leaking forever (exactly
-- the "zombie window" failure mode this project's own dev workflow kept hitting by hand).
core.WINDOW_REGISTRY_KEY = "__RayfieldGen3WindowRegistry"

function core.windowRegistry()
    local reg = _G[core.WINDOW_REGISTRY_KEY]
    if typeof(reg) ~= "table" then
        reg = {}
        _G[core.WINDOW_REGISTRY_KEY] = reg
    end
    return reg
end

return core

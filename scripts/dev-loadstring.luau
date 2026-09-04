-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Dev-only loadstring bootstrap. Rebuilds src/ as a real module tree straight from this repo's
-- GitHub raw content (no Rojo/Studio needed) and runs one of the example scripts against it, so
-- a change can be pushed and eyeballed in a real client in the time it takes to re-run one line.
--
-- Usage, from any executor:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/opploop/67676767/main/scripts/dev-loadstring.luau"))()
--
-- Pass a config table to point at a different example, branch, or repo:
--   loadstring(...)({ example = "example.client.luau", branch = "some-branch" })
--
-- Not part of the CI/build pipeline (no Makefile target wraps it) and not meant to ship - it's a
-- fast feedback loop for the *contents* of a branch while iterating, standing in for `make bundle`
-- + a real Rojo/Studio session. Use those (see CONTRIBUTING.md) for anything going into a PR.

-- runs directly at the chunk's top level (not wrapped in a returned function) so a plain single
-- call - loadstring(...)() - both loads *and* runs it; a config table just arrives as `...`
local config = ...
config = if typeof(config) == "table" then config else {}

local owner = config.owner or "opploop"
local repo = config.repo or "67676767"
local branch = config.branch or "main"
local example = config.example or "example.gen3.client.luau"

local REPO_RAW = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(owner, repo, branch)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = ReplicatedStorage:FindFirstChild("Rayfield")
if existing then
    existing:Destroy()
end

local function fetch(path)
    local ok, body = pcall(function()
        return game:HttpGet(REPO_RAW .. path, true)
    end)
    if not ok or type(body) ~= "string" or #body == 0 then
        warn("Rayfield dev loader: failed to fetch " .. path .. " - " .. tostring(body))
        return ""
    end
    return body
end

local function makeModule(name, parent, source)
    local m = Instance.new("ModuleScript")
    m.Name = name
    m.Source = source
    m.Parent = parent
    return m
end

local function makeFolder(name, parent)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

print(("Rayfield dev loader: fetching source from %s/%s (%s)..."):format(owner, repo, branch))

local Rayfield = makeModule("Rayfield", ReplicatedStorage, fetch("src/init.luau"))
makeModule("types", Rayfield, fetch("src/types.luau"))

local components = makeFolder("components", Rayfield)
local componentFiles = {
    "action",
    "button",
    "changelog",
    "checkbox",
    "chrome",
    "collapsible",
    "colorpicker",
    "console",
    "copybutton",
    "descriptor",
    "divider",
    "drag",
    "dropdown",
    "flipbutton",
    "gradientpicker",
    "group",
    "holdbutton",
    "hud",
    "input",
    "keybind",
    "label",
    "notification",
    "paragraph",
    "popup",
    "progressbar",
    "resize",
    "ripplebutton",
    "scrollhint",
    "search",
    "section",
    "segmentedpicker",
    "shimmerlabel",
    "slider",
    "spacer",
    "stat",
    "statuscard",
    "tab",
    "tabSection",
    "tag",
    "tabbox",
    "toast",
    "toggle",
    "tour",
    "window",
    "windowCore",
    "windowExtra",
    "windowMethods",
}
for _, name in componentFiles do
    makeModule(name, components, fetch("src/components/" .. name .. ".luau"))
end

local themes = makeFolder("themes", Rayfield)
local themeFiles =
    { "amethyst", "cobalt", "default", "ember", "emerald", "frost", "highcontrast", "midnight", "ocean", "rose" }
for _, name in themeFiles do
    makeModule(name, themes, fetch("src/themes/" .. name .. ".luau"))
end

local utility = makeFolder("utility", Rayfield)
local utilityFiles = {
    "acrylic",
    "assetResolver",
    "autoTranslate",
    "builtinLocales",
    "clipboard",
    "colors",
    "constants",
    "enums",
    "filesystem",
    "filesystemManager",
    "flagNames",
    "fontManager",
    "functions",
    "HapticEngine",
    "hsvEditor",
    "icons",
    "image",
    "imageCache",
    "locale",
    "lockable",
    "log",
    "moveable",
    "network",
    "odometer",
    "ordering",
    "path",
    "persistence",
    "persistenceConfig",
    "persistencePaths",
    "persistenceSettings",
    "persistenceWrite",
    "runtime",
    "services",
    "sound",
    "squircle",
    "textMetrics",
    "variables",
    "windowSizing",
}
for _, name in utilityFiles do
    makeModule(name, utility, fetch("src/utility/" .. name .. ".luau"))
end

print("Rayfield dev loader: source tree built, loading...")

-- Executors report only a generic "module experienced an error" for a freshly Source-
-- injected ModuleScript's native require(), with no way to see the real error. Load with
-- our own loadstring-based require instead, so a real failure actually tells us where.
local requireCache = {}
local function customRequire(moduleScript)
    if requireCache[moduleScript] ~= nil then
        return requireCache[moduleScript]
    end
    local f, loadErr = loadstring(moduleScript.Source, moduleScript:GetFullName())
    if not f then
        error(("%s: loadstring failed - %s"):format(moduleScript:GetFullName(), tostring(loadErr)), 0)
    end
    local env = setmetatable({
        script = moduleScript,
        require = customRequire,
    }, { __index = getfenv() })
    setfenv(f, env)
    local result = f()
    requireCache[moduleScript] = result
    return result
end

local ok, err = pcall(customRequire, Rayfield)
if not ok then
    warn("Rayfield dev loader: require failed - " .. tostring(err))
    return
end

print("Rayfield dev loader: Rayfield loaded OK, fetching+running " .. example .. "...")

local exampleSource = fetch(example)
local exampleFn, exampleLoadErr = loadstring(exampleSource, example)
if not exampleFn then
    warn("Rayfield dev loader: example loadstring failed - " .. tostring(exampleLoadErr))
    return
end

-- the example does `require(ReplicatedStorage.Rayfield)` itself; feed it the same
-- loadstring-based require so it warms straight off the already-built module tree.
setfenv(exampleFn, setmetatable({ require = customRequire }, { __index = getfenv() }))

local exampleOk, exampleErr = pcall(exampleFn)
if not exampleOk then
    warn("Rayfield dev loader: example failed - " .. tostring(exampleErr))
else
    print("Rayfield dev loader: done, no errors.")
end

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Production loader. The single thing a real hub script needs to fetch and require the
-- library, with no repo/file-list boilerplate of its own - all of that (owner, repo, the
-- full component/theme/utility file lists, the module-tree build, the executor-safe
-- customRequire) lives here, once, instead of copy-pasted into every hub.
--
-- Usage from a hub script - no arguments needed, always tracks `main`:
--   local Rayfield = loadstring(game:HttpGet(
--       "https://raw.githubusercontent.com/opploop/67676767/main/scripts/loader.luau"
--   ))()
--
-- Pass a commit SHA or branch name instead if you specifically want to pin a shipped hub
-- to a version that won't move under it later:
--   loadstring(...)("<40-char commit SHA>")

local ref = ...
if type(ref) ~= "string" or #ref == 0 then
    ref = "main"
end

local owner = "opploop"
local repo = "67676767"

local REPO_RAW = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(owner, repo, ref)

local function fetch(path)
    local ok, body = pcall(function()
        return game:HttpGet(REPO_RAW .. path, true)
    end)
    if not ok or type(body) ~= "string" or #body == 0 then
        error("Rayfield loader: failed to fetch " .. path .. " - " .. tostring(body), 0)
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = ReplicatedStorage:FindFirstChild("Rayfield")
if existing then
    existing:Destroy()
end

local componentFiles = {
    "action", "button", "changelog", "checkbox", "chrome", "collapsible", "colorpicker",
    "console", "copybutton", "descriptor", "divider", "drag", "dropdown", "flipbutton", "gradientpicker",
    "group", "holdbutton", "hud", "input", "keybind", "label", "notification", "paragraph",
    "popup", "progressbar", "resize", "ripplebutton", "scrollhint", "search", "section",
    "segmentedpicker", "shimmerlabel", "slider", "spacer", "stat", "statuscard", "tab", "tabSection", "tabSelector", "tag", "tabbox",
    "toast", "toggle", "tour", "window", "windowCore", "windowExtra", "windowMethods",
}

local themeFiles = {
    "amethyst", "cobalt", "default", "ember", "emerald", "frost", "highcontrast",
    "midnight", "ocean", "rose",
}

local utilityFiles = {
    "acrylic", "assetResolver", "autoTranslate", "builtinLocales", "clipboard", "colors",
    "constants", "enums", "filesystem", "filesystemManager", "flagNames", "fontManager",
    "functions", "HapticEngine", "hsvEditor", "icons", "image", "imageCache", "locale",
    "lockable", "log", "moveable", "network", "odometer", "ordering", "path", "persistence",
    "persistenceConfig", "persistencePaths", "persistenceSettings", "persistenceWrite",
    "runtime", "services", "sound", "squircle", "textMetrics", "variables", "windowSizing",
}

-- Every file this needs, as one flat list, so they can all be in flight at once. Fetched
-- sequentially this was ~95 blocking round trips back to back - the single biggest chunk of the
-- "why does it take so long to appear" wait, and none of them depend on each other.
local requests = {
    { path = "src/init.luau", key = "init" },
    { path = "src/types.luau", key = "types" },
}
for _, name in componentFiles do
    table.insert(requests, { path = "src/components/" .. name .. ".luau", key = "components/" .. name })
end
for _, name in themeFiles do
    table.insert(requests, { path = "src/themes/" .. name .. ".luau", key = "themes/" .. name })
end
for _, name in utilityFiles do
    table.insert(requests, { path = "src/utility/" .. name .. ".luau", key = "utility/" .. name })
end

-- How many fetches are allowed in flight at once. High enough to collapse the wait into a
-- handful of round trips, low enough that an executor's own HTTP layer (and GitHub's rate
-- limiting) doesn't start refusing them.
local concurrency = 12

local sources = {}
local nextIndex = 1
local finished = 0
local failure = nil

local function worker()
    while true do
        local index = nextIndex
        nextIndex += 1
        local request = requests[index]
        if not request then
            return
        end

        local ok, body = pcall(fetch, request.path)
        if ok then
            sources[request.key] = body
        elseif not failure then
            failure = body -- first error wins; the rest are usually the same cause
        end
        finished += 1
    end
end

for _ = 1, math.min(concurrency, #requests) do
    task.spawn(worker)
end

while finished < #requests do
    task.wait()
end

if failure then
    error(failure, 0)
end

local RayfieldModule = makeModule("Rayfield", ReplicatedStorage, sources["init"])
makeModule("types", RayfieldModule, sources["types"])

local components = makeFolder("components", RayfieldModule)
for _, name in componentFiles do
    makeModule(name, components, sources["components/" .. name])
end

local themes = makeFolder("themes", RayfieldModule)
for _, name in themeFiles do
    makeModule(name, themes, sources["themes/" .. name])
end

local utility = makeFolder("utility", RayfieldModule)
for _, name in utilityFiles do
    makeModule(name, utility, sources["utility/" .. name])
end

-- Native require() on a freshly Source-injected ModuleScript only ever reports "Requested
-- module experienced an error while loading" - no file, no line, nothing to act on. Load
-- through our own loadstring-based require instead, so a real compile/runtime error in
-- Rayfield's own source actually surfaces here. See 01_ARCHITECTURE.md for why.
local requireCache = {}
local function customRequire(moduleScript)
    if requireCache[moduleScript] ~= nil then
        return requireCache[moduleScript]
    end
    local chunk, compileErr = loadstring(moduleScript.Source, moduleScript:GetFullName())
    if not chunk then
        error(("%s: loadstring failed - %s"):format(moduleScript:GetFullName(), tostring(compileErr)), 0)
    end
    local env = setmetatable({ script = moduleScript, require = customRequire }, { __index = getfenv() })
    setfenv(chunk, env)
    local result = chunk()
    requireCache[moduleScript] = result
    return result
end

return customRequire(RayfieldModule)

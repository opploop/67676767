#!/usr/bin/env bash
# Copyright (c) 2026 Corridon Capital
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Bundles every file under src/ into one loadable Lua file at dist/rayfield.lua.
#
# Why: the normal loader (scripts/loader.luau) fetches ~95 files over HTTP. Even fetching them
# 12-at-a-time that's a real chunk of the wait before a hub's window can appear; the bundle is
# one request instead. A hub loads it exactly like the loader:
#
#   local Rayfield = loadstring(game:HttpGet(
#       "https://raw.githubusercontent.com/opploop/67676767/main/dist/rayfield.lua"
#   ))()
#
# Run this (and commit dist/rayfield.lua) whenever src/ changes - a stale bundle is the same
# class of problem a stale commit pin used to be, just quieter, so treat it as part of shipping
# rather than an optional extra:
#
#   bash scripts/build-bundle.sh
#
# The generated file embeds each module's source in a long string and rebuilds a small virtual
# module tree at runtime, so `script.Parent.x` / `script.Parent.Parent.utility.y` navigation and
# the loadstring-based require behave exactly like they do against the real ModuleScript tree.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="dist/rayfield.lua"
mkdir -p dist

# Long-bracket level chosen so no source can accidentally close its own string. Verified: no
# file under src/ contains this sequence.
BRACKET_OPEN="[=====["
BRACKET_CLOSE="]=====]"

if grep -rqF "$BRACKET_CLOSE" src/; then
    echo "error: a file under src/ contains $BRACKET_CLOSE - bump the bracket level in this script" >&2
    exit 1
fi

{
    echo "-- Rayfield Gen2 Modded - generated bundle, do not edit by hand."
    echo "-- Built from src/ by scripts/build-bundle.sh. Rebuild after any src/ change."
    echo ""
    echo "local sources = {}"
    echo ""
} > "$OUT"

# module key = path under src/ without the .luau extension ("init", "components/window", ...)
while IFS= read -r file; do
    key="${file#src/}"
    key="${key%.luau}"
    {
        printf 'sources["%s"] = %s\n' "$key" "$BRACKET_OPEN"
        cat "$file"
        printf '%s\n\n' "$BRACKET_CLOSE"
    } >> "$OUT"
done < <(find src -name "*.luau" | sort)

cat >> "$OUT" <<'RUNTIME'
-- Virtual module tree. Each node stands in for a ModuleScript/Folder: it answers Name, Parent,
-- GetFullName() and child lookups by name, which is every shape src/ actually navigates with
-- (script.Parent.x, script.Parent.Parent.utility.y, script.Parent[name]).
local nodes = {}

local function isFolder(path)
    local prefix = path .. "/"
    for key in sources do
        if string.sub(key, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function node(path)
    local existing = nodes[path]
    if existing then
        return existing
    end

    local name = string.match(path, "[^/]+$") or "Rayfield"
    if path == "init" then
        name = "Rayfield"
    end

    local self = {}
    nodes[path] = self

    setmetatable(self, {
        __index = function(_, key)
            if key == "Name" then
                return name
            elseif key == "Parent" then
                local parent = string.match(path, "^(.*)/[^/]+$")
                -- a top-level module/folder's parent is the root module itself
                return node(parent or "init")
            elseif key == "GetFullName" then
                return function()
                    return "Rayfield." .. string.gsub(path, "/", ".")
                end
            end

            -- child by name: a module first, then a folder
            local base = if path == "init" then "" else path .. "/"
            local childPath = base .. tostring(key)
            if sources[childPath] or isFolder(childPath) then
                return node(childPath)
            end
            return nil
        end,
    })

    return self
end

-- Same loadstring-based require the file-by-file loader uses, for the same reason: a native
-- require() on injected source reports only "module experienced an error while loading", with no
-- file and no line to act on.
local cache = {}
local function customRequire(target)
    -- a real Instance can still reach this if a consumer passes one in; only virtual nodes here
    local path
    for candidate, built in nodes do
        if built == target then
            path = candidate
            break
        end
    end
    if not path then
        error("Rayfield bundle: require() called with something outside the bundle", 0)
    end

    if cache[path] ~= nil then
        return cache[path]
    end

    local source = sources[path]
    if not source then
        error(("Rayfield bundle: no module at '%s'"):format(path), 0)
    end

    local chunk, compileErr = loadstring(source, "Rayfield." .. string.gsub(path, "/", "."))
    if not chunk then
        error(("Rayfield.%s: loadstring failed - %s"):format(string.gsub(path, "/", "."), tostring(compileErr)), 0)
    end

    local env = setmetatable({ script = target, require = customRequire }, { __index = getfenv() })
    setfenv(chunk, env)
    local result = chunk()
    cache[path] = result
    return result
end

return customRequire(node("init"))
RUNTIME

echo "built $OUT ($(wc -c < "$OUT") bytes, $(find src -name '*.luau' | wc -l) modules)"

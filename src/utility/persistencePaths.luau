--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local variables = require(script.Parent.variables)
local path = require(script.Parent.path)

local paths = {}

type ConfigWindow = {
    configuration: {
        fileName: string?,
        customFolder: string?,
        scopeByPlace: boolean?,
    },
    name: string,
}

-- PlaceId, or a Studio-safe stand-in (PlaceId reads 0 there) built from GameId instead - so
-- scopeByPlace still gives distinct, stable folders per Studio place rather than every one of
-- them colliding on the same "0".
local function placeFolderName(): string
    if game.PlaceId ~= 0 then
        return tostring(game.PlaceId)
    end
    return "Studio_" .. tostring(game.GameId)
end

function paths.getConfigPath(window: ConfigWindow, name: unknown?): (string, string)
    local dir = variables.fileSystemManager:getPath("Configurations")
    if window.configuration.customFolder then
        dir = path.join(dir, path.sanitizeFolder(window.configuration.customFolder))
    end
    -- scopeByPlace: nests one folder deeper per game/place, so a multi-place experience (or a
    -- hub-style script reused across several games) never mixes one place's saved configs into
    -- another's just because they happened to share a fileName/customFolder. Opt-in (see its own
    -- WindowProps comment) rather than the default, since flipping it on for an existing window
    -- would silently orphan whatever was already saved at the old, unscoped path.
    if window.configuration.scopeByPlace then
        dir = path.join(dir, path.sanitizeFolder(placeFolderName()))
    end
    local base = name or window.configuration.fileName or window.name
    local safe = path.sanitizeFile(base)
    if safe == "" then
        safe = path.sanitizeFile(window.name)
    end
    if safe == "" then
        safe = "Configuration"
    end
    return dir, path.join(dir, safe .. ".rfld")
end

function paths.getSettingsPath(): (string, string)
    local dir = variables.fileSystemManager:getPath("Settings")
    return dir, path.join(dir, "rayfield.rfld")
end

return paths

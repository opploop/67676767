--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local imageCache = require(script.Parent.imageCache)
local variables = require(script.Parent.variables)
local icons = require(script.Parent.icons)
local log = require(script.Parent.log)

type AvatarCallback = imageCache.AvatarCallback
type PreloadCallback = imageCache.PreloadCallback

local image = {}

image.rewrites = imageCache.rewrites
image.onBlock = nil :: ((unknown) -> ())?

-- images that resolve blank in secure mode (their icon isnt cached yet) register here, so the real
-- texture can be dropped in once the background download lands instead of leaving a blank. keyed by
-- instance so re-assigning the same icon cant stack up, and weakly so a destroyed one isnt pinned
type PendingProperties = { [string]: boolean }

image.pending = {} :: { [number]: { [Instance]: PendingProperties } }

-- once preload settles nothing else will ever land, so theres nothing left worth tracking
local settled = false

local imageProperties: { [string]: boolean } = {
    Image = true,
    HoverImage = true,
    PressedImage = true,
}

-- An icon string that looks like a pack lookup but doesn't resolve renders as nothing at all,
-- with no error anywhere - live-caught more than once as "the icon just isn't showing" with no
-- way to tell a typo from a dead pack. Warned once per distinct string so a whole tab list of
-- the same bad name doesn't flood the console.
local warnedIcons: { [string]: boolean } = {}
local function warnUnresolvedIcon(value: string, reason: string)
    if warnedIcons[value] then
        return
    end
    warnedIcons[value] = true
    log.warn(("Rayfield: icon '%s' didn't resolve - %s"):format(value, reason))
end

local function idOf(value: unknown): number?
    if type(value) == "number" then
        return value
    elseif type(value) == "string" then
        return tonumber(string.match(value, "^rbxassetid://(%d+)$"))
    end
    return nil
end

local function blocked(value: unknown): string
    if image.onBlock then
        image.onBlock(value)
    end
    return ""
end

function image.preload(onSettled: PreloadCallback?): (boolean, number)
    settled = false
    return imageCache.preload(function(failed)
        -- everything that cached has already rebound through onCached, and everything else never
        -- will, so drop whats left and stop tracking rather than growing all session
        settled = true
        table.clear(image.pending)
        if onSettled then
            onSettled(failed)
        end
    end)
end

function image.avatar(userId: number, onReady: AvatarCallback?): string
    if not variables.secureMode then
        return `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48`
    end

    return imageCache.avatar(userId, onReady)
end

function image.assign(instance: Instance, property: string, value: unknown)
    local target = instance :: any
    if not imageProperties[property] then
        target[property] = value
        return
    end
    target[property] = image.resolve(value)
    -- in secure mode an un-cached icon resolves blank; remember it so it appears once cached
    if variables.secureMode and not settled then
        local id = idOf(value)
        if id and not image.rewrites[id] then
            local waiting = image.pending[id]
            if not waiting then
                waiting = setmetatable({}, { __mode = "k" }) :: any
                image.pending[id] = waiting
            end
            local properties = waiting[instance]
            if not properties then
                properties = {}
                waiting[instance] = properties
            end
            properties[property] = true
        end
    end
end

-- imageCache calls this when a background icon download lands: drop the real texture into every
-- instance that resolved blank waiting for it
imageCache.onCached = function(id: number)
    local waiting = image.pending[id]
    if not waiting then
        return
    end
    local uri = image.rewrites[id]
    if uri then
        for instance, properties in waiting do
            if instance.Parent then
                local target = instance :: any
                for property in properties do
                    target[property] = uri
                end
            end
        end
    end
    image.pending[id] = nil
end

function image.resolve(value: unknown): string
    if value == nil or value == 0 or value == "" then
        return ""
    end

    if type(value) == "string" then
        if string.sub(value, 1, 11) == "rbxasset://" then
            return value
        end
        if string.sub(value, 1, 11) == "rbxthumb://" then
            return if variables.secureMode then blocked(value) else value
        end
        -- "pack:icon-name" (e.g. "lucide:lock") - a community icon pack lookup (see icons.luau).
        -- Only ever resolves a *flat*-format pack's icon this way (lucide/solar/sfsymbols/
        -- gravity - each already a plain rbxassetid, nothing else to set); a spritesheet pack's
        -- icon (geist/craft) also needs ImageRectSize/Offset set alongside Image, which this
        -- single-string return can't carry - use icons.apply() directly for those instead.
        -- Falls through to the plain-string case below on any miss (unknown pack/name, pack
        -- fetch failed, ...), which just resolves to the string as-is - a caller passing a real
        -- rbxassetid://... never round-trips through here to begin with.
        local packName, iconName = string.match(value, "^(%a+):([%w%-_]+)$")
        if packName then
            if not icons.packNames[packName] then
                warnUnresolvedIcon(value, ("unknown icon pack '%s'"):format(packName))
            else
                local found = icons.find(iconName, packName)
                if found and not found.ImageRectSize then
                    return found.Image
                end
                if found then
                    -- a spritesheet pack's icon can't come back as a single string - see above
                    warnUnresolvedIcon(
                        value,
                        ("'%s' is a spritesheet pack; use icons.apply() rather than an icon string"):format(packName)
                    )
                else
                    warnUnresolvedIcon(value, ("no icon named '%s' in '%s'"):format(iconName, packName))
                end
            end
        end
    end

    local id: number? = nil
    if type(value) == "number" then
        id = value
    elseif type(value) == "string" then
        id = tonumber(string.match(value, "^rbxassetid://(%d+)$"))
    end

    local rewrite = if id then image.rewrites[id] else nil
    if rewrite then
        return rewrite
    end

    if variables.secureMode then
        return blocked(value)
    end

    if type(value) == "number" then
        return "rbxassetid://" .. value
    end
    if type(value) == "string" then
        return value
    end

    return blocked(value)
end

return image

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Community icon packs (github.com/Footagesus/Icons - the same source WindUI uses), fetched the
-- same way every other dev-loadstring asset in this codebase is: a plain HttpGet + loadstring,
-- no server script or RemoteFunction involved (unlike WindUI's own loader, which leans on a
-- server-side Script to hand icons to clients over a RemoteFunction - real for a dev who owns
-- the game and can add one via Studio, but nothing an executor-injected library like this one
-- can stand up in someone else's game). Each pack is ~18k icons combined; fetched lazily (only
-- the packs actually asked for) and cached per pack after the first successful fetch.
--
-- Two on-disk shapes exist upstream, both handled transparently by find():
--   flat:        { [iconName] = "rbxassetid://..." }                      (lucide, solar, sfsymbols, gravity)
--   spritesheet: { Icons = { [iconName] = { Image, ImageRectSize, ImageRectPosition } }, Spritesheets = {...} }  (geist, craft)

local icons = {}

local baseUrl = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/"

icons.packNames = {
    lucide = true,
    solar = true,
    sfsymbols = true,
    gravity = true,
    geist = true,
    craft = true,
}

export type IconEntry = {
    Image: string,
    ImageRectSize: Vector2?,
    ImageRectOffset: Vector2?,
}

local cache: { [string]: any } = {} -- pack -> the raw decoded table, or false if fetching it failed
local attempted: { [string]: boolean } = {}

-- Fetches and loadstring()s one pack's data file. Synchronous (HttpGet yields the calling
-- thread, same tradeoff every other dev-loadstring fetch in this codebase already makes) - only
-- ever pays that cost once per pack per session, on whichever call happens to ask for it first.
local function fetchPack(pack: string): any
    if cache[pack] ~= nil then
        return cache[pack] or nil
    end
    if attempted[pack] then
        return nil
    end
    attempted[pack] = true

    local ok, result = pcall(function()
        local code = game:HttpGet(baseUrl .. pack .. "/dist/Icons.lua", true)
        local fn = loadstring(code)
        assert(fn, "loadstring failed")
        return fn()
    end)

    if ok and typeof(result) == "table" then
        cache[pack] = result
        return result
    end

    cache[pack] = false -- remembered so a dead pack/repo doesn't retry a fetch every lookup
    return nil
end

-- Looks up one icon, normalized to the same shape regardless of which on-disk format its pack
-- uses. Returns nil if the pack name is unknown, its fetch failed, or the icon isn't in it -
-- callers should have a plain fallback ready (a built-in rbxassetid, or draw one from Frames)
-- rather than assume this always succeeds, since it depends on a third-party repo staying up.
function icons.find(name: string, pack: string?): IconEntry?
    pack = pack or "lucide"
    if not icons.packNames[pack] then
        return nil
    end

    local data = fetchPack(pack)
    if not data then
        return nil
    end

    if data.Icons then
        local entry = data.Icons[name]
        if not entry or not entry.Image then
            return nil
        end
        return {
            Image = entry.Image,
            ImageRectSize = entry.ImageRectSize,
            ImageRectOffset = entry.ImageRectPosition,
        }
    end

    local raw = data[name]
    if typeof(raw) ~= "string" then
        return nil
    end
    return { Image = raw }
end

-- Applies an icon by name straight onto an existing ImageLabel/ImageButton, including the rect
-- properties a spritesheet pack's icon needs (harmlessly zeroed for a flat-pack icon, which
-- doesn't use them). Returns false (and leaves the instance untouched) if the icon couldn't be
-- resolved, so a caller can fall back to whatever it already had.
function icons.apply(instance: Instance, name: string, pack: string?): boolean
    local entry = icons.find(name, pack)
    if not entry then
        return false
    end
    local target = instance :: any
    target.Image = entry.Image
    target.ImageRectSize = entry.ImageRectSize or Vector2.new(0, 0)
    target.ImageRectOffset = entry.ImageRectOffset or Vector2.new(0, 0)
    return true
end

return icons

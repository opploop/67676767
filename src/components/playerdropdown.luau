--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A Dropdown whose options are the players in the server, kept in step with joins and leaves.
--
-- This is not a new element - it builds a real Dropdown and hands it straight back, so every
-- Dropdown method, flag, and behaviour applies unchanged. All it adds is the wiring every hub
-- was writing by hand: fill the options from Players, refresh on PlayerAdded/PlayerRemoving,
-- and keep a label -> Player map so a selection can be turned back into the actual instances
-- (a display-name label has no way back to a Player on its own, and even a plain Name lookup
-- is a FindFirstChild the caller shouldn't have to remember to guard).
--
-- Refreshes are deferred and coalesced: a fresh server fires PlayerAdded once per player in a
-- burst, and rebuilding the option list once per event would rebuild it a dozen times for one
-- visible change.

local dropdown = require(script.Parent.dropdown)

local playersService = game:GetService("Players")

local playerDropdown = {}

-- "name" (default) is what code actually needs - a display name is not unique and not a lookup
-- key. The other two exist for the cases where a player picks from this list and wants to read
-- the name they see in-game.
local function labelFor(player: Player, format: string): string
    if format == "display" then
        return player.DisplayName
    elseif format == "both" then
        -- DisplayName already equals Name for accounts that never set one; showing "x (@x)"
        -- there is just noise
        if player.DisplayName == player.Name then
            return player.Name
        end
        return `{player.DisplayName} (@{player.Name})`
    end
    return player.Name
end

function playerDropdown.new(host, properties)
    properties = if typeof(properties) == "table" then table.clone(properties) else {}

    local format = properties.format or properties.Format or "name"
    local includeSelf = properties.includeSelf
    if includeSelf == nil then
        includeSelf = properties.IncludeSelf
    end
    if includeSelf == nil then
        includeSelf = true
    end

    -- these are ours, not the Dropdown's; leaving them in the table would just be dead keys
    properties.format, properties.Format = nil, nil
    properties.includeSelf, properties.IncludeSelf = nil, nil

    properties.name = properties.name or properties.Name or "Player"
    properties.options = nil -- ours to fill; a caller-supplied list would be overwritten anyway
    properties.Options = nil

    local element

    local function collect()
        local options, byOption = {}, {}
        for _, player in playersService:GetPlayers() do
            if includeSelf or player ~= playersService.LocalPlayer then
                local label = labelFor(player, format)
                table.insert(options, label)
                byOption[label] = player
            end
        end
        -- case-insensitively: a plain table.sort is byte order, which files every capitalised
        -- name above every lowercase one ("Nick, kevin, say, templar") and reads as unsorted
        table.sort(options, function(left, right)
            local a, b = string.lower(left), string.lower(right)
            if a == b then
                return left < right
            end
            return a < b
        end)
        return options, byOption
    end

    local initialOptions, initialByOption = collect()
    properties.options = initialOptions

    element = dropdown.new(host, properties)
    element._playerByOption = initialByOption

    -- Rebuild the option list from the current server. Dropdown:Refresh re-derives the
    -- selection from the full intent, so someone who left and came back keeps their pick.
    function element:RefreshPlayers()
        local options, byOption = collect()
        self._playerByOption = byOption
        self:Refresh(options)
        return options
    end

    -- The selection as actual Player instances, skipping anyone who left between the pick and
    -- this call. Always an array, matching Dropdown.value being one even in single-select.
    function element:GetSelectedPlayers(): { Player }
        local players = {}
        for _, option in self.value do
            local player = self._playerByOption[option]
            -- a player can leave between the refresh and this call, so re-check parentage
            -- rather than trusting the map alone
            if player and player.Parent then
                table.insert(players, player)
            end
        end
        return players
    end

    -- Tab:Remove/teardownElements disconnects an element's ConnectFor connections and clears
    -- element.connections, so a nil there is the signal that this element is gone - checked in
    -- the deferred body because the element can be torn down between the event and the defer.
    local function isAlive()
        return not host.window.unloaded and element.connections ~= nil
    end

    local queued = false
    local function queueRefresh()
        if queued then
            return
        end
        queued = true
        task.defer(function()
            queued = false
            if isAlive() then
                element:RefreshPlayers()
            end
        end)
    end

    -- ConnectFor, not Connect: these die with the element, so a Tab:Remove or a rebuilt page
    -- doesn't leave two listeners refreshing a dropdown that no longer exists.
    host.window:ConnectFor(element, playersService.PlayerAdded, queueRefresh)
    host.window:ConnectFor(element, playersService.PlayerRemoving, queueRefresh)

    return element
end

return playerDropdown

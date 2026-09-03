--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Sound feedback. Same shape as HapticEngine.luau on purpose (enabled flag, setEnabled,
-- setContainer/releaseContainer, a click() and a notify()) - the two are siblings, not the same
-- system: a player might want a tap without a sound, or a sound without a tap, so they stay on
-- separate settings toggles rather than one "feedback" switch deciding both.
--
-- Uses rbxasset:// sounds, not rbxassetid:// - these ship inside the Roblox client itself, so
-- there's no network fetch and no risk of a moderated/deleted/wrong asset id. That risk is not
-- theoretical on this project: the resize grip's own glyph (see resize.luau's header comment)
-- took several rounds of live debugging over a single bad-fitting rbxassetid image. A sound
-- that silently 404s is much harder to notice than an icon that renders wrong, so rbxasset://
-- is the safer default here even though it means picking from Roblox's smaller built-in set
-- rather than a custom SFX pack.

local services = require(script.Parent.services)
local variables = require(script.Parent.variables)

local sound = {}

sound.enabled = false -- off by default; the settings toggle flips it (see setEnabled) - same
-- opt-in-only default HapticEngine uses, for the same reason: a supplementary sense a player
-- didn't ask for shouldn't just start firing the moment a window opens.

-- Verified live (Sound.IsLoaded + TimeLength, not just a successful pcall - PreloadAsync/loadstring
-- both happily "succeed" on a bad rbxasset:// path and only the actual Sound reports it never
-- loaded) that both of these genuinely exist on-client: electronicpingshort.wav (0.72s) and
-- button.wav (0.576s). bell.wav, tried first for notify, does not - IsLoaded stayed false,
-- TimeLength 0, and a real "Failed to load sound... Temp read failed" landed in the console the
-- moment it actually tried to play, live-caught on the very first post-fix reload.
local assets = {
    click = "rbxasset://sounds/electronicpingshort.wav", -- press/switch/tab - short, soft tick
    notify = "rbxasset://sounds/button.wav", -- toast/popup/notification - a touch more weight
}

local volume = 0.35

local container: Instance? = nil

-- Where new Sound instances get parented. Same pattern as HapticEngine.setContainer - the
-- window hands us its ScreenGui; until then (or after it goes away) fall back to the container
-- every Rayfield gui lives in, so a click before a window finishes constructing doesn't error.
function sound.setContainer(target: Instance?)
    container = target
end

function sound.releaseContainer(target: Instance?)
    if target == nil or container == target then
        container = nil
    end
end

local function containerFor(): Instance
    if container and container.Parent then
        return container
    end
    return variables.guiContainer
end

local function play(assetId: string?)
    if not assetId or not sound.enabled then
        return
    end
    local ok = pcall(function()
        local instance = Instance.new("Sound")
        instance.SoundId = assetId
        instance.Volume = volume
        instance.Parent = containerFor()
        -- self-destroying one-shot rather than a pooled/reused Sound (unlike HapticEngine's
        -- pooled HapticEffect) - overlapping clicks (a fast double-toggle, several rows in a
        -- row) need their own independent instances to actually layer instead of one cutting
        -- the last one off, and a UI click is cheap enough to not need pooling.
        instance.Ended:Once(function()
            instance:Destroy()
        end)
        instance:Play()
        -- safety net in case Ended never fires (SoundId fails to load, instance gets orphaned) -
        -- nothing here should ever run longer than a couple seconds.
        task.delay(3, function()
            if instance.Parent then
                instance:Destroy()
            end
        end)
    end)
    if not ok then
        return
    end
end

-- tap for a button, switch, tab or any discrete press - mirrors hapticEngine.click()'s own
-- call sites 1:1, so anywhere haptics fires, sound is available to fire alongside it.
function sound.click()
    play(assets.click)
end

-- attention cue for a notification, toast or popup - mirrors hapticEngine.notify().
function sound.notify()
    play(assets.notify)
end

function sound.setVolume(value: number)
    volume = math.clamp(value, 0, 1)
end

-- Global on/off for the settings toggle.
function sound.setEnabled(state: boolean?)
    sound.enabled = state and true or false
end

return sound

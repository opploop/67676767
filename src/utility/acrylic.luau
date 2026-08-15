--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 7 "frost the game behind the window": a Lighting.BlurEffect toggled on/off. Works
-- because post-processing effects in Lighting only ever touch the 3D viewport render - the 2D
-- GUI layer composites on top afterward untouched - so the game world blurs while the window
-- itself (and every other ScreenGui) stays perfectly crisp, reading as a frosted sheet of glass
-- sitting in front of a soft-focus world. BlurEffect over DepthOfFieldEffect (the technique
-- WindUI/Fluent use, see WindUI's src/utils/Acrylic) on purpose: DepthOfField's blur strength
-- varies with distance from the in-focus point, which is the wrong shape for "uniformly frost
-- everything" - BlurEffect's single Size property blurs the whole frame evenly regardless of
-- depth. Uses its own dedicated, uniquely-named effect instance rather than touching (or
-- disabling) any BlurEffect the game itself already has in Lighting, so this never fights with
-- or clobbers a host game's own visual effects.

local acrylic = {}

local effectName = "__RayfieldAcrylicBlur"
local blurInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local lighting = game:GetService("Lighting")
local tweenService = game:GetService("TweenService")

local effect: BlurEffect? = nil

local function ensure(): BlurEffect
    if effect and effect.Parent then
        return effect
    end
    local existing = lighting:FindFirstChild(effectName)
    if existing and existing:IsA("BlurEffect") then
        effect = existing
        return existing
    end
    local blur = Instance.new("BlurEffect")
    blur.Name = effectName
    blur.Size = 0
    blur.Parent = lighting
    effect = blur
    return blur
end

-- size: blur radius in Roblox's own BlurEffect.Size units (0-56ish is the sane range; defaults
-- to a moderate 18 - noticeably frosted without turning the background to mush).
function acrylic.setEnabled(enabled: boolean, size: number?)
    local blur = ensure()
    tweenService:Create(blur, blurInfo, { Size = if enabled then (size or 18) else 0 }):Play()
end

function acrylic.isEnabled(): boolean
    return effect ~= nil and effect.Size > 0
end

return acrylic

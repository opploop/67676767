--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 7 "Acrylic Blur", reworked: the blur has to live ON the window, not on the game behind
-- it. A first pass used a Lighting.BlurEffect, which reads correctly as "frosted glass in front of
-- a soft-focus world" - but that's backwards from what was asked for: the whole 3D viewport went
-- soft while the window itself stayed perfectly crisp, when the window is the thing that should
-- look like frosted glass. Roblox has no property that blurs a single 2D GuiObject or a screen
-- region behind one - Lighting post-processing only ever touches the 3D render, uniformly, for
-- the whole client - so an actual per-pixel blur of "whatever's behind this window" would mean
-- capturing the 3D scene through a second camera and re-rendering it every frame just to sit
-- behind the window, which is expensive and fragile for what's meant to be a visual polish knob.
--
-- Instead this fakes the *look* of frosted glass entirely within the UI layer: a soft translucent
-- wash layered on top of each surface's own background, with an off-angle gradient so the wash
-- reads as uneven light scatter instead of a flat tint - the same trick real glassmorphism CSS
-- uses (a translucent overlay + subtle gradient, no actual blur convolution). Zero render cost,
-- confined entirely to the window's own instances, and never touches Lighting or the game world.

local acrylic = {}

-- Default wash strength: how opaque the frosted wash gets at its most opaque point, 0-1.
acrylic.defaultStrength = 0.16

local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Tweens a pre-built overlay (see Window:_buildAcrylicOverlay) toward "frosted" or "off".
-- strength: how opaque the wash reads at its most opaque point, 0-1 (defaults to acrylic.defaultStrength).
function acrylic.apply(overlay: Frame, enabled: boolean, strength: number?)
    local clamped = math.clamp(strength or acrylic.defaultStrength, 0, 1)
    local targetTransparency = if enabled then 1 - clamped else 1
    game:GetService("TweenService"):Create(overlay, tweenInfo, { BackgroundTransparency = targetTransparency }):Play()
end

return acrylic

--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Picks the window size for a given screen. Anything roomy keeps the default untouched; a
-- short screen trades height for a slice of width so the content area doesnt shrink with it.

local windowSizing = {}

-- Default window size, and the smallest we'll shrink it to on a tiny screen. The minimum is a
-- floor, not a guarantee: a screen too small to hold it gets a window that fits instead.
local defaultSize = Vector2.new(475, 500)
local minSize = Vector2.new(300, 285)

-- Most of the screen we'll ever take, per axis, plus a pixel floor so a huge display still
-- gets a margin. Fractions rather than a flat inset: a fixed margin only ever bites on the
-- small screens least able to afford it, which is how a phone ended up filled top to bottom
-- while half its width sat unused. The vertical cap is deliberately the tighter of the two -
-- an open window should always read as sitting on the screen rather than filling it, and it
-- also clears the Roblox topbar for free, since a centred window leaves 15% above it.
-- plain numbers, not a Vector2: its components are 32 bit, so 0.70 would come back as
-- 0.69999998 and the cap would sit a pixel under what it says on some screens
local maxOccupancyX, maxOccupancyY = 0.86, 0.70
local marginFloorX, marginFloorY = 24, 28

-- When a short screen forces the height down, the window earns a little width back, capped
-- by the viewport and by how wide we'll ever let it read. Scales with the height actually
-- lost, so a screen tall enough for the full height keeps the default width exactly.
local widthCompensation = 80
local maxAspectRatio = 1.95

-- Below this, either axis is a viewport we dont believe - a camera mid-init or a stray 1x1
-- report. Sizing off one would pin the window at its floor for the session, so take the
-- default and let the caller's reconcile correct it once the screen reports properly.
local minPlausibleViewport = 200

windowSizing.defaultSize = defaultSize
windowSizing.minSize = minSize

-- How much height we had to give up, 0 on a screen tall enough and 1 once pinned to the floor.
-- baseHeight is normally the module's own defaultSize.Y, but a dev-supplied custom size (see
-- fit below) becomes the ceiling this scales from instead, so a custom size shrinks the same
-- way the built-in default does on a short screen rather than ignoring the cap entirely.
local function heightDeficit(height: number, baseHeight: number): number
    if baseHeight <= minSize.Y then
        return 1 -- a custom size at or under the floor is already fully "shrunk"
    end
    return math.clamp((baseHeight - height) / (baseHeight - minSize.Y), 0, 1)
end

-- target: a dev-supplied starting size (WindowProps.size) to fit from instead of the built-in
-- default - it's still subject to the same screen-occupancy caps and floor below, so a custom
-- size that's too big for the current screen still shrinks instead of hanging off the edge.
function windowSizing.fit(viewport: Vector2?, target: Vector2?): UDim2
    local baseSize = target or defaultSize

    if not viewport or viewport.X < minPlausibleViewport or viewport.Y < minPlausibleViewport then
        return UDim2.fromOffset(baseSize.X, baseSize.Y)
    end

    local availableX = math.min(viewport.X * maxOccupancyX, viewport.X - marginFloorX)
    local availableY = math.min(viewport.Y * maxOccupancyY, viewport.Y - marginFloorY)

    -- the floor gives way to the screen: a viewport too small to hold it gets a smaller window
    -- rather than one hanging off the edge, so the occupancy caps hold at every size. settle the
    -- height to whole pixels first, so the aspect cap is measured against the height we ship
    -- rather than a fraction that rounds away underneath it.
    local height = math.floor(math.min(math.clamp(availableY, minSize.Y, baseSize.Y), availableY))
    local deficit = heightDeficit(height, baseSize.Y)
    local width = math.max(baseSize.X + widthCompensation * deficit, minSize.X)

    -- the screen and the aspect ceiling are the hard limits, so they are applied after the
    -- floor has lifted the width: a minimum that can push back past a cap is not a cap.
    -- floor, not round: rounding up can carry the result back past those same limits.
    return UDim2.fromOffset(math.floor(math.min(width, availableX, height * maxAspectRatio)), height)
end

-- Devlog 8 corner grip: bounds for a user freely dragging the window's own size, reusing the
-- same "how big should this window ever get" rules as the auto-fit above (the occupancy caps,
-- floor, and short-screen fallback) rather than inventing a separate ceiling that could drift out
-- of sync with it. Unlike `fit`, this never shrinks the window on its own - it just clamps
-- whatever size the drag produced into the same sane range fit would have chosen from scratch.
function windowSizing.clampUserSize(viewport: Vector2?, size: Vector2): Vector2
    if not viewport or viewport.X < minPlausibleViewport or viewport.Y < minPlausibleViewport then
        return Vector2.new(math.max(size.X, minSize.X), math.max(size.Y, minSize.Y))
    end

    local maxX = math.min(viewport.X * maxOccupancyX, viewport.X - marginFloorX)
    local maxY = math.min(viewport.Y * maxOccupancyY, viewport.Y - marginFloorY)

    return Vector2.new(
        math.clamp(size.X, minSize.X, math.max(minSize.X, maxX)),
        math.clamp(size.Y, minSize.Y, math.max(minSize.Y, maxY))
    )
end

return windowSizing

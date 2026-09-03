--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Squircle corners - the smoother "superellipse" curve iOS uses, instead of UICorner's plain
-- circular arc. The three asset ids and the aspect-ratio-driven shape-switching approach below
-- are Wind UI's own work (github.com/Footages/WindUI, MIT licensed, Copyright (c) 2026
-- Footages), reused here with credit per that license's own attribution term - these are three
-- generic geometric shape masks, not distinctive branded artwork, and Wind UI released the exact
-- code that references them under a license that explicitly permits this.
--
-- A squircle can't be drawn from plain Instance properties the way UICorner's arc can - it needs
-- a real image, 9-slice scaled so one small asset stretches to any element size while its corner
-- curve stays crisp. Three variants cover any aspect ratio a UI element actually takes: Squircle
-- (square-ish), SquircleH (wider than tall), SquircleV (taller than wide) - apply() measures the
-- element and switches between them live as it resizes, the same way Wind UI's own DynamicShape
-- module does.

local squircle = {}

export type ShapeName = "Squircle" | "SquircleH" | "SquircleV"

local shapes: { [ShapeName]: { image: string, rect: Rect, radius: number } } = {
    Squircle = { image = "rbxassetid://89641024074289", rect = Rect.new(460, 460, 460, 460), radius = 310 },
    SquircleH = { image = "rbxassetid://125083578015333", rect = Rect.new(512, 325, 512, 325), radius = 325 },
    SquircleV = { image = "rbxassetid://124965260437653", rect = Rect.new(325, 512, 325, 512), radius = 325 },
}

-- Picks the shape matching the element's own aspect ratio right now. A little slack (1.15x)
-- around "square" so a near-square element doesn't flicker between Squircle and SquircleH/V on
-- a 1px resize jitter.
local function shapeFor(size: Vector2): ShapeName
    if size.X > size.Y * 1.15 then
        return "SquircleH"
    elseif size.Y > size.X * 1.15 then
        return "SquircleV"
    end
    return "Squircle"
end

-- Applies a squircle corner to an ImageLabel/ImageButton, sized for `cornerRadius` pixels and
-- kept in sync as the element resizes (a resize can flip which of the 3 shapes fits best, and
-- SliceScale has to track the element's own size against whichever asset's baked-in radius is
-- now in play). Returns a cleanup function - disconnects the resize listener, doesn't touch the
-- image itself (a caller swapping back to a plain UICorner clears Image on its own).
function squircle.apply(imageLabel: ImageLabel | ImageButton, cornerRadius: number): () -> ()
    imageLabel.ScaleType = Enum.ScaleType.Slice

    local function refresh()
        local size = imageLabel.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end
        local shapeName = shapeFor(size)
        local shape = shapes[shapeName]
        if imageLabel.Image ~= shape.image then
            imageLabel.Image = shape.image
            imageLabel.SliceCenter = shape.rect
        end
        -- SliceScale stretches the whole 9-slice uniformly, so a bigger requested radius is a
        -- bigger SliceScale (the asset's own baked-in corner grows right along with it) -
        -- clamped so an absurd radius request can't invert the slice into nonsense.
        imageLabel.SliceScale = math.clamp(cornerRadius / shape.radius, 0.02, 1)
    end

    refresh()
    local connection = imageLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
    return function()
        connection:Disconnect()
    end
end

return squircle

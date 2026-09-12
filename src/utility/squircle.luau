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

export type Shape = { image: string, rect: Rect, radius: number }

-- Named fields rather than a [ShapeName] indexer: Luau refuses dot-access on an indexer-typed
-- table, and shapeFor below reaches for these by name.
local shapes: { Squircle: Shape, SquircleH: Shape, SquircleV: Shape } = {
    Squircle = { image = "rbxassetid://89641024074289", rect = Rect.new(460, 460, 460, 460), radius = 310 },
    SquircleH = { image = "rbxassetid://125083578015333", rect = Rect.new(512, 325, 512, 325), radius = 325 },
    SquircleV = { image = "rbxassetid://124965260437653", rect = Rect.new(325, 512, 325, 512), radius = 325 },
}

-- Picks the shape matching the element's own aspect ratio right now. A little slack (1.15x)
-- around "square" so a near-square element doesn't flicker between Squircle and SquircleH/V on
-- a 1px resize jitter.
-- Returns the shape itself rather than its name. Going through the name meant indexing the
-- shapes table with a value Luau had widened to plain `string`, which is not the ShapeName its
-- keys are declared as - and there is nothing the caller wants the name for anyway.
local function shapeFor(size: Vector2): Shape
    if size.X > size.Y * 1.15 then
        return shapes.SquircleH
    elseif size.Y > size.X * 1.15 then
        return shapes.SquircleV
    end
    return shapes.Squircle
end

-- Applies a squircle corner to an ImageLabel/ImageButton, sized for `cornerRadius` pixels and
-- kept in sync as the element resizes (a resize can flip which of the 3 shapes fits best, and
-- SliceScale has to track the element's own size against whichever asset's baked-in radius is
-- now in play). Returns a cleanup function - disconnects the resize listener, doesn't touch the
-- image itself (a caller swapping back to a plain UICorner clears Image on its own).
function squircle.apply(target: ImageLabel | ImageButton, cornerRadius: number): () -> ()
    -- Narrowed once here rather than annotated as a union throughout: Luau will happily READ a
    -- property off a union but refuses to WRITE one, and every slice property this touches
    -- (ScaleType, Image, SliceCenter, SliceScale) exists identically on both classes.
    local imageLabel = target :: ImageLabel
    imageLabel.ScaleType = Enum.ScaleType.Slice

    local function refresh()
        local size = imageLabel.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end
        local shape = shapeFor(size)
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

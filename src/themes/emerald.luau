--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Deep green-black dark theme with a vivid emerald accent. Partial: overrides the green tones +
-- accent, inherits corners, fonts and toggle/field behaviour from default.
return {
    WindowColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 18, 15)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(16, 28, 23)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 38, 31)),
    }),
    ShadowColor = Color3.fromRGB(5, 12, 9),

    ElementStroke = Color3.fromRGB(32, 54, 44),
    ElementGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 30, 25)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(22, 36, 30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 36, 30)),
    }),
    ElementStrokeGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 72, 60)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(54, 88, 74)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(44, 72, 60)),
    }),
    ElementStrokeHover = Color3.fromRGB(50, 84, 70),

    TabBackground = ColorSequence.new(Color3.fromRGB(34, 58, 48), Color3.fromRGB(22, 38, 31)),
    TabStroke = ColorSequence.new(Color3.fromRGB(54, 92, 76), Color3.fromRGB(34, 58, 48)),

    SliderBackground = Color3.fromRGB(28, 48, 40),
    SliderBackgroundHover = Color3.fromRGB(38, 62, 52),
    SliderProgress = ColorSequence.new(Color3.fromRGB(20, 200, 138), Color3.fromRGB(12, 160, 108)),

    -- Vivid emerald accent for the active toggle, slider glow and popup primary button.
    AccentColor = Color3.fromRGB(20, 200, 138),
    AccentStroke = Color3.fromRGB(96, 232, 182),

    ToggleKnobOff = Color3.fromRGB(214, 232, 222), -- cool off-knob on the dark track

    StatBackground = Color3.fromRGB(14, 24, 20),

    DropdownHighlight = Color3.fromRGB(20, 200, 138),

    NeutralButton = Color3.fromRGB(28, 48, 40),
    NeutralButtonHover = Color3.fromRGB(38, 62, 52),
    NeutralButtonStroke = Color3.fromRGB(90, 140, 118),
}

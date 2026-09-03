--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Deep blue-grey dark theme with a sky-blue accent. Partial: overrides the blue tones + accent,
-- inherits corners, fonts and toggle/field behaviour from default.
return {
    WindowColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 18, 26)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(18, 27, 38)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 35, 48)),
    }),
    ShadowColor = Color3.fromRGB(6, 10, 16),

    ElementStroke = Color3.fromRGB(38, 52, 68),
    ElementGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 29, 40)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(24, 34, 46)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 34, 46)),
    }),
    ElementStrokeGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 68, 88)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(62, 84, 108)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 68, 88)),
    }),
    ElementStrokeHover = Color3.fromRGB(58, 80, 104),

    TabBackground = ColorSequence.new(Color3.fromRGB(38, 54, 72), Color3.fromRGB(24, 35, 48)),
    TabStroke = ColorSequence.new(Color3.fromRGB(62, 88, 116), Color3.fromRGB(38, 54, 72)),

    SliderBackground = Color3.fromRGB(32, 45, 60),
    SliderBackgroundHover = Color3.fromRGB(42, 58, 76),
    SliderProgress = ColorSequence.new(Color3.fromRGB(64, 180, 232), Color3.fromRGB(32, 138, 196)),

    -- Sky-blue accent for the active toggle, slider glow and popup primary button.
    AccentColor = Color3.fromRGB(56, 176, 232),
    AccentStroke = Color3.fromRGB(120, 212, 250),

    ToggleKnobOff = Color3.fromRGB(210, 224, 236), -- cool off-knob on the dark track

    StatBackground = Color3.fromRGB(16, 24, 34),

    DropdownHighlight = Color3.fromRGB(56, 176, 232),

    NeutralButton = Color3.fromRGB(32, 45, 60),
    NeutralButtonHover = Color3.fromRGB(42, 58, 76),
    NeutralButtonStroke = Color3.fromRGB(96, 132, 168),
}

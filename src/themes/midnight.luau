--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Near-black indigo dark theme with a periwinkle accent - the darkest/moodiest of the presets.
-- Partial: overrides the indigo tones + accent, inherits corners, fonts and toggle/field
-- behaviour from default.
return {
    WindowColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 7, 12)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(11, 12, 19)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 17, 26)),
    }),
    ShadowColor = Color3.fromRGB(3, 3, 7),

    ElementStroke = Color3.fromRGB(28, 29, 42),
    ElementGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 15, 23)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(17, 18, 27)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 18, 27)),
    }),
    ElementStrokeGradient = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 42, 60)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(50, 52, 74)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 42, 60)),
    }),
    ElementStrokeHover = Color3.fromRGB(46, 48, 70),

    TabBackground = ColorSequence.new(Color3.fromRGB(30, 32, 46), Color3.fromRGB(16, 17, 26)),
    TabStroke = ColorSequence.new(Color3.fromRGB(50, 52, 76), Color3.fromRGB(30, 32, 46)),

    SliderBackground = Color3.fromRGB(24, 25, 37),
    SliderBackgroundHover = Color3.fromRGB(33, 35, 50),
    SliderProgress = ColorSequence.new(Color3.fromRGB(110, 128, 244), Color3.fromRGB(80, 96, 216)),

    -- Periwinkle accent for the active toggle, slider glow and popup primary button.
    AccentColor = Color3.fromRGB(110, 128, 244),
    AccentStroke = Color3.fromRGB(156, 170, 255),

    ToggleKnobOff = Color3.fromRGB(210, 210, 224), -- cool off-knob on the dark track

    StatBackground = Color3.fromRGB(11, 12, 19),

    DropdownHighlight = Color3.fromRGB(110, 128, 244),

    NeutralButton = Color3.fromRGB(24, 25, 37),
    NeutralButtonHover = Color3.fromRGB(33, 35, 50),
    NeutralButtonStroke = Color3.fromRGB(84, 88, 120),
}

--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Pure black/white with a saturated yellow accent - the same colour convention Windows' own
-- High Contrast mode and most OS accessibility themes lean on: black-on-white or white-on-black
-- reads reliably at a glance for low-vision/colour-deficient users in a way none of the other
-- themes here (all some shade of dark-grey-on-dark-grey, differentiated mainly by a tinted
-- accent) are designed to guarantee. Every stroke that's a soft, low-opacity hint on the other
-- themes is pushed fully opaque and bright white here instead - a translucent border is exactly
-- the kind of low-contrast detail this theme exists to remove, not preserve.

local variables = require(script.Parent.Parent.utility.variables)

return {
    CornerRoundness = UDim.new(0, 20),
    -- Near-flat, unlike every other theme's own visible top-to-bottom gradient (see their own
    -- WindowColor) - a gradient is itself a soft, low-contrast detail; three keypoints instead
    -- of ColorSequence.new(Color3)'s implicit two purely to match this file's own shape to every
    -- other theme's, not for the barely-there gradient itself.
    WindowColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(0.9999, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 5)),
    }),
    ShadowColor = Color3.fromRGB(0, 0, 0),

    -- Fully opaque, bright white - every other theme's ElementStroke is a soft dark-grey hint
    -- (barely visible on purpose, a subtle card edge); high contrast needs the opposite, a
    -- border you can't miss.
    ElementStroke = Color3.fromRGB(255, 255, 255),
    ElementGradient = ColorSequence.new(Color3.fromRGB(15, 15, 15)),
    ElementStrokeGradient = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
    TabColor = Color3.fromRGB(255, 255, 255),
    TabBackground = ColorSequence.new(Color3.fromRGB(30, 30, 30)),
    TabStroke = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
    SliderBackground = Color3.fromRGB(40, 40, 40),
    SliderBackgroundHover = Color3.fromRGB(60, 60, 60),
    SliderProgress = ColorSequence.new(Color3.fromRGB(255, 214, 10)),
    SliderStroke = Color3.fromRGB(255, 255, 255),
    ActionColor = Color3.fromRGB(255, 255, 255),
    TitleFont = variables.brandFont(Enum.FontWeight.SemiBold),
    Font = variables.brandFont(Enum.FontWeight.Medium),
    ContentColor = Color3.fromRGB(255, 255, 255),

    LiveAnimation = false,

    DarkToggleOverlay = true,
    ElementTransparency = 0,
    ElementStrokeTransparency = 0,
    ElementStrokeHoverTransparency = 0,
    ElementStrokeHover = Color3.fromRGB(255, 214, 10), -- the accent, not just a lighter grey -
    -- hover needs to be unmistakably a different state, not a shade away from rest
    ElementCornerRadius = UDim.new(0, 12),
    ElementTextHoverColor = Color3.fromRGB(255, 214, 10),
    TitlingColor = Color3.fromRGB(255, 255, 255),

    DropdownHighlight = Color3.fromRGB(255, 214, 10),

    -- Saturated yellow - the one hue that reads clearly against both the pure black background
    -- and pure white text/strokes everywhere else in this theme, the same reason OS-level high
    -- contrast modes converge on yellow for their own accent/focus colour.
    AccentColor = Color3.fromRGB(255, 214, 10),
    AccentStroke = Color3.fromRGB(255, 235, 120),
    AccentGlow = 0.15, -- brighter glow than default's 0.4 - low-opacity glows are another soft
    -- detail this theme trades for something more legible

    StatBackground = Color3.fromRGB(15, 15, 15),
    SliderHandle = Color3.fromRGB(255, 255, 255),
    PillCornerRadius = UDim.new(1, 0),

    ToggleTrack = Color3.fromRGB(80, 80, 80),
    ToggleTrackTransparency = 0.4, -- default's 0.9 leaves an off-toggle almost invisible against
    -- a dark card; still needs to read as "there" at a glance here
    ToggleKnobOff = Color3.fromRGB(255, 255, 255),
    ToggleKnobOffTransparency = 0,

    FieldBackground = Color3.fromRGB(255, 255, 255),
    FieldTransparency = 0.85,
    FieldGlow = Color3.fromRGB(255, 214, 10),

    PlaceholderColor = Color3.fromRGB(210, 210, 210), -- default's 178 reads as too low-contrast
    -- against a pure black field here
    SurfaceStroke = Color3.fromRGB(255, 255, 255),

    NeutralButton = Color3.fromRGB(40, 40, 40),
    NeutralButtonHover = Color3.fromRGB(70, 70, 70),
    NeutralButtonStroke = Color3.fromRGB(255, 255, 255),

    ErrorColor = Color3.fromRGB(255, 60, 60),
    ErrorStrokeColor = Color3.fromRGB(255, 130, 130),
}

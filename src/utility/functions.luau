--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local functions = {}

local textMetrics = require(script.Parent.textMetrics)
local colors = require(script.Parent.colors)
local flags = require(script.Parent.flagNames)

-- Read a boolean property that accepts either casing, with a default for when neither is set.
--
-- Why this needs a helper: the obvious one-liner is wrong for exactly the value that matters.
-- `(properties.showIndex or properties.ShowIndex) ~= false` evaluates `false or nil` to nil, and
-- nil ~= false is true - so passing `showIndex = false` is silently ignored and the option can
-- only ever be turned ON. Live-caught on ReorderList, whose index badges kept rendering for a
-- caller that had explicitly switched them off.
function functions.readBool(properties: { [string]: any }, name: string, default: boolean): boolean
    local value = properties[name]
    if value == nil then
        value = properties[string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)]
    end
    if value == nil then
        return default
    end
    return value ~= false
end

-- Read a control's starting value from the first of `names` that is actually PRESENT, then
-- from `default`/`Default` as a last resort.
--
-- Two things this fixes at once. Presence, not truthiness: `properties.value or properties.Value`
-- evaluates `false or nil` to nil, so a declared `value = false` is indistinguishable from not
-- declaring one at all - the same trap readBool exists for. And the alias: `value` is this
-- fork's canonical name for a starting state, but upstream Rayfield called it `Default`, so that
-- is what hub scripts carried over from it (and anything generated against upstream's docs)
-- reach for. Accepting it costs nothing and silently ignoring it was a real reported confusion.
-- Each caller spells out its own `names` order because a few controls put a
-- domain-specific spelling first (colorpicker's `color`, gradientpicker's `gradient`).
function functions.readValue(properties: { [string]: any }, names: { string }): any
    for _, name in names do
        if properties[name] ~= nil then
            return properties[name]
        end
    end
    if properties.default ~= nil then
        return properties.default
    end
    return properties.Default
end

functions.textWidth = textMetrics.textWidth
functions.textHeight = textMetrics.textHeight
functions.deriveFlagFromName = flags.deriveFlagFromName
functions.contrastColor = colors.contrastColor
functions.toColorSequence = colors.toColorSequence
functions.contrastText = colors.contrastText
functions.flattenColor = colors.flatten

return functions

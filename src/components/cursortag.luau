--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- A hover area where a small chip trails the cursor, like a designer name tag on a canvas.
-- Hovering the card activates it (code can too, via SetEnabled - handy for a toggle-driven
-- demo); every frame it eases toward the mouse and clamps to its scope's bounds so it never
-- leaves that container. `area` is its own card; `window` is the whole window; `screen` is the
-- full viewport.

local CursorTag = {}
CursorTag.__index = CursorTag
CursorTag.__type = "CursorTag"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local constants = require(utility.constants)

local defaultHeight = 70
local defaultEase = 0.22 -- per-frame Lerp factor toward the target; not a Tween, a continuous chase
local scopes = { area = true, window = true, screen = true }

function CursorTag.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local scope = string.lower(tostring(properties.scope or properties.Scope or "area"))
    if not scopes[scope] then
        scope = "area"
    end

    local offset = properties.offset or properties.Offset or Vector2.new(14, 14)
    if typeof(offset) == "table" then
        offset = Vector2.new(offset.x or offset.X or 0, offset.y or offset.Y or 0)
    end

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        text = properties.text or properties.Text or "You",
        placeholder = properties.placeholder or properties.Placeholder or "Move your mouse over this area",
        scope = scope,
        offset = offset,
        height = properties.height or properties.Height or defaultHeight,
        ease = properties.ease or properties.Ease or defaultEase,

        _tracking = false,
    }, CursorTag)

    self:_build()

    return self
end

function CursorTag:_build()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, self.height),
        BorderSizePixel = 0,
        Name = "CursorTag",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = window:StyleElementBody(self.main)

    self.placeholderLabel = window:Create("TextLabel", {
        Text = locale.t(self.placeholder),
        Size = UDim2.new(1, -30, 1, -20),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,

        TextTransparency = 1, -- In = 0.55

        Parent = self.main,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    self.interact = window:Create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,

        Parent = self.main,
    })

    -- The chip lives at the top of the screenGui, not nested under main: a tab page is a
    -- ScrollingFrame and clips its own content, which would cut the chip off the moment
    -- window/screen scope lets it roam past the page's edge.
    self.chip = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 28),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = constants.zIndex.cursorTag,

        Parent = window.screenGui,
    }, { BackgroundColor3 = "AccentColor" })

    window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.chip,
    })

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),

        Parent = self.chip,
    })

    self.chipLabel = window:Create("TextLabel", {
        Text = locale.t(self.text),
        Size = UDim2.fromOffset(0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        TextColor3 = functions.contrastColor(window.theme.AccentColor),
        ZIndex = constants.zIndex.cursorTag,

        Parent = self.chip,
    }, { FontFace = "Font" })

    window:ConnectFor(self, self.main.MouseEnter, function()
        if not window:_interactive() then
            return
        end
        self:_startTracking()
    end)

    window:ConnectFor(self, self.main.MouseLeave, function()
        self:_stopTracking()
    end)
end

function CursorTag:_bounds()
    local window = self.window
    if self.scope == "window" and window.main then
        return window.main.AbsolutePosition, window.main.AbsoluteSize
    elseif self.scope == "screen" and window.screenGui then
        return Vector2.zero, window.screenGui.AbsoluteSize
    end
    return self.main.AbsolutePosition, self.main.AbsoluteSize
end

function CursorTag:_updatePosition()
    if not self.main.Visible or self.main.AbsoluteSize.Magnitude == 0 then
        self:_stopTracking() -- e.g. its tab isn't the one on screen anymore
        return
    end

    local mouse = self.window:_mouseAbsolutePosition()
    local targetX, targetY = mouse.X + self.offset.X, mouse.Y + self.offset.Y

    local boundsPos, boundsSize = self:_bounds()
    local chipSize = self.chip.AbsoluteSize
    local minX, maxX = boundsPos.X, boundsPos.X + boundsSize.X - chipSize.X
    local minY, maxY = boundsPos.Y, boundsPos.Y + boundsSize.Y - chipSize.Y
    targetX = math.clamp(targetX, minX, math.max(minX, maxX))
    targetY = math.clamp(targetY, minY, math.max(minY, maxY))

    local current = self.chip.AbsolutePosition
    local eased = current:Lerp(Vector2.new(targetX, targetY), self.ease)
    self.chip.Position = UDim2.fromOffset(eased.X, eased.Y)
end

-- Hovering the card calls this; so does explicit code (a toggle wired to SetEnabled(true), say)
function CursorTag:_startTracking()
    if self._tracking then
        return
    end
    self._tracking = true

    -- land it on the mouse immediately rather than easing in from wherever it last was
    local mouse = self.window:_mouseAbsolutePosition()
    self.chip.Position = UDim2.fromOffset(mouse.X + self.offset.X, mouse.Y + self.offset.Y)
    self.chip.Visible = true
    self.chip.BackgroundTransparency = 1
    self.chipLabel.TextTransparency = 1
    variables.tweenService
        :Create(self.chip, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
        })
        :Play()
    variables.tweenService
        :Create(self.chipLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            TextTransparency = 0,
        })
        :Play()

    self._trackConnection = variables.runService.RenderStepped:Connect(function()
        self:_updatePosition()
    end)
end

function CursorTag:_stopTracking()
    if not self._tracking then
        return
    end
    self._tracking = false

    if self._trackConnection then
        self._trackConnection:Disconnect()
        self._trackConnection = nil
    end

    local fadeOut = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    variables.tweenService:Create(self.chip, fadeOut, { BackgroundTransparency = 1 }):Play()
    local tween = variables.tweenService:Create(self.chipLabel, fadeOut, { TextTransparency = 1 })
    tween:Play()
    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and not self._tracking then
            self.chip.Visible = false
        end
    end)
end

-- Explicit on/off from code, independent of hover - e.g. a toggle demoing window/screen scope.
function CursorTag:SetEnabled(enabled)
    if enabled then
        self:_startTracking()
    else
        self:_stopTracking()
    end
end

-- Update the chip's label at runtime.
function CursorTag:Set(text)
    self.text = tostring(text)
    self.chipLabel.Text = locale.resolve(self.text)
end

function CursorTag:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.placeholderLabel, { TextTransparency = 0.55 }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.placeholderLabel, { TextTransparency = 1 }, animate)
        self:_stopTracking()
    end
end

-- The chip's colour rides a themeProperty already; only its contrast-computed text needs a
-- manual refresh when AccentColor changes.
function CursorTag:_refreshTheme()
    self.chipLabel.TextColor3 = functions.contrastColor(self.window.theme.AccentColor)
end

moveable(CursorTag)

return CursorTag

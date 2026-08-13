--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Devlog 5 rebuild: a collapsed header row (name + a live colour swatch pill) that taps open
-- into a hex field, RGB number boxes, a big swatch bar and quick-pick presets on the left, and a
-- Saturation/Value square + horizontal Hue rail (hsvEditor.luau, shared with GradientPicker) on
-- the right - same open/close shape as GradientPicker so the two pickers behave identically.
-- Reflows to a single stacked column under narrowWidth.

local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__type = "ColorPicker"

-- Utility
local utility = script.Parent.Parent.utility

-- Variables
local variables = require(utility.variables)
local functions = require(utility.functions)
local moveable = require(utility.moveable)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)
local hsvEditor = require(utility.hsvEditor)

local headerHeight = 44
local squareSize = 150
local rowGap = 8
local narrowWidth = 380
local glowOnTransparency = 0.55

local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local openInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

local function clampByte(n)
    return math.clamp(math.round(n), 0, 255)
end

local function clamp01(n)
    return math.clamp(n, 0, 1)
end

-- named colours accepted by the smart hex field
local namedColors = {
    black = Color3.fromRGB(0, 0, 0),
    white = Color3.fromRGB(255, 255, 255),
    red = Color3.fromRGB(255, 0, 0),
    green = Color3.fromRGB(0, 255, 0),
    blue = Color3.fromRGB(0, 0, 255),
    yellow = Color3.fromRGB(255, 255, 0),
    cyan = Color3.fromRGB(0, 255, 255),
    magenta = Color3.fromRGB(255, 0, 255),
    orange = Color3.fromRGB(255, 165, 0),
    purple = Color3.fromRGB(128, 0, 128),
    pink = Color3.fromRGB(255, 105, 180),
    brown = Color3.fromRGB(139, 69, 19),
    gray = Color3.fromRGB(128, 128, 128),
    grey = Color3.fromRGB(128, 128, 128),
}

local function numbersIn(s)
    local out = {}
    for n in s:gmatch("[%d%.]+") do
        table.insert(out, tonumber(n))
    end
    return out
end

-- Smart, forgiving colour parse: hex (#fff, ffffff, 0xffffff), rgb("255,0,0"), 0..1 float
-- triplets, or a named colour. Returns a Color3 or nil.
local function parseColor(input)
    if typeof(input) ~= "string" then
        return nil
    end
    local s = (input:lower():match("^%s*(.-)%s*$")) or ""
    if s == "" then
        return nil
    end

    if namedColors[s] then
        return namedColors[s]
    end

    local model = s:match("^(%a+)")
    local nums = numbersIn(s)

    if (model == "rgb" or model == "rgba") and #nums >= 3 then
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    local hex = s:match("^#?(%x%x%x%x%x%x)$") or s:match("^#?(%x%x%x)$") or s:match("^0x(%x%x%x%x%x%x)$")
    if hex then
        local ok, color = pcall(Color3.fromHex, hex)
        if ok then
            return color
        end
    end

    if #nums >= 3 and not model then
        if nums[1] <= 1 and nums[2] <= 1 and nums[3] <= 1 then
            return Color3.new(clamp01(nums[1]), clamp01(nums[2]), clamp01(nums[3]))
        end
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    return nil
end

local function coerceColor(value, fallback)
    if typeof(value) == "Color3" then
        return value
    end
    if typeof(value) == "string" then
        return parseColor(value) or fallback
    end
    return fallback
end

local defaultPresets = {
    Color3.fromRGB(255, 255, 255),
    Color3.fromRGB(255, 59, 48),
    Color3.fromRGB(255, 149, 0),
    Color3.fromRGB(255, 214, 10),
    Color3.fromRGB(52, 199, 89),
    Color3.fromRGB(10, 132, 255),
    Color3.fromRGB(175, 82, 222),
}

function ColorPicker.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Color Picker",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        tooltip = properties.tooltip or properties.Tooltip,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,
        presets = properties.presets or properties.Presets or defaultPresets,

        callback = properties.callback or properties.Callback or function() end,

        _isOpen = false,
        showGlow = if properties.glow ~= nil
            then properties.glow
            elseif properties.Glow ~= nil then properties.Glow
            else true,
    }, ColorPicker)

    self.value = coerceColor(
        properties.color or properties.Color or properties.value or properties.Value or properties.default,
        Color3.fromRGB(255, 255, 255)
    )
    self.hue, self.sat, self.val = self.value:ToHSV()

    local a = properties.alpha or properties.Alpha
    self.alpha = if type(a) == "number" then clamp01(a) else 1

    self.flag = properties.flag
        or properties.Flag
        or (not self.forgetState and functions.deriveFlagFromName(self.name) or nil)
    self.window:_registerControl(self)

    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, headerHeight),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.main)
    self.previewGlow = self.window:CreateGlow(self.main, self.value, 26, 1) -- In = glowOnTransparency (if showGlow)

    self:_buildHeader()
    self:_buildBody()

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        if self._isOpen then
            self:_close()
        else
            self:_open()
        end
    end)

    self.window:ConnectFor(self, self.main.MouseEnter, function()
        if self._isOpen or not self.window:_interactive() then
            return
        end
        local theme = self.window.theme
        variables.tweenService
            :Create(self.stroke, fadeInfo, { Transparency = theme.ElementStrokeHoverTransparency, Color = theme.ElementStrokeHover })
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ElementTextHoverColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 0.97 }):Play()
    end)

    self.window:ConnectFor(self, self.main.MouseLeave, function()
        local theme = self.window.theme
        variables.tweenService
            :Create(self.stroke, fadeInfo, { Transparency = theme.ElementStrokeTransparency, Color = theme.ElementStroke })
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ContentColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 1 }):Play()
    end)

    self.window:ConnectFor(self, self.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        if self.window.animating or (self.window.hidden and self.window.hasShownOnce) then
            return
        end
        self:_applyLayout()
    end)
    self:_applyLayout()

    self.window:_wireTooltip(self)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    self:_applyBodyVisibility(false, false)
    self:_setControlsVisible(false)

    self:_render("instant")

    return self
end

function ColorPicker:_buildHeader()
    local container = self.window:Create("Frame", {
        Size = UDim2.new(1, -90, 0, 16),
        Position = UDim2.new(0, 20, 0, headerHeight / 2),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 5,

            ImageTransparency = 1, -- In = 0

            Parent = container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = 5,

        TextTransparency = 1, -- In = 0

        Parent = container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- small always-on colour pill in the header, live even while collapsed - mirrors
    -- GradientPicker's header swatch so both pickers read the same way at a glance
    self.swatch = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0, headerHeight / 2),
        Size = UDim2.fromOffset(40, 22),
        BackgroundColor3 = self.value,
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.swatch })

    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, headerHeight),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,

        Parent = self.main,
    })
end

-- A small rounded field: an optional single-letter label (R/G/B) left, a TextBox filling the
-- rest. Used for the hex box (no label) and the three RGB channel boxes.
function ColorPicker:_buildField(label, placeholder)
    local box = self.window:Create("Frame", {
        Size = UDim2.fromOffset(0, 34),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.85

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = box })
    local stroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- Open = 0.75

        Parent = box,
    })

    local padLeft = if label then 30 else 12
    local input = self.window:Create("TextBox", {
        PlaceholderText = placeholder or "",
        Size = UDim2.new(1, -(padLeft + 10), 1, 0),
        Position = UDim2.new(0, padLeft, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = 3,

        TextTransparency = 1, -- Open = 0

        Parent = box,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    local text = nil
    if label then
        text = self.window:Create("TextLabel", {
            Text = label,
            Size = UDim2.fromOffset(16, 34),
            Position = UDim2.new(0, 10, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 13,
            ZIndex = 3,

            TextTransparency = 1, -- Open = 0.4

            Parent = box,
        }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })
    end

    return box, input, stroke, text
end

function ColorPicker:_buildBody()
    -- hex field
    self.hexBox, self.hexInput, self.hexBoxStroke = self:_buildField(nil, "Hex")
    self.hexInput.Text = "#" .. self.value:ToHex():upper()
    self.hexInput.TextXAlignment = Enum.TextXAlignment.Center

    -- RGB row: three equal fields sharing one flex-filled row
    self.rgbRow = self.window:Create("Frame", {
        Size = UDim2.fromOffset(0, 34),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,

        Parent = self.main,
    })
    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        Padding = UDim.new(0, 8),

        Parent = self.rgbRow,
    })

    self.rBox, self.rInput, self.rBoxStroke, self.rBoxText = self:_buildRgbField("R")
    self.gBox, self.gInput, self.gBoxStroke, self.gBoxText = self:_buildRgbField("G")
    self.bBox, self.bInput, self.bBoxStroke, self.bBoxText = self:_buildRgbField("B")

    -- big live swatch bar
    self.swatchBar = self.window:Create("Frame", {
        Size = UDim2.fromOffset(0, 34),
        BackgroundColor3 = self.value,
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.main,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.swatchBar })

    -- preset swatches row
    self.presetsRow = self.window:Create("Frame", {
        Size = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,

        Parent = self.main,
    })
    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),

        Parent = self.presetsRow,
    })

    self.presetButtons = {}
    for _, color in self.presets do
        local dot = self.window:Create("TextButton", {
            Size = UDim2.fromOffset(26, 26),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 2,

            BackgroundTransparency = 1, -- Open = 0

            Parent = self.presetsRow,
        })
        self.window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
        local ring = self.window:Create("UIStroke", {
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 2,
            Transparency = 1, -- managed by _render (selection ring), forced shut while closed

            Parent = dot,
        })
        table.insert(self.presetButtons, { color = color, dot = dot, ring = ring })

        self.window:ConnectFor(self, dot.MouseButton1Click, function()
            hapticEngine.click()
            self:Set(color)
            self.window:_persist(self)
        end)
    end

    -- shared HSV editor, right column
    self.hsv = hsvEditor.build(self.window, self, self.main, {
        squareSize = squareSize,
        hueHeight = 14,
        gap = 14,
        hue = self.hue,
        sat = self.sat,
        val = self.val,
        onChange = function(h, s, v)
            self.hue, self.sat, self.val = h, s, v
            self.value = Color3.fromHSV(h, s, v)
            self:_render("drag")
            self:_fireCallback()
        end,
        onCommit = function()
            self.window:_persist(self)
        end,
    })

    self.window:ConnectFor(self, self.hexInput.FocusLost, function()
        local color = parseColor(self.hexInput.Text)
        if color then
            self:Set(color)
            self.window:_persist(self)
        else
            self.hexInput.Text = "#" .. self.value:ToHex():upper()
        end
    end)

    local function commitRgb()
        local r = tonumber(self.rInput.Text) or self.value.R * 255
        local g = tonumber(self.gInput.Text) or self.value.G * 255
        local b = tonumber(self.bInput.Text) or self.value.B * 255
        self:Set(Color3.fromRGB(clampByte(r), clampByte(g), clampByte(b)))
        self.window:_persist(self)
    end
    self.window:ConnectFor(self, self.rInput.FocusLost, commitRgb)
    self.window:ConnectFor(self, self.gInput.FocusLost, commitRgb)
    self.window:ConnectFor(self, self.bInput.FocusLost, commitRgb)
end

function ColorPicker:_buildRgbField(label)
    local box = self.window:Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.85

        Parent = self.rgbRow,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = box })
    local stroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- Open = 0.75

        Parent = box,
    })

    local text = self.window:Create("TextLabel", {
        Text = label,
        Size = UDim2.fromOffset(14, 34),
        Position = UDim2.new(0, 8, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 13,
        ZIndex = 3,

        TextTransparency = 1, -- Open = 0.4

        Parent = box,
    }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })

    local input = self.window:Create("TextBox", {
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.new(0, 24, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = 3,

        TextTransparency = 1, -- Open = 0

        Parent = box,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    return box, input, stroke, text
end

function ColorPicker:_render(mode)
    self.swatch.BackgroundColor3 = self.value
    self.swatchBar.BackgroundColor3 = self.value
    self.hsv:SetColor(self.hue, self.sat, self.val, mode ~= "instant")

    if not self.hexInput:IsFocused() then
        self.hexInput.Text = "#" .. self.value:ToHex():upper()
    end
    if not self.rInput:IsFocused() then
        self.rInput.Text = tostring(math.round(self.value.R * 255))
    end
    if not self.gInput:IsFocused() then
        self.gInput.Text = tostring(math.round(self.value.G * 255))
    end
    if not self.bInput:IsFocused() then
        self.bInput.Text = tostring(math.round(self.value.B * 255))
    end

    self.previewGlow.Color = self.value
    for _, entry in self.presetButtons do
        entry.ring.Transparency = if entry.color == self.value and self._isOpen then 0 else 1
    end
end

function ColorPicker:_fireCallback()
    self.window:_runGuarded(self, self.callback, self.value, self.alpha)
end

function ColorPicker:_open()
    if self._isOpen then
        return
    end
    self._isOpen = true
    self:_setControlsVisible(true)

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
    end
    self._outsideClickConn = self.window:Connect(variables.userInputService.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local pos = input.Position
        local mainPos = self.main.AbsolutePosition
        local mainSize = self.main.AbsoluteSize
        if pos.X < mainPos.X or pos.X > mainPos.X + mainSize.X or pos.Y < mainPos.Y or pos.Y > mainPos.Y + mainSize.Y then
            self:_close()
        end
    end)

    variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    self:_applyBodyVisibility(true, true)
    self.hsv:SetVisible(true, true)
    self:_render("animate")
end

function ColorPicker:_close()
    if not self._isOpen then
        return
    end
    self._isOpen = false

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end
    if self.hexInput:IsFocused() then
        self.hexInput:ReleaseFocus()
    end

    self:_applyBodyVisibility(false, true)
    self.hsv:SetVisible(false, true)
    self:_render("animate") -- also drops the preset ring now that _isOpen is false
    variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, headerHeight) }):Play()

    task.delay(fadeInfo.Time, function()
        if not self._isOpen then
            self:_setControlsVisible(false)
        end
    end)
end

-- Wide: hex/RGB/swatch/presets left, square+hue right, side by side.
-- Narrow: same stack, full width, with the editor centred underneath.
function ColorPicker:_applyLayout()
    local width = self.main.AbsoluteSize.X
    local mode = if width > 0 and width < narrowWidth then "narrow" else "wide"
    if mode == self._layoutMode then
        return
    end
    self._layoutMode = mode

    local leftWidth = if mode == "wide" then UDim.new(1, -(20 + squareSize + 16 + 20)) else UDim.new(1, -40)
    local y = headerHeight
    self.hexBox.Position = UDim2.new(0, 20, 0, y)
    self.hexBox.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 34)
    y += 34 + rowGap

    self.rgbRow.Position = UDim2.new(0, 20, 0, y)
    self.rgbRow.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 34)
    y += 34 + rowGap

    self.swatchBar.Position = UDim2.new(0, 20, 0, y)
    self.swatchBar.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 34)
    y += 34 + rowGap + 2

    self.presetsRow.Position = UDim2.new(0, 20, 0, y)
    self.presetsRow.Size = UDim2.new(leftWidth.Scale, leftWidth.Offset, 0, 26)
    local leftBottom = y + 26

    if mode == "wide" then
        self.hsv.root.Position = UDim2.new(1, -20 - squareSize, 0, headerHeight)
        self._openHeight = math.max(leftBottom, headerHeight + squareSize + 14 + 14) + 20
    else
        local hsvY = leftBottom + 16
        self.hsv.root.Position = UDim2.new(0.5, -squareSize / 2, 0, hsvY)
        self._openHeight = hsvY + squareSize + 14 + 14 + 20
    end

    if self._isOpen then
        variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    end
end

function ColorPicker:Set(color, skipCallback)
    self.value = coerceColor(color, self.value)
    self.hue, self.sat, self.val = self.value:ToHSV()
    self:_render(if skipCallback then "instant" else "animate")

    if not skipCallback then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

function ColorPicker:SetAlpha(alpha, skipCallback)
    self.alpha = clamp01(if type(alpha) == "number" then alpha else self.alpha)

    if not skipCallback then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

-- Toggle the ambient glow behind the card at runtime.
function ColorPicker:SetGlow(shown)
    self.showGlow = shown and true or false
    variables.tweenService
        :Create(self.previewGlow, fadeInfo, { Transparency = if self.showGlow then glowOnTransparency else 1 })
        :Play()
end

-- Persistence: RRGGBB plus an alpha byte (AA) so alpha round-trips even though this layout has
-- no alpha control of its own - a dev can still drive SetAlpha() from code.
function ColorPicker:_serialize()
    return self.value:ToHex() .. string.format("%02x", math.clamp(math.round((self.alpha or 1) * 255), 0, 255))
end

function ColorPicker:_deserialize(raw)
    local hex = tostring(raw)
    if #hex >= 8 then
        self:SetAlpha((tonumber(hex:sub(7, 8), 16) or 255) / 255, true)
        hex = hex:sub(1, 6)
    end
    self:Set(Color3.fromHex(hex))
end

-- Every OPEN-only body part (hex/RGB fields, swatch bar, presets), listed once so both the
-- initial hidden state at build and every later open/close pull from the same table - same
-- idea as the old picker's _applyPickerVisibility. The header swatch pill is NOT in here since
-- it stays visible whether the card is open or closed. hsvEditor manages its own instances.
function ColorPicker:_applyBodyVisibility(open, animate)
    local set = {
        [self.hexBox] = { BackgroundTransparency = if open then 0.85 else 1 },
        [self.hexBoxStroke] = { Transparency = if open then 0.75 else 1 },
        [self.hexInput] = { TextTransparency = if open then 0 else 1 },
        [self.swatchBar] = { BackgroundTransparency = if open then 0 else 1 },
    }
    for _, field in { { self.rBox, self.rBoxStroke, self.rBoxText, self.rInput },
        { self.gBox, self.gBoxStroke, self.gBoxText, self.gInput },
        { self.bBox, self.bBoxStroke, self.bBoxText, self.bInput } } do
        local box, stroke, text, input = field[1], field[2], field[3], field[4]
        set[box] = { BackgroundTransparency = if open then 0.85 else 1 }
        set[stroke] = { Transparency = if open then 0.75 else 1 }
        set[text] = { TextTransparency = if open then 0.4 else 1 }
        set[input] = { TextTransparency = if open then 0 else 1 }
    end
    for _, entry in self.presetButtons do
        set[entry.dot] = { BackgroundTransparency = if open then 0 else 1 }
        if not open then
            set[entry.ring] = { Transparency = 1 }
        end
    end

    for instance, props in set do
        if animate then
            variables.tweenService:Create(instance, fadeInfo, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end
end

-- The open-only controls sit below the header even while collapsed (the card doesn't clip), so
-- a transparent TextBox/button down there would still catch the cursor. Toggling them off drops
-- the whole cluster out of input while closed - the header swatch pill is separate, stays put.
function ColorPicker:_setControlsVisible(visible)
    for _, frame in { self.hexBox, self.rgbRow, self.swatchBar, self.presetsRow, self.hsv.root } do
        frame.Visible = visible
    end
end

function ColorPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.swatch, { BackgroundTransparency = 0 }, animate)
        w:_reveal(self.previewGlow, { Transparency = if self.showGlow then glowOnTransparency else 1 }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.swatch, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.previewGlow, { Transparency = 1 }, animate)
        if self._isOpen then
            self:_close()
        end
    end
end

moveable(ColorPicker)

return ColorPicker

--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Shared Saturation/Value square + horizontal Hue rail, factored out of the old colorpicker.luau
-- so both ColorPicker (editing its own solid colour) and GradientPicker (editing whichever stop
-- is selected) drive the exact same widget instead of drifting two copies of the same drag math.
-- Owns its own instances and input wiring; the caller just supplies where to build it and what
-- to do with the (h, s, v) it produces.

local hsvEditor = {}

local variables = require(script.Parent.variables)

local dragInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local followInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local heldInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- left(red) -> right, wrapping back to red, for the horizontal hue rail
local hueSequence = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
})

local function clamp01(n)
    return math.clamp(n, 0, 1)
end

-- opts: {
--   position, squareSize, hueHeight, gap = layout
--   hue, sat, val = initial channels
--   onChange = function(h, s, v, mode) end -- fires continuously (mode: "drag"/"instant")
--   onCommit = function() end -- fires once when a drag/click-set finishes, for persistence
-- }
function hsvEditor.build(window, owner, parent, opts)
    opts = opts or {}
    local squareSize = opts.squareSize or 150
    local hueHeight = opts.hueHeight or 14
    local gap = opts.gap or 14
    local onChange = opts.onChange or function() end
    local onCommit = opts.onCommit or function() end

    local hue, sat, val = opts.hue or 0, opts.sat or 1, opts.val or 1

    local root = window:Create("Frame", {
        Position = opts.position or UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(squareSize, squareSize + gap + hueHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Parent = parent,
    })

    -- Saturation/Value square: hue-tinted base, a white->clear saturation gradient (left->right)
    -- layered on top, and a clear->black value gradient (top->bottom) over that.
    local square = window:Create("Frame", {
        Size = UDim2.fromOffset(squareSize, squareSize),
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = root,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = square })
    local squareStroke = window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),

        Transparency = 1, -- Shown = 0.9

        Parent = square,
    })

    local satOverlay = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = square,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = satOverlay })
    window:Create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = satOverlay,
    })

    local valOverlay = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = square,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = valOverlay })
    window:Create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = valOverlay,
    })

    local cursor = window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = Color3.fromHSV(hue, sat, val),
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = square,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cursor })
    local cursorStroke = window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,

        Transparency = 1, -- Shown = 0

        Parent = cursor,
    })

    local squareInteract = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,

        Parent = square,
    })

    -- Horizontal hue rail, directly under the square.
    local hueBar = window:Create("Frame", {
        Position = UDim2.fromOffset(0, squareSize + gap),
        Size = UDim2.new(1, 0, 0, hueHeight),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = root,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueBar })
    window:Create("UIGradient", { Color = hueSequence, Parent = hueBar })

    local hueHandle = window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(hue, 0, 0.5, 0),
        Size = UDim2.fromOffset(hueHeight + 6, hueHeight + 6),
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- Shown = 0

        Parent = hueBar,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueHandle })
    local hueHandleStroke = window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,

        Transparency = 1, -- Shown = 0

        Parent = hueHandle,
    })

    local hueInteract = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 16),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,

        Parent = hueBar,
    })

    local controller = { root = root, square = square, hueBar = hueBar }

    local function paint(mode)
        local mapHue = Color3.fromHSV(hue, 1, 1)
        local satPos = UDim2.new(sat, 0, 1 - val, 0)
        local huePos = UDim2.new(hue, 0, 0.5, 0)
        local swatch = Color3.fromHSV(hue, sat, val)

        if mode == "instant" then
            square.BackgroundColor3 = mapHue
            cursor.Position, cursor.BackgroundColor3 = satPos, swatch
            hueHandle.Position, hueHandle.BackgroundColor3 = huePos, mapHue
        else
            local moveInfo = if mode == "drag" then dragInfo else followInfo
            variables.tweenService:Create(square, moveInfo, { BackgroundColor3 = mapHue }):Play()
            variables.tweenService:Create(cursor, moveInfo, { Position = satPos, BackgroundColor3 = swatch }):Play()
            variables.tweenService:Create(hueHandle, moveInfo, { Position = huePos, BackgroundColor3 = mapHue }):Play()
        end
    end

    function controller:SetColor(h, s, v, animate)
        hue, sat, val = h, s, v
        paint(if animate then "animate" else "instant")
    end

    -- Fade the whole editor in/out together, mirroring the shown/hidden convention every other
    -- element's _setShown uses (one table of instance -> target prop, so the owner's own
    -- _setShown can just delegate here instead of reaching into our private instances).
    function controller:SetVisible(shown, animate)
        local set = {
            [square] = { BackgroundTransparency = if shown then 0 else 1 },
            [squareStroke] = { Transparency = if shown then 0.9 else 1 },
            [satOverlay] = { BackgroundTransparency = if shown then 0 else 1 },
            [valOverlay] = { BackgroundTransparency = if shown then 0 else 1 },
            [cursor] = { BackgroundTransparency = if shown then 0 else 1 },
            [cursorStroke] = { Transparency = if shown then 0 else 1 },
            [hueBar] = { BackgroundTransparency = if shown then 0 else 1 },
            [hueHandle] = { BackgroundTransparency = if shown then 0 else 1 },
            [hueHandleStroke] = { Transparency = if shown then 0 else 1 },
        }
        for instance, props in set do
            if animate then
                variables.tweenService:Create(instance, followInfo, props):Play()
            else
                for prop, value in props do
                    instance[prop] = value
                end
            end
        end
    end

    function controller:Destroy()
        root:Destroy()
    end

    -- Mouse in AbsolutePosition space (see colorpicker.luau's original note: GetMouseLocation()
    -- sits one gui-inset below AbsolutePosition when the screen ignores the inset).
    local function mouseLocation()
        local mouse = variables.userInputService:GetMouseLocation()
        local screenGui = window.screenGui
        if screenGui and screenGui.IgnoreGuiInset then
            return mouse - variables.guiService:GetGuiInset()
        end
        return mouse
    end

    local drag, dragIsMouse, dragConnection = nil, false, nil

    local function setHeld(region)
        local cursorSize = if region == "square" then UDim2.fromOffset(20, 20) else UDim2.fromOffset(16, 16)
        local hueSize = if region == "hue"
            then UDim2.fromOffset(hueHeight + 10, hueHeight + 10)
            else UDim2.fromOffset(hueHeight + 6, hueHeight + 6)
        variables.tweenService:Create(cursor, heldInfo, { Size = cursorSize }):Play()
        variables.tweenService:Create(hueHandle, heldInfo, { Size = hueSize }):Play()
    end

    local function pump()
        local prevHue, prevSat, prevVal = hue, sat, val

        if drag == "square" then
            local size = square.AbsoluteSize
            if size.X <= 0 or size.Y <= 0 then
                return
            end
            local mouse = mouseLocation()
            sat = clamp01((mouse.X - square.AbsolutePosition.X) / size.X)
            val = 1 - clamp01((mouse.Y - square.AbsolutePosition.Y) / size.Y)
        elseif drag == "hue" then
            local width = hueBar.AbsoluteSize.X
            if width <= 0 then
                return
            end
            local mouse = mouseLocation()
            hue = clamp01((mouse.X - hueBar.AbsolutePosition.X) / width)
        else
            return
        end

        if hue == prevHue and sat == prevSat and val == prevVal then
            return
        end

        paint("drag")
        onChange(hue, sat, val, "drag")
    end

    local function endDrag()
        drag = nil
        setHeld(nil)
        if dragConnection then
            dragConnection:Disconnect()
            dragConnection = nil
        end
        onCommit()
    end

    local function beginDrag(region, isMouse)
        drag = region
        dragIsMouse = isMouse
        setHeld(region)
        pump()

        if dragConnection then
            dragConnection:Disconnect()
            dragConnection = nil
        end

        dragConnection = variables.runService.RenderStepped:Connect(function()
            local mouseReleased = dragIsMouse
                and not variables.userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            if window.unloaded or not drag or mouseReleased then
                if mouseReleased then
                    endDrag()
                    return
                end
                if dragConnection then
                    dragConnection:Disconnect()
                    dragConnection = nil
                end
                return
            end
            pump()
        end)
    end

    window:ConnectFor(owner, squareInteract.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag("square", input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    window:ConnectFor(owner, hueInteract.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag("hue", input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    window:ConnectFor(owner, variables.userInputService.InputEnded, function(input)
        if
            (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
            and drag
        then
            endDrag()
        end
    end)

    paint("instant")

    return controller
end

return hsvEditor

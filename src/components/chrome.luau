--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Window furniture: the collapsed "Show" face main wears while hidden (window.collapsed*
-- fields), plus the first-open new-user check. The welcome greeting itself is just a toast now.

local utility = script.Parent.Parent.utility
local variables = require(utility.variables)
local filesystem = require(utility.filesystem)
local constants = require(utility.constants)
local locale = require(utility.locale)
local hapticEngine = require(utility.HapticEngine)
local soundEngine = require(utility.sound)

local chrome = {}

local collapsedDragThreshold = 6

-- Same half-extent clamp _clampedPosition (windowMethods.luau) uses for a real drag, just
-- against the pill's own current AbsoluteSize instead of the full window's self.size - main is
-- tiny while collapsed, so clamping against the expanded window's own half-extents would either
-- refuse to let the pill reach the real screen edges or let it hang off them, depending on which
-- is bigger.
local function clampCollapsedPosition(window, position: UDim2): UDim2
    if not (window.settings and window.settings.keepOnScreen) then
        return position
    end
    if position.X.Scale ~= 0 or position.Y.Scale ~= 0 then
        return position -- on-scale positions recentre on their own; nothing to clamp
    end
    local size = window.main.AbsoluteSize
    local screen = window.screenGui.AbsoluteSize
    local margin = 8
    local halfX, halfY = size.X / 2, size.Y / 2
    local x = math.clamp(position.X.Offset, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
    local y = math.clamp(position.Y.Offset, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
    return UDim2.fromOffset(x, y)
end

-- Drag the collapsed pill around the screen (e.g. out from under something else on screen it
-- happens to land on) - a plain tap still restores the window; a real drag doesn't also fire
-- that. MouseButton1Click alone can't tell those apart (Roblox fires it on any mouse-up over the
-- button regardless of movement in between), so this tracks the raw input itself and only calls
-- ToggleHide() when the pointer never moved past a small threshold - the same click-vs-drag
-- shape a real drag handle would use, just with the "was this actually a drag" check added on
-- top.
local function wireCollapsedDrag(window)
    local uis = variables.userInputService
    local dragging, dragged = false, false
    local startMouse, startMainPos = Vector2.zero, UDim2.new()

    window:Connect(window.collapsedInteract.InputBegan, function(input, processed)
        if processed then
            return
        end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
            return
        end
        dragging = true
        dragged = false
        startMouse = uis:GetMouseLocation()
        startMainPos = window.main.Position
    end)

    window:Connect(variables.runService.RenderStepped, function()
        if not dragging then
            return
        end
        local delta = uis:GetMouseLocation() - startMouse
        if not dragged and delta.Magnitude > collapsedDragThreshold then
            dragged = true
        end
        if dragged then
            local target = UDim2.new(
                startMainPos.X.Scale,
                startMainPos.X.Offset + delta.X,
                startMainPos.Y.Scale,
                startMainPos.Y.Offset + delta.Y
            )
            window.main.Position = clampCollapsedPosition(window, target)
        end
    end)

    local function release(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
            return
        end
        if not dragging then
            return
        end
        dragging = false
        if dragged then
            -- the pill actually moved: Show() grows the window back from here, not from
            -- wherever it sat before it was ever collapsed (see Window:Hide's own
            -- _restorePosition capture) - otherwise reopening would visibly teleport the window
            -- away from the pill the player just moved it to.
            window._restorePosition = window.main.Position
            window:_syncDragBar()
        else
            hapticEngine.click()
            soundEngine.click()
            window:ToggleHide()
        end
    end
    window:Connect(uis.InputEnded, release)
    window:Connect(uis.WindowFocusReleased, function()
        dragging = false
    end)
end

-- The face main wears once collapsed: an icon + "name"/"Tap to show", drawn straight onto
-- the window frame itself. main already carries the pill's background (its own WindowColor
-- gradient reads the same as the old standalone pill), so shrinking main IS becoming the
-- pill - nothing to hand off to, nothing to swap.
function chrome.buildCollapsedFace(window)
    window.collapsedIcon = window:Create("ImageLabel", {
        Name = "CollapsedIcon",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 16, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        -- raw value: Create routes Image through image.resolve (concat would double the prefix)
        Image = window.showIcon,
        ZIndex = constants.zIndex.restoreContent,

        ImageTransparency = 1, -- shown = 0, set by chrome.setCollapsedShown

        Parent = window.main,
    }, { ImageColor3 = "TitlingColor" })

    window:Create("UICorner", {
        Parent = window.collapsedIcon,
    }, { CornerRadius = "PillCornerRadius" })

    local textContainer = window:Create("Frame", {
        Name = "CollapsedText",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 50, 0.5, 0),
        Size = UDim2.new(1, -60, 0, 32),
        BackgroundTransparency = 1,
        ZIndex = constants.zIndex.restoreContent,

        Parent = window.main,
    })

    window:Create("UIListLayout", {
        Padding = UDim.new(0, 1),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = textContainer,
    })

    window.collapsedTitle = window:Create("TextLabel", {
        Name = "Title",
        Text = window.showName,
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        FontFace = variables.brandFont(Enum.FontWeight.Medium),
        RichText = true,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = constants.zIndex.restoreContent,

        TextTransparency = 1, -- shown = 0, set by chrome.setCollapsedShown

        Parent = textContainer,
    }, { TextColor3 = "TitlingColor" })

    window.collapsedSubtitle = window:Create("TextLabel", {
        Name = "Subtitle",
        Text = locale.t("Tap to show"),
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        FontFace = variables.brandFont(Enum.FontWeight.Medium),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 2,
        ZIndex = constants.zIndex.restoreContent,

        TextTransparency = 1, -- shown = 0.5, set by chrome.setCollapsedShown

        Parent = textContainer,
    }, { TextColor3 = "TitlingColor" })

    -- covers the whole window but only takes clicks while collapsed - Window:Hide/Show flip
    -- Visible as the morph starts/settles so it can never eat a click mid-animation or while
    -- the window is fully open. Active alone doesn't stop a GuiButton from still receiving
    -- clicks here, so Visible is what actually keeps it out of hit-testing.
    window.collapsedInteract = window:Create("TextButton", {
        Name = "CollapsedInteract",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        TextTransparency = 1,
        Visible = false,
        ZIndex = constants.zIndex.restoreInteract,

        Parent = window.main,
    })

    -- Drag the collapsed pill around the screen (e.g. out from under something else on screen
    -- it happens to land on) - a plain tap still restores the window; a real drag doesn't also
    -- fire that. MouseButton1Click alone can't tell those apart (Roblox fires it on any
    -- mouse-up over the button regardless of movement in between), so this tracks the raw
    -- input itself and only calls ToggleHide() when the pointer never moved past a small
    -- threshold - the same click-vs-drag shape a real drag handle would use, just with the
    -- "was this actually a drag" check added on top.
    wireCollapsedDrag(window)
end

function chrome.isNewUser()
    local localPlayer = variables.localPlayer
    if not localPlayer then
        return false
    end

    -- No filesystem available - just show the banner every launch.
    if typeof(filesystem.isfile) ~= "function" or typeof(filesystem.writefile) ~= "function" then
        return true
    end

    local path = variables.fileSystemManager:getPath("lastuser.txt")
    local currentId = tostring(localPlayer.UserId)
    local isNew = true

    pcall(function()
        if filesystem.isfile(path) then
            isNew = filesystem.readfile(path) ~= currentId
        end
    end)

    pcall(function()
        filesystem.writefile(path, currentId)
    end)

    return isNew
end

-- Fade the collapsed face (icon + labels) in or out as main morphs into/out of the pill.
-- When tweenInfo is nil the values snap instantly.
function chrome.setCollapsedShown(window, shown, tweenInfo)
    local targets = {
        [window.collapsedIcon] = { ImageTransparency = if shown then 0 else 1 },
        [window.collapsedTitle] = { TextTransparency = if shown then 0 else 1 },
        [window.collapsedSubtitle] = { TextTransparency = if shown then 0.5 else 1 },
    }

    for instance, props in targets do
        if tweenInfo then
            variables.tweenService:Create(instance, tweenInfo, props):Play()
        else
            for property, value in props do
                instance[property] = value
            end
        end
    end
end

return chrome

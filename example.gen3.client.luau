-- Gen 3 - focused smoke test
--
-- Only the new batches (one tab per devlog), kept separate from example.client.luau so it's
-- quick to eyeball each new element on its own against the devlog reference, without the rest
-- of the library's tabs in the way.
--
-- Not wired into default.project.json - load it the same way you'd load any standalone script
-- (or point the GitHub-raw test loader at this file instead of example.client.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rayfield = require(ReplicatedStorage.Rayfield)

local window = Rayfield:CreateWindow({
    name = "Gen 3 Changes",
    subtitle = "Devlog 1 + 2",
    theme = "cobalt",
    -- Devlog 6: an initial custom size (still screen-fit the same way the built-in default is,
    -- see windowSizing.luau) - left commented here so this smoke-test window keeps the size
    -- it's been tested at all session; uncomment to try it.
    -- size = Vector2.new(600, 650),
})

-- debug hook for the test harness: lets an external probe call window:Navigate(...) directly
-- instead of simulating clicks on the tab bar. Harmless to leave in a smoke-test script.
_G.RayfieldGen3Window = window

-- Devlog 1: Checkbox, CopyButton, FlipButton --------------------------------
local tab = window:CreateTab({ name = "Devlog 1", icon = 93364949241311 })

-- Checkbox --------------------------------------------------------------------
tab:CreateSection({ name = "Checkbox" })

tab:CreateCheckbox({
    name = "Basic Checkbox",
    description = "A compact alternative to a toggle. Supports flags, config saving, and descriptions.",
    callback = function(value)
        print("Basic Checkbox:", value)
    end,
})

tab:CreateCheckbox({
    name = "Starts Checked",
    value = true,
    icon = 125626312718314, -- built-in check glyph, just to show an icon next to the title
    callback = function(value)
        print("Starts Checked:", value)
    end,
})

local updatedFromCode = tab:CreateCheckbox({ name = "Set() From Code", forgetState = true })

tab:CreateButton({
    name = "Toggle It From Code",
    description = "Calls Checkbox:Set() on the row above.",
    callback = function()
        updatedFromCode:Set(not updatedFromCode.value)
    end,
})

local checkboxRow = tab:CreateGroup()
checkboxRow:CreateCheckbox({ name = "Row A" })
checkboxRow:CreateCheckbox({ name = "Row B" })
checkboxRow:CreateCheckbox({ name = "Row C" })

-- Copy Button -------------------------------------------------------------------
tab:CreateSection({ name = "Copy Button" })

tab:CreateCopyButton({
    name = "Copy Text",
    description = "Icon well pops, squishes, then shows a checkmark that reverts after 2 seconds.",
    text = "Hello from Rayfield Gen3!",
    callback = function(success)
        print("Copy Text success:", success)
    end,
})

tab:CreateCopyButton({
    name = "Copy With Icon",
    icon = 129180860773723, -- built-in settings glyph, just to show the well holding an icon
    description = "Same behaviour, with a dev-supplied icon sitting in the well at rest.",
    text = "PLAYER-0001",
})

local copyRow = tab:CreateGroup()
copyRow:CreateCopyButton({ name = "Copy A", text = "A" })
copyRow:CreateCopyButton({ name = "Copy B", text = "B" })

-- Flip Button ---------------------------------------------------------------
tab:CreateSection({ name = "Flip Button" })

tab:CreateFlipButton({
    name = "Hover Me",
    secondaryName = "Flipped!",
    description = "Hovering flips the title to reveal the second label; clicking still runs the callback.",
    callback = function()
        print("Flip button pressed")
    end,
})

tab:CreateFlipButton({
    name = "Version",
    secondaryName = "v1.0.0",
    icon = 93364949241311,
    description = "Icon stays put; only the title flips.",
})

local flipRow = tab:CreateGroup()
flipRow:CreateFlipButton({ name = "A", secondaryName = "1" })
flipRow:CreateFlipButton({ name = "B", secondaryName = "2" })
flipRow:CreateFlipButton({ name = "C", secondaryName = "3" })

-- Devlog 2: RippleButton, ProgressBar, ScrollHint ----------------------------
local tab2 = window:CreateTab({ name = "Devlog 2", icon = 84750991656135 })

tab2:CreateSection({ name = "Ripple Button" })

tab2:CreateRippleButton({
    name = "Click Me",
    icon = 93364949241311,
    description = "Ripple spreads from wherever you press - mouse or touch.",
    callback = function()
        print("Ripple button pressed")
    end,
})

tab2:CreateButton({ name = "Normal Button For Comparison" })

tab2:CreateSection({ name = "Progress Bar" })

tab2:CreateProgressBar({ name = "Static Progress", icon = 91452555903853, value = 65 })

local download = tab2:CreateProgressBar({
    name = "Fake Download",
    icon = 108115485663409,
    description = "Animates from 0 to 100 on a loop through Set.",
})

tab2:CreateProgressBar({
    name = "XP This Level",
    icon = 80387863064905,
    value = 340,
    max = 500,
    suffix = "xp",
})

task.spawn(function()
    local progress = 0
    while true do
        task.wait(2)
        progress = (progress + 10) % 110
        download:Set(progress)
    end
end)

tab2:CreateSection({ name = "Scroll Hint" })

tab2:CreateScrollHint({ text = "You found it" })

-- Devlog 3: Tooltips ------------------------------------------------------------
local tab3 = window:CreateTab({ name = "Devlog 3", icon = 100604009889706 })

tab3:CreateSection({ name = "Tooltips" })

tab3:CreateButton({ name = "Docs", tooltip = "Opens the documentation site in a new tab." })
tab3:CreateButton({ name = "Guide", tooltip = "A short walkthrough for first-time users." })
tab3:CreateToggle({
    name = "Lorem",
    tooltip = "Lorem ipsum dolor sit amet consectetur adipisicing elit",
})

-- Devlog 4: Segmented Picker, Shimmer Label, Greeting Intro --------------------
local tab4 = window:CreateTab({ name = "Devlog 4", icon = 87024289287775 })

tab4:CreateSection({ name = "Segmented Picker" })

tab4:CreateSegmentedPicker({
    name = "Plan",
    options = {
        "Free",
        { text = "Premium", options = { "Monthly", "Annual" } },
    },
    value = "Monthly",
    callback = function(value)
        print("Plan:", value)
    end,
})

tab4:CreateSegmentedPicker({
    name = "Difficulty",
    options = { "Low", "Medium", "High" },
    value = "Medium",
    description = "A plain three way split, no nested options.",
    callback = function(value)
        print("Difficulty:", value)
    end,
})

tab4:CreateSection({ name = "Text Shimmer" })

local shimmerLines = { "Text Shimmer", "Rayfield Gen 3", "Now In Motion", "Ship It" }
local shimmerIndex = 1
local shimmer = tab4:CreateShimmerLabel({ text = shimmerLines[1] })

tab4:CreateSlider({
    name = "Shimmer speed",
    range = { 0.6, 4 },
    increment = 0.1,
    value = 1.4,
    suffix = "s",
    callback = function(value)
        shimmer:SetSpeed(value)
    end,
})

tab4:CreateSlider({
    name = "Shimmer spread",
    range = { 5, 60 },
    value = 20,
    suffix = "%",
    callback = function(value)
        shimmer:SetSpread(value / 100)
    end,
})

tab4:CreateButton({
    name = "Rename shimmer",
    description = "Cycles a new line on every tap.",
    callback = function()
        shimmerIndex = (shimmerIndex % #shimmerLines) + 1
        shimmer:Set(shimmerLines[shimmerIndex])
    end,
})

tab4:CreateSection({ name = "Greeting Intro" })

tab4:CreateButton({
    name = "Play greeting",
    description = "A hello sequence, then a curved wipe reveals the menu again.",
    callback = function()
        window:PlayGreeting({ texts = { "Hello", "你好", "こんにちは", "olá" } })
    end,
})

-- Devlog 5: tab dock redesign, HSV Color Picker rebuild, Gradient Picker, Glow control -------
local tab5 = window:CreateTab({ name = "Devlog 5", icon = 91452555903853 })

tab5:CreateSection({ name = "Tabs" })

tab5:CreateSegmentedPicker({
    name = "Tab style",
    options = { "Accent", "White" },
    value = "Accent",
    description = "The shared pill behind the active tab: tinted to the accent colour with a glow, or plain white.",
    callback = function(value)
        window:SetTabStyle(if value == "White" then "white" else "accent")
    end,
})

tab5:CreateToggle({
    name = "Tab accent glow",
    value = true,
    callback = function(value)
        window:SetTabAccentGlow(value)
    end,
})

tab5:CreateSection({ name = "Single color picker" })

local solidPicker = tab5:CreateColorPicker({
    name = "Solid color",
    color = Color3.fromRGB(255, 214, 10),
    glow = true,
    callback = function(value)
        print("Solid color:", value)
    end,
})

tab5:CreateToggle({
    name = "Solid glow",
    value = true,
    callback = function(value)
        solidPicker:SetGlow(value)
    end,
})

tab5:CreateSection({ name = "Gradient color picker" })

local connectGradientToAccent = false

local themeGradient = tab5:CreateGradientPicker({
    name = "Theme gradient",
    gradient = { Color3.fromRGB(52, 199, 89), Color3.fromRGB(10, 132, 255), Color3.fromRGB(175, 82, 222) },
    glow = true,
    callback = function(value)
        if connectGradientToAccent then
            window:SetTabAccentColor(value)
        end
    end,
})

tab5:CreateToggle({
    name = "Gradient glow",
    value = true,
    callback = function(value)
        themeGradient:SetGlow(value)
    end,
})

tab5:CreateToggle({
    name = "Connect gradient to tab accent",
    value = false,
    description = "Live-ties the tab pill's fill to the whole gradient, not just one stop.",
    callback = function(value)
        connectGradientToAccent = value
        if value then
            window:SetTabAccentColor(themeGradient.value)
        end
    end,
})

-- Devlog 6: Hold Button, Collapsible Section, Update Log --------------------------------------
local tab6 = window:CreateTab({ name = "Devlog 6", icon = 125626312718314 })
local lockedTab = window:CreateTab({ name = "Locked", icon = 91452555903853, locked = true })
lockedTab:CreateSection({ name = "Unlocked!" })
lockedTab:CreateButton({ name = "You made it in", callback = function() end })

tab6:CreateSection({ name = "New buttons" })

tab6:CreateToggle({
    name = "Unlock the \"Locked\" tab",
    value = false,
    callback = function(value)
        lockedTab:SetLocked(not value)
    end,
})

tab6:CreateHoldButton({
    name = "Hold to wipe save",
    description = "Press and hold to confirm.",
    danger = true,
    holdDuration = 1.2,
    callback = function()
        print("Save wiped!")
    end,
})

local lockedHold = tab6:CreateHoldButton({
    name = "Locked hold button",
    description = "Locked - try holding it, nothing should happen.",
    locked = true,
    callback = function()
        print("this should never fire while locked")
    end,
})

tab6:CreateToggle({
    name = "Unlock the button above",
    value = false,
    callback = function(value)
        lockedHold:SetLocked(not value)
    end,
})

tab6:CreateSection({ name = "Confirmation dialog" })

-- Window:Popup already covers this ask outright (title/description/buttons, dim backdrop,
-- centred) - no new component needed, just wiring a couple of real dialogs to it.
tab6:CreateButton({
    name = "Ask me (dialog)",
    description = "Cancel/Reset, Confirm/Decline - a two-choice confirmation.",
    callback = function()
        window:Popup({
            title = "Reset save data?",
            content = "This clears every saved setting and can't be undone.",
            options = {
                { text = "Cancel", style = "neutral" },
                {
                    text = "Reset",
                    style = "danger",
                    callback = function()
                        print("Save data reset!")
                    end,
                },
            },
        })
    end,
})

tab6:CreateButton({
    name = "Single accept dialog",
    description = "One acknowledge button, no cancel path.",
    callback = function()
        window:Popup({
            title = "Update installed",
            content = "Rayfield Gen 3 is now on Devlog 6.",
            options = {
                { text = "Got it", style = "primary" },
            },
        })
    end,
})

tab6:CreateSection({ name = "Sections" })

local advanced = tab6:CreateCollapsible({ name = "Advanced" })
advanced:CreateToggle({ name = "Nested toggle", value = false })
advanced:CreateSlider({ name = "Nested slider", range = { 0, 100 }, value = 50 })

tab6:CreateSection({ name = "Dropdown" })

local weaponDropdown = tab6:CreateDropdown({
    name = "Weapon",
    placeholder = "Choose a weapon",
    sections = {
        { name = "Melee", options = { "Sword", "Axe" } },
        { name = "Ranged", options = { "Bow", "Rifle" } },
    },
    callback = function(value)
        print("Weapon:", value)
    end,
})

tab6:CreateButton({
    name = "Reset dropdown",
    callback = function()
        weaponDropdown:Reset()
    end,
})

local lockedDropdown = tab6:CreateDropdown({
    name = "Locked dropdown",
    options = { "One", "Two", "Three" },
    locked = true,
})

tab6:CreateToggle({
    name = "Unlock the dropdown above",
    value = false,
    callback = function(value)
        lockedDropdown:SetLocked(not value)
    end,
})

tab6:CreateSection({ name = "Update log" })

tab6:CreateChangelog({
    version = "v6",
    date = "Jul 13",
    entries = {
        { tag = "ADDED", text = "Hold button, collapsible sections, and an inline update log" },
        { tag = "ADDED", text = "Section headers and a live search bar inside dropdowns" },
        { tag = "FIXED", text = "Locked elements now block input from every angle, not just clicks" },
        { tag = "CHANGED", text = "Preset color themes and a global font picker" },
        { tag = "REMOVED", text = "The old fixed window-size assumption at startup" },
    },
})

window:Navigate("Devlog 1")

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
    icon = 80387863064905, -- built-in Rayfield glyph - also what the loading splash's icon defaults to

    -- Devlog 14: live machine translation - every name/description in this whole file (window
    -- title, tab names, every toggle/button below) translates on its own the moment it's shown
    -- in a non-English locale, with zero manual translation table needed. See autoTranslate.luau.
    autoTranslate = true,
    -- Pinned rather than left to locale.detect(): this smoke-test window should always start in
    -- the language it's actually written in, regardless of whose Roblox account opens it - flip
    -- the Settings > Language dropdown by hand to see autoTranslate do its thing on purpose,
    -- instead of it firing automatically off a tester's own account locale.
    locale = "en",
    -- Devlog 6: an initial custom size (still screen-fit the same way the built-in default is,
    -- see windowSizing.luau) - left commented here so this smoke-test window keeps the size
    -- it's been tested at all session; uncomment to try it.
    -- size = Vector2.new(600, 650),

    -- Devlog 11: loading splash on the very first Show() - icon/title default to the window's
    -- own, tips cycle like PlayGreeting's texts. Player can still switch it off from Settings >
    -- Window > "Loading Animation" (only shown at all because this table is present).
    loading = {
        title = "Gen 3 Changes",
        tips = { "Fetching modules...", "Building the UI...", "Almost there..." },
    },

    -- Devlog 13: turns on Settings > Configurations (save/load/delete named configs, plus the
    -- new clipboard export/import) - that whole section is gated on this table being present at
    -- all, so it's otherwise invisible for a window that doesn't want config saving.
    configuration = { fileName = "Gen3Demo" },
})

-- debug hook for the test harness: lets an external probe call window:Navigate(...) directly
-- instead of simulating clicks on the tab bar. Harmless to leave in a smoke-test script.
_G.RayfieldGen3Window = window

-- Tags: already a real feature (window:CreateTag), just never demoed in this smoke-test file -
-- the small pills that sit next to the title bar, dev-configured (icon/text/color/order at
-- creation, Set()/SetColor()/SetText()/SetIcon() at runtime). Two here to match the reference
-- style: a version badge + a credit handle.
window:CreateTag({ text = "v3.0.0", color = Color3.fromRGB(0, 170, 127) })
window:CreateTag({ text = "@opploop", icon = 80387863064905, color = Color3.fromRGB(184, 61, 219) })

-- Devlog 1: Checkbox, CopyButton, FlipButton --------------------------------
local tab = window:CreateTab({ name = "Devlog 1", icon = 93364949241311 })

-- Checkbox --------------------------------------------------------------------
tab:CreateSection({ name = "Checkbox" })

-- Devlog 13: captured into a local (rather than the usual bare call) so the guided tour set up
-- near the bottom of this file has a real element to point its first step at.
local basicCheckbox = tab:CreateCheckbox({
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

local toggleFromCodeButton = tab:CreateButton({
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

local copyTextButton = tab:CreateCopyButton({
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
    -- Devlog 6 icons: real Lucide icons now (icons.luau), same HttpGet+loadstring fetch every
    -- other dev-loadstring asset uses - "pack:icon-name" resolves through image.resolve.
    icon = "lucide:trash-2",
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
    icon = "lucide:message-circle",
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

-- Devlog 8: "Select all"/"Clear" sit between the search bar and the option list, and both
-- scope to whatever the active search filter leaves visible - try filtering (e.g. "F") then
-- hitting Clear, only the filtered-in options should drop out of the selection.
tab6:CreateDropdown({
    name = "Multi select",
    multiSelect = true,
    options = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight" },
    callback = function(value)
        print("Multi select:", table.concat(value, ", "))
    end,
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

-- Devlog 9: Label, Paragraph ------------------------------------------------------------------
local tab9 = window:CreateTab({ name = "Devlog 9", icon = 100604009889706 })

tab9:CreateSection({ name = "Label" })

tab9:CreateLabel({ text = "A line of text on its own, with no card around it." })

tab9:CreateLabel({
    text = "With an icon beside it.",
    icon = "lucide:house",
})

tab9:CreateLabel({
    text = "Long enough to wrap onto a second line once the window is pulled in, "
        .. "which it does on its own.",
})

tab9:CreateSection({ name = "Paragraph" })

tab9:CreateParagraph({
    title = "Title and body",
    content = "A title with a body under it, on a card of its own. This is for copy that is "
        .. "too long to hang off an element as a description.",
})

tab9:CreateParagraph({ title = "Title only" })

tab9:CreateParagraph({
    content = "Body only, no title. Either half is dropped when it is empty, so this is just "
        .. "the copy on a card.",
})

tab9:CreateParagraph({
    title = "With an icon",
    content = "The icon sits beside the title, the same way it does on a section.",
    icon = "lucide:house",
})

tab9:CreateSection({ name = "Set" })

tab9:CreateLabel({ text = "Press the button below." })

local demoParagraph = tab9:CreateParagraph({
    title = "Before",
    content = "This body is about to change.",
})

tab9:CreateButton({
    name = "Change both",
    callback = function()
        demoParagraph:Set({ title = "After", content = "Both halves just changed at once." })
    end,
})

-- Devlog 10: Divider ----------------------------------------------------------------------------
local tab10 = window:CreateTab({ name = "Devlog 10", icon = 88479147175134 })

tab10:CreateSection({ name = "Divider" })

tab10:CreateDivider() -- plain line, no caption

tab10:CreateDivider({ text = "Advanced" })

tab10:CreateToggle({ name = "Verbose Logging", value = false })

tab10:CreateInput({ name = "Endpoint", value = "localhost" })

tab10:CreateDivider({ text = "Spacing only, no line below this" })

tab10:CreateDivider({ line = false, height = 48 })

tab10:CreateButton({ name = "Sitting after 48px of nothing" })

tab10:CreateDivider({ text = "Tight", spacing = "tight" })

tab10:CreateButton({ name = "Close above and below" })

tab10:CreateDivider({ text = "Loose", spacing = "loose" })

tab10:CreateButton({ name = "Open above and below" })

-- Devlog 14: notifications, live status, confirm-to-delete, floating HUD, hidden tab ------------
local tab14 = window:CreateTab({ name = "Devlog 14", icon = 88479147175134 })

tab14:CreateSection({ name = "Notifications" })

tab14:CreateButton({
    name = "Progress notification",
    description = "One card, updated in place across a fake 5-step job - not five separate toasts.",
    icon = "lucide:loader",
    callback = function()
        local n = window:Notify({ title = "Importing configs", content = "Starting...", persist = true })
        task.spawn(function()
            for i = 1, 5 do
                task.wait(0.4)
                n:SetProgress(i / 5)
                n:ChangeDescription(("Imported %d/5"):format(i))
            end
            task.wait(0.6)
            n:ChangeTitle("Import complete")
            task.wait(1.2)
            n:Destroy()
        end)
    end,
})

tab14:CreateButton({
    name = "Fire NotifyOnce x3",
    -- 2s, not 5s - long enough to prove the same-key dedup within one click (the loop below fires
    -- 3 calls a frame apart), short enough that clicking the button again a couple seconds later
    -- still shows something instead of looking dead - the cooldown key here is fixed
    -- ("devlog14-demo") on purpose, so it *also* dedupes across separate clicks, not just within
    -- one - that's the whole point of the demo, but a 5s window made every re-click for the next
    -- 5 seconds look like nothing happened.
    description = "3 rapid calls, same key - only the first shows. Wait 2s and click again for a fresh one.",
    icon = "lucide:bell-off",
    callback = function()
        for i = 1, 3 do
            window:NotifyOnce("devlog14-demo", { title = "Deduped toast", content = "Call #" .. i }, 2)
        end
    end,
})

tab14:CreateSection({ name = "Live status" })

-- forward-declared for the same reason importButton below is: the callback needs to call
-- :SetStatus on this toggle's own handle, which doesn't exist yet while CreateToggle's argument
-- table is still being built - a plain `local statusToggle = tab14:CreateToggle({...})` would
-- have the callback close over a global of the same name instead (nil), not this local.
local statusToggle
statusToggle = tab14:CreateToggle({
    name = "Auto Farm",
    description = "Flip this on - the line below updates every second while it runs, in place.",
    icon = "lucide:bot",
    callback = function(state)
        if not state then
            return
        end
        task.spawn(function()
            for i = 1, 12 do
                if not statusToggle.value then
                    return
                end
                statusToggle:SetStatus(("Farming... %d/12"):format(i))
                task.wait(1)
            end
            if statusToggle.value then
                statusToggle:SetStatus("Done - 12/12")
            end
        end)
    end,
})

-- forward-declared so the callback below can reference the button's own handle to call
-- :SetStatus on itself once CreateButton has actually returned it
local importButton
importButton = tab14:CreateButton({
    name = "Import All",
    description = "SetStatus works on a button too, not just a toggle.",
    icon = "lucide:download",
    callback = function()
        importButton:SetStatus("Imported 12/12 items")
    end,
})

tab14:CreateSection({ name = "Confirm before delete" })

tab14:CreateButton({
    name = "Delete everything",
    description = "doubleClick = true - first click just arms it, second click within 3s confirms.",
    icon = "lucide:trash-2",
    doubleClick = true,
    callback = function()
        window:NotifySuccess({ title = "Deleted", content = "(not really - this is a demo)" })
    end,
})

tab14:CreateSection({ name = "Floating HUD" })

local demoHud = nil
tab14:CreateToggle({
    name = "Show floating HUD",
    description = "A small draggable chip parented outside the window - stays up even if you hide this menu.",
    icon = "lucide:layout-template",
    callback = function(state)
        if state then
            demoHud = window:CreateHUD({ text = "Devlog 14 · drag me" })
        elseif demoHud then
            demoHud:Destroy()
            demoHud = nil
        end
    end,
})

tab14:CreateSection({ name = "Hidden tab + card link" })

local diagnosticsTab = window:CreateHiddenTab({ name = "Diagnostics" })
diagnosticsTab:CreateLabel({ text = "This tab isn't in the tab bar above - only reachable from the button below." })
diagnosticsTab:CreateParagraph({
    title = "Why this pattern",
    content = "Both hub scripts this idea was mined from use it for exactly this: a drill-down screen that would clutter the main tab list if it sat there permanently.",
})
diagnosticsTab:CreateButton({
    name = "Back to Devlog 14",
    callback = function()
        tab14:Select()
    end,
})

tab14:CreateButton({
    name = "Open Diagnostics",
    description = "window:CreateHiddenTab({...}) + a button that calls :Select() on it - that's the whole pattern.",
    icon = "lucide:layout-dashboard",
    callback = function()
        diagnosticsTab:Select()
    end,
})

tab14:CreateSection({ name = "Side by side" })

-- Row group: children build compact and share the width, wrapping to a new row if the window's
-- too narrow to fit them all - already existed (tab.luau/group.luau), just never demoed here.
local sideRow = tab14:CreateGroup({ direction = "row" })
sideRow:CreateToggle({ name = "Left Toggle" })
sideRow:CreateToggle({ name = "Right Toggle" })

tab14:CreateSection({ name = "Two columns (\"Basic\" / \"Advanced\" side by side)" })

-- A row whose own children are columns instead of compact leaves - nest a Group inside a Group.
-- Each column is full width *of its own half*, so a Section/toggle inside behaves exactly like
-- it would in a normal tab - this is the "grid" group.luau's own header comment describes.
local columnsRow = tab14:CreateGroup({ direction = "row" })

local basicColumn = columnsRow:CreateGroup({ direction = "column" })
basicColumn:CreateSection({ name = "Basic" })
basicColumn:CreateToggle({ name = "Auto Jump" })
basicColumn:CreateToggle({ name = "Auto Sprint" })

local advancedColumn = columnsRow:CreateGroup({ direction = "column" })
advancedColumn:CreateSection({ name = "Advanced" })
advancedColumn:CreateToggle({ name = "Bypass Anti-AFK" })
advancedColumn:CreateToggle({ name = "Bypass Rate Limit" })

tab14:CreateSection({ name = "Two collapsible panels, side by side" })

-- Group:CreateCollapsible didn't exist until now - only Tab had it. Collapsible only reads
-- window/tabPage/forgetState off its host (same minimal contract Tabbox's fake-host trick
-- relies on), so a Group already satisfied it once the method itself was wired up. Same row-of-
-- columns shape as the plain "Basic"/"Advanced" columns above, just with each column's content
-- wrapped in its own collapsible header instead of a plain Section - the two panels expand and
-- collapse completely independently of each other.
local panelsRow = tab14:CreateGroup({ direction = "row" })

local basicPanelColumn = panelsRow:CreateGroup({ direction = "column" })
-- forgetState on these: same names as the plain-column demo above on purpose (the point is
-- showing the identical layout with a collapsible header instead of a plain Section), which
-- would otherwise collide on the same auto-derived config flag - live-caught as "Rayfield:
-- duplicate config flag 'AutoJump', saving this one as 'AutoJump2'" the first time this whole
-- file actually ran end to end. Neither demo's toggles need to persist anyway.
local basicPanel = basicPanelColumn:CreateCollapsible({ name = "Basic", expanded = true })
basicPanel:CreateToggle({ name = "Auto Jump", forgetState = true })
basicPanel:CreateToggle({ name = "Auto Sprint", forgetState = true })

local advancedPanelColumn = panelsRow:CreateGroup({ direction = "column" })
local advancedPanel = advancedPanelColumn:CreateCollapsible({ name = "Advanced" })
advancedPanel:CreateToggle({ name = "Bypass Anti-AFK", forgetState = true })
advancedPanel:CreateToggle({ name = "Bypass Rate Limit", forgetState = true })

-- Not demoed above (nothing to click, they're either invisible improvements or need a real
-- failure to show off): the singleton window registry (auto-unloads a same-named window left
-- from a previous run of this exact script), Window:OnRenderFreeze (detects a stalled render
-- thread), Window:DebugLog + the "Debug Logging (F9)" Settings toggle (already live there),
-- configuration.scopeByPlace (nests saved configs per game.PlaceId), and the debounced autosave
-- (rapid changes now collapse into one write instead of one per change).

window:Navigate("Devlog 1")

-- Devlog 13: guided onboarding tour - plays once automatically on first show (see
-- Window:_firstShow's own tour block), re-playable from Settings > "Replay Tour". Set as a plain
-- property assignment rather than passed inline at CreateWindow, since the targets below don't
-- exist until the tab/element calls above have actually run - _firstShow itself only reaches its
-- own tour check after several task.wait()s deeper in the reveal sequence, well after this
-- top-level script chunk finishes, so setting it here lands in plenty of time.
window.tourSteps = {
    {
        target = basicCheckbox,
        title = "Checkboxes",
        description = "A compact alternative to a toggle - supports flags, config saving, and its own description text.",
    },
    {
        target = toggleFromCodeButton,
        title = "Driving elements from code",
        description = "Every element returns a handle you can call :Set() on later, from anywhere in your script.",
    },
    {
        target = copyTextButton,
        title = "Copy buttons",
        description = "One click copies the configured text to the clipboard, with its own little pop-and-checkmark animation.",
    },
}

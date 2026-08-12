local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rayfield = require(ReplicatedStorage.Rayfield)

-- Let the viewport settle before opening, so the window fits to the full screen size.
task.wait(2)

-- Localization. Keys are the English source strings exactly as they read in the UI. A partial table
-- is fine, anything left out stays in English. German is added at runtime to show that path too.
local translations = {
    fr = {
        ["Gameplay"] = "Jeu",
        ["Interface"] = "Interface",
        ["Auto Sprint"] = "Sprint auto",
        ["Reduced Motion"] = "Animations réduites",
        ["Field of View"] = "Champ de vision",
        ["Player Name"] = "Nom du joueur",
    },
    es = {
        ["Gameplay"] = "Juego",
        ["Interface"] = "Interfaz",
        ["Auto Sprint"] = "Sprint automático",
        ["Reduced Motion"] = "Movimiento reducido",
        ["Field of View"] = "Campo de visión",
        ["Player Name"] = "Nombre del jugador",
    },
}

local window = Rayfield:CreateWindow({
    name = "Example",
    subtitle = "Rayfield Gen2",
    theme = "cobalt",
    translations = translations,
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "ExampleConfigFile",
    },
})

-- Topbar tag, next to the window title.
window:CreateTag({ text = "Beta", color = Color3.fromRGB(255, 175, 15) })

-- Home ----------------------------------------------------------------------
local home = window:CreateTab({ name = "Home", icon = 93364949241311 })

home:CreateSection({ name = "Gameplay" })

home:CreateToggle({
    name = "Auto Sprint",
    tooltip = "Sprints automatically once your stamina allows it.",
    value = true,
    callback = function(value)
        print("Auto Sprint:", value)
    end,
})

home:CreateToggle({
    name = "Reduced Motion",
    description = "Disables screen shake and camera effects for a smoother experience.",
    callback = function(value)
        print("Reduced Motion:", value)
    end,
})

home:CreateSlider({
    name = "Field of View",
    range = { 70, 120 },
    increment = 1,
    value = 90,
    suffix = "°",
    callback = function(value)
        workspace.CurrentCamera.FieldOfView = value
    end,
})

home:CreateSection({ name = "Interface" })

home:CreateToggle({ name = "Show FPS Counter" })

home:CreateCheckbox({
    name = "Compact HUD",
    description = "A checkbox is a compact alternative to a toggle - same flag/config contract.",
    callback = function(value)
        print("Compact HUD:", value)
    end,
})

home:CreateDropdown({
    name = "Quality",
    options = { "Low", "Medium", "High", "Ultra" },
    value = "High",
    callback = function(value)
        print("Quality:", value)
    end,
})

home:CreateSection({ name = "Feedback" })

home:CreateButton({
    name = "Send Notification",
    icon = 93364949241311,
    callback = function()
        window:Notify({
            title = "Auto-saved",
            content = "Your configuration was saved.",
            icon = 125823673784681,
        })
    end,
})

home:CreateButton({
    name = "Send Toast",
    icon = 125823673784681,
    callback = function()
        window:Toast({ title = "Saved", icon = 125823673784681 })
    end,
})

home:CreateButton({
    name = "Open Popup",
    icon = 83277910885129,
    callback = function()
        window:Popup({
            title = "Reset everything?",
            content = "This clears every saved value and puts the menu back to its defaults. You can't undo it.",
            icon = 83277910885129,
            options = {
                { text = "Cancel" },
                { text = "Reset", style = "danger" },
            },
        })
    end,
})

home:CreateCopyButton({
    name = "Discord Invite",
    description = "Pops, squishes, then shows a checkmark for 2 seconds. Falls back quietly without one.",
    text = "https://discord.gg/example",
    callback = function(success)
        print("Copied invite:", success)
    end,
})

home:CreateFlipButton({
    name = "Click Me",
    secondaryName = "Nice!",
    description = "Hovering flips the title to its second face; clicking still runs the callback.",
    callback = function()
        print("Flip button pressed")
    end,
})

home:CreateRippleButton({
    name = "Ripple Me",
    description = "Ripple spreads from wherever you press, clipped to the card's corners.",
    callback = function()
        print("Ripple button pressed")
    end,
})

home:CreateScrollHint({ text = "Keep scrolling" })

-- Combat --------------------------------------------------------------------
local combat = window:CreateTab({ name = "Combat", icon = 84750991656135 })

combat:CreateSection({ name = "Aiming" })

combat:CreateToggle({ name = "Aimbot", value = true })

combat:CreateSlider({ name = "Smoothness", range = { 0, 100 }, value = 40, suffix = "%" })

combat:CreateDropdown({
    name = "Modules",
    description = "Pick any combination of modules to load.",
    multiSelect = true,
    options = { "Aimbot", "ESP", "Triggerbot", "Fly" },
    value = { "ESP" },
    placeholder = "None selected",
})

-- Fields --------------------------------------------------------------------
local fields = window:CreateTab({ name = "Fields", icon = 100604009889706 })

fields:CreateSection({ name = "Setup" })

fields:CreateInput({ name = "Player Name", placeholder = "Enter a name" })

fields:CreateInput({
    name = "Max Players",
    description = "Numeric only, commits when you click away or press enter.",
    numeric = true,
    value = "16",
})

fields:CreateKeybind({ name = "Sprint", value = Enum.KeyCode.LeftShift })

fields:CreateKeybind({
    name = "Zoom",
    description = "Hold mode: fires true once held, false on release.",
    value = Enum.KeyCode.C,
    hold = true,
    callback = function(holding)
        print("Zoom:", holding)
    end,
})

fields:CreateColorPicker({ name = "Highlight", color = Color3.fromRGB(96, 205, 255) })

-- Stats ---------------------------------------------------------------------
local stats = window:CreateTab({ name = "Stats", icon = 85925158736685 })

stats:CreateSection({ name = "Session" })

local revenue = stats:CreateStat({ name = "Revenue", prefix = "$", value = 12400 })
local kills = stats:CreateStat({ name = "Kills", value = 128 })

stats:CreateButton({
    name = "Simulate Round",
    callback = function()
        revenue:Set(revenue.value + math.random(500, 3000))
        kills:Set(kills.value + math.random(1, 20))
    end,
})

stats:CreateSection({ name = "Progress" })

local xp = stats:CreateProgressBar({ name = "XP This Level", value = 340, max = 500, suffix = "xp" })

stats:CreateButton({
    name = "Add XP",
    callback = function()
        xp:Set(math.min(xp.value + 40, 500))
    end,
})

-- Layout --------------------------------------------------------------------
local layout = window:CreateTab({ name = "Layout", icon = 84750991656135 })

layout:CreateSection({ name = "Loadout" })

local grid = layout:CreateGroup()

local leftColumn = grid:CreateGroup({ direction = "column" })
-- own flag: "Aimbot" is taken by the Combat toggle and derived flags must stay unique
leftColumn:CreateToggle({ name = "Aimbot", flag = "LoadoutAimbot", value = true })
leftColumn:CreateToggle({ name = "Triggerbot" })

local rightColumn = grid:CreateGroup({ direction = "column" })
rightColumn:CreateToggle({ name = "ESP", value = true })
rightColumn:CreateToggle({ name = "Tracers" })

layout:CreateSection({ name = "Quick Actions" })

-- checkbox/copybutton/flipbutton all render compact in a row, same as button/toggle/stat/slider
local quickRow = layout:CreateGroup()
quickRow:CreateCheckbox({ name = "HUD" })
quickRow:CreateCopyButton({ name = "Copy ID", text = "PLAYER-0001" })
quickRow:CreateFlipButton({ name = "Info", secondaryName = "v1.0.0" })

-- Extras ----------------------------------------------------------------------
local extras = window:CreateTab({ name = "Extras", icon = 91452555903853 })

extras:CreateSection({ name = "Favourites" })

extras:CreatePinnedList({
    items = {
        { icon = 129180860773723, title = "Settings", subtitle = "Menu preferences", pinned = true },
        { icon = 100604009889706, title = "Search", subtitle = "Find anything fast" },
        { icon = 84750991656135, title = "Combat", subtitle = "Aimbot, ESP, more" },
    },
})

extras:CreateSection({ name = "Cursor Tag" })

extras:CreateCursorTag({ text = "Here", placeholder = "Hover to see the tag trail your cursor" })

-- Language ------------------------------------------------------------------
local language = window:CreateTab({ name = "Language", icon = 100604009889706 })

language:CreateSection({ name = "Localization" })

local localeIds = { English = "en", ["Français"] = "fr", ["Español"] = "es", ["Deutsch"] = "de" }

language:CreateDropdown({
    name = "Language",
    description = "Switches every localized label in place. Untranslated strings stay in English.",
    options = { "English", "Français", "Español", "Deutsch" },
    value = "English",
    forgetState = true,
    callback = function(value)
        if value == "Deutsch" then
            window:RegisterTranslations({
                de = {
                    ["Gameplay"] = "Spiel",
                    ["Interface"] = "Benutzeroberfläche",
                    ["Auto Sprint"] = "Auto-Sprint",
                    ["Field of View"] = "Sichtfeld",
                    ["Player Name"] = "Spielername",
                },
            })
        end
        window:SetLocale(localeIds[value] or "en")
    end,
})

window:Navigate("Home")

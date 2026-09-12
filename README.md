# Rayfield Gen3

A Roblox UI library for script hubs, built on Rayfield Gen2. One `loadstring`, one `CreateWindow`
call, and you have a themed, draggable, persistent window to hang your features off.

- **34 element types** on every container — buttons, toggles, sliders, dropdowns, color and
  gradient pickers, keybinds, stats, status cards, a drag-to-reorder list, a searchable item grid,
  collapsibles, nested tab boxes, groups that lay out in rows or columns.
- **Config saving** that survives a rejoin, per-element, keyed by a `flag` you choose.
- **Ten themes**, live-swappable, plus per-window overrides for accent, corner radius and shadow.
- **Automatic translation** of every label through the player's own locale.
- Top-bar or sidebar tab layouts, a guided tour, toasts, popups, notifications, a floating HUD
  chip, a key system, and a built-in Settings tab you get for free.

Licensed under the [Mozilla Public License 2.0](LICENSE).

## Loading it

The fastest path is the single-file bundle — one HTTP request for the whole library:

```lua
local Rayfield = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/opploop/67676767/main/dist/rayfield.lua"
))()
```

Measured on a real executor: ~87ms to fetch (~1.3MB) plus ~14ms to compile and run every module.
It builds a virtual module tree in memory and writes nothing to `ReplicatedStorage`.

If you would rather fetch the source file-by-file (useful when you want the real module tree under
`ReplicatedStorage.Rayfield` to inspect), use the loader instead. It fetches up to 12 files
concurrently — about 0.4s for all 102 modules:

```lua
local Rayfield = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/opploop/67676767/main/scripts/loader.luau"
))()
```

Both track `main`. Pass a 40-character commit SHA to the loader to pin a shipped hub to a version
that will not move under it later:

```lua
))("0123456789abcdef0123456789abcdef01234567")
```

> The raw CDN can serve the *previous* contents of a `main` URL for a few minutes after a push. If
> you are testing a change you just made, fetch a pinned SHA URL — those are immutable and immediate.

## A window, start to finish

```lua
local Rayfield = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/opploop/67676767/main/dist/rayfield.lua"
))()

local Window = Rayfield:CreateWindow({
    name = "My Hub",
    subtitle = "v1.0",
    configuration = { enabled = true, folder = "MyHub" },
})

local Main = Window:CreateTab({ name = "Main", icon = "lucide:zap" })

Main:CreateToggle({
    name = "Auto farm",
    description = "Collects every spawn in range.",
    flag = "autoFarm",
    callback = function(on)
        print("auto farm:", on)
    end,
})

Main:CreateSlider({
    name = "Range",
    range = { 0, 500 },
    value = 120,
    flag = "range",
    callback = function(value)
        print("range:", value)
    end,
})

Main:CreateButton({
    name = "Collect now",
    callback = function()
        Window:NotifySuccess({ title = "Done", content = "Collected." })
    end,
})
```

`value` is the property for a control's starting state everywhere (`default` is accepted as an
alias, for scripts carried over from upstream Rayfield). A `flag` is what ties the control to the
config file — make it unique across the window and derived from something stable, never from a
position or an index.

Nothing should yield between `CreateWindow` and the window appearing: `CreateWindow` shows a brief
splash and reveals the real window about a second later on its own. Build every tab and element in
that gap.

## Working on the library itself

Requires [Rokit](https://github.com/rojo-rbx/rokit) for the pinned toolchain (Lune, Rojo, StyLua,
Selene, luau-lsp).

```bash
make install   # fetch the pinned tools
make ci        # format check, lint, typecheck, tests, and the repo's own guards
make test      # just the suite, with coverage
make format    # apply formatting
```

`make ci` is what CI runs on every push, and it is the whole bar: 380 tests under Lune with no
Roblox or Studio involved, 75%+ line coverage enforced against a tracked per-file baseline, zero
lint findings, zero type errors, plus three repo-specific guards — the bundle matches `src/`, the
loader's file lists match `src/`, and every `UIListLayout` sets an explicit `SortOrder`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow and [SECURITY.md](SECURITY.md) for
reporting a vulnerability.

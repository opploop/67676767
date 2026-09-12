local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

-- Three public entry points the suite never called. Each is small enough that nothing was
-- obviously missing, which is exactly why they went unwatched: CreateSwitch and CreateHiddenTab
-- are thin wrappers whose whole job is to forward correctly, and a wrapper that forwards to the
-- wrong thing looks fine from the outside until a dev uses the name the docs gave them.
return function()
    local Window = helpers.requireComponent("window")

    local window

    local function makeWindow()
        window = Window.new({
            name = "API Surface Spec",
            configuration = { autoSave = false, autoLoad = false },
        })
        return window
    end

    local function makeTab()
        return makeWindow():CreateTab({ name = "Main" })
    end

    local function cleanup()
        if window and not window.unloaded then
            window:Unload()
        end
        window = nil
    end

    describe("CreateSwitch", function()
        afterEach(cleanup)

        it("is a Toggle under another name", function()
            local switch = makeTab():CreateSwitch({ name = "Switched", forgetState = true })

            expect(switch).to.be.ok()
            expect(switch.__type).to.equal("Toggle")
        end)

        it("carries state like the Toggle it is", function()
            local switch = makeTab():CreateSwitch({ name = "Switched", forgetState = true })

            expect(switch.value).to.equal(false)
            switch:Set(true)
            expect(switch.value).to.equal(true)
        end)

        it("honours a declared starting value, same as CreateToggle", function()
            -- `value`, not `default`: this fork standardised every control on `value` (dropdown,
            -- slider, colorpicker all take it) where upstream Rayfield used Default/CurrentValue.
            local switch = makeTab():CreateSwitch({ name = "On", value = true, forgetState = true })

            expect(switch.value).to.equal(true)
        end)

        it("forwards from a Group and a Collapsible too", function()
            local tab = makeTab()
            local column = tab:CreateGroup({ direction = "column" })
            local collapsible = tab:CreateCollapsible({ name = "Panel", expanded = true })

            expect(column:CreateSwitch({ name = "A", forgetState = true }).__type).to.equal("Toggle")
            expect(collapsible:CreateSwitch({ name = "B", forgetState = true }).__type).to.equal("Toggle")
        end)
    end)

    describe("CreateHiddenTab", function()
        afterEach(cleanup)

        it("builds a real tab with no entry in the dock", function()
            local w = makeWindow()
            local visible = w:CreateTab({ name = "Visible" })
            local hidden = w:CreateHiddenTab({ name = "Hidden" })

            expect(hidden.neglectSelector).to.equal(true)
            expect(hidden.tabPage).to.be.ok()
            expect(hidden.topbarItem).to.equal(nil)

            -- the contrast is the point: an ordinary tab does get the dock row
            expect(visible.neglectSelector).to.equal(false)
            expect(visible.topbarItem).to.be.ok()
        end)

        it("still counts as one of the window's tabs and hosts elements", function()
            local w = makeWindow()
            w:CreateTab({ name = "Visible" })
            local hidden = w:CreateHiddenTab({ name = "Hidden" })

            expect(table.find(w.tabs, hidden)).to.be.ok()
            expect(hidden:CreateToggle({ name = "Inside", forgetState = true })).to.be.ok()
        end)

        it("does not mutate the table it was handed", function()
            local w = makeWindow()
            w:CreateTab({ name = "Visible" })
            -- annotated: a sealed literal has no neglectSelector key to read back below
            local properties: { [string]: any } = { name = "Hidden" }

            w:CreateHiddenTab(properties)

            -- it sets neglectSelector on a CLONE. A caller reusing one properties table for
            -- several tabs would otherwise find every later tab silently hidden too.
            expect(properties.neglectSelector).to.equal(nil)
        end)

        it("keeps its elements out of the search results", function()
            local w = makeWindow()
            local visible = w:CreateTab({ name = "Visible" })
            local hidden = w:CreateHiddenTab({ name = "Hidden" })
            local found = visible:CreateToggle({ name = "Findable", forgetState = true })
            local buried = hidden:CreateToggle({ name = "Buried", forgetState = true })

            -- search refuses to open while the window is not interactive, and a window that
            -- was never shown counts as hidden
            w:Show()
            w.searchAction.interact.MouseButton1Click:Fire()
            expect(w._searching).to.equal(true)

            local gathered = {}
            for _, entry in w._searchUnits do
                gathered[entry.unit] = true
            end

            -- a hidden tab is a destination reached from a card, not a page a player browses,
            -- so search pulling its contents into the results would be a leak
            expect(gathered[found]).to.equal(true)
            expect(gathered[buried]).to.equal(nil)

            w.searchAction.interact.MouseButton1Click:Fire()
        end)

        it("takes an icon instead of a name, like any tab", function()
            local w = makeWindow()
            w:CreateTab({ name = "Visible" })

            expect(w:CreateHiddenTab({ icon = 100 }).neglectSelector).to.equal(true)
        end)
    end)

    -- `value` is this fork's canonical name for a control's starting state. Upstream Rayfield
    -- called it `Default`, so that is what a hub script carried over from it reaches for - and
    -- for a long time only keybind and colorpicker happened to read it, so on every other
    -- control a declared Default was accepted and silently dropped. These pin the alias down on
    -- one control per value type, so a future constructor that forgets it fails here.
    describe("default as an alias for value", function()
        afterEach(cleanup)

        it("starts a Toggle on", function()
            local tab = makeTab()

            expect(tab:CreateToggle({ name = "A", default = true, forgetState = true }).value).to.equal(true)
            expect(tab:CreateToggle({ name = "B", Default = true, forgetState = true }).value).to.equal(true)
        end)

        it("starts a Checkbox ticked", function()
            expect(makeTab():CreateCheckbox({ name = "A", default = true, forgetState = true }).value).to.equal(true)
        end)

        it("carries a number into Slider, Stat and ProgressBar", function()
            local tab = makeTab()

            expect(tab:CreateSlider({ name = "S", default = 25, forgetState = true }).value).to.equal(25)
            expect(tab:CreateStat({ name = "T", default = 5 }).value).to.equal(5)
            expect(tab:CreateProgressBar({ name = "P", default = 4, max = 10 }).value).to.equal(4)
        end)

        it("picks a Dropdown option and fills an Input", function()
            local tab = makeTab()
            local dropdown = tab:CreateDropdown({
                name = "D",
                options = { "Alpha", "Beta" },
                default = "Beta",
                forgetState = true,
            })

            -- a Dropdown normalises to a list even single-select, so the selection is value[1]
            expect(dropdown.value[1]).to.equal("Beta")
            expect(tab:CreateInput({ name = "I", default = "typed", forgetState = true }).value).to.equal("typed")
        end)

        it("selects a SegmentedPicker leaf", function()
            local picker = makeTab():CreateSegmentedPicker({
                name = "M",
                options = { "Basic", "Advanced", "Expert" },
                default = "Expert",
                forgetState = true,
            })

            expect(picker.value).to.equal("Expert")
        end)

        it("keeps working where it already did, on Keybind and ColorPicker", function()
            local tab = makeTab()
            local keybind = tab:CreateKeybind({ name = "K", default = Enum.KeyCode.H })
            local picker = tab:CreateColorPicker({ name = "C", default = Color3.fromRGB(20, 40, 60) })

            expect(keybind.value).to.equal(Enum.KeyCode.H)
            expect(picker.value).to.equal(Color3.fromRGB(20, 40, 60))
        end)

        it("loses to value when both are declared", function()
            local toggle = makeTab():CreateToggle({ name = "A", value = false, default = true, forgetState = true })

            -- `value` is the documented name, so it is the one that wins
            expect(toggle.value).to.equal(false)
        end)
    end)

    -- Upstream Rayfield Gen2 declares the whole persistence block as
    -- ConfigurationSaving = { Enabled, FolderName, FileName }. Reading only `configuration`
    -- meant a hub ported from upstream got no persistence whatsoever and nothing said so: the
    -- window builds, every control works, and not one flag is ever written or restored.
    describe("ConfigurationSaving as an alias for configuration", function()
        afterEach(cleanup)

        -- Every window it builds, not just the last one: assigning to the shared `window`
        -- upvalue orphaned the earlier window in any test that called this twice, and an
        -- un-unloaded window stays wired to the camera. That leak read as a failure in an
        -- unrelated viewport-rebinding spec, which counts the old camera's connections.
        local extras = {}

        local function configOf(properties)
            local built = Window.new(properties)
            table.insert(extras, built)
            return built.configuration
        end

        afterEach(function()
            for _, built in extras do
                if built and not built.unloaded then
                    built:Unload()
                end
            end
            table.clear(extras)
        end)

        it("maps Enabled onto both halves, since upstream has no separate switch", function()
            local config = configOf({
                name = "Legacy",
                ConfigurationSaving = { Enabled = true, FileName = "Hub", FolderName = "HubFolder" },
            })

            expect(config.autoSave).to.equal(true)
            expect(config.autoLoad).to.equal(true)
            expect(config.fileName).to.equal("Hub")
            expect(config.customFolder).to.equal("HubFolder")
        end)

        it("carries a disabled block through as disabled, not as absent", function()
            local config = configOf({ name = "Legacy off", ConfigurationSaving = { Enabled = false } })

            -- false, not nil: presence is what is read, so an explicit opt-out stays an opt-out
            expect(config.autoSave).to.equal(false)
            expect(config.autoLoad).to.equal(false)
        end)

        it("lets the canonical spelling win where both are given", function()
            local config = configOf({
                name = "Both",
                configuration = { autoSave = false, fileName = "canonical" },
                ConfigurationSaving = { Enabled = true, FileName = "legacy" },
            })

            expect(config.autoSave).to.equal(false)
            expect(config.fileName).to.equal("canonical")
            -- and the legacy block still fills in what the canonical one left out
            expect(config.autoLoad).to.equal(true)
        end)

        it("keeps an explicit scopeByPlace = false as false, not as absent", function()
            -- read by presence like the rest of the block: an `or` chain here turned a declared
            -- false into nil, which only ever looked harmless because the one consumer also does
            -- a truthiness check
            local config = configOf({
                name = "Scoped off",
                configuration = { scopeByPlace = false },
            })

            expect(config.scopeByPlace).to.equal(false)
            expect(configOf({ name = "Scoped on", configuration = { ScopeByPlace = true } }).scopeByPlace).to.equal(
                true
            )
        end)

        it("leaves a window with neither block with an empty configuration", function()
            expect(next(configOf({ name = "Neither" }))).to.equal(nil)
        end)
    end)

    describe("CreateHoverOverlay", function()
        afterEach(cleanup)

        it("builds a fully transparent white fill over its parent", function()
            local w = makeWindow()
            local host = w:CreateTab({ name = "Main" }).tabPage
            local overlay = w:CreateHoverOverlay(host)

            expect(overlay.Parent).to.equal(host)
            expect(overlay.Size).to.equal(UDim2.fromScale(1, 1))
            -- additive brighten: it starts invisible and hover tweens the transparency down, so
            -- anything but 1 here would light every element up permanently
            expect(overlay.BackgroundTransparency).to.equal(1)
            expect(overlay.BackgroundColor3).to.equal(Color3.fromRGB(255, 255, 255))
        end)

        it("sits above the parent's own fill but below its contents", function()
            local w = makeWindow()
            local overlay = w:CreateHoverOverlay(w:CreateTab({ name = "Main" }).tabPage)

            expect(overlay.ZIndex).to.equal(1)
        end)

        it("rounds itself to match the element it fills", function()
            local w = makeWindow()
            local overlay = w:CreateHoverOverlay(w:CreateTab({ name = "Main" }).tabPage)

            -- a square overlay on a rounded element shows its corners through the radius
            expect(overlay:FindFirstChildWhichIsA("UICorner")).to.be.ok()
        end)

        it("is what the interactive elements actually build", function()
            local tab = makeTab()

            -- six components call this; if the method regressed they would all lose their hover
            expect(tab:CreateButton({ name = "B", callback = function() end }).hoverOverlay).to.be.ok()
            expect(tab:CreateCheckbox({ name = "C", forgetState = true }).hoverOverlay).to.be.ok()
        end)
    end)
end

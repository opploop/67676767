local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component panel", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Panel Spec",
                configuration = { autoSave = false, autoLoad = false },
            })
            return window:CreateTab({ name = "Main" })
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        local function trialPanel(properties)
            local panel = makeTab():CreatePanel(properties or { name = "Trial" })
            local trial = panel:CreatePage({ name = "Trial", icon = "rbxassetid://1" })
            local config = panel:CreatePage({ name = "Config" })
            return panel, trial, config
        end

        it("opens on the first page, with a pill only for the others", function()
            local panel, trial, config = trialPanel()

            expect(panel:GetPage()).to.equal("Trial")
            expect(panel.title.Text).to.equal("Trial")
            expect(trial.frame.Visible).to.equal(true)
            expect(config.frame.Visible).to.equal(false)

            -- the header names where you are and offers where you can go, never both for one page
            expect(trial.pill.frame.Visible).to.equal(false)
            expect(config.pill.frame.Visible).to.equal(true)
        end)

        it("flips the header on a real click of a pill", function()
            local panel, trial, config = trialPanel()

            config.pill.interact.MouseButton1Click:Fire()

            expect(panel:GetPage()).to.equal("Config")
            expect(panel.title.Text).to.equal("Config")
            expect(config.frame.Visible).to.equal(true)
            expect(trial.frame.Visible).to.equal(false)
            expect(trial.pill.frame.Visible).to.equal(true)
            expect(config.pill.frame.Visible).to.equal(false)
        end)

        it("shows the current page's icon, and only when it has one", function()
            local panel = trialPanel()

            expect(panel.iconLabel.Visible).to.equal(true)
            panel:SelectPage("Config")
            expect(panel.iconLabel.Visible).to.equal(false)
        end)

        it("selects by index, by name and by the page object, and refuses what it does not have", function()
            local panel, trial, config = trialPanel()

            expect(panel:SelectPage(2)).to.equal(true)
            expect(panel:GetPage()).to.equal("Config")
            expect(panel:SelectPage("Trial")).to.equal(true)
            expect(panel:GetPage()).to.equal("Trial")
            expect(panel:SelectPage(config)).to.equal(true)
            expect(panel:GetPage()).to.equal("Config")

            expect(panel:SelectPage("Nope")).to.equal(false)
            expect(panel:SelectPage(9)).to.equal(false)
            expect(panel:GetPage()).to.equal("Config")
            expect(trial.frame.Visible).to.equal(false)
        end)

        it("reports a page change, but not the page it opened on or a repeat", function()
            local seen = {}
            local panel = makeTab():CreatePanel({
                name = "Trial",
                onPageChanged = function(page)
                    table.insert(seen, page)
                end,
            })
            panel:CreatePage({ name = "Trial" })
            local config = panel:CreatePage({ name = "Config" })

            expect(#seen).to.equal(0)

            config.pill.interact.MouseButton1Click:Fire()
            panel:SelectPage("Config")
            panel:SelectPage("Trial", true)

            expect(table.concat(seen, ",")).to.equal("Config")
        end)

        it("hosts elements on each page like a Group", function()
            local _, trial, config = trialPanel()

            local status = trial:CreateLabel({ text = "Trial Status: Waiting schedule" })
            local auto = trial:CreateToggle({ name = "Auto Trial", forgetState = true })
            local delay = config:CreateSlider({ name = "Delay", range = { 0, 10 }, value = 2, forgetState = true })

            expect(status.title.Text).to.equal("Trial Status: Waiting schedule")
            expect(auto.__type).to.equal("Toggle")
            expect(delay.value).to.equal(2)
        end)

        it("sizes the card to the current page and follows it", function()
            local panel, trial, config = trialPanel()

            trial.main.AbsoluteSize = Vector2.new(0, 120)
            trial.main:GetPropertyChangedSignal("AbsoluteSize"):Fire()
            local onTrial = panel.main.Size.Y.Offset

            config.main.AbsoluteSize = Vector2.new(0, 40)
            config.main:GetPropertyChangedSignal("AbsoluteSize"):Fire()
            -- growth on a page that is not showing does not move the card
            expect(panel.main.Size.Y.Offset).to.equal(onTrial)

            panel:SelectPage("Config")
            expect(panel.main.Size.Y.Offset).to.equal(onTrial - 80)
        end)

        it("leaves the title the width the pills do not take", function()
            local panel, _, config = trialPanel()

            -- the title's negative width offset has to cover at least the pill beside it
            expect(-panel.title.Size.X.Offset > config.pill.frame.Size.X.Offset).to.equal(true)
        end)

        it("fades in as a container, not as a full element card", function()
            local panel, _, config = trialPanel()
            local fill = window.theme.ElementTransparency or 0

            panel:_setShown(true, false)
            -- half the element fill, so the toggles on it still read as raised
            expect(panel.main.BackgroundTransparency).to.equal(1 - (1 - fill) * 0.5)
            expect(config.pill.frame.BackgroundTransparency).to.equal(window.theme.FieldTransparency)

            panel:_setShown(false, false)
            expect(panel.main.BackgroundTransparency).to.equal(1)
            expect(config.pill.frame.BackgroundTransparency).to.equal(1)
        end)

        it("builds from a Group and from a Collapsible, not just a Tab", function()
            local tab = makeTab()
            local column = tab:CreateGroup({ direction = "column" })
            local collapsible = tab:CreateCollapsible({ name = "Trial", expanded = true })

            expect(column:CreatePanel({ name = "InGroup" }).__type).to.equal("Panel")
            expect(collapsible:CreatePanel({ name = "InCollapsible" }).__type).to.equal("Panel")
        end)
    end)
end

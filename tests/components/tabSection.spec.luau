local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component tabSection", function()
        local window

        local function makeWindow(tabsMode)
            window = Window.new({
                name = "Section Spec",
                tabsMode = tabsMode,
                configuration = {
                    autoSave = false,
                    autoLoad = false,
                },
            })
            return window
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        it("builds a real heading in sidebar mode and registers it on the window", function()
            local w = makeWindow("Sidebar")
            local section = w:CreateSection({ name = "Combat" })

            expect(section.inert).to.never.be.ok()
            expect(section.name).to.equal("Combat")
            expect(section.main).to.be.ok()
            expect(section.title.Text).to.equal("Combat")
            expect(#w.tabSections).to.equal(1)
            expect(w.tabSections[1]).to.equal(section)
        end)

        it("hands back an inert handle on the top strip instead of half-building one", function()
            local w = makeWindow("Top")
            local section = w:CreateSection({ name = "Combat" })

            expect(section.inert).to.equal(true)
            expect(section.main).to.equal(nil)
            -- warned once, and only once, however many sections a top-mode window asks for
            expect(w._warnedTabSection).to.equal(true)
            w:CreateSection({ name = "Other" })
            expect(w._warnedTabSection).to.equal(true)
        end)

        it("survives every method being called on an inert handle", function()
            local w = makeWindow("Top")
            local section = w:CreateSection({ name = "Combat" })

            -- the rail drives these on every width change; an inert handle must not throw
            section:_setCollapsed(true)
            section:_setVisible(false)
            section:_setShown(true)
            expect(section.main).to.equal(nil)
        end)

        it("defaults its name when none is given", function()
            expect(makeWindow("Sidebar"):CreateSection({}).name).to.equal("Section")
        end)

        it("builds an icon only when one is asked for", function()
            local w = makeWindow("Sidebar")

            expect(w:CreateSection({ name = "Plain" }).iconLabel).to.equal(nil)
            expect(w:CreateSection({ name = "Iconed", icon = 100 }).iconLabel).to.be.ok()
        end)

        it("swaps the heading for a rule when the rail collapses, and back again", function()
            local w = makeWindow("Sidebar")
            local section = w:CreateSection({ name = "Combat", icon = 100 })

            section:_setCollapsed(true)
            expect(section.title.Visible).to.equal(false)
            expect(section.iconLabel.Visible).to.equal(false)
            expect(section.rule.Visible).to.equal(true)
            -- a fixed 9px rule, not a heading that sizes itself to text nobody can read
            expect(section.main.AutomaticSize).to.equal(Enum.AutomaticSize.None)
            expect(section.main.Size.Y.Offset).to.equal(9)

            section:_setCollapsed(false)
            expect(section.title.Visible).to.equal(true)
            expect(section.iconLabel.Visible).to.equal(true)
            expect(section.rule.Visible).to.equal(false)
            expect(section.main.AutomaticSize).to.equal(Enum.AutomaticSize.Y)
            expect(section.main.Size.Y.Offset).to.equal(0)
        end)

        it("comes up already collapsed when the rail is narrow before it is built", function()
            local w = makeWindow("Sidebar")
            w:SetSidebarCollapsed(true)

            local section = w:CreateSection({ name = "Late" })
            expect(section.rule.Visible).to.equal(true)
            expect(section.title.Visible).to.equal(false)
        end)

        it("drops itself off the window when removed", function()
            local w = makeWindow("Sidebar")
            local section = w:CreateSection({ name = "Combat" })

            section:Remove()

            expect(#w.tabSections).to.equal(0)
            expect(section.main).to.equal(nil)
        end)
    end)
end

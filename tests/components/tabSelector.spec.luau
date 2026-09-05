local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")
    local tabSelector = helpers.requireComponent("tabSelector")

    describe("component tabSelector", function()
        local window

        local function makeWindow(tabsMode)
            window = Window.new({
                name = "Selector Spec",
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

        describe("layout constants", function()
            it("matches the upstream Rayfield Gen2 1.2 rail metrics", function()
                -- these are ported values, not taste. a drift here is a visual regression
                -- against the reference the whole rail was copied from.
                local layout = tabSelector.layout
                expect(layout.rowHeight).to.equal(38)
                expect(layout.rowCornerRadius).to.equal(14)
                expect(layout.rowInset).to.equal(15)
                expect(layout.rowPadding).to.equal(10)
                expect(layout.rowContentSpacing).to.equal(6)
                expect(layout.rowIconSize).to.equal(20)
            end)

            it("gives the rail's selected row a lighter fill than the top strip's pill", function()
                expect(tabSelector.states.top.selected.background).to.equal(0)
                expect(tabSelector.states.sidebar.selected.background).to.equal(0.4)
            end)

            it("only gives the rail row a shadow entry", function()
                expect(tabSelector.states.sidebar.selected.shadow).to.be.ok()
                expect(tabSelector.states.top.selected.shadow).to.equal(nil)
            end)
        end)

        describe("sidebar rows", function()
            it("builds a row sized to the ported metrics", function()
                local tab = makeWindow("Sidebar"):CreateTab({ name = "Combat", icon = 100 })

                expect(tab.topbarItem).to.be.ok()
                expect(tab.topbarItem.Size.Y.Offset).to.equal(tabSelector.layout.rowHeight)
                expect(tab.topbarItemTitle.Text).to.equal("Combat")
                expect(tab.topbarItemShadow).to.be.ok()
            end)

            it("falls back to the name's first letter for a tab with no icon", function()
                local tab = makeWindow("Sidebar"):CreateTab({ name = "combat" })

                expect(tab.topbarItemInitial).to.be.ok()
                expect(tab.topbarItemInitial.Text).to.equal("C")
            end)

            it("takes a whole multi-byte first character, not half of one", function()
                local tab = makeWindow("Sidebar"):CreateTab({ name = "Ámbar" })

                expect(tab.topbarItemInitial.Text).to.equal(string.upper("Á"))
            end)

            it("swaps the label for the initial when the rail collapses, and back", function()
                local tab = makeWindow("Sidebar"):CreateTab({ name = "Combat" })
                local layout = tabSelector.layout

                tabSelector.setRowCollapsed(tab, true)
                expect(tab.topbarItemTitle.Visible).to.equal(false)
                expect(tab.topbarItemInitial.Visible).to.equal(true)
                expect(tab.topbarItemContainer.Position.X.Offset).to.equal(0)
                expect(tab.topbarItemLayout.HorizontalAlignment).to.equal(Enum.HorizontalAlignment.Center)

                tabSelector.setRowCollapsed(tab, false)
                expect(tab.topbarItemTitle.Visible).to.equal(true)
                expect(tab.topbarItemInitial.Visible).to.equal(false)
                expect(tab.topbarItemContainer.Position.X.Offset).to.equal(layout.rowPadding)
                expect(tab.topbarItemLayout.HorizontalAlignment).to.equal(Enum.HorizontalAlignment.Left)
            end)
        end)

        describe("top pills", function()
            it("builds a pill with no shadow and no initial", function()
                local tab = makeWindow("Top"):CreateTab({ name = "Combat", icon = 100 })

                expect(tab.topbarItem).to.be.ok()
                expect(tab.topbarItemShadow).to.equal(nil)
                expect(tab.topbarItemInitial).to.equal(nil)
            end)

            it("ignores a collapse request, having no rail to collapse into", function()
                local tab = makeWindow("Top"):CreateTab({ name = "Combat" })
                local before = tab.topbarItemTitle.Visible

                tabSelector.setRowCollapsed(tab, true)

                expect(tab.topbarItemTitle.Visible).to.equal(before)
            end)
        end)

        it("leaves a part it doesn't have alone when applying a state", function()
            -- a pill has no shadow; applying the sidebar state (which carries one) must not throw
            local tab = makeWindow("Top"):CreateTab({ name = "Combat" })

            tabSelector.applyVisual(tab, tabSelector.states.sidebar.selected)

            expect(tab.topbarItem.BackgroundTransparency).to.equal(0.4)
        end)
    end)
end

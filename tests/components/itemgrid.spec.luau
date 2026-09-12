local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component itemgrid", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Grid Spec",
                configuration = { autoSave = false, autoLoad = false },
            })
            return window:CreateTab({ name = "Main" })
        end

        local function selected(grid)
            return table.concat(grid:Get(), ",")
        end

        local function visible(grid)
            local shown = {}
            for _, entry in grid.entries do
                if grid.cells[entry.id].frame.Visible then
                    table.insert(shown, entry.id)
                end
            end
            return table.concat(shown, ",")
        end

        local function rarityItems()
            return {
                { id = "a", name = "Alpha", tag = "RARE" },
                { id = "b", name = "Bravo", tag = "EPIC" },
                { id = "c", name = "Alpine", tag = "RARE" },
            }
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        it("builds a cell per item and starts with nothing ticked", function()
            local grid = makeTab():CreateItemGrid({ items = { "X", "Y" }, forgetState = true })

            expect(grid.cells["X"]).to.be.ok()
            expect(selected(grid)).to.equal("")
            expect(grid.counter.Text).to.equal("0 / 2")
        end)

        it("counts against the total, not the filtered view", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })
            grid:Set({ "b" }, true)

            grid:Filter("alp") -- hides b, which is the one that is ticked
            -- "1 / 2" here would claim half the visible cards are selected, which is untrue
            expect(grid.counter.Text).to.equal("1 / 3")
        end)

        it("returns ids in item order, not click order", function()
            local grid = makeTab():CreateItemGrid({ items = { "X", "Y", "Z" }, forgetState = true })

            grid:Toggle("Z", true)
            grid:Toggle("X", true)

            expect(selected(grid)).to.equal("X,Z")
        end)

        it("toggles off again and reports which way it went", function()
            local grid = makeTab():CreateItemGrid({ items = { "X" }, forgetState = true })

            expect(grid:Toggle("X", true)).to.equal(true)
            expect(selected(grid)).to.equal("X")
            expect(grid:Toggle("X", true)).to.equal(false)
            expect(selected(grid)).to.equal("")
            expect(grid:Toggle("nope", true)).to.equal(false)
        end)

        it("keeps only one tick when multiSelect is false", function()
            -- the `(x or X) ~= false` trap again: passing false used to be ignored
            local grid = makeTab():CreateItemGrid({
                items = { "X", "Y" },
                multiSelect = false,
                forgetState = true,
            })

            expect(grid.multiSelect).to.equal(false)
            grid:Toggle("X", true)
            grid:Toggle("Y", true)
            expect(selected(grid)).to.equal("Y")
        end)

        it("drops ids it does not know on Set", function()
            local grid = makeTab():CreateItemGrid({ items = { "X", "Y" }, forgetState = true })

            grid:Set({ "Y", "ghost" }, true)

            expect(selected(grid)).to.equal("Y")
        end)

        it("filters on text, case-insensitively", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter("ALP")

            expect(visible(grid)).to.equal("a,c")
        end)

        it("filters on tags, and a second tag widens rather than replaces", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter({ tags = { "EPIC" } })
            expect(visible(grid)).to.equal("b")

            grid:Filter({ tags = { "EPIC", "RARE" } })
            expect(visible(grid)).to.equal("a,b,c")
        end)

        it("composes text and tags", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter({ text = "alp", tags = { "RARE" } })

            expect(visible(grid)).to.equal("a,c")
        end)

        it("takes a predicate", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter(function(entry)
                return entry.id == "b"
            end)

            expect(visible(grid)).to.equal("b")
        end)

        it("clears the search box and the chips together on Filter(nil)", function()
            local grid = makeTab():CreateItemGrid({
                items = rarityItems(),
                search = true,
                filters = { "RARE", "EPIC" },
                forgetState = true,
            })

            grid:Filter({ text = "alp", tags = { "RARE" } })
            grid:Filter(nil)

            expect(visible(grid)).to.equal("a,b,c")
            expect(grid.searchInput.Text).to.equal("")
            expect(grid.activeTags["RARE"]).to.equal(nil)
        end)

        it("reports the live filter in the shape Filter takes", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter({ text = "alp", tags = { "RARE" } })
            local state = grid:GetFilter()

            expect(state.text).to.equal("alp")
            expect(#state.tags).to.equal(1)
            expect(state.tags[1]).to.equal("RARE")
        end)

        it("shows the empty state when nothing matches", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter("zzzz")

            expect(grid.emptyLabel.Visible).to.equal(true)
            expect(grid.scroll.Visible).to.equal(false)
        end)

        it("only selects what the filter is showing", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

            grid:Filter({ tags = { "RARE" } })
            grid:SelectAll(true)

            -- selecting the whole catalogue from a filtered view would be a nasty surprise
            expect(selected(grid)).to.equal("a,c")
        end)

        it("keeps surviving ticks through a Refresh", function()
            local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })
            grid:Set({ "a", "b" }, true)

            grid:Refresh({ { id = "a", name = "Alpha" }, { id = "d", name = "Delta" } }, true)

            expect(selected(grid)).to.equal("a")
            expect(grid.cells["b"]).to.equal(nil)
        end)

        it("builds a chip per declared filter", function()
            local grid = makeTab():CreateItemGrid({
                items = rarityItems(),
                filters = { { tag = "RARE", name = "Raro" }, "EPIC" },
                forgetState = true,
            })

            expect(grid.chips["RARE"]).to.be.ok()
            expect(grid.chips["RARE"].title.Text).to.equal("Raro")
            expect(grid.chips["EPIC"].title.Text).to.equal("EPIC")
        end)

        it("toggles a tag on and back off through ToggleTag", function()
            local grid = makeTab():CreateItemGrid({
                items = rarityItems(),
                filters = { "RARE" },
                forgetState = true,
            })

            grid:ToggleTag("RARE")
            expect(visible(grid)).to.equal("a,c")
            grid:ToggleTag("RARE")
            expect(visible(grid)).to.equal("a,b,c")
        end)

        it("takes only as much height as its rows need, up to `height`", function()
            local tab = makeTab()
            local few = tab:CreateItemGrid({ items = { "X", "Y" }, height = 400, columns = 4, forgetState = true })
            few.columns = 4 -- pin it: the shim has no real width to measure

            -- two items are one row, not 400px of empty panel
            expect(few:_contentHeight() < 400).to.equal(true)
        end)

        describe("maxSelected", function()
            it("refuses a pick past the cap instead of dropping an earlier one", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 2,
                    forgetState = true,
                })

                expect(grid:Toggle("a")).never.to.equal(false)
                expect(grid:Toggle("b")).never.to.equal(false)
                -- at the cap: the third is refused, and the first two are untouched
                expect(grid:Toggle("c")).to.equal(false)
                expect(selected(grid)).to.equal("a,b")
            end)

            it("frees a slot again when something is unticked", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 1,
                    forgetState = true,
                })

                grid:Toggle("a")
                expect(grid:Toggle("b")).to.equal(false)
                grid:Toggle("a") -- untick
                expect(grid:Toggle("b")).never.to.equal(false)
                expect(selected(grid)).to.equal("b")
            end)

            it("caps a Set too, so a config saved before the cap cannot restore over it", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 2,
                    forgetState = true,
                })

                grid:Set({ "a", "b", "c" })

                expect(selected(grid)).to.equal("a,b")
            end)

            it("counts against the cap rather than the total", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 2,
                    forgetState = true,
                })

                grid:Toggle("a")
                -- "1 / 2" is what a capped player needs; "1 / 3" says nothing about picks left
                expect(grid.counter.Text).to.equal("1 / 2")
            end)

            it("is ignored when it makes no sense, and absent by default", function()
                local tab = makeTab()

                expect(tab:CreateItemGrid({ items = rarityItems(), forgetState = true }).maxSelected).to.equal(nil)
                expect(tab:CreateItemGrid({ items = rarityItems(), maxSelected = 0, forgetState = true }).maxSelected).to.equal(
                    nil
                )
            end)
        end)

        describe("scope", function()
            local function ownedOnly(entry)
                return entry.tag == "RARE"
            end

            it("hides everything outside it, from the start", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    scope = ownedOnly,
                    forgetState = true,
                })

                expect(visible(grid)).to.equal("a,c")
            end)

            it("survives the player typing, which a Filter predicate does not", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    scope = ownedOnly,
                    search = true,
                    forgetState = true,
                })

                grid.searchInput.Text = "Alp"
                grid.searchInput:GetPropertyChangedSignal("Text"):Fire()

                -- "Alpha" and "Alpine" both match the text, and both are in scope. "Bravo" is out
                -- of scope and stays out - this is the whole reason scope is not Filter.
                expect(visible(grid)).to.equal("a,c")

                grid.searchInput.Text = "Bravo"
                grid.searchInput:GetPropertyChangedSignal("Text"):Fire()
                expect(visible(grid)).to.equal("")
            end)

            it("still ANDs with a Filter predicate", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    scope = ownedOnly,
                    forgetState = true,
                })

                grid:Filter(function(entry)
                    return entry.id ~= "a"
                end)

                expect(visible(grid)).to.equal("c")
            end)

            it("can be replaced and dropped later", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    scope = ownedOnly,
                    forgetState = true,
                })

                grid:SetScope(function(entry)
                    return entry.id == "b"
                end)
                expect(visible(grid)).to.equal("b")

                grid:SetScope(nil)
                expect(visible(grid)).to.equal("a,b,c")
            end)

            it("leaves a selection it hides alone rather than silently unticking it", function()
                local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

                grid:Toggle("b")
                grid:SetScope(ownedOnly)

                -- b is off screen but still the player's pick, same as any other filter. Dropping
                -- it would rewrite their saved value as a side effect of a scope change.
                expect(selected(grid)).to.equal("b")
            end)
        end)

        describe("the Select all / Clear row", function()
            local function actions(grid)
                return grid.selectAllButton, grid.clearButton
            end

            it("builds both on a multi-select grid, and only Clear on a single-select one", function()
                local tab = makeTab()
                local multi = tab:CreateItemGrid({ items = rarityItems(), forgetState = true })
                local single = tab:CreateItemGrid({
                    items = rarityItems(),
                    multiSelect = false,
                    forgetState = true,
                })

                expect(multi.selectAllButton).to.be.ok()
                expect(multi.clearButton).to.be.ok()
                -- "Select all" on a grid that can hold one thing is a button with no meaning
                expect(single.selectAllButton).to.equal(nil)
                expect(single.clearButton).to.be.ok()
            end)

            it("is opt-out, and then takes no height", function()
                local tab = makeTab()
                local withRow = tab:CreateItemGrid({ items = rarityItems(), forgetState = true })
                local without = tab:CreateItemGrid({
                    items = rarityItems(),
                    quickActions = false,
                    forgetState = true,
                })

                expect(without.selectAllButton).to.equal(nil)
                expect(without.clearButton).to.equal(nil)
                expect(without.quickRow).to.equal(nil)
                -- the row is part of the element's own height, so dropping it moves the grid up
                expect(without:_gridTop() < withRow:_gridTop()).to.equal(true)
            end)

            it("ticks and empties the selection on a real click", function()
                local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })
                local selectAll, clear = actions(grid)

                selectAll.MouseButton1Click:Fire()
                expect(selected(grid)).to.equal("a,b,c")

                clear.MouseButton1Click:Fire()
                expect(selected(grid)).to.equal("")
            end)

            it("acts on what the filter shows, not the whole catalogue", function()
                local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

                grid:Filter({ tags = { "RARE" } })
                grid.selectAllButton.MouseButton1Click:Fire()

                -- selecting the hidden EPIC card from a filtered view would be a nasty surprise
                expect(selected(grid)).to.equal("a,c")
            end)

            it("stops Select all at the cap instead of walking past it", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 2,
                    forgetState = true,
                })

                grid.selectAllButton.MouseButton1Click:Fire()

                -- "all" has to mean "as many as the cap allows", or the button is a way around it
                expect(#grid:Get()).to.equal(2)
                expect(grid.counter.Text).to.equal("2 / 2")
            end)

            it("counts a hidden-but-ticked card against the cap", function()
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    maxSelected = 2,
                    forgetState = true,
                })

                grid:Toggle("b") -- EPIC, ticked while everything is visible
                grid:SetScope(function(entry)
                    return entry.tag == "RARE"
                end)

                -- b is off screen and stays ticked (a scope change must not rewrite the player's
                -- saved value), so it still occupies one of the two slots. "Select all" over the
                -- two visible RARE cards therefore adds only one.
                grid.selectAllButton.MouseButton1Click:Fire()

                expect(#grid:Get()).to.equal(2)
                expect(grid.counter.Text).to.equal("2 / 2")
                -- deliberate: never exceeding the cap is the only reading that cannot lose a
                -- pick the player already made. The alternative - counting only what is visible -
                -- would let the total run past the cap as the scope moves.
                expect(table.find(grid:Get(), "b")).to.be.ok()
            end)

            it("does nothing while the element is locked", function()
                local grid = makeTab():CreateItemGrid({ items = rarityItems(), forgetState = true })

                grid:Lock()
                grid.selectAllButton.MouseButton1Click:Fire()

                -- the guard has to sit in the button handler, not only at the callback funnel:
                -- _runGuarded refuses a locked element callback, but SelectAll mutates the
                -- selection before it ever gets there
                expect(selected(grid)).to.equal("")
                expect(grid:IsLocked()).to.equal(true)
            end)

            it("reports the change through the callback, once", function()
                local calls = 0
                local grid = makeTab():CreateItemGrid({
                    items = rarityItems(),
                    forgetState = true,
                    callback = function()
                        calls += 1
                    end,
                })

                grid.selectAllButton.MouseButton1Click:Fire()
                expect(calls).to.equal(1)

                grid.clearButton.MouseButton1Click:Fire()
                expect(calls).to.equal(2)
            end)
        end)
    end)
end

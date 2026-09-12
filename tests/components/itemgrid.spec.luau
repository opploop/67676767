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
    end)
end

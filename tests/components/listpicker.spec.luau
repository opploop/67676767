local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component listpicker", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Picker Spec",
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

        it("selects its first option rather than nothing", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                forgetState = true,
            })

            -- a category rail with nothing chosen leaves the panel beside it showing nothing
            expect(picker:Get()).to.equal("Armors")
            expect(#picker.rows).to.equal(2)
        end)

        it("honours an explicit starting value", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                value = "Weapons",
                forgetState = true,
            })

            expect(picker:Get()).to.equal("Weapons")
        end)

        it("keeps the id separate from the display name", function()
            local picker = makeTab():CreateListPicker({
                options = { { id = "armors", name = "Armaduras" } },
                forgetState = true,
            })

            expect(picker:Get()).to.equal("armors")
            expect(picker.rows[1].title.Text).to.equal("Armaduras")
        end)

        it("refuses an id it does not have, and keeps the current pick", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                forgetState = true,
            })

            expect(picker:Set("ghost", true)).to.equal(false)
            expect(picker:Get()).to.equal("Armors")
            expect(picker:Set("Weapons", true)).to.equal(true)
            expect(picker:Get()).to.equal("Weapons")
        end)

        it("reports the chosen id to the callback", function()
            local seen
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                forgetState = true,
                callback = function(id)
                    seen = id
                end,
            })

            picker:Set("Weapons")
            expect(seen).to.equal("Weapons")
        end)

        it("fills exactly one row - the selected one", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                forgetState = true,
            })

            picker:Set("Weapons", true)

            -- unselected rows are bare text; the fill is what marks the selection
            expect(picker.rows[1].frame.BackgroundTransparency).to.equal(1)
            expect(picker.rows[2].frame.BackgroundTransparency).to.equal(0)
        end)

        it("builds a row icon only when one is given", function()
            local picker = makeTab():CreateListPicker({
                options = { { id = "a", name = "A", icon = 100 }, "B" },
                forgetState = true,
            })

            expect(picker.rows[1].iconLabel).to.be.ok()
            expect(picker.rows[2].iconLabel).to.equal(nil)
        end)

        it("drops the header when showHeader is false", function()
            local tab = makeTab()
            local withHeader = tab:CreateListPicker({ options = { "A" }, forgetState = true })
            local without = tab:CreateListPicker({ options = { "A" }, showHeader = false, forgetState = true })

            expect(withHeader.title).to.be.ok()
            expect(without.title).to.equal(nil)
            -- the list starts higher up when there is no header above it
            expect(without:_listTop() < withHeader:_listTop()).to.equal(true)
        end)

        it("keeps the current pick through a Refresh that still has it", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons", "Titles" },
                forgetState = true,
            })
            picker:Set("Weapons", true)

            picker:Refresh({ "Weapons", "Titles" }, true)

            expect(picker:Get()).to.equal("Weapons")
            expect(#picker.rows).to.equal(2)
        end)

        it("falls back to the first option when the pick is refreshed away", function()
            local picker = makeTab():CreateListPicker({
                options = { "Armors", "Weapons" },
                forgetState = true,
            })
            picker:Set("Weapons", true)

            picker:Refresh({ "Titles", "Armors" }, true)

            expect(picker:Get()).to.equal("Titles")
        end)

        describe("height", function()
            local function many(count)
                local options = {}
                for index = 1, count do
                    table.insert(options, "Option " .. index)
                end
                return options
            end

            it("takes only the rows it has when they fit under the ceiling", function()
                local picker = makeTab():CreateListPicker({ options = { "A", "B", "C" }, forgetState = true })

                -- three rows, not seven rows of empty rail
                expect(picker.list.Size.Y.Offset).to.equal(picker:_rowsHeight(3))
            end)

            it("stops growing at seven rows by default and scrolls past that", function()
                local picker = makeTab():CreateListPicker({ options = many(40), forgetState = true })

                -- forty options used to mean a rail forty rows tall, pushing the page away
                expect(picker.list:IsA("ScrollingFrame")).to.equal(true)
                expect(picker.list.Size.Y.Offset).to.equal(picker:_rowsHeight(7))
                expect(#picker.rows).to.equal(40)
            end)

            it("treats an explicit height as a ceiling, not a reservation", function()
                local tab = makeTab()
                local short = tab:CreateListPicker({ options = { "A", "B" }, height = 300, forgetState = true })
                local long = tab:CreateListPicker({ options = many(20), height = 120, forgetState = true })

                expect(short.list.Size.Y.Offset).to.equal(short:_rowsHeight(2))
                expect(long.list.Size.Y.Offset).to.equal(120)
            end)

            it("puts the default ceiling back when SetHeight is given nil", function()
                local picker = makeTab():CreateListPicker({ options = many(20), height = 80, forgetState = true })

                picker:SetHeight(nil)

                expect(picker.list.Size.Y.Offset).to.equal(picker:_rowsHeight(7))
            end)
        end)

        describe("multiSelect", function()
            local function options()
                return { "Armors", "Weapons", "Enchants" }
            end

            it("starts with nothing ticked, unlike the single-select rail", function()
                local picker =
                    makeTab():CreateListPicker({ options = options(), multiSelect = true, forgetState = true })

                -- none is a real state here; pre-ticking the first row would choose for the player
                expect(#picker:Get()).to.equal(0)
            end)

            it("ticks and unticks rows on a real click, keeping option order", function()
                local picker =
                    makeTab():CreateListPicker({ options = options(), multiSelect = true, forgetState = true })

                picker.rows[3].interact.MouseButton1Click:Fire()
                picker.rows[1].interact.MouseButton1Click:Fire()
                -- option order, not click order, so a saved selection round-trips to the same array
                expect(table.concat(picker:Get(), ",")).to.equal("Armors,Enchants")

                picker.rows[1].interact.MouseButton1Click:Fire()
                expect(table.concat(picker:Get(), ",")).to.equal("Enchants")
            end)

            it("fills every ticked row, not just one", function()
                local picker = makeTab():CreateListPicker({
                    options = options(),
                    multiSelect = true,
                    value = { "Armors", "Enchants" },
                    forgetState = true,
                })

                expect(picker.rows[1].frame.BackgroundTransparency).to.equal(0)
                expect(picker.rows[2].frame.BackgroundTransparency).never.to.equal(0)
                expect(picker.rows[3].frame.BackgroundTransparency).to.equal(0)
            end)

            it("hands the callback the whole array", function()
                local seen
                local picker = makeTab():CreateListPicker({
                    options = options(),
                    multiSelect = true,
                    forgetState = true,
                    callback = function(ids)
                        seen = ids
                    end,
                })

                picker:Toggle("Weapons")

                expect(type(seen)).to.equal("table")
                expect(table.concat(seen, ",")).to.equal("Weapons")
            end)

            it("drops unknown ids from Set instead of refusing the whole call", function()
                local picker =
                    makeTab():CreateListPicker({ options = options(), multiSelect = true, forgetState = true })

                picker:Set({ "Weapons", "Gone", "Armors" })

                expect(table.concat(picker:Get(), ",")).to.equal("Armors,Weapons")
            end)

            it("selects all and clears", function()
                local picker =
                    makeTab():CreateListPicker({ options = options(), multiSelect = true, forgetState = true })

                picker:SelectAll()
                expect(#picker:Get()).to.equal(3)
                picker:Clear()
                expect(#picker:Get()).to.equal(0)
            end)

            it("keeps surviving ticks through a Refresh and never pre-ticks a newcomer", function()
                local picker = makeTab():CreateListPicker({
                    options = options(),
                    multiSelect = true,
                    value = { "Armors", "Enchants" },
                    forgetState = true,
                })

                picker:Refresh({ "Armors", "Titles", "Weapons" })

                expect(table.concat(picker:Get(), ",")).to.equal("Armors")
            end)

            it("gives a single-select rail the first surviving id of a saved list", function()
                -- a config written while the rail was multi-select, restored after it went back
                local picker = makeTab():CreateListPicker({ options = options(), forgetState = true })

                picker:Set({ "Gone", "Weapons", "Armors" })

                expect(picker:Get()).to.equal("Weapons")
            end)

            it("hands out a copy from Get, so mutating it cannot rewrite the selection", function()
                local picker = makeTab():CreateListPicker({
                    options = options(),
                    multiSelect = true,
                    value = { "Armors" },
                    forgetState = true,
                })

                table.insert(picker:Get(), "Weapons")

                expect(table.concat(picker:Get(), ",")).to.equal("Armors")
            end)

            it("leaves the single-select behaviour exactly as it was", function()
                local picker = makeTab():CreateListPicker({ options = options(), forgetState = true })

                picker:Toggle("Weapons")
                picker:SelectAll()

                -- Toggle means pick there, and SelectAll has nothing it can hold
                expect(picker:Get()).to.equal("Weapons")
            end)
        end)

        it("shows its empty state with no options", function()
            local picker = makeTab():CreateListPicker({ options = {}, forgetState = true })

            expect(picker:Get()).to.equal(nil)
            expect(picker.emptyLabel.Visible).to.equal(true)
        end)
    end)
end

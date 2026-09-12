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

        it("grows with its options, and scrolls instead when given a height", function()
            local tab = makeTab()
            local grows = tab:CreateListPicker({ options = { "A", "B", "C" }, forgetState = true })
            local scrolls = tab:CreateListPicker({ options = { "A", "B", "C" }, height = 60, forgetState = true })

            expect(grows.list:IsA("ScrollingFrame")).to.equal(false)
            expect(grows.list.Size.Y.Offset > 60).to.equal(true)
            expect(scrolls.list:IsA("ScrollingFrame")).to.equal(true)
            expect(scrolls.list.Size.Y.Offset).to.equal(60)
        end)

        it("shows its empty state with no options", function()
            local picker = makeTab():CreateListPicker({ options = {}, forgetState = true })

            expect(picker:Get()).to.equal(nil)
            expect(picker.emptyLabel.Visible).to.equal(true)
        end)
    end)
end

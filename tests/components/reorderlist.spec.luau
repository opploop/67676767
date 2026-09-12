local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component reorderlist", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Reorder Spec",
                configuration = { autoSave = false, autoLoad = false },
            })
            return window:CreateTab({ name = "Main" })
        end

        local function ids(list)
            return table.concat(list:Get(), ",")
        end

        local function rowNames(list)
            local names = {}
            for _, row in list.rows do
                table.insert(names, row.entry.name)
            end
            return table.concat(names, ",")
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        it("takes bare strings as their own ids", function()
            local list = makeTab():CreateReorderList({ items = { "Alpha", "Bravo" }, forgetState = true })

            expect(#list.rows).to.equal(2)
            expect(ids(list)).to.equal("Alpha,Bravo")
            expect(list.entries[1].name).to.equal("Alpha")
        end)

        it("keeps the id separate from the display name", function()
            local list = makeTab():CreateReorderList({
                items = { { id = "farm", name = "Auto Farm" } },
                forgetState = true,
            })

            expect(ids(list)).to.equal("farm")
            expect(list.rows[1].title.Text).to.equal("Auto Farm")
        end)

        it("numbers its badges from the top down", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })

            expect(list.rows[1].badgeLabel.Text).to.equal("1")
            expect(list.rows[3].badgeLabel.Text).to.equal("3")
        end)

        it("honours showIndex and removable when they are false", function()
            local tab = makeTab()
            -- the `(x or X) ~= false` trap: passing false used to be ignored entirely
            local plain = tab:CreateReorderList({ items = { "A" }, showIndex = false, forgetState = true })
            local rich = tab:CreateReorderList({ items = { "A" }, removable = true, forgetState = true })

            expect(plain.showIndex).to.equal(false)
            expect(plain.rows[1].badge).to.equal(nil)
            expect(rich.removable).to.equal(true)
            expect(rich.rows[1].removeButton).to.be.ok()
        end)

        it("lays rows out at its own computed offsets, with no layout object", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })
            local slot = list:_slot()

            expect(list.rows[1].frame.Position.Y.Offset).to.equal(0)
            expect(list.rows[2].frame.Position.Y.Offset).to.equal(slot)
            expect(list.rows[3].frame.Position.Y.Offset).to.equal(slot * 2)

            -- the whole reason this component works where PinnedList didn't: nothing else may
            -- own a row's Position (see reorderlist.luau's header)
            for _, child in list.stack:GetChildren() do
                expect(child:IsA("UIListLayout")).to.equal(false)
                expect(child:IsA("UIGridLayout")).to.equal(false)
            end
        end)

        it("reorders to a given order", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })

            list:Set({ "C", "A", "B" }, true)

            expect(ids(list)).to.equal("C,A,B")
            expect(rowNames(list)).to.equal("C,A,B")
            expect(list.rows[1].badgeLabel.Text).to.equal("1")
        end)

        it("ignores unknown ids and keeps unmentioned ones at the end", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })

            -- a config saved before C existed, plus an id for something long since removed
            list:Set({ "B", "ghost", "A" }, true)

            expect(ids(list)).to.equal("B,A,C")
        end)

        it("appends with Add and refuses a duplicate id", function()
            local list = makeTab():CreateReorderList({ items = { "A" }, forgetState = true })

            expect(list:Add("B", true)).to.equal(true)
            expect(ids(list)).to.equal("A,B")
            expect(list:Add("B", true)).to.equal(false)
            expect(ids(list)).to.equal("A,B")
        end)

        it("drops one entry with RemoveItem and renumbers", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })

            expect(list:RemoveItem("B", true)).to.equal(true)

            expect(ids(list)).to.equal("A,C")
            expect(#list.rows).to.equal(2)
            expect(list.rows[2].badgeLabel.Text).to.equal("2")
            expect(list:RemoveItem("B", true)).to.equal(false)
        end)

        it("fires onRemove with the id that went", function()
            local removed
            local list = makeTab():CreateReorderList({
                items = { "A", "B" },
                forgetState = true,
                onRemove = function(id)
                    removed = id
                end,
            })

            list:RemoveItem("A", true)
            expect(removed).to.equal("A")
        end)

        it("keeps the surviving order through a Refresh", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B", "C" }, forgetState = true })
            list:Set({ "C", "B", "A" }, true)

            -- B is gone, D is new: C and A hold their relative order, D lands at the end
            list:Refresh({ "A", "C", "D" }, true)

            expect(ids(list)).to.equal("C,A,D")
        end)

        it("hands the callback a copy, not the live order", function()
            local list = makeTab():CreateReorderList({ items = { "A", "B" }, forgetState = true })

            local handed = list:Get()
            table.remove(handed, 1)

            expect(ids(list)).to.equal("A,B")
        end)

        it("shows its empty state with nothing in it", function()
            local list = makeTab():CreateReorderList({ items = {}, forgetState = true })

            expect(#list.rows).to.equal(0)
            expect(list.emptyLabel.Visible).to.equal(true)
        end)
    end)
end

local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

-- StatusCard, Checkbox, HoldButton, CopyButton, FlipButton, RippleButton, ProgressBar: the
-- compact/row-capable set, none of which had a spec.
return function()
    local Window = helpers.requireComponent("window")

    local window

    local function makeTab()
        window = Window.new({
            name = "Compact Spec",
            configuration = { autoSave = false, autoLoad = false },
        })
        return window:CreateTab({ name = "Main" })
    end

    local function cleanup()
        if window and not window.unloaded then
            window:Unload()
        end
        window = nil
    end

    describe("component statuscard", function()
        afterEach(cleanup)

        it("builds a row per entry", function()
            local card = makeTab():CreateStatusCard({
                name = "Server",
                rows = { { label = "Ping", value = "30ms" }, { label = "FPS", value = "60" } },
            })

            expect(card.main).to.be.ok()
            expect(#card._rows).to.equal(2)
        end)

        it("rewrites one row in place", function()
            local card = makeTab():CreateStatusCard({
                name = "Server",
                rows = { { label = "Ping", value = "30ms" } },
            })

            card:SetRow(1, { label = "Ping", value = "12ms" })

            expect(#card._rows).to.equal(1)
        end)

        it("adds and removes rows", function()
            local card = makeTab():CreateStatusCard({ name = "Server", rows = { { label = "A", value = "1" } } })

            card:AddRow({ label = "B", value = "2" })
            expect(#card._rows).to.equal(2)

            -- RemoveRow takes the row KEY, not an index; a row without an explicit key is
            -- keyed by its label
            card:RemoveRow("A")
            expect(#card._rows).to.equal(1)
            expect(card._rows[1].key).to.equal("B")
        end)

        it("replaces the whole row set with Set", function()
            local card = makeTab():CreateStatusCard({ name = "Server", rows = { { label = "A", value = "1" } } })

            card:Set({ { label = "X", value = "9" }, { label = "Y", value = "8" }, { label = "Z", value = "7" } })

            expect(#card._rows).to.equal(3)
        end)

        it("expands and collapses when collapsible", function()
            local card = makeTab():CreateStatusCard({
                name = "Server",
                collapsible = true,
                expanded = false,
                rows = { { label = "A", value = "1" } },
            })

            expect(card.expanded).to.equal(false)
            card:SetExpanded(true)
            expect(card.expanded).to.equal(true)
            card:Toggle()
            expect(card.expanded).to.equal(false)
        end)

        it("hands its width to a row's flex instead of pinning it", function()
            local tab = makeTab()
            local alone = tab:CreateStatusCard({ name = "Alone", rows = { { label = "A", value = "1" } } })
            local row = tab:CreateGroup({ direction = "row" })
            local inRow = row:CreateStatusCard({ name = "InRow", rows = { { label = "A", value = "1" } } })

            -- on its own it builds at its own width; in a row the row owns it
            expect(alone._widthManaged).never.to.be.ok()
            expect(inRow._widthManaged).to.equal(true)
            expect(inRow:_minWidth() <= 180).to.equal(true)
        end)
    end)

    describe("component checkbox", function()
        afterEach(cleanup)

        it("starts off and flips on", function()
            local seen
            local box = makeTab():CreateCheckbox({
                name = "Thing",
                forgetState = true,
                callback = function(value)
                    seen = value
                end,
            })

            expect(box.value).to.equal(false)
            box:Set(true)
            expect(box.value).to.equal(true)
            expect(seen).to.equal(true)
        end)

        it("honours a starting value", function()
            local box = makeTab():CreateCheckbox({ name = "Thing", value = true, forgetState = true })
            expect(box.value).to.equal(true)
        end)

        it("skips the callback when told to", function()
            local calls = 0
            local box = makeTab():CreateCheckbox({
                name = "Thing",
                forgetState = true,
                callback = function()
                    calls += 1
                end,
            })

            box:Set(true, true)
            expect(box.value).to.equal(true)
            expect(calls).to.equal(0)
        end)

        it("locks and unlocks", function()
            local box = makeTab():CreateCheckbox({ name = "Thing", forgetState = true })

            box:Lock("nope")
            expect(box:IsLocked()).to.equal(true)
            box:Unlock()
            expect(box:IsLocked()).to.equal(false)
        end)

        it("builds a compact variant inside a row", function()
            local row = makeTab():CreateGroup({ direction = "row" })
            local box = row:CreateCheckbox({ name = "Thing", forgetState = true })

            expect(box.compact).to.equal(true)
            expect(box:_minWidth() > 0).to.equal(true)
        end)
    end)

    describe("component holdbutton", function()
        afterEach(cleanup)

        it("builds with a hold duration", function()
            local button = makeTab():CreateHoldButton({ name = "Delete", holdDuration = 2, forgetState = true })

            expect(button.main).to.be.ok()
            expect(button.holdDuration).to.equal(2)
        end)

        it("tints itself for a destructive action", function()
            local button = makeTab():CreateHoldButton({ name = "Delete", danger = true, forgetState = true })
            expect(button.danger).to.equal(true)
        end)

        it("locks through both spellings", function()
            local button = makeTab():CreateHoldButton({ name = "Delete", forgetState = true })

            button:SetLocked(true)
            expect(button:IsLocked()).to.equal(true)
            button:Unlock()
            expect(button:IsLocked()).to.equal(false)
            button:Lock()
            expect(button:IsLocked()).to.equal(true)
        end)
    end)

    describe("component copybutton", function()
        afterEach(cleanup)

        it("holds the text it was given", function()
            local button = makeTab():CreateCopyButton({ name = "Copy", text = "hello", forgetState = true })

            expect(button.main).to.be.ok()
            expect(button.text).to.equal("hello")
        end)

        it("swaps its text with Set", function()
            local button = makeTab():CreateCopyButton({ name = "Copy", text = "a", forgetState = true })

            button:Set("b")
            expect(button.text).to.equal("b")
        end)

        it("locks", function()
            local button = makeTab():CreateCopyButton({ name = "Copy", text = "a", forgetState = true })

            button:Lock()
            expect(button:IsLocked()).to.equal(true)
        end)
    end)

    describe("component flipbutton", function()
        afterEach(cleanup)

        it("builds with both faces", function()
            local button = makeTab():CreateFlipButton({
                name = "Start",
                secondaryName = "Stop",
                forgetState = true,
            })

            expect(button.main).to.be.ok()
            expect(button.name).to.equal("Start")
        end)

        it("flips through Set", function()
            local button = makeTab():CreateFlipButton({
                name = "Start",
                secondaryName = "Stop",
                forgetState = true,
            })

            button:Set(true)
            button:Set(false)
            expect(button.main).to.be.ok()
        end)

        it("locks", function()
            local button = makeTab():CreateFlipButton({ name = "Start", forgetState = true })

            button:Lock()
            expect(button:IsLocked()).to.equal(true)
        end)
    end)

    describe("component ripplebutton", function()
        afterEach(cleanup)

        it("builds, and locks like the rest", function()
            local button = makeTab():CreateRippleButton({ name = "Go", forgetState = true })

            expect(button.main).to.be.ok()
            button:Lock()
            expect(button:IsLocked()).to.equal(true)
            button:Unlock()
            expect(button:IsLocked()).to.equal(false)
        end)

        it("fits in a row", function()
            local row = makeTab():CreateGroup({ direction = "row" })
            local button = row:CreateRippleButton({ name = "Go", forgetState = true })

            expect(button).to.be.ok()
            expect(button.main).to.be.ok()
        end)
    end)

    describe("component progressbar", function()
        afterEach(cleanup)

        it("starts at its given value out of max", function()
            local bar = makeTab():CreateProgressBar({ name = "Loading", value = 25, max = 50 })

            expect(bar.value).to.equal(25)
            expect(bar.max).to.equal(50)
        end)

        it("moves with Set", function()
            local bar = makeTab():CreateProgressBar({ name = "Loading", value = 0, max = 100 })

            bar:Set(60)
            expect(bar.value).to.equal(60)
        end)

        it("clamps past its own maximum", function()
            local bar = makeTab():CreateProgressBar({ name = "Loading", value = 0, max = 10 })

            bar:Set(999)
            expect(bar.value <= 10).to.equal(true)
        end)

        it("carries a suffix", function()
            local bar = makeTab():CreateProgressBar({ name = "Loading", value = 5, max = 10, suffix = "%" })
            expect(bar.main).to.be.ok()
        end)
    end)
end

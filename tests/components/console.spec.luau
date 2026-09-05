local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component console", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Console Spec",
                configuration = {
                    autoSave = false,
                    autoLoad = false,
                },
            })
            return window:CreateTab({ name = "Main" })
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        it("starts empty and applies the documented defaults", function()
            local console = makeTab():CreateConsole({})

            expect(console:Get()).to.equal("")
            expect(console.height).to.equal(120)
            expect(console.maxLines).to.equal(200)
            expect(console.follow).to.equal(false)
        end)

        it("splits its initial text into lines", function()
            local console = makeTab():CreateConsole({ text = "first\nsecond\nthird" })

            expect(#console.lines).to.equal(3)
            expect(console.lines[1]).to.equal("first")
            expect(console.lines[3]).to.equal("third")
            expect(console:Get()).to.equal("first\nsecond\nthird")
        end)

        it("appends one line at a time and splits a multi-line append", function()
            local console = makeTab():CreateConsole({})

            console:Append("one")
            console:Append("two\nthree")

            expect(#console.lines).to.equal(3)
            expect(console:Get()).to.equal("one\ntwo\nthree")
        end)

        it("replaces the whole body on Set", function()
            local console = makeTab():CreateConsole({ text = "old" })

            console:Set("new body")

            expect(#console.lines).to.equal(1)
            expect(console:Get()).to.equal("new body")
        end)

        it("empties on Clear", function()
            local console = makeTab():CreateConsole({ text = "a\nb" })

            console:Clear()

            expect(#console.lines).to.equal(0)
            expect(console:Get()).to.equal("")
        end)

        it("rolls the oldest line off once maxLines is reached", function()
            local console = makeTab():CreateConsole({ maxLines = 3 })

            for index = 1, 5 do
                console:Append("line " .. index)
            end

            -- newest three survive, in order, and the pool never grew past the cap
            expect(#console.lines).to.equal(3)
            expect(console:Get()).to.equal("line 3\nline 4\nline 5")
            expect(#console.lineLabels).to.equal(3)
        end)

        it("trims an oversized initial body to maxLines as well", function()
            local console = makeTab():CreateConsole({ maxLines = 2, text = "a\nb\nc\nd" })

            expect(console:Get()).to.equal("c\nd")
        end)

        it("clamps a too-small height instead of accepting it", function()
            local console = makeTab():CreateConsole({ height = 4 })

            expect(console.height).to.equal(48)

            console:SetHeight(300)
            expect(console.height).to.equal(300)

            console:SetHeight(1)
            expect(console.height).to.equal(48)
        end)

        it("keeps at least one line of capacity for a nonsense maxLines", function()
            local console = makeTab():CreateConsole({ maxLines = 0 })

            expect(console.maxLines).to.equal(1)

            console:Append("a")
            console:Append("b")
            expect(console:Get()).to.equal("b")
        end)

        it("accepts PascalCase properties the way every other component does", function()
            local console = makeTab():CreateConsole({ Text = "x", Height = 90, MaxLines = 7, Follow = true })

            expect(console:Get()).to.equal("x")
            expect(console.height).to.equal(90)
            expect(console.maxLines).to.equal(7)
            expect(console.follow).to.equal(true)
        end)
    end)
end

local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component playerdropdown", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Player Spec",
                configuration = { autoSave = false, autoLoad = false },
            })
            return window:CreateTab({ name = "Main" })
        end

        local function options(dropdown)
            return table.concat(dropdown.options, ",")
        end

        beforeEach(function()
            helpers.resetPlayers()
        end)

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
            helpers.resetPlayers()
        end)

        it("fills itself from the server roster", function()
            helpers.addPlayer("zara", "Zara")
            helpers.addPlayer("bob", "Bob")

            local dropdown = makeTab():CreatePlayerDropdown({ forgetState = true })

            -- SpecUser is the shim's LocalPlayer, included by default
            expect(#dropdown.options).to.equal(3)
            expect(options(dropdown)).to.equal("bob,SpecUser,zara")
        end)

        it("sorts case-insensitively", function()
            helpers.addPlayer("alice", "Alice")
            helpers.addPlayer("Bravo", "Bravo")

            local dropdown = makeTab():CreatePlayerDropdown({ forgetState = true })

            -- byte order would file every capitalised name above every lowercase one
            expect(options(dropdown)).to.equal("alice,Bravo,SpecUser")
        end)

        it("leaves the local player out when asked", function()
            helpers.addPlayer("bob", "Bob")

            local dropdown = makeTab():CreatePlayerDropdown({ includeSelf = false, forgetState = true })

            expect(options(dropdown)).to.equal("bob")
        end)

        it("labels by display name when told to", function()
            helpers.addPlayer("bob", "Bobby")

            local dropdown = makeTab():CreatePlayerDropdown({ format = "display", forgetState = true })

            expect(options(dropdown)).to.equal("Bobby,Spec User")
        end)

        it("shows both, and collapses the pair when they match", function()
            helpers.addPlayer("bob", "Bobby")
            helpers.addPlayer("plain", "plain") -- display name never set

            local dropdown = makeTab():CreatePlayerDropdown({ format = "both", forgetState = true })

            local joined = options(dropdown)
            expect(string.find(joined, "Bobby (@bob)", 1, true) ~= nil).to.equal(true)
            -- "plain (@plain)" would just be noise
            expect(string.find(joined, "plain (@plain)", 1, true)).to.equal(nil)
        end)

        it("hands back Player instances, not the labels", function()
            local bob = helpers.addPlayer("bob", "Bobby")

            local dropdown = makeTab():CreatePlayerDropdown({ includeSelf = false, forgetState = true })
            dropdown:Set("bob", true)

            local picked = dropdown:GetSelectedPlayers()
            expect(#picked).to.equal(1)
            expect(picked[1]).to.equal(bob)
        end)

        it("skips a selected player who has since left", function()
            helpers.addPlayer("bob", "Bobby")

            local dropdown = makeTab():CreatePlayerDropdown({ includeSelf = false, forgetState = true })
            dropdown:Set("bob", true)
            helpers.removePlayer("bob") -- clears Parent, which is what GetSelectedPlayers checks

            expect(#dropdown:GetSelectedPlayers()).to.equal(0)
        end)

        it("rebuilds on demand and returns the new labels", function()
            local dropdown = makeTab():CreatePlayerDropdown({ forgetState = true })
            expect(#dropdown.options).to.equal(1)

            helpers.addPlayer("bob", "Bobby")
            local refreshed = dropdown:RefreshPlayers()

            expect(#refreshed).to.equal(2)
            expect(options(dropdown)).to.equal("bob,SpecUser")
        end)

        it("files its join/leave listeners on the element, so a teardown releases them", function()
            local dropdown = makeTab():CreatePlayerDropdown({ forgetState = true })

            -- ConnectFor puts them here; teardownElements is what later disconnects them
            expect(dropdown.connections).to.be.ok()
            expect(#dropdown.connections > 0).to.equal(true)
        end)
    end)
end

local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Window = helpers.requireComponent("window")

    describe("component hud", function()
        local window

        local function makeWindow()
            window = Window.new({
                name = "HUD Spec",
                configuration = { autoSave = false, autoLoad = false },
            })
            return window
        end

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
        end)

        it("builds outside the window's own frame", function()
            local w = makeWindow()
            local hud = w:CreateHUD({ text = "Ping 30ms" })

            expect(hud).to.be.ok()
            expect(hud.main).to.be.ok()
            -- the HUD floats on the screen, not inside the window it was created from
            expect(hud.main.Parent).never.to.equal(w.main)
        end)

        it("shows the text it was given, and swaps it", function()
            local hud = makeWindow():CreateHUD({ text = "First" })

            expect(hud.label.Text).to.equal("First")
            hud:SetText("Second")
            expect(hud.label.Text).to.equal("Second")
        end)

        it("hides and shows without being destroyed", function()
            local hud = makeWindow():CreateHUD({ text = "x" })

            hud:SetVisible(false)
            expect(hud.main.Visible).to.equal(false)
            hud:SetVisible(true)
            expect(hud.main.Visible).to.equal(true)
        end)

        it("takes a starting position and moves later", function()
            local hud = makeWindow():CreateHUD({ text = "x", position = UDim2.fromOffset(40, 60) })

            expect(hud.main.Position).to.equal(UDim2.fromOffset(40, 60))
            hud:SetPosition(UDim2.fromOffset(10, 20))
            expect(hud.main.Position).to.equal(UDim2.fromOffset(10, 20))
        end)

        it("keeps the position listener for a drag, not for a programmatic move", function()
            local hud = makeWindow():CreateHUD({ text = "x" })
            local fired = 0
            hud:OnPositionChanged(function()
                fired += 1
            end)

            hud:SetPosition(UDim2.fromOffset(5, 5))

            -- deliberate: the hook exists to persist where a PLAYER dropped the chip and fires
            -- once on drag release. A script moving it is not a thing to persist back.
            expect(hud.main.Position).to.equal(UDim2.fromOffset(5, 5))
            expect(fired).to.equal(0)
            expect(#hud._positionChangedCallbacks).to.equal(1)
        end)

        it("builds an icon only when one is given", function()
            local w = makeWindow()
            local plain = w:CreateHUD({ text = "a" })
            local iconed = w:CreateHUD({ text = "b", icon = 100 })

            expect(plain.iconLabel).to.equal(nil)
            expect(iconed.iconLabel).to.be.ok()
        end)

        it("tears itself down on Destroy", function()
            local hud = makeWindow():CreateHUD({ text = "x" })
            local frame = hud.main

            hud:Destroy()

            expect(frame.Parent).to.equal(nil)
        end)

        it("goes away with the window that made it", function()
            local w = makeWindow()
            local hud = w:CreateHUD({ text = "x" })
            local frame = hud.main

            w:Unload()

            -- a HUD outliving its window would be an orphan nothing can reach or close
            expect(frame.Parent).to.equal(nil)
        end)
    end)
end

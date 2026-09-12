local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

-- GradientPicker and SegmentedPicker: the two largest components that had no spec at all.
return function()
    local Window = helpers.requireComponent("window")

    describe("component gradientpicker", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Gradient Spec",
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

        it("builds with a default gradient when none is given", function()
            local picker = makeTab():CreateGradientPicker({ name = "Glow", forgetState = true })

            expect(picker.main).to.be.ok()
            expect(picker.value).to.be.ok()
            expect(typeof(picker.value)).to.equal("ColorSequence")
        end)

        it("takes a ColorSequence as its starting value", function()
            local sequence = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 255))
            local picker = makeTab():CreateGradientPicker({
                name = "Glow",
                value = sequence,
                forgetState = true,
            })

            expect(#picker.value.Keypoints).to.equal(#sequence.Keypoints)
            expect(picker.value.Keypoints[1].Value).to.equal(Color3.fromRGB(255, 0, 0))
        end)

        it("takes a plain colour list and turns it into a sequence", function()
            local picker = makeTab():CreateGradientPicker({
                name = "Glow",
                colors = { Color3.fromRGB(10, 20, 30), Color3.fromRGB(200, 100, 0) },
                forgetState = true,
            })

            expect(typeof(picker.value)).to.equal("ColorSequence")
            expect(picker.value.Keypoints[1].Value).to.equal(Color3.fromRGB(10, 20, 30))
        end)

        it("reports a change through the callback", function()
            local seen
            local picker = makeTab():CreateGradientPicker({
                name = "Glow",
                forgetState = true,
                callback = function(value)
                    seen = value
                end,
            })

            local target = ColorSequence.new(Color3.fromRGB(1, 2, 3), Color3.fromRGB(4, 5, 6))
            picker:Set(target)

            expect(seen).to.be.ok()
            expect(typeof(seen)).to.equal("ColorSequence")
            expect(picker.value.Keypoints[1].Value).to.equal(Color3.fromRGB(1, 2, 3))
        end)

        it("stays quiet when Set is told to skip the callback", function()
            local calls = 0
            local picker = makeTab():CreateGradientPicker({
                name = "Glow",
                forgetState = true,
                callback = function()
                    calls += 1
                end,
            })

            picker:Set(ColorSequence.new(Color3.fromRGB(9, 9, 9)), true)
            expect(calls).to.equal(0)
        end)

        it("toggles its glow", function()
            local picker = makeTab():CreateGradientPicker({ name = "Glow", forgetState = true })

            picker:SetGlow(true)
            picker:SetGlow(false)
            expect(picker.main).to.be.ok()
        end)

        it("builds a descriptor when given a description", function()
            local tab = makeTab()
            local bare = tab:CreateGradientPicker({ name = "A", forgetState = true })
            local described = tab:CreateGradientPicker({ name = "B", description = "why", forgetState = true })

            expect(bare.descriptor).to.equal(nil)
            expect(described.descriptor).to.be.ok()
        end)
    end)

    describe("component segmentedpicker", function()
        local window

        local function makeTab()
            window = Window.new({
                name = "Segmented Spec",
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

        it("selects its first option by default", function()
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = { "Basic", "Advanced" },
                forgetState = true,
            })

            expect(picker.value).to.equal("Basic")
        end)

        it("honours an explicit starting value", function()
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = { "Basic", "Advanced", "Expert" },
                value = "Expert",
                forgetState = true,
            })

            expect(picker.value).to.equal("Expert")
        end)

        it("moves the selection and reports it", function()
            local seen
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = { "Basic", "Advanced" },
                forgetState = true,
                callback = function(value)
                    seen = value
                end,
            })

            picker:Set("Advanced")

            expect(picker.value).to.equal("Advanced")
            expect(seen).to.equal("Advanced")
        end)

        it("skips the callback when asked", function()
            local calls = 0
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = { "Basic", "Advanced" },
                forgetState = true,
                callback = function()
                    calls += 1
                end,
            })

            picker:Set("Advanced", true)

            expect(picker.value).to.equal("Advanced")
            expect(calls).to.equal(0)
        end)

        it("ignores an option it does not have", function()
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = { "Basic", "Advanced" },
                forgetState = true,
            })

            picker:Set("Nope")

            expect(picker.value).to.equal("Basic")
        end)

        it("builds nested options, and starts on the first leaf", function()
            local picker = makeTab():CreateSegmentedPicker({
                name = "Mode",
                options = {
                    { text = "Farm", options = { "Slow", "Fast" } },
                    { text = "Idle" },
                },
                forgetState = true,
            })

            expect(picker.main).to.be.ok()
            -- a nested first option resolves to its own first leaf, not the group's label
            expect(picker.value).to.equal("Slow")
        end)
    end)
end

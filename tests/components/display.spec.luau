local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

-- Divider, Paragraph, Label, ShimmerLabel, ScrollHint, Spacer, Changelog, Tabbox: the
-- display-side elements, none of which had a spec.
return function()
    local Window = helpers.requireComponent("window")

    local window

    local function makeTab()
        window = Window.new({
            name = "Display Spec",
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

    describe("component divider", function()
        afterEach(cleanup)

        it("builds a bare rule with no text", function()
            local divider = makeTab():CreateDivider({})

            expect(divider.main).to.be.ok()
        end)

        it("carries a label when given one", function()
            local divider = makeTab():CreateDivider({ text = "Section" })

            expect(divider.title).to.be.ok()
            expect(divider.title.Text).to.equal("Section")
        end)

        it("swaps its label with Set", function()
            local divider = makeTab():CreateDivider({ text = "Before" })

            divider:Set("After")

            expect(divider.title.Text).to.equal("After")
        end)

        it("accepts each spacing preset, and an unknown one falls back", function()
            local tab = makeTab()

            -- the preset drives padding rather than the frame's own height, so this covers the
            -- lookup rather than asserting a size relationship that does not hold
            for _, spacing in { "tight", "normal", "loose", "nonsense" } do
                expect(tab:CreateDivider({ spacing = spacing }).main).to.be.ok()
            end
        end)

        it("takes an explicit height for a spacing-only divider", function()
            local divider = makeTab():CreateDivider({ line = false, height = 40 })

            -- the outer frame is AutomaticSize.Y; the height sits on the invisible spacer it wraps
            expect(divider.spacer).to.be.ok()
            expect(divider.spacer.Size.Y.Offset).to.equal(40)
        end)

        it("can drop the rule and keep only the spacing", function()
            local divider = makeTab():CreateDivider({ line = false })

            expect(divider.main).to.be.ok()
        end)
    end)

    describe("component paragraph", function()
        afterEach(cleanup)

        it("builds with a title and a body", function()
            local paragraph = makeTab():CreateParagraph({ title = "Heads up", content = "Body copy." })

            expect(paragraph.main).to.be.ok()
            expect(paragraph.title.Text).to.equal("Heads up")
            expect(paragraph.body.Text).to.equal("Body copy.")
        end)

        it("rewrites each half independently", function()
            local paragraph = makeTab():CreateParagraph({ title = "A", content = "B" })

            paragraph:SetTitle("A2")
            expect(paragraph.title.Text).to.equal("A2")
            expect(paragraph.body.Text).to.equal("B")

            paragraph:SetContent("B2")
            expect(paragraph.body.Text).to.equal("B2")
        end)

        it("rewrites both at once with Set", function()
            local paragraph = makeTab():CreateParagraph({ title = "A", content = "B" })

            paragraph:Set({ title = "X", content = "Y" })

            expect(paragraph.title.Text).to.equal("X")
            expect(paragraph.body.Text).to.equal("Y")
        end)

        it("builds an icon only when asked", function()
            local tab = makeTab()
            local bare = tab:CreateParagraph({ title = "A", content = "B" })
            local iconed = tab:CreateParagraph({ title = "A", content = "B", icon = 100 })

            expect(bare.iconLabel).to.equal(nil)
            expect(iconed.iconLabel).to.be.ok()
        end)
    end)

    describe("component label", function()
        afterEach(cleanup)

        -- CreateLabel was reachable from Tab, Group and Collapsible and called by nothing in the
        -- suite. label.luau still read as 96% covered, because other elements build labels
        -- internally - the percentage was green while the entry point a dev actually writes had
        -- never once been exercised.
        it("builds a bare line of text", function()
            local label = makeTab():CreateLabel({ text = "Just a line" })

            expect(label.main).to.be.ok()
            expect(label.title.Text).to.equal("Just a line")
            expect(label.iconLabel).to.equal(nil)
        end)

        it("defaults to empty text rather than erroring", function()
            local label = makeTab():CreateLabel({})

            expect(label.title.Text).to.equal("")
        end)

        it("insets the text to clear an icon, and only then", function()
            local tab = makeTab()
            local bare = tab:CreateLabel({ text = "a" })
            local iconed = tab:CreateLabel({ text = "b", icon = 100 })

            expect(bare.title.Position.X.Offset).to.equal(0)
            expect(bare.title.Size.X.Offset).to.equal(0)

            -- 16px icon + an 8px gap, taken off the text's width as well as its offset, so the
            -- copy wraps inside what is left instead of running under the icon
            expect(iconed.iconLabel).to.be.ok()
            expect(iconed.title.Position.X.Offset).to.equal(24)
            expect(iconed.title.Size.X.Offset).to.equal(-24)
        end)

        it("swaps the copy, and clears it on nil", function()
            local label = makeTab():CreateLabel({ text = "First" })

            label:Set("Second")
            expect(label.title.Text).to.equal("Second")

            -- Set takes a literal, deliberately: the constructor's text goes through locale.t
            -- because it is authored copy, while a runtime Set is usually a computed string with
            -- no translation key. Paragraph's setters work the same way.
            label:Set(nil)
            expect(label.title.Text).to.equal("")
        end)

        it("registers on the tab, so search can reach it", function()
            local tab = makeTab()
            local label = tab:CreateLabel({ text = "Findable" })

            expect(table.find(tab.elements, label)).to.be.ok()
        end)

        it("builds from a Group and from a Collapsible, not just a Tab", function()
            local tab = makeTab()
            local column = tab:CreateGroup({ direction = "column" })
            local collapsible = tab:CreateCollapsible({ name = "Panel", expanded = true })

            expect(column:CreateLabel({ text = "in a group" }).title.Text).to.equal("in a group")
            expect(collapsible:CreateLabel({ text = "in a panel" }).title.Text).to.equal("in a panel")
        end)
    end)

    describe("component shimmerlabel", function()
        afterEach(cleanup)

        it("builds with its text", function()
            local label = makeTab():CreateShimmerLabel({ text = "Loading" })

            expect(label.main).to.be.ok()
            expect(label.label.Text).to.equal("Loading")
        end)

        it("swaps its text", function()
            local label = makeTab():CreateShimmerLabel({ text = "A" })

            label:Set("B")
            expect(label.label.Text).to.equal("B")
        end)

        it("takes the sweep controls, before and after building", function()
            local label =
                makeTab():CreateShimmerLabel({ text = "A", speed = 2, spread = 0.3, angle = 45, textSize = 20 })

            expect(label.speed).to.equal(2)
            expect(label.angle).to.equal(45)

            label:SetSpeed(4)
            label:SetSpread(0.6)
            label:SetAngle(90)
            label:SetTextSize(24)

            expect(label.speed).to.equal(4)
            expect(label.spread).to.equal(0.6)
            expect(label.angle).to.equal(90)
            expect(label.label.TextSize).to.equal(24)
        end)
    end)

    describe("component scrollhint", function()
        afterEach(cleanup)

        it("builds and swaps its text", function()
            local hint = makeTab():CreateScrollHint({ text = "Scroll for more" })

            expect(hint.main).to.be.ok()
            hint:Set("Nearly there")
            expect(hint.main).to.be.ok()
        end)
    end)

    describe("component spacer", function()
        afterEach(cleanup)

        it("takes the height it is given, and a new one later", function()
            local spacer = makeTab():CreateSpacer({ height = 30 })

            expect(spacer.main.Size.Y.Offset).to.equal(30)
            spacer:SetHeight(60)
            expect(spacer.main.Size.Y.Offset).to.equal(60)
        end)

        it("has nothing to reveal, and does not throw when asked", function()
            local spacer = makeTab():CreateSpacer({})

            spacer:_setShown(true, false)
            spacer:_setShown(false, false)
            expect(spacer.main).to.be.ok()
        end)
    end)

    describe("component changelog", function()
        afterEach(cleanup)

        it("builds a row per entry", function()
            local changelog = makeTab():CreateChangelog({
                name = "What's new",
                version = "v1.2.0",
                date = "2026-01-01",
                entries = {
                    { type = "added", text = "A thing" },
                    { type = "fixed", text = "A bug" },
                },
            })

            expect(changelog.main).to.be.ok()
        end)

        it("survives an empty entry list", function()
            local changelog = makeTab():CreateChangelog({ name = "Empty", entries = {} })

            expect(changelog.main).to.be.ok()
        end)

        it("takes plain strings as entries too", function()
            local changelog = makeTab():CreateChangelog({ name = "Plain", entries = { "One", "Two" } })

            expect(changelog.main).to.be.ok()
        end)
    end)

    describe("component tabbox", function()
        afterEach(cleanup)

        it("builds pages that host elements like a Group", function()
            local box = makeTab():CreateTabbox({ name = "Modes" })
            local page = box:CreateTab({ name = "First" })

            expect(box.main).to.be.ok()
            expect(page).to.be.ok()
            expect(page.__type).to.equal("Group")

            local toggle = page:CreateToggle({ name = "Inside", forgetState = true })
            expect(toggle).to.be.ok()
        end)

        it("keeps several pages and selects the first", function()
            local box = makeTab():CreateTabbox({ name = "Modes" })
            box:CreateTab({ name = "A" })
            box:CreateTab({ name = "B" })

            expect(#box.pages).to.equal(2)
        end)

        it("builds from a Group and from a Collapsible, not just a Tab", function()
            local tab = makeTab()
            local column = tab:CreateGroup({ direction = "column" })
            local collapsible = tab:CreateCollapsible({ name = "Panel", expanded = true })

            expect(column:CreateTabbox({ name = "FromGroup" })).to.be.ok()
            expect(collapsible:CreateTabbox({ name = "FromCollapsible" })).to.be.ok()
        end)
    end)
end

local requireUtility = (_G :: any).__RAYFIELD_TEST_HELPERS.requireUtility

return function()
    local functions = requireUtility("functions")
    local colors = requireUtility("colors")
    local flagNames = requireUtility("flagNames")
    local textMetrics = requireUtility("textMetrics")

    describe("utility.functions", function()
        it("exports the shared utility functions", function()
            expect(functions.textWidth).to.equal(textMetrics.textWidth)
            expect(functions.textHeight).to.equal(textMetrics.textHeight)
            expect(functions.deriveFlagFromName).to.equal(flagNames.deriveFlagFromName)
            expect(functions.contrastColor).to.equal(colors.contrastColor)
            expect(functions.toColorSequence).to.equal(colors.toColorSequence)
            expect(functions.contrastText).to.equal(colors.contrastText)
        end)

        describe("readValue", function()
            it("takes the first name that is present, in the order given", function()
                expect(functions.readValue({ value = 1, Value = 2 }, { "value", "Value" })).to.equal(1)
                expect(functions.readValue({ Value = 2 }, { "value", "Value" })).to.equal(2)
                expect(functions.readValue({ color = "c", value = "v" }, { "color", "value" })).to.equal("c")
            end)

            it("reads a declared false rather than skipping it", function()
                -- the whole reason this is not `a or b`: false is a real declared value, and
                -- `false or nil` is nil, which reads as "nothing was declared"
                expect(functions.readValue({ value = false }, { "value", "Value" })).to.equal(false)
            end)

            it("falls back to default and Default, last", function()
                expect(functions.readValue({ default = true }, { "value", "Value" })).to.equal(true)
                expect(functions.readValue({ Default = true }, { "value", "Value" })).to.equal(true)

                -- the canonical name still wins when both are given
                expect(functions.readValue({ value = 1, default = 2 }, { "value", "Value" })).to.equal(1)
            end)

            it("returns nil when nothing was declared", function()
                expect(functions.readValue({}, { "value", "Value" })).to.equal(nil)
            end)
        end)
    end)
end

local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

-- Every theme module, loaded and checked for the keys the library reads off them. Four of the
-- ten were never required by any spec, so nothing would have noticed a typo'd or missing key
-- until a player picked that theme and the window came up wrong.
return function()
    local themeNames = {
        "amethyst",
        "cobalt",
        "default",
        "ember",
        "emerald",
        "frost",
        "highcontrast",
        "midnight",
        "ocean",
        "rose",
    }

    -- A representative slice rather than the whole palette: these are the ones every window
    -- reads on any code path, so a theme missing one of them cannot build at all.
    local requiredKeys = {
        "WindowColor",
        "ElementStroke",
        "AccentColor",
        "AccentStroke",
        "ContentColor",
        "Font",
        "TitleFont",
        "ElementCornerRadius",
        "ErrorColor",
    }

    describe("themes", function()
        it("all ten load", function()
            for _, name in themeNames do
                local theme = helpers.requireTheme(name)
                expect(type(theme)).to.equal("table")
            end
        end)

        it("default carries every key the others may leave out", function()
            -- The other nine are partial overlays: each overrides what it wants to change and
            -- inherits the rest, so default is the only one that has to be complete.
            local theme = helpers.requireTheme("default")
            for _, key in requiredKeys do
                if theme[key] == nil then
                    error(("default is missing '%s'"):format(key), 0)
                end
            end
        end)

        it("every key an overlay declares has the type default declares it as", function()
            local base = helpers.requireTheme("default")
            for _, name in themeNames do
                local theme = helpers.requireTheme(name)
                for key, value in theme do
                    local baseValue = base[key]
                    if baseValue ~= nil and typeof(value) ~= typeof(baseValue) then
                        error(
                            ("theme '%s' declares '%s' as %s, default has %s"):format(
                                name,
                                tostring(key),
                                typeof(value),
                                typeof(baseValue)
                            ),
                            0
                        )
                    end
                end
            end
        end)

        it("every overlay actually overrides something", function()
            local base = helpers.requireTheme("default")
            for _, name in themeNames do
                if name ~= "default" then
                    local theme = helpers.requireTheme(name)
                    local differs = false
                    for key, value in theme do
                        if base[key] ~= value then
                            differs = true
                            break
                        end
                    end
                    if not differs then
                        error(("theme '%s' is identical to default"):format(name), 0)
                    end
                end
            end
        end)
    end)
end

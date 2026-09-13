local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local Rayfield = helpers.requireRayfield()
    local image = helpers.requireUtility("image")
    local variables = helpers.requireUtility("variables")

    describe("Rayfield init and themes", function()
        local originalSecureMode
        local originalPreload
        local originalLoadFont
        local window

        beforeEach(function()
            originalSecureMode = variables.secureMode
            originalPreload = image.preload
            originalLoadFont = variables.fontManager.loadFont
        end)

        afterEach(function()
            if window and not window.unloaded then
                window:Unload()
            end
            window = nil
            variables.secureMode = originalSecureMode
            image.preload = originalPreload
            variables.fontManager.loadFont = originalLoadFont
        end)

        it("requires every built-in theme", function()
            for _, name in { "default", "amethyst", "cobalt", "ember", "frost", "rose" } do
                local theme = helpers.requireTheme(name)
                expect(type(theme)).to.equal("table")
                expect(theme.WindowColor).to.be.ok()
                expect(theme.AccentColor).to.be.ok()
            end
        end)

        it("creates a window through the public init module", function()
            variables.secureMode = false

            window = Rayfield:CreateWindow({
                name = "Init Window",
                subtitle = "Normal",
                configuration = {
                    autoSave = false,
                    autoLoad = false,
                },
            })

            expect(window.name).to.equal("Init Window")
            expect(window.hidden).to.equal(false)
            expect(window.hasShownOnce).to.equal(true)
        end)

        describe("the logo splash", function()
            local constants = helpers.requireUtility("constants")
            local originalResolve

            -- createBanner is the only thing that resolves the banner icon, so counting those
            -- lookups is how a spec sees the splash: in the shim it is built and destroyed before
            -- CreateWindow even returns, so there is nothing left on screen to look for.
            local bannerBuilds

            beforeEach(function()
                bannerBuilds = 0
                originalResolve = image.resolve
                image.resolve = function(icon, ...)
                    if icon == constants.icons.banner then
                        bannerBuilds += 1
                    end
                    return originalResolve(icon, ...)
                end
            end)

            afterEach(function()
                image.resolve = originalResolve
            end)

            it("is off by default, so the hub's window is the first thing players see", function()
                variables.secureMode = false

                window = Rayfield:CreateWindow({
                    name = "No Splash",
                    configuration = { autoSave = false, autoLoad = false },
                })

                expect(bannerBuilds).to.equal(0)
                expect(window.hasShownOnce).to.equal(true)
            end)

            it("still comes back when a dev asks for it", function()
                variables.secureMode = false

                window = Rayfield:CreateWindow({
                    name = "Splash",
                    showBanner = true,
                    configuration = { autoSave = false, autoLoad = false },
                })

                expect(bannerBuilds).to.equal(1)
                expect(window.hasShownOnce).to.equal(true)
            end)

            it("takes the PascalCase spelling too", function()
                variables.secureMode = false

                window = Rayfield:CreateWindow({
                    name = "Splash Pascal",
                    ShowBanner = true,
                    configuration = { autoSave = false, autoLoad = false },
                } :: any)

                expect(bannerBuilds).to.equal(1)
            end)
        end)

        it("runs the secure-mode preload and font-swap branches deterministically", function()
            local preloadCalled = false
            local loadedWeights = {}

            variables.secureMode = true
            image.preload = function(onSettled)
                preloadCalled = true
                if onSettled then
                    onSettled(0)
                end
            end
            variables.fontManager.loadFont = function(_, _asset, weight)
                table.insert(loadedWeights, weight)
                return Font.new("font://secure", weight, Enum.FontStyle.Normal)
            end

            window = Rayfield:CreateWindow({
                name = "Secure Window",
                fallbackFont = Enum.Font.SourceSans,
                configuration = {
                    autoSave = false,
                    autoLoad = false,
                },
            })

            expect(preloadCalled).to.equal(true)
            expect(#loadedWeights).to.equal(2)
            expect(window.name).to.equal("Secure Window")
            expect(window.hidden).to.equal(false)
        end)
    end)
end

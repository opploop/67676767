local helpers = (_G :: any).__RAYFIELD_TEST_HELPERS

return function()
    local lockable = helpers.requireUtility("lockable")

    describe("utility.lockable", function()
        -- A stand-in for the real Window:_setElementLocked: records what it was asked to do and
        -- flips element.locked the way the real one does, so IsLocked has something to read.
        local function makeClass()
            local calls = {}
            local Class = {}
            Class.__index = Class
            lockable(Class)

            local function newElement()
                return setmetatable({
                    window = {
                        _setElementLocked = function(_, element, locked, reason)
                            table.insert(calls, { locked = locked, reason = reason })
                            element.locked = locked
                        end,
                    },
                }, Class)
            end

            return newElement, calls
        end

        it("adds Lock, Unlock and IsLocked to the class it is applied to", function()
            local Class = {}
            Class.__index = Class

            expect(rawget(Class, "Lock")).to.equal(nil)
            lockable(Class)

            expect(type(rawget(Class, "Lock"))).to.equal("function")
            expect(type(rawget(Class, "Unlock"))).to.equal("function")
            expect(type(rawget(Class, "IsLocked"))).to.equal("function")
        end)

        it("returns the same class table it was given", function()
            local Class = {}
            expect(lockable(Class)).to.equal(Class)
        end)

        it("reports false before anything locks it", function()
            local newElement = makeClass()
            -- `locked` starts out nil, not false: IsLocked must still answer a real boolean
            expect(newElement():IsLocked()).to.equal(false)
        end)

        it("routes Lock and Unlock through the window", function()
            local newElement, calls = makeClass()
            local element = newElement()

            element:Lock()
            expect(#calls).to.equal(1)
            expect(calls[1].locked).to.equal(true)
            expect(element:IsLocked()).to.equal(true)

            element:Unlock()
            expect(#calls).to.equal(2)
            expect(calls[2].locked).to.equal(false)
            expect(element:IsLocked()).to.equal(false)
        end)

        it("passes the reason through to the window", function()
            local newElement, calls = makeClass()
            newElement():Lock("Requires Premium")
            expect(calls[1].reason).to.equal("Requires Premium")
        end)

        it("passes no reason when Lock is called bare", function()
            local newElement, calls = makeClass()
            newElement():Lock()
            expect(calls[1].reason).to.equal(nil)
        end)
    end)
end

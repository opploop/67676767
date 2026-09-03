--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Shared Move* + SetVisible methods for tab elements. Call moveable(Class) once on the
-- prototype, after the class has already defined its own _setShown (SetVisible wraps it).

local hideDelay = 0.2 -- gives the fade-out a moment before pulling the row out of layout

local function moveable<T>(class: T): T
    local target = class :: any

    function target:MoveTo(index: number)
        self.tab:_moveElement(self, index)
    end

    function target:MoveToTop()
        self.tab:_moveElement(self, 1)
    end

    function target:MoveToBottom()
        self.tab:_moveElement(self, #self.tab.elements)
    end

    function target:MoveUp()
        local idx = table.find(self.tab.elements, self)
        if idx then
            self.tab:_moveElement(self, idx - 1)
        end
    end

    function target:MoveDown()
        local idx = table.find(self.tab.elements, self)
        if idx then
            self.tab:_moveElement(self, idx + 1)
        end
    end

    -- Devlog 7: every element gets :SetVisible(boolean) for free here, rather than touching
    -- ~20 component files individually. Wraps the class's own _setShown (already defined by
    -- this point - every component calls moveable() as its last line) so a runtime hide takes
    -- effect the same way a tab switch or window hide already would (dropdown closes its panel,
    -- hold button cancels an in-progress hold, ...), on top of also pulling the row out of
    -- layout entirely (main.Visible = false) rather than just fading its content, and pinning
    -- it hidden against any later automatic reveal (a tab switch, a window show) until
    -- SetVisible(true) explicitly clears it again.
    local ownSetShown = target._setShown
    if ownSetShown then
        target._setShown = function(self, shown, animate)
            if shown and self._userHidden then
                return
            end
            return ownSetShown(self, shown, animate)
        end

        function target:SetVisible(visible)
            visible = visible and true or false
            local wasHidden = self._userHidden or false
            if wasHidden == not visible then
                return
            end

            if visible then
                self._userHidden = false
                if self.main then
                    self.main.Visible = true
                end
                if self.descriptor and self.descriptor.main then
                    self.descriptor.main.Visible = true
                end
                if self.window and not self.window.hidden then
                    self:_setShown(true, self.window:_interactive())
                end
            else
                self._userHidden = true
                self:_setShown(false, true)

                local token = (self._hideToken or 0) + 1
                self._hideToken = token
                task.delay(hideDelay, function()
                    if self._userHidden and self._hideToken == token then
                        if self.main then
                            self.main.Visible = false
                        end
                        if self.descriptor and self.descriptor.main then
                            self.descriptor.main.Visible = false
                        end
                    end
                end)
            end
        end
    end

    return class
end

return moveable

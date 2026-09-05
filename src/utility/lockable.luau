--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Shared Lock/Unlock for tab elements. Call lockable(Class) once on the prototype. Ported from
-- upstream Rayfield Gen2 1.2's own Element Locking.
--
-- A locked element does three things: it dims so you can see it's out of reach, it stops taking
-- pointer input via an opaque scrim laid over it (see Window:_buildLockScrim), and its callback
-- is refused at the funnel every interactive element already routes through (Window:_runGuarded
-- checks `element.locked` before it runs anything). The scrim alone only ever stopped a real
-- click; the funnel check is what makes a lock hold against a programmatic `:Set()` or a fired
-- signal too, which is what a caller gating a premium feature actually needs.
--
-- A handful of components (Toggle, Button, Dropdown, HoldButton) already carry their own
-- bespoke SetLocked with a purpose-built dimming look - lockable(Class) is skipped for those
-- and Lock/Unlock/IsLocked are instead defined by hand right next to that existing method (see
-- each file's own SetLocked), aliasing straight into it rather than layering a second,
-- competing scrim on top.

local function lockable<T>(class: T): T
    local target = class :: any

    -- Lock it. `reason` is an optional line shown in place of the description while locked.
    function target:Lock(reason: string?)
        self.window:_setElementLocked(self, true, reason)
    end

    function target:Unlock()
        self.window:_setElementLocked(self, false)
    end

    function target:IsLocked(): boolean
        return self.locked == true
    end

    return class
end

return lockable

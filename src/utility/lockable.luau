--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Shared Lock/Unlock for tab elements. Call lockable(Class) once on the prototype. Ported from
-- upstream Rayfield Gen2 1.2's own Element Locking.
--
-- A locked element does two things: it dims so you can see it's out of reach, and it stops
-- taking input via an opaque scrim laid over it (see Window:_buildLockScrim) - a real click
-- never reaches the control underneath, so its own callback simply never runs. That's enough
-- for every element wired through this file; it doesn't additionally route through a shared
-- callback funnel the way upstream's own Window:_runGuarded does; this codebase has no such
-- funnel; every callback wires with its own MouseButton1Click).
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

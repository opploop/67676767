--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Clipboard access, abstracted the same way network.luau abstracts `request`: every executor
-- names its clipboard writer differently (or ships none at all), so probe the environment for
-- one and no-op cleanly when nothing's there instead of throwing at the caller.

local clipboard = {}
clipboard.__index = clipboard

export type CopyFn = (text: string) -> ()

-- accepts the environment table from getfenv()
function clipboard.getCopyFn(env: any?): CopyFn?
    env = env or getfenv()
    return env.setclipboard or env.toclipboard or env.set_clipboard or (env.Clipboard and env.Clipboard.set)
end

-- Best-effort copy. Returns true only when a clipboard function was found and it didn't error.
function clipboard.copy(text: string): boolean
    local fn = clipboard.getCopyFn()
    if not fn then
        return false
    end
    local ok = pcall(fn, text)
    return ok
end

return clipboard

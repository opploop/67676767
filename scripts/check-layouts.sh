#!/usr/bin/env bash
# Copyright (c) 2026 Corridon Capital
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Fails if any UIListLayout under src/ is created without an explicit SortOrder.
#
# Why this exists as a build step rather than a code-review habit: Roblox's real default for
# UIListLayout.SortOrder is Enum.SortOrder.Name (alphabetical), not LayoutOrder. Every element
# in this library sets LayoutOrder and expects it to be honoured, so a layout that forgets
# SortOrder silently sorts its children by name instead - and it only *looks* broken when the
# names happen not to already be in the right order, which is why it has shipped here more than
# once (a player card's rows out of order; a button row that "worked" purely because two
# identically-named buttons tie-broke by creation order, until a third button broke the luck).
# It never errors, so nothing else in CI would catch it.
#
#   bash scripts/check-layouts.sh

set -euo pipefail

cd "$(dirname "$0")/.."

failures=0

while IFS= read -r file; do
    # awk walks each UIListLayout construction from its opening line to the `})` that closes the
    # property table, and reports the ones with no SortOrder anywhere inside.
    awk -v file="$file" '
        /Create\("UIListLayout"/ { inside = 1; found = 0; start = NR }
        inside && /SortOrder/    { found = 1 }
        inside && /^[[:space:]]*}\)/ {
            if (!found) {
                printf "%s:%d  UIListLayout created without SortOrder\n", file, start
                bad = 1
            }
            inside = 0
        }
        END { exit bad ? 1 : 0 }
    ' "$file" || failures=$((failures + 1))
done < <(find src -name "*.luau" | sort)

if [ "$failures" -gt 0 ]; then
    echo "" >&2
    echo "error: every UIListLayout must set SortOrder = Enum.SortOrder.LayoutOrder explicitly." >&2
    echo "       Roblox's default is alphabetical by Name, which sorts this library's elements wrong." >&2
    exit 1
fi

total=$(grep -rc 'Create("UIListLayout"' src/ --include="*.luau" | awk -F: '{ n += $2 } END { print n }')
echo "check-layouts: $total UIListLayout construction sites, all set SortOrder"

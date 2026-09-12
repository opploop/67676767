#!/usr/bin/env bash
# Copyright (c) 2026 Corridon Capital
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Fails if scripts/loader.luau or scripts/dev-loadstring.luau list a different set of modules
# than src/ actually contains.
#
# Both scripts fetch src/ file by file over HTTP, so they carry a hardcoded list of every module
# to request. Adding a component without adding it to those lists produces a library that builds
# fine, bundles fine, passes every test, and then dies the moment a consumer touches the new
# element: "<name> is not a valid member of Folder ReplicatedStorage.Rayfield.components". That
# happened twice in a row here (playerdropdown shipped broken for the file-by-file loader, and
# reorderlist/itemgrid followed it) because nothing in the build had any reason to notice.
#
# A stale entry is caught too: a name left behind after a file is deleted makes the loader
# request a 404 and fail the whole fetch.
#
#   bash scripts/check-loader-lists.sh

set -euo pipefail

cd "$(dirname "$0")/.."

status=0

# usage: check <script> <lua list variable> <src subdirectory>
check() {
    local file="$1" variable="$2" directory="$3"

    # The names inside `local <variable> = { ... }`, one per line. Deliberately tolerant of where
    # the braces fall: dev-loadstring.luau wraps one of its lists so the `{` lands on the line
    # after the `local`, and both files mix one-per-line and several-per-line styles.
    local declared
    declared=$(awk -v want="local $variable =" '
        index($0, want) == 1 { inside = 1 }
        inside {
            line = $0
            while (match(line, /"[^"]+"/)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
            if (index($0, "}") > 0) { inside = 0 }
        }
    ' "$file" | sort)

    if [ -z "$declared" ]; then
        echo "error: $file has no '$variable' list to check" >&2
        status=1
        return
    fi

    local onDisk
    onDisk=$(find "src/$directory" -maxdepth 1 -name "*.luau" -exec basename {} .luau \; | sort)

    local missing stale
    missing=$(comm -13 <(echo "$declared") <(echo "$onDisk"))
    stale=$(comm -23 <(echo "$declared") <(echo "$onDisk"))

    if [ -n "$missing" ]; then
        echo "error: $file '$variable' is missing: $(echo "$missing" | tr '\n' ' ')" >&2
        status=1
    fi
    if [ -n "$stale" ]; then
        echo "error: $file '$variable' lists files that no longer exist: $(echo "$stale" | tr '\n' ' ')" >&2
        status=1
    fi
}

for script in scripts/loader.luau scripts/dev-loadstring.luau; do
    check "$script" componentFiles components
    check "$script" utilityFiles utility
    check "$script" themeFiles themes
done

if [ "$status" -ne 0 ]; then
    echo "" >&2
    echo "       Add the new module(s) to the list(s) above, or the file-by-file loader will" >&2
    echo "       fail on the first consumer that touches them." >&2
    exit 1
fi

echo "check-loader-lists: loader.luau and dev-loadstring.luau match src/"

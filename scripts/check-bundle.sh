#!/usr/bin/env bash
# Copyright (c) 2026 Corridon Capital
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Fails if dist/rayfield.lua is not what scripts/build-bundle.sh would produce from the current
# src/ - i.e. if someone changed src/ and forgot to rebuild and commit the bundle.
#
# This is the quietest possible failure in the repo if it goes unchecked: hubs load
# dist/rayfield.lua straight off main, so a stale bundle means every consumer keeps running the
# old library with no error, no warning, and a fix that "didn't work" for reasons nothing in the
# code explains. Same class of problem the old pinned-commit loader had, minus the visible pin.
#
#   bash scripts/check-bundle.sh

set -euo pipefail

cd "$(dirname "$0")/.."

committed="dist/rayfield.lua"

if [ ! -f "$committed" ]; then
    echo "error: $committed is missing - run: bash scripts/build-bundle.sh" >&2
    exit 1
fi

# Build to a scratch copy so a check never mutates the working tree, then swap the real one back.
backup="$(mktemp)"
cp "$committed" "$backup"
restore() { cp "$backup" "$committed"; rm -f "$backup"; }
trap restore EXIT

bash scripts/build-bundle.sh > /dev/null

if ! cmp -s "$committed" "$backup"; then
    echo "error: $committed is out of date with src/." >&2
    echo "       Rebuild and commit it:  bash scripts/build-bundle.sh" >&2
    exit 1
fi

echo "check-bundle: $committed matches src/"

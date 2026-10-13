#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerates the model database from OpenRazer.
# Usage: scripts/update-models.sh [<git ref>]   (default: master)
set -euo pipefail

cd "$(dirname "$0")/.."
REF="${1:-master}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone --quiet --depth 1 --branch "$REF" https://github.com/openrazer/openrazer.git "$TMP/openrazer" 2>/dev/null \
    || { git clone --quiet https://github.com/openrazer/openrazer.git "$TMP/openrazer" && git -C "$TMP/openrazer" checkout --quiet "$REF"; }

COMMIT="$(git -C "$TMP/openrazer" log -1 --format=%H)"
DATE="$(git -C "$TMP/openrazer" log -1 --format=%cs)"
# -I: don't let anything in the checkout influence the interpreter.
python3 -I scripts/generate-models.py "$TMP/openrazer" "$COMMIT" "$DATE"
echo "Updated from OpenRazer $COMMIT ($DATE). Review the diff, run swift test, and commit."

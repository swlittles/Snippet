#!/bin/bash
# Reproducible Finder layout without driving Finder or requiring UI automation.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?App bundle path required}"
DESTINATION="${2:?Output DMG path required}"
MODE="${3:-signed}"
TOOLS="$PWD/.build/dmg-tools"
python3 -m venv "$TOOLS"
"$TOOLS/bin/python" -m pip install --disable-pip-version-check -q -r scripts/dmg-requirements.txt
ART=$(mktemp -d "$PWD/.build/dmg-art.XXXXXX")
trap 'rm -rf "$ART"' EXIT
if [ "$MODE" = preview ]; then
    swift scripts/make-dmg-background.swift "$ART" --preview
else
    swift scripts/make-dmg-background.swift "$ART"
fi
tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff"
"$TOOLS/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D background="$ART/background.tiff" Snippet "$DESTINATION"

# Validate the copied app too: Finder metadata must not invalidate its seal.
MOUNT=$(mktemp -d "$PWD/.build/dmg-check.XXXXXX")
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; rm -rf "$ART"' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DESTINATION" >/dev/null
codesign --verify --deep --strict "$MOUNT/Snippet.app"
hdiutil detach "$MOUNT" >/dev/null
rmdir "$MOUNT"

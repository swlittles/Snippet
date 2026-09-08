#!/bin/bash
# Build a universal DMG + ZIP. Stable distribution requires Developer ID + notarization.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-signed}"
[[ "$MODE" = signed || "$MODE" = preview ]] || { echo 'Usage: release.sh [signed|preview]' >&2; exit 1; }
VERSION=$(cat VERSION)
TEAM_ID="${APPLE_TEAM_ID:-KQFYGC7SWB}"
if [ "$MODE" = signed ]; then
    : "${SNIPPET_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
    : "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
    [[ "$SNIPPET_SIGNING_IDENTITY" != - ]] || { echo 'Stable releases cannot use ad-hoc signing.' >&2; exit 1; }
else
    export SNIPPET_SIGNING_IDENTITY=-
fi
export SNIPPET_OUTPUT_DIR="$PWD/release-build"
export SNIPPET_UNIVERSAL=1
export SNIPPET_BUILD_VARIANT=production
bash scripts/build.sh
APP="$SNIPPET_OUTPUT_DIR/Snippet.app"
mkdir -p release-assets
WORK=$(mktemp -d "$PWD/release-build/.package.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NAME="Snippet-$VERSION-macos-universal"
if [ "$MODE" = preview ]; then NAME="Snippet-$VERSION-preview-macos-universal"; fi
if [ "$MODE" = signed ]; then
    signature=$(codesign -dvv "$APP" 2>&1)
    [[ "$signature" == *"Authority=Developer ID Application:"* && "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] || { echo 'Wrong signing certificate or team.' >&2; exit 1; }
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
    xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/notary.json"
    if ! python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("status") != "Accepted")' "$WORK/notary.json"; then
        cat "$WORK/notary.json" >&2; exit 1
    fi
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi
mkdir -p "$WORK/disk"
ditto "$APP" "$WORK/disk/Snippet.app"
ln -s /Applications "$WORK/disk/Applications"
cp docs/INSTALL.md "$WORK/disk/Installation.md"
if [ "$MODE" = preview ]; then
    printf '%s\n' 'DEVELOPER PREVIEW — NOT NOTARIZED' 'This build is ad-hoc signed and is not a normal Gatekeeper-approved installation.' 'For routine use, wait for a signed stable release. See Installation.md.' > "$WORK/disk/PREVIEW.txt"
fi
hdiutil create -volname Snippet -srcfolder "$WORK/disk" -ov -format UDZO "$WORK/$NAME.dmg"
if [ "$MODE" = signed ]; then
    codesign --timestamp --sign "$SNIPPET_SIGNING_IDENTITY" "$WORK/$NAME.dmg"
    xcrun notarytool submit "$WORK/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/dmg-notary.json"
    python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("status") != "Accepted")' "$WORK/dmg-notary.json"
    xcrun stapler staple "$WORK/$NAME.dmg"
    xcrun stapler validate "$WORK/$NAME.dmg"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$NAME.zip"
cp "$WORK/$NAME.dmg" "$WORK/$NAME.zip" release-assets/
(cd release-assets && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME-SHA256SUMS.txt")
echo "Release assets: release-assets/$NAME.{dmg,zip}"

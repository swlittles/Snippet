#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT_DIR="${SNIPPET_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
DESTINATION="$OUTPUT_DIR/Snippet.app"
VERSION=$(cat VERSION)
BUILD_NUMBER=$(cat BUILD_NUMBER)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid BUILD_NUMBER" >&2; exit 1; }
IDENTITY="${SNIPPET_SIGNING_IDENTITY:--}"

assert_app_stopped() {
    if /bin/ps -axo comm= | /usr/bin/awk -v executable="$DESTINATION/Contents/MacOS/Snippet" '$0 == executable { found = 1 } END { exit !found }'; then
        echo "Snippet is running. Quit it from its menu bar before rebuilding." >&2
        echo "The installed app has been left untouched to preserve its running code identity and Accessibility permission." >&2
        exit 1
    fi
}
assert_app_stopped
if [ "${SNIPPET_UNIVERSAL:-0}" = "1" ]; then
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/distribution-$arch"
    done
else
    swift build -c release
fi
if [ ! -f assets/Snippet.icns ] || [ scripts/make-icon.swift -nt assets/Snippet.icns ]; then
    swift scripts/make-icon.swift "$PWD/assets"
    iconutil -c icns assets/Snippet.iconset -o assets/Snippet.icns
fi

STAGING_ROOT=$(mktemp -d "$OUTPUT_DIR/.Snippet-build.XXXXXX")
APP="$STAGING_ROOT/Snippet.app"
cleanup() {
    if [ -d "$STAGING_ROOT/previous.app" ] && [ ! -e "$DESTINATION" ]; then
        mv "$STAGING_ROOT/previous.app" "$DESTINATION"
    fi
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${SNIPPET_UNIVERSAL:-0}" = "1" ]; then
    arm_bin=$(swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/distribution-arm64 --show-bin-path)
    intel_bin=$(swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/distribution-x86_64 --show-bin-path)
    lipo -create "$arm_bin/Snippet" "$intel_bin/Snippet" -output "$APP/Contents/MacOS/Snippet"
    lipo "$APP/Contents/MacOS/Snippet" -verify_arch arm64 x86_64
else
    cp .build/release/Snippet "$APP/Contents/MacOS/Snippet"
fi
cp assets/Snippet.icns assets/MenuIcon.png assets/logo-1024.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snippet</string>
<key>CFBundleIdentifier</key><string>local.snippet.app</string>
<key>CFBundleIconFile</key><string>Snippet</string>
<key>CFBundleName</key><string>Snippet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
# Check again in case Snippet was opened while compilation was in progress.
assert_app_stopped
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$STAGING_ROOT/previous.app"
fi
mv "$APP" "$DESTINATION"
echo "Built $DESTINATION"
if [ "${SNIPPET_SIGNING_IDENTITY:--}" = "-" ]; then
    echo "Local ad-hoc build: changed code may require removing and re-adding Snippet in Accessibility settings."
fi

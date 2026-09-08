#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT_DIR="${SNIPPET_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
VARIANT="${SNIPPET_BUILD_VARIANT:-development}"
case "$VARIANT" in
    development) APP_NAME="Snippet Dev"; BUNDLE_ID="local.snippet.dev" ;;
    production) APP_NAME="Snippet"; BUNDLE_ID="local.snippet.app" ;;
    *) echo 'SNIPPET_BUILD_VARIANT must be development or production.' >&2; exit 1 ;;
esac
DESTINATION="$OUTPUT_DIR/$APP_NAME.app"
EXECUTABLE="$APP_NAME"
VERSION=$(cat VERSION)
BUILD_NUMBER=$(cat BUILD_NUMBER)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid BUILD_NUMBER" >&2; exit 1; }
IDENTITY="${SNIPPET_SIGNING_IDENTITY:--}"

assert_app_stopped() {
    if /bin/ps -axo comm= | /usr/bin/awk -v executable="$DESTINATION/Contents/MacOS/$EXECUTABLE" '$0 == executable { found = 1 } END { exit !found }'; then
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
APP="$STAGING_ROOT/$APP_NAME.app"
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
    lipo -create "$arm_bin/Snippet" "$intel_bin/Snippet" -output "$APP/Contents/MacOS/$EXECUTABLE"
    lipo "$APP/Contents/MacOS/$EXECUTABLE" -verify_arch arm64 x86_64
else
    arm_bin=$(swift build -c release --show-bin-path)
    cp .build/release/Snippet "$APP/Contents/MacOS/$EXECUTABLE"
fi
# SwiftPM links Sparkle; app bundles must embed and sign its helpers inside-out.
mkdir -p "$APP/Contents/Frameworks"
ditto "$arm_bin/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != - ]; then SIGN_ARGS+=(--options runtime --timestamp); fi
for component in "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app" \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" "$FRAMEWORK"; do
    codesign "${SIGN_ARGS[@]}" "$component"
done
ICON_DIR="$PWD/assets"
if [ "$VARIANT" = development ]; then
    ICON_DIR="$STAGING_ROOT/dev-assets"
    swift scripts/make-icon.swift "$ICON_DIR" --development
    iconutil -c icns "$ICON_DIR/Snippet.iconset" -o "$ICON_DIR/Snippet.icns"
fi
cp docs/THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/"
cp "$ICON_DIR/Snippet.icns" "$ICON_DIR/MenuIcon.png" "$ICON_DIR/logo-1024.png" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleIconFile</key><string>Snippet</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://github.com/swlittles/Snippet/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>YfIG78UZQGzCyzQtQsJHOojs16mS5v1YAP/RQ5zvUQg=</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUAllowsAutomaticUpdates</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
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

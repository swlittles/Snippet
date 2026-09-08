#!/bin/bash
# Run only on an ephemeral macOS Actions runner. Never enable shell tracing here.
set -euo pipefail
: "${RUNNER_TEMP:?}"
: "${GITHUB_ENV:?}"
: "${DEVELOPER_ID_P12_BASE64:?Add the signing certificate GitHub secret}"
: "${DEVELOPER_ID_P12_PASSWORD:?Add the certificate password GitHub secret}"
if [ -n "${NOTARY_API_KEY_P8:-}" ]; then
    : "${NOTARY_KEY_ID:?}"
    : "${NOTARY_ISSUER_ID:?}"
else
    : "${NOTARY_APPLE_ID:?Add notarization API credentials or Apple Account credentials}"
    : "${NOTARY_APP_PASSWORD:?Add a dedicated app-specific password}"
fi
umask 077
KEYCHAIN="$RUNNER_TEMP/snippet-signing.keychain-db"
P12="$RUNNER_TEMP/snippet-signing.p12"
P8="$RUNNER_TEMP/snippet-notary.p8"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
trap 'rm -f "$P12" "$P8"' EXIT
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$P12"
printf '%s' "${NOTARY_API_KEY_P8:-}" > "$P8"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/Developer ID Application:/ { print $2; exit }')
[[ -n "$IDENTITY" ]] || { echo 'No valid Developer ID Application identity in the supplied certificate.' >&2; exit 1; }
if [ -n "${NOTARY_API_KEY_P8:-}" ]; then
    xcrun notarytool store-credentials snippet-notary --key "$P8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --keychain "$KEYCHAIN" >/dev/null
else
    xcrun notarytool store-credentials snippet-notary --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_APP_PASSWORD" --team-id "${APPLE_TEAM_ID:-KQFYGC7SWB}" --keychain "$KEYCHAIN" >/dev/null
fi
printf 'SNIPPET_SIGNING_IDENTITY=%s\nNOTARY_PROFILE=snippet-notary\n' "$IDENTITY" >> "$GITHUB_ENV"
# Make notarytool use this profile without embedding credentials in build output.
security default-keychain -d user -s "$KEYCHAIN"

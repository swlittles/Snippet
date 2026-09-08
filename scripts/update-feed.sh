#!/bin/bash
# Publish a signed feed alongside immutable GitHub release assets.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPARKLE_ED_PRIVATE_KEY:?Configure the Sparkle signing secret}"
VERSION=$(cat VERSION)
WORK=$(mktemp -d "$PWD/.build/appcast.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NAME="Snippet-$VERSION-macos-universal"
cp "release-assets/$NAME.dmg" "$WORK/"
cp docs/RELEASE_NOTES.md "$WORK/$NAME.md"
TOOLS="$PWD/.build/distribution-arm64/artifacts/sparkle/Sparkle/bin"
# Feed and archive signatures are generated after Developer ID notarization/stapling.
# Keep the private key on stdin, out of arguments, files, and logs.
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/generate_appcast" \
    --ed-key-file - --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/swlittles/Snippet/releases/download/v$VERSION/" "$WORK"
python3 - "$WORK/appcast.xml" "$VERSION" "$(cat BUILD_NUMBER)" <<'PY'
import sys, xml.etree.ElementTree as ET
path,version,build=sys.argv[1:]
root=ET.parse(path).getroot()
ns={'sparkle':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item=root.find('./channel/item')
assert item.findtext('sparkle:version',namespaces=ns)==build
assert item.findtext('sparkle:shortVersionString',namespaces=ns)==version
enclosure=item.find('enclosure')
assert enclosure.attrib['url']==f'https://github.com/swlittles/Snippet/releases/download/v{version}/Snippet-{version}-macos-universal.dmg'
assert enclosure.attrib['{'+ns['sparkle']+'}edSignature']
assert int(enclosure.attrib['length'])>0
print('Verified signed update feed version and download URL.')
PY
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - --verify "$WORK/appcast.xml"
cp "$WORK/appcast.xml" release-assets/appcast.xml

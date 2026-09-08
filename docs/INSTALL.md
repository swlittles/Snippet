# Installing and updating Snippet

## Stable downloads

Use the DMG or ZIP attached to a [GitHub Release](https://github.com/swlittles/Snippet/releases). GitHub's automatically generated “Source code” archives contain source, not an installable app. Stable app downloads require macOS 13 or newer and include both arm64 (Apple Silicon) and x86_64 (Intel) executables.

Open the DMG, drag Snippet to Applications, eject the disk image, and launch the copy in Applications. With the ZIP, unzip it and move Snippet.app to Applications. No administrator-level installer or background service is installed.

The project is initially setting up Developer ID signing. Only releases explicitly described as signed and notarized are intended for normal installation. Developer previews are ad-hoc signed, not notarized, and may be blocked by Gatekeeper. Do not disable Gatekeeper or strip quarantine as an installation step; wait for a signed release or build from reviewed source for development.

## Permissions and first launch

Snippet stays in the menu bar. Option–Space opens its panel. If that combination is unavailable, open Snippet from its menu-bar icon and choose another shortcut in Settings.

Clipboard history is opt-in. Turn on “Remember copied text” in Settings. Capture begins with subsequent copies; it does not import another app's clipboard history.

Direct paste and keyword expansion need Accessibility permission. Click “Enable Accessibility…” in Snippet, then enable the **installed copy** in System Settings → Privacy & Security → Accessibility. macOS may ask for your password or Touch ID. Keyword expansion additionally requires its global setting and an enabled keyword on an individual snippet.

## Updating

1. Back up `~/Library/Application Support/Snippet/` if desired.
2. Quit Snippet using its menu-bar menu.
3. Download the new stable release and replace the app in Applications.
4. Reopen it. Your data is stored outside the app bundle and remains in place.

There is no built-in update checker or automatic updater. GitHub release notifications can tell you when updates are available.

## Accessibility says enabled, but paste is denied

Quit and reopen the exact installed copy first. If this started after replacing a development/ad-hoc build, remove Snippet's old Accessibility entry and re-add the current app. A visible checkmark can refer to an earlier code signature. A consistent Developer ID identity is intended to keep identity stable across signed updates; switching from a local ad-hoc build may require one fresh grant.

Snippet never bypasses a macOS denial. Without permission, it copies the text and shows guidance. Custom editors or apps that refuse simulated input may still require manual paste.

## Verify a download

Download the matching `SHA256SUMS.txt`, DMG, and ZIP into the same folder, then run:

```sh
shasum -a 256 -c Snippet-3.2.0-macos-universal-SHA256SUMS.txt
```

The checksum file lists both assets, so a missing one is reported as missing. Signed releases also support:

```sh
codesign --verify --strict /Applications/Snippet.app
spctl --assess --type execute --verbose=2 /Applications/Snippet.app
xcrun stapler validate /Applications/Snippet.app
```

The expected Developer Team ID is `KQFYGC7SWB`. Checksums detect corruption; Apple signature and Gatekeeper checks establish the signed developer identity.

## Login and uninstall

To launch on login, add Snippet under System Settings → General → Login Items. To uninstall, quit the app, remove it from Login Items if present, and move it to Trash. Your library remains in `~/Library/Application Support/Snippet/` until you remove it yourself. Preferences use the `local.snippet.app` UserDefaults domain. Removing that data permanently deletes your local library/preferences; export or back it up first.

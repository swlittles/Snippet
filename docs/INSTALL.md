# Installing and updating Snippet

## Stable downloads

Use the DMG or ZIP attached to a [GitHub Release](https://github.com/swlittles/Snippet/releases). GitHub's automatically generated “Source code” archives contain source, not an installable app. Stable app downloads require macOS 13 or newer and include both arm64 (Apple Silicon) and x86_64 (Intel) executables.

Open the DMG, drag Snippet to Applications, eject the disk image, and launch the copy in Applications. With the ZIP, unzip it and move Snippet.app to Applications. No administrator-level installer or background service is installed.

Stable release assets are signed and notarized before publication. Only releases explicitly described as signed and notarized are intended for normal installation. Developer previews are ad-hoc signed, not notarized, and may be blocked by Gatekeeper. Do not disable Gatekeeper or strip quarantine as an installation step; wait for a signed release or build from reviewed source for development.

## Permissions and first launch

Snippet stays in the menu bar. Option–Space opens its panel. If that combination is unavailable, open Snippet from its menu-bar icon and choose another shortcut in Settings.

Clipboard history is opt-in. Turn on “Remember copied text” in Settings. Capture begins with subsequent copies; it does not import another app's clipboard history.

Direct paste and keyword expansion need Accessibility permission. Click “Enable Accessibility…” in Snippet, then enable the **installed copy** in System Settings → Privacy & Security → Accessibility. macOS may ask for your password or Touch ID. Keyword expansion additionally requires its global setting and an enabled keyword on an individual snippet.

## Updating

1. Back up `~/Library/Application Support/Snippet/` if desired.
2. Quit Snippet using its menu-bar menu.
3. Download the new stable release and replace the app in Applications.
4. Reopen it. Your data is stored outside the app bundle and remains in place.

Starting with 3.3.0, choose **Check for Updates…** from Snippet’s menu bar menu or **Settings → Updates**. Sparkle checks the signed feed, shows release notes, downloads the update, and offers to install and relaunch. Your library lives outside the app and is preserved.

Enable **Automatically check for updates** in Settings for daily checks. It defaults to off; updates are installed only when you choose. Background reminders appear in the menu and Updates settings without taking keyboard focus. The Settings panel also shows the last check time. A manual check reports when you are up to date or when the server cannot be reached.

Versions 3.2.x require one manual download to gain the updater. Snippet Dev does not contact the feed or install production updates. Run the release app from Applications, not directly from a mounted DMG.

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

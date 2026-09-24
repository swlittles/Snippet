A native macOS clipboard, snippet, and calculator launcher. Requires macOS 13 or newer; one universal app supports Apple Silicon and Intel.

### What’s new in 3.5.0

- **Click to paste.** A single click on a result pastes it, like Return. The second click of a double-click is absorbed so it can't land in your document.
- **More reliable direct paste.** Snippet waits for the destination window to be ready before sending Command–V, and returns focus more dependably on recent macOS versions.
- **Fewer missed copies.** Text copied from Office, Pages and Numbers is recorded as text rather than as a picture. Rich-text-only copies are captured, and quick successive copies are no longer lost while Snippet is in the background.
- **Frequently used.** The new flame filter shows clips and snippets you've used several times in the last few days. They fade on their own when you stop using them, so there's nothing to unfavorite.
- **Apps.** Press Command–4 to search and open installed apps by name, word starts or initials. Matching apps also appear after text results, so Return opens an app when nothing else matches.
- A smoother launcher with large histories and screenshots.
- The menu-bar icon toggles its menu cleanly and dismisses it on outside clicks.

Use counts for the Frequent filter are stored locally in `usage.json` and are never synced.

From 3.3.0 or later, choose **Check for Updates…** to install this release. Versions 3.2.x require one manual upgrade to gain the updater.

### Install

Download the DMG, open it, and drag Snippet into Applications. The ZIP is an alternative app download. Source archives are for developers.

These stable assets are Developer ID signed and Apple notarized for team `KQFYGC7SWB`. The app and DMG have stapled notarization tickets. SHA-256 checksums accompany both downloads.

Enable clipboard capture in Settings if wanted. Direct paste and optional keyword expansion require macOS Accessibility permission. When upgrading from an ad-hoc development build, you may need to refresh Snippet's Accessibility entry once.

Quit the old app before replacing it. Your local library is stored outside the app bundle. After this installation, use Check for Updates for future releases.

See the repository's installation guide, privacy document, and changelog for details. Intel/macOS 13 cross-compilation is checked; the full hardware/OS runtime matrix has not yet been tested.

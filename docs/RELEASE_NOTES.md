A native macOS clipboard, snippet, and calculator launcher. Requires macOS 13 or newer; one universal app supports Apple Silicon and Intel.

### What’s new in 3.4.0

- Workspace (Cmd–K) brings local developer tools, quicklinks, collections and snippet packs together.
- Smart snippets prompt for fields and support date, clipboard, UUID and cursor placeholders.
- Markdown previews and formatted paste, including code blocks and basic tables.
- Image clipboard history with local text recognition and searchable thumbnails.
- Reorderable paste queues with individual and combined text actions.
- Unit conversions, natural percentages and date arithmetic; unlimited calculation history.
- Optional iCloud Drive folder sync for your library, with a separate clipboard-sharing opt-in.
- New shortcuts are configurable. Existing libraries migrate automatically.

Sync is off until you choose a folder. Real iCloud delivery depends on macOS and has not been tested across two physical Macs. See the Workspace guide for supported Markdown syntax, cursor-placement behavior and conflict handling.

From 3.3.0 or later, choose **Check for Updates…** to install this release. Versions 3.2.x require one manual upgrade to gain the updater.

### Install

Download the DMG, open it, and drag Snippet into Applications. The ZIP is an alternative app download. Source archives are for developers.

These stable assets are Developer ID signed and Apple notarized for team `KQFYGC7SWB`. The app and DMG have stapled notarization tickets. SHA-256 checksums accompany both downloads.

Enable clipboard capture in Settings if wanted. Direct paste and optional keyword expansion require macOS Accessibility permission. When upgrading from an ad-hoc development build, you may need to refresh Snippet's Accessibility entry once.

Quit the old app before replacing it. Your local library is stored outside the app bundle. After this installation, use Check for Updates for future releases.

See the repository's installation guide, privacy document, and changelog for details. Intel/macOS 13 cross-compilation is checked; the full hardware/OS runtime matrix has not yet been tested.

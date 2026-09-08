A native macOS clipboard, snippet, and calculator launcher. Requires macOS 13 or newer; one universal app supports Apple Silicon and Intel.

### What’s new in 3.2.2

- A polished, compact installer with Retina artwork and a clear drag-to-Applications layout. No loose Markdown files.
- Local source builds now run as Snippet Dev, with separate data, settings, permissions, and a distinct icon.
- Fixed preferences initialization at startup and added startup verification for both build variants.

### Install

Download the DMG, open it, and drag Snippet into Applications. The ZIP is an alternative app download. Source archives are for developers.

These stable assets are Developer ID signed and Apple notarized for team `KQFYGC7SWB`. The app and DMG have stapled notarization tickets. SHA-256 checksums accompany both downloads.

Enable clipboard capture in Settings if wanted. Direct paste and optional keyword expansion require macOS Accessibility permission. When upgrading from an ad-hoc development build, you may need to refresh Snippet's Accessibility entry once.

Quit the old app before replacing it. Your local library is stored outside the app bundle. Updates are manual; there is no automatic updater.

See the repository's installation guide, privacy document, and changelog for details. Intel/macOS 13 cross-compilation is checked; the full hardware/OS runtime matrix has not yet been tested.

# Changelog

## 3.6.1

- Show whether Accessibility access is granted. Settings shows "Accessibility access is on" instead of the enable link, and the menu-bar item reads "Accessibility Enabled" with a checkmark. Both previously always asked you to enable it.

## 3.6.0

- Add an optional **Vault** section (Command–5) that searches a Bitwarden vault on Bitwarden.com, Bitwarden.eu, a self-hosted Bitwarden server or Vaultwarden, and pastes passwords, usernames, notes, card details and verification codes. Items are read-only for now.
- Sign in with a master password plus authenticator, email or YubiKey codes, new-device verification, or a personal API key. The master password is never stored or sent.
- Decrypt on this Mac with PBKDF2 or Argon2id accounts, organization items and per-item keys. The encrypted vault is cached for offline unlocking; tokens are kept in the Keychain.
- Lock automatically after inactivity and on sleep, screen lock or user switch. Honor master-password re-prompt on items.
- Mark copied vault values confidential so clipboard history skips them, and clear them from the clipboard after a configurable delay.

## 3.5.0

- Make the menu-bar icon toggle its menu on mouse-down without reopening on mouse-up.
- Ignore stale outside-click callbacks when reopening the menu and activate before menu tracking begins.
- Paste on a single click. A double-click's second click is absorbed instead of landing in the destination.
- Make direct paste more reliable: wait for the destination window to settle before Command–V, use cooperative activation on macOS 14+, fall back to hiding Snippet, and remember the last app across every way of opening the launcher.
- Capture copies that were previously missed: record text instead of the picture Office/iWork add alongside it, read rich-text-only copies, keep polling during menus and drags, and prevent App Nap from delaying capture.
- Add a **Frequent** filter (flame) for clips and snippets used several times in the last few days. Scores decay, so temporary heavy use fades without unfavoriting anything.
- Add **Apps** (Command–4) to search and open installed apps. Matching apps also appear after text results in Clipboard and Snippets, so Return opens an app when nothing else matches.
- Speed up the launcher: results are computed once per change, row dates are formatted only for visible rows, and image thumbnails are decoded once.

## 3.4.0

- Add Workspace with local text/developer tools, quicklinks, collections and import/export.
- Add smart snippets with fill-in fields, date/clipboard/UUID variables and cursor placement.
- Add native Markdown previews, basic tables and formatted RTF paste.
- Capture copied images with local Vision OCR, thumbnails and recognized-text editing/copying.
- Add a persistent, reorderable paste queue with individual and combined text actions.
- Add natural percentages, unit/temperature conversions and date arithmetic; remove the calculation-history count cap.
- Add explicit iCloud Drive folder sync with revisions, deletion tombstones and separately opt-in clipboard sharing.
- Import Snippet packs, legacy libraries, Markdown and Alfred collections without overwriting existing snippets.
- Add configurable Workspace and queue shortcuts; preserve existing library and preference formats.

## 3.3.2

- Handle the launcher toggle before native text input, including when a field editor owns focus.
- Route the registered global shortcut through the Carbon event dispatcher.
- Remove the redundant favorites/limits note from Storage settings.

## 3.3.1

- Removed the redundant Settings section label above the tabs.
- Keep clipboard history indefinitely by default, without a count limit.
- Added Storage settings for optional age/count cleanup, with confirmation before removing existing clips.
- Keep favorites exempt from all cleanup rules.

## 3.3.0

- Added Sparkle updates: Check for Updates in the menu bar and Settings, optional daily checks, and download/install/relaunch.
- Added gentle update reminders and last-check information.
- Sign update feeds and archives; verify downloads before extraction and retain Developer ID signing and notarization.
- Keep automatic updates disabled in Snippet Dev.

## 3.2.2

- Preserve the app signature when configuring the installer’s Finder appearance.
- Verify the packaged app signature inside the DMG before publication.

## 3.2.1

- Redesigned the DMG with a compact branded Retina background, drag-to-Applications layout, and no loose documentation files.
- Fixed bundled preferences initialization at startup.

- Separate local Snippet Dev builds from production: bundle identity, data, settings, Accessibility permission, default hotkey, and DEV icon/menu label.
- Default local builds to development; release scripts explicitly select production.
- Verify both build variants in CI.

## 3.2.0 — initial public release

- Added favorites for clips and snippets, favorite-first sorting, and a favorites-only filter.
- Exempted favorite clips from age/capacity cleanup and Clear History; re-copying preserves favorites.
- Added in-place clip editing and visible pencil controls for both result types.
- Added configurable Cmd–Shift–F favorite action; Cmd–E now edits either result type.
- Included native clipboard history, reusable snippets and optional keyword expansion.
- Included calculator history, preset/custom themes, and fully configurable shortcuts.
- Added universal macOS packaging, checksums, CI, and a Developer ID/notarization release workflow.

This is the first public repository snapshot. Earlier local development versions were not published GitHub releases. Signed binary availability is tracked on the Releases page.

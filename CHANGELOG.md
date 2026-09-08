# Changelog

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

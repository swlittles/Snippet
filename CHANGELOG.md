# Changelog

## Unreleased

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

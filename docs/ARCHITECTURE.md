# How Snippet works

Snippet is a Swift Package executable targeting macOS 13+. AppKit owns app lifecycle, the menu bar, the panel, and native event handling. SwiftUI renders the panel, editors, calculator, and settings. There are no third-party runtime dependencies.

## Source map

| File | Responsibility |
| --- | --- |
| `AppEnvironment.swift` | Runtime build identity, data paths, and preferences domain |
| `main.swift` | AppDelegate, NSPanel, menu bar, global Carbon hotkey, menu commands, previous-app activation and paste |
| `LauncherView.swift` | Search/selection state, results, favorite and edit actions, clip/snippet editors, general settings |
| `Store.swift` | Snippet model, search, atomic persistence |
| `History.swift` | Clip model, legacy decoding, favorites, deduplication, retention, editing, keyword matcher |
| `Services.swift` | Clipboard polling, sensitive-type exclusions, Accessibility-gated keyword event tap |
| `Shortcuts.swift` | Bindings, contextual conflict validation, persistence, recording, settings UI |
| `Navigation.swift` | Section cycling and result navigation |
| `Calculator.swift` | Tokenizer/parser, numeric evaluation, calculation persistence |
| `CalculatorView.swift` | Calculator keypad and history UI |
| `Theme.swift` | Theme presets, custom colors, native color panels, shared cursor styles and logo mark |

## Copy → history → paste

1. ClipboardService polls the pasteboard change count every 0.4 seconds.
2. When enabled, it rejects marked concealed/transient/generated content and known password apps, then reads plain text.
3. History records non-empty text up to 100,000 UTF-8 bytes. Re-copies retain the chosen entry's ID and favorite status.
4. Retention keeps all favorites plus at most 500 recent ordinary entries. Pruning occurs at startup, when opening the launcher, and periodically.
5. Search filters results by query words and the optional favorites-only mode. Favorites sort first.
6. Paste writes the selected text to the system clipboard with an auto-generated marker. The app checks Accessibility trust, activates the saved destination, and posts Command–V after it becomes frontmost.

If permission or activation fails, the text remains copied and the UI explains the problem. The app doesn't read the destination's document.

## Data and errors

`~/Library/Application Support/Snippet/` stores `snippets.json`, `history.json`, and `calculations.json`. Writes are atomic and files use mode 0600. A read or save error blocks subsequent writes through that store and is surfaced in the UI; unreadable originals are preserved. Settings, shortcuts, and themes use UserDefaults.

Clip decoding treats a missing `favorite` field as false for older history files. Clip edits retain identity/source/date; they validate non-empty content and the capture size limit. Editor drafts are value types and aren't persisted on Cancel. Unfavoriting doesn't reset a clip's age, so normal pruning can subsequently remove it.

## Keyboard contexts

The global launcher binding uses Carbon RegisterEventHotKey. A local AppKit monitor handles panel/sheet shortcuts and prevents matched commands from falling through. Each action declares contexts (launcher, calculator, editor, settings); conflict checks allow the same key in disjoint contexts. Native text editing and editor save actions pass through to the responder chain or SwiftUI when appropriate.

## Expansion

When enabled and trusted, a CGEvent tap feeds a short-lived ASCII keyword buffer. Matching `;keywords` delete the already delivered keyword characters and insert Unicode text without replacing the clipboard. Secure input, known password apps, modifiers, focus changes, and pauses reset or exclude matching. The buffer is in memory, bounded to 64 characters, and not persisted. Expansion text is limited to 2,000 UTF-16 units.

## Distribution

`VERSION` and `BUILD_NUMBER` drive bundle metadata. `scripts/build.sh` builds a native or universal app, stages replacement, and refuses to overwrite a running bundle. `scripts/release.sh` signs with hardened runtime and a secure timestamp, notarizes and staples the app, packages a DMG/ZIP, notarizes and staples the DMG, then writes checksums. The signed release path checks team identity and refuses to continue after notarization failure.

Production retains `local.snippet.app` to preserve preferences and avoid an unnecessary identity migration. Local packaging defaults to `local.snippet.dev` / Snippet Dev; unbundled `swift run` also uses development storage and preferences. All stores and settings use `AppEnvironment` to select their domain. The Apple Team ID is independently verified during signing.

## Verification

`bash scripts/test.sh` uses a standalone Swift test executable and isolated temporary storage. It covers persistence, search, migration, corrupt-file preservation, clipboard filtering, favorite age/capacity exemptions, re-copying, clip edits, calculation parsing/history, themes, shortcut validation/persistence, and navigation. CI builds both architectures. Hardware testing on macOS 13 and Intel is still needed for a complete compatibility matrix; cross-compilation is not a runtime test.

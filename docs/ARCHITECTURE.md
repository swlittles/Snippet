# How Snippet works

Snippet is a Swift Package executable targeting macOS 13+. AppKit owns app lifecycle, the menu bar, the panel, and native event handling. SwiftUI renders the panel, editors, calculator, and settings. Sparkle provides signed app updates; other features use Apple frameworks.

## Source map

| File | Responsibility |
| --- | --- |
| `AppEnvironment.swift` | Runtime build identity, data paths, and preferences domain |
| `main.swift` | AppDelegate, NSPanel, menu bar, global Carbon hotkey, menu commands, previous-app activation and paste |
| `LauncherView.swift` | Search/selection state, results, favorite and edit actions, clip/snippet editors, general settings |
| `Store.swift` | Snippet model, search, atomic persistence |
| `History.swift` | Clip model, legacy decoding, favorites, deduplication, retention, editing, keyword matcher |
| `Services.swift` | Clipboard polling and text-vs-image choice, sensitive-type exclusions, Command–V posting, double-click guard, Accessibility-gated keyword event tap |
| `Usage.swift` | Decaying use scores for the Frequent filter and app ranking |
| `Apps.swift` | Background scan of app folders, name matching and ranking, icons |
| `Shortcuts.swift` | Bindings, contextual conflict validation, persistence, recording, settings UI |
| `Navigation.swift` | Section cycling and result navigation |
| `Calculator.swift` | Tokenizer/parser, numeric evaluation, calculation persistence |
| `CalculatorView.swift` | Calculator keypad and history UI |
| `Theme.swift` | Theme presets, custom colors, native color panels, shared cursor styles and logo mark |
| `VaultCrypto.swift` | Bitwarden EncStrings, PBKDF2/Argon2id/HKDF key derivation, AES-CBC + HMAC, RSA-OAEP, TOTP, BLAKE2b |
| `VaultAPI.swift` | Server endpoints, prelogin, token grants, two-step errors, sync request |
| `Vault.swift` | Sync decoding and item decryption, encrypted cache, Keychain secrets, lock state, search |
| `VaultView.swift` | Vault settings and sign-in, item details, master-password re-prompt |

## Copy → history → paste

1. ClipboardService polls the pasteboard change count every 0.25 seconds in common run-loop modes. While capture is enabled it holds a user-initiated activity so App Nap can't stretch the interval and let one copy overwrite another unseen.
2. When enabled, it rejects marked concealed/transient/generated content and known password apps, then reads text or image representations. An image wins only if its type precedes every text type or there's no text, because Office/iWork add a picture of copied text. Rich-text-only copies are read as plain text. Images are normalized to PNG; Vision OCR runs off the main thread.
3. History records non-empty text up to 100,000 UTF-8 bytes. Re-copies retain the chosen entry's ID and favorite status.
4. Retention is unlimited by default. User-selected age/count rules apply to ordinary clips; favorites are always kept. Pruning occurs at startup, when opening the launcher, and periodically.
5. Search filters results by query words and the optional favorites-only mode. Favorites sort first.
6. Paste writes the selected text to the system clipboard with an auto-generated marker. The app checks Accessibility trust, yields activation to the saved destination (the last other app activated, tracked by notification), waits until it's frontmost plus 80 ms for its window to regain focus, and posts Command–V. After 0.35 seconds it hides itself so macOS returns focus, and it gives up after 1.5 seconds. A click-triggered paste arms a short event tap that swallows the rest of a double-click so it can't select text in the destination.

Launcher results are computed once per input change and cached. Re-copying existing text and every launcher paste/copy is recorded in `usage.json`. Each use counts 0.5^(age / 3 days). A score of at least 1.5 marks an item frequent.

If permission or activation fails, the text remains copied and the UI explains the problem. The app doesn't read the destination's document.

## Data and errors

`~/Library/Application Support/Snippet/` stores `snippets.json`, `history.json`, `calculations.json`, `usage.json`, `workspace.json`, `sync-journal.json`, the optional encrypted `vault-cache.json`, and the `Images/` attachment directory. Writes are atomic and files use mode 0600. A read or save error blocks subsequent writes through that store and is surfaced in the UI; unreadable originals are preserved. Settings, shortcuts, and themes use UserDefaults.

Clip decoding treats a missing `favorite` field as false for older history files. Clip edits retain identity/source/date; they validate non-empty content and the capture size limit. Editor drafts are value types and aren't persisted on Cancel. Unfavoriting doesn't reset a clip's age, so normal pruning can subsequently remove it.

## Keyboard contexts

The global launcher binding uses Carbon RegisterEventHotKey. A local AppKit monitor handles panel/sheet shortcuts and prevents matched commands from falling through. Each action declares contexts (launcher, calculator, editor, settings); conflict checks allow the same key in disjoint contexts. Native text editing and editor save actions pass through to the responder chain or SwiftUI when appropriate.

## Expansion

When enabled and trusted, a CGEvent tap feeds a short-lived ASCII keyword buffer. Matching `;keywords` delete the already delivered keyword characters and insert Unicode text without replacing the clipboard. Secure input, known password apps, modifiers, focus changes, and pauses reset or exclude matching. The buffer is in memory, bounded to 64 characters, and not persisted. Expansion text is limited to 2,000 UTF-16 units.

## Distribution

`VERSION` and `BUILD_NUMBER` drive bundle metadata. `scripts/build.sh` builds a native or universal app, stages replacement, and refuses to overwrite a running bundle. `scripts/release.sh` signs with hardened runtime and a secure timestamp, notarizes and staples the app, packages a DMG/ZIP, notarizes and staples the DMG, then writes checksums. The signed release path checks team identity and refuses to continue after notarization failure.

Production retains `local.snippet.app` to preserve preferences and avoid an unnecessary identity migration. Local packaging defaults to `local.snippet.dev` / Snippet Dev; unbundled `swift run` also uses development storage and preferences. All stores and settings use `AppEnvironment` to select their domain. The Apple Team ID is independently verified during signing.

## Verification

`bash scripts/test.sh` uses a standalone Swift test executable and isolated temporary storage. It covers persistence, search, migration, corrupt-file preservation, clipboard filtering, favorite age/capacity exemptions, re-copying, clip edits, text-over-rendering capture, rich-text capture, re-copy usage, frecency decay and pruning, app scanning (including hidden-flag symlinks like Safari) and ranking, calculation parsing/history, themes, shortcut validation/persistence, and navigation. CI builds both architectures. Hardware testing on macOS 13 and Intel is still needed for a complete compatibility matrix; cross-compilation is not a runtime test.

## Vault

`VaultStore` implements the Bitwarden client protocol directly, with no SDK. Sign-in fetches the account's KDF settings from `identity/accounts/prelogin`, derives the master key (PBKDF2-SHA256 with the email as salt, or Argon2id with the email's SHA-256), and sends only `PBKDF2(masterKey, password, 1)` to `identity/connect/token`. Two-step and new-device responses pause sign-in with the derived key held in memory until a code is entered. The HKDF-stretched master key opens the account's user key; the user key opens the RSA private key, which unwraps organization keys; items with their own key are opened with it. Unknown item types are skipped, and items that fail authentication are counted and hidden.

The raw `api/sync` response is saved as `vault-cache.json` alongside the KDF settings, so unlocking is offline and never needs the network. Refresh and API-key secrets are in the Keychain. Refreshes compare the server's protected user key and KDF settings with the cache; a change locks the vault rather than mixing keys. Decrypted `VaultItem`s live only in `VaultStore.items` and are cleared on lock, timeout, sleep, screen lock and user switch. Launcher results for vault items carry no text, so previews, Workspace tools and the paste queue never receive secrets. Paste and copy mark the pasteboard concealed and clear it after a delay if it's unchanged.

JSON keys are decoded case-insensitively for the first letter, because Vaultwarden has returned PascalCase where Bitwarden returns camelCase. Tests cover RFC vectors for BLAKE2b, Argon2id, PBKDF2 and TOTP, EncString parsing and tampering, and a full sign-in, two-step, sync, decrypt, relaunch, offline unlock, refresh, key change and sign-out cycle against an in-process fake server.

## Workspace implementation

- `TextTools.swift`: literal template substitution, local text/developer transforms, unit and date parsing. No eval or shell execution.
- `MarkdownView.swift`: native block and inline preview plus RTF conversion; no web view, remote images or executable HTML.
- `Workspace.swift`: queue snapshots, collection names, validated quicklinks, pack codecs and Vision image handling.
- `WorkspaceView.swift`: explicit user actions, import review, templates, tools, queue, links and sync controls.
- `LibrarySync.swift`: a coordinated shared file, per-item revisions and tombstones, persisted local journal and separate clipboard opt-in. See WORKSPACE.md for conflict semantics.

New optional model fields preserve compatibility with existing local JSON. Queue snapshots survive clip deletion. Calculation display strings preserve unit/date results alongside the numeric value, and calculation history no longer has a count cap. All new shortcut bindings go through the existing contextual registry.

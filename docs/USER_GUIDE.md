# User guide

A native macOS clipboard-history and text-snippet launcher inspired by Alfred’s keyboard workflow. SwiftUI + AppKit; no dependencies or network requests. macOS 13+.

## Run

Use the production app from Releases for everyday use. Local source builds produce `dist/Snippet Dev.app` with separate data/settings and Control–Option–Space as the default hotkey. See [development versus production](DEVELOPMENT.md). The app stays in the menu bar.

```sh
./scripts/build.sh
open "dist/Snippet Dev.app"
```

## Quick workflow

1. Click **Enable clipboard history** once, then copy text normally in any app.
2. Press **Option–Space**. Type to search copied text.
3. Use **Up/Down**, then **Return** to paste into the app you were using and close the launcher.
4. Press **Command–S** on a history result to save it permanently as a snippet.
5. Press **Command–2** for saved snippets, or type `snip ` followed by a title or keyword.

Other controls: **Command–Return** copies and closes; **Command–1 / 2 / 3** switches to Clipboard / Snippets / Calculator; **Tab / Shift–Tab** selects the next/previous result within Clipboard or Snippets (wrapping at the ends); **Command–N** creates a snippet; **Command–E** edits the selected clip or snippet in place; **Command–Shift–F** toggles its favorite status; **Command–P** toggles the full-text preview; **Command–comma** opens settings; **Escape** dismisses. Double-click a result to paste; right-click for copy, save, or removal. Clicking outside dismisses the launcher.

## Favorites and editing

Click the star on any clip or snippet to favorite it. Favorites sort first; the star beside the section tabs filters the list to favorites only. Favorite clips are exempt from any age or count cleanup rules you choose and remain favorites when copied again. Clear clipboard history keeps favorites; individual removal still deletes them. Unfavoriting makes a clip eligible for normal retention cleanup based on its capture date.

Click a result’s pencil or press **Command–E** to edit it. Clip edits update the existing entry and preserve its source and capture date; snippet edits include title, text, tags, keyword, expansion, and favorite status. **Command–S** saves editor changes; **Escape** cancels. From the result list, **Command–S** still saves a clip as a separate snippet. Editing never changes text already pasted into another app.

## Direct paste and keyword expansion

Open Settings using the gear, then click **Enable Accessibility…** to open the macOS Accessibility pane directly. Enable Snippet in macOS **System Settings → Privacy & Security → Accessibility**. If macOS requires it, quit and reopen Snippet after granting access. Without access, Return copies and shows setup guidance.

To expand text:

1. Edit a snippet and assign a keyword such as `;email`.
2. Check **Expand automatically when I type this keyword** and save.
3. In Settings enable **Expand snippet keywords as I type**.
4. Type `;email` in a text field in another app. Its final character triggers replacement with the snippet, without opening the launcher.

Keywords are case-sensitive, begin with `;`, contain 2–32 ASCII characters without spaces, and must be unique. Expansion will not trigger inside a word. Navigation, clicks, app switches, and typing pauses of more than three seconds reset partial matches. Expansion does not change the clipboard. Automatic expansion supports up to 2,000 UTF-16 units; use the launcher for larger snippets. Secure input and known password apps are excluded. Some applications or custom editors may not accept simulated input; copy/paste remains available.

## Configurable shortcuts

Open **Settings → Shortcuts**. Click a command’s shortcut, then press a new key combination. Changes save immediately and apply to the launcher, menus, and shortcut hints. The **×** button clears a binding. Escape cancels recording; the recording row’s **Esc** button explicitly assigns Escape. **Restore all defaults** resets assignments with confirmation.

Every app command is configurable, including the global launcher, section selection, result navigation, paste/copy, snippet editor, calculator, dismissal, quitting, and native text-editing commands. Conflicts are checked within the views where commands apply. The same key may be used in separate views (for example, Return pastes a clip and calculates an expression). Changing the global shortcut registers the new combination first; if macOS reports it unavailable, the previous binding is retained. A global binding needs Command, Option, or Control.

Default navigation:

- **Command–1 / 2 / 3:** Clipboard / Snippets / Calculator.
- **Tab / Shift–Tab:** next/previous result in Clipboard and Snippets, wrapping around.
- **Down / Up:** next/previous result, stopping at list boundaries.
- **Control–Tab / Control–Shift–Tab:** next/previous section.
- In Calculator, settings, and editors, unassigned Tab continues normal keyboard focus navigation.

The keyboard shortcuts elsewhere in this document describe defaults. Use the labels in the app for your customized assignments. Shortcut settings persist in macOS UserDefaults.

## Calculator

Press **Command–3** for Calculator. Type an expression into the search field or use the keypad. **Return** or **=** calculates and saves a result; **Command–Return** copies the result without closing the calculator. History remembers the latest 200 calculations across launches, including angle mode. Click a history item to reuse its expression, or its copy icon to copy the saved result. Clear history with confirmation.

Supported syntax:

- Arithmetic: `+`, `-`, `*`/`×`, `/`/`÷`, parentheses, decimals, and scientific notation (`1.5e3`).
- Powers: `2^3`, right-associative exponents (`2^3^2 = 512`), unary minus (`-2^2 = -4`).
- `%` divides a value by 100 (`200*15% = 30`); `!` computes factorial for integers 0–170.
- Functions: `sqrt`, `abs`, `sin`, `cos`, `tan`, `log` (base 10), `ln`, `exp`, `round`, `floor`, `ceil`, and two-argument `min`, `max`, `pow`.
- Constants: `pi` / `π`, `e`, and `ans` (most recent saved result).
- Implicit multiplication before a parenthesis or name: `2(3+4)`, `2pi`.
- Switch **RAD / DEG** for trigonometry. Invalid expressions, division by zero, and out-of-range results show an error without saving.

Calculations use floating-point arithmetic and display up to 14 significant digits. No shell commands, scripts, or arbitrary code are evaluated.

## Themes and logo

Open **Settings → Appearance** to choose Midnight, Paper, Ocean, Forest, or Rose. Six native color pickers customize background, surface, text, muted text, accent, and selection colors. Changes apply immediately and persist across launches. Picking a preset replaces the current palette; Reset restores Midnight.

The app’s new stacked-card logo appears in the launcher, settings, menu bar, and app bundle. Editable vector artwork is at `../assets/logo.svg`; `assets/logo-1024.png` and `assets/Snippet.icns` are generated by `scripts/make-icon.swift` during packaging. Custom buttons, tabs, rows, and links show pointing-hand cursors; text fields retain text cursors.

## History and privacy

History and expansion start disabled. Enable each from the app when wanted. History captures **plain text**, including multiline text and URLs, up to 100 KB per clip. It keeps clips indefinitely without a count limit by default and moves recopied text to the top. Settings → Storage offers optional age/count cleanup; applying a rule confirms any immediate deletions. Favorites are exempt from age and capacity cleanup. Images, rich text formatting, and file objects are not captured.

Pause capture in Settings, remove individual clips through their context menu, or clear history with confirmation. Clearing history does not delete favorite clips or saved snippets. Clipboard data marked concealed, transient, or auto-generated is ignored, along with known password apps. These filters cannot recognize every sensitive text value copied by every app; history is local plain text, not a password vault.

Data lives at `~/Library/Application Support/Snippet/`:

- `snippets.json`: permanent snippets; existing v1 data migrates without losing entries.
- `history.json`: recent copied text.
- `calculations.json`: previous calculations.

Files use atomic writes and owner-only permissions. Unreadable files are left untouched and surfaced in the launcher. Back up the snippets file to preserve your library. Settings are stored in macOS UserDefaults. Direct paste replaces the clipboard with the selected text.

## Development

```sh
swift build
./scripts/test.sh
./scripts/build.sh
```

The test runner works with Command Line Tools alone. It checks persistence, Unicode, search, legacy migration, damaged-data protection, history deduplication/expiry, keyword matching, calculator precedence and errors, calculation persistence, theme persistence, tab navigation, configurable shortcut contexts/conflicts/persistence, and result cycling. `Services.swift` owns clipboard polling and the accessibility-gated event tap. `History.swift` contains history persistence and the pure keyword matcher.

The local app is ad-hoc signed, not notarized for distribution. **Quit Snippet before rebuilding.** The build script refuses to overwrite a running app and assembles the new bundle in a staging directory before replacing the old one. This avoids macOS rejecting a running process whose on-disk signature has changed.

If Accessibility is enabled but Snippet reports otherwise, quit and reopen the app first. If access is still denied after a code change, remove its old entry from Accessibility and add the current `dist/Snippet.app` again. Ad-hoc builds have a build-specific code identity, so a checked entry can refer to an older build. This cannot be repaired by treating an OS denial as approval.

If you have a persistent code-signing identity installed, set `SNIPPET_SIGNING_IDENTITY` when building to use it instead of ad-hoc signing. No certificate trust or macOS privacy permissions are changed by the build script. While open, Snippet activates and owns its keyboard shortcuts, then restores the previous app on dismissal. Global shortcut conflicts are reported, and the menu bar remains available. To launch at login, add the app in macOS Login Items.

### Storage and cleanup

Open Settings → Storage to choose **Forever** or an age limit, and **Unlimited** or an ordinary-clip count limit. Defaults are Forever and Unlimited, including when upgrading from earlier releases. Save cleanup rules to apply them; if existing clips would be removed, a confirmation shows the count. Favorites and snippets are excluded. Previously expired clips cannot be recovered by changing the rules.

Data is stored on your Mac, not in a hosted account or iCloud. No cloud subscription or account is required. Calculator history still keeps its most recent 200 calculations; clipboard cleanup settings only apply to ordinary clips.

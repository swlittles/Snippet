# Privacy

Snippet stores your library locally. It has no accounts, cloud sync, analytics, advertising, or telemetry. The Sparkle updater contacts GitHub over HTTPS when you check for updates or enable optional daily checks. GitHub and its download hosts receive ordinary connection information such as your IP address and HTTP client metadata. Clipboard contents, snippets, calculations, and shortcuts are never included in update requests. Sparkle system profiling is disabled. Development builds do not start the updater.

## Stored information

When you enable history, Snippet stores copied plain text, the source app's display name, a timestamp, an ID, and favorite status. It stores snippets you create and calculator expressions/results. Preferences include themes, shortcuts, and opt-in settings.

Files live in `~/Library/Application Support/Snippet/`. They are JSON, use owner-only file permissions, and are not encrypted by Snippet. macOS FileVault and your own backups have separate policies. Do not use the app to store passwords or other secrets that require a dedicated vault.

Local development builds (Snippet Dev) use a separate `~/Library/Application Support/Snippet Dev/` folder and `local.snippet.dev` preferences domain. No production library or settings are copied automatically.

## Retention and deletion

- Ordinary clips: seven days, at most 500 entries.
- Favorite clips: no automatic expiry or capacity eviction.
- Saved snippets: until explicitly deleted.
- Calculations: latest 200 entries, or until you clear them.
- Clear clipboard history preserves favorite clips and snippets. Individual clip removal can delete a favorite.
- Turning capture off stops new collection; it does not erase existing data. Ordinary retention still applies.

## Permissions

Accessibility is used for simulated paste and optional keyword expansion. Expansion observes keystrokes in memory to match enabled keywords; it does not keep a keystroke log. Secure input and known password apps are excluded. Clipboard capture and expansion both default to off.

The app filters known password apps and clipboard types marked concealed, transient, or auto-generated. These are best-effort filters, not detection of all confidential content. Any ordinary copied text from an unrecognized app may be captured when history is on.

Pasting replaces the system clipboard with the selected text. Other clipboard managers may observe that value. Snippet doesn't control other apps' data handling.

## Reports

Do not attach your clipboard database, real snippet library, or private screenshots to public issues. Use synthetic examples. See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

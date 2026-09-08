# Privacy

Snippet stores your library locally. It has no accounts, analytics, advertising, or telemetry. Optional folder-based sync shares library data only after you select a folder; clipboard sharing is a separate opt-in. Quicklinks open chosen destinations in your browser or Finder. The Sparkle updater contacts GitHub over HTTPS when you check for updates or enable optional daily checks. GitHub and its download hosts receive ordinary connection information such as your IP address and HTTP client metadata. Clipboard contents, snippets, calculations, and shortcuts are never included in update requests. Sparkle system profiling is disabled. Development builds do not start the updater.

## Stored information

When you enable history, Snippet stores copied text and PNG images, locally recognized image text, the source app's display name, a timestamp, an ID, and favorite status. It stores snippets you create and calculator expressions/results. Preferences include themes, shortcuts, and opt-in settings.

Files live in `~/Library/Application Support/Snippet/`. They are JSON, use owner-only file permissions, and are not encrypted by Snippet. macOS FileVault and your own backups have separate policies. Do not use the app to store passwords or other secrets that require a dedicated vault.

Local development builds (Snippet Dev) use a separate `~/Library/Application Support/Snippet Dev/` folder and `local.snippet.dev` preferences domain. No production library or settings are copied automatically.

## Retention and deletion

- Ordinary clips: kept indefinitely by default. Optional age and count limits can be set in Storage settings; applying a rule confirms any immediate deletions.
- Favorite clips: no automatic expiry or capacity eviction.
- Saved snippets: until explicitly deleted.
- Calculations: kept until you clear them.
- Clear clipboard history preserves favorite clips and snippets. Individual clip removal can delete a favorite.
- Turning capture off stops new collection; it does not erase existing data. Any cleanup rules you choose still apply.

## Permissions

Accessibility is used for simulated paste and optional keyword expansion. Expansion observes keystrokes in memory to match enabled keywords; it does not keep a keystroke log. Secure input and known password apps are excluded. Clipboard capture and expansion both default to off.

The app filters known password apps and clipboard types marked concealed, transient, or auto-generated. These are best-effort filters, not detection of all confidential content. Any ordinary copied text from an unrecognized app may be captured when history is on.

Pasting replaces the system clipboard with the selected text, image or formatted content. Other clipboard managers may observe that value. Snippet doesn't control other apps' data handling.

## Workspace, OCR and optional sync

Apple Vision recognizes image text locally. Text/developer transformations and Markdown rendering run locally. Markdown does not load remote images or execute HTML. Clicking a web link opens the destination in your browser.

`workspace.json` stores collections, quicklinks and queue snapshots. `Images/` stores image attachments. Queued images are separate snapshots; removing a history image does not delete its queue copy. Import/export is explicit, and packs contain snippet text, quicklinks and optionally a theme. Packs do not include clipboard history or signing credentials.

Optional sync writes readable `Snippet.sync.json` into the folder you choose. The folder's service (for example iCloud Drive) transports it. Snippet adds no encryption. Snippets, collections, quicklinks and themes are included. Enabling clipboard sharing also includes clipboard text/images and metadata. Local `sync-journal.json` tracks revisions and deletion tombstones. Deletions sync; tombstones contain no deleted payload. Existing backups or offline copies have their own retention behavior.

Turning off clipboard sharing or disconnecting does not erase already shared copies. Disconnect every participating Mac before removing the shared folder if you want to erase the shared library. See [the sync guide](docs/WORKSPACE.md#optional-icloud-drive-sync) for merge behavior and deletion details.

## Reports

Do not attach your clipboard database, real snippet library, or private screenshots to public issues. Use synthetic examples. See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

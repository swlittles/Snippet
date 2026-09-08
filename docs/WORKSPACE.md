# Workspace and Markdown

Open **Workspace** using the grid button beside Settings or **Cmd–K**. All three new shortcuts can be changed in Settings → Shortcuts.

| Default | Action |
| --- | --- |
| Cmd–K | Open Workspace |
| Cmd–Shift–B | Add the selected clip or snippet to the queue |
| Cmd–Shift–V | Paste the next queued item while the launcher is open |

## Smart snippets

Create a snippet containing placeholders:

```text
Hi {{name}},

Here is the update for {{project}} on {{date}}.
{{cursor}}
Thanks!
```

Choosing it prompts for `name` and `project`, with a preview before pasting. Repeated field names share one value. Replacement values are literal: they cannot introduce another template expression.

Built-ins:

| Placeholder | Value |
| --- | --- |
| `{{date}}` | Local date, `yyyy-MM-dd` |
| `{{time}}` | Local time, `HH:mm` |
| `{{date:MMMM d, yyyy}}` | Date formatted with Foundation date patterns |
| `{{clipboard}}` | Text from the clipboard when the snippet is selected |
| `{{uuid}}` | A newly generated UUID |
| `{{cursor}}` | Cursor position after paste; the first marker is used |

Cursor placement uses left-arrow events after pasting. It works with ordinary text fields; editors with custom cursor behavior or slow paste processing may behave differently. Copy-only places text on the clipboard without moving a cursor.

Automatic keyword expansion supports built-ins. Snippets with fill-in fields must be used from the launcher; the editor prevents enabling automatic expansion for them. Imported snippets start with expansion disabled.

## Markdown

Choose **Markdown** in the snippet editor and turn on **Preview Markdown**. The launcher’s eye button also previews Markdown in clips or snippets.

The native preview supports headings, emphasis, bold, strikethrough, inline code, fenced code blocks, links, basic lists, task checkboxes, quotes, and simple pipe tables. Code stays literal. This is a practical Markdown renderer, not a complete CommonMark/GFM engine: nested block structures, escaped table pipes, and embedded HTML layouts are not supported.

The regular Paste and Copy actions use source text. Right-click a result → **Paste as formatted Markdown** supplies RTF plus a plain-text fallback. The destination chooses the format it supports. Table formatting in rich paste uses tab-separated text.

Raw HTML is not executed. Remote images are not loaded. Links only open after a click; preview links are restricted to HTTP, HTTPS, and mailto.

## Text and developer tools

Right-click a result → **Transform / developer tools…**, or open Workspace → Tools. Input initially comes from the selected result. **Read clipboard** explicitly reads the current clipboard. Run an action, inspect/edit the result, then copy, paste, save it as a snippet, or use it as the next input.

- Format/minify JSON, including scalar JSON values.
- Uppercase, lowercase, title case, trim whitespace, deduplicate or sort lines.
- Remove common URL tracking parameters while preserving other parameters and fragments.
- Base64 UTF-8 encoding/decoding and URL percent encoding/decoding.
- JSON string escaping/unescaping.
- SHA-256 hashes and UUID generation.
- Unix timestamps in seconds ↔ dates/current time.
- JWT payload inspection. **This decodes the payload; it does not verify the signature or establish trust.**

All transformations run locally. They do not execute shell commands, JavaScript, or imported code.

## Images and recognized text

With clipboard history enabled, copied PNG/TIFF images are stored as PNG attachments. The launcher shows thumbnails; the preview shows the image and recognized text. Apple Vision performs text recognition locally on a background queue. Recognition quality depends on image clarity and the OS's supported languages.

Return pastes the image. **Copy recognized text** copies its OCR text instead. Edit changes the recognized/searchable text, not the image pixels. Image favorites survive retention, and removed clips' image files are cleaned up. A queued image owns a separate snapshot so history cleanup cannot remove it from the queue.

## Paste queue

Add selected results with Cmd–Shift–B or the context menu. Open Workspace → Queue to reorder or remove entries. **Paste next** sends the first entry to the previous app, then removes it after dispatching the paste command. If permission or activation fails, the entry stays queued. Snippet cannot confirm whether the destination accepted the paste; the selected content remains on the system clipboard for a manual retry.

Templates in individually pasted queue entries expand at paste time. For batch text, choose newlines, blank lines, spaces, tabs, or commas, then copy/paste combined text. Combining preserves raw snippet text and uses recognized text for image entries. It leaves the queue intact.

## Collections and quicklinks

Create collections in Workspace, or type a collection name in the snippet editor. The folder menu in the launcher filters snippets. **Ungroup** removes the collection assignment while keeping its snippets.

Quicklinks accept HTTP(S) URLs or absolute folder paths. Include `{query}` in a search URL; entered search terms are percent-encoded before substitution. Examples:

```text
https://github.com/search?q={query}
https://www.google.com/search?q={query}
~/Documents
```

Links open in your default browser; folders open in Finder. Quicklinks do not accept executable URL schemes or shell commands.

## Import and export

Workspace → Import / export accepts:

- Snippet version-1 `.json` packs.
- An older `snippets.json` library.
- UTF-8 `.md` / `.markdown` files.
- Alfred `.alfredsnippets` collections and individual Alfred snippet JSON.

Alfred archives are read without extracting files or running their contents. Imported text is preserved; Alfred-specific dynamic placeholders are not translated into Snippet templates. The archive reader rejects individual entries above 32 MiB.

Review the import count and titles before importing. Imports create new IDs, keep existing entries, disable automatic expansion, and clear conflicting keywords. Applying an included theme is optional.

Export all snippets or one collection. A full pack also includes quicklinks and the current theme. Clipboard history, queue, hotkeys, updater credentials and signing material are excluded. Snippet content and quicklink destinations can themselves be sensitive; inspect the pack before sharing it publicly.

## Optional iCloud Drive sync

Choose **Workspace → Sync** (also linked from Settings → Storage), then select a dedicated folder inside iCloud Drive. Select that same folder on each Mac. No Snippet account, server, or CloudKit container is required; the app exchanges a file through your chosen folder. Any writable folder can be used, but only iCloud Drive or another separately configured file service transports it between computers.

Saved snippets, collection names, quicklinks and the theme sync every 30 seconds while the app runs, or with **Sync now**. Each record has a revision timestamp and writer ID. Different items merge; the latest edit to the same item wins. Deletions are recorded as tombstones so an offline Mac does not resurrect them. Collection names and the theme each merge as one record. Keep Mac clocks accurate. iCloud delivery may take longer than the app's polling interval.

**Clipboard sharing is a separate opt-in on each Mac.** It includes text, image attachments, source names, dates and favorite status. Turning it off stops transfers from that Mac; it does not remove previously shared data. With clipboard sharing on, explicit deletions and retention cleanup propagate to other participating Macs. Queue, hotkeys, capture preferences and retention settings are local.

The shared `Snippet.sync.json` is readable JSON and includes tombstones. Snippet does not add encryption. Use a private folder. Disconnect stops sync and keeps both local and shared files. To erase the shared copy, first disconnect every Mac, then delete the dedicated shared folder using Finder. Back up important libraries with Export before making large changes.

Tests cover two clients using a coordinated local folder, including edits, deletions, opt-in and corruption. Real iCloud transport between separate Macs requires verification on your own devices; no account or folder is enabled automatically.

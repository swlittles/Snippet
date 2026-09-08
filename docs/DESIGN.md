# What Snippet solves

Snippet reduces the small interruptions involved in moving and reusing text on a Mac.

## Recover an earlier copy

A normal clipboard replaces its previous value. Snippet watches for new plain-text copies when capture is enabled and stores a searchable local history. Search can match both the text and the source app's name. Re-copying text refreshes the same entry rather than filling the list with duplicates.

## Keep the useful parts

Ordinary clipboard history is temporary: seven days and 500 clips. A star explicitly says “keep this.” Favorites are excluded from both age and capacity cleanup, sort first, and have their own filter. Re-copying a favorite retains its ID and favorite status. Clear history preserves favorites, while an explicit individual removal can delete them. Unfavoriting returns an entry to ordinary retention based on its original or last-copy date.

## Reuse deliberate, maintained text

Snippets add a name, tags, and an optional expansion keyword to text you expect to use repeatedly. Clips can be corrected in place; snippets can be edited as reusable templates. Saving a clip as a snippet makes a separate permanent entry. Editing doesn't retroactively change text already pasted elsewhere.

## Stay in the current task

A native hotkey panel searches, selects, and pastes back into the previous app. The panel becomes active to own its shortcuts. Tab cycles results; explicit section shortcuts switch tools. All key bindings are configurable to avoid conflicts with a person's workflow.

## Calculate without another workspace

The calculator uses a small expression parser with numeric functions and persistent history. It evaluates numbers, not arbitrary Swift, shell commands, or scripts. Floating-point results are convenient for everyday calculations, not arbitrary-precision accounting.

## Deliberate boundaries

- Local only: no login, remote sync, analytics, or server.
- Plain text only: no screenshot, image, file, or rich-text history.
- Capture and expansion are opt-in.
- OS permission checks remain authoritative.
- No general app launcher, plugin engine, command execution, or workflow automation.
- Sparkle handles signed updates from GitHub Releases. Optional daily checks are quiet; users choose when to install. Development builds never start the updater.

These limits keep the app small and make its behavior easier to inspect. They also mean it is not a secret store, a full Alfred replacement, or a cross-device clipboard.

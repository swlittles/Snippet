# Contributing

Bug reports and focused pull requests are welcome. For behavior changes, describe the user problem and expected keyboard flow first.

## Local development

Use macOS 13+ with Swift 5.9+ (Xcode or Command Line Tools).

```sh
swift build
bash scripts/test.sh
bash scripts/build.sh
```

Quit Snippet before rebuilding its installed bundle. Use `SNIPPET_OUTPUT_DIR="$PWD/release-build"` to package separately without replacing the running local app. Build artifacts and signing credentials must remain untracked.

## Before a pull request

- Run the tests and a release build.
- Add regression coverage for changes to persistence, retention, parsing, or key handling.
- Use temporary test storage, never the user's clipboard history or snippet files.
- Check keyboard-only use, pointing-hand cursors, focus restoration, and the affected theme states.
- Keep existing data readable. Do not silently overwrite unreadable files.
- Explain what changed, why, and how it was verified. Call out hardware/OS testing you couldn't perform.
- Update the user guide and changelog when behavior changes.

## Scope

Keep contributions native, local-first, and focused on text reuse and calculations. Discuss dependencies, networking, data-format changes, and new permission requirements before implementation. Never include credentials, personal clipboard text, or private signing material in a commit or issue.

## Releases

Maintainers follow [docs/RELEASING.md](docs/RELEASING.md). Pull-request CI never receives signing secrets. Contributions are licensed under the repository's MIT license.

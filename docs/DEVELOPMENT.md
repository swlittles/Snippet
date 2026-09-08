# Development and production on one Mac

| | Production | Development |
| --- | --- | --- |
| App | Snippet | Snippet Dev |
| Bundle ID / preferences domain | `local.snippet.app` | `local.snippet.dev` |
| Data folder under Application Support | `Snippet/` | `Snippet Dev/` |
| Default hotkey | Option–Space | Control–Option–Space |
| Icon and menu bar | Standard | DEV badge and Dev menu label |
| Accessibility permission | Snippet | Snippet Dev, separately granted |

Production retains its existing identity and data. Development starts with an empty library and default preferences; it does not copy production data automatically. You can run one at a time or both. Both can observe your system clipboard if you opt into capture in both, but their saved libraries and settings are separate.

## Everyday commands

```sh
# Build the local development app (default)
bash scripts/build.sh
open "dist/Snippet Dev.app"

# Run directly from SwiftPM: also uses development data/settings
swift run

# Build a production-identity bundle explicitly
SNIPPET_BUILD_VARIANT=production bash scripts/build.sh
```

Both variants use the same source/binary logic. Runtime identity comes from the bundle identifier, and an unbundled executable defaults to development. Release packaging always selects production explicitly, even if your shell's build-variant variable is set to development. Unknown build variants are rejected.

The production-identity command is for packaging checks; it shares the released app's data and preferences and is ad-hoc signed unless you supply a signing identity. Prefer the signed release in Applications for normal use. `scripts/release.sh signed` is the documented notarized production pipeline.

## Permissions

Grant Accessibility to **Snippet Dev** separately if you want to test direct paste/expansion. Development is ad-hoc signed by default, so rebuilding may require refreshing its entry. This does not change production's identity or its permission entry. History capture and keyword expansion start off in the new development profile.

## Existing local builds

Older local `dist/Snippet.app` builds used the production identity. They and the released production app share `~/Library/Application Support/Snippet/`. That library remains the production library. The new default build writes `dist/Snippet Dev.app` and leaves the old bundle/data untouched. Use Snippet Dev for future development; use the released app in Applications for production.

## Test data

Use synthetic clips/snippets for development. If you deliberately want a copy of a library, quit both apps and back up the destination before copying the relevant JSON files between their Application Support folders. No automatic sync, import, or migration runs between profiles. Preferences remain separate.

Unit tests use temporary data. CI builds and checks both development and production bundle identities, including universal architectures. No signing secrets are exposed to pull-request CI.

# Release engineering

## Distribution contract

Stable releases are universal macOS 13+ apps for arm64 and x86_64. They use a **Developer ID Application** identity for team `KQFYGC7SWB`, hardened runtime, and a secure timestamp. The app is notarized and stapled before creating the ZIP and DMG; the DMG is also signed, notarized, and stapled. A failed signature, team check, notarization, or Gatekeeper assessment aborts publication.

A Team ID is a public account identifier, not a signing credential. An Apple Development, Apple Distribution, or Developer ID Installer certificate is not a substitute for Developer ID Application when signing this app.

## One-time Apple setup

1. Sign into [Apple Developer](https://developer.apple.com/account/resources/certificates/list) as the account holder or a role allowed to create Developer ID certificates.
2. Generate a local RSA 2048-bit private key and certificate signing request (CSR), or use Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority. Keep the private key outside the repository.
3. Create a **Developer ID Application** certificate with the **G2 Sub-CA**, upload the CSR, and download the issued certificate. Do not revoke an existing production certificate merely to add another app.
4. Import the certificate alongside its matching private key. Verify `security find-identity -v -p codesigning` lists a valid Developer ID Application identity for the expected team.
5. Export that identity (certificate plus private key) as a password-protected `.p12`. Store a secure backup. A `.cer` file alone has no private key and cannot sign.
6. Configure notarization authentication. The automated workflow supports an App Store Connect team API key (`.p8`, Key ID, Issuer ID) or an Apple Account with a dedicated app-specific password. Apple may require account-holder actions/2FA. Do not post credentials in chat, issues, source, or logs.

Apple's current [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow guide](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) are the authority for account roles and credential setup.

## GitHub Actions secrets

Configure these under repository **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 encoding of the exported Developer ID Application identity |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that P12 |
| `NOTARY_API_KEY_P8` | Contents of the App Store Connect team API private key file |
| `NOTARY_KEY_ID` | API Key ID |
| `NOTARY_ISSUER_ID` | Team API Issuer ID |

Instead of the three API-key secrets, set `NOTARY_APPLE_ID` and `NOTARY_APP_PASSWORD` for an Apple Account/app-specific password. Prefer a dedicated notarization credential. The Team ID is configured in the workflow; it is not secret. The script validates the issued signing identity's team after building.

Use the GitHub secrets UI or pipe files to `gh secret set`; never paste values into committed workflow YAML. Secrets let the release workflow act under your signing identity: restrict repository write access and review changes to release scripts carefully. PR CI has read-only repository permissions and no release credentials. A protected release environment can add required reviewers if your team needs that policy.

The release job imports the certificate into an ephemeral runner Keychain, removes temporary key files, and deletes the Keychain at the end. A local build does not change your Keychain trust or grant Accessibility access.

## Publish a version

1. Update `VERSION`, `BUILD_NUMBER` (monotonically increasing), `CHANGELOG.md`, and `docs/RELEASE_NOTES.md`. Update initial-distribution notices once the first signed release is ready.
2. Run `bash scripts/test.sh` and build the universal app. Verify the UI with synthetic data, particularly paste, keyword expansion, favorites, and editor save/cancel.
3. Commit and push to `main`, then wait for CI to pass.
4. Create an annotated tag exactly matching `v$(cat VERSION)` and push it:

   ```sh
   git tag -a "v$(cat VERSION)" -m "Snippet $(cat VERSION)"
   git push origin "v$(cat VERSION)"
   ```

5. The Release workflow tests, signs, notarizes, packages, preserves CI artifacts, and publishes a GitHub Release with DMG, ZIP, and SHA-256 checksums. It cannot silently downgrade to an unsigned stable build.
6. Verify downloads from the actual release, including a fresh Gatekeeper-enabled Mac. Test both architectures and oldest supported macOS before claiming that compatibility matrix was runtime-validated.

If credentials are missing or notarization fails, fix setup and rerun the workflow. Manual dispatch accepts an existing version tag. An existing draft for that tag is completed after verification. If the release is already published, publication fails rather than overwriting public assets; inspect it deliberately before retrying. Don't move tags used by published releases.

Release packaging explicitly selects `SNIPPET_BUILD_VARIANT=production`, regardless of the local default. Plain `scripts/build.sh` makes Snippet Dev; both variants are built and verified in CI.

## Local signed release

Store a profile in Keychain with `xcrun notarytool store-credentials snippet-notary` (interactive prompts prevent passwords entering shell history). Then:

```sh
SNIPPET_SIGNING_IDENTITY='Developer ID Application: Your Name (KQFYGC7SWB)' \
NOTARY_PROFILE=snippet-notary \
bash scripts/release.sh signed
```

The default signed mode requires credentials before building. Output goes to `release-build/` and `release-assets/`, leaving `dist/Snippet.app` untouched.

## Developer preview

`bash scripts/release.sh preview` exercises universal packaging without Apple credentials. Its filenames and DMG notice explicitly identify it as a preview. It is ad-hoc signed, not notarized, and is unsuitable as a normal Gatekeeper-approved release. The automatic stable workflow never uses this mode. Any public preview must be marked prerelease and clearly state the limitation; do not instruct users to disable Gatekeeper.

## Current limitations

There is no App Store distribution or Intel/macOS 13 runtime test farm. CI cross-compiles both architectures and runs the logic suite on its macOS runner. A build passing CI is not proof of Accessibility/paste behavior in every third-party app.

## Installer design

`scripts/package-dmg.sh` uses [dmgbuild](https://dmgbuild.readthedocs.io/en/latest/settings.html) to write Finder metadata without UI automation. Python 3.10+ is required; exact packaging dependencies are installed into `.build/dmg-tools` from `scripts/dmg-requirements.txt`. AppKit generates the 1x/2x background, combined into a Retina TIFF. Edit `scripts/make-dmg-background.swift` and `scripts/dmg-settings.py` together when changing dimensions or icon positions.

The disk opens at 680 × 440 points with Snippet on the left and an Applications symlink on the right. Only these two items are visible; installation documentation stays on GitHub. Preview builds show a notice in the artwork. Signing and notarization still happen after packaging.

To preview layout independently of rebuilding the app:

```sh
bash scripts/package-dmg.sh "$PWD/release-build/Snippet.app" "$PWD/release-build/Installer-preview.dmg" preview
```

Open the resulting DMG in Finder and check typography, icon alignment, and the Applications destination before tagging a release.

## Sparkle update distribution

Sparkle 2.9.6 is pinned through SwiftPM and its binary checksum. `build.sh` embeds and signs the framework and its helpers before signing the app. Production starts Sparkle; development never starts it. Automatic checks default to off; installation requires user action.

The stable feed URL is `https://github.com/swlittles/Snippet/releases/latest/download/appcast.xml`. Each release includes its own signed feed pointing to that version’s immutable notarized DMG. GitHub’s latest-release redirect advances the feed only when the release is published. Never mark a legacy release lacking an appcast as latest.

Configure `SPARKLE_ED_PRIVATE_KEY` as an Actions secret (the base64 seed exported by Sparkle’s `generate_keys`). Keep a secure backup outside the repo. The corresponding public key is embedded as `SUPublicEDKey`; do not replace or regenerate it during ordinary releases. `scripts/update-feed.sh` generates the signed feed after notarization, embeds release notes, and checks version and asset URLs. Feed and download signatures are required, with archive verification before extraction. Do not edit a signed feed after generation.

Versions before 3.3.0 need one manual upgrade. To exercise a complete update, retain an older updater-enabled app in an isolated test location, publish a newer signed build, then use Check for Updates and verify installation and relaunch. Also check no-update, offline failure, disabled development behavior, and preference persistence. Never lower version numbers in published artifacts for testing.

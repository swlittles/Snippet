A native macOS clipboard, snippet, and calculator launcher. Requires macOS 13 or newer; one universal app supports Apple Silicon and Intel.

### What’s new in 3.6.0

- **Vault.** Search your Bitwarden vault from the launcher with Command–5 and paste passwords, usernames, notes, card details and verification codes. It works with Bitwarden.com, Bitwarden.eu, self-hosted Bitwarden and Vaultwarden. Turn it on in Settings → Vault.
- **Two-step login.** Sign in with authenticator, email or YubiKey codes and remember this Mac, or use a personal API key if your account uses Duo or a security key.
- **Private by design.** Your master password is never saved or sent. The vault is decrypted on this Mac, and decrypted items stay in memory only while it's unlocked. It locks after inactivity and when your Mac sleeps or its screen locks.
- **Safer clipboard.** Copied vault values are marked confidential, so clipboard history skips them, and they're cleared after 30 seconds by default.
- Command–Shift–C copies a username, Command–Shift–T copies a verification code and Command–L locks the vault. Items that require your master password again ask for it before secrets are used.

Vault items are read-only in this release. Vault is off by default, and Snippet connects only to the server you choose. See the Vault guide in the repository for details.

From 3.3.0 or later, choose **Check for Updates…** to install this release. Versions 3.2.x require one manual upgrade to gain the updater.

### Install

Download the DMG, open it, and drag Snippet into Applications. The ZIP is an alternative app download. Source archives are for developers.

These stable assets are Developer ID signed and Apple notarized for team `KQFYGC7SWB`. The app and DMG have stapled notarization tickets. SHA-256 checksums accompany both downloads.

Enable clipboard capture in Settings if wanted. Direct paste and optional keyword expansion require macOS Accessibility permission. When upgrading from an ad-hoc development build, you may need to refresh Snippet's Accessibility entry once.

Quit the old app before replacing it. Your local library is stored outside the app bundle. After this installation, use Check for Updates for future releases.

See the repository's installation guide, privacy document, and changelog for details. Intel/macOS 13 cross-compilation is checked; the full hardware/OS runtime matrix has not yet been tested.

# Vault

Snippet can search a Bitwarden vault from the launcher and paste its logins, cards, notes and verification codes. It works with Bitwarden’s US and EU cloud, a self-hosted Bitwarden server, and Vaultwarden. Vault access is off by default, and vault items are read-only in this version.

## Set up

1. Open **Settings → Vault** and turn on **Show Vault in the launcher**.
2. Choose **Bitwarden.com**, **Bitwarden.eu** or **Self-hosted**. For a self-hosted server, enter the address you use for its web vault, such as `https://vault.example.com`. HTTPS is required. Plain HTTP is accepted only for a server on this Mac.
3. Enter your email and master password, then click **Sign in**.
4. If your account uses two-step login, enter the code from your authenticator app, email or YubiKey. **Remember this Mac** skips the code next time. Bitwarden’s cloud may email a new-device code instead; enter it to finish.

Snippet accepts typed two-step codes only. If your account uses Duo or a security key (FIDO2/WebAuthn), turn on **Sign in with a personal API key** and enter the `client_id` and `client_secret` from your web vault (**Settings → Security → Keys → View API key**). Your master password is still needed, because it decrypts the vault on this Mac.

Your server address, email and preferences are saved only in Snippet’s settings on this Mac.

## Use

Press **Command–5**, or click **Vault** beside the other sections. When the vault is locked, type your master password in the search field and press **Return**.

- **Return** pastes the item’s main value into the app you were using: a login’s password (or its username if there’s no password), a note’s text, a card number, an identity’s email or an SSH public key.
- **Command–Return** copies the value instead.
- **Command–Shift–C** copies the username. **Command–Shift–T** copies the current verification code.
- **Command–P** shows every field, with buttons to reveal secrets and copy each value. Copying from the details keeps the launcher open.
- Right-click a result to copy any field or open its website.
- **Command–L** locks the vault.

Search matches the item name, username, website, folder and organization. The star filters to your Bitwarden favorites. Items in the trash don’t appear.

Items with **Master password re-prompt** turned on ask for your master password before any secret is pasted, copied or revealed.

## Locking and the clipboard

The vault locks after the delay you choose in **Settings → Vault** (15 minutes by default; each paste or copy restarts it), and whenever your Mac sleeps, its screen locks or you switch users. Locking removes every decrypted item from memory.

Values copied or pasted from the vault are marked as confidential, so Snippet’s clipboard history and other clipboard managers that respect the marker skip them. The clipboard is cleared after 30 seconds by default, unless you copy something else first. Choose a different delay, or **Never**, in **Settings → Vault**.

## Syncing and signing out

Snippet downloads your vault when you sign in, after you unlock it, and when you open Vault more than five minutes after the last sync. **Settings → Vault → Sync now** downloads it immediately. The saved copy lets you unlock and search while offline.

If your master password, KDF settings or account encryption key changes on the server, Snippet locks the vault after the next sync. Unlock it with your current master password.

**Sign out** deletes Snippet’s saved copy of your encrypted vault and its sign-in tokens from this Mac. It doesn’t change anything on the server.

## Security

- Your master password is never saved or sent. Snippet derives your master key on this Mac (PBKDF2-SHA256 or Argon2id, using your account’s settings) and sends the server only the derived authentication hash, as Bitwarden’s own apps do.
- Every item is decrypted on this Mac using AES-256-CBC with HMAC-SHA256 authentication. Organization keys are unwrapped with your RSA private key, and per-item keys are supported. Data that fails authentication isn’t shown, and Snippet reports how many items it couldn’t open.
- `vault-cache.json` in Snippet’s data folder holds the encrypted sync response, your KDF settings and your account details. It uses owner-only permissions, and nothing in it opens the vault without your master password. Organization and folder names follow Bitwarden’s own encryption: folder names are encrypted, organization names aren’t.
- The refresh token, personal API key secret and remembered two-step token are stored in the macOS Keychain, on this Mac only, and are available only while it’s unlocked.
- Decrypted items exist only in memory while the vault is unlocked. Swift can’t guarantee that freed memory is wiped immediately, so treat an unlocked vault the way you treat an unlocked Bitwarden app.
- Network requests use an ephemeral session, with no cookies, credential storage or response cache.

Snippet is an independent client and isn’t affiliated with or endorsed by Bitwarden, Inc. or the Vaultwarden project.

## Limits

- Vault items can’t yet be created, edited, deleted or favorited from Snippet. Use a Bitwarden app for changes; Snippet picks them up on its next sync.
- Duo and security-key two-step login require the personal API key sign-in.
- Accounts that unlock without a master password (SSO with trusted devices or Key Connector) aren’t supported.
- Attachments, Sends and passkeys aren’t shown. Linked custom fields are omitted.
- Snippet doesn’t fill in web forms automatically. Paste the username and password separately.

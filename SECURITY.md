# Security policy

Only the latest stable release receives security fixes. Until a signed stable release is available, development builds are provided for evaluation, not as a hardened secret store.

Please report vulnerabilities privately through [GitHub's security advisory form](https://github.com/swlittles/Snippet/security/advisories/new). Do not post exploit details or clipboard contents in a public issue. Include the version, macOS version, reproduction steps using synthetic data, and impact. No guaranteed response SLA is offered.

Clipboard history may contain sensitive text. Filters for known password apps and concealed clipboard types are best effort. Local JSON isn't encrypted by Snippet. Accessibility access enables simulated input; grant it only to a build you trust.

The optional Vault is an independent Bitwarden-compatible client. Its key derivation, decryption and token handling are security-sensitive code; changes need tests against synthetic data. The master password is never stored or sent, decrypted items are held in memory only while unlocked, and tokens live in the Keychain. Report vault issues privately as described above, and never include vault contents, server addresses or account emails in a public report.

Signing certificates, private keys, and notarization credentials must never enter Git history. Release credentials belong in a local Keychain or GitHub Actions secrets. Release workflows are security-sensitive code and should be reviewed accordingly.

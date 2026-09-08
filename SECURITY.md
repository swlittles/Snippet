# Security policy

Only the latest stable release receives security fixes. Until a signed stable release is available, development builds are provided for evaluation, not as a hardened secret store.

Please report vulnerabilities privately through [GitHub's security advisory form](https://github.com/swlittles/Snippet/security/advisories/new). Do not post exploit details or clipboard contents in a public issue. Include the version, macOS version, reproduction steps using synthetic data, and impact. No guaranteed response SLA is offered.

Clipboard history may contain sensitive text. Filters for known password apps and concealed clipboard types are best effort. Local JSON isn't encrypted by Snippet. Accessibility access enables simulated input; grant it only to a build you trust.

Signing certificates, private keys, and notarization credentials must never enter Git history. Release credentials belong in a local Keychain or GitHub Actions secrets. Release workflows are security-sensitive code and should be reviewed accordingly.

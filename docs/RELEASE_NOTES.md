A native macOS clipboard, snippet, and calculator launcher. Requires macOS 13 or newer; one universal app supports Apple Silicon and Intel.

### What’s new in 3.8.0

- **Activity: see and stop what your Mac is doing.** Press Command–6 for CPU, memory, disk and network at a glance, each with a two-minute history. Below them is a table of every process with % CPU, memory, power, disk, threads and PID. Sort by any column, filter by name, PID or user, and switch between Apps (each app with its helpers added together), My processes and All processes.
- **Quit stuck apps and processes from the keyboard.** Command–Delete quits the selected process after you confirm, and Option–Command–Delete force quits. Apps get the chance to save first. Processes owned by root ask for an administrator's password. Return shows details such as path, parent, start time and totals.
- **The app icon matches your theme everywhere.** Finder, Launchpad, Spotlight and System Settings now show Snippet's icon in your theme's colors.

### Also in 3.7

- **The update window matches your theme.** Check for Updates and its alerts use your theme’s colors.
- **Fill sign-in forms from the Vault.** Click into a username field, open the Vault and press Return: Snippet pastes the username, presses Tab and pastes the password.

From 3.3.0 or later, choose **Check for Updates…** to install this release. Versions 3.2.x require one manual upgrade to gain the updater.

### Install

Download the DMG, open it, and drag Snippet into Applications. The ZIP is an alternative app download. Source archives are for developers.

These stable assets are Developer ID signed and Apple notarized for team `KQFYGC7SWB`. The app and DMG have stapled notarization tickets. SHA-256 checksums accompany both downloads.

Enable clipboard capture in Settings if wanted. Direct paste and optional keyword expansion require macOS Accessibility permission. When upgrading from an ad-hoc development build, you may need to refresh Snippet's Accessibility entry once.

Quit the old app before replacing it. Your local library is stored outside the app bundle. After this installation, use Check for Updates for future releases.

See the repository's installation guide, privacy document, and changelog for details. Intel/macOS 13 cross-compilation is checked; the full hardware/OS runtime matrix has not yet been tested.

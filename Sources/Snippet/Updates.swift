import AppKit
import Combine
import Sparkle
import SwiftUI

/// Production updates only; development builds never start or contact the feed.
final class UpdateService: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var availableVersion: String?
    private var observations: [NSKeyValueObservation] = []
    private var controller: SPUStandardUpdaterController?
    var beforeUserCheck: (() -> Void)?
    var availabilityChanged: (() -> Void)?
    /// The theme Sparkle's windows are styled with.
    var palette = ThemePalette.presets[0] { didSet { styled.removeAllObjects() } }
    private var showingAlert = false
    private let styled = NSHashTable<NSWindow>.weakObjects()
    private var windowObserver: NSObjectProtocol?
    let enabled = !AppEnvironment.current.isDevelopment

    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                self?.canCheck = change.newValue ?? false
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                self?.automaticChecks = change.newValue ?? false
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                self?.lastCheck = updater.lastUpdateCheckDate
            }
        ]
        controller.startUpdater()
        // Sparkle's windows and alerts appear on their own, so style each one the first time it updates.
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, !self.styled.contains(window) else { return }
            let sparkle = Bundle(for: SPUUpdater.self)
            guard window.windowController.map({ Bundle(for: type(of: $0)) == sparkle }) == true || (self.showingAlert && window == NSApp.modalWindow) else { return }
            self.styled.add(window)
            ThemedIcon.style(window, self.palette)
        }
    }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheck else { return }
        beforeUserCheck?()
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }
    func menuItem() -> NSMenuItem {
        let title = availableVersion.map { "Update to Snippet \($0)…" } ?? "Check for Updates…"
        let item = NSMenuItem(title: title, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        return item
    }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Keep scheduled updates discoverable in the menu/settings without stealing focus.
        false
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        availabilityChanged?()
    }
    func standardUserDriverWillShowModalAlert() { showingAlert = true }
    func standardUserDriverDidShowModalAlert() { showingAlert = false }
    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        availabilityChanged?()
    }
}
extension UpdateService: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheck }
}

struct UpdatesSettingsView: View {
    @ObservedObject var updates: UpdateService
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(AppEnvironment.current.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
            if updates.enabled {
                Toggle("Automatically check for updates", isOn: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks)).pointerCursor()
                Text("Check daily for new versions. You choose when to download and install an update.").font(.caption).foregroundStyle(theme.secondary)
                if let version = updates.availableVersion { Text("Snippet \(version) is available.").foregroundStyle(theme.accent) }
                Button("Check for Updates…") { updates.checkForUpdates() }.disabled(!updates.canCheck).pointerCursor()
                Text(updates.lastCheck.map { "Last checked: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No update checks yet.").font(.caption).foregroundStyle(theme.secondary)
                Divider()
                Text("Updates are downloaded securely from GitHub and verified before installation. Your clips, snippets, and settings stay on this Mac.").font(.caption).foregroundStyle(theme.secondary)
            } else {
                Text("This is a local development build. Update it by rebuilding from source. Automatic updates are available in the release version of Snippet.").foregroundStyle(theme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

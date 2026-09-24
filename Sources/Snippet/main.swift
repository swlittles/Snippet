import AppKit
import SwiftUI
import Carbon
import ApplicationServices

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var keyHandler: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = Store()
    let history = History()
    let calculator = CalculatorStore()
    let theme = ThemeStore()
    let workspace = WorkspaceStore()
    let usage = UsageStore()
    let apps = AppCatalog()
    let clickGuard = FollowUpClickGuard()
    lazy var librarySync = LibrarySync(store: store, history: history, workspace: workspace, theme: theme)
    let shortcuts = ShortcutStore()
    let updates = UpdateService()
    var activeGlobal: KeyBinding?
    var clipboard: ClipboardService!
    var expansion: ExpansionService!
    var panel: LauncherPanel!
    var status: NSStatusItem!
    var hotkey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var previousApp: NSRunningApplication?
    /// The most recently activated other app, whichever way Snippet was opened.
    private var lastExternalApp: NSRunningApplication?
    var model: LauncherModel!
    var hotkeyMessage = ""
    private var statusMenu: NSMenu?
    private var menuSession = MenuTrackingSession()
    private var trackingStatusMenu: NSMenu?
    private var menuOutsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = LauncherModel(store: store, history: history, calculator: calculator, app: self)
        clipboard = ClipboardService(history: history, usage: usage)
        lastExternalApp = externalFrontmostApp()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastExternalApp = app
        }
        apps.refresh()
        expansion = ExpansionService(store: store)
        clipboard.start()
        expansion.start()
        _ = librarySync
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 456), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false
        panel.keyHandler = { [weak self] event in self?.handleKeyEvent(event) ?? false }
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = AppEnvironment.current.name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LauncherView(model: model, store: store, history: history).environmentObject(theme).environmentObject(shortcuts))
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menuImage = Bundle.main.url(forResource: "MenuIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Snippet")
        menuImage?.size = NSSize(width: 18, height: 18)
        menuImage?.isTemplate = true
        status.button?.image = menuImage
        status.button?.setAccessibilityLabel(AppEnvironment.current.name)
        status.button?.toolTip = AppEnvironment.current.name
        if AppEnvironment.current.isDevelopment {
            status.length = NSStatusItem.variableLength
            status.button?.title = " Dev"
        }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if let event, GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                app.shortcuts.releaseToggle()
                return noErr
            }
            if let recording = app.shortcuts.recording {
                _ = app.shortcuts.set(app.shortcuts[.toggle], for: recording)
            } else { app.shortcuts.performTogglePress { app.toggle() } }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        shortcuts.registerGlobal = { [weak self] binding in self?.registerGlobal(binding) }
        shortcuts.didChange = { [weak self] in self?.configureMenus() }
        if let error = registerGlobal(shortcuts[.toggle]) { hotkeyMessage = error; shortcuts.error = error }
        updates.beforeUserCheck = { [weak self] in
            self?.model.settings = false
            self?.hide(restoreFocus: false)
        }
        updates.availabilityChanged = { [weak self] in self?.configureMenus() }
        updates.start()
        configureMenus()
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event) == true ? nil : event
        }
        show()
    }
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Escape and arrow keys belong to AppKit while a menu is tracking.
        guard trackingStatusMenu == nil else { return false }
        if shortcuts.consumeToggleRelease(event) { return true }
        guard event.type == .keyDown else { return false }
        if shortcuts.capture(event) { return true }
        // A field editor or sheet can own keyboard focus. Visibility, not the
        // panel's key-window flag, determines whether the toggle should close it.
        if shortcuts.consumeLauncherToggle(event, launcherVisible: panel?.isVisible == true, toggle: { self.toggle() }) { return true }
        guard panel?.isKeyWindow == true || panel?.attachedSheet?.isKeyWindow == true else { return false }
        return model.handle(event)
    }
    @objc func performCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = ShortcutAction(rawValue: name), shortcuts.recording == nil else { return }
        _ = model.perform(action)
    }
    func registerGlobal(_ binding: KeyBinding) -> String? {
        if let activeGlobal, activeGlobal.sameKeys(as: binding) { return nil }
        if !binding.enabled {
            if let hotkey { UnregisterEventHotKey(hotkey) }
            hotkey = nil; activeGlobal = nil; hotkeyMessage = ""; return nil
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.code), binding.carbonModifiers, EventHotKeyID(signature: 0x534E4950, id: 1), GetEventDispatcherTarget(), 0, &replacement)
        guard status == noErr else { return "\(binding.label) is unavailable or used by another app. Your previous shortcut was kept." }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = replacement; activeGlobal = binding; hotkeyMessage = ""; return nil
    }
    func menuItem(_ action: ShortcutAction, selector: Selector? = nil, native: Bool = false) -> NSMenuItem {
        let binding = shortcuts[action]
        let item = NSMenuItem(title: action.title, action: selector ?? #selector(performCommand(_:)), keyEquivalent: binding.enabled ? binding.character : "")
        item.keyEquivalentModifierMask = binding.flags
        item.representedObject = action.rawValue
        item.target = native ? nil : self
        return item
    }
    func configureMenus() {
        trackingStatusMenu?.cancelTracking()
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: AppEnvironment.current.name)
        appMenu.addItem(menuItem(.settings, selector: #selector(settings)))
        if updates.enabled { appMenu.addItem(updates.menuItem()) }
        appMenu.addItem(.separator()); appMenu.addItem(menuItem(.quit, selector: #selector(quit)))
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (action, selector): (ShortcutAction, String) in [(.undo,"undo:"),(.redo,"redo:"),(.cut,"cut:"),(.copy,"copy:"),(.paste,"paste:"),(.selectAll,"selectAll:")] {
            edit.addItem(menuItem(action, selector: Selector(selector), native: true))
        }
        editItem.submenu = edit; main.addItem(editItem)
        let viewItem = NSMenuItem(); let view = NSMenu(title: "View")
        for action: ShortcutAction in [.clipboard,.snippets,.calculator,.apps,.workspace,.enqueue,.pasteNext,.nextSection,.previousSection] { view.addItem(menuItem(action)) }
        viewItem.submenu = view; main.addItem(viewItem)
        NSApp.mainMenu = main
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open " + AppEnvironment.current.name + "    " + shortcuts.label(.toggle), action: #selector(show), keyEquivalent: ""); open.target = self; menu.addItem(open)
        let capture = NSMenuItem(title: "Save Clipboard as Snippet", action: #selector(capture), keyEquivalent: ""); capture.target = self; menu.addItem(capture)
        menu.addItem(menuItem(.settings, selector: #selector(settings)))
        if updates.enabled { menu.addItem(updates.menuItem()) }
        menu.addItem(.separator())
        let access = NSMenuItem(title: "Enable Accessibility…", action: #selector(accessibility), keyEquivalent: ""); access.target = self; menu.addItem(access)
        let folder = NSMenuItem(title: "Show Data Folder", action: #selector(dataFolder), keyEquivalent: ""); folder.target = self; menu.addItem(folder)
        menu.addItem(.separator()); menu.addItem(menuItem(.quit, selector: #selector(quit)))
        menu.delegate = self
        statusMenu = menu
        // Own the click action: mouse-down opens the menu; its native tracking
        // consumes the next outside/icon click without a mouse-up reopening it.
        status.menu = nil
        status.button?.target = self
        status.button?.action = #selector(toggleStatusMenu)
        status.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }
    @objc func toggleStatusMenu() {
        if let menu = trackingStatusMenu { menu.cancelTracking(); return }
        guard let menu = statusMenu, let button = status.button else { return }
        if !panel.isVisible { previousApp = externalFrontmostApp() ?? lastExternalApp ?? previousApp }
        // Activate before entering AppKit's tracking loop, never from menuWillOpen.
        NSApp.activate(ignoringOtherApps: true)
        button.highlight(true)
        defer { button.highlight(false) }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.maxY), in: button)
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        trackingStatusMenu = menu
        let generation = menuSession.begin(at: ProcessInfo.processInfo.systemUptime)
        if let monitor = menuOutsideClickMonitor { NSEvent.removeMonitor(monitor) }
        menuOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak menu] event in
            guard let self, let menu, menu === self.trackingStatusMenu,
                  self.menuSession.acceptsOutsideClick(generation: generation, timestamp: event.timestamp) else { return }
            menu.cancelTracking()
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        guard menu === trackingStatusMenu else { return }
        menuSession.end()
        trackingStatusMenu = nil
        if let monitor = menuOutsideClickMonitor { NSEvent.removeMonitor(monitor) }
        menuOutsideClickMonitor = nil
        shortcuts.releaseToggle()
    }
    func toggle() { trackingStatusMenu?.cancelTracking(); if panel.isVisible { hide() } else { show() } }
    func externalFrontmostApp() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return front
    }
    @objc func show() {
        if !panel.isVisible {
            previousApp = externalFrontmostApp() ?? lastExternalApp ?? previousApp
            let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
            if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 340, y: frame.midY - 170)) }
        }
        history.prune()
        let clipKeys = Set(history.clips.map { UsageStore.key(clip: $0.id) }), snippetKeys = Set(store.items.map { UsageStore.key(snippet: $0.id) })
        usage.prune { $0.hasPrefix("app:") || clipKeys.contains($0) || snippetKeys.contains($0) }
        apps.refresh()
        model.query = ""
        model.message = hotkeyMessage
        model.refresh()
        model.focusToken = UUID()
        resizeLauncher()
        // The paste fallback hides the app to hand focus back.
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func resizeLauncher() {
        guard panel != nil else { return }
        let height = model.listHeight + 151 + (model.preview && model.current != nil ? 131 : 0)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: 680, height: height)
        panel.setFrame(frame, display: true)
    }
    func hide(restoreFocus: Bool = true) {
        panel.orderOut(nil)
        if restoreFocus && NSApp.isActive, let previousApp { activate(previousApp) }
    }
    /// macOS 14 activation is cooperative: yield to the target, then ask it to come forward.
    func activate(_ target: NSRunningApplication) {
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: target)
            target.activate(from: .current, options: [])
        } else { target.activate(options: [.activateIgnoringOtherApps]) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.trackingStatusMenu == nil, !self.panel.isKeyWindow, self.model.editing == nil, self.model.editingClip == nil, !self.model.settings, !self.model.workspaceOpen, self.model.templateRequest == nil,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.hide(restoreFocus: false)
        }
    }
    @objc func settings() { if !panel.isVisible { show() }; model.settings = true }
    @objc func capture() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        show()
        model.editing = SnippetItem(title: "", text: text, tags: "")
    }
    @objc func accessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func dataFolder() { NSWorkspace.shared.open(store.url.deletingLastPathComponent()) }
    @objc func quit() { NSApp.terminate(nil) }
    func copyText(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        clipboard.changeCount = board.changeCount
    }
    func pasteText(_ text: String, copyOnly: Bool, image: Data? = nil, cursorMoves: Int = 0, formatted: Bool = false, completion: (() -> Void)? = nil) {
        copyText(text)
        let board = NSPasteboard.general
        if let image { board.setData(image, forType: .png) }
        if formatted {
            let rich = MarkdownBlock.attributed(text)
            if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) { board.setData(rtf, forType: .rtf) }
        }
        clipboard.changeCount = board.changeCount
        if copyOnly { hide(); return }
        guard AXIsProcessTrusted() else {
            model.message = "Copied. Enable Accessibility in Settings for Return to paste automatically."
            return
        }
        guard let target = previousApp, !target.isTerminated else {
            model.message = "Copied. Focus your destination, then open Snippet again."
            return
        }
        hide(restoreFocus: false)
        activate(target)
        attemptPaste(target, started: Date(), cursorMoves: cursorMoves, completion: completion)
    }
    /// Waits for the destination to come forward, then gives its window a moment
    /// to regain keyboard focus. Frontmost alone isn't enough: a Command–V sent
    /// during the switch is often dropped.
    func attemptPaste(_ target: NSRunningApplication, started: Date, retried: Bool = false, cursorMoves: Int = 0, completion: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(started)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if elapsed > 1.5 || target.isTerminated {
                    self.show(); self.model.message = "Copied, but \(target.localizedName ?? "the destination") didn’t come to the front. Paste with Command–V."
                    return
                }
                // If a direct activation is refused, hiding Snippet returns focus to the app that had it before.
                if !retried && elapsed > 0.35 { NSApp.hide(nil) }
                self.attemptPaste(target, started: started, retried: retried || elapsed > 0.35, cursorMoves: cursorMoves, completion: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    self.attemptPaste(target, started: started, retried: retried, cursorMoves: cursorMoves, completion: completion)
                    return
                }
                postPaste()
                completion?()
                if cursorMoves > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                        for _ in 0..<cursorMoves { postKey(CGKeyCode(kVK_LeftArrow)) }
                    }
                }
            }
        }
    }
    func open(_ entry: AppEntry) {
        usage.record(entry.usageKey)
        hide(restoreFocus: false)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async { self?.show(); self?.model.message = "Couldn’t open \(entry.name): \(error.localizedDescription)" }
        }
    }
    func reveal(_ entry: AppEntry) {
        hide(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }
}

// Exercise bundled preferences initialization in CI without opening a window.
if CommandLine.arguments.contains("--verify-environment") {
    _ = AppEnvironment.defaults.bool(forKey: "historyEnabled")
    print("Verified environment: " + AppEnvironment.current.bundleIdentifier)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store()
    let history = History()
    let calculator = CalculatorStore()
    let theme = ThemeStore()
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
    var model: LauncherModel!
    var hotkeyMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = LauncherModel(store: store, history: history, calculator: calculator, app: self)
        clipboard = ClipboardService(history: history)
        expansion = ExpansionService(store: store)
        clipboard.start()
        expansion.start()
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 456), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false
        panel.keyHandler = { [weak self] event in self?.model.handle(event) ?? false }
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
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if let recording = app.shortcuts.recording {
                _ = app.shortcuts.set(app.shortcuts[.toggle], for: recording)
            } else { app.toggle() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
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
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.shortcuts.capture(event) { return nil }
            guard self.panel.isKeyWindow || self.panel.attachedSheet?.isKeyWindow == true else { return event }
            return self.model.handle(event) ? nil : event
        }
        show()
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
        let status = RegisterEventHotKey(UInt32(binding.code), binding.carbonModifiers, EventHotKeyID(signature: 0x534E4950, id: 1), GetApplicationEventTarget(), 0, &replacement)
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
        for action: ShortcutAction in [.clipboard,.snippets,.calculator,.nextSection,.previousSection] { view.addItem(menuItem(action)) }
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
        self.status.menu = menu
    }
    func toggle() { if panel.isVisible { hide() } else { show() } }
    @objc func show() {
        if !panel.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
            if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 340, y: frame.midY - 170)) }
        }
        history.prune()
        model.query = ""
        model.message = hotkeyMessage
        model.refresh()
        model.focusToken = UUID()
        resizeLauncher()
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
        if restoreFocus && NSApp.isActive { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.panel.isKeyWindow, self.model.editing == nil, self.model.editingClip == nil, !self.model.settings,
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
    func pasteText(_ text: String, copyOnly: Bool) {
        copyText(text)
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
        target.activate(options: [.activateIgnoringOtherApps])
        attemptPaste(target, remaining: 10)
    }
    func attemptPaste(_ target: NSRunningApplication, remaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
            } else if remaining > 0 { self.attemptPaste(target, remaining: remaining - 1) }
            else { self.show(); self.model.message = "Copied, but the destination didn’t activate. Paste with Command–V." }
        }
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

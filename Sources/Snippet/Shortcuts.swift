import AppKit
import SwiftUI
import Carbon

enum ShortcutContext { case launcher, calculator, editor, settings }
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case toggle, clipboard, snippets, calculator, nextSection, previousSection
    case nextResult, previousResult, downResult, upResult, pasteResult, copyResult, newSnippet, saveSnippet, editSnippet, favorite, preview, settings, close
    case calculate, calculateEquals, copyCalculation, saveEditor, cancelEditor, closeSettings, quit
    case undo, redo, cut, copy, paste, selectAll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggle: return "Open / close Snippet"
        case .clipboard: return "Show Clipboard"
        case .snippets: return "Show Snippets"
        case .calculator: return "Show Calculator"
        case .nextSection: return "Next section"
        case .previousSection: return "Previous section"
        case .nextResult: return "Next result (wrap)"
        case .previousResult: return "Previous result (wrap)"
        case .downResult: return "Move down a result"
        case .upResult: return "Move up a result"
        case .pasteResult: return "Paste selected result"
        case .copyResult: return "Copy selected result"
        case .newSnippet: return "New snippet"
        case .saveSnippet: return "Save result as snippet"
        case .editSnippet: return "Edit selected clip or snippet"
        case .favorite: return "Toggle favorite"
        case .preview: return "Toggle preview"
        case .settings: return "Open settings"
        case .close: return "Dismiss launcher"
        case .calculate: return "Calculate"
        case .calculateEquals: return "Calculate (alternate)"
        case .copyCalculation: return "Copy calculation result"
        case .saveEditor: return "Save changes in editor"
        case .cancelEditor: return "Cancel editor"
        case .closeSettings: return "Close settings"
        case .quit: return "Quit Snippet"
        case .undo: return "Undo text edit"
        case .redo: return "Redo text edit"
        case .cut: return "Cut text"
        case .copy: return "Copy text"
        case .paste: return "Paste text"
        case .selectAll: return "Select all text"
        }
    }
    var group: String {
        switch self {
        case .toggle: return "Global"
        case .clipboard, .snippets, .calculator, .nextSection, .previousSection: return "Sections"
        case .calculate, .calculateEquals, .copyCalculation: return "Calculator"
        case .saveEditor, .cancelEditor: return "Editor"
        case .closeSettings, .quit, .settings: return "App"
        case .undo, .redo, .cut, .copy, .paste, .selectAll: return "Text editing"
        default: return "Clipboard and snippet results"
        }
    }
    var contexts: Set<ShortcutContext> {
        switch self {
        case .toggle, .quit, .undo, .redo, .cut, .copy, .paste, .selectAll: return [.launcher, .calculator, .editor, .settings]
        case .saveEditor, .cancelEditor: return [.editor]
        case .closeSettings: return [.settings]
        case .calculate, .calculateEquals, .copyCalculation: return [.calculator]
        case .clipboard, .snippets, .calculator, .nextSection, .previousSection, .newSnippet, .settings, .close: return [.launcher, .calculator]
        default: return [.launcher]
        }
    }
    var standard: KeyBinding {
        let cmd = NSEvent.ModifierFlags.command, shift = NSEvent.ModifierFlags.shift
        switch self {
        case .toggle: return .init(49, AppEnvironment.current.isDevelopment ? [.control, .option] : .option)
        case .clipboard: return .init(18, cmd)
        case .snippets: return .init(19, cmd)
        case .calculator: return .init(20, cmd)
        case .nextSection: return .init(48, .control)
        case .previousSection: return .init(48, [.control, .shift])
        case .nextResult: return .init(48)
        case .previousResult: return .init(48, shift)
        case .downResult: return .init(125)
        case .upResult: return .init(126)
        case .pasteResult, .calculate: return .init(36)
        case .copyResult, .copyCalculation: return .init(36, cmd)
        case .newSnippet: return .init(45, cmd)
        case .saveSnippet, .saveEditor: return .init(1, cmd)
        case .editSnippet: return .init(14, cmd)
        case .favorite: return .init(3, [.command, .shift])
        case .preview: return .init(35, cmd)
        case .settings: return .init(43, cmd)
        case .close, .cancelEditor, .closeSettings: return .init(53)
        case .calculateEquals: return .init(24)
        case .quit: return .init(12, cmd)
        case .undo: return .init(6, cmd)
        case .redo: return .init(6, [.command, .shift])
        case .cut: return .init(7, cmd)
        case .copy: return .init(8, cmd)
        case .paste: return .init(9, cmd)
        case .selectAll: return .init(0, cmd)
        }
    }
}

struct KeyBinding: Codable, Equatable {
    var code: UInt16
    var modifiers: UInt64
    var character: String
    static let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let disabled = KeyBinding(UInt16.max)
    var enabled: Bool { code != UInt16.max }
    init(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], character: String? = nil) {
        self.code = code; self.modifiers = UInt64(flags.intersection(Self.allowed).rawValue)
        self.character = character ?? Self.characters[code] ?? ""
    }
    init(event: NSEvent) { self.init(event.keyCode, event.modifierFlags, character: Self.characters[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased()) }
    var flags: NSEvent.ModifierFlags { .init(rawValue: UInt(modifiers)) }
    func matches(_ event: NSEvent) -> Bool { enabled && code == event.keyCode && modifiers == UInt64(event.modifierFlags.intersection(Self.allowed).rawValue) }
    func sameKeys(as other: KeyBinding) -> Bool { enabled && other.enabled && code == other.code && modifiers == other.modifiers }
    var label: String {
        guard enabled else { return "Not set" }
        var text = ""
        if flags.contains(.control) { text += "⌃" }; if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }; if flags.contains(.command) { text += "⌘" }
        return text + (Self.names[code] ?? character.uppercased())
    }
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }; if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }; if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    var swiftUI: KeyboardShortcut? {
        guard enabled, let character = character.first else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }; if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }; if flags.contains(.shift) { modifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
    static let names: [UInt16: String] = [36:"↵",48:"Tab",49:"Space",51:"⌫",53:"Esc",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"Page Up",121:"Page Down",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
    static let characters: [UInt16:String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"o",32:"u",33:"[",34:"i",35:"p",36:"\r",37:"l",38:"j",39:"'",40:"k",41:";",42:"\\",43:",",44:"/",45:"n",46:"m",47:".",48:"\t",49:" ",50:"`",51:"\u{7f}",53:"\u{1b}",123:"\u{f702}",124:"\u{f703}",125:"\u{f701}",126:"\u{f700}",122:"\u{f704}",120:"\u{f705}",99:"\u{f706}",118:"\u{f707}",96:"\u{f708}",97:"\u{f709}",98:"\u{f70a}",100:"\u{f70b}",101:"\u{f70c}",109:"\u{f70d}",103:"\u{f70e}",111:"\u{f70f}"]
}

final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [String: KeyBinding]
    @Published var recording: ShortcutAction?
    @Published var error: String?
    private var toggleIsDown = false
    var registerGlobal: ((KeyBinding) -> String?)?
    var didChange: (() -> Void)?
    let defaults: UserDefaults
    init(defaults: UserDefaults = AppEnvironment.defaults) {
        self.defaults = defaults
        var values = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.standard) })
        if let data = defaults.data(forKey: "shortcuts.v1"), let saved = try? JSONDecoder().decode([String:KeyBinding].self, from: data) { values.merge(saved) { _, new in new } }
        bindings = values
    }
    subscript(_ action: ShortcutAction) -> KeyBinding { bindings[action.rawValue] ?? action.standard }
    func label(_ action: ShortcutAction) -> String { self[action].label }
    func match(_ event: NSEvent, in context: ShortcutContext) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0.contexts.contains(context) && self[$0].matches(event) }
    }
    func validation(_ binding: KeyBinding, for action: ShortcutAction) -> String? {
        guard binding.enabled else { return nil }
        if binding.character.isEmpty { return "This key isn’t supported. Choose a letter, number, symbol, arrow, or function key." }
        if action == .toggle && binding.flags.intersection([.command,.option,.control]).isEmpty { return "The global shortcut must include Command, Option, or Control." }
        if binding.code == 48 && binding.flags.contains(.command) { return "Command–Tab is reserved by macOS." }
        if let conflict = ShortcutAction.allCases.first(where: { $0 != action && !$0.contexts.isDisjoint(with: action.contexts) && self[$0].sameKeys(as: binding) }) {
            return "Already assigned to \(conflict.title). Clear or change that shortcut first."
        }
        return nil
    }
    @discardableResult func set(_ binding: KeyBinding, for action: ShortcutAction) -> Bool {
        if let message = validation(binding, for: action) { error = message; return false }
        if action == .toggle, let message = registerGlobal?(binding) { error = message; return false }
        if action == .toggle { releaseToggle() }
        bindings[action.rawValue] = binding
        persist(); error = nil; recording = nil; didChange?(); return true
    }
    func capture(_ event: NSEvent) -> Bool {
        guard let recording else { return false }
        if event.keyCode == 53 { self.recording = nil; error = nil; return true }
        _ = set(KeyBinding(event: event), for: recording)
        return true
    }
    /// Match physical keys, including Option combinations that produce text.
    /// Consume repeats too, so holding the shortcut cannot type or reopen it.
    func consumeLauncherToggle(_ event: NSEvent, launcherVisible: Bool, toggle: () -> Void) -> Bool {
        guard event.type == .keyDown, (launcherVisible || toggleIsDown), recording == nil, self[.toggle].matches(event) else { return false }
        if !event.isARepeat { performTogglePress(toggle) }
        return true
    }
    // Carbon and AppKit can both deliver the same physical press. Handle it once
    // and wait for key-up, rather than using a timing debounce that drops taps.
    func performTogglePress(_ toggle: () -> Void) {
        guard !toggleIsDown else { return }
        toggleIsDown = true
        toggle()
    }
    func releaseToggle() { toggleIsDown = false }
    func consumeToggleRelease(_ event: NSEvent) -> Bool {
        guard event.type == .keyUp, event.keyCode == self[.toggle].code, toggleIsDown else { return false }
        releaseToggle()
        return true
    }
    func resetAll() {
        if let message = registerGlobal?(ShortcutAction.toggle.standard) { error = message; return }
        releaseToggle()
        bindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.standard) })
        recording = nil; error = nil; persist(); didChange?()
    }
    private func persist() { if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "shortcuts.v1") } }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var shortcuts: ShortcutStore
    @EnvironmentObject var theme: ThemeStore
    @State private var reset = false
    private let groups = ["Global", "Sections", "Clipboard and snippet results", "Calculator", "Editor", "App", "Text editing"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click a shortcut, then press its new keys. Escape cancels recording. Changes save immediately.").font(.caption).foregroundStyle(theme.secondary)
            if let error = shortcuts.error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondary)
                            ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in row(action) }
                        }
                    }
                }.padding(.vertical, 5)
            }.frame(height: 330)
            HStack {
                Button("Restore all defaults…") { reset = true }.pointerCursor()
                Spacer()
                if shortcuts.recording != nil { Button("Cancel recording") { shortcuts.recording = nil }.pointerCursor() }
            }
        }.onDisappear { shortcuts.recording = nil }
            .alert("Restore default shortcuts?", isPresented: $reset) {
                Button("Restore defaults") { shortcuts.resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This replaces your custom key assignments.") }
    }
    func row(_ action: ShortcutAction) -> some View {
        HStack(spacing: 8) {
            Text(action.title).font(.system(size: 12))
            Spacer()
            Button {
                shortcuts.error = nil
                shortcuts.recording = shortcuts.recording == action ? nil : action
            } label: {
                Text(shortcuts.recording == action ? "Press keys…" : shortcuts.label(action)).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(minWidth: 94).padding(.vertical, 6).padding(.horizontal, 8)
                    .background(shortcuts.recording == action ? theme.selection : theme.surface, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(PointerButtonStyle()).help("Change " + action.title.lowercased())
            if shortcuts.recording == action {
                Button("Esc") { _ = shortcuts.set(KeyBinding(53), for: action) }.buttonStyle(PointerButtonStyle()).help("Assign Escape")
            } else {
                Button { _ = shortcuts.set(.disabled, for: action) } label: { Image(systemName: "xmark.circle").font(.system(size: 12)) }.buttonStyle(PointerButtonStyle()).help("Clear " + action.title.lowercased()).disabled(!shortcuts[action].enabled)
            }
        }
    }
}

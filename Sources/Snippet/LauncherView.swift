import SwiftUI
import AppKit

struct ResultItem: Identifiable {
    var id: UUID
    var title: String
    var text: String
    var subtitle: String
    var favorite: Bool
    var snippet: SnippetItem?
}
final class LauncherModel: ObservableObject {
    let store: Store
    let history: History
    let calculator: CalculatorStore
    unowned let app: AppDelegate
    @Published var query = "" { didSet { selected = nil; refresh() } }
    @Published var tab: LauncherTab = .history { didSet { selected = nil; refresh(); focusToken = UUID(); app.resizeLauncher() } }
    @Published var expression = "" { didSet { calcError = nil; calcResult = nil } }
    @Published var calcResult: Double?
    @Published var calcError: String?
    @Published var degrees = AppEnvironment.defaults.bool(forKey: "calculatorDegrees") { didSet { AppEnvironment.defaults.set(degrees, forKey: "calculatorDegrees"); calcResult = nil; calcError = nil } }
    @Published var selected: UUID?
    @Published var editingClip: Clip?
    @Published var favoritesOnly = false { didSet { selected = nil; refresh() } }
    @Published var editing: SnippetItem?
    @Published var settings = false
    @Published var preview = false
    @Published var message = ""
    @Published var focusToken = UUID()
    init(store: Store, history: History, calculator: CalculatorStore, app: AppDelegate) { self.store = store; self.history = history; self.calculator = calculator; self.app = app }
    var results: [ResultItem] {
        if tab == .calculator { return [] }
        let isSnip = query.lowercased().hasPrefix("snip ")
        let search = isSnip ? String(query.dropFirst(5)) : query
        if tab == .snippets || isSnip {
            return store.results(search, favorites: favoritesOnly).map { ResultItem(id: $0.id, title: $0.title, text: $0.text, subtitle: [$0.keyword ?? "", $0.tags].filter { !$0.isEmpty }.joined(separator: " · "), favorite: $0.favorite, snippet: $0) }
        }
        return history.search(search, favorites: favoritesOnly).map { ResultItem(id: $0.id, title: $0.title, text: $0.text, subtitle: $0.source + " · " + $0.date.formatted(.relative(presentation: .named)), favorite: $0.favorite, snippet: nil) }
    }
    var listHeight: CGFloat { tab == .calculator ? 388 : results.isEmpty ? 180 : CGFloat(min(results.count, 5) * 58 + 16) }
    var current: ResultItem? { results.first { $0.id == selected } }
    func refresh() { if !results.contains(where: { $0.id == selected }) { selected = results.first?.id } }
    func new() { editing = SnippetItem(title: "", text: "", tags: "") }
    func saveSelection() {
        guard let current else { return }
        editing = current.snippet ?? SnippetItem(title: current.title, text: current.text, tags: "")
    }
    func editSelection() {
        guard let current else { return }
        if let snippet = current.snippet { editing = snippet }
        else { editingClip = history.clips.first { $0.id == current.id } }
    }
    func toggleFavorite(_ item: ResultItem) {
        if var snippet = item.snippet { snippet.favorite.toggle(); store.save(snippet) }
        else { history.toggleFavorite(item.id) }
        refresh()
    }
    func choose(copy: Bool = false) { if let current { app.pasteText(current.text, copyOnly: copy) } }
    func switchTab(_ target: LauncherTab) { query = ""; message = ""; tab = target }
    func cycleTab(backward: Bool = false) {
        switchTab(tab.cycled(backward: backward))
    }
    func calculate() {
        do {
            let value = try Calculator.evaluate(expression, answer: calculator.answer, degrees: degrees)
            calcResult = value; calcError = nil
            _ = calculator.record(expression: expression.trimmingCharacters(in: .whitespacesAndNewlines), result: value, degrees: degrees)
        } catch { calcResult = nil; calcError = error.localizedDescription }
    }
    func calculatorKey(_ key: String) {
        switch key {
        case "AC": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        default: expression += key
        }
        focusToken = UUID()
    }
    func copyResult(_ text: String) { app.copyText(text); message = "Result copied" }
    func copyCalculation() {
        if calcResult == nil { calculate() }
        if let calcResult { copyResult(Calculator.format(calcResult)) }
    }
    func moveResult(backward: Bool, wraps: Bool) {
        let list = results
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selected }
        let next = ResultNavigation.index(current: current, count: list.count, backward: backward, wraps: wraps)
        selected = list[next].id
    }
    var shortcutContext: ShortcutContext { (editing != nil || editingClip != nil) ? .editor : settings ? .settings : tab == .calculator ? .calculator : .launcher }
    func handle(_ event: NSEvent) -> Bool {
        guard let action = app.shortcuts.match(event, in: shortcutContext) else { return false }
        return perform(action)
    }
    @discardableResult func perform(_ action: ShortcutAction) -> Bool {
        guard action.contexts.contains(shortcutContext) else { return false }
        switch action {
        case .toggle: app.toggle()
        case .clipboard: switchTab(.history)
        case .snippets: switchTab(.snippets)
        case .calculator: switchTab(.calculator)
        case .nextSection: cycleTab()
        case .previousSection: cycleTab(backward: true)
        case .nextResult: moveResult(backward: false, wraps: true)
        case .previousResult: moveResult(backward: true, wraps: true)
        case .downResult: moveResult(backward: false, wraps: false)
        case .upResult: moveResult(backward: true, wraps: false)
        case .pasteResult: choose()
        case .copyResult: choose(copy: true)
        case .newSnippet: new()
        case .saveSnippet: saveSelection()
        case .editSnippet: editSelection()
        case .favorite: if let current { toggleFavorite(current) }
        case .preview: preview.toggle()
        case .settings: settings = true
        case .close: app.hide()
        case .calculate, .calculateEquals: calculate()
        case .copyCalculation: copyCalculation()
        case .cancelEditor: editing = nil; editingClip = nil
        case .closeSettings: settings = false
        case .quit: app.quit()
        // SwiftUI handles the editor's draft; AppKit handles text editing through the responder chain.
        case .saveEditor, .undo, .redo, .cut, .copy, .paste, .selectAll: return false
        }
        return true
    }

}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var store: Store
    @ObservedObject var history: History
    @AppStorage("historyEnabled", store: AppEnvironment.defaults) var historyEnabled = false
    @FocusState private var searchFocused: Bool
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    var accent: Color { theme.accent }
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            tabs
            Divider()
            if let error = store.error ?? history.error {
                Text(error).foregroundStyle(.orange).padding()
            }
            if model.tab == .calculator { CalculatorView(model: model, calculator: model.calculator) }
            else if model.results.isEmpty { emptyState } else { resultList }
            if model.preview, let current = model.current {
                Divider()
                ScrollView { Text(current.text).textSelection(.enabled).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(16) }.frame(height: 130)
            }
            Divider()
            footer
        }
        .frame(width: 680)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .preferredColorScheme(theme.palette.isDark ? .dark : .light)
        .onAppear { searchFocused = true; model.app.resizeLauncher() }
        .onChange(of: model.results.count) { _ in model.app.resizeLauncher() }
        .onChange(of: model.preview) { _ in model.app.resizeLauncher() }
        .onChange(of: model.focusToken) { _ in searchFocused = true }
        .onChange(of: store.items) { _ in model.refresh() }
        .onChange(of: history.clips) { _ in model.refresh() }
        .sheet(item: $model.editing, onDismiss: { searchFocused = true }) { item in EditorView(item: item, store: store) }
        .sheet(item: $model.editingClip, onDismiss: { searchFocused = true }) { clip in ClipEditorView(clip: clip, history: history) }
        .sheet(isPresented: $model.settings, onDismiss: { searchFocused = true }) { SettingsView(history: history, expansion: model.app.expansion, app: model.app) }
    }
    var searchBar: some View {
        HStack(spacing: 14) {
            LogoMark(color: theme.accent).frame(width: 27, height: 27)
            if AppEnvironment.current.isDevelopment {
                Text("DEV").font(.system(size: 10, weight: .bold)).padding(5).background(theme.selection, in: RoundedRectangle(cornerRadius: 4)).accessibilityLabel("Development build")
            }
            TextField(model.tab == .calculator ? "Calculate…  e.g. (24 + 18) / 6" : "Search copied text or type snip…", text: model.tab == .calculator ? $model.expression : $model.query).textFieldStyle(.plain).font(.system(size: 24)).focused($searchFocused).accessibilityLabel(model.tab == .calculator ? "Calculator expression" : "Search clipboard and snippets")
            if !(model.tab == .calculator ? model.expression : model.query).isEmpty { Button { if model.tab == .calculator { model.expression = "" } else { model.query = "" } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(PointerButtonStyle()).help("Clear search") }
        }.padding(22)
    }
    var tabs: some View {
        HStack(spacing: 6) {
            ForEach(LauncherTab.allCases, id: \.self) { tab in
                Button { model.switchTab(tab) } label: {
                    Text(tab.rawValue + "  " + shortcuts.label(tab.shortcutAction)).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                        .background((model.query.lowercased().hasPrefix("snip ") ? tab == .snippets : model.tab == tab) ? theme.selection : .clear, in: Capsule())
                }.buttonStyle(PointerButtonStyle())
            }
            if model.tab != .calculator {
                Button { model.favoritesOnly.toggle() } label: {
                    Image(systemName: model.favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(model.favoritesOnly ? theme.accent : theme.secondary)
                }.help(model.favoritesOnly ? "Show all results" : "Show favorites only")
                    .accessibilityLabel("Favorites only").accessibilityValue(model.favoritesOnly ? "On" : "Off")
            }
            Spacer()
            if !historyEnabled { Text("History paused").font(.system(size: 10)).foregroundStyle(theme.secondary) }
            Button { model.new() } label: { Image(systemName: "plus") }.help("New snippet · " + shortcuts.label(.newSnippet))
            Button { model.settings = true } label: { Image(systemName: "gearshape") }.help("Settings · " + shortcuts.label(.settings))
        }.buttonStyle(PointerButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12)
    }
    var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in row(item, index: index) }
                }.padding(8)
            }.frame(height: model.listHeight)
                .onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
        }
    }
    func row(_ item: ResultItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.snippet == nil ? "doc.on.clipboard" : "text.badge.star").foregroundStyle(accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(item.subtitle.isEmpty ? String(item.text.prefix(100)) : item.subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.toggleFavorite(item) } label: {
                Image(systemName: item.favorite ? "star.fill" : "star").foregroundStyle(item.favorite ? accent : theme.secondary)
            }.buttonStyle(PointerButtonStyle()).help(item.favorite ? "Remove favorite" : "Favorite · keep indefinitely")
                .accessibilityLabel(item.favorite ? "Unfavorite " + item.title : "Favorite " + item.title)
            Button { model.selected = item.id; model.editSelection() } label: { Image(systemName: "pencil") }
                .buttonStyle(PointerButtonStyle()).help("Edit · " + shortcuts.label(.editSnippet)).accessibilityLabel("Edit " + item.title)
            if model.selected == item.id { Image(systemName: "return").foregroundStyle(accent).font(.system(size: 12)) }
        }.padding(.horizontal, 12).frame(height: 55)
            .background(model.selected == item.id ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).pointerCursor().onTapGesture(count: 2) { model.selected = item.id; model.choose() }
            .onTapGesture { model.selected = item.id }.id(item.id)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton).accessibilityValue(model.selected == item.id ? "Selected" : "")
            .contextMenu {
                Button("Paste") { model.selected = item.id; model.choose() }
                Button("Copy") { model.selected = item.id; model.choose(copy: true) }
                Button(item.favorite ? "Remove favorite" : "Add to favorites") { model.toggleFavorite(item) }
                Button("Edit…") { model.selected = item.id; model.editSelection() }
                if item.snippet == nil { Button("Save as snippet…") { model.selected = item.id; model.saveSelection() } }
                if item.snippet == nil { Button("Remove from history") { history.remove(item.id) } }
            }
    }
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.tab == .history ? "doc.on.clipboard" : "text.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
            Text(model.favoritesOnly ? "No matching favorites" : model.query.isEmpty ? (model.tab == .history ? "Copy now. Find it later." : "Your words, ready to paste.") : "No matching text").font(.system(size: 18, weight: .medium))
            Text(model.favoritesOnly ? "Star a clip or snippet to find it here." : model.tab == .history ? (historyEnabled ? "Copy text in any app. It will appear here." : "Enable clipboard history to remember the text you copy.") : "Create a snippet, then find it by name or keyword.").font(.system(size: 12)).foregroundStyle(theme.secondary)
            if model.tab == .history && !historyEnabled { Button("Enable clipboard history") { historyEnabled = true }.buttonStyle(.borderedProminent).pointerCursor().tint(accent) }
            if model.tab == .snippets { Button("New snippet") { model.new() } }
        }.frame(maxWidth: .infinity).frame(height: model.listHeight)
    }
    var footer: some View {
        HStack(spacing: 12) {
            if model.message.isEmpty {
                Text(model.tab == .calculator ? "\(shortcuts.label(.calculate)) Calculate    \(shortcuts.label(.copyCalculation)) Copy result" : "\(shortcuts.label(.nextResult)) Next result    \(shortcuts.label(.pasteResult)) Paste    \(shortcuts.label(.saveSnippet)) Save").foregroundStyle(theme.secondary)
            } else { Text(model.message).foregroundStyle(accent).lineLimit(2) }
            Spacer(minLength: 0)
            if model.tab != .calculator { Button { model.preview.toggle() } label: { Image(systemName: "eye") }.help("Preview · " + shortcuts.label(.preview)) }
            if model.tab != .calculator { Button("Copy") { model.choose(copy: true) }.disabled(model.current == nil) }
        }.buttonStyle(PointerButtonStyle()).font(.system(size: 10)).padding(.horizontal, 20).frame(height: 38)
    }
}

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @State private var section = 0
    @ObservedObject var history: History
    @ObservedObject var expansion: ExpansionService
    let app: AppDelegate
    @AppStorage("historyEnabled", store: AppEnvironment.defaults) var historyEnabled = false
    @AppStorage("expansionEnabled", store: AppEnvironment.defaults) var expansionEnabled = false
    @Environment(\.dismiss) var dismiss
    @State var clear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { LogoMark(color: theme.accent).frame(width: 32, height: 32); Text(AppEnvironment.current.name + " settings").font(.title2.bold()); Spacer() }
            Picker("Settings section", selection: $section) { Text("General").tag(0); Text("Appearance").tag(1); Text("Shortcuts").tag(2); Text("Updates").tag(3) }.pickerStyle(.segmented)
            if section == 1 { ThemeSettingsView() } else if section == 2 { ShortcutsSettingsView() } else if section == 3 { UpdatesSettingsView(updates: app.updates) } else { general }
            Divider()
            HStack { Button("Open data folder") { app.dataFolder() }.pointerCursor(); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(shortcuts[.closeSettings].swiftUI).pointerCursor() }
        }.padding(26).frame(width: 530).foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(theme.palette.isDark ? .dark : .light)
            .onChange(of: expansionEnabled) { _ in expansion.update() }
            .alert("Clear clipboard history?", isPresented: $clear) {
                Button("Clear history", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Favorite clips and saved snippets will be kept.") }
    }
    var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Remember copied text", isOn: $historyEnabled).pointerCursor()
            Text("Keep up to 500 non-favorite text clips for 7 days on this Mac. Favorites are kept indefinitely and do not count toward this limit. Pausing stops new captures. Password apps and clipboard content marked confidential are skipped.").font(.caption).foregroundStyle(theme.secondary)
            Button("Clear clipboard history…") { clear = true }.disabled(history.clips.isEmpty).pointerCursor()
            Divider()
            Toggle("Expand snippet keywords as I type", isOn: $expansionEnabled).pointerCursor()
            Text("Assign a keyword such as ;email to a snippet. Type it in another app to replace it with your saved text. Secure input and password apps are excluded.").font(.caption).foregroundStyle(theme.secondary)
            Text(expansion.status).font(.caption).foregroundStyle(theme.secondary)
            Button { app.accessibility() } label: { Label("Enable Accessibility…", systemImage: "arrow.up.right.square").foregroundStyle(theme.accent).underline() }.buttonStyle(PointerButtonStyle()).help("Open macOS Accessibility settings")
            Divider()
            Text("\(shortcuts.label(.toggle)) opens Snippet. \(shortcuts.label(.clipboard)) Clipboard · \(shortcuts.label(.snippets)) Snippets · \(shortcuts.label(.calculator)) Calculator. \(shortcuts.label(.nextResult)) / \(shortcuts.label(.previousResult)) moves through results. Customize every command in Shortcuts.").font(.caption).foregroundStyle(theme.secondary)
        }
    }
}

struct EditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @State var item: SnippetItem
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    var validationError: String? {
        let keyword = item.keyword ?? ""
        if !keyword.isEmpty && !ExpansionMatcher.valid(keyword) { return "Use ; followed by 1–31 ASCII characters, without spaces." }
        if item.expands == true && keyword.isEmpty { return "Add a keyword to enable expansion." }
        if item.expands == true && item.text.utf16.count > 2000 { return "Automatic expansion supports up to 2,000 characters. Use the launcher for longer text." }
        if !keyword.isEmpty && store.items.contains(where: { $0.id != item.id && $0.keyword == keyword }) { return "That keyword is already assigned to another snippet." }
        return nil
    }
    var existing: Bool { store.items.contains { $0.id == item.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing ? "Edit snippet" : "New snippet").font(.system(size: 22, weight: .semibold))
            Text("Give it a name you’ll remember. Find it whenever you need it.").foregroundStyle(theme.secondary).font(.system(size: 12))
            TextField("Title", text: $item.title).textFieldStyle(.roundedBorder).focused($titleFocused)
            TextField("Tags (e.g. work, email)", text: $item.tags).textFieldStyle(.roundedBorder)
            TextField("Keyword, e.g. ;email (optional)", text: Binding(get: { item.keyword ?? "" }, set: { item.keyword = $0 })).textFieldStyle(.roundedBorder)
            Toggle("Expand automatically when I type this keyword", isOn: Binding(get: { item.expands ?? false }, set: { item.expands = $0 }))
            if let validationError { Text(validationError).font(.caption).foregroundStyle(.orange) }
            Toggle("Favorite", isOn: $item.favorite).pointerCursor()
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("CONTENT").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondary)
            TextEditor(text: $item.text).font(.system(size: 13, design: .monospaced)).padding(8).background(theme.surface, in: RoundedRectangle(cornerRadius: 8)).frame(height: 185)
            HStack {
                if existing { Button("Delete", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(shortcuts[.cancelEditor].swiftUI)
                Button("Save snippet") { item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines); if store.save(item) { dismiss() } }
                    .keyboardShortcut(shortcuts[.saveEditor].swiftUI).buttonStyle(.borderedProminent).pointerCursor()
                    .disabled(validationError != nil || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 520).foregroundStyle(theme.text).background(theme.background).tint(theme.accent).preferredColorScheme(theme.palette.isDark ? .dark : .light).onAppear { titleFocused = true }
        .alert("Delete this snippet?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { if store.delete(item) { dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("“\(item.title)” will be permanently deleted.") }
    }
}

struct ClipEditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss
    @State var clip: Clip
    @ObservedObject var history: History
    @FocusState private var contentFocused: Bool
    var invalid: Bool { clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clip.text.utf8.count > 100_000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit clip").font(.system(size: 22, weight: .semibold))
            Text("Update the text that will be pasted. The original capture date and source are kept.").font(.caption).foregroundStyle(theme.secondary)
            TextEditor(text: $clip.text).font(.system(size: 13, design: .monospaced))
                .focused($contentFocused).padding(8).background(theme.surface).frame(height: 240)
                .accessibilityLabel("Clip content")
            Toggle("Favorite — keep indefinitely", isOn: $clip.favorite).pointerCursor()
            if clip.text.utf8.count > 100_000 { Text("Clips can contain up to 100,000 bytes of text.").font(.caption).foregroundStyle(.orange) }
            if let error = history.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(shortcuts[.cancelEditor].swiftUI).pointerCursor()
                Button("Save clip") { if history.update(clip) { dismiss() } }
                    .keyboardShortcut(shortcuts[.saveEditor].swiftUI).buttonStyle(.borderedProminent).pointerCursor().disabled(invalid)
            }
        }.padding(26).frame(width: 520).foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(theme.palette.isDark ? .dark : .light).onAppear { contentFocused = true }
    }
}

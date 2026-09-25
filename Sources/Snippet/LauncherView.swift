import SwiftUI
import AppKit
import Combine
import ImageIO

enum ResultFilter { case all, favorites, frequent }

struct ResultItem: Identifiable {
    var id: UUID
    var title: String
    var text: String
    var subtitle: String
    var favorite: Bool
    var snippet: SnippetItem?
    var clip: Clip? = nil
    var app: AppEntry? = nil
    var vault: VaultItem? = nil
    var usageKey = ""
    var frequent = false
    var uses = 0
}

/// Decoded images, so scrolling and typing don't reread and rescale screenshots on every render.
enum ImageCache {
    private static let thumbnails = NSCache<NSURL, NSImage>()
    private static let images: NSCache<NSURL, NSImage> = { let cache = NSCache<NSURL, NSImage>(); cache.countLimit = 8; return cache }()
    static func thumbnail(_ url: URL) -> NSImage? {
        if let image = thumbnails.object(forKey: url as NSURL) { return image }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
    static func image(_ url: URL) -> NSImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}
final class LauncherModel: ObservableObject {
    let store: Store
    let history: History
    let calculator: CalculatorStore
    unowned let app: AppDelegate
    @Published var query = "" { didSet { selected = nil; refresh() } }
    @Published var tab: LauncherTab = .history { didSet { selected = nil; refresh(); focusToken = UUID(); app.resizeLauncher() } }
    @Published var expression = "" { didSet { calcError = nil; calcResult = nil; calcDisplay = nil } }
    @Published var calcDisplay: String?
    @Published var calcResult: Double?
    @Published var calcError: String?
    @Published var degrees = AppEnvironment.defaults.bool(forKey: "calculatorDegrees") { didSet { AppEnvironment.defaults.set(degrees, forKey: "calculatorDegrees"); calcResult = nil; calcDisplay = nil; calcError = nil } }
    @Published var selected: UUID?
    @Published var editingClip: Clip?
    @Published var filter: ResultFilter = .all { didSet { selected = nil; refresh() } }
    /// Cached: every render reads results several times, and search scans the whole history.
    @Published private(set) var results: [ResultItem] = []
    private var subscriptions: Set<AnyCancellable> = []
    @Published var editing: SnippetItem?
    @Published var settings = false
    /// The Settings section to show when Settings next opens.
    @Published var settingsSection: Int?
    @Published var vaultPassword = ""
    /// A secure field being edited doesn't redraw when its value is reset, so each attempt gets a fresh one.
    @Published var vaultFieldID = UUID()
    @Published var vaultReprompt: VaultReprompt?
    @Published var workspaceOpen = false
    @Published var workspaceSection = 0
    @Published var templateRequest: TemplateRequest?
    @Published var collectionFilter = "" { didSet { refresh() } }
    var collections: [String] { Array(Set(app.workspace.data.collections + store.items.compactMap(\.collection).filter { !$0.isEmpty })).sorted() }
    func openWorkspace(_ section: Int = 0) { workspaceSection = section; workspaceOpen = true }
    @Published var preview = false
    @Published var message = ""
    @Published var focusToken = UUID()
    init(store: Store, history: History, calculator: CalculatorStore, app: AppDelegate) {
        self.store = store; self.history = history; self.calculator = calculator; self.app = app
        // @Published emits before the value changes; hop to the next turn so refresh reads the new list.
        app.apps.$apps.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        app.vault.$items.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        // Locking and unlocking swap the search field for the password field; keep keyboard focus there.
        app.vault.$state.dropFirst().removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.message = ""; self?.refresh(); self?.focusToken = UUID() }.store(in: &subscriptions)
    }
    private func computeResults() -> [ResultItem] {
        if tab == .calculator { return [] }
        if tab == .vault { return app.vault.state == .unlocked ? app.vault.search(query, favorites: filter == .favorites).map(vaultResult) : [] }
        let usage = app.usage, now = Date()
        if tab == .apps { return app.apps.search(query, usage: usage).map(appResult) }
        let isSnip = query.lowercased().hasPrefix("snip ")
        let search = isSnip ? String(query.dropFirst(5)) : query
        var items: [ResultItem]
        if tab == .snippets || isSnip {
            items = store.results(search, favorites: filter == .favorites).filter { collectionFilter.isEmpty || $0.collection == collectionFilter }.map { item in
                let key = UsageStore.key(snippet: item.id)
                return ResultItem(id: item.id, title: item.title, text: item.text, subtitle: [item.keyword ?? "", item.collection ?? "", item.tags].filter { !$0.isEmpty }.joined(separator: " · "), favorite: item.favorite, snippet: item, usageKey: key, frequent: usage.isFrequent(key, now: now), uses: usage.count(key))
            }
        } else {
            items = history.search(search, favorites: filter == .favorites).map { clip in
                let key = UsageStore.key(clip: clip.id)
                return ResultItem(id: clip.id, title: clip.title, text: clip.text, subtitle: clip.source, favorite: clip.favorite, snippet: nil, clip: clip, usageKey: key, frequent: usage.isFrequent(key, now: now), uses: usage.count(key))
            }
        }
        if filter == .frequent {
            return items.filter(\.frequent).map { ($0, usage.score($0.usageKey, now: now)) }.sorted { $0.1 > $1.1 }.map(\.0)
        }
        // As in Spotlight, a query naming an app offers it after any matching text, so Return opens it when nothing else matches.
        if filter == .all, !isSnip, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            items += app.apps.search(search, usage: usage, minimumScore: 50, limit: 3).map(appResult)
        }
        return items
    }
    /// Vault results carry no text of their own, so previews, tools and the queue never receive a secret.
    private func vaultResult(_ item: VaultItem) -> ResultItem {
        ResultItem(id: item.resultID, title: item.name, text: "", subtitle: item.subtitle, favorite: item.favorite, snippet: nil, vault: item)
    }
    private func appResult(_ entry: AppEntry) -> ResultItem {
        ResultItem(id: entry.id, title: entry.name, text: entry.url.path, subtitle: entry.location, favorite: false, snippet: nil, app: entry, usageKey: entry.usageKey)
    }
    var listHeight: CGFloat { tab == .calculator ? 388 : results.isEmpty ? 180 : CGFloat(min(results.count, 5) * 58 + 16) }
    var current: ResultItem? { results.first { $0.id == selected } }
    func refresh() {
        results = computeResults()
        if !results.contains(where: { $0.id == selected }) { selected = results.first?.id }
    }
    func new() { editing = SnippetItem(title: "", text: "", tags: "", collection: collectionFilter.isEmpty ? nil : collectionFilter) }
    var visibleTabs: [LauncherTab] { LauncherTab.visible(vault: app.vault.enabled) }
    func openSettings(section: Int) { settingsSection = section; settings = true }
    func saveSelection() {
        guard let current, current.app == nil, current.vault == nil else { return }
        editing = current.snippet ?? SnippetItem(title: current.title, text: current.text, tags: "")
    }
    func editSelection() {
        guard let current, current.app == nil, current.vault == nil else { return }
        if let snippet = current.snippet { editing = snippet }
        else { editingClip = history.clips.first { $0.id == current.id } }
    }
    func toggleFavorite(_ item: ResultItem) {
        guard item.app == nil, item.vault == nil else { return }
        if var snippet = item.snippet { snippet.favorite.toggle(); store.save(snippet) }
        else { history.toggleFavorite(item.id) }
        refresh()
    }
    /// Return pastes and Command–Return copies; for apps they open and show in Finder, as in Spotlight.
    func choose(copy: Bool = false, formatted: Bool = false, textOnly: Bool = false, clicked: Bool = false) {
        guard let current else { return }
        if clicked { app.clickGuard.arm() }
        if let item = current.vault { useVault(item, { item.primary }, copy: copy); return }
        if let entry = current.app {
            if copy { app.reveal(entry) } else { app.open(entry) }
            return
        }
        app.usage.record(current.usageKey)
        if !textOnly, let clip = current.clip, let url = history.imageURL(clip) {
            do { app.pasteText(current.text, copyOnly: copy, image: try Data(contentsOf: url)) }
            catch { message = "Couldn’t read the image: " + error.localizedDescription }
            return
        }
        if current.snippet != nil && !SnippetTemplate.fields(current.text).isEmpty {
            templateRequest = TemplateRequest(text: current.text, copyOnly: copy, clipboard: NSPasteboard.general.string(forType: .string) ?? "", formatted: formatted)
        } else {
            let value = current.snippet == nil ? ExpandedTemplate(text: current.text, cursorMoves: 0) : SnippetTemplate.expand(current.text, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
            app.pasteText(value.text, copyOnly: copy, cursorMoves: value.cursorMoves, formatted: formatted)
        }
    }
    func enqueue() {
        guard let current, current.app == nil, current.vault == nil else { return }
        do {
            let image = try current.clip.flatMap { history.imageURL($0) }.map { try Data(contentsOf: $0) }
            if app.workspace.update({ $0.queue.append(QueueEntry(title: current.title, text: current.text, image: image, template: current.snippet != nil)) }) { message = "Added to queue · \(app.workspace.data.queue.count) items" }
        } catch { message = error.localizedDescription }
    }
    func pasteNext() {
        guard let entry = app.workspace.data.queue.first else { message = "The paste queue is empty"; return }
        if entry.template == true && !SnippetTemplate.fields(entry.text).isEmpty {
            templateRequest = TemplateRequest(text: entry.text, copyOnly: false, clipboard: NSPasteboard.general.string(forType: .string) ?? "", queueID: entry.id); return
        }
        let expanded = entry.template == true ? SnippetTemplate.expand(entry.text, clipboard: NSPasteboard.general.string(forType: .string) ?? "") : ExpandedTemplate(text: entry.text, cursorMoves: 0)
        app.pasteText(expanded.text, copyOnly: false, image: entry.image, cursorMoves: expanded.cursorMoves) { [weak self] in
            self?.app.workspace.update { $0.queue.removeAll { $0.id == entry.id } }
        }
    }
    func switchTab(_ target: LauncherTab) {
        guard visibleTabs.contains(target) else { return }
        query = ""; message = ""; vaultPassword = ""; tab = target
        if target == .vault { refreshVaultIfNeeded() }
    }
    func cycleTab(backward: Bool = false) {
        switchTab(tab.cycled(backward: backward, in: visibleTabs))
    }
    func unlockVault() {
        let password = vaultPassword
        guard !password.isEmpty, !app.vault.busy else { return }
        vaultPassword = ""; vaultFieldID = UUID()
        Task { await app.vault.unlock(password: password); await app.vault.refresh() }
    }
    func refreshVaultIfNeeded() { if app.vault.needsRefresh { Task { await app.vault.refresh() } } }
    /// Pastes or copies a vault value, evaluated at that moment so verification codes are current.
    /// Secrets of items that ask for the master password wait until it's confirmed.
    func useVault(_ item: VaultItem, _ field: @escaping () -> VaultItem.Field?, copy: Bool = false, keepOpen: Bool = false) {
        guard let preview = field(), !preview.value.isEmpty else { message = "This item has nothing to " + (copy ? "copy" : "paste") + "."; return }
        let deliver = { [weak self] in
            guard let self, let value = field() else { return }
            self.app.vault.touch()
            if keepOpen {
                self.app.copyText(value.value, concealed: true)
                let seconds = self.app.vault.clipboardSeconds
                self.message = value.name + " copied" + (seconds > 0 ? ". The clipboard clears in \(seconds) seconds." : ".")
            } else { self.app.pasteText(value.value, copyOnly: copy, concealed: true) }
        }
        if item.reprompt && preview.hidden { vaultReprompt = VaultReprompt(item: item, perform: deliver) } else { deliver() }
    }
    func calculate() {
        do {
            let natural = try NaturalCalculator.evaluate(expression)
            let value = try natural?.value ?? Calculator.evaluate(expression, answer: calculator.answer, degrees: degrees)
            calcDisplay = natural?.display
            calcResult = value; calcError = nil
            _ = calculator.record(expression: expression.trimmingCharacters(in: .whitespacesAndNewlines), result: value, degrees: degrees, display: calcDisplay)
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
        if let calcResult { copyResult(calcDisplay ?? Calculator.format(calcResult)) }
    }
    func moveResult(backward: Bool, wraps: Bool) {
        let list = results
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selected }
        let next = ResultNavigation.index(current: current, count: list.count, backward: backward, wraps: wraps)
        selected = list[next].id
    }
    var shortcutContext: ShortcutContext { (editing != nil || editingClip != nil || templateRequest != nil || vaultReprompt != nil) ? .editor : (settings || workspaceOpen) ? .settings : tab == .calculator ? .calculator : .launcher }
    func handle(_ event: NSEvent) -> Bool {
        guard let action = app.shortcuts.match(event, in: shortcutContext) else { return false }
        return perform(action)
    }
    @discardableResult func perform(_ action: ShortcutAction) -> Bool {
        guard action.contexts.contains(shortcutContext) else { return false }
        switch action {
        case .workspace: openWorkspace()
        case .enqueue: enqueue()
        case .pasteNext: pasteNext()
        case .toggle: app.toggle()
        case .clipboard: switchTab(.history)
        case .snippets: switchTab(.snippets)
        case .calculator: switchTab(.calculator)
        case .apps: switchTab(.apps)
        case .vault:
            guard app.vault.enabled else { return false }
            switchTab(.vault)
        case .copyUsername, .copyCode, .lockVault:
            guard tab == .vault, app.vault.state == .unlocked else { return false }
            if action == .lockVault { app.vault.lock(); break }
            guard let item = current?.vault else { return false }
            if action == .copyUsername { useVault(item, { item.usernameField }, copy: true) } else { useVault(item, { item.codeField() }, copy: true) }
        case .nextSection: cycleTab()
        case .previousSection: cycleTab(backward: true)
        case .nextResult: moveResult(backward: false, wraps: true)
        case .previousResult: moveResult(backward: true, wraps: true)
        case .downResult: moveResult(backward: false, wraps: false)
        case .upResult: moveResult(backward: true, wraps: false)
        case .pasteResult:
            if tab == .vault && app.vault.state != .unlocked {
                guard app.vault.state == .locked else { return false }
                unlockVault()
            } else { choose() }
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
        case .cancelEditor: editing = nil; editingClip = nil; templateRequest = nil; vaultReprompt = nil
        case .closeSettings: settings = false; workspaceOpen = false
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
    @ObservedObject var vault: VaultStore
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
            if let error = store.error ?? history.error ?? model.app.usage.error {
                Text(error).foregroundStyle(.orange).padding()
            }
            if model.tab == .vault && !vault.message.isEmpty {
                Text(vault.message).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.tab == .calculator { CalculatorView(model: model, calculator: model.calculator) }
            else if model.results.isEmpty { if model.tab == .vault { vaultEmptyState } else { emptyState } } else { resultList }
            if model.preview, let current = model.current {
                Divider()
                Group {
                    if let item = current.vault {
                        VaultDetailView(item: item) { field in model.useVault(item, field, copy: true, keepOpen: true) }
                    } else if let clip = current.clip, let url = history.imageURL(clip), let image = ImageCache.image(url) {
                        HStack { Image(nsImage: image).resizable().scaledToFit(); ScrollView { Text(current.text).font(.caption).textSelection(.enabled) } }.padding(8)
                    } else { MarkdownPreview(text: current.text) }
                }.frame(height: 130)
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
        // The password field replaces the search field, or a fresh one replaces it; focus it once it exists.
        .onChange(of: model.tab == .vault && vault.state == .locked) { _ in DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: model.vaultFieldID) { _ in DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: store.items) { _ in model.refresh() }
        .onChange(of: history.clips) { _ in model.refresh() }
        .onChange(of: vault.enabled) { enabled in if !enabled && model.tab == .vault { model.switchTab(.history) } }
        .sheet(item: $model.editing, onDismiss: { searchFocused = true }) { item in EditorView(item: item, store: store, collections: model.collections) }
        .sheet(item: $model.editingClip, onDismiss: { searchFocused = true }) { clip in ClipEditorView(clip: clip, history: history) }
        .sheet(isPresented: $model.settings, onDismiss: { searchFocused = true }) { SettingsView(history: history, expansion: model.app.expansion, app: model.app) }
        .sheet(item: $model.vaultReprompt, onDismiss: { searchFocused = true }) { request in VaultRepromptView(request: request, vault: vault) }
        .sheet(isPresented: $model.workspaceOpen) { WorkspaceView(model: model, workspace: model.app.workspace, store: store, sync: model.app.librarySync) }
        .sheet(item: $model.templateRequest) { request in
            TemplateView(request: request) { value, formatted in
                model.app.pasteText(value.text, copyOnly: request.copyOnly, cursorMoves: value.cursorMoves, formatted: formatted) {
                    if let id = request.queueID { model.app.workspace.update { $0.queue.removeAll { $0.id == id } } }
                }
            }
        }
    }
    var placeholder: String {
        switch model.tab {
        case .calculator: return "Calculate…  e.g. (24 + 18) / 6"
        case .apps: return "Search apps…"
        case .vault: return vault.state == .locked ? "Master password" : "Search your vault…"
        default: return "Search copied text, apps, or type snip…"
        }
    }
    var searchBar: some View {
        HStack(spacing: 14) {
            LogoMark(color: theme.accent).frame(width: 27, height: 27)
            if AppEnvironment.current.isDevelopment {
                Text("DEV").font(.system(size: 10, weight: .bold)).padding(5).background(theme.selection, in: RoundedRectangle(cornerRadius: 4)).accessibilityLabel("Development build")
            }
            if model.tab == .vault && vault.state == .locked {
                SecureField(placeholder, text: $model.vaultPassword).textFieldStyle(.plain).font(.system(size: 24)).focused($searchFocused).accessibilityLabel("Master password").id(model.vaultFieldID)
            } else {
                TextField(placeholder, text: model.tab == .calculator ? $model.expression : $model.query).textFieldStyle(.plain).font(.system(size: 24)).focused($searchFocused).accessibilityLabel(model.tab == .calculator ? "Calculator expression" : model.tab == .apps ? "Search apps" : model.tab == .vault ? "Search vault" : "Search clipboard and snippets")
            }
            if !(model.tab == .vault && vault.state == .locked), !(model.tab == .calculator ? model.expression : model.query).isEmpty { Button { if model.tab == .calculator { model.expression = "" } else { model.query = "" } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(PointerButtonStyle()).help("Clear search") }
        }.padding(22)
    }
    var tabs: some View {
        HStack(spacing: 6) {
            ForEach(model.visibleTabs, id: \.self) { tab in
                Button { model.switchTab(tab) } label: {
                    Text(tab.rawValue + "  " + shortcuts.label(tab.shortcutAction)).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                        .background((model.tab != .apps && model.tab != .vault && model.query.lowercased().hasPrefix("snip ") ? tab == .snippets : model.tab == tab) ? theme.selection : .clear, in: Capsule())
                }.buttonStyle(PointerButtonStyle())
            }
            if model.tab == .history || model.tab == .snippets {
                filterButton(.favorites, icon: "star", label: "Favorites only", help: "Show favorites only")
                filterButton(.frequent, icon: "flame", label: "Frequently used", help: "Show what you’ve used most in the last few days")
            } else if model.tab == .vault && vault.state == .unlocked {
                filterButton(.favorites, icon: "star", label: "Favorites only", help: "Show vault favorites only")
            }
            Spacer()
            Menu {
                Button("All collections") { model.collectionFilter = "" }
                ForEach(model.collections, id: \.self) { name in Button(name) { model.collectionFilter = name; model.switchTab(.snippets) } }
            } label: { Image(systemName: "folder") }.menuStyle(.borderlessButton).frame(width: 20).help(model.collectionFilter.isEmpty ? "Filter by collection" : model.collectionFilter)
            Button { model.openWorkspace() } label: { Image(systemName: "square.grid.2x2") }.help("Workspace · tools, queue, quicklinks, collections, packs and sync")
            Button { model.new() } label: { Image(systemName: "plus") }.help("New snippet · " + shortcuts.label(.newSnippet))
            Button { model.settings = true } label: { Image(systemName: "gearshape") }.help("Settings · " + shortcuts.label(.settings))
        }.buttonStyle(PointerButtonStyle()).padding(.horizontal, 20).padding(.bottom, 12)
    }
    func filterButton(_ filter: ResultFilter, icon: String, label: String, help: String) -> some View {
        let on = model.filter == filter
        return Button { model.filter = on ? .all : filter } label: {
            Image(systemName: on ? icon + ".fill" : icon).foregroundStyle(on ? theme.accent : theme.secondary)
        }.help(on ? "Show all results" : help)
            .accessibilityLabel(label).accessibilityValue(on ? "On" : "Off")
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
    @ViewBuilder func row(_ item: ResultItem, index: Int) -> some View {
        if let entry = item.app { appRow(item, entry) } else if let entry = item.vault { vaultRow(item, entry) } else { textRow(item) }
    }
    func subtitle(_ item: ResultItem) -> String {
        var parts: [String] = []
        if model.filter == .frequent { parts.append("Used \(item.uses)×") }
        // Formatted per visible row rather than for the whole history on each keystroke.
        if let clip = item.clip { parts += [clip.source, clip.date.formatted(.relative(presentation: .named))] }
        else if !item.subtitle.isEmpty { parts.append(item.subtitle) }
        return parts.isEmpty ? String(item.text.prefix(100)) : parts.joined(separator: " · ")
    }
    /// A single click pastes, like pressing Return. The row's buttons keep their own actions.
    func selectable<Content: View>(_ item: ResultItem, _ content: Content) -> some View {
        content.padding(.horizontal, 12).frame(height: 55)
            .background(model.selected == item.id ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).pointerCursor().onTapGesture { model.selected = item.id; model.choose(clicked: true) }.id(item.id)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton).accessibilityValue(model.selected == item.id ? "Selected" : "")
    }
    func textRow(_ item: ResultItem) -> some View {
        selectable(item, HStack(spacing: 12) {
            if let clip = item.clip, let url = history.imageURL(clip), let image = ImageCache.thumbnail(url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 40)
            } else { Image(systemName: item.snippet == nil ? "doc.on.clipboard" : "text.badge.star").foregroundStyle(accent).frame(width: 32) }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(subtitle(item)).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
            Spacer()
            if item.frequent && model.filter != .frequent {
                Image(systemName: "flame").font(.system(size: 11)).foregroundStyle(theme.secondary).help("Used \(item.uses)× recently").accessibilityLabel("Frequently used")
            }
            Button { model.toggleFavorite(item) } label: {
                Image(systemName: item.favorite ? "star.fill" : "star").foregroundStyle(item.favorite ? accent : theme.secondary)
            }.buttonStyle(PointerButtonStyle()).help(item.favorite ? "Remove favorite" : "Favorite · keep indefinitely")
                .accessibilityLabel(item.favorite ? "Unfavorite " + item.title : "Favorite " + item.title)
            Button { model.selected = item.id; model.editSelection() } label: { Image(systemName: "pencil") }
                .buttonStyle(PointerButtonStyle()).help("Edit · " + shortcuts.label(.editSnippet)).accessibilityLabel("Edit " + item.title)
            if model.selected == item.id { Image(systemName: "return").foregroundStyle(accent).font(.system(size: 12)) }
        })
            .contextMenu {
                Button("Paste") { model.selected = item.id; model.choose() }
                Button("Copy") { model.selected = item.id; model.choose(copy: true) }
                Button("Paste as formatted Markdown") { model.selected = item.id; model.choose(formatted: true, textOnly: true) }
                if item.clip?.imageName != nil { Button("Copy recognized text") { model.selected = item.id; model.choose(copy: true, textOnly: true) } }
                Button("Add to queue") { model.selected = item.id; model.enqueue() }
                Button("Transform / developer tools…") { model.selected = item.id; model.openWorkspace() }
                Button(item.favorite ? "Remove favorite" : "Add to favorites") { model.toggleFavorite(item) }
                Button("Edit…") { model.selected = item.id; model.editSelection() }
                if item.snippet == nil { Button("Save as snippet…") { model.selected = item.id; model.saveSelection() } }
                if item.snippet == nil { Button("Remove from history") { history.remove(item.id) } }
            }
    }
    func appRow(_ item: ResultItem, _ entry: AppEntry) -> some View {
        selectable(item, HStack(spacing: 12) {
            Image(nsImage: model.app.apps.icon(entry)).resizable().scaledToFit().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(model.tab == .apps ? item.subtitle : "Application · " + item.subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
            Spacer()
            if model.selected == item.id { Text("Open").font(.system(size: 11)).foregroundStyle(theme.secondary); Image(systemName: "return").foregroundStyle(accent).font(.system(size: 12)) }
        })
            .contextMenu {
                Button("Open") { model.selected = item.id; model.choose() }
                Button("Show in Finder") { model.selected = item.id; model.choose(copy: true) }
                Button("Copy path") { model.app.copyText(entry.url.path); model.message = "Path copied" }
            }
    }
    func vaultRow(_ item: ResultItem, _ entry: VaultItem) -> some View {
        selectable(item, HStack(spacing: 12) {
            Image(systemName: entry.icon).foregroundStyle(accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
            Spacer()
            if entry.reprompt { Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(theme.secondary).help("Asks for your master password").accessibilityLabel("Asks for master password") }
            if !entry.totp.isEmpty { Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(theme.secondary).help("Verification code · " + shortcuts.label(.copyCode)).accessibilityLabel("Has verification code") }
            if entry.favorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(accent).accessibilityLabel("Favorite") }
            if model.selected == item.id {
                if let primary = entry.primary { Text(primary.name).font(.system(size: 11)).foregroundStyle(theme.secondary) }
                Image(systemName: "return").foregroundStyle(accent).font(.system(size: 12))
            }
        })
            .contextMenu {
                if let primary = entry.primary {
                    Button("Paste " + primary.name.lowercased()) { model.selected = item.id; model.choose() }
                    Button("Copy " + primary.name.lowercased()) { model.selected = item.id; model.choose(copy: true) }
                    Divider()
                }
                if entry.usernameField != nil { Button("Copy username") { model.useVault(entry, { entry.usernameField }, copy: true) } }
                if entry.passwordField != nil { Button("Copy password") { model.useVault(entry, { entry.passwordField }, copy: true) } }
                if !entry.totp.isEmpty { Button("Copy verification code") { model.useVault(entry, { entry.codeField() }, copy: true) } }
                if !entry.fields.isEmpty {
                    Menu("Copy field") { ForEach(Array(entry.fields.enumerated()), id: \.offset) { _, field in Button(field.name) { model.useVault(entry, { field }, copy: true) } } }
                }
                if let url = entry.launchURL { Button("Open website") { model.app.hide(restoreFocus: false); NSWorkspace.shared.open(url) } }
                Button("Show details") { model.selected = item.id; model.preview = true }
                Divider()
                Button("Lock vault") { vault.lock() }
            }
    }
    var vaultEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: vault.state == .unlocked ? "key" : "lock.shield").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
            switch vault.state {
            case .signedOut:
                Text("Connect your vault").font(.system(size: 18, weight: .medium))
                Text("Sign in to Bitwarden, or to your own Bitwarden or Vaultwarden server, to search and paste your logins.").font(.system(size: 12)).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
                Button("Set up vault…") { model.openSettings(section: 5) }.buttonStyle(.borderedProminent).pointerCursor().tint(accent)
            case .locked:
                Text(vault.busy ? "Unlocking…" : "Vault locked").font(.system(size: 18, weight: .medium))
                if vault.busy { ProgressView().controlSize(.small) }
                else { Text("Type your master password above and press Return.").font(.system(size: 12)).foregroundStyle(theme.secondary) }
            case .unlocked:
                Text(!model.query.isEmpty ? "No matching items" : model.filter == .favorites ? "No favorites" : "Your vault is empty").font(.system(size: 18, weight: .medium))
                Text("Search by name, username, website or folder.").font(.system(size: 12)).foregroundStyle(theme.secondary)
            }
        }.padding(.horizontal, 40).frame(maxWidth: .infinity).frame(height: model.listHeight)
    }
    var emptyTitle: String {
        if model.tab == .apps { return model.query.isEmpty ? "Looking for apps…" : "No matching apps" }
        switch model.filter {
        case .favorites: return "No matching favorites"
        case .frequent: return model.query.isEmpty ? "Nothing used often yet" : "No matching frequent items"
        case .all: return model.query.isEmpty ? (model.tab == .history ? "Copy now. Find it later." : "Your words, ready to paste.") : "No matching text"
        }
    }
    var emptyDetail: String {
        if model.tab == .apps { return "Apps in Applications, System Applications and ~/Applications appear here." }
        switch model.filter {
        case .favorites: return "Star a clip or snippet to find it here."
        case .frequent: return "Clips and snippets you paste a few times appear here, then fade once you stop using them."
        case .all: return model.tab == .history ? (historyEnabled ? "Copy text in any app. It will appear here." : "Enable clipboard history to remember the text you copy.") : "Create a snippet, then find it by name or keyword."
        }
    }
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.tab == .apps ? "app.dashed" : model.filter == .frequent ? "flame" : model.tab == .history ? "doc.on.clipboard" : "text.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
            Text(emptyTitle).font(.system(size: 18, weight: .medium))
            Text(emptyDetail).font(.system(size: 12)).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
            if model.tab == .history && model.filter == .all && !historyEnabled { Button("Enable clipboard history") { historyEnabled = true }.buttonStyle(.borderedProminent).pointerCursor().tint(accent) }
            if model.tab == .snippets && model.filter == .all { Button("New snippet") { model.new() } }
        }.frame(maxWidth: .infinity).frame(height: model.listHeight)
    }
    var hints: String {
        switch model.tab {
        case .calculator: return "\(shortcuts.label(.calculate)) Calculate    \(shortcuts.label(.copyCalculation)) Copy result"
        case .apps: return "\(shortcuts.label(.nextResult)) Next app    \(shortcuts.label(.pasteResult)) Open    \(shortcuts.label(.copyResult)) Show in Finder"
        case .vault:
            guard vault.state == .unlocked else { return vault.state == .locked ? "\(shortcuts.label(.pasteResult)) Unlock" : "" }
            return "\(shortcuts.label(.pasteResult)) Paste    \(shortcuts.label(.copyResult)) Copy    \(shortcuts.label(.copyUsername)) Username    \(shortcuts.label(.copyCode)) Code    \(shortcuts.label(.lockVault)) Lock"
        default: return "\(shortcuts.label(.nextResult)) Next result    \(shortcuts.label(.pasteResult)) Paste    \(shortcuts.label(.saveSnippet)) Save"
        }
    }
    var footer: some View {
        HStack(spacing: 12) {
            if model.message.isEmpty {
                Text(hints).foregroundStyle(theme.secondary)
            } else { Text(model.message).foregroundStyle(accent).lineLimit(2) }
            Spacer(minLength: 0)
            if model.tab == .history || model.tab == .snippets {
                Button { model.openWorkspace(1) } label: { Image(systemName: "text.badge.plus") }.help("Paste queue")
                Button { model.preview.toggle() } label: { Image(systemName: "eye") }.help("Preview · " + shortcuts.label(.preview))
            } else if model.tab == .vault && vault.state == .unlocked {
                Button { vault.lock() } label: { Image(systemName: "lock") }.help("Lock vault · " + shortcuts.label(.lockVault))
                Button { model.preview.toggle() } label: { Image(systemName: "eye") }.help("Details · " + shortcuts.label(.preview))
            }
            if model.tab != .calculator && !(model.tab == .vault && vault.state != .unlocked) { Button(model.current?.app == nil ? "Copy" : "Show in Finder") { model.choose(copy: true) }.disabled(model.current == nil) }
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
            Picker("Settings section", selection: $section) { Text("General").tag(0); Text("Appearance").tag(1); Text("Shortcuts").tag(2); Text("Storage").tag(4); Text("Vault").tag(5); Text("Updates").tag(3) }.pickerStyle(.segmented).labelsHidden()
            if section == 5 { VaultSettingsView(vault: app.vault) } else if section == 1 { ThemeSettingsView() } else if section == 2 { ShortcutsSettingsView() } else if section == 3 { UpdatesSettingsView(updates: app.updates) } else if section == 4 { VStack(alignment: .leading, spacing: 14) { StorageSettingsView(history: history); Button("Library sync and packs…") { app.model.settings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { app.model.openWorkspace(5) } }.pointerCursor() } } else { general }
            Divider()
            HStack { Button("Open data folder") { app.dataFolder() }.pointerCursor(); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(shortcuts[.closeSettings].swiftUI).pointerCursor() }
        }.padding(26).frame(width: 530).foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(theme.palette.isDark ? .dark : .light)
            .onChange(of: expansionEnabled) { _ in expansion.update() }
            .onAppear { if let requested = app.model.settingsSection { section = requested; app.model.settingsSection = nil } }
            .alert("Clear clipboard history?", isPresented: $clear) {
                Button("Clear history", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Favorite clips and saved snippets will be kept.") }
    }
    var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Remember copied text and images", isOn: $historyEnabled).pointerCursor()
            Text("Save text and images on this Mac. Image text recognition runs locally. History is unlimited by default; optional cleanup rules are in Storage. Pausing stops new captures. Password apps and clipboard content marked confidential are skipped.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Clear clipboard history…") { clear = true }.disabled(history.clips.isEmpty).pointerCursor()
            Divider()
            Toggle("Expand snippet keywords as I type", isOn: $expansionEnabled).pointerCursor()
            Text("Assign a keyword such as ;email to a snippet. Type it in another app to replace it with your saved text. Secure input and password apps are excluded.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Text(expansion.status).font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button { app.accessibility() } label: { Label("Enable Accessibility…", systemImage: "arrow.up.right.square").foregroundStyle(theme.accent).underline() }.buttonStyle(PointerButtonStyle()).help("Open macOS Accessibility settings")
            Divider()
            Text("\(shortcuts.label(.toggle)) opens Snippet. \(shortcuts.label(.clipboard)) Clipboard · \(shortcuts.label(.snippets)) Snippets · \(shortcuts.label(.calculator)) Calculator · \(shortcuts.label(.apps)) Apps. \(shortcuts.label(.nextResult)) / \(shortcuts.label(.previousResult)) moves through results. Customize every command in Shortcuts.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @State var item: SnippetItem
    @ObservedObject var store: Store
    var collections: [String] = []
    @State private var showMarkdown = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    var validationError: String? {
        let keyword = item.keyword ?? ""
        if !keyword.isEmpty && !ExpansionMatcher.valid(keyword) { return "Use ; followed by 1–31 ASCII characters, without spaces." }
        if item.expands == true && keyword.isEmpty { return "Add a keyword to enable expansion." }
        if item.expands == true && !SnippetTemplate.fields(item.text).isEmpty { return "Snippets with fill-in fields are pasted from the launcher. Turn off automatic expansion." }
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
            HStack {
                TextField("Collection (optional)", text: Binding(get: { item.collection ?? "" }, set: { item.collection = $0 })).textFieldStyle(.roundedBorder)
                Menu("Choose") { Button("None") { item.collection = nil }; ForEach(collections, id: \.self) { name in Button(name) { item.collection = name } } }
                Picker("Format", selection: Binding(get: { item.format ?? "plain" }, set: { item.format = $0 })) { Text("Plain text").tag("plain"); Text("Markdown").tag("markdown") }.frame(width: 180)
            }
            TextField("Keyword, e.g. ;email (optional)", text: Binding(get: { item.keyword ?? "" }, set: { item.keyword = $0 })).textFieldStyle(.roundedBorder)
            Toggle("Expand automatically when I type this keyword", isOn: Binding(get: { item.expands ?? false }, set: { item.expands = $0 }))
            if let validationError { Text(validationError).font(.caption).foregroundStyle(.orange) }
            Toggle("Favorite", isOn: $item.favorite).pointerCursor()
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Text("CONTENT").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondary); Spacer(); Toggle("Preview Markdown", isOn: $showMarkdown).toggleStyle(.checkbox) }
            Text("Templates: {{name}}, {{date}}, {{date:MMMM d}}, {{clipboard}}, {{uuid}}, {{cursor}}").font(.system(size: 10)).foregroundStyle(theme.secondary)
            if showMarkdown { MarkdownPreview(text: item.text).frame(height: 185) } else {
            CodeEditor(text: $item.text, label: "Snippet content").font(.system(size: 13, design: .monospaced)).padding(8).background(theme.surface, in: RoundedRectangle(cornerRadius: 8)).frame(height: 185)
            }
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
    var invalid: Bool { (clip.imageName == nil && clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || clip.text.utf8.count > 100_000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit clip").font(.system(size: 22, weight: .semibold))
            Text("Update the text that will be pasted. The original capture date and source are kept.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            CodeEditor(text: $clip.text, label: "Clip content").font(.system(size: 13, design: .monospaced))
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

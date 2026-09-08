import AppKit
import Combine

struct SyncRecord: Codable, Equatable {
    var revision: Date
    var writer: String
    var payload: Data?
    func isNewer(than other: SyncRecord) -> Bool { revision == other.revision ? writer > other.writer : revision > other.revision }
}
struct SyncDocument: Codable {
    var version = 1
    var records: [String: SyncRecord] = [:]
    mutating func merge(_ other: Self) {
        for (key, value) in other.records where records[key] == nil || value.isNewer(than: records[key]!) { records[key] = value }
    }
}
struct SyncedClip: Codable { var clip: Clip; var image: Data? }

/// User-selected iCloud Drive folder. All access and local mutations run serially on the main thread.
/// A persisted per-item journal keeps deletions and offline edits from being resurrected by another Mac.
final class LibrarySync: ObservableObject {
    @Published var status = "Sync is off"
    @Published private(set) var folder: URL?
    @Published var shareClips: Bool { didSet { defaults.set(shareClips, forKey: "syncClipboard") } }
    let store: Store, history: History, workspace: WorkspaceStore, theme: ThemeStore
    let defaults: UserDefaults
    let journalURL: URL
    var journal = SyncDocument()
    var timer: Timer?
    let writer: String
    init(store: Store, history: History, workspace: WorkspaceStore, theme: ThemeStore, defaults: UserDefaults = AppEnvironment.defaults, journalURL: URL? = nil, automatic: Bool = true) {
        self.defaults = defaults; self.journalURL = journalURL ?? AppEnvironment.current.dataURL("sync-journal.json")
        self.store = store; self.history = history; self.workspace = workspace; self.theme = theme
        shareClips = defaults.bool(forKey: "syncClipboard")
        writer = defaults.string(forKey: "syncDeviceID") ?? UUID().uuidString
        defaults.set(writer, forKey: "syncDeviceID")
        if let bookmark = defaults.data(forKey: "syncFolderBookmark") {
            var stale = false; folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        if automatic { timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sync() } }
        if folder != nil { status = "Ready to sync" }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose a dedicated folder in iCloud Drive on each Mac. Saved snippets, collections, quicklinks and your theme will be shared."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        connect(url)
    }
    func connect(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            if folder != url { journal = SyncDocument(); try WorkspaceStore.write(journal, to: journalURL); defaults.set(false, forKey: "syncHasCompleted") }
            defaults.set(bookmark, forKey: "syncFolderBookmark"); folder = url; sync()
        } catch { status = error.localizedDescription }
    }
    func disconnect() { folder = nil; defaults.removeObject(forKey: "syncFolderBookmark"); status = "Sync is off. Local and shared data are kept." }
    func active(_ key: String) -> Bool { !key.hasPrefix("clip/") || shareClips }
    func snapshot() throws -> [String: Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var result: [String: Data] = [:]
        for item in store.items { result["snippet/" + item.id.uuidString] = try encoder.encode(item) }
        for link in workspace.data.links { result["link/" + link.id.uuidString] = try encoder.encode(link) }
        result["collections"] = try encoder.encode(workspace.data.collections)
        result["theme"] = try encoder.encode(theme.palette)
        if shareClips {
            for clip in history.clips {
                let image = try history.imageURL(clip).map { try Data(contentsOf: $0) }
                result["clip/" + clip.id.uuidString] = try encoder.encode(SyncedClip(clip: clip, image: image))
            }
        }
        return result
    }
    func sync() {
        guard let folder else { return }
        guard store.error == nil, history.error == nil, workspace.error == nil else { status = "Sync paused: resolve the local storage error first."; return }
        do {
            guard FileManager.default.fileExists(atPath: folder.path) else { throw MathError.invalid("The selected sync folder is unavailable.") }
            if FileManager.default.fileExists(atPath: journalURL.path) { journal = try JSONDecoder().decode(SyncDocument.self, from: Data(contentsOf: journalURL)) }
            let local = try snapshot(), now = Date()
            let firstConnection = !defaults.bool(forKey: "syncHasCompleted")
            for key in Set(local.keys).union(journal.records.keys).filter({ active($0) }) {
                if journal.records[key]?.payload != local[key] {
                    journal.records[key] = .init(revision: now, writer: writer, payload: local[key])
                }
            }
            try WorkspaceStore.write(journal, to: journalURL)
            let destination = folder.appendingPathComponent("Snippet.sync.json")
            var coordinationError: NSError?, failure: Error?, merged = journal
            NSFileCoordinator().coordinate(writingItemAt: destination, options: [], error: &coordinationError) { url in
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let remote = try JSONDecoder().decode(SyncDocument.self, from: Data(contentsOf: url))
                        guard remote.version == 1 else { throw MathError.invalid("This sync folder uses a newer format. Update Snippet before syncing.") }
                        merged.merge(remote)
                        if firstConnection {
                            // A fresh Mac must not replace the shared theme with its defaults.
                            if let sharedTheme = remote.records["theme"] { merged.records["theme"] = sharedTheme }
                            if let payload = remote.records["collections"]?.payload {
                                let names = try JSONDecoder().decode([String].self, from: payload)
                                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                                merged.records["collections"] = .init(revision: Date(), writer: writer, payload: try encoder.encode(Array(Set(names + workspace.data.collections)).sorted()))
                            }
                        }
                    }
                    // Clipboard records are published only while explicitly enabled.
                    var published = merged
                    if !shareClips { published.records = published.records.filter { !$0.key.hasPrefix("clip/") } }
                    // Keep existing remote clip records when this Mac opts out.
                    if !shareClips, FileManager.default.fileExists(atPath: url.path) {
                        let remote = try JSONDecoder().decode(SyncDocument.self, from: Data(contentsOf: url))
                        for (key, value) in remote.records where key.hasPrefix("clip/") { published.records[key] = value }
                    }
                    try WorkspaceStore.write(published, to: url)
                } catch { failure = error }
            }
            if let error = coordinationError { throw error }; if let failure { throw failure }
            // Decode every incoming record before changing any local file.
            let decoder = JSONDecoder()
            var snippets: [SnippetItem] = [], links: [Quicklink] = [], clips: [SyncedClip] = []
            var collections = workspace.data.collections, palette = theme.palette
            for (key, record) in merged.records where active(key) {
                guard let payload = record.payload else { continue }
                if key.hasPrefix("snippet/") { snippets.append(try decoder.decode(SnippetItem.self, from: payload)) }
                else if key.hasPrefix("link/") { links.append(try decoder.decode(Quicklink.self, from: payload)) }
                else if key.hasPrefix("clip/") { clips.append(try decoder.decode(SyncedClip.self, from: payload)) }
                else if key == "collections" { collections = try decoder.decode([String].self, from: payload) }
                else if key == "theme" { palette = try decoder.decode(ThemePalette.self, from: payload) }
            }
            if shareClips {
                for entry in clips {
                    if let image = entry.image {
                        guard let url = history.imageURL(entry.clip), NSImage(data: image) != nil else { throw MathError.invalid("Invalid image in shared clipboard.") }
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try image.write(to: url, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    }
                }
                guard history.replace(clips.map(\.clip).sorted { $0.date > $1.date }) else { throw MathError.invalid("Couldn’t save synced clipboard.") }
            }
            guard store.replace(snippets.sorted { $0.updatedAt > $1.updatedAt }), workspace.update({ $0.links = links.sorted { $0.title < $1.title }; $0.collections = collections }) else { throw MathError.invalid("Couldn’t save synced library.") }
            if theme.palette != palette { theme.palette = palette }
            merged.records = merged.records.filter { active($0.key) }
            try WorkspaceStore.write(merged, to: journalURL); journal = merged
            defaults.set(true, forKey: "syncHasCompleted")
            status = "Synced at " + Date().formatted(date: .omitted, time: .shortened)
        } catch { status = "Sync paused: " + error.localizedDescription }
    }
}

import AppKit
import Combine
import CryptoKit

struct AppEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    init(name: String, url: URL) {
        self.name = name; self.url = url
        // A path-derived ID keeps the selection stable across rescans.
        id = Array(SHA256.hash(data: Data(url.path.utf8))).withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
    }
    var usageKey: String { "app:" + url.path }
    var location: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
}

enum AppSearch {
    static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }
    /// Splits on punctuation, spaces and camel case: "TextEdit" → text, edit.
    static func words(_ name: String) -> [String] {
        var words: [String] = [], current = ""
        var previous: Character?
        for character in name {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                if character.isUppercase, previous?.isLowercase == true, !current.isEmpty { words.append(current); current = "" }
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words.map(fold)
    }
    /// Higher is better; nil means no match. Tiers: exact, prefix, word prefixes, initials, substring.
    static func score(_ name: String, query: String) -> Double? {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return 0 }
        let n = fold(name)
        if n == q { return 130 }
        // Shorter names win within a tier, so "Notes" ranks above "Notes Helper".
        let brevity = max(0, 10 - Double(n.count) / 4)
        if n.hasPrefix(q) { return 80 + brevity }
        let parts = words(name)
        let terms = q.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.allSatisfy({ term in parts.contains { $0.hasPrefix(term) } }) { return 60 + brevity }
        if terms.count == 1, q.count >= 2, String(parts.compactMap(\.first)).hasPrefix(q) { return 50 + brevity }
        if n.contains(q) { return 30 + brevity }
        return nil
    }
    /// Usage adds up to 20 points: an often-opened app can overtake the next tier up, not an exact match.
    static func rank(_ apps: [AppEntry], query: String, usage: UsageStore, minimumScore: Double = 0, limit: Int = .max, now: Date = Date()) -> [AppEntry] {
        let ranked = apps.compactMap { app -> (app: AppEntry, score: Double)? in
            guard let match = score(app.name, query: query), match >= minimumScore else { return nil }
            return (app, match + min(usage.score(app.usageKey, now: now) * 4, 20))
        }
        return ranked.sorted { $0.score != $1.score ? $0.score > $1.score : $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
            .prefix(limit).map(\.app)
    }
}

/// Installed applications, found by scanning the standard folders in the background.
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    let roots: [URL]
    private var scanning = false
    private var lastScan = Date.distantPast
    private let icons = NSCache<NSURL, NSImage>()
    init(roots: [URL] = AppCatalog.standardRoots) { self.roots = roots }
    static var standardRoots: [URL] {
        ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications", "/System/Library/CoreServices/Finder.app", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0) }
    }
    /// Rescans at most every 30 seconds; results publish on the main thread.
    func refresh(now: Date = Date()) {
        guard !scanning, now.timeIntervalSince(lastScan) > 30 else { return }
        scanning = true; lastScan = now
        let roots = self.roots, own = Bundle.main.bundleURL.resolvingSymlinksInPath()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.scan(roots).filter { $0.url.resolvingSymlinksInPath() != own }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                if found != self.apps { self.apps = found }
            }
        }
    }
    static func scan(_ roots: [URL], maxDepth: Int = 3) -> [AppEntry] {
        let manager = FileManager.default
        var seen = Set<String>(), entries: [AppEntry] = []
        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            // The same app can be reachable from two roots; keep the first.
            guard seen.insert(Bundle(url: resolved)?.bundleIdentifier ?? resolved.path).inserted else { return }
            var name = manager.displayName(atPath: url.path)
            if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
            entries.append(AppEntry(name: name, url: url))
        }
        for root in roots {
            if root.pathExtension.lowercased() == "app" {
                if manager.fileExists(atPath: root.path) { add(root) }
                continue
            }
            // Not .skipsHiddenFiles: /Applications/Safari.app is a symlink with the hidden flag set.
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants() }
                else if url.pathExtension.lowercased() == "app" { add(url); enumerator.skipDescendants() }
                else if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            }
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func search(_ query: String, usage: UsageStore, minimumScore: Double = 0, limit: Int = .max) -> [AppEntry] {
        AppSearch.rank(apps, query: query, usage: usage, minimumScore: minimumScore, limit: limit)
    }
    func icon(_ entry: AppEntry) -> NSImage {
        if let icon = icons.object(forKey: entry.url as NSURL) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        icons.setObject(icon, forKey: entry.url as NSURL)
        return icon
    }
}

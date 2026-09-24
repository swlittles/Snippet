import Foundation
import Combine

/// Local use timestamps for clips, snippets and apps. Scores decay with age, so
/// something pasted repeatedly this week surfaces without being made a favorite,
/// then fades once you stop using it.
final class UsageStore: ObservableObject {
    static let halfLife: TimeInterval = 3 * 86400
    /// Two uses within about a day, or three within a few days.
    static let frequentScore = 1.5
    static let keptUses = 30
    static let maximumAge: TimeInterval = 60 * 86400
    @Published private(set) var uses: [String: [Date]] = [:]
    @Published var error: String?
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? AppEnvironment.current.dataURL("usage.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { uses = try JSONDecoder().decode([String: [Date]].self, from: Data(contentsOf: self.url)) }
        catch { self.error = "Couldn’t read usage history. The original file was preserved." }
    }
    static func key(clip id: UUID) -> String { "clip:" + id.uuidString }
    static func key(snippet id: UUID) -> String { "snippet:" + id.uuidString }
    func record(_ key: String, now: Date = Date()) {
        var next = uses
        next[key] = Array((next[key, default: []] + [now]).suffix(Self.keptUses))
        persist(next)
    }
    func count(_ key: String) -> Int { uses[key]?.count ?? 0 }
    func score(_ key: String, now: Date = Date()) -> Double {
        (uses[key] ?? []).reduce(0) { $0 + pow(0.5, max(0, now.timeIntervalSince($1)) / Self.halfLife) }
    }
    func isFrequent(_ key: String, now: Date = Date()) -> Bool { score(key, now: now) >= Self.frequentScore }
    /// Drops deleted items and uses too old to affect ranking.
    func prune(keeping keep: (String) -> Bool, now: Date = Date()) {
        var next: [String: [Date]] = [:]
        for (key, dates) in uses where keep(key) {
            let recent = dates.filter { now.timeIntervalSince($0) < Self.maximumAge }
            if !recent.isEmpty { next[key] = recent }
        }
        if next != uses { persist(next) }
    }
    private func persist(_ next: [String: [Date]]) {
        guard error == nil else { return }
        do { try WorkspaceStore.write(next, to: url); uses = next }
        catch { self.error = "Couldn’t save usage history: \(error.localizedDescription)" }
    }
}

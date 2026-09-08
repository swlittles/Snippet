import Foundation
import Combine

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var source: String
    var date: Date
    var favorite = false
    var imageName: String? = nil
    init(id: UUID = UUID(), text: String, source: String, date: Date, favorite: Bool = false, imageName: String? = nil) {
        self.id = id; self.text = text; self.source = source; self.date = date; self.favorite = favorite; self.imageName = imageName
    }
    enum CodingKeys: String, CodingKey { case id, text, source, date, favorite, imageName }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        source = try values.decode(String.self, forKey: .source)
        date = try values.decode(Date.self, forKey: .date)
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        imageName = try values.decodeIfPresent(String.self, forKey: .imageName)
    }
    var title: String { String(text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)?.prefix(90) ?? (imageName == nil ? "Text" : "Image").prefix(90)) }
}

/// Zero means unlimited. Retention is a local preference, never a product quota.
struct HistoryRetention: Equatable {
    var days: Int = 0
    var limit: Int = 0
    static var current: HistoryRetention {
        HistoryRetention(days: max(0, AppEnvironment.defaults.integer(forKey: "historyRetentionDays")),
                         limit: max(0, AppEnvironment.defaults.integer(forKey: "historyRetentionLimit")))
    }
    func retaining(_ candidates: [Clip], now: Date) -> [Clip] {
        guard days > 0 || limit > 0 else { return candidates }
        var ordinaryCount = 0
        return candidates.sorted { $0.date > $1.date }.filter {
            if $0.favorite { return true }
            if days > 0 && now.timeIntervalSince($0.date) >= Double(days) * 86400 { return false }
            ordinaryCount += 1
            return limit <= 0 || ordinaryCount <= limit
        }
    }
}

final class History: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var error: String?
    let url: URL
    let retention: () -> HistoryRetention
    init(url: URL? = nil, retention: @escaping () -> HistoryRetention = { .current }) {
        self.retention = retention
        self.url = url ?? AppEnvironment.current.dataURL("history.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: self.url)) }
        catch { self.error = "Couldn’t read clipboard history. Original data was preserved." }
    }
    func search(_ query: String, favorites: Bool = false) -> [Clip] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return clips.filter { clip in
            (!favorites || clip.favorite) && words.allSatisfy { "\(clip.text) \(clip.source)".localizedStandardContains(String($0)) }
        }.sorted {
            if $0.favorite != $1.favorite { return $0.favorite }
            return $0.date > $1.date
        }
    }
    private func retained(_ candidates: [Clip], now: Date) -> [Clip] {
        retention().retaining(candidates, now: now)
    }

    func record(_ text: String, source: String, now: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000 else { return }
        // Re-copying keeps the favorite's identity and protection, including edited duplicates.
        var clip = clips.first { $0.imageName == nil && $0.text == text && $0.favorite } ?? clips.first { $0.imageName == nil && $0.text == text } ?? Clip(text: text, source: source, date: now)
        clip.date = now; clip.source = source
        var next = clips.filter { $0.id != clip.id && ($0.imageName != nil || $0.text != text || $0.favorite) }
        next.insert(clip, at: 0)
        persist(retained(next, now: now))
    }
    func prune(now: Date = Date()) {
        let next = retained(clips, now: now)
        if next != clips { persist(next) }
    }
    @discardableResult func update(_ item: Clip) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == item.id }),
              (!item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.imageName != nil),
              item.text.utf8.count <= 100_000 else { return false }
        var next = clips
        next[index].text = item.text
        next[index].favorite = item.favorite
        return persist(next)
    }
    func toggleFavorite(_ id: UUID) {
        guard var clip = clips.first(where: { $0.id == id }) else { return }
        clip.favorite.toggle()
        update(clip)
    }
    func remove(_ id: UUID) { persist(clips.filter { $0.id != id }) }
    func clear() { persist(clips.filter(\.favorite)) }
    @discardableResult func replace(_ next: [Clip]) -> Bool { persist(next) }
    @discardableResult func appendImage(_ clip: Clip) -> Bool { persist(retained([clip] + clips, now: Date())) }
    func setRecognizedText(_ text: String, id: UUID) {
        guard var clip = clips.first(where: { $0.id == id }), clip.text.isEmpty else { return }
        clip.text = text; _ = update(clip)
    }
    @discardableResult private func persist(_ next: [Clip]) -> Bool {
        guard error == nil else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let kept = Set(next.compactMap(\.imageName))
            for clip in clips where clip.imageName != nil && !kept.contains(clip.imageName!) {
                if let image = imageURL(clip) { try? FileManager.default.removeItem(at: image) }
            }
            clips = next
            return true
        } catch { self.error = "Couldn’t save clipboard history: \(error.localizedDescription)"; return false }
    }
}

struct ExpansionMatcher {
    private(set) var buffer = ""
    mutating func reset() { buffer = "" }
    mutating func feed(_ text: String, snippets: [SnippetItem]) -> SnippetItem? {
        guard text.count == 1, let character = text.first, character.isASCII, !character.isWhitespace else { reset(); return nil }
        buffer += text
        buffer = String(buffer.suffix(64))
        let match = snippets.first { item in
            guard item.expands == true, let keyword = item.keyword, Self.valid(keyword), buffer.hasSuffix(keyword) else { return false }
            let preceding = buffer.dropLast(keyword.count).last
            return preceding == nil || !(preceding!.isLetter || preceding!.isNumber)
        }
        if match != nil { reset() }
        return match
    }
    static func valid(_ keyword: String) -> Bool {
        keyword.count >= 2 && keyword.count <= 32 && keyword.first == ";" && keyword.allSatisfy { $0.isASCII && !$0.isWhitespace }
    }
}

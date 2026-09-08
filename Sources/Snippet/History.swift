import Foundation
import Combine

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var source: String
    var date: Date
    var favorite = false
    init(id: UUID = UUID(), text: String, source: String, date: Date, favorite: Bool = false) {
        self.id = id; self.text = text; self.source = source; self.date = date; self.favorite = favorite
    }
    enum CodingKeys: String, CodingKey { case id, text, source, date, favorite }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        source = try values.decode(String.self, forKey: .source)
        date = try values.decode(Date.self, forKey: .date)
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
    var title: String { String(text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)?.prefix(90) ?? "Text".prefix(90)) }
}

final class History: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var error: String?
    let url: URL
    init(url: URL? = nil) {
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
        var ordinaryCount = 0
        return candidates.filter {
            if $0.favorite { return true }
            guard now.timeIntervalSince($0.date) < 7 * 86400 else { return false }
            ordinaryCount += 1
            return ordinaryCount <= 500
        }
    }
    func record(_ text: String, source: String, now: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000 else { return }
        // Re-copying keeps the favorite's identity and protection, including edited duplicates.
        var clip = clips.first { $0.text == text && $0.favorite } ?? clips.first { $0.text == text } ?? Clip(text: text, source: source, date: now)
        clip.date = now; clip.source = source
        var next = clips.filter { $0.id != clip.id && ($0.text != text || $0.favorite) }
        next.insert(clip, at: 0)
        persist(retained(next, now: now))
    }
    func prune(now: Date = Date()) {
        let next = retained(clips, now: now)
        if next != clips { persist(next) }
    }
    @discardableResult func update(_ item: Clip) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == item.id }),
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
    @discardableResult private func persist(_ next: [Clip]) -> Bool {
        guard error == nil else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

import Foundation
import Combine

struct SnippetItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var tags: String
    var keyword: String? = nil
    var expands: Bool? = nil
    var favorite = false
    var updatedAt = Date()
    var collection: String? = nil
    var format: String? = nil
}

final class Store: ObservableObject {
    @Published private(set) var items: [SnippetItem] = []
    @Published var error: String?
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? AppEnvironment.current.dataURL("snippets.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                items = try JSONDecoder().decode([SnippetItem].self, from: Data(contentsOf: self.url))
            }
        } catch { self.error = "Couldn’t read your snippets. The original file has been left untouched. \(error.localizedDescription)" }
    }
    func results(_ query: String, favorites: Bool = false) -> [SnippetItem] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return items.filter { item in
            (!favorites || item.favorite) && words.allSatisfy { word in
                "\(item.title) \(item.text) \(item.tags) \(item.keyword ?? "") \(item.collection ?? "")".localizedStandardContains(word)
            }
        }.sorted {
            if $0.favorite != $1.favorite { return $0.favorite }
            return $0.updatedAt > $1.updatedAt
        }
    }
    @discardableResult func save(_ item: SnippetItem) -> Bool {
        var next = items
        var item = item
        item.updatedAt = Date()
        if let index = next.firstIndex(where: { $0.id == item.id }) { next[index] = item }
        else { next.append(item) }
        return persist(next)
    }
    @discardableResult func delete(_ item: SnippetItem) -> Bool { persist(items.filter { $0.id != item.id }) }
    @discardableResult func replace(_ next: [SnippetItem]) -> Bool { persist(next) }
    @discardableResult private func persist(_ next: [SnippetItem]) -> Bool {
        guard error == nil else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            items = next
            return true
        } catch { self.error = "Couldn’t save your snippets: \(error.localizedDescription)"; return false }
    }
}

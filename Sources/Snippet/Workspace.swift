import AppKit
import Combine
import Vision

struct Quicklink: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var destination: String
    var updatedAt = Date()
    func url(query: String) throws -> URL {
        if destination.hasPrefix("/") || destination.hasPrefix("~/") {
            return URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard let url = URL(string: destination.replacingOccurrences(of: "{query}", with: encoded)), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw MathError.invalid("Use an http(s) URL or an absolute folder path. Search URLs can include {query}.") }
        return url
    }
}
struct QueueEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var image: Data?
    var template: Bool? = nil
}
struct WorkspaceData: Codable, Equatable {
    var collections: [String] = []
    var links: [Quicklink] = []
    var queue: [QueueEntry] = []
}
final class WorkspaceStore: ObservableObject {
    @Published private(set) var data = WorkspaceData()
    @Published var error: String?
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? AppEnvironment.current.dataURL("workspace.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { data = try JSONDecoder().decode(WorkspaceData.self, from: Data(contentsOf: self.url)) }
            catch { self.error = "Couldn’t read Workspace. The original file was preserved." }
        }
    }
    @discardableResult func update(_ change: (inout WorkspaceData) -> Void) -> Bool {
        guard error == nil else { return false }
        var next = data; change(&next)
        do { try Self.write(next, to: url); data = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func move(_ id: UUID, offset: Int) {
        update { data in
            guard let index = data.queue.firstIndex(where: { $0.id == id }), data.queue.indices.contains(index + offset) else { return }
            data.queue.swapAt(index, index + offset)
        }
    }
}

struct SnippetPack: Codable {
    var format = "snippet-pack"
    var version = 1
    var snippets: [SnippetItem]
    var collections: [String]
    var quicklinks: [Quicklink]
    var theme: ThemePalette?
    static func read(_ url: URL) throws -> SnippetPack {
        if url.pathExtension.lowercased() == "alfredsnippets" {
            let listing = try archive(url, arguments: ["-Z1"])
            let entries = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init).filter { $0.hasSuffix(".json") && !$0.hasPrefix("__MACOSX/") }
            var items: [SnippetItem] = []
            for entry in entries {
                let data = try archive(url, arguments: ["-p"], entry: entry)
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let value = root["alfredsnippet"] as? [String: Any], let text = value["snippet"] as? String {
                    let key = value["keyword"] as? String
                    items.append(.init(title: value["name"] as? String ?? "Imported snippet", text: text, tags: "Imported from Alfred", keyword: key.flatMap { ExpansionMatcher.valid($0) ? $0 : nil }, expands: false, collection: url.deletingPathExtension().lastPathComponent))
                }
            }
            guard !items.isEmpty else { throw MathError.invalid("No snippets found in this Alfred collection.") }
            return .init(snippets: items, collections: [url.deletingPathExtension().lastPathComponent], quicklinks: [])
        }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
            guard let text = String(data: data, encoding: .utf8) else { throw MathError.invalid("The Markdown file must use UTF-8.") }
            return .init(snippets: [.init(title: url.deletingPathExtension().lastPathComponent, text: text, tags: "", format: "markdown")], collections: [], quicklinks: [])
        }
        if let pack = try? JSONDecoder().decode(Self.self, from: data) {
            guard pack.format == "snippet-pack", pack.version == 1 else { throw MathError.invalid("Unsupported snippet pack version.") }; return try pack.validated()
        }
        if let library = try? JSONDecoder().decode([SnippetItem].self, from: data) { return try Self(snippets: library, collections: [], quicklinks: []).validated() }
        // Alfred's exported per-snippet JSON, or an extracted collection directory.
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let item = root["alfredsnippet"] as? [String: Any], let text = item["snippet"] as? String {
            let key = item["keyword"] as? String
            return .init(snippets: [.init(title: item["name"] as? String ?? url.deletingPathExtension().lastPathComponent, text: text, tags: "Imported from Alfred", keyword: key.flatMap { ExpansionMatcher.valid($0) ? $0 : nil }, expands: false)], collections: [], quicklinks: [])
        }
        throw MathError.invalid("Choose a Snippet pack, snippets.json, Markdown file, or Alfred snippet JSON.")
    }
    private static func archive(_ url: URL, arguments: [String], entry: String? = nil) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [url.path] + (entry.map { [$0] } ?? [])
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 65536)
            if chunk.isEmpty { break }; data.append(chunk)
            if data.count > 32 * 1024 * 1024 { process.terminate(); process.waitUntilExit(); throw MathError.invalid("This archive entry is too large to import safely.") }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MathError.invalid("Couldn’t read the Alfred collection archive.") }
        return data
    }
    func validated() throws -> Self {
        guard snippets.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), Set(snippets.map(\.id)).count == snippets.count, Set(quicklinks.map(\.id)).count == quicklinks.count else { throw MathError.invalid("The pack contains invalid or duplicate entries.") }
        for link in quicklinks { _ = try link.url(query: "test") }
        return self
    }
}

extension History {
    var imageDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true) }
    func imageURL(_ clip: Clip) -> URL? {
        guard let name = clip.imageName, UUID(uuidString: String(name.dropLast(4))) != nil, name.hasSuffix(".png") else { return nil }
        return imageDirectory.appendingPathComponent(name)
    }
    func recordImage(_ image: NSImage, source: String) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let clip = Clip(text: "", source: source, date: Date(), imageName: UUID().uuidString + ".png")
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            guard let location = imageURL(clip) else { return }
            try png.write(to: location, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
            guard appendImage(clip) else { try? FileManager.default.removeItem(at: location); return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(data: png).perform([request])
                    let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                    DispatchQueue.main.async { self?.setRecognizedText(text, id: clip.id) }
                } catch { /* The image remains usable when OCR cannot recognize it. */ }
            }
        } catch { self.error = "Couldn’t store image: \(error.localizedDescription)" }
    }
}

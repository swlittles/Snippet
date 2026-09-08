import Foundation

/// Unbundled `swift run` executions are development builds too.
struct AppEnvironment: Equatable {
    let isDevelopment: Bool
    init(bundleIdentifier: String?) { isDevelopment = bundleIdentifier != "local.snippet.app" }
    var name: String { isDevelopment ? "Snippet Dev" : "Snippet" }
    var bundleIdentifier: String { isDevelopment ? "local.snippet.dev" : "local.snippet.app" }
    func dataURL(_ filename: String, root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) -> URL {
        root.appendingPathComponent(name, isDirectory: true).appendingPathComponent(filename)
    }
    static let current = AppEnvironment(bundleIdentifier: Bundle.main.bundleIdentifier)
    static let defaults: UserDefaults = {
        // The app's own bundle domain belongs to .standard. Opening that domain
        // as a suite can return nil on macOS; suites are only needed unbundled.
        if Bundle.main.bundleIdentifier == current.bundleIdentifier { return .standard }
        return UserDefaults(suiteName: current.bundleIdentifier)!
    }()
}

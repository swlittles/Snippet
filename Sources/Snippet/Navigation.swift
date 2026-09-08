import Foundation

enum LauncherTab: String, CaseIterable {
    case history = "Clipboard", snippets = "Snippets", calculator = "Calculator"
    func cycled(backward: Bool = false) -> LauncherTab {
        let tabs = Self.allCases
        let index = tabs.firstIndex(of: self) ?? 0
        return tabs[(index + (backward ? tabs.count - 1 : 1)) % tabs.count]
    }
    static func command(_ key: String) -> LauncherTab? {
        guard let number = Int(key), (1...3).contains(number) else { return nil }
        return allCases[number - 1]
    }
}

extension LauncherTab {
    var shortcutAction: ShortcutAction {
        switch self { case .history: return .clipboard; case .snippets: return .snippets; case .calculator: return .calculator }
    }
}
enum ResultNavigation {
    static func index(current: Int?, count: Int, backward: Bool, wraps: Bool) -> Int {
        guard count > 0 else { return 0 }
        guard let current else { return backward ? count - 1 : 0 }
        let next = current + (backward ? -1 : 1)
        return wraps ? (next + count) % count : max(0, min(count - 1, next))
    }
}

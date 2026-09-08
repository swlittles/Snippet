import Foundation

/// Outside-click callbacks are asynchronous; an event from an earlier menu
/// session must never dismiss a newly opened menu, even when NSMenu is reused.
struct MenuTrackingSession {
    private(set) var generation = 0
    private var openedAt: TimeInterval?
    mutating func begin(at timestamp: TimeInterval) -> Int {
        generation += 1
        openedAt = timestamp
        return generation
    }
    mutating func end() { openedAt = nil }
    func acceptsOutsideClick(generation: Int, timestamp: TimeInterval) -> Bool {
        guard let openedAt else { return false }
        return generation == self.generation && timestamp > openedAt
    }
}

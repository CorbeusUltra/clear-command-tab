import Foundation

/// Keep a quick MRU flip invisible. Further navigation is deliberate cycling and
/// reveals the panel immediately. The same delay applies to all three modes.
public struct SelectionPresentation: Sendable {
    private var deadline: TimeInterval?
    public init() {}
    public mutating func begin(mode _: SwitcherMode, now: TimeInterval) {
        deadline = now + 0.150
    }
    public mutating func navigate(now: TimeInterval) {
        if deadline != nil { deadline = now }
    }
    public mutating func cancel() { deadline = nil }
    public func permitsDisplay(now: TimeInterval) -> Bool {
        deadline.map { now >= $0 } ?? false
    }
    public func delayRemaining(now: TimeInterval) -> TimeInterval {
        max(0, (deadline ?? now) - now)
    }
}

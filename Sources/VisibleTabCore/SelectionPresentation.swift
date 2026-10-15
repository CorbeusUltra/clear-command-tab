import Foundation

/// Keep a quick MRU flip invisible. Further navigation is deliberate cycling and
/// reveals the panel immediately; window mode retains its immediate presentation.
public struct SelectionPresentation: Sendable {
    private var deadline: TimeInterval?
    public init() {}
    public mutating func begin(mode: SwitcherMode, now: TimeInterval) {
        deadline = mode == .windows ? now : now + 0.150
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

import Foundation

/// One explicit Settings opening owns at most one native focus fallback.
public struct SettingsFocusIntent {
    public private(set) var revision: UInt64 = 0
    private var expiresAt: TimeInterval?
    private var usedFallback = false

    public init() {}

    public mutating func begin(now: TimeInterval) -> UInt64 {
        revision &+= 1
        expiresAt = now + 0.8
        usedFallback = false
        return revision
    }

    public func isCurrent(_ revision: UInt64, now: TimeInterval) -> Bool {
        self.revision == revision && expiresAt.map { now < $0 } == true
    }

    public mutating func takeFallback(_ revision: UInt64, now: TimeInterval) -> Bool {
        guard isCurrent(revision, now: now), !usedFallback else { return false }
        usedFallback = true
        return true
    }

    public mutating func cancel() {
        revision &+= 1
        expiresAt = nil
    }
}

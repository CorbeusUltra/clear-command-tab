import Foundation

/// Own activation notifications can arrive after the next shortcut has started.
/// Only the latest request may complete; a short-lived logical target seeds rapid
/// switching without changing the history before focus has actually been observed.
public struct FocusIntentPolicy: Sendable {
    public private(set) var revision: UInt64 = 0
    private var target: SwitcherTargetID?
    private var expiresAt: TimeInterval = 0
    private var expectedActivations: [Int32: TimeInterval] = [:]
    public init() {}

    public mutating func request(_ target: SwitcherTargetID, now: TimeInterval) -> UInt64 {
        prune(now)
        revision &+= 1
        self.target = target
        expiresAt = now + 0.8
        expectedActivations[target.pid] = expiresAt
        return revision
    }

    public mutating func beginSelection(now: TimeInterval) -> SwitcherTargetID? {
        prune(now)
        let origin = target
        // Cancel work from the previous commit, but still recognize its delayed
        // activation notification. It must not dismiss the newly opened panel.
        cancel(clearNotifications: false)
        return origin
    }

    public mutating func cancel(clearNotifications: Bool = true) {
        revision &+= 1
        target = nil
        if clearNotifications { expectedActivations.removeAll() }
    }

    public func isCurrent(_ revision: UInt64) -> Bool { self.revision == revision }

    @discardableResult
    public mutating func complete(_ revision: UInt64, observed: Bool) -> Bool {
        guard isCurrent(revision) else { return false }
        if !observed { target = nil }
        return true
    }

    public mutating func consumeActivation(pid: Int32, now: TimeInterval) -> Bool {
        prune(now)
        return expectedActivations.removeValue(forKey: pid) != nil
    }

    private mutating func prune(_ now: TimeInterval) {
        expectedActivations = expectedActivations.filter { $0.value > now }
        if expiresAt <= now { target = nil }
    }

    /// Apply the logical origin to a copy of the cached history, never to real MRU.
    public static func prioritizing<ID: Equatable>(_ origin: ID?, in ids: [ID]) -> [ID] {
        guard let origin, ids.contains(origin) else { return ids }
        return [origin] + ids.filter { $0 != origin }
    }
}

/// Discovery begun before a focus transition may contain the old focused window.
public struct WindowSnapshotEpoch: Sendable {
    public private(set) var revision: UInt64 = 0
    public private(set) var transitioning = false
    public init() {}
    public mutating func setTransitioning(_ value: Bool) {
        revision &+= 1
        transitioning = value
    }
    public mutating func invalidate() { revision &+= 1 }
    public func accepts(_ revision: UInt64) -> Bool { self.revision == revision }
    public var canRecordFocus: Bool { !transitioning }
}

/// Wire format for the optional WindowServer key-window bridge. It targets a
/// window ID, far outside its content. A down-only record has no matching click-up.
/// Keep the entire 256-byte buffer zero-initialized, including the trailing bytes.
public enum KeyWindowEventRecord {
    public static func bytes(window: UInt32) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 256)
        result[4] = 248
        result[8] = 1
        result[58] = 16
        var point = CGPoint(x: 300_000, y: 300_000)
        var window = window
        withUnsafeBytes(of: &point) { result.replaceSubrange(32..<48, with: $0) }
        withUnsafeBytes(of: &window) { result.replaceSubrange(60..<64, with: $0) }
        return result
    }
}

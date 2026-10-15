import Foundation

public enum SwitcherTargetID: Hashable, Sendable {
    case application(Int32)
    case window(pid: Int32, number: UInt32)

    public var pid: Int32 {
        switch self {
        case .application(let pid), .window(let pid, _): return pid
        }
    }
}

public struct ShortcutModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
}

public enum SwitcherMode: Sendable {
    case applications, hiddenApplications, windows

    public static func starting(with modifiers: ShortcutModifiers) -> Self? {
        guard !modifiers.contains(.control) else { return nil }
        if modifiers.contains(.command) {
            return modifiers.contains(.option) ? .hiddenApplications : .applications
        }
        return modifiers.contains(.option) ? .windows : nil
    }

    public func isHeld(by modifiers: ShortcutModifiers) -> Bool {
        modifiers.contains(self == .windows ? .option : .command)
    }

    public func permits(_ modifiers: ShortcutModifiers) -> Bool {
        guard !modifiers.contains(.control) else { return false }
        switch self {
        case .applications: return !modifiers.contains(.option)
        // The opening chord fixes the mode; releasing Option before Command is safe.
        case .hiddenApplications: return true
        case .windows: return !modifiers.contains(.command)
        }
    }
}

/// Window recency is separate from app recency; a second window of one app is a target.
public struct WindowHistory: Sendable {
    public private(set) var order: [SwitcherTargetID] = []
    public init() {}

    /// Groups follow the recency of their latest-used window. Within each group, MRU
    /// is preserved. The underlying history remains global so focus updates are cheap.
    public var groupedOrder: [SwitcherTargetID] {
        Self.group(order)
    }

    public func groupedOrder(applicationOrder: [Int32]) -> [SwitcherTargetID] {
        Self.group(order, applicationOrder: applicationOrder)
    }

    public static func group(_ ids: [SwitcherTargetID], applicationOrder: [Int32] = []) -> [SwitcherTargetID] {
        var pids: [Int32] = []
        var windows: [Int32: [SwitcherTargetID]] = [:]
        for id in ids {
            if windows[id.pid] == nil { pids.append(id.pid) }
            windows[id.pid, default: []].append(id)
        }
        var known: Set<Int32> = []
        let orderedPIDs = (applicationOrder + pids).filter { windows[$0] != nil && known.insert($0).inserted }
        return orderedPIDs.flatMap { windows[$0] ?? [] }
    }

    public mutating func update(frontToBack ids: [SwitcherTargetID]) {
        let live = Set(ids)
        order.removeAll { !live.contains($0) }
        var known = Set(order)
        order.append(contentsOf: ids.filter { known.insert($0).inserted })
    }

    public mutating func activate(_ id: SwitcherTargetID?) {
        guard let id, order.contains(id) else { return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }
}

extension SelectionSession where ID == SwitcherTargetID {
    public mutating func regroupWindows() {
        let selected = selectedID
        let grouped = WindowHistory.group(ids)
        guard grouped != ids else { return }
        self = Self(ids: grouped, currentID: nil)
        if let selected { select(selected) }
    }
}

public enum ApplicationSwitch {
    /// Cocoa's isHidden remains cached for the current run-loop turn after unhide.
    /// Treat an accepted unhide as permission to activate; never re-read that stale bit.
    @discardableResult
    public static func commit(revealHidden: Bool, isHidden: Bool, isTerminated: Bool,
                              unhide: () -> Bool, activate: () -> Bool) -> Bool {
        guard !isTerminated else { return false }
        if isHidden {
            guard revealHidden, unhide() else { return false }
        }
        return activate()
    }
}

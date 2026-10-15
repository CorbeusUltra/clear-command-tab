import Foundation

public enum StatusMenuCommand: Equatable, Sendable {
    case settings, quit

    /// Character-based matching respects the current keyboard layout. These are
    /// menu shortcuts, never global shortcuts for the foreground application.
    public static func matching(menuIsOpen: Bool, characters: String?, modifiers: ShortcutModifiers) -> Self? {
        guard menuIsOpen, modifiers == .command else { return nil }
        switch characters?.lowercased() {
        case ",": return .settings
        case "q": return .quit
        default: return nil
        }
    }
}

/// Closing a menu is separate from finishing tracking and returning to the normal
/// application run loop. Keep its requested action until that later stage.
public struct StatusMenuSession: Sendable {
    public private(set) var isTracking = false
    public private(set) var isOpen = false
    private var pending: StatusMenuCommand?

    public init() {}
    public mutating func beginTracking() {
        isTracking = true
        isOpen = false
        pending = nil
    }
    public mutating func menuWillOpen() { isOpen = true }
    public mutating func menuDidClose() { isOpen = false }

    /// True means the caller must defer execution until finishTracking().
    public mutating func deferCommand(_ command: StatusMenuCommand) -> Bool {
        guard isTracking else { return false }
        if pending == nil { pending = command }
        return true
    }

    public mutating func finishTracking() -> StatusMenuCommand? {
        isTracking = false
        isOpen = false
        defer { pending = nil }
        return pending
    }
}

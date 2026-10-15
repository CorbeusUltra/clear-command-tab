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

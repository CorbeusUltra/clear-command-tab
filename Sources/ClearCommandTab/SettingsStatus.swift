/// Presentation state, independent of AppKit and of the wording used in the menu bar.
struct SettingsStatus {
    enum Accessibility: Equatable {
        case notChecked, granted, notGranted

        var title: String {
            switch self {
            case .notChecked: return "Not checked"
            case .granted: return "Granted"
            case .notGranted: return "Not granted"
            }
        }

        var symbol: String {
            switch self {
            case .notChecked: return "questionmark.circle"
            case .granted: return "checkmark.circle.fill"
            case .notGranted: return "xmark.circle.fill"
            }
        }
    }

    enum Switching: Equatable {
        case active, paused, permissionRequired, unavailable, preview

        var title: String {
            switch self {
            case .active: return "Shortcuts: Active"
            case .paused: return "Shortcuts: Paused"
            case .permissionRequired: return "Shortcuts: Inactive"
            case .unavailable: return "Shortcuts: Unavailable"
            case .preview: return "Preview — shortcuts are disabled"
            }
        }
    }

    let accessibility: Accessibility
    let switching: Switching
    let detail: String?
    let yellowButtonFailure: String?
    var showsGrantPermission: Bool { accessibility == .notGranted }

    init(permissionChecked: Bool, accessibilityGranted: Bool, keyboardRunning: Bool,
         paused: Bool, preview: Bool = false, detail: String? = nil,
         yellowButtonFailure: String? = nil) {
        accessibility = permissionChecked && !preview
            ? (accessibilityGranted ? .granted : .notGranted) : .notChecked
        if preview { switching = .preview }
        else if paused { switching = .paused }
        else if !accessibilityGranted { switching = .permissionRequired }
        else { switching = keyboardRunning ? .active : .unavailable }
        self.detail = paused || preview ? nil : detail
        self.yellowButtonFailure = paused || preview ? nil : yellowButtonFailure
    }
}

/// Shared runtime identity. Keep Resources/Info.plist in sync; integration
/// checks compare the packaged metadata with this value.
public enum ApplicationIdentity {
    public static let bundleIdentifier = "io.github.corbeusultra.ClearCommandTab"
    public static let showSettingsNotification = bundleIdentifier + ".showSettings"
}

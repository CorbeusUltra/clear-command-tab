import AppKit
import CryptoKit
import ClearCommandTabCore

if CommandLine.arguments.contains("--diagnostics") {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
    let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    let report: [String: Any] = [
        "accessibilityTrusted": AXIsProcessTrusted(),
        "windowIdentityAvailable": WindowTracker.identityAvailable,
        "nativeFocusAvailable": FocusCoordinator.nativeAvailable,
        "altTabGlassAvailable": GlassProfile.altTabAvailable,
        "glassProfile": GlassProfile.selected.rawValue,
        "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
        "dockBadges": dockPID.map { DockBadgeReader().snapshot(dockPID: $0) } ?? [:],
        "applications": apps.map {
            let icon = ApplicationIcon.resolve($0, pixels: 320)
            let digest = icon?.dataProvider?.data.map {
                SHA256.hash(data: $0 as Data).map { String(format: "%02x", $0) }.joined()
            } ?? ""
            return ["pid": $0.processIdentifier, "name": $0.localizedName ?? "Application",
             "bundleIdentifier": $0.bundleIdentifier ?? "", "hidden": $0.isHidden,
             "bundlePath": $0.bundleURL?.path ?? "", "executablePath": $0.executableURL?.path ?? "",
             "iconPixels": icon?.width ?? 0, "iconDigest": digest] as [String: Any]
        },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else {
    let bundleID = Bundle.main.bundleIdentifier
    let otherInstance = bundleID.flatMap { id in
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated &&
                ApplicationTracker.processIsRunning($0.processIdentifier)
        }
    }
    if otherInstance != nil {
        DistributedNotificationCenter.default().postNotificationName(.init(ApplicationIdentity.showSettingsNotification),
                                                                    object: nil, userInfo: nil, deliverImmediately: true)
    } else {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            let delegate = AppController()
            application.delegate = delegate
            application.run()
            withExtendedLifetime(delegate) {}
        }
    }
}

import AppKit

if CommandLine.arguments.contains("--diagnostics") {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
    let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    let report: [String: Any] = [
        "accessibilityTrusted": AXIsProcessTrusted(),
        "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
        "dockBadges": dockPID.map { DockBadgeReader().snapshot(dockPID: $0) } ?? [:],
        "applications": apps.map {
            ["pid": $0.processIdentifier, "name": $0.localizedName ?? "Application",
             "bundleIdentifier": $0.bundleIdentifier ?? "", "hidden": $0.isHidden] as [String: Any]
        },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else {
    let bundleID = Bundle.main.bundleIdentifier
    let otherInstance = bundleID.flatMap { id in
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
        }
    }
    if otherInstance != nil {
        DistributedNotificationCenter.default().postNotificationName(.init("local.lucas.VisibleTab.showSettings"),
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

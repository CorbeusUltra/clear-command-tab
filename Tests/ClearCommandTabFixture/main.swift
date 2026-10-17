import AppKit

/// Disposable, document-free windows for opt-in live integration checks.
@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ClearCommandTab Test"
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        let argument = CommandLine.arguments.first { $0.hasPrefix("--windows=") }
        let count = min(3, max(1, argument.flatMap { Int($0.dropFirst("--windows=".count)) } ?? 1))
        for index in 0..<count {
            let window = NSWindow(contentRect: NSRect(x: 120 + index * 35, y: 130 + index * 35, width: 420, height: 180),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "\(name) — \(index + 1)"
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Disposable integration fixture — no user documents.")
            label.frame = NSRect(x: 20, y: 90, width: 380, height: 40)
            label.maximumNumberOfLines = 2
            window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate()
        // A crashed test runner must never leave an indefinite overlay behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.first?.deminiaturize(nil)
        windows.first?.makeKeyAndOrderFront(nil)
        return false
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = FixtureDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}

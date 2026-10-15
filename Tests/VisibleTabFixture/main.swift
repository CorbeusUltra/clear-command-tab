import AppKit

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VisibleTab Test"
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 180),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Disposable test application — no documents or saved data.")
        label.frame = NSRect(x: 20, y: 105, width: 380, height: 40)
        label.maximumNumberOfLines = 2
        window.contentView?.addSubview(label)
        let minimize = NSButton(title: "Minimize window", target: self, action: #selector(minimizeWindow))
        minimize.frame = NSRect(x: 20, y: 55, width: 165, height: 30)
        window.contentView?.addSubview(minimize)
        let close = NSButton(title: "Close window", target: self, action: #selector(closeWindow))
        close.frame = NSRect(x: 200, y: 55, width: 165, height: 30)
        window.contentView?.addSubview(close)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        return false
    }
    @objc private func minimizeWindow() { window.miniaturize(nil) }
    @objc private func closeWindow() { window.close() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = FixtureDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}

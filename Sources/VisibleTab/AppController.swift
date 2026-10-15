import AppKit
import Carbon
import VisibleTabCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, KeyboardTapDelegate {
    private let tracker = ApplicationTracker()
    private let keyboard = KeyboardTap()
    private let panel = SwitcherPanel()
    private let settings = SettingsWindow()
    private let badgeReader = DockBadgeReader()
    private var badges: [String: String] = [:]
    private var badgeRefresh: Timer?
    private var badgeReadInFlight = false
    private var session: SwitcherSession?
    private var ownership = KeyOwnership()
    private var displayWork: DispatchWorkItem?
    private var sessionWatchdog: Timer?
    private var sessionScreen: NSScreen?
    private var hiddenForeground: NSRunningApplication?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var paused = false
    private var status = ""
    private var observers: [NSObjectProtocol] = []
    private let preview = CommandLine.arguments.contains("--preview")
    private var previewSelection: Int32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])
        keyboard.delegate = self
        tracker.onChange = { [weak self] activated in
            guard let self else { return }
            if self.preview { self.renderPreview(); return }
            if activated {
                // H can hide the foreground app while cycling; its automatic successor
                // must not cancel the switcher like an unrelated user activation would.
                if self.hiddenForeground?.isHidden == true {
                    self.hiddenForeground = nil
                    self.reconcileSelection()
                } else { self.cancelSelection() }
            }
            else { self.reconcileSelection() }
            // Recheck after a trip to System Settings without idle permission polling.
            if activated && !self.paused && !self.keyboard.isRunning && !self.preview {
                self.checkPermission()
            }
        }
        panel.onSelect = { [weak self] id, activate in
            guard let self else { return }
            if self.preview { self.previewSelection = id; self.renderPreview(); return }
            guard self.session != nil else { return }
            self.session?.select(id)
            if activate { self.finishSelection() }
            else { self.renderSelection() }
        }
        settings.onShowIcon = { [weak self] visible in
            UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
            self?.updateControls()
        }
        settings.onTogglePause = { [weak self] in self?.togglePause() }
        settings.onCheckPermission = { [weak self] in self?.checkPermission() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenFromNotification),
                                                             name: .init("local.lucas.VisibleTab.showSettings"), object: nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelSelection() }
            })
        }
        NotificationCenter.default.addObserver(self, selector: #selector(checkPermission),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        if preview {
            if CommandLine.arguments.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            else if CommandLine.arguments.contains("--preview-light") { NSApp.appearance = NSAppearance(named: .aqua) }
            status = "Preview only. Keyboard interception is disabled."
            updateControls()
            sessionScreen = foregroundScreen()
            panel.isMovableByWindowBackground = true
            // A nonactivating preview cannot receive Escape reliably. Give every preview
            // a bounded lifetime so it can never leave an uncloseable overlay on screen.
            let lifetimeArgument = CommandLine.arguments.first { $0.hasPrefix("--preview-duration=") }
            let lifetime = min(30, max(2, lifetimeArgument.flatMap {
                Double($0.dropFirst("--preview-duration=".count))
            } ?? 6))
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { NSApp.terminate(nil) }
            renderPreview()
        } else {
            checkPermission()
            if !keyboard.isRunning { showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if preview { renderPreview() } else { showSettings() }
        return false
    }

    private func renderPreview() {
        let originals = tracker.history.visible
        guard !originals.isEmpty, let screen = sessionScreen ?? NSScreen.main else { return }
        let argument = CommandLine.arguments.first { $0.hasPrefix("--preview-count=") }
        let count = min(100, max(1, argument.flatMap { Int($0.dropFirst("--preview-count=".count)) } ?? originals.count))
        let items = (0..<count).map { index in
            let app = originals[index % originals.count]
            return SwitcherItem(id: Int32(index + 1), name: app.name, icon: tracker.icons[app.id])
        }
        let selected = previewSelection.flatMap { id in items.contains { $0.id == id } ? id : nil } ?? items.first?.id
        panel.display(items: items, selected: selected, screen: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboard.stop()
        cancelSelection()
        tracker.save()
    }

    @objc private func reopenFromNotification() { showSettings() }

    @objc private func showSettings() {
        checkPermission()
        updateControls()
        settings.showWindow(nil)
        NSApp.activate()
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkPermission() {
        guard !preview else { updateControls(); return }
        if paused { status = "Paused. Command-Tab is handled by macOS." }
        else if keyboard.start() { status = "Ready. Command-Tab excludes hidden apps." }
        else if !AXIsProcessTrusted() {
            status = "Accessibility permission is required. Grant permission, then click Check permission."
        } else {
            status = "Could not intercept the keyboard. Command-Tab is handled by macOS. Try Check permission."
        }
        updateControls()
    }

    @objc private func togglePause() {
        paused.toggle()
        if paused {
            cancelSelection()
            ownership.reset()
            keyboard.stop()
        }
        checkPermission()
    }

    private func updateControls() {
        let visible = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        if visible && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "VisibleTab")
            image?.isTemplate = true
            item.button?.image = image
            let menu = NSMenu()
            let state = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            state.tag = 1
            menu.addItem(state)
            menu.addItem(.separator())
            let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
            pause.target = self
            pauseMenuItem = pause
            menu.addItem(pause)
            let preferences = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
            preferences.target = self
            menu.addItem(preferences)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: preview ? "Quit Preview" : "Quit VisibleTab",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            item.menu = menu
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            pauseMenuItem = nil
        }
        statusItem?.button?.toolTip = "VisibleTab — \(status)"
        statusItem?.button?.appearsDisabled = paused || (!preview && !keyboard.isRunning)
        statusItem?.menu?.item(withTag: 1)?.title = paused ? "Paused" : keyboard.isRunning ? "Ready" : "Permission required"
        pauseMenuItem?.title = paused ? "Resume" : "Pause"
        settings.update(status: status, paused: paused, iconVisible: visible)
    }

    func keyboardUnavailable(_ reason: String) {
        cancelSelection()
        ownership.reset()
        status = reason
        updateControls()
    }

    func keyboardInputInterrupted() {
        cancelSelection()
        ownership.reset()
    }

    func handleKey(type: CGEventType, event: CGEvent) -> Bool {
        if type == .keyUp { return ownership.consumeUp(UInt16(event.getIntegerValueField(.keyboardEventKeycode))) }
        if type == .flagsChanged {
            if session != nil && !event.flags.contains(.maskCommand) { finishSelection() }
            return false
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            if session != nil && !panel.containsQuartzPoint(event.location) { cancelSelection() }
            return false
        }
        guard type == .keyDown else { return false }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let extraModifiers = flags.contains(.maskAlternate) || flags.contains(.maskControl)
        if key == UInt16(kVK_Tab) && command && !extraModifiers {
            if session == nil { beginSelection(backwards: flags.contains(.maskShift)) }
            else { session?.advance(flags.contains(.maskShift) ? -1 : 1); renderIfVisible() }
            ownership.consumeDown(key)
            return true
        }
        guard session != nil else { return false }
        if extraModifiers {
            // Option/Control shortcuts belong to the foreground application.
            cancelSelection()
            return false
        }
        var handled = true
        switch Int(key) {
        case kVK_Escape: cancelSelection()
        case kVK_LeftArrow, kVK_ANSI_Grave: session?.advance(-1); renderIfVisible()
        case kVK_RightArrow: session?.advance(1); renderIfVisible()
        default:
            // Resolve letters through the current layout instead of assuming QWERTY.
            let letter = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
            if letter == "h", let id = session?.selectedID {
                if id == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    hiddenForeground = tracker.applications[id]
                }
                if tracker.applications[id]?.hide() == true {
                    let visible = tracker.history.visible.map(\.id).filter { $0 != id }
                    session?.reconcile(visibleIDs: visible)
                    if session?.selectedID == nil { cancelSelection() } else { renderIfVisible() }
                } else { hiddenForeground = nil }
            } else if letter == "q", let id = session?.selectedID {
                // Never force quit; unsaved-document prompts remain the app's responsibility.
                _ = tracker.applications[id]?.terminate()
            } else {
                cancelSelection()
                handled = false
            }
        }
        if handled { ownership.consumeDown(key) }
        return handled
    }

    private func beginSelection(backwards: Bool) {
        session = SwitcherSession(ids: tracker.history.visible.map(\.id),
                                  currentID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                  backwards: backwards)
        guard session?.selectedID != nil else { cancelSelection(); return }
        sessionScreen = foregroundScreen()
        refreshBadges()
        badgeRefresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBadges() }
        }
        if let badgeRefresh { RunLoop.main.add(badgeRefresh, forMode: .common) }
        let work = DispatchWorkItem { [weak self] in self?.renderSelection() }
        displayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        // This timer exists only while cycling, to prevent a stuck overlay if Secure Input
        // swallows the modifier release. There is no timer while idle.
        sessionWatchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if IsSecureEventInputEnabled() { self.keyboardInputInterrupted() }
                else if !NSEvent.modifierFlags.contains(.command) { self.finishSelection() }
            }
        }
        if let sessionWatchdog { RunLoop.main.add(sessionWatchdog, forMode: .common) }
    }

    private func reconcileSelection() {
        session?.reconcile(visibleIDs: tracker.history.visible.map(\.id))
        if session?.selectedID == nil { cancelSelection() }
        else { renderIfVisible() }
    }

    private func renderIfVisible() { if panel.isVisible { renderSelection() } }

    private func renderSelection() {
        guard let session, let screen = sessionScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel.display(ids: session.ids, selected: session.selectedID, tracker: tracker, badges: badges, screen: screen)
    }

    private func refreshBadges() {
        guard session != nil, !badgeReadInFlight,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        badgeReadInFlight = true
        badgeReader.read(dockPID: dock.processIdentifier) { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.badgeReadInFlight = false
                guard self.badges != snapshot else { return }
                self.badges = snapshot
                self.renderIfVisible()
            }
        }
    }

    private func finishSelection() {
        let selected = session?.selectedID
        cancelSelection()
        guard let selected, let app = tracker.applications[selected], !app.isHidden, !app.isTerminated else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != selected else { return }
        if !app.activate(options: [.activateAllWindows]) { NSSound.beep() }
    }

    func cancelSelection() {
        displayWork?.cancel()
        displayWork = nil
        sessionWatchdog?.invalidate()
        sessionWatchdog = nil
        badgeRefresh?.invalidate()
        badgeRefresh = nil
        session = nil
        sessionScreen = nil
        hiddenForeground = nil
        panel.orderOut(nil)
    }

    private func foregroundScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return NSScreen.main }
        for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == pid &&
            window[kCGWindowLayer as String] as? Int == 0 {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let center = NSPoint(x: rect.midX, y: top - rect.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        }
        return NSScreen.main
    }
}

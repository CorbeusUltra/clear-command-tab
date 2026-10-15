import AppKit
import Carbon
import VisibleTabCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, KeyboardTapDelegate {
    private let tracker = ApplicationTracker()
    private let keyboard = KeyboardTap()
    private let windows = WindowTracker()
    private let panel = SwitcherPanel()
    private let settings = SettingsWindow()
    private let badgeReader = DockBadgeReader()
    private var badges: [String: String] = [:]
    private var badgeRefresh: Timer?
    private var badgeReadInFlight = false
    private var session: SelectionSession<SwitcherTargetID>?
    private var sessionMode: SwitcherMode?
    private var selectionGeneration = 0
    private var pendingWindowAdvances: Int?
    private var pendingWindowBackwards = false
    private var ownership = KeyOwnership()
    private var displayWork: DispatchWorkItem?
    private var sessionWatchdog: Timer?
    private var sessionScreen: NSScreen?
    private var hiddenForeground: NSRunningApplication?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var statusMenu: NSMenu?
    private var paused = false
    private var status = ""
    private var observers: [NSObjectProtocol] = []
    private let preview = CommandLine.arguments.contains("--preview")
    private var cachedForegroundScreen: NSScreen?
    private let screenQueue = DispatchQueue(label: "local.lucas.VisibleTab.screen", qos: .utility)
    private var previewSelection: SwitcherTargetID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true, GlassProfile.preferenceKey: "altTab"])
        keyboard.delegate = self
        updateForegroundScreen()
        tracker.onIconsChanged = { [weak self] in
            guard let self else { return }
            if self.preview { self.renderPreview() } else { self.renderIfVisible() }
        }
        tracker.onChange = { [weak self] activated in
            guard let self else { return }
            if self.preview { self.renderPreview(); return }
            if activated {
                self.updateForegroundScreen()
                // H can hide the foreground app while cycling; its automatic successor
                // must not cancel the switcher like an unrelated user activation would.
                if self.hiddenForeground?.isHidden == true {
                    self.hiddenForeground = nil
                    self.reconcileSelection()
                } else { self.cancelSelection() }
            }
            else { self.reconcileSelection() }
            self.refreshWindows()
            // Recheck after a trip to System Settings without idle permission polling.
            if activated && !self.paused && !self.keyboard.isRunning && !self.preview {
                self.checkPermission()
            }
        }
        windows.onChange = { [weak self] in
            guard let self else { return }
            if let bounds = self.windows.foregroundBounds { self.cacheForegroundScreen(bounds) }
            guard self.sessionMode == .windows, self.session != nil else { return }
            self.reconcileSelection()
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
        settings.onGlassProfile = { [weak self] profile in
            UserDefaults.standard.set(profile.rawValue, forKey: GlassProfile.preferenceKey)
            self?.panel.applyGlassProfile(profile)
            if self?.preview == true { self?.renderPreview() }
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
                MainActor.assumeIsolated {
                    self?.cancelSelection()
                    self?.windows.invalidateSnapshot()
                    self?.updateForegroundScreen()
                    self?.refreshWindows()
                }
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
            return SwitcherItem(id: .application(Int32(index + 1)), name: app.name, icon: tracker.icons[app.id])
        }
        let selected = previewSelection.flatMap { id in items.contains { $0.id == id } ? id : nil } ?? items.first?.id
        panel.display(items: items, selected: selected, screen: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboard.stop()
        windows.setEnabled(false)
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
        else if keyboard.start() {
            status = WindowTracker.identityAvailable
                ? "Ready. ⌘Tab: visible apps · ⌘⌥Tab: hidden apps · ⌥Tab: windows."
                : "Ready for app switching. Option-Tab is unavailable: window identity is not supported on this macOS."
        }
        else if !AXIsProcessTrusted() {
            status = "Accessibility permission is required. Grant permission, then click Check permission."
        } else {
            status = "Could not intercept the keyboard. Command-Tab is handled by macOS. Try Check permission."
        }
        windows.setEnabled(keyboard.isRunning && !paused)
        refreshWindows()
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
            statusMenu = menu
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            pauseMenuItem = nil
            statusMenu = nil
        }
        statusItem?.button?.toolTip = "VisibleTab — \(status)\nClick to \(paused ? "resume" : "pause"); right-click for Settings and Quit."
        let symbol = (!paused && !preview && !keyboard.isRunning) ? "exclamationmark.circle" : "arrow.left.arrow.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: paused ? "VisibleTab paused" : "VisibleTab enabled")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = paused || (!preview && !keyboard.isRunning)
        statusMenu?.item(withTag: 1)?.title = paused ? "Paused" : keyboard.isRunning ? "Ready" : "Permission required"
        pauseMenuItem?.title = paused ? "Resume" : "Pause"
        settings.update(status: status, paused: paused, iconVisible: visible, glassProfile: GlassProfile.selected)
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            if let button = statusItem?.button, let menu = statusMenu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            }
        } else { togglePause() }
    }

    private func refreshWindows(completion: (() -> Void)? = nil) {
        windows.refresh(applications: tracker.windowInputs,
                        frontmost: tracker.frontmostPID, completion: completion)
    }

    func keyboardUnavailable(_ reason: String) {
        cancelSelection()
        ownership.reset()
        windows.setEnabled(false)
        status = reason
        updateControls()
    }

    func keyboardInputInterrupted() {
        cancelSelection()
        ownership.reset()
    }

    private func modifiers(_ flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
    }

    private var heldModifiers: ShortcutModifiers {
        modifiers(CGEventFlags(rawValue: UInt64(NSEvent.modifierFlags.rawValue)))
    }

    func handleKey(type: CGEventType, event: CGEvent) -> Bool {
        if type == .keyUp { return ownership.consumeUp(UInt16(event.getIntegerValueField(.keyboardEventKeycode))) }
        if type == .flagsChanged {
            if let mode = sessionMode, !mode.isHeld(by: modifiers(event.flags)) { finishSelection() }
            return false
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            if sessionMode != nil && !panel.containsQuartzPoint(event.location) { cancelSelection() }
            return false
        }
        guard type == .keyDown else { return false }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = modifiers(event.flags)
        if key == UInt16(kVK_Tab) {
            if let mode = sessionMode {
                guard mode.permits(flags), mode.isHeld(by: flags) else { cancelSelection(); return false }
                let direction = flags.contains(.shift) ? -1 : 1
                if session != nil { session?.advance(direction); renderIfVisible() }
                else if pendingWindowAdvances != nil { pendingWindowAdvances! += direction }
            } else {
                guard let mode = SwitcherMode.starting(with: flags),
                      mode != .windows || WindowTracker.identityAvailable else { return false }
                beginSelection(mode: mode, backwards: flags.contains(.shift))
            }
            ownership.consumeDown(key)
            return true
        }
        guard let mode = sessionMode else { return false }
        guard mode.permits(flags), mode.isHeld(by: flags) else { cancelSelection(); return false }
        var handled = true
        switch Int(key) {
        case kVK_Escape: cancelSelection()
        case kVK_LeftArrow, kVK_ANSI_Grave:
            if session != nil { session?.advance(-1); renderIfVisible() }
            else if pendingWindowAdvances != nil { pendingWindowAdvances! -= 1 }
        case kVK_RightArrow:
            if session != nil { session?.advance(1); renderIfVisible() }
            else if pendingWindowAdvances != nil { pendingWindowAdvances! += 1 }
        default:
            let letter = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
            if mode == .applications, letter == "h", let id = session?.selectedID {
                if id.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    hiddenForeground = tracker.applications[id.pid]
                }
                if tracker.applications[id.pid]?.hide() == true {
                    session?.reconcile(visibleIDs: candidateIDs().filter { $0 != id })
                    if session?.selectedID == nil { cancelSelection() } else { renderIfVisible() }
                } else { hiddenForeground = nil }
            } else if mode == .applications, letter == "q", let id = session?.selectedID {
                _ = tracker.applications[id.pid]?.terminate()
            } else {
                cancelSelection()
                handled = false
            }
        }
        if handled { ownership.consumeDown(key) }
        return handled
    }

    private func candidateIDs() -> [SwitcherTargetID] {
        switch sessionMode {
        case .applications: return tracker.history.visible.map { .application($0.id) }
        case .hiddenApplications: return tracker.history.hidden.map { .application($0.id) }
        case .windows:
            let visiblePIDs = Set(tracker.history.visible.map(\.id))
            return windows.history.groupedOrder(applicationOrder: tracker.history.order).filter { visiblePIDs.contains($0.pid) }
        case nil: return []
        }
    }

    private var currentWindowID: SwitcherTargetID? {
        windows.focusedID ?? windows.history.order.first { $0.pid == tracker.frontmostPID }
    }

    private func beginSelection(mode: SwitcherMode, backwards: Bool) {
        selectionGeneration += 1
        let generation = selectionGeneration
        sessionMode = mode
        sessionScreen = foregroundScreen()
        if mode == .windows, windows.history.order.isEmpty {
            pendingWindowAdvances = 0
            pendingWindowBackwards = backwards
        } else {
            let current = mode == .windows ? currentWindowID :
                tracker.frontmostPID.map { SwitcherTargetID.application($0) }
            session = SelectionSession(ids: candidateIDs(), currentID: current, backwards: backwards)
            guard session?.selectedID != nil else { cancelSelection(); return }
        }
        refreshBadges()
        badgeRefresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBadges() }
        }
        if let badgeRefresh { RunLoop.main.add(badgeRefresh, forMode: .common) }
        let work = DispatchWorkItem { [weak self] in self?.renderSelection() }
        displayWork = work
        DispatchQueue.main.async(execute: work)
        sessionWatchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let mode = self.sessionMode else { return }
                if IsSecureEventInputEnabled() { self.keyboardInputInterrupted() }
                else if !mode.isHeld(by: self.heldModifiers) { self.finishSelection() }
            }
        }
        if let sessionWatchdog { RunLoop.main.add(sessionWatchdog, forMode: .common) }
        if mode == .windows && pendingWindowAdvances != nil {
            refreshWindows { [weak self] in
                guard let self, self.selectionGeneration == generation, self.sessionMode == .windows else { return }
                if let advances = self.pendingWindowAdvances {
                    guard mode.isHeld(by: self.heldModifiers) else { self.cancelSelection(); return }
                    self.session = SelectionSession(ids: self.candidateIDs(), currentID: self.currentWindowID,
                                                    backwards: self.pendingWindowBackwards)
                    self.session?.advance(advances)
                    self.pendingWindowAdvances = nil
                    guard self.session?.selectedID != nil else { self.cancelSelection(); return }
                    self.renderSelection()
                } else { self.reconcileSelection() }
            }
            // Cold discovery cannot activate a window long after an abandoned shortcut.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.selectionGeneration == generation, self.pendingWindowAdvances != nil else { return }
                self.cancelSelection()
            }
        }
    }

    private func reconcileSelection() {
        guard session != nil else { return }
        session?.reconcile(visibleIDs: candidateIDs())
        if sessionMode == .windows { session?.regroupWindows() }
        if session?.selectedID == nil { cancelSelection() }
        else { renderIfVisible() }
    }

    private func renderIfVisible() { if panel.isVisible { renderSelection() } }

    private func renderSelection() {
        guard let session, let screen = sessionScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let items = session.ids.map { id -> SwitcherItem in
            let app = tracker.presentations[id.pid]
            let title = sessionMode == .windows ? windows.records[id]?.title : nil
            return SwitcherItem(id: id, name: app?.name ?? "Application", icon: tracker.icons[id.pid],
                                badge: app?.bundleIdentifier.flatMap { badges[$0] },
                                windowTitle: title.map { $0.isEmpty ? "Untitled window" : $0 })
        }
        panel.applyGlassProfile(GlassProfile.selected)
        panel.display(items: items, selected: session.selectedID, screen: screen)
    }

    private func refreshBadges() {
        guard sessionMode != nil, !badgeReadInFlight,
              let dockPID = tracker.dockPID else { return }
        badgeReadInFlight = true
        badgeReader.read(dockPID: dockPID) { [weak self] snapshot in
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
        if session == nil, pendingWindowAdvances != nil {
            // Never turn a quick release into a delayed activation after cold discovery.
            cancelSelection()
            return
        }
        let selected = session?.selectedID, mode = sessionMode
        cancelSelection()
        guard let selected, let app = tracker.applications[selected.pid], !app.isTerminated else { return }
        if mode == .windows {
            windows.focus(selected, app: app) { success in if !success { NSSound.beep() } }
        } else {
            if mode == .applications, tracker.frontmostPID == selected.pid { return }
            let accepted = ApplicationSwitch.commit(revealHidden: mode == .hiddenApplications,
                                                     isHidden: app.isHidden, isTerminated: app.isTerminated,
                                                     unhide: { app.unhide() },
                                                     activate: { app.activate(options: [.activateAllWindows]) })
            if !accepted { NSSound.beep() }
        }
    }

    func cancelSelection() {
        selectionGeneration += 1
        displayWork?.cancel()
        displayWork = nil
        sessionWatchdog?.invalidate()
        sessionWatchdog = nil
        badgeRefresh?.invalidate()
        badgeRefresh = nil
        session = nil
        sessionMode = nil
        pendingWindowAdvances = nil
        sessionScreen = nil
        hiddenForeground = nil
        panel.orderOut(nil)
    }

    private func foregroundScreen() -> NSScreen? {
        cachedForegroundScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func cacheForegroundScreen(_ rect: CGRect) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let center = NSPoint(x: rect.midX, y: top - rect.midY)
        cachedForegroundScreen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func updateForegroundScreen() {
        if NSScreen.screens.count == 1 { cachedForegroundScreen = NSScreen.screens.first; return }
        guard let pid = tracker.frontmostPID else { return }
        screenQueue.async { [weak self] in
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            let bounds = windows.first { $0[kCGWindowOwnerPID as String] as? Int32 == pid &&
                $0[kCGWindowLayer as String] as? Int == 0 }?[kCGWindowBounds as String] as? NSDictionary
            let rect = bounds.flatMap { CGRect(dictionaryRepresentation: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.tracker.frontmostPID == pid, let rect else { return }
                self.cacheForegroundScreen(rect)
            }
        }
    }
}

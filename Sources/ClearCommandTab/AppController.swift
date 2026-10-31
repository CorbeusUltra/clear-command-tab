import AppKit
import Carbon
import os
import ClearCommandTabCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, KeyboardTapDelegate, NSMenuDelegate {
    private let tracker = ApplicationTracker()
    private let keyboard = KeyboardTap()
    private var yellowButtonFailure: String?
    private lazy var yellowButton = YellowButtonInterceptor(onHide: { [weak self] pid in
        guard let self, !self.paused, !self.preview,
              UserDefaults.standard.bool(forKey: YellowButtonInterceptor.preferenceKey),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        self.settingsFocus.cancel()
        self.cancelSelection()
        self.focus.cancel(reason: "yellow-button")
        let accepted = app.hide()
        Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "YellowButton")
            .debug("hide request pid=\(pid) accepted=\(accepted)")
        if !accepted && !app.isHidden {
            Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "YellowButton").error("Hide request was rejected")
            self.yellowButtonFailure = "The selected app did not accept Hide. Its windows were not minimized."
            self.updateControls()
        }
    }, onStatus: { [weak self] message in
        guard let self else { return }
        self.yellowButtonFailure = message
        let logger = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "YellowButton")
        if let message { logger.notice("mouse interception: \(message, privacy: .public)") }
        else { logger.debug("mouse interception: Ready") }
        self.updateControls()
    })
    // Window titles are unused while window-only switching is parked.
    private let windows = WindowTracker(tracksTitles: false)
    private let focus = FocusCoordinator()
    private let panel = SwitcherPanel()
    private let settings = SettingsWindow()
    private let settingsFocus = SettingsFocusCoordinator()
    private let badgeReader = DockBadgeReader()
    private var badges: [String: String] = [:]
    private var badgeRefresh: Timer?
    private var badgeReadInFlight = false
    private var session: SelectionSession<SwitcherTargetID>?
    private var sessionMode: SwitcherMode?
    private var selectionOrigin: SwitcherTargetID?
    private var selectionGeneration = 0
    private var pendingWindowAdvances: Int?
    private var pendingWindowBackwards = false
    private var ownership = KeyOwnership()
    private var displayWork: DispatchWorkItem?
    private var presentation = SelectionPresentation()
    private var sessionWatchdog: Timer?
    private var sessionScreen: NSScreen?
    private var hiddenForeground: NSRunningApplication?
    private var statusItem: NSStatusItem?
    private let menuIcon: NSImage? = {
        let image = Bundle.main.url(forResource: "ClearCommandTab-menu", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "arrow.right.arrow.left", accessibilityDescription: ApplicationIdentity.displayName)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = ApplicationIdentity.displayName
        return image
    }()
    private var statusItemVisibilityObservation: NSKeyValueObservation?
    private var statusMenu: NSMenu?
    private var statusMenuSession = StatusMenuSession()
    private var statusMenuOwnedKeys: Set<UInt16> = []
    private let settingsLog = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "Settings")
    private var paused = false
    private var status = ""
    private var reportedStatus: String?
    private var observers: [NSObjectProtocol] = []
    private let preview = CommandLine.arguments.contains("--preview")
    private var cachedForegroundScreen: NSScreen?
    private let screenQueue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".screen", qos: .utility)
    private var previewSelection: SwitcherTargetID?
    private var launchCompleted = false
    private var pendingSettingsOpen = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
            andSelector: #selector(openApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenApplication))
    }

    @objc private func openApplication(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard !preview, ApplicationLaunch.opensSettings(event) else { return }
        if launchCompleted { showSettings() }
        else { pendingSettingsOpen = true }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true, GlassProfile.preferenceKey: "altTab",
                                                  YellowButtonInterceptor.preferenceKey: false])
        keyboard.delegate = self
        focus.onTransition = { [weak self] active in self?.windows.setFocusTransition(active) }
        focus.onConfirmed = { [weak self] target, window in
            guard let self else { return }
            self.tracker.recordConfirmedActivation(target.pid)
            self.windows.recordConfirmedFocus(pid: target.pid, window: window)
        }
        updateForegroundScreen()
        tracker.onIconsChanged = { [weak self] in
            guard let self else { return }
            if self.preview { self.renderPreview() } else { self.renderIfVisible() }
        }
        tracker.onChange = { [weak self] activated in
            guard let self else { return }
            if self.preview { self.renderPreview(); return }
            if activated {
                self.settingsFocus.foregroundChanged(to: self.tracker.frontmostPID)
                self.updateForegroundScreen()
                // H can hide the foreground app while cycling; its automatic successor
                // must not cancel the switcher like an unrelated user activation would.
                if let pid = self.tracker.frontmostPID, self.focus.consumeActivation(pid: pid) {
                    // This may acknowledge the previous commit while another
                    // selection is already open. Keep that selection intact.
                    self.reconcileSelection()
                } else if self.hiddenForeground?.isHidden == true {
                    self.hiddenForeground = nil
                    self.reconcileSelection()
                } else { self.cancelSelection() }
            }
            else { self.reconcileSelection() }
            self.refreshWindows()
            // An app can terminate without a successor activation notification.
            // Recover on any lifecycle change, without retaining a stale gesture.
            if !self.paused && !self.keyboard.isRunning && !self.preview {
                self.keyboardInputInterrupted()
                self.checkPermission()
            }
        }
        windows.onChange = { [weak self] in
            guard let self else { return }
            self.yellowButton.setCandidateRegions(self.windows.minimizeButtonsReady ? self.windows.minimizeButtonRegions : nil)
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
        panel.onViewportChanged = { [weak self] in
            guard let self, self.panel.isVisible, self.session != nil else { return }
            self.tracker.setVisibleIconTargets(self.panel.visibleApplicationPIDs, selected: self.session?.selectedID?.pid)
        }
        settings.onShowIcon = { [weak self] visible in
            UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
            self?.updateControls()
            // Re-show the existing item explicitly. Recreating an item can simply
            // restore the same hidden state from AppKit's autosaved visibility.
            self?.statusItem?.isVisible = visible
        }
        settings.onGlassProfile = { [weak self] profile in
            UserDefaults.standard.set(profile.rawValue, forKey: GlassProfile.preferenceKey)
            self?.panel.applyGlassProfile(profile)
            if self?.preview == true { self?.renderPreview() }
            self?.updateControls()
        }
        settings.onTogglePause = { [weak self] in self?.togglePause() }
        settings.onClose = { [weak self] in self?.settingsFocus.cancel() }
        settings.onYellowButton = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: YellowButtonInterceptor.preferenceKey)
            self?.checkPermission()
        }
        settings.onCheckPermission = { [weak self] in
            self?.checkPermission()
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenFromNotification),
                                                             name: .init(ApplicationIdentity.showSettingsNotification), object: nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.settingsFocus.cancel()
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
            launchCompleted = true
            if pendingSettingsOpen || !keyboard.isRunning { showSettings() }
            pendingSettingsOpen = false
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
        settingsFocus.cancel()
        statusItemVisibilityObservation?.invalidate()
        keyboard.stop()
        windows.setEnabled(false)
        cancelSelection()
        tracker.save()
    }

    @objc private func reopenFromNotification() { showSettings() }

    @objc private func showSettings() {
        presentSettingsPage(.settings, command: .settings)
    }

    @objc private func showAbout() { presentSettingsPage(.about, command: .about) }
    @objc private func showGuide() { presentSettingsPage(.guide, command: .guide) }

    private func presentSettingsPage(_ page: SettingsWindow.Page, command: StatusMenuCommand) {
        if statusMenuSession.deferCommand(command) {
            settingsLog.debug("request deferred until menu tracking ends")
            return
        }
        checkPermission()
        updateControls()
        cancelSelection()
        settings.selectPage(page)
        settings.showWindow(nil)
        if let window = settings.window { settingsFocus.present(window) }
        settingsLog.debug("present visible=\(self.settings.window?.isVisible == true) key=\(self.settings.window?.isKeyWindow == true) active=\(NSApp.isActive)")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settingsFocus.applicationDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) { settingsFocus.cancel() }

    @objc private func checkPermission() {
        guard !preview else { updateControls(); return }
        let trusted = AXIsProcessTrusted()
        if !trusted {
            cancelSelection()
            ownership.reset()
            keyboard.stop()
        }
        if paused { status = "Paused. Command-Tab is handled by macOS." }
        else if keyboard.start() {
            status = "Ready. ⌘Tab: visible apps · ⌘⌥Tab: hidden apps."
            if !FocusCoordinator.nativeAvailable {
                status += " Native focus is unavailable; using public activation."
            }
        }
        else if !trusted {
            status = "Accessibility permission is required. Grant permission, then click Check permission."
        } else {
            status = "Could not intercept the keyboard. Command-Tab is handled by macOS. Try Check permission."
        }
        windows.setEnabled(keyboard.isRunning && !paused)
        let hidesOnYellow = !paused && keyboard.isRunning &&
            UserDefaults.standard.bool(forKey: YellowButtonInterceptor.preferenceKey)
        windows.setTracksMinimizeButtons(hidesOnYellow)
        yellowButton.setCandidateRegions(windows.minimizeButtonsReady ? windows.minimizeButtonRegions : nil)
        yellowButton.setEnabled(hidesOnYellow)
        if reportedStatus != status {
            Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "Lifecycle").notice("status=\(self.status, privacy: .public)")
            reportedStatus = status
        }
        refreshWindows()
        updateControls()
    }

    @objc private func togglePause() {
        if statusMenuSession.deferCommand(.togglePause) { return }
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
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.isVisible = visible
            item.behavior.insert(.removalAllowed)
            item.button?.image = menuIcon
            let menu = NSMenu()
            menu.delegate = self
            NotificationCenter.default.addObserver(self, selector: #selector(statusMenuTrackingEnded),
                                                    name: NSMenu.didEndTrackingNotification, object: menu)
            let state = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            state.tag = 1
            menu.addItem(state)
            menu.addItem(.separator())
            let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
            pause.target = self
            pause.tag = 2
            menu.addItem(pause)
            menu.addItem(.separator())
            let preferences = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            preferences.target = self
            preferences.keyEquivalentModifierMask = .command
            menu.addItem(preferences)
            let guide = NSMenuItem(title: "Guide", action: #selector(showGuide), keyEquivalent: "")
            guide.target = self
            menu.addItem(guide)
            let about = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
            about.target = self
            menu.addItem(about)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: preview ? "Quit Preview" : "Quit \(ApplicationIdentity.displayName)",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            quit.keyEquivalentModifierMask = .command
            menu.addItem(quit)
            statusMenu = menu
            // Let AppKit own ordinary status-item clicks and menu tracking.
            item.menu = menu
            statusItem = item
            statusItemVisibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] observed, _ in
                let itemID = ObjectIdentifier(observed)
                Task { @MainActor [weak self] in self?.statusItemVisibilityChanged(itemID) }
            }
        }
        statusItem?.button?.toolTip = "\(ApplicationIdentity.displayName) — \(status)\nClick to open the menu."
        let image = (!paused && !preview && !keyboard.isRunning)
            ? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "\(ApplicationIdentity.displayName) unavailable")
            : menuIcon
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = paused || (!preview && !keyboard.isRunning)
        let trusted = !preview && AXIsProcessTrusted()
        statusMenu?.item(withTag: 1)?.title = paused ? "Paused" : keyboard.isRunning ? "Ready"
            : trusted ? "Shortcuts unavailable" : "Permission required"
        statusMenu?.item(withTag: 2)?.title = paused ? "Resume" : "Pause"
        let hidesOnYellow = UserDefaults.standard.bool(forKey: YellowButtonInterceptor.preferenceKey)
        var limitations: [String] = []
        if keyboard.isRunning {
            if !WindowTracker.identityAvailable { limitations.append("Window switching is unavailable on this macOS.") }
            if !FocusCoordinator.nativeAvailable { limitations.append("Using public app activation.") }
        } else if trusted {
            limitations.append("Could not start keyboard interception. Click Check permission to retry.")
        }
        // The query above is already a current permission check. macOS retains
        // the grant; no manual-click flag or persisted boolean should hide it.
        let settingsStatus = SettingsStatus(permissionChecked: !preview, accessibilityGranted: trusted,
            keyboardRunning: keyboard.isRunning, paused: paused, preview: preview,
            detail: limitations.isEmpty ? nil : limitations.joined(separator: " "),
            yellowButtonFailure: hidesOnYellow ? yellowButtonFailure : nil)
        settings.update(status: settingsStatus, iconVisible: visible,
                        glassProfile: GlassProfile.selected, yellowButtonHidesApp: hidesOnYellow)
    }

    private func statusItemVisibilityChanged(_ itemID: ObjectIdentifier) {
        guard let item = statusItem, ObjectIdentifier(item) == itemID else { return }
        // Read the current value on the main actor; queued observations from a
        // rapid hide/show cannot restore a stale state. This cannot read macOS's
        // separate per-app "Allow in the Menu Bar" permission.
        let visible = item.isVisible
        guard UserDefaults.standard.bool(forKey: "showMenuBarIcon") != visible else { return }
        UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
        updateControls()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        settingsFocus.cancel()
        statusMenuSession.beginTracking()
        statusMenuSession.menuWillOpen()
        cancelSelection()
        statusItem?.button?.highlight(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        statusMenuSession.menuDidClose()
        statusItem?.button?.highlight(false)
        settingsLog.debug("menu closed; tracking completion still pending")
    }

    @objc private func statusMenuTrackingEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, menu === statusMenu else { return }
        // DispatchQueue.main also runs in nested tracking loops. Wait for AppKit's
        // explicit end notification and the ordinary application run-loop mode.
        let menuID = ObjectIdentifier(menu)
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.finishStatusMenuTracking(menuID) }
        }
    }

    private func finishStatusMenuTracking(_ menuID: ObjectIdentifier) {
        guard let menu = statusMenu, ObjectIdentifier(menu) == menuID,
              statusMenuSession.isTracking, !statusMenuSession.isOpen else { return }
        let command = statusMenuSession.finishTracking()
        settingsLog.debug("menu tracking finished pending=\(command.map { String(describing: $0) } ?? "none", privacy: .public)")
        switch command {
        case .settings: showSettings()
        case .about: showAbout()
        case .guide: showGuide()
        case .togglePause: togglePause()
        case .quit: NSApp.terminate(nil)
        case nil: break
        }
    }

    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent,
                             target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                             action: UnsafeMutablePointer<Selector?>) -> Bool {
        // Keep the native path available even while switching is paused and its
        // event tap is stopped. Resolve an explicit target rather than a responder.
        // AppKit may resolve the action after menuDidClose. It still belongs to
        // this tracking session until the end notification has been processed.
        guard let command = StatusMenuCommand.matching(menuIsOpen: menu === statusMenu && statusMenuSession.isTracking,
                    characters: event.charactersIgnoringModifiers,
                    modifiers: modifiers(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))) else { return false }
        switch command {
        case .settings: target.pointee = self; action.pointee = #selector(showSettings)
        case .about: target.pointee = self; action.pointee = #selector(showAbout)
        case .guide: target.pointee = self; action.pointee = #selector(showGuide)
        case .togglePause: target.pointee = self; action.pointee = #selector(togglePause)
        case .quit: target.pointee = NSApp; action.pointee = #selector(NSApplication.terminate(_:))
        }
        return true
    }

    private func refreshWindows(completion: (() -> Void)? = nil) {
        windows.refresh(applications: tracker.windowInputs,
                        frontmost: tracker.frontmostPID, completion: completion)
    }

    func keyboardUnavailable(_ reason: String) {
        cancelSelection()
        ownership.reset()
        windows.setEnabled(false)
        yellowButton.setEnabled(false)
        status = reason
        updateControls()
    }

    func keyboardInputInterrupted() {
        cancelSelection()
        ownership.reset()
        statusMenuOwnedKeys.removeAll()
    }

    func keyboardRecovered() { checkPermission() }

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
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            let menuOwned = statusMenuOwnedKeys.remove(key) != nil
            return ownership.consumeUp(key) || menuOwned
        }
        if type == .keyDown, statusMenuOwnedKeys.contains(key) { return true }
        if statusMenuSession.isOpen {
            guard type == .keyDown,
                  let command = StatusMenuCommand.matching(menuIsOpen: true,
                    characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
                    modifiers: modifiers(event.flags)), let menu = statusMenu else { return false }
            statusMenuOwnedKeys.insert(key)
            if statusMenuSession.deferCommand(command) {
                settingsLog.debug("menu command queued action=\(command == .settings ? "settings" : "quit", privacy: .public)")
                // Do not reenter AppKit menu tracking from the event-tap callback.
                // Common modes also run while the native menu is tracking.
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    menu.cancelTracking()
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
            return true
        }
        if type == .flagsChanged {
            if let mode = sessionMode, !mode.isHeld(by: modifiers(event.flags)) { finishSelection() }
            return false
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            // The internal key-window record targets an off-content point, not a
            // physical screen click. Never treat it as new user selection intent.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let point = NSPoint(x: event.location.x, y: top - event.location.y)
            if NSScreen.screens.contains(where: { $0.frame.contains(point) }) {
                if sessionMode == nil { focus.cancel(reason: "mouse-down") }
                else if !panel.containsQuartzPoint(event.location) { cancelSelection() }
            }
            return false
        }
        guard type == .keyDown else { return false }
        let flags = modifiers(event.flags)
        if key == UInt16(kVK_Tab) {
            if let mode = sessionMode {
                guard mode.permits(flags), mode.isHeld(by: flags) else { cancelSelection(); return false }
                navigateSelection(flags.contains(.shift) ? -1 : 1)
            } else {
                guard let mode = SwitcherMode.starting(with: flags),
                      mode != .windows || WindowTracker.identityAvailable else { return false }
                beginSelection(mode: mode, backwards: flags.contains(.shift))
            }
            ownership.consumeDown(key)
            return true
        }
        guard let mode = sessionMode else { focus.cancel(reason: "keyboard-input"); return false }
        guard mode.permits(flags), mode.isHeld(by: flags) else { cancelSelection(); return false }
        var handled = true
        switch Int(key) {
        case kVK_Escape: cancelSelection()
        case kVK_LeftArrow, kVK_ANSI_Grave:
            navigateSelection(-1)
        case kVK_RightArrow:
            navigateSelection(1)
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
        let appOrder = FocusIntentPolicy.prioritizing(selectionOrigin?.pid, in: tracker.history.order)
        switch sessionMode {
        case .applications:
            let ids = tracker.history.visible.map { SwitcherTargetID.application($0.id) }
            return FocusIntentPolicy.prioritizing(selectionOrigin.map { .application($0.pid) }, in: ids)
        case .hiddenApplications: return tracker.history.hidden.map { .application($0.id) }
        case .windows:
            let visiblePIDs = Set(tracker.history.visible.map(\.id))
            let windowOrder = FocusIntentPolicy.prioritizing(selectionOrigin, in: windows.history.order)
            return WindowHistory.group(windowOrder, applicationOrder: appOrder).filter { visiblePIDs.contains($0.pid) }
        case nil: return []
        }
    }

    private var currentWindowID: SwitcherTargetID? {
        if case .window = selectionOrigin { return selectionOrigin }
        if let pid = selectionOrigin?.pid { return windows.history.order.first { $0.pid == pid } }
        return windows.history.current(focused: windows.focusedID, frontmostPID: tracker.frontmostPID)
    }

    private func beginSelection(mode: SwitcherMode, backwards: Bool) {
        tracker.pruneTerminatedApplications()
        settingsFocus.cancel()
        selectionOrigin = focus.beginSelection()
        selectionGeneration += 1
        let generation = selectionGeneration
        sessionMode = mode
        presentation.begin(mode: mode, now: ProcessInfo.processInfo.systemUptime)
        sessionScreen = foregroundScreen()
        if mode == .windows, windows.history.order.isEmpty {
            pendingWindowAdvances = 0
            pendingWindowBackwards = backwards
        } else {
            let current = mode == .windows ? currentWindowID :
                (selectionOrigin?.pid ?? tracker.frontmostPID).map { SwitcherTargetID.application($0) }
            session = SelectionSession(ids: candidateIDs(), currentID: current, backwards: backwards)
            guard session?.selectedID != nil else { cancelSelection(); return }
        }
        refreshBadges()
        badgeRefresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBadges() }
        }
        if let badgeRefresh { RunLoop.main.add(badgeRefresh, forMode: .common) }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.selectionGeneration == generation else { return }
            self.renderSelection()
        }
        displayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + presentation.delayRemaining(now: ProcessInfo.processInfo.systemUptime), execute: work)
        sessionWatchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let mode = self.sessionMode else { return }
                self.tracker.pruneTerminatedApplications()
                guard self.sessionMode == mode else { return }
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

    private func navigateSelection(_ direction: Int) {
        presentation.navigate(now: ProcessInfo.processInfo.systemUptime)
        displayWork?.cancel()
        displayWork = nil
        if session != nil { session?.advance(direction); renderSelection() }
        else if pendingWindowAdvances != nil { pendingWindowAdvances! += direction }
    }

    private func renderIfVisible() { if panel.isVisible { renderSelection() } }

    private func renderSelection() {
        guard presentation.permitsDisplay(now: ProcessInfo.processInfo.systemUptime),
              let mode = sessionMode, mode.isHeld(by: heldModifiers) else { return }
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
        tracker.setVisibleIconTargets(panel.visibleApplicationPIDs, selected: session.selectedID?.pid)
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
        tracker.pruneTerminatedApplications()
        if session == nil, pendingWindowAdvances != nil {
            // Never turn a quick release into a delayed activation after cold discovery.
            cancelSelection()
            return
        }
        let selected = session?.selectedID, mode = sessionMode
        dismissSelection()
        guard let selected, let app = tracker.applications[selected.pid], !app.isTerminated else { return }
        if mode == .applications, tracker.frontmostPID == selected.pid { return }
        let record = mode == .windows ? windows.records[selected] : windows.preferredWindow(for: selected.pid)
        focus.commit(selected, app: app, record: record,
                     revealHidden: mode == .hiddenApplications) { result in
            if result.shouldBeep { NSSound.beep() }
        }
    }

    func cancelSelection() {
        focus.cancel()
        dismissSelection()
    }

    private func dismissSelection() {
        tracker.setVisibleIconTargets([], selected: nil)
        presentation.cancel()
        selectionGeneration += 1
        displayWork?.cancel()
        displayWork = nil
        sessionWatchdog?.invalidate()
        sessionWatchdog = nil
        badgeRefresh?.invalidate()
        badgeRefresh = nil
        session = nil
        sessionMode = nil
        selectionOrigin = nil
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

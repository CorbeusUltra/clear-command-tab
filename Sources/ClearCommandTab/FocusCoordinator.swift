import AppKit
import Carbon
import Darwin
import os
import ClearCommandTabCore

private let revealLog = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "RevealFocus")
private let focusLog = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "Focus")

private final class FocusTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let deadline = ProcessInfo.processInfo.systemUptime + 0.8
    var valid: Bool {
        lock.lock(); defer { lock.unlock() }
        return !cancelled && ProcessInfo.processInfo.systemUptime < deadline
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Optional symbols, resolved rather than linked, so newer macOS versions can fall
/// back to public activation. No process injection or permanent system change.
private enum NativeFocusBridge {
    typealias ProcessLookup = @convention(c) (Int32, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    typealias FrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let processHandle = dlopen(nil, RTLD_LAZY)
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    static let lookup: ProcessLookup? = resolve("GetProcessForPID", from: processHandle, as: ProcessLookup.self)
    static let front: FrontProcess? = resolve("_SLPSSetFrontProcessWithOptions", from: skyLight, as: FrontProcess.self)
    static let post: PostRecord? = resolve("SLPSPostEventRecordTo", from: skyLight, as: PostRecord.self)
    static var available: Bool { lookup != nil && front != nil && post != nil && WindowTracker.identityAvailable }

    private static func resolve<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static func focus(pid: Int32, window: CGWindowID?, allWindows: Bool, ticket: FocusTicket, trace: Bool) -> Bool {
        guard ticket.valid, let lookup, let front, let post else { return false }
        var process = ProcessSerialNumber()
        guard lookup(pid, &process) == noErr, ticket.valid else { return false }
        // A validated shortcut is user intent. All-windows is reserved for app mode.
        let flags: UInt32 = 0x200 | (allWindows ? 0x100 : 0)
        let result = front(&process, window ?? kCGNullWindowID, flags)
        if trace { revealLog.notice("front pid=\(pid) window=\(window ?? 0) flags=\(flags) result=\(result.rawValue)") }
        guard result == .success, ticket.valid else { return false }
        if let window {
            var record = KeyWindowEventRecord.bytes(window: window)
            guard ticket.valid else { return false }
            let result = record.withUnsafeMutableBufferPointer { post(&process, $0.baseAddress!) }
            if trace { revealLog.notice("key window=\(window) result=\(result.rawValue)") }
            guard result == .success else { return false }
        }
        return ticket.valid
    }
}

/// Settings has its own short-lived intent, separate from switcher MRU/focus work.
/// The same optional native bridge is used once, only after public activation.
@MainActor
final class SettingsFocusCoordinator {
    private let log = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "SettingsFocus")
    private let queue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".settingsFocus", qos: .userInteractive)
    private var intent = SettingsFocusIntent()
    private var ticket: FocusTicket?
    private weak var window: NSWindow?
    private var windowNumber: CGWindowID = 0
    private var originPID: Int32?
    private var timer: Timer?
    private var monitor: Any?
    private var observationInFlight = false

    func present(_ window: NSWindow) {
        cancel()
        self.window = window
        windowNumber = CGWindowID(window.windowNumber)
        originPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let revision = intent.begin(now: ProcessInfo.processInfo.systemUptime)
        ticket = FocusTicket()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                // The native key-window record is an off-screen, down-only event.
                if event.type != .keyDown, let point = event.cgEvent?.location {
                    let top = NSScreen.screens.first?.frame.maxY ?? 0
                    let cocoa = NSPoint(x: point.x, y: top - point.y)
                    guard NSScreen.screens.contains(where: { $0.frame.contains(cocoa) }) else { return }
                }
                self?.cancel()
            }
        }
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // A default-mode handoff lets menu tracking and AppKit activation finish.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.probe(revision) }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.probe(revision) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .default)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.intent.revision == revision else { return }
            self.log.notice("Settings keyboard focus not confirmed before deadline")
            self.cancel()
        }
    }

    func applicationDidBecomeActive() {
        guard let window, window.isVisible, ticket?.valid == true else { return }
        window.makeMain()
        window.makeKey()
    }

    func foregroundChanged(to pid: Int32?) {
        guard ticket != nil, pid != ProcessInfo.processInfo.processIdentifier, pid != originPID else { return }
        cancel()
    }

    func cancel() {
        intent.cancel()
        ticket?.cancel()
        ticket = nil
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observationInFlight = false
    }

    private func probe(_ revision: UInt64) {
        guard intent.isCurrent(revision, now: ProcessInfo.processInfo.systemUptime),
              let ticket, ticket.valid, let window, window.isVisible,
              window.windowNumber == Int(windowNumber) else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        guard NSApp.isActive, window.isKeyWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            requestFallback(revision, ticket: ticket)
            return
        }
        guard !observationInFlight else { return }
        observationInFlight = true
        queue.async { [weak self] in
            let observation = FocusActions.observe(pid: pid, ticket: ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.intent.isCurrent(revision, now: ProcessInfo.processInfo.systemUptime),
                      ticket.valid else { return }
                self.observationInFlight = false
                let target = SwitcherTargetID.window(pid: pid, number: self.windowNumber)
                if self.window?.isVisible == true, self.window?.isKeyWindow == true, NSApp.isActive,
                   FocusConfirmation.matches(target: target, expectedWindow: target,
                       frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                       keyboardPID: observation.appPID, window: observation.window) {
                    self.log.notice("Settings foreground and keyboard window confirmed")
                    self.cancel()
                } else { self.requestFallback(revision, ticket: ticket) }
            }
        }
    }

    private func requestFallback(_ revision: UInt64, ticket: FocusTicket) {
        guard NativeFocusBridge.available, AXIsProcessTrusted(),
              intent.takeFallback(revision, now: ProcessInfo.processInfo.systemUptime) else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let number = windowNumber
        let origin = originPID
        queue.async { [weak self] in
            guard ticket.valid else { return }
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard foreground == pid || foreground == origin else { return }
            let sent = NativeFocusBridge.focus(pid: pid, window: number, allWindows: false, ticket: ticket, trace: false)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.intent.isCurrent(revision, now: ProcessInfo.processInfo.systemUptime),
                      ticket.valid else { return }
                self.log.notice("Settings native focus request sent=\(sent)")
                if NSApp.isActive, self.window?.isVisible == true {
                    self.window?.makeMain()
                    self.window?.makeKey()
                }
            }
        }
    }
}

private struct FocusDispatch: Sendable {
    var sent = false
    var expectedWindow: SwitcherTargetID?
}

private struct RevealDispatch: Sendable {
    let error: Int32
    let hidden: Bool?
}

private struct FocusObservation: Sendable {
    var appPID: Int32?
    var window: SwitcherTargetID?
}

private enum FocusActions {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func hidden(pid: Int32, ticket: FocusTicket) -> Bool? {
        guard ticket.valid else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.025)
        return value(application, kAXHiddenAttribute)
    }

    static func reveal(pid: Int32, ticket: FocusTicket) -> RevealDispatch {
        guard ticket.valid else { return .init(error: AXError.cannotComplete.rawValue, hidden: nil) }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.025)
        let before: Bool? = value(application, kAXHiddenAttribute)
        if before == false { return .init(error: AXError.success.rawValue, hidden: false) }
        guard ticket.valid else { return .init(error: AXError.cannotComplete.rawValue, hidden: nil) }
        let result = AXUIElementSetAttributeValue(application, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        let after: Bool? = ticket.valid ? value(application, kAXHiddenAttribute) : nil
        revealLog.notice("AX reveal pid=\(pid) result=\(result.rawValue) before=\(String(describing: before), privacy: .public) after=\(String(describing: after), privacy: .public)")
        return .init(error: result.rawValue, hidden: after)
    }

    static func appWindow(pid: Int32, preferred: TrackedWindow?, ticket: FocusTicket) -> TrackedWindow? {
        if let preferred, case .window(let owner, let number) = preferred.id, owner == pid, ticket.valid,
           let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]],
           let surface = info.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid &&
               $0[kCGWindowNumber as String] as? UInt32 == number }) {
            AXUIElementSetMessagingTimeout(preferred.element, 0.025)
            // Hidden/off-Space cache entries may since have been minimized. Never
            // use an unknown minimized state to bring such a cached window forward.
            if surface[kCGWindowIsOnscreen as String] as? Bool == true ||
                value(preferred.element, kAXMinimizedAttribute) as Bool? == false {
                return preferred
            }
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.025)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard ticket.valid else { return nil }
            guard let element: AXUIElement = value(application, attribute) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.025)
            guard ticket.valid, value(element, kAXMinimizedAttribute) as Bool? != true,
                  let number = WindowIdentity.number(element) else { continue }
            return TrackedWindow(id: .window(pid: pid, number: number), title: "", element: element)
        }
        return nil // Windowless and minimized-only apps must not reopen documents.
    }

    static func validWindow(_ record: TrackedWindow, ticket: FocusTicket) -> Bool {
        guard ticket.valid, case .window(let pid, let number) = record.id,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              info.contains(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid &&
                  $0[kCGWindowNumber as String] as? UInt32 == number }) else { return false }
        AXUIElementSetMessagingTimeout(record.element, 0.025)
        return ticket.valid && WindowIdentity.number(record.element) == number &&
            value(record.element, kAXMinimizedAttribute) as Bool? != true && ticket.valid
    }

    static func perform(target: SwitcherTargetID, record: TrackedWindow?, native: Bool,
                        revealed: Bool, ticket: FocusTicket) -> FocusDispatch {
        guard ticket.valid else { return .init() }
        let window: TrackedWindow?
        let allWindows: Bool
        switch target {
        case .window:
            guard let record, validWindow(record, ticket: ticket) else { return .init() }
            window = record
            allWindows = false
        case .application(let pid):
            window = appWindow(pid: pid, preferred: record, ticket: ticket)
            // Unhide already restores the app's windows. Focus its real window
            // using exact-window focus rather than bringing every window forward.
            allWindows = !revealed
        }
        guard ticket.valid else { return .init() }
        if revealed { revealLog.notice("resolved pid=\(target.pid) window=\(String(describing: window?.id), privacy: .public)") }
        if native {
            let number: CGWindowID?
            if case .window(_, let id) = window?.id { number = id } else { number = nil }
            guard NativeFocusBridge.focus(pid: target.pid, window: number, allWindows: allWindows,
                                          ticket: ticket, trace: revealed) else { return .init() }
        } else if let window {
            // Public fallback for a future OS without the optional bridge.
            _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            guard ticket.valid else { return .init() }
            let application = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(application, 0.025)
            _ = AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, window.element)
        }
        guard ticket.valid else { return .init() }
        if let window {
            let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            if revealed { revealLog.notice("raise result=\(result.rawValue)") }
        }
        // Return codes only mean the request was sent; readback confirms actual focus.
        return FocusDispatch(sent: ticket.valid, expectedWindow: revealed ? window?.id : nil)
    }

    static func observe(pid: Int32, ticket: FocusTicket) -> FocusObservation {
        guard ticket.valid else { return .init() }
        let system = AXUIElementCreateSystemWide()
        // Confirmation has its own queue and budget: it must neither time out at
        // the action's 25 ms limit nor block a newer focus action behind this read.
        AXUIElementSetMessagingTimeout(system, 0.1)
        guard let focusedApp: AXUIElement = value(system, kAXFocusedApplicationAttribute) else { return .init() }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focusedApp, &focusedPID) == .success else { return .init() }
        var observation = FocusObservation(appPID: focusedPID)
        guard focusedPID == pid, ticket.valid else { return observation }
        AXUIElementSetMessagingTimeout(focusedApp, 0.1)
        if let element: AXUIElement = value(focusedApp, kAXFocusedWindowAttribute),
           ticket.valid {
            AXUIElementSetMessagingTimeout(element, 0.1)
            if let number = WindowIdentity.number(element) {
                observation.window = .window(pid: pid, number: number)
            }
        }
        return observation
    }
}

private struct PendingReveal {
    let target: SwitcherTargetID
    let app: NSRunningApplication
    let record: TrackedWindow?
    let revision: UInt64
    let ticket: FocusTicket
    let native: Bool
    let completion: (FocusResult) -> Void
}

/// One focus queue for all modes. Every action/readback belongs to an intent;
/// opening another selection cancels remaining work from the preceding commit.
@MainActor
final class FocusCoordinator {
    nonisolated static var nativeAvailable: Bool { NativeFocusBridge.available }
    var onTransition: ((Bool) -> Void)?
    var onConfirmed: ((SwitcherTargetID, SwitcherTargetID?) -> Void)?
    private var policy = FocusIntentPolicy()
    private var ticket: FocusTicket?
    private var revealGate = ApplicationRevealGate()
    private var pendingReveal: PendingReveal?
    private var revealObserver: NSObjectProtocol?
    private var tracingReveal = false

    init() {
        revealObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.acknowledgeUnhide(app.processIdentifier) }
        }
    }

    deinit {
        if let revealObserver { NSWorkspace.shared.notificationCenter.removeObserver(revealObserver) }
    }
    private let queue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".focus", qos: .userInteractive)
    private let observationQueue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".focusReadback", qos: .utility)

    func beginSelection() -> SwitcherTargetID? {
        if tracingReveal { revealLog.notice("cancel new-selection revision=\(self.policy.revision)") }
        clearReveal()
        ticket?.cancel()
        ticket = nil
        let origin = policy.beginSelection(now: ProcessInfo.processInfo.systemUptime)
        onTransition?(false)
        return origin
    }

    func cancel(reason: String = "selection-cancelled") {
        if tracingReveal { revealLog.notice("cancel \(reason, privacy: .public) revision=\(self.policy.revision)") }
        clearReveal()
        ticket?.cancel()
        ticket = nil
        policy.cancel()
        onTransition?(false)
    }

    func consumeActivation(pid: Int32) -> Bool {
        policy.consumeActivation(pid: pid, now: ProcessInfo.processInfo.systemUptime)
    }

    func commit(_ target: SwitcherTargetID, app: NSRunningApplication, record: TrackedWindow?,
                revealHidden: Bool, completion: @escaping (FocusResult) -> Void) {
        ticket?.cancel()
        let ticket = FocusTicket()
        self.ticket = ticket
        let revision = policy.request(target, now: ProcessInfo.processInfo.systemUptime)
        onTransition?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            // An action waiting in the queue or a slow AX read must also settle.
            // This deadline only clears bookkeeping; it never retries focus.
            self?.complete(revision, ticket: ticket, observed: nil, target: target, result: .unverified, completion: completion)
        }
        clearReveal()
        let wasHidden = app.isHidden
        tracingReveal = revealHidden && wasHidden
        let request = PendingReveal(target: target, app: app, record: record, revision: revision,
                                    ticket: ticket, native: Self.nativeAvailable, completion: completion)
        if tracingReveal {
            // Register before sending the request, so even an immediate acknowledgement
            // cannot be missed. No focus action is allowed while this gate is closed.
            revealLog.notice("request pid=\(target.pid) revision=\(revision)")
            revealGate.wait(for: target.pid)
            pendingReveal = request
        }
        guard !app.isTerminated, !wasHidden || revealHidden else {
            complete(revision, ticket: ticket, observed: nil, target: target, completion: completion)
            return
        }
        if tracingReveal { requestReveal(request) }
        else { enqueue(request, revealed: false) }
    }

    private func requestReveal(_ request: PendingReveal) {
        queue.async { [weak self] in
            let result = FocusActions.reveal(pid: request.target.pid, ticket: request.ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(request.revision), request.ticket.valid,
                      self.pendingReveal != nil else { return }
                if self.revealGate.observe(pid: request.target.pid, hidden: result.hidden) {
                    self.resumeReveal(request)
                } else {
                    if [AXError.attributeUnsupported.rawValue, AXError.notImplemented.rawValue].contains(result.error),
                       !request.app.isTerminated {
                        let sent = request.app.unhide()
                        revealLog.notice("Cocoa reveal fallback pid=\(request.target.pid) returned=\(sent)")
                        // The user's trace showed unhide=false while the app actually
                        // reappeared. Do not abandon focus on that return value: wait
                        // for a real notification/AX observation, within this intent.
                    }
                    self.observeReveal(request, attempt: 0)
                }
            }
        }
    }

    private func observeReveal(_ request: PendingReveal, attempt: Int) {
        guard policy.isCurrent(request.revision), request.ticket.valid, pendingReveal != nil else { return }
        queue.async { [weak self] in
            let hidden = FocusActions.hidden(pid: request.target.pid, ticket: request.ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(request.revision), request.ticket.valid,
                      self.pendingReveal != nil else { return }
                if self.revealGate.observe(pid: request.target.pid, hidden: hidden) {
                    self.resumeReveal(request)
                } else {
                    // Readiness probes only while revealing, never idle polling or
                    // retries of the focus action itself. The overall deadline remains.
                    let delays = [0.01, 0.02, 0.04, 0.08, 0.16]
                    if attempt < delays.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
                            self?.observeReveal(request, attempt: attempt + 1)
                        }
                    }
                }
            }
        }
    }

    private func acknowledgeUnhide(_ pid: Int32) {
        guard let request = pendingReveal, request.ticket.valid,
              policy.isCurrent(request.revision), revealGate.acknowledge(pid) else { return }
        resumeReveal(request)
    }

    private func resumeReveal(_ request: PendingReveal) {
        pendingReveal = nil
        revealLog.notice("acknowledged pid=\(request.target.pid) revision=\(request.revision)")
        // Let the current notification finish before asking the app for its now-live
        // window. This is a run-loop handoff, not an arbitrary display/focus delay.
        DispatchQueue.main.async { [weak self] in self?.enqueue(request, revealed: true) }
    }

    private func enqueue(_ request: PendingReveal, revealed: Bool) {
        let target = request.target, ticket = request.ticket, revision = request.revision
        guard policy.isCurrent(revision), ticket.valid, !request.app.isTerminated else { return }
        if !request.native {
            let activated = request.app.activate(options: target == .application(target.pid) ? [.activateAllWindows] : [])
            if !activated {
                // As with unhide, use actual focus observations rather than
                // turning an advisory Cocoa return into an immediate error sound.
                focusLog.notice("public activation returned false pid=\(target.pid)")
            }
        }
        queue.async { [weak self] in
            guard ticket.valid else { return }
            let result = FocusActions.perform(target: target, record: request.record, native: request.native,
                                              revealed: revealed, ticket: ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(revision), ticket.valid else { return }
                if result.sent {
                    self.confirm(target, expectedWindow: result.expectedWindow, revision: revision,
                                 ticket: ticket, attempt: 0, completion: request.completion)
                } else {
                    self.complete(revision, ticket: ticket, observed: nil, target: target, completion: request.completion)
                }
            }
        }
    }

    private func clearReveal() {
        revealGate.cancel()
        pendingReveal = nil
        tracingReveal = false
    }

    private func confirm(_ target: SwitcherTargetID, expectedWindow: SwitcherTargetID?, revision: UInt64, ticket: FocusTicket, attempt: Int,
                         completion: @escaping (FocusResult) -> Void) {
        guard policy.isCurrent(revision), ticket.valid else { return }
        observationQueue.async { [weak self] in
            let observation = FocusActions.observe(pid: target.pid, ticket: ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(revision), ticket.valid else { return }
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let matches = FocusConfirmation.matches(target: target, expectedWindow: expectedWindow,
                                                        frontmostPID: frontPID, keyboardPID: observation.appPID,
                                                        window: observation.window)
                if self.tracingReveal && attempt == 0 {
                    revealLog.notice("readback front=\(frontPID ?? -1) keyboard=\(observation.appPID ?? -1) window=\(String(describing: observation.window), privacy: .public) matches=\(matches)")
                }
                if matches {
                    self.complete(revision, ticket: ticket, observed: observation.window, target: target,
                                  result: .confirmed, completion: completion)
                } else {
                    // Read-only, bounded confirmation. No delayed reactivation that
                    // could steal focus after the user has moved on to another app.
                    let delays = [0.02, 0.04, 0.08, 0.16, 0.24]
                    if attempt < delays.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
                            self?.confirm(target, expectedWindow: expectedWindow, revision: revision, ticket: ticket, attempt: attempt + 1, completion: completion)
                        }
                    } else {
                        self.complete(revision, ticket: ticket, observed: nil, target: target, result: .unverified, completion: completion)
                    }
                }
            }
        }
    }

    private func complete(_ revision: UInt64, ticket: FocusTicket, observed: SwitcherTargetID?, target: SwitcherTargetID,
                          result: FocusResult = .failed, completion: (FocusResult) -> Void) {
        guard self.ticket === ticket, policy.complete(revision, observed: result == .confirmed) else { return }
        if tracingReveal { revealLog.notice("complete revision=\(revision) result=\(result.rawValue, privacy: .public)") }
        if result != .confirmed {
            focusLog.notice("result=\(result.rawValue, privacy: .public) pid=\(target.pid) revision=\(revision)")
        }
        clearReveal()
        ticket.cancel()
        self.ticket = nil
        if result == .confirmed { onConfirmed?(target, observed) }
        onTransition?(false)
        completion(result)
    }
}

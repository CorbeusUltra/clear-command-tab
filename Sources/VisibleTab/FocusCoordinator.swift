import AppKit
import Carbon
import Darwin
import VisibleTabCore

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

    static func focus(pid: Int32, window: CGWindowID?, allWindows: Bool, ticket: FocusTicket) -> Bool {
        guard ticket.valid, let lookup, let front, let post else { return false }
        var process = ProcessSerialNumber()
        guard lookup(pid, &process) == noErr, ticket.valid else { return false }
        // A validated shortcut is user intent. All-windows is reserved for app mode.
        let flags: UInt32 = 0x200 | (allWindows ? 0x100 : 0)
        guard front(&process, window ?? kCGNullWindowID, flags) == .success, ticket.valid else { return false }
        if let window {
            var record = KeyWindowEventRecord.bytes(window: window)
            guard ticket.valid, record.withUnsafeMutableBufferPointer({ post(&process, $0.baseAddress!) }) == .success else {
                return false
            }
        }
        return ticket.valid
    }
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

    static func appWindow(pid: Int32, ticket: FocusTicket) -> TrackedWindow? {
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

    static func perform(target: SwitcherTargetID, record: TrackedWindow?, native: Bool, ticket: FocusTicket) -> Bool {
        guard ticket.valid else { return false }
        let window: TrackedWindow?
        let allWindows: Bool
        switch target {
        case .window:
            guard let record, validWindow(record, ticket: ticket) else { return false }
            window = record
            allWindows = false
        case .application(let pid):
            window = appWindow(pid: pid, ticket: ticket)
            allWindows = true
        }
        guard ticket.valid else { return false }
        if native {
            let number: CGWindowID?
            if case .window(_, let id) = window?.id { number = id } else { number = nil }
            guard NativeFocusBridge.focus(pid: target.pid, window: number, allWindows: allWindows, ticket: ticket) else { return false }
        } else if let window {
            // Public fallback for a future OS without the optional bridge.
            _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            guard ticket.valid else { return false }
            let application = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(application, 0.025)
            _ = AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, window.element)
        }
        guard ticket.valid else { return false }
        if let window { _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
        // Return codes only mean the request was sent; readback confirms actual focus.
        return ticket.valid
    }

    static func observe(pid: Int32, ticket: FocusTicket) -> FocusObservation {
        guard ticket.valid else { return .init() }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.025)
        guard let focusedApp: AXUIElement = value(system, kAXFocusedApplicationAttribute) else { return .init() }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focusedApp, &focusedPID) == .success else { return .init() }
        var observation = FocusObservation(appPID: focusedPID)
        guard focusedPID == pid, ticket.valid else { return observation }
        AXUIElementSetMessagingTimeout(focusedApp, 0.025)
        if let element: AXUIElement = value(focusedApp, kAXFocusedWindowAttribute),
           let number = WindowIdentity.number(element) {
            observation.window = .window(pid: pid, number: number)
        }
        return observation
    }
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
    private let queue = DispatchQueue(label: "local.lucas.VisibleTab.focus", qos: .userInteractive)

    func beginSelection() -> SwitcherTargetID? {
        ticket?.cancel()
        ticket = nil
        let origin = policy.beginSelection(now: ProcessInfo.processInfo.systemUptime)
        onTransition?(false)
        return origin
    }

    func cancel() {
        ticket?.cancel()
        ticket = nil
        policy.cancel()
        onTransition?(false)
    }

    func consumeActivation(pid: Int32) -> Bool {
        policy.consumeActivation(pid: pid, now: ProcessInfo.processInfo.systemUptime)
    }

    func commit(_ target: SwitcherTargetID, app: NSRunningApplication, record: TrackedWindow?,
                revealHidden: Bool, completion: @escaping (Bool) -> Void) {
        ticket?.cancel()
        let ticket = FocusTicket()
        self.ticket = ticket
        let revision = policy.request(target, now: ProcessInfo.processInfo.systemUptime)
        onTransition?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            // An action waiting in the queue or a slow AX read must also settle.
            // This deadline only clears bookkeeping; it never retries focus.
            self?.complete(revision, ticket: ticket, observed: nil, target: target, completion: completion)
        }
        let native = Self.nativeAvailable
        let accepted = ApplicationSwitch.commit(revealHidden: revealHidden, isHidden: app.isHidden,
                                               isTerminated: app.isTerminated, unhide: { app.unhide() },
                                               activate: {
            native || app.activate(options: target == .application(target.pid) ? [.activateAllWindows] : [])
        })
        guard accepted else { complete(revision, ticket: ticket, observed: nil, target: target, completion: completion); return }
        queue.async { [weak self] in
            guard ticket.valid else { return }
            let sent = FocusActions.perform(target: target, record: record, native: native, ticket: ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(revision), ticket.valid else { return }
                if sent { self.confirm(target, revision: revision, ticket: ticket, attempt: 0, completion: completion) }
                else { self.complete(revision, ticket: ticket, observed: nil, target: target, completion: completion) }
            }
        }
    }

    private func confirm(_ target: SwitcherTargetID, revision: UInt64, ticket: FocusTicket, attempt: Int,
                         completion: @escaping (Bool) -> Void) {
        guard policy.isCurrent(revision), ticket.valid else { return }
        queue.async { [weak self] in
            let observation = FocusActions.observe(pid: target.pid, ticket: ticket)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.policy.isCurrent(revision), ticket.valid else { return }
                let appFocused = observation.appPID == target.pid &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
                let matches = appFocused && (target == .application(target.pid) || observation.window == target)
                if matches {
                    self.complete(revision, ticket: ticket, observed: observation.window, target: target,
                                  success: true, completion: completion)
                } else {
                    // Read-only, bounded confirmation. No delayed reactivation that
                    // could steal focus after the user has moved on to another app.
                    let delays = [0.02, 0.04, 0.08, 0.16, 0.24]
                    if attempt < delays.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
                            self?.confirm(target, revision: revision, ticket: ticket, attempt: attempt + 1, completion: completion)
                        }
                    } else {
                        self.complete(revision, ticket: ticket, observed: nil, target: target, completion: completion)
                    }
                }
            }
        }
    }

    private func complete(_ revision: UInt64, ticket: FocusTicket, observed: SwitcherTargetID?, target: SwitcherTargetID,
                          success: Bool = false, completion: (Bool) -> Void) {
        guard self.ticket === ticket, policy.complete(revision, observed: success) else { return }
        ticket.cancel()
        self.ticket = nil
        if success { onConfirmed?(target, observed) }
        onTransition?(false)
        completion(success)
    }
}

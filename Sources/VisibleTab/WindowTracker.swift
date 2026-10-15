import AppKit
import ApplicationServices
import Darwin
import VisibleTabCore

private struct WindowApplication: Sendable {
    let pid: Int32
    let hidden: Bool
}

// The AX reference is retained across queues but only read/acted on by the scanner queue.
struct TrackedWindow: @unchecked Sendable {
    let id: SwitcherTargetID
    let title: String
    let element: AXUIElement
}

private struct WindowSnapshot: Sendable {
    var windows: [TrackedWindow] = []
    var focused: SwitcherTargetID?
    var complete = true
}

/// This optional bridge supplies identity only. Discovery and actions use public AX APIs.
private enum WindowIdentity {
    typealias Function = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    static let function: Function? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    static func number(_ element: AXUIElement) -> CGWindowID? {
        var number: CGWindowID = 0
        guard function?(element, &number) == .success, number != 0, number != UInt32.max else { return nil }
        return number
    }
}

private let windowNotification: AXObserverCallback = { _, _, _, context in
    guard let context else { return }
    Unmanaged<AXWindowScanner>.fromOpaque(context).takeUnretainedValue().onEvent()
}

/// All AX reads, subscription bookkeeping, and focus actions run on one serial queue.
/// Notification sources are attached to the main run loop; callbacks only schedule work.
private final class AXWindowScanner: @unchecked Sendable {
    let onEvent: @Sendable () -> Void
    private var observers: [Int32: AXObserver] = [:]
    private var applications: [Int32: AXUIElement] = [:]
    private var subscribedWindows: [SwitcherTargetID: AXUIElement] = [:]
    private let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                    kAXMainWindowChangedNotification]
    private let windowNotifications = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                                       kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                                       kAXMovedNotification, kAXResizedNotification]

    init(onEvent: @escaping @Sendable () -> Void) { self.onEvent = onEvent }

    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }

    static func onscreenWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).filter {
            ($0[kCGWindowLayer as String] as? Int) == 0 &&
            ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
    }

    func scan(_ inputs: [WindowApplication], frontmost: Int32?) -> WindowSnapshot {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.7
        let livePIDs = Set(inputs.map(\.pid))
        for pid in Array(observers.keys) where !livePIDs.contains(pid) { removeObserver(pid) }
        let surfaces = Self.onscreenWindows()
        let surfaceIDs = Set(surfaces.compactMap { surface -> SwitcherTargetID? in
            guard let pid = surface[kCGWindowOwnerPID as String] as? Int32,
                  let number = surface[kCGWindowNumber as String] as? UInt32 else { return nil }
            return .window(pid: pid, number: number)
        })
        let ranks = Dictionary(surfaces.enumerated().compactMap { index, surface -> (SwitcherTargetID, Int)? in
            guard let pid = surface[kCGWindowOwnerPID as String] as? Int32,
                  let number = surface[kCGWindowNumber as String] as? UInt32 else { return nil }
            return (.window(pid: pid, number: number), index)
        }, uniquingKeysWith: { first, _ in first })
        var result = WindowSnapshot()
        // Foreground first, then WindowServer order, so a slow app cannot delay that target.
        let orderedInputs = inputs.sorted { lhs, rhs in
            if (lhs.pid == frontmost) != (rhs.pid == frontmost) { return lhs.pid == frontmost }
            let left = surfaces.firstIndex { $0[kCGWindowOwnerPID as String] as? Int32 == lhs.pid } ?? Int.max
            let right = surfaces.firstIndex { $0[kCGWindowOwnerPID as String] as? Int32 == rhs.pid } ?? Int.max
            return left == right ? lhs.pid < rhs.pid : left < right
        }
        for input in orderedInputs {
            guard ProcessInfo.processInfo.systemUptime < deadline else { result.complete = false; break }
            let application = applications[input.pid] ?? AXUIElementCreateApplication(input.pid)
            AXUIElementSetMessagingTimeout(application, 0.06)
            applications[input.pid] = application
            subscribeApplication(input.pid, application)
            guard !input.hidden, ranks.keys.contains(where: { $0.pid == input.pid }) else { continue }
            var elements: [AXUIElement] = Self.value(application, kAXWindowsAttribute) ?? []
            let focused: AXUIElement? = input.pid == frontmost ? Self.value(application, kAXFocusedWindowAttribute) : nil
            if let focused, !elements.contains(where: { CFEqual($0, focused) }) { elements.append(focused) }
            if elements.isEmpty, let main: AXUIElement = Self.value(application, kAXMainWindowAttribute) {
                elements.append(main)
            }
            for element in elements.prefix(128) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { result.complete = false; break }
                AXUIElementSetMessagingTimeout(element, 0.06)
                guard let number = WindowIdentity.number(element) else { continue }
                let id = SwitcherTargetID.window(pid: input.pid, number: number)
                guard surfaceIDs.contains(id), Self.value(element, kAXRoleAttribute) as String? == kAXWindowRole,
                      Self.value(element, kAXMinimizedAttribute) as Bool? != true else { continue }
                let subrole: String? = Self.value(element, kAXSubroleAttribute)
                guard subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let title: String = Self.value(element, kAXTitleAttribute) ?? ""
                result.windows.append(.init(id: id, title: title, element: element))
                subscribeWindow(id, element)
                if let focused, CFEqual(focused, element) { result.focused = id }
            }
        }
        result.windows.sort { ranks[$0.id, default: Int.max] < ranks[$1.id, default: Int.max] }
        // Drop off-Space, hidden, closed, and minimized window subscriptions. App-level
        // notifications and Space changes rediscover them without a background poll.
        let retained = Set(result.windows.map(\.id))
        for id in Array(subscribedWindows.keys) where !surfaceIDs.contains(id) ||
            (result.complete && !retained.contains(id)) {
            unsubscribeWindow(id)
        }
        return result
    }

    func validated(_ record: TrackedWindow) -> AXUIElement? {
        guard case .window(let pid, let number) = record.id,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, !app.isHidden,
              Self.onscreenWindows().contains(where: {
                  $0[kCGWindowOwnerPID as String] as? Int32 == pid &&
                  $0[kCGWindowNumber as String] as? UInt32 == number
              }), WindowIdentity.number(record.element) == number,
              Self.value(record.element, kAXRoleAttribute) as String? == kAXWindowRole,
              Self.value(record.element, kAXMinimizedAttribute) as Bool? != true else { return nil }
        return record.element
    }

    func prepareFocus(_ record: TrackedWindow) -> Bool {
        guard let element = validated(record) else { return false }
        let app = applications[record.id.pid] ?? AXUIElementCreateApplication(record.id.pid)
        AXUIElementSetMessagingTimeout(app, 0.06)
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        return true
    }

    func raise(_ record: TrackedWindow) -> Bool {
        guard let element = validated(record) else { return false }
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    func stop() {
        for pid in Array(observers.keys) { removeObserver(pid) }
        applications.removeAll()
    }

    private func subscribeApplication(_ pid: Int32, _ application: AXUIElement) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowNotification, &observer) == .success, let observer else { return }
        observers[pid] = observer
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in appNotifications { _ = AXObserverAddNotification(observer, application, name as CFString, context) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func subscribeWindow(_ id: SwitcherTargetID, _ element: AXUIElement) {
        if let previous = subscribedWindows[id], CFEqual(previous, element) { return }
        unsubscribeWindow(id)
        guard let observer = observers[id.pid] else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in windowNotifications { _ = AXObserverAddNotification(observer, element, name as CFString, context) }
        subscribedWindows[id] = element
    }

    private func unsubscribeWindow(_ id: SwitcherTargetID) {
        guard let element = subscribedWindows.removeValue(forKey: id), let observer = observers[id.pid] else { return }
        for name in windowNotifications { _ = AXObserverRemoveNotification(observer, element, name as CFString) }
    }

    private func removeObserver(_ pid: Int32) {
        for id in Array(subscribedWindows.keys) where id.pid == pid { unsubscribeWindow(id) }
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        applications[pid] = nil
    }
}

@MainActor
final class WindowTracker {
    nonisolated static var identityAvailable: Bool { WindowIdentity.function != nil }
    private(set) var records: [SwitcherTargetID: TrackedWindow] = [:]
    private(set) var history = WindowHistory()
    private(set) var focusedID: SwitcherTargetID?
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "local.lucas.VisibleTab.windows", qos: .userInitiated)
    private lazy var scanner = AXWindowScanner(onEvent: { [weak self] in
        DispatchQueue.main.async { self?.scheduleRefresh() }
    })
    private var enabled = false
    private var generation = 0
    private var inFlight = false
    private var refreshAgain = false
    private var refreshWork: DispatchWorkItem?
    private var inputs: [WindowApplication] = []
    private var frontmost: Int32?
    private var completions: [() -> Void] = []

    func invalidateSnapshot() {
        generation += 1
        records.removeAll()
        history = WindowHistory()
        focusedID = nil
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value && Self.identityAvailable
        generation += 1
        if !enabled {
            refreshWork?.cancel()
            refreshWork = nil
            completions.removeAll()
            records.removeAll()
            focusedID = nil
            history = WindowHistory()
            let scanner = self.scanner
            queue.async { scanner.stop() }
        }
    }

    func refresh(applications: [NSRunningApplication], frontmost: Int32?, completion: (() -> Void)? = nil) {
        self.inputs = applications.map { .init(pid: $0.processIdentifier, hidden: $0.isHidden) }
        self.frontmost = frontmost
        guard enabled else { completion?(); return }
        if let completion { completions.append(completion) }
        requestRefresh()
    }

    private func scheduleRefresh() {
        guard enabled else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            self.requestRefresh()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func requestRefresh() {
        guard enabled else { return }
        guard !inFlight else { refreshAgain = true; return }
        refreshWork?.cancel()
        refreshWork = nil
        inFlight = true
        let scanner = self.scanner, inputs = self.inputs, frontmost = self.frontmost, generation = self.generation
        let callbacks = completions
        completions.removeAll()
        queue.async { [weak self] in
            let snapshot = scanner.scan(inputs, frontmost: frontmost)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.enabled && self.generation == generation {
                    // A timed-out scan must not erase valid destinations already known.
                    let fresh = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    if snapshot.complete { self.records = fresh }
                    else {
                        let eligible = Set(AXWindowScanner.onscreenWindows().compactMap { surface -> SwitcherTargetID? in
                            guard let pid = surface[kCGWindowOwnerPID as String] as? Int32,
                                  let number = surface[kCGWindowNumber as String] as? UInt32,
                                  inputs.contains(where: { $0.pid == pid && !$0.hidden }) else { return nil }
                            return .window(pid: pid, number: number)
                        })
                        self.records = self.records.filter { eligible.contains($0.key) }
                        self.records.merge(fresh, uniquingKeysWith: { _, new in new })
                    }
                    let oldOrder = self.history.order.filter { self.records[$0] != nil }
                    self.history.update(frontToBack: snapshot.windows.map(\.id) + oldOrder)
                    self.focusedID = snapshot.focused
                    self.history.activate(snapshot.focused)
                    self.onChange?()
                    callbacks.forEach { $0() }
                }
                if self.refreshAgain || !self.completions.isEmpty {
                    self.refreshAgain = false
                    self.requestRefresh()
                }
            }
        }
    }

    func focus(_ id: SwitcherTargetID, completion: @escaping (Bool) -> Void) {
        guard enabled, let record = records[id] else { completion(false); return }
        let scanner = self.scanner, generation = self.generation
        queue.async { [weak self] in
            let prepared = scanner.prepareFocus(record)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled, generation == self.generation, prepared,
                      let app = NSRunningApplication(processIdentifier: id.pid), !app.isHidden, !app.isTerminated,
                      app.activate(options: []) else { completion(false); return }
                self.queue.async {
                    let raised = scanner.raise(record)
                    DispatchQueue.main.async { completion(raised) }
                }
            }
        }
    }
}

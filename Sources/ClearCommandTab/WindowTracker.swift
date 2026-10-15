import AppKit
import ApplicationServices
import Darwin
import ClearCommandTabCore

struct WindowApplication: Sendable {
    let pid: Int32
    let hidden: Bool
}

// AX references are retained for off-main discovery and validated focus actions.
struct TrackedWindow: @unchecked Sendable {
    let id: SwitcherTargetID
    let title: String
    let element: AXUIElement
}

private struct WindowSnapshot: Sendable {
    var windows: [TrackedWindow] = []
    var focused: SwitcherTargetID?
    var complete = true
    var foregroundBounds: CGRect?
    var eligibleIDs: Set<SwitcherTargetID> = []
}

/// Optional identity bridge shared by discovery and the focus coordinator.
enum WindowIdentity {
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

/// Discovery reads and subscription bookkeeping run on one serial queue.
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
        let visiblePIDs = Set(inputs.filter { !$0.hidden }.map(\.pid))
        result.eligibleIDs = surfaceIDs.filter { visiblePIDs.contains($0.pid) }
        if let bounds = surfaces.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == frontmost })?[kCGWindowBounds as String] as? NSDictionary {
            result.foregroundBounds = CGRect(dictionaryRepresentation: bounds)
        }
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
    private(set) var foregroundBounds: CGRect?
    // One MRU window per app survives Hide. The focus queue rechecks WindowServer
    // ownership before using its ID; a slow AX main-window query is then unnecessary.
    private var recentAppWindows: [Int32: TrackedWindow] = [:]
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "local.lucas.VisibleTab.windows", qos: .utility)
    private var focusEpoch = WindowSnapshotEpoch()
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
        focusEpoch.setTransitioning(false)
        generation += 1
        records.removeAll()
        recentAppWindows.removeAll()
        history = WindowHistory()
        focusedID = nil
        foregroundBounds = nil
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value && Self.identityAvailable
        generation += 1
        if !enabled {
            focusEpoch.setTransitioning(false)
            refreshWork?.cancel()
            refreshWork = nil
            completions.removeAll()
            records.removeAll()
            recentAppWindows.removeAll()
            focusedID = nil
            history = WindowHistory()
            let scanner = self.scanner
            queue.async { scanner.stop() }
        }
    }

    func refresh(applications: [WindowApplication], frontmost: Int32?, completion: (() -> Void)? = nil) {
        self.inputs = applications
        let livePIDs = Set(applications.map(\.pid))
        recentAppWindows = recentAppWindows.filter { livePIDs.contains($0.key) }
        updateFrontmost(frontmost)
        guard enabled else { completion?(); return }
        if let completion { completions.append(completion) }
        requestRefresh()
    }

    private func scheduleRefresh() {
        guard enabled else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.updateFrontmost(NSWorkspace.shared.frontmostApplication?.processIdentifier)
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
        let focusRevision = focusEpoch.revision
        let callbacks = completions
        completions.removeAll()
        queue.async { [weak self] in
            let snapshot = scanner.scan(inputs, frontmost: frontmost)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.enabled && self.generation == generation && self.focusEpoch.accepts(focusRevision) {
                    // A timed-out scan must not erase valid destinations already known.
                    let fresh = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    if snapshot.complete { self.records = fresh }
                    else {
                        self.records = self.records.filter { snapshot.eligibleIDs.contains($0.key) }
                        self.records.merge(fresh, uniquingKeysWith: { _, new in new })
                    }
                    let oldOrder = self.history.order.filter { self.records[$0] != nil }
                    self.history.update(frontToBack: snapshot.windows.map(\.id) + oldOrder)
                    if self.focusEpoch.canRecordFocus {
                        self.focusedID = snapshot.focused
                        self.foregroundBounds = snapshot.foregroundBounds
                        self.history.activate(snapshot.focused)
                    }
                    for id in self.history.order.reversed() {
                        if let record = self.records[id] { self.recentAppWindows[id.pid] = record }
                    }
                    self.onChange?()
                    callbacks.forEach { $0() }
                } else if self.enabled && self.generation == generation {
                    // Preserve cold-discovery callbacks while discarding an old focus
                    // snapshot. The next pass reads the latest foreground inputs.
                    self.completions.insert(contentsOf: callbacks, at: 0)
                    self.refreshAgain = true
                }
                if self.refreshAgain || !self.completions.isEmpty {
                    self.refreshAgain = false
                    self.requestRefresh()
                }
            }
        }
    }

    func setFocusTransition(_ active: Bool) {
        guard active || focusEpoch.transitioning else { return }
        focusEpoch.setTransitioning(active)
        if !active { requestRefresh() }
    }

    func recordConfirmedFocus(pid: Int32, window: SwitcherTargetID?) {
        updateFrontmost(pid)
        focusedID = window
        history.activate(window)
        if let window, let record = records[window] { recentAppWindows[pid] = record }
        onChange?()
    }

    func preferredWindow(for pid: Int32) -> TrackedWindow? {
        if let id = history.order.first(where: { $0.pid == pid }), let record = records[id] { return record }
        return recentAppWindows[pid]
    }

    private func updateFrontmost(_ pid: Int32?) {
        guard frontmost != pid else { return }
        frontmost = pid
        focusEpoch.invalidate()
        if focusedID?.pid != pid { focusedID = nil }
    }
}

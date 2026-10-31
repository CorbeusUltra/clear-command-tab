import AppKit
import ApplicationServices
import Darwin
import ClearCommandTabCore

struct WindowApplication: Sendable, Equatable {
    let pid: Int32
    let hidden: Bool
}

// AX references are retained for off-main discovery and validated focus actions.
struct TrackedWindow: @unchecked Sendable {
    let id: SwitcherTargetID
    let title: String
    let element: AXUIElement
}

struct WindowButtonRegion: Sendable, Equatable {
    let pid: Int32
    let bounds: CGRect // Quartz screen coordinates, as supplied by Accessibility.
    var windowBounds: CGRect? = nil
}

struct WindowGeometryChange: @unchecked Sendable {
    let pid: Int32
    let element: AXUIElement
}

struct WindowScanRequest: Sendable {
    let applications: [WindowApplication]
    let frontmost: Int32?
    let dirtyPIDs: Set<Int32>? // nil requests a full initial/Space scan
    let geometry: [WindowGeometryChange]
    let tracksTitles: Bool
    let tracksMinimizeButtons: Bool
}

struct WindowSnapshot: Sendable {
    var windows: [TrackedWindow] = []
    var focused: SwitcherTargetID?
    var complete = true
    var foregroundBounds: CGRect?
    var eligibleIDs: Set<SwitcherTargetID> = []
    var completedPIDs: Set<Int32> = []
    var buttonRegions: [WindowButtonRegion] = []
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

private let windowNotification: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    Unmanaged<AXWindowScanner>.fromOpaque(context).takeUnretainedValue().onEvent(pid, element, notification as String)
}

/// Discovery reads and subscription bookkeeping run on one serial queue.
/// Notification sources are attached to the main run loop; callbacks only schedule work.
private final class AXWindowScanner: @unchecked Sendable {
    let onEvent: @Sendable (Int32, AXUIElement, String) -> Void
    private var observers: [Int32: AXObserver] = [:]
    private var applications: [Int32: AXUIElement] = [:]
    private var subscribedWindows: [SwitcherTargetID: AXUIElement] = [:]
    private let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                    kAXMainWindowChangedNotification]
    private var tracksTitles = true
    private struct ButtonEntry { let window: AXUIElement; let region: WindowButtonRegion; let id: SwitcherTargetID }
    private var buttonRegions: [Int32: [ButtonEntry]] = [:]
    private var windowNotifications: [String] { [kAXUIElementDestroyedNotification,
                                       kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                                       kAXMovedNotification, kAXResizedNotification] + (tracksTitles ? [kAXTitleChangedNotification] : []) }

    init(onEvent: @escaping @Sendable (Int32, AXUIElement, String) -> Void) { self.onEvent = onEvent }

    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }

    static func onscreenWindows(normalOnly: Bool = true) -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).filter {
            (!normalOnly || ($0[kCGWindowLayer as String] as? Int) == 0) &&
            ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
    }

    func scan(_ request: WindowScanRequest) -> WindowSnapshot {
        let inputs = request.applications, frontmost = request.frontmost
        let deadline = ProcessInfo.processInfo.systemUptime + 0.7
        if tracksTitles != request.tracksTitles {
            for id in Array(subscribedWindows.keys) { unsubscribeWindow(id) }
            tracksTitles = request.tracksTitles
        }
        let livePIDs = Set(inputs.map(\.pid))
        for pid in Array(observers.keys) where !livePIDs.contains(pid) { removeObserver(pid) }
        let allSurfaces = Self.onscreenWindows(normalOnly: false)
        let surfaces = allSurfaces.filter { $0[kCGWindowLayer as String] as? Int == 0 }
        var windowBounds: [SwitcherTargetID: CGRect] = [:]
        if request.tracksMinimizeButtons {
            for surface in allSurfaces {
                if let pid = surface[kCGWindowOwnerPID as String] as? Int32,
                   let number = surface[kCGWindowNumber as String] as? UInt32,
                   let bounds = surface[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: bounds) {
                    windowBounds[.window(pid: pid, number: number)] = rect
                }
            }
        }
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
        buttonRegions = buttonRegions.filter { visiblePIDs.contains($0.key) }.mapValues {
            $0.filter { surfaceIDs.contains($0.id) }
        }
        if !request.tracksMinimizeButtons { buttonRegions.removeAll() }
        else {
            for change in request.geometry where visiblePIDs.contains(change.pid) &&
                !(request.dirtyPIDs?.contains(change.pid) ?? true) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                var entries = buttonRegions[change.pid] ?? []
                let previousID = entries.first { CFEqual($0.window, change.element) }?.id
                entries.removeAll { CFEqual($0.window, change.element) }
                if let id = previousID ?? WindowIdentity.number(change.element).map({ .window(pid: change.pid, number: $0) }),
                   surfaceIDs.contains(id), let region = minimizeRegion(change.element, pid: change.pid, fallback: windowBounds[id]) {
                    entries.append(ButtonEntry(window: change.element, region: region, id: id))
                }
                buttonRegions[change.pid] = entries
            }
        }
        result.eligibleIDs = surfaceIDs.filter { visiblePIDs.contains($0.pid) }
        if let bounds = surfaces.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == frontmost })?[kCGWindowBounds as String] as? NSDictionary {
            result.foregroundBounds = CGRect(dictionaryRepresentation: bounds)
        }
        // Foreground first, then WindowServer order, so a slow app cannot delay that target.
        var appRanks: [Int32: Int] = [:]
        for (index, surface) in surfaces.enumerated() {
            if let pid = surface[kCGWindowOwnerPID as String] as? Int32, appRanks[pid] == nil { appRanks[pid] = index }
        }
        let orderedInputs = inputs.filter { request.dirtyPIDs?.contains($0.pid) ?? true }.sorted { lhs, rhs in
            if (lhs.pid == frontmost) != (rhs.pid == frontmost) { return lhs.pid == frontmost }
            let left = appRanks[lhs.pid] ?? Int.max
            let right = appRanks[rhs.pid] ?? Int.max
            return left == right ? lhs.pid < rhs.pid : left < right
        }
        for input in orderedInputs {
            guard ProcessInfo.processInfo.systemUptime < deadline else { result.complete = false; break }
            let application = applications[input.pid] ?? AXUIElementCreateApplication(input.pid)
            AXUIElementSetMessagingTimeout(application, 0.06)
            applications[input.pid] = application
            subscribeApplication(input.pid, application)
            guard !input.hidden, appRanks[input.pid] != nil else {
                result.completedPIDs.insert(input.pid)
                buttonRegions[input.pid] = nil
                continue
            }
            var buttons: [ButtonEntry] = []
            var appComplete = true
            let reportedWindows: [AXUIElement]? = Self.value(application, kAXWindowsAttribute)
            var elements = reportedWindows ?? []
            let focused: AXUIElement? = input.pid == frontmost ? Self.value(application, kAXFocusedWindowAttribute) : nil
            if let focused, !elements.contains(where: { CFEqual($0, focused) }) { elements.append(focused) }
            if elements.isEmpty, let main: AXUIElement = Self.value(application, kAXMainWindowAttribute) {
                elements.append(main)
            }
            if reportedWindows == nil && elements.isEmpty {
                // Missing IPC evidence must not erase still-eligible cached data.
                result.complete = false
                continue
            }
            for element in elements.prefix(128) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { result.complete = false; appComplete = false; break }
                AXUIElementSetMessagingTimeout(element, 0.06)
                guard let number = WindowIdentity.number(element) else { continue }
                let id = SwitcherTargetID.window(pid: input.pid, number: number)
                guard surfaceIDs.contains(id), Self.value(element, kAXRoleAttribute) as String? == kAXWindowRole,
                      Self.value(element, kAXMinimizedAttribute) as Bool? != true else { continue }
                let subrole: String? = Self.value(element, kAXSubroleAttribute)
                guard subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let title: String = request.tracksTitles ? (Self.value(element, kAXTitleAttribute) ?? "") : ""
                result.windows.append(.init(id: id, title: title, element: element))
                if request.tracksMinimizeButtons, let region = minimizeRegion(element, pid: input.pid, fallback: windowBounds[id]) {
                    buttons.append(ButtonEntry(window: element, region: region, id: id))
                }
                subscribeWindow(id, element)
                if let focused, CFEqual(focused, element) { result.focused = id }
            }
            if appComplete {
                result.completedPIDs.insert(input.pid)
                buttonRegions[input.pid] = buttons
            }
        }
        result.windows.sort { ranks[$0.id, default: Int.max] < ranks[$1.id, default: Int.max] }
        // Drop off-Space, hidden, closed, and minimized window subscriptions. App-level
        // notifications and Space changes rediscover them without a background poll.
        let retained = Set(result.windows.map(\.id))
        for id in Array(subscribedWindows.keys) where !surfaceIDs.contains(id) ||
            (result.completedPIDs.contains(id.pid) && !retained.contains(id)) {
            unsubscribeWindow(id)
        }
        if request.tracksMinimizeButtons {
            let known = Dictionary(buttonRegions.values.flatMap { $0.map { ($0.id, $0.region) } },
                                   uniquingKeysWith: { first, _ in first })
            // Unknown AX controls, incomplete discovery and floating panels keep
            // the original public hit-test path, scoped to their window bounds.
            // This is a fallback for missing metadata, never an app whitelist.
            // Preserve WindowServer z-order: an unknown background window must
            // not make ordinary clicks in a known foreground window expensive.
            result.buttonRegions = allSurfaces.compactMap { surface in
                guard let pid = surface[kCGWindowOwnerPID as String] as? Int32,
                      let number = surface[kCGWindowNumber as String] as? UInt32,
                      let rect = windowBounds[.window(pid: pid, number: number)] else { return nil }
                return WindowButtonRegion(pid: pid, bounds: known[.window(pid: pid, number: number)]?.bounds ?? rect,
                                          windowBounds: rect)
            }
        }
        return result
    }

    private func minimizeRegion(_ window: AXUIElement, pid: Int32, fallback: CGRect?) -> WindowButtonRegion? {
        let unknown = fallback.map { WindowButtonRegion(pid: pid, bounds: $0) }
        AXUIElementSetMessagingTimeout(window, 0.01)
        guard let button: AXUIElement = Self.value(window, kAXMinimizeButtonAttribute) else { return unknown }
        AXUIElementSetMessagingTimeout(button, 0.01)
        guard Self.value(button, kAXEnabledAttribute) as Bool? == true,
              let position: AXValue = Self.value(button, kAXPositionAttribute),
              let size: AXValue = Self.value(button, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return unknown }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return unknown }
        return WindowButtonRegion(pid: pid, bounds: CGRect(origin: point, size: extent))
    }

    func stop() {
        for pid in Array(observers.keys) { removeObserver(pid) }
        applications.removeAll()
        buttonRegions.removeAll()
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
        buttonRegions[pid] = nil
    }
}

@MainActor
final class WindowTracker {
    nonisolated static var identityAvailable: Bool { WindowIdentity.function != nil }
    private(set) var records: [SwitcherTargetID: TrackedWindow] = [:]
    private(set) var history = WindowHistory()
    private(set) var focusedID: SwitcherTargetID?
    private(set) var foregroundBounds: CGRect?
    private(set) var minimizeButtonRegions: [WindowButtonRegion] = []
    private(set) var minimizeButtonsReady = false
    // One MRU window per app survives Hide. The focus queue rechecks WindowServer
    // ownership before using its ID; a slow AX main-window query is then unnecessary.
    private var recentAppWindows: [Int32: TrackedWindow] = [:]
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".windows", qos: .utility)
    private var focusEpoch = WindowSnapshotEpoch()
    private lazy var scanner = AXWindowScanner(onEvent: { [weak self] pid, element, notification in
        let change = WindowGeometryChange(pid: pid, element: element)
        DispatchQueue.main.async { self?.windowChanged(pid: change.pid, element: change.element, notification: notification) }
    })
    private let tracksTitles: Bool
    private var tracksMinimizeButtons = false
    private let scanOverride: ((WindowScanRequest) -> WindowSnapshot)?
    private var fullScanRequired = true
    private var dirtyPIDs: Set<Int32> = []
    private var geometryChanges: [Int32: [AXUIElement]] = [:]
    private var enabled = false
    private var generation = 0
    private var inFlight = false
    private var refreshAgain = false
    private var refreshWork: DispatchWorkItem?
    private var inputs: [WindowApplication] = []
    private var frontmost: Int32?
    private var completions: [() -> Void] = []

    init(tracksTitles: Bool = true, scan: ((WindowScanRequest) -> WindowSnapshot)? = nil) {
        self.tracksTitles = tracksTitles
        scanOverride = scan
    }

    func setTracksMinimizeButtons(_ value: Bool) {
        guard tracksMinimizeButtons != value else { return }
        tracksMinimizeButtons = value
        fullScanRequired = true
        if !value { minimizeButtonRegions.removeAll(); minimizeButtonsReady = false; onChange?() }
        requestRefresh()
    }

    func invalidateSnapshot() {
        focusEpoch.setTransitioning(false)
        generation += 1
        fullScanRequired = true
        records.removeAll()
        recentAppWindows.removeAll()
        history = WindowHistory()
        focusedID = nil
        foregroundBounds = nil
        minimizeButtonRegions.removeAll()
        minimizeButtonsReady = false
        onChange?()
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value && Self.identityAvailable
        generation += 1
        fullScanRequired = true
        if !enabled {
            focusEpoch.setTransitioning(false)
            refreshWork?.cancel()
            refreshWork = nil
            completions.removeAll()
            records.removeAll()
            recentAppWindows.removeAll()
            focusedID = nil
            history = WindowHistory()
            minimizeButtonRegions.removeAll()
            minimizeButtonsReady = false
            geometryChanges.removeAll()
            dirtyPIDs.removeAll()
            refreshAgain = false
            onChange?()
            let scanner = self.scanner
            queue.async { scanner.stop() }
        }
    }

    func refresh(applications: [WindowApplication], frontmost: Int32?, completion: (() -> Void)? = nil) {
        let previous = Dictionary(inputs.map { ($0.pid, $0.hidden) }, uniquingKeysWith: { first, _ in first })
        for app in applications where previous[app.pid] != app.hidden { dirtyPIDs.insert(app.pid) }
        if inputs.contains(where: { old in !applications.contains(where: { $0.pid == old.pid }) }) {
            // Also let the scanner remove terminated observers and cached regions.
            fullScanRequired = true
        }
        self.inputs = applications
        let livePIDs = Set(applications.map(\.pid))
        recentAppWindows = recentAppWindows.filter { livePIDs.contains($0.key) }
        updateFrontmost(frontmost)
        guard enabled else { completion?(); return }
        if let completion { completions.append(completion) }
        requestRefresh()
    }

    func windowChanged(pid: Int32, element: AXUIElement, notification: String) {
        guard enabled else { return }
        if notification == kAXMovedNotification || notification == kAXResizedNotification {
            guard tracksMinimizeButtons || pid == frontmost else { return }
            var elements = geometryChanges[pid] ?? []
            if !elements.contains(where: { CFEqual($0, element) }) {
                // Coalesce a bounded number of actual changed windows per app.
                if elements.count < 16 { elements.append(element) }
                else { dirtyPIDs.insert(pid) }
            }
            geometryChanges[pid] = elements
        } else { dirtyPIDs.insert(pid) }
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
        if !completions.isEmpty, !fullScanRequired, dirtyPIDs.isEmpty, geometryChanges.isEmpty {
            if let frontmost { dirtyPIDs.insert(frontmost) } else { fullScanRequired = true }
        }
        guard fullScanRequired || !dirtyPIDs.isEmpty || !geometryChanges.isEmpty else { return }
        refreshWork?.cancel()
        refreshWork = nil
        inFlight = true
        let scanner = self.scanner, inputs = self.inputs, frontmost = self.frontmost, generation = self.generation
        let request = WindowScanRequest(applications: inputs, frontmost: frontmost,
            dirtyPIDs: fullScanRequired ? nil : dirtyPIDs,
            geometry: geometryChanges.flatMap { pid, elements in elements.map { WindowGeometryChange(pid: pid, element: $0) } },
            tracksTitles: tracksTitles, tracksMinimizeButtons: tracksMinimizeButtons)
        let scan = scanOverride
        fullScanRequired = false
        dirtyPIDs.removeAll()
        geometryChanges.removeAll()
        let focusRevision = focusEpoch.revision
        let callbacks = completions
        completions.removeAll()
        queue.async { [weak self] in
            let snapshot = autoreleasepool { scan?(request) ?? scanner.scan(request) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.enabled && self.generation == generation && self.focusEpoch.accepts(focusRevision) {
                    // A timed-out scan must not erase valid destinations already known.
                    let fresh = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    self.records = self.records.filter {
                        snapshot.eligibleIDs.contains($0.key) && !snapshot.completedPIDs.contains($0.key.pid)
                    }
                    self.records.merge(fresh, uniquingKeysWith: { _, new in new })
                    self.minimizeButtonRegions = self.tracksMinimizeButtons ? snapshot.buttonRegions : []
                    self.minimizeButtonsReady = self.tracksMinimizeButtons
                    let oldOrder = self.history.order.filter { self.records[$0] != nil }
                    self.history.update(frontToBack: snapshot.windows.map(\.id) + oldOrder)
                    if self.focusEpoch.canRecordFocus {
                        if snapshot.completedPIDs.contains(self.frontmost ?? -1) { self.focusedID = snapshot.focused }
                        else if let id = self.focusedID, self.records[id] == nil { self.focusedID = nil }
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
                    if let pids = request.dirtyPIDs { self.dirtyPIDs.formUnion(pids) }
                    else { self.fullScanRequired = true }
                    for change in request.geometry {
                        self.dirtyPIDs.insert(change.pid)
                    }
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
        if !active {
            if let frontmost { dirtyPIDs.insert(frontmost) }
            requestRefresh()
        }
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
        if let old = frontmost { dirtyPIDs.insert(old) }
        if let pid { dirtyPIDs.insert(pid) }
        frontmost = pid
        focusEpoch.invalidate()
        if focusedID?.pid != pid { focusedID = nil }
    }
}

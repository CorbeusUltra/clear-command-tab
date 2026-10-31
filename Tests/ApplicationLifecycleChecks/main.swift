import AppKit
import ClearCommandTabCore

private final class DynamicArtwork {
    private let lock = NSLock()
    private var image: CGImage?
    private var reads: [Int32: Int] = [:]
    init(_ image: CGImage?) { self.image = image }
    func set(_ image: CGImage?) { lock.lock(); defer { lock.unlock() }; self.image = image }
    func resolve(_ pid: Int32) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        reads[pid, default: 0] += 1
        return image
    }
    func count(_ pid: Int32) -> Int { lock.lock(); defer { lock.unlock() }; return reads[pid, default: 0] }
}

private final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    var writes = 0
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value; writes += 1 }
}

private final class ObservableLaunchFixture: NSObject {
    @objc dynamic var ready = false
    var onDeinit: (() -> Void)?
    deinit { onDeinit?() }
}

private final class BlockingArtwork {
    private let lock = NSLock()
    private var blocked = false
    private var armed = false
    private var count = 0
    private var image: CGImage
    let release = DispatchSemaphore(value: 0)
    init(_ image: CGImage) { self.image = image }
    func arm(image: CGImage) { lock.lock(); self.image = image; armed = true; blocked = false; lock.unlock() }
    func snapshot() -> (blocked: Bool, count: Int) { lock.lock(); defer { lock.unlock() }; return (blocked, count) }
    func resolve() -> CGImage {
        lock.lock()
        count += 1
        let shouldBlock = armed && !blocked
        if shouldBlock { blocked = true; armed = false }
        let output = image
        lock.unlock()
        if shouldBlock { _ = release.wait(timeout: .now() + 3) }
        return output
    }
}

private final class ScanRecorder {
    private let lock = NSLock()
    private var requests: [WindowScanRequest] = []
    func all() -> [WindowScanRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    func scan(_ request: WindowScanRequest) -> WindowSnapshot {
        lock.lock(); requests.append(request); lock.unlock()
        var snapshot = WindowSnapshot()
        for app in request.applications where !app.hidden {
            snapshot.eligibleIDs.insert(.window(pid: app.pid, number: UInt32(app.pid)))
        }
        for app in request.applications where request.dirtyPIDs?.contains(app.pid) ?? true {
            snapshot.completedPIDs.insert(app.pid)
            if !app.hidden {
                snapshot.windows.append(TrackedWindow(id: .window(pid: app.pid, number: UInt32(app.pid)),
                    title: "", element: AXUIElementCreateApplication(app.pid)))
            }
        }
        return snapshot
    }
}

// Local notification centers and injected liveness never quit, hide, focus or
// otherwise modify a user's app. Only the disposable /bin/sleep child is stopped.
@MainActor func run() -> Int32 {
    var failures = 0
    var checks = 0
    func check(_ value: Bool, _ label: String) {
        checks += 1
        if !value { failures += 1 }
        print("\(value ? "PASS" : "FAIL") \(label)")
    }
    func wait(_ timeout: Double = 2, until predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return predicate()
    }
    // Replacing a workspace wrapper must not destroy an observed object before
    // its KVO registration has been removed. No user process is modified here.
    weak var watched: ObservableLaunchFixture?
    var registration: RetainedObservation<ObservableLaunchFixture>?
    var finished = 0
    var released = false
    autoreleasepool {
        let processWrapper = ObservableLaunchFixture()
        watched = processWrapper
        processWrapper.onDeinit = { released = true }
        registration = RetainedObservation(processWrapper, keyPath: \.ready) { object in
            if object.ready { finished += 1 }
        }
    }
    check(watched != nil && !released, "observation retains its source after the workspace drops a wrapper")
    watched?.ready = true
    check(finished == 1, "launch observation remains live after the workspace replaces its wrapper")
    registration?.invalidate()
    watched?.ready = false
    watched?.ready = true
    check(finished == 1, "explicit invalidation prevents further launch callbacks")
    autoreleasepool { registration = nil }
    check(watched == nil && released, "retiring the observer releases its source without a retained cycle")
    for _ in 0..<250 {
        autoreleasepool {
            let wrapper = ObservableLaunchFixture()
            let observation = RetainedObservation(wrapper, keyPath: \.ready) { _ in }
            withExtendedLifetime(observation) {}
        }
    }
    check(true, "repeated observation teardown safely unregisters before releasing its source")
    let apps = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    guard apps.count >= 2 else {
        print("SKIP: lifecycle checks need two existing regular apps; none are launched")
        return 77
    }
    let target = apps[0], pid = target.processIdentifier
    var nativeInitialCallbacks = 0
    for _ in 0..<100 {
        autoreleasepool {
            guard let wrapper = NSRunningApplication(processIdentifier: pid) else { return }
            let observation = RetainedObservation(wrapper, keyPath: \.isFinishedLaunching) { _ in
                nativeInitialCallbacks += 1
            }
            withExtendedLifetime(observation) {}
        }
    }
    check(nativeInitialCallbacks == 100, "native process-wrapper observations survive repeated autorelease and teardown")
    let center = NotificationCenter()
    let defaults = MemoryDefaults()
    let tracker = ApplicationTracker(defaults: defaults, notificationCenter: center,
                                     runningApplications: { apps })
    let initialOrder = tracker.history.order
    var changeCount = 0
    tracker.onChange = { _ in changeCount += 1 }
    check(tracker.applications[pid] != nil, "live app enters tracker")
    var selection = SelectionSession(ids: initialOrder, currentID: nil)
    selection.select(pid)
    let oldIndex = initialOrder.firstIndex(of: pid)!
    let successor = initialOrder[(oldIndex + 1) % initialOrder.count]
    center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: target])
    check(tracker.applications[pid] == nil && !tracker.history.order.contains(pid),
          "termination removes app immediately despite stale workspace list")
    check(tracker.presentations[pid] == nil && tracker.icons[pid] == nil,
          "termination clears cached presentation and artwork")
    check(tracker.history.order == initialOrder.filter { $0 != pid }, "termination preserves survivor MRU")
    check(changeCount == 1, "termination notifies selection reconciliation once")
    selection.reconcile(visibleIDs: tracker.history.order)
    check(selection.selectedID == successor, "terminated selection moves to its original successor")
    tracker.refresh()
    check(tracker.applications[pid] == nil, "stale enumeration cannot resurrect terminated instance")
    center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: target])
    check(tracker.applications[pid] == nil && changeCount == 1,
          "late activation cannot resurrect terminated instance")
    check(!tracker.windowInputs.contains { $0.pid == pid }, "terminated app leaves window-discovery inputs")

    let fallbackCenter = NotificationCenter()
    var dead: Set<Int32> = []
    let fallback = ApplicationTracker(defaults: defaults, notificationCenter: fallbackCenter,
        runningApplications: { apps }, processIsRunning: { !dead.contains($0) })
    var fallbackChanges = 0
    fallback.onChange = { _ in fallbackChanges += 1 }
    dead.insert(pid)
    fallback.pruneTerminatedApplications()
    check(fallback.applications[pid] == nil && !fallback.history.order.contains(pid),
          "kernel-liveness backstop removes app when workspace event is missing")
    fallback.pruneTerminatedApplications()
    check(fallbackChanges == 1, "repeated pruning does not cause redundant changes")
    fallback.refresh()
    check(fallback.applications[pid] == nil, "refresh excludes process reported dead")
    let remaining = apps.filter { $0.processIdentifier != pid }
    for app in remaining { dead.insert(app.processIdentifier) }
    fallback.pruneTerminatedApplications()
    check(fallback.history.order.isEmpty && fallback.windowInputs.isEmpty,
          "all-app termination empties both switching and discovery")
    selection.reconcile(visibleIDs: fallback.history.order)
    check(selection.selectedID == nil, "last-app termination ends selection safely")

    check(ApplicationTracker.processIsRunning(ProcessInfo.processInfo.processIdentifier), "kernel probe recognizes live process")
    check(!ApplicationTracker.processIsRunning(-1) && !ApplicationTracker.processIsRunning(0), "kernel probe rejects invalid IDs")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    do {
        try child.run()
        check(ApplicationTracker.processIsRunning(child.processIdentifier), "kernel probe recognizes disposable child")
        child.terminate()
        child.waitUntilExit()
        check(!ApplicationTracker.processIsRunning(child.processIdentifier), "kernel probe detects actual exited process")
    } catch { check(false, "disposable child could not launch: \(error)") }

    // Change only this test process's appearance, never the user's system theme.
    let localApp = NSApplication.shared
    let originalAppearance = localApp.appearance
    defer { localApp.appearance = originalAppearance }
    localApp.appearance = NSAppearance(named: .aqua)
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let oldImage = ApplicationIcon.rasterize(NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.red.setFill(); rect.fill(); return true
    })!
    let newImage = ApplicationIcon.rasterize(NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.blue.setFill(); rect.fill(); return true
    })!
    var loads = 0
    var appearances: [NSAppearance.Name?] = []
    let appearanceTracker = ApplicationTracker(defaults: defaults, notificationCenter: NotificationCenter(),
        runningApplications: { [target] }, iconResolver: { _, _, appearance in
            loads += 1
            appearances.append(appearance.bestMatch(from: [.aqua, .darkAqua]))
            if loads == 1 {
                started.signal()
                _ = release.wait(timeout: .now() + 3)
                return oldImage
            }
            return newImage
        })
    var published: [CGImage] = []
    appearanceTracker.onIconsChanged = {
        if let image = appearanceTracker.icons[pid] { published.append(image) }
    }
    check(started.wait(timeout: .now() + 2) == .success, "initial icon load starts off the UI loop")
    localApp.appearance = NSAppearance(named: .darkAqua)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    release.signal()
    let iconDeadline = Date().addingTimeInterval(3)
    while published.isEmpty && Date() < iconDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    check(!published.isEmpty && published.allSatisfy { $0 === newImage },
          "appearance observation rejects in-flight old artwork before publishing refreshed icons")
    check(appearanceTracker.icons[pid] === newImage && appearances.first! == .aqua && appearances.last! == .darkAqua,
          "deferred refresh captures the latest appearance without another app activation")
    appearanceTracker.onIconsChanged = nil

    // Same public resolver contract for any app: runtime pixels may change, stay
    // unchanged, or become temporarily unavailable. No Dock drawing is fabricated.
    let otherPID = apps[1].processIdentifier
    let artwork = DynamicArtwork(oldImage)
    let dynamicTracker = ApplicationTracker(defaults: defaults, notificationCenter: NotificationCenter(),
        runningApplications: { Array(apps.prefix(2)) }, launchIconRetryDelays: [],
        iconResolver: { app, _, _ in artwork.resolve(app.processIdentifier) })
    check(wait { dynamicTracker.icons.count == 2 }, "initial artwork cache resolves asynchronously for arbitrary apps")
    var changes = 0
    dynamicTracker.onIconsChanged = { changes += 1 }
    let initialReads = artwork.count(pid), otherReads = artwork.count(otherPID)
    dynamicTracker.setVisibleIconTargets([pid], selected: pid)
    check(wait { artwork.count(pid) > initialReads }, "panel presentation schedules a targeted icon refresh")
    check(changes == 0, "unchanged icon pixels do not redraw the panel")
    artwork.set(newImage)
    check(wait { dynamicTracker.icons[pid] === newImage }, "visible runtime icon change refreshes without activation")
    check(dynamicTracker.icons[otherPID] === oldImage && artwork.count(otherPID) == otherReads,
          "apps outside the displayed set are never polled by visible refresh")
    let validChanges = changes, readsBeforeFailure = artwork.count(pid)
    artwork.set(nil)
    check(wait { artwork.count(pid) > readsBeforeFailure }, "visible resolver can report temporarily unavailable artwork")
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    check(dynamicTracker.icons[pid] === newImage && changes == validChanges,
          "failed refresh preserves the last correct icon without inventing content")
    let sameBlue = ApplicationIcon.rasterize(NSImage(cgImage: newImage, size: .init(width: 320, height: 320)))!
    artwork.set(sameBlue)
    let beforeSamePixels = artwork.count(pid)
    check(wait { artwork.count(pid) > beforeSamePixels }, "visible refresh also checks replacement image objects")
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    check(dynamicTracker.icons[pid] === newImage && changes == validChanges,
          "replacement NSImage with identical pixels does not invalidate cached drawing")
    artwork.set(oldImage)
    dynamicTracker.setVisibleIconTargets([pid, otherPID], selected: otherPID)
    check(wait { dynamicTracker.icons[pid] === oldImage && artwork.count(otherPID) > otherReads },
          "selection priority and round robin cover all displayed apps without a whitelist")
    dynamicTracker.setVisibleIconTargets([], selected: nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let stoppedReads = artwork.count(pid) + artwork.count(otherPID)
    _ = wait(1.1) { false }
    check(artwork.count(pid) + artwork.count(otherPID) == stoppedReads,
          "closing the selector stops all periodic icon refresh")

    let queuedArtwork = BlockingArtwork(oldImage)
    let queuedTracker = ApplicationTracker(defaults: MemoryDefaults(), notificationCenter: NotificationCenter(),
        runningApplications: { Array(apps.prefix(2)) }, launchIconRetryDelays: [],
        iconResolver: { _, _, _ in queuedArtwork.resolve() })
    check(wait { queuedTracker.icons.count == 2 }, "cancellation test begins with a warm icon cache")
    let warmReads = queuedArtwork.snapshot().count
    queuedArtwork.arm(image: oldImage)
    queuedTracker.setVisibleIconTargets([pid, otherPID], selected: pid)
    check(wait { queuedArtwork.snapshot().blocked }, "visibility refresh can be blocked independently of main loop")
    queuedTracker.setVisibleIconTargets([], selected: nil)
    queuedArtwork.release.signal()
    _ = wait(0.15) { false }
    check(queuedArtwork.snapshot().count == warmReads + 1,
          "queued visibility work is skipped before resolving after panel closure")
    queuedArtwork.arm(image: newImage)
    queuedTracker.setVisibleIconTargets([pid, otherPID], selected: pid)
    check(wait { queuedArtwork.snapshot().blocked }, "second visibility batch starts for required-refresh test")
    queuedTracker.refreshIconsForAppearanceChange()
    queuedTracker.setVisibleIconTargets([], selected: nil)
    queuedArtwork.release.signal()
    check(wait { queuedTracker.icons[pid] === newImage && queuedTracker.icons[otherPID] === newImage },
          "required appearance work survives cancellation of a queued visibility request")

    let stored = MemoryDefaults()
    let persistenceTracker = ApplicationTracker(defaults: stored, notificationCenter: NotificationCenter(),
        runningApplications: { [target] }, launchIconRetryDelays: [], iconResolver: { _, _, _ in oldImage })
    persistenceTracker.recordConfirmedActivation(pid)
    persistenceTracker.save()
    let savedWrites = stored.writes
    persistenceTracker.recordConfirmedActivation(pid)
    _ = wait(0.6) { false }
    persistenceTracker.save()
    check(stored.writes == savedWrites, "unchanged remembered app order does not write preferences again")

    let scans = ScanRecorder()
    let tracked = WindowTracker(tracksTitles: false, scan: { scans.scan($0) })
    let windowApps = [WindowApplication(pid: pid, hidden: false), WindowApplication(pid: otherPID, hidden: false)]
    tracked.setTracksMinimizeButtons(true)
    tracked.setEnabled(true)
    tracked.refresh(applications: windowApps, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    check(wait { tracked.records.count == 2 }, "initial full discovery populates the real WindowTracker merge path")
    let countBeforeGeometry = scans.all().count
    let fakeWindow = AXUIElementCreateApplication(pid)
    for _ in 0..<20 { tracked.windowChanged(pid: pid, element: fakeWindow, notification: kAXMovedNotification) }
    check(wait { scans.all().count > countBeforeGeometry }, "coalesced geometry change schedules metadata refresh")
    let geometryRequest = scans.all().last!
    check(geometryRequest.dirtyPIDs?.isEmpty == true && geometryRequest.geometry.count == 1,
          "moving a known window never enumerates unrelated app windows")
    check(tracked.records.count == 2 && !geometryRequest.tracksTitles,
          "geometry-only refresh preserves cached window destinations without unused titles")
    let countBeforeChange = scans.all().count
    tracked.windowChanged(pid: otherPID, element: AXUIElementCreateApplication(otherPID), notification: kAXWindowCreatedNotification)
    check(wait { scans.all().count > countBeforeChange }, "window creation schedules a targeted discovery")
    check(scans.all().last!.dirtyPIDs == [otherPID] && tracked.records.count == 2,
          "one-app discovery preserves records from all other applications")
    let unchangedScans = scans.all().count
    tracked.refresh(applications: windowApps, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    _ = wait(0.1) { false }
    check(scans.all().count == unchangedScans, "unchanged app snapshots do not trigger another AX scan")
    tracked.setEnabled(false)

    #if YELLOW_BUTTON_CHECKS
    var hitReads = 0, hideRequests = 0
    let region = CGRect(x: 10, y: 10, width: 14, height: 14)
    let button = YellowButtonInterceptor(onHide: { _ in hideRequests += 1 }, onStatus: { _ in })
    button.hitTestForChecks = { point in
        hitReads += 1
        return region.contains(point) ? (fakeWindow, pid) : nil
    }
    button.setCandidateRegions([WindowButtonRegion(pid: pid, bounds: region)])
    button.setEnabledForChecks(true)
    func mouse(_ type: CGEventType, _ point: CGPoint, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        event.flags = flags
        return event
    }
    check(!button.receiveForChecks(type: .leftMouseDown, event: mouse(.leftMouseDown, .init(x: 200, y: 200))) && hitReads == 0,
          "ordinary content click bypasses all window/AX hit testing")
    button.setCandidateRegions([
        WindowButtonRegion(pid: pid, bounds: region, windowBounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
        WindowButtonRegion(pid: otherPID, bounds: CGRect(x: 0, y: 0, width: 500, height: 500),
                           windowBounds: CGRect(x: 0, y: 0, width: 500, height: 500))])
    check(!button.receiveForChecks(type: .leftMouseDown, event: mouse(.leftMouseDown, .init(x: 200, y: 200))) && hitReads == 0,
          "unknown background window cannot override a known foreground content click")
    check(!button.receiveForChecks(type: .leftMouseDown, event: mouse(.leftMouseDown, .init(x: 15, y: 15), flags: .maskAlternate)) && hitReads == 0,
          "modified yellow click stays native without any hit test")
    check(button.receiveForChecks(type: .leftMouseDown, event: mouse(.leftMouseDown, .init(x: 15, y: 15))),
          "candidate press is validated before taking ownership")
    check(button.receiveForChecks(type: .leftMouseUp, event: mouse(.leftMouseUp, .init(x: 15, y: 15))),
          "validated release on the same yellow control is consumed")
    check(wait { hideRequests == 1 }, "one complete candidate click queues exactly one hide callback")
    _ = button.receiveForChecks(type: .leftMouseDown, event: mouse(.leftMouseDown, .init(x: 15, y: 15)))
    button.setEnabledForChecks(false)
    check(button.receiveForChecks(type: .leftMouseUp, event: mouse(.leftMouseUp, .init(x: 15, y: 15))),
          "disabling during an owned click still consumes its matching release")
    _ = wait(0.03) { false }
    check(hideRequests == 1, "disabled gesture cannot queue a late hide")
    #endif

    #if FOCUS_DISPATCH_CHECKS
    if let visibleApp = apps.first(where: { !$0.isHidden }) {
        let dispatches = NSLock()
        var sentModes: [Bool] = []
        var publicActivations = 0
        var finished = false
        let coordinator = FocusCoordinator()
        coordinator.sendForChecks = { native in
            dispatches.lock(); sentModes.append(native); dispatches.unlock()
            return false
        }
        coordinator.activateForChecks = { publicActivations += 1; return true }
        coordinator.commit(.application(visibleApp.processIdentifier), app: visibleApp, record: nil, revealHidden: false) { _ in finished = true }
        check(wait { finished }, "rejected private focus settles after one public fallback")
        dispatches.lock(); let modes = sentModes; dispatches.unlock()
        check(modes == [true, false] && publicActivations == 1,
              "a present but failing private bridge falls back once without a retry loop")
        let nativeStarted = DispatchSemaphore(value: 0), nativeRelease = DispatchSemaphore(value: 0)
        coordinator.sendForChecks = { _ in
            nativeStarted.signal(); _ = nativeRelease.wait(timeout: .now() + 2); return false
        }
        coordinator.commit(.application(visibleApp.processIdentifier), app: visibleApp, record: nil, revealHidden: false) { _ in }
        check(nativeStarted.wait(timeout: .now() + 1) == .success, "cancellation test blocks only an injected native action")
        coordinator.cancel()
        nativeRelease.signal()
        _ = wait(0.1) { false }
        check(publicActivations == 1, "cancelled focus intent cannot activate through the public fallback")
    } else { check(false, "focus fallback checks require an existing visible app; none is revealed by the test") }
    #endif

    let exitCenter = NotificationCenter()
    let exitStarted = DispatchSemaphore(value: 0), exitRelease = DispatchSemaphore(value: 0)
    let exitingTracker = ApplicationTracker(defaults: defaults, notificationCenter: exitCenter,
        runningApplications: { [target] }, launchIconRetryDelays: [], iconResolver: { _, _, _ in
            exitStarted.signal(); _ = exitRelease.wait(timeout: .now() + 3); return newImage
        })
    check(exitStarted.wait(timeout: .now() + 2) == .success, "termination test starts one in-flight icon read")
    exitCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: target])
    exitRelease.signal()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    check(exitingTracker.icons[pid] == nil && exitingTracker.applications[pid] == nil,
          "late icon completion cannot resurrect a terminated app")
    let start = ProcessInfo.processInfo.systemUptime
    for _ in 0..<1000 { tracker.pruneTerminatedApplications() }
    print("Mean liveness-prune milliseconds: \((ProcessInfo.processInfo.systemUptime - start) * 1000 / 1000)")
    print("\(checks) checks, \(failures) failed assertions")
    return failures == 0 ? 0 : 1
}
exit(MainActor.assumeIsolated { run() })

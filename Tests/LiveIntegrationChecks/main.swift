import AppKit
import ClearCommandTabCore

// Opt-in OS integration. Only the two bundles under .build/Fixtures may receive
// focus/hide/minimize/close actions. No keyboard injection or permission prompts.
@MainActor func run() -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    guard AXIsProcessTrusted(), WindowTracker.identityAvailable else {
        print("SKIP: live checks need existing Accessibility trust and window identity support")
        return 77
    }
    let root = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : FileManager.default.currentDirectoryPath)
    let origin = NSWorkspace.shared.frontmostApplication
    var fixtures: [NSRunningApplication] = []
    var failures: [String] = []
    var scenarios: [String] = []
    var latencies: [String: [Double]] = [:]
    defer {
        let report: [String: Any] = ["status": failures.isEmpty ? "passed" : "failed",
            "scenarios": scenarios, "failures": failures, "latencyMs": latencies,
            "boundary": "commit -> coordinator callback; window routes require exact OS focus, app-only routes check foreground; not physical shortcut latency"]
        if CommandLine.arguments.count >= 2 {
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
    }
    let tracker = WindowTracker()
    let focus = FocusCoordinator()
    defer {
        focus.cancel()
        tracker.setEnabled(false)
        for fixture in fixtures { _ = fixture.terminate() }
        _ = origin?.activate(options: [])
    }
    func wait(_ description: String, timeout: Double = 3, until predicate: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let success = predicate()
        if !success { failures.append(description) }
        return success
    }
    func check(_ result: Bool, _ description: String) {
        if result { scenarios.append(description) } else { failures.append(description) }
    }
    func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
    func refresh() {
        var completed = false
        tracker.refresh(applications: fixtures.map { WindowApplication(pid: $0.processIdentifier, hidden: $0.isHidden) },
            frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) { completed = true }
        _ = wait("Window discovery completed", until: { completed })
    }
    func discover(_ description: String, until predicate: () -> Bool) -> Bool {
        wait(description, until: {
            refresh()
            return predicate()
        })
    }
    func commit(_ target: SwitcherTargetID, record: TrackedWindow?, reveal: Bool = false, label: String) {
        guard let fixture = fixtures.first(where: { $0.processIdentifier == target.pid }) else {
            failures.append("Refused a non-fixture target"); return
        }
        var result: FocusResult?
        var completedAt: Double?
        let start = ProcessInfo.processInfo.systemUptime
        focus.commit(target, app: fixture, record: record, revealHidden: reveal) {
            completedAt = ProcessInfo.processInfo.systemUptime
            result = $0
        }
        guard wait("Focus completion: \(label)", timeout: 1.2, until: { result != nil }) else { return }
        latencies[label, default: []].append((completedAt! - start) * 1000)
        if target == .application(target.pid), record == nil {
            check(result != .failed && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                  "App-only destination becomes foreground: \(label)")
        } else if result != .confirmed {
            failures.append("Unconfirmed real focus: \(label) (\(String(describing: result)))")
        }
    }
    for suffix in ["A", "B"] {
        let path = root.appendingPathComponent(".build/Fixtures/ClearCommandTab Test \(suffix).app")
        guard Bundle(url: path)?.bundleIdentifier == "\(ApplicationIdentity.bundleIdentifier).Test\(suffix)" else {
            failures.append("Refused an unexpected fixture bundle"); return 1
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--windows=2"]
        var launched: NSRunningApplication?
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: path, configuration: configuration) { application, error in
            launched = application; launchError = error
        }
        guard wait("Launch fixture \(suffix)", until: { launched != nil || launchError != nil }),
              let launched, launched.bundleURL?.standardizedFileURL == path.standardizedFileURL else {
            failures.append("Fixture launch failed or returned an unexpected bundle: \(suffix)")
            return 1
        }
        fixtures.append(launched)
    }
    tracker.setEnabled(true)
    guard discover("Discover four actual fixture windows", until: { tracker.records.count == 4 }) else {
        print(failures); return 1
    }
    let a = fixtures[0], b = fixtures[1]
    let aWindows = tracker.records.values.filter { $0.id.pid == a.processIdentifier }.sorted { $0.title < $1.title }
    let bWindows = tracker.records.values.filter { $0.id.pid == b.processIdentifier }.sorted { $0.title < $1.title }
    guard aWindows.count == 2, bWindows.count == 2 else { failures.append("Wrong fixture window counts"); return 1 }
    let first = aWindows[0], second = aWindows[1], other = bWindows[0]
    check(tracker.records.keys.allSatisfy { [a.processIdentifier, b.processIdentifier].contains($0.pid) },
          "Discovery is restricted to fixture apps")
    var dimensions: [SwitcherTargetID: CGSize] = [:]
    for record in [first, second, other] {
        if let size: AXValue = value(record.element, kAXSizeAttribute) {
            var actual = CGSize.zero
            if AXValueGetValue(size, .cgSize, &actual) { dimensions[record.id] = actual }
        }
    }
    for index in 0..<12 {
        let target = index % 2 == 0 ? first : other
        commit(target.id, record: target, label: "window-focus")
    }
    commit(second.id, record: second, label: "same-app-window-focus")
    check(NSWorkspace.shared.frontmostApplication?.processIdentifier == a.processIdentifier,
          "Same-app window focus retains the owning app")
    for _ in 0..<4 {
        _ = a.hide()
        guard wait("Fixture became hidden", until: { a.isHidden }) else { break }
        refresh()
        check(!tracker.records.keys.contains { $0.pid == a.processIdentifier }, "Hidden windows leave discovery")
        commit(.application(a.processIdentifier), record: second, reveal: true, label: "hidden-app-reveal")
        _ = wait("Reveal made fixture visible", until: { !a.isHidden })
        refresh()
    }
    check(AXUIElementSetAttributeValue(first.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success,
          "Fixture minimize action accepted")
    _ = discover("Minimized window is excluded while sibling remains available", until: {
        tracker.records[first.id] == nil && tracker.records[second.id] != nil
    })
    check(AXUIElementSetAttributeValue(first.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success,
          "Fixture restore action accepted")
    _ = discover("Restored window re-enters discovery", until: { tracker.records[first.id] != nil })

    var session = SelectionSession(ids: [first.id, second.id, other.id], currentID: first.id)
    if let close: AXUIElement = value(second.element, kAXCloseButtonAttribute) {
        _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
        _ = discover("Closed window leaves discovery", until: { tracker.records[second.id] == nil })
        session.reconcile(visibleIDs: [first.id, second.id, other.id].filter { tracker.records[$0] != nil })
        check(session.selectedID == other.id && !session.ids.contains(second.id),
              "Closing the selected real window preserves the next destination")
    } else { failures.append("Fixture has no AX close button") }
    _ = AXUIElementSetAttributeValue(first.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    _ = wait("Only remaining fixture window finishes minimizing", until: {
        value(first.element, kAXMinimizedAttribute) as Bool? == true
    })
    _ = discover("Minimized-only fixture has no visible destination", until: {
        !tracker.records.keys.contains { $0.pid == a.processIdentifier }
    })
    commit(.application(a.processIdentifier), record: nil, label: "minimized-only-app")
    check(value(first.element, kAXMinimizedAttribute) as Bool? == true,
          "App activation does not restore minimized-only windows")
    _ = AXUIElementSetAttributeValue(first.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    _ = discover("Last fixture window finishes restoring before close", until: {
        tracker.records[first.id] != nil && value(first.element, kAXMinimizedAttribute) as Bool? == false
    })
    if let close: AXUIElement = value(first.element, kAXCloseButtonAttribute) {
        check(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success,
              "Last fixture window close action accepted")
    } else { failures.append("Last fixture window has no close button") }
    let aRoot = AXUIElementCreateApplication(a.processIdentifier)
    _ = wait("Fixture finishes closing its last window", until: {
        (value(aRoot, kAXWindowsAttribute) as [AXUIElement]? ?? []).isEmpty
    })
    commit(.application(a.processIdentifier), record: nil, label: "windowless-app")
    check((value(aRoot, kAXWindowsAttribute) as [AXUIElement]? ?? []).isEmpty && !a.isTerminated,
          "Windowless activation does not reopen documents or terminate the app")
    for record in [other] {
        if let expected = dimensions[record.id], let size: AXValue = value(record.element, kAXSizeAttribute) {
            var actual = CGSize.zero
            AXValueGetValue(size, .cgSize, &actual)
            check(actual == expected, "Native focus does not resize the target window")
        }
    }
    for scenario in scenarios { print("PASS \(scenario)") }
    for failure in failures { print("FAIL \(failure)") }
    print("Live integration: \(scenarios.count) scenario assertions; \(failures.count) failures")
    return failures.isEmpty ? 0 : 1
}
let result = MainActor.assumeIsolated { run() }
if result == 77, CommandLine.arguments.count >= 2 {
    let status: [String: Any] = ["status": result == 77 ? "skipped" : "failed",
        "reason": result == 77 ? "Existing Accessibility trust or window identity support unavailable" : "Live scenario aborted"]
    try! JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
exit(result)

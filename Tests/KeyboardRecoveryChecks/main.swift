import AppKit

@MainActor final class Delegate: KeyboardTapDelegate {
    var interrupted = 0
    var recovered = 0
    var unavailable = 0
    func handleKey(type: CGEventType, event: CGEvent) -> Bool { false }
    func keyboardUnavailable(_ reason: String) { unavailable += 1 }
    func cancelSelection() {}
    func keyboardInputInterrupted() { interrupted += 1 }
    func keyboardRecovered() { recovered += 1 }
}

@MainActor func run() -> [String: Any] {
    NSApplication.shared.setActivationPolicy(.prohibited)
    guard AXIsProcessTrusted() else {
        return ["status": "skipped", "reason": "Existing Accessibility trust unavailable; no permission requested"]
    }
    let tap = KeyboardTap()
    let delegate = Delegate()
    tap.delegate = delegate
    defer { tap.stop() }
    var passed: [String] = [], failed: [String] = []
    func check(_ value: Bool, _ label: String) {
        if value { passed.append(label) } else { failed.append(label) }
    }
    func wait(_ seconds: Double, until predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return predicate()
    }
    check(tap.start(), "native tap starts with existing permission")
    guard tap.isRunning else { return ["status": "failed", "passed": passed, "failed": failed] }
    tap.disableWithoutCallbackForCheck()
    let disabledAt = ProcessInfo.processInfo.systemUptime
    check(!tap.isRunning, "native tap is disabled without invoking timeout handler")
    check(wait(2.5, until: { tap.isRunning && delegate.recovered == 1 }),
          "health timer recovers missed disabled callback")
    check(ProcessInfo.processInfo.systemUptime - disabledAt >= 0.5,
          "disabled callback is suppressed; recovery waits for health timer")
    check(delegate.interrupted == 1 && delegate.unavailable == 0,
          "recovery cancels old selection state without reporting lost permission")
    tap.disableWithoutCallbackForCheck()
    tap.deliverTimeoutForCheck()
    check(tap.isRunning && delegate.recovered == 2, "native timeout callback recovers immediately")
    tap.stop()
    let recoveries = delegate.recovered
    _ = wait(1.5, until: { false })
    check(!tap.isRunning && delegate.recovered == recoveries, "stopped or paused tap stays stopped")
    check(!NSApplication.shared.windows.contains(where: \.isVisible), "check host creates no visible windows")
    return ["status": failed.isEmpty ? "passed" : "failed", "passed": passed, "failed": failed,
            "inputPosted": false, "permissionPrompted": false]
}
let report = MainActor.assumeIsolated { run() }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
exit(report["status"] as? String == "passed" ? 0 : report["status"] as? String == "skipped" ? 77 : 1)

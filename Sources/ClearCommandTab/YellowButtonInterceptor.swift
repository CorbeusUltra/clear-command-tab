import AppKit
import ApplicationServices
import ClearCommandTabCore

private let yellowButtonCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<YellowButtonInterceptor>.fromOpaque(context).takeUnretainedValue()
    return interceptor.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

/// Mouse-only tap with its own run loop. AX messaging never runs on the UI thread
/// or in KeyboardTap. The disabled tap does no hit testing and sleeps when idle.
final class YellowButtonInterceptor: @unchecked Sendable {
    static let preferenceKey = "yellowButtonHidesApp"
    private let lock = NSLock()
    private var gate = YellowButtonActionGate()
    private var starting = false
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let onHide: @MainActor @Sendable (Int32) -> Void
    private let onStatus: @MainActor @Sendable (String?) -> Void

    // Confined to the mouse run loop.
    private var gesture = YellowButtonGesture()
    private var target: AXUIElement?
    private var targetPID: Int32 = 0
    private var pressGeneration: UInt64 = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(onHide: @escaping @MainActor @Sendable (Int32) -> Void,
         onStatus: @escaping @MainActor @Sendable (String?) -> Void) {
        self.onHide = onHide
        self.onStatus = onStatus
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        gate.setEnabled(enabled)
        let launch = enabled && port == nil && !starting
        let existingTap = port
        let existingLoop = runLoop
        if launch { starting = true }
        lock.unlock()
        if launch {
            let thread = Thread { [self] in run() }
            thread.name = "ClearCommandTab yellow button"
            thread.qualityOfService = .userInteractive
            thread.start()
        } else if enabled, let existingTap, let existingLoop {
            CFRunLoopPerformBlock(existingLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
                guard snapshot().enabled, AXIsProcessTrusted() else { return }
                if !CGEvent.tapIsEnabled(tap: existingTap) {
                    _ = gesture.release(sameButton: false)
                    target = nil
                    CGEvent.tapEnable(tap: existingTap, enable: true)
                }
                report(CGEvent.tapIsEnabled(tap: existingTap) ? nil : "Yellow button interception is unavailable.")
            }
            CFRunLoopWakeUp(existingLoop)
        }
    }

    private func snapshot() -> YellowButtonActionGate {
        lock.lock()
        defer { lock.unlock() }
        return gate
    }

    private func run() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard AXIsProcessTrusted(),
              let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                  options: .defaultTap, eventsOfInterest: mask, callback: yellowButtonCallback,
                  userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lock.lock()
            starting = false
            lock.unlock()
            report("Yellow button interception is unavailable. Click Check permission to retry.")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            lock.lock()
            starting = false
            lock.unlock()
            report("Yellow button interception could not start. Click Check permission to retry.")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        port = tap
        runLoop = CFRunLoopGetCurrent()
        starting = false
        lock.unlock()
        report(CGEvent.tapIsEnabled(tap: tap) ? nil : "Yellow button interception is unavailable.")
        CFRunLoopRun()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFMachPortInvalidate(tap)
        lock.lock()
        port = nil
        runLoop = nil
        gate.invalidate()
        lock.unlock()
    }

    private func report(_ message: String?) {
        DispatchQueue.main.async { [onStatus] in onStatus(message) }
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // After a tap outage macOS may have delivered the press itself.
            // Drop ownership rather than swallowing an unrelated future release.
            _ = gesture.release(sameButton: false)
            target = nil
            lock.lock()
            gate.invalidate()
            let tap = port
            lock.unlock()
            // A timeout may have delivered an event natively: never run a pending hide.
            if AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                report(CGEvent.tapIsEnabled(tap: tap) ? nil : "Yellow button interception stopped.")
            } else { report("Yellow button interception requires Accessibility permission.") }
            return false
        }

        let state = snapshot()
        let modified = YellowButtonGesture.hasModifier(event.flags)
        if gesture.ownsPress && (!state.accepts(pressGeneration) || modified) { gesture.cancel() }
        if type == .leftMouseDragged { return gesture.ownsPress }
        if type == .leftMouseUp {
            guard gesture.ownsPress else { return false }
            let match: Bool
            if state.accepts(pressGeneration), !modified, let target,
               let hit = button(at: event.location) {
                match = hit.pid == targetPID && CFEqual(hit.element, target)
            } else { match = false }
            let result = gesture.release(sameButton: match)
            target = nil
            if result.hide {
                let pid = targetPID
                let token = pressGeneration
                DispatchQueue.main.async { [self] in
                    guard snapshot().accepts(token), AXIsProcessTrusted() else { return }
                    onHide(pid)
                }
            }
            return result.consume
        }
        guard type == .leftMouseDown else { return false }
        if gesture.ownsPress { return true }
        guard state.enabled, !modified, AXIsProcessTrusted(),
              let hit = button(at: event.location), snapshot().accepts(state.generation) else { return false }
        target = hit.element
        targetPID = hit.pid
        pressGeneration = state.generation
        return gesture.press(eligible: true)
    }

    private func button(at point: CGPoint) -> (element: AXUIElement, pid: Int32)? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.040
        // Per-application hit testing avoids setting the system-wide AX timeout,
        // which would also change unrelated discovery/focus requests in this process.
        guard let surfaces = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                         kCGNullWindowID) as? [[String: Any]],
              let surface = surfaces.first(where: { surface in
                  guard (surface[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                        let bounds = surface[kCGWindowBounds as String] as? NSDictionary,
                        let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                  return rect.contains(point)
              }),
              let pid = surface[kCGWindowOwnerPID as String] as? Int32,
              pid > 0, pid != ownPID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard setTimeout(app, deadline: deadline) else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success,
              let element,
              let role: String = value(element, kAXSubroleAttribute, deadline: deadline),
              role == (kAXMinimizeButtonSubrole as String),
              let enabled: Bool = value(element, kAXEnabledAttribute, deadline: deadline), enabled,
              ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
        return (element, pid)
    }

    private func setTimeout(_ element: AXUIElement, deadline: TimeInterval) -> Bool {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return false }
        return AXUIElementSetMessagingTimeout(element, Float(min(0.010, remaining))) == .success
    }

    private func value<T>(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) -> T? {
        guard setTimeout(element, deadline: deadline) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}

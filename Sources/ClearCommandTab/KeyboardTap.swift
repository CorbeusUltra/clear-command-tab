import AppKit
import Carbon
import os
import ClearCommandTabCore

@MainActor
protocol KeyboardTapDelegate: AnyObject {
    func handleKey(type: CGEventType, event: CGEvent) -> Bool
    func keyboardUnavailable(_ reason: String)
    func cancelSelection()
    func keyboardInputInterrupted()
    func keyboardRecovered()
}

private let keyboardCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated {
        let tap = Unmanaged<KeyboardTap>.fromOpaque(context).takeUnretainedValue()
        return tap.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}

@MainActor
final class KeyboardTap {
    weak var delegate: KeyboardTapDelegate?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var recoveryTimer: Timer?
    #if KEYBOARD_RECOVERY_CHECKS
    private var omitDisabledCallbackForCheck = false
    #endif
    private let log = Logger(subsystem: ApplicationIdentity.bundleIdentifier, category: "KeyboardTap")
    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if isRunning { return true }
        stop()
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
                                    .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: keyboardCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        port = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isRunning else { return }
                self.recoverDisabledTap()
            }
        }
        timer.tolerance = 0.2
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return isRunning
    }

    func stop() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            #if KEYBOARD_RECOVERY_CHECKS
            if type == .tapDisabledByUserInput, omitDisabledCallbackForCheck {
                omitDisabledCallbackForCheck = false
                return false
            }
            #endif
            log.notice("event tap disabled reason=\(type == .tapDisabledByTimeout ? "timeout" : "user-input", privacy: .public)")
            recoverDisabledTap(recreate: false)
            return false
        }
        guard AXIsProcessTrusted() else {
            // Cancel before passing events back to macOS if permission was revoked.
            stop()
            delegate?.keyboardUnavailable("Accessibility permission is required. Command-Tab is handled by macOS.")
            return false
        }
        if IsSecureEventInputEnabled() {
            delegate?.keyboardInputInterrupted()
            return false
        }
        return delegate?.handleKey(type: type, event: event) ?? false
    }

    private func recoverDisabledTap(recreate: Bool = true) {
        delegate?.keyboardInputInterrupted()
        guard AXIsProcessTrusted() else {
            stop()
            delegate?.keyboardUnavailable("Accessibility permission is required. Command-Tab is handled by macOS.")
            return
        }
        if let port, CFMachPortIsValid(port) { CGEvent.tapEnable(tap: port, enable: true) }
        if !isRunning && recreate { _ = start() }
        if isRunning {
            log.notice("event tap recovered")
            delegate?.keyboardRecovered()
        } else {
            log.error("event tap recovery failed")
            delegate?.keyboardUnavailable("Keyboard interception stopped. Click Check permission to retry.")
        }
    }

    #if KEYBOARD_RECOVERY_CHECKS
    // Compiled only by the hidden native check host; no input is posted.
    func disableWithoutCallbackForCheck() {
        omitDisabledCallbackForCheck = true
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
    }
    func deliverTimeoutForCheck() {
        if let event = CGEvent(source: nil) { _ = receive(type: .tapDisabledByTimeout, event: event) }
    }
    #endif
}

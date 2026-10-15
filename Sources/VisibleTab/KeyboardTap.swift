import AppKit
import Carbon

@MainActor
protocol KeyboardTapDelegate: AnyObject {
    func handleKey(type: CGEventType, event: CGEvent) -> Bool
    func keyboardUnavailable(_ reason: String)
    func cancelSelection()
    func keyboardInputInterrupted()
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
        return isRunning
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            delegate?.keyboardInputInterrupted()
            if AXIsProcessTrusted(), let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            if !isRunning { delegate?.keyboardUnavailable("Keyboard interception stopped. Recheck Accessibility permission.") }
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
}

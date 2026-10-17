import CoreGraphics

/// Tracks ownership of a suppressed mouse press independently from its action.
/// Cancellation must still consume the matching drag/release, never a later click.
public struct YellowButtonGesture {
    public private(set) var ownsPress = false
    private var cancelled = false

    public init() {}

    public static func hasModifier(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl]).isEmpty
    }

    public mutating func press(eligible: Bool) -> Bool {
        guard !ownsPress else { return true }
        ownsPress = eligible
        cancelled = false
        return ownsPress
    }

    public mutating func cancel() { cancelled = true }

    public mutating func release(sameButton: Bool) -> (consume: Bool, hide: Bool) {
        let result = (consume: ownsPress, hide: ownsPress && !cancelled && sameButton)
        ownsPress = false
        cancelled = false
        return result
    }
}

/// Invalidates work queued before pause, disable, permission loss, or a tap reset.
public struct YellowButtonActionGate {
    public private(set) var enabled = false
    public private(set) var generation: UInt64 = 0

    public init() {}

    public mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        invalidate()
    }

    public mutating func invalidate() { generation &+= 1 }

    public func accepts(_ token: UInt64) -> Bool { enabled && generation == token }
}

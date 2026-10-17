import CoreGraphics
import ClearCommandTabCore

struct YellowButtonTests {
    func testPlainClickAndUnrelatedRelease() {
        var gesture = YellowButtonGesture()
        expectFalse(gesture.release(sameButton: true).consume)
        expectTrue(gesture.press(eligible: true))
        expectTrue(gesture.ownsPress)
        let release = gesture.release(sameButton: true)
        expectTrue(release.consume)
        expectTrue(release.hide)
        expectFalse(gesture.ownsPress)
        expectFalse(gesture.release(sameButton: true).hide)
    }

    func testModifiedUnsupportedAndDisabledClicksPassThrough() {
        var gesture = YellowButtonGesture()
        for flags: CGEventFlags in [.maskAlternate, .maskCommand, .maskShift, .maskControl,
                                    [.maskAlternate, .maskCommand]] {
            expectTrue(YellowButtonGesture.hasModifier(flags))
            expectFalse(gesture.press(eligible: !YellowButtonGesture.hasModifier(flags)))
        }
        expectFalse(YellowButtonGesture.hasModifier([]))
        expectFalse(YellowButtonGesture.hasModifier(.maskAlphaShift))
        // Unsupported, disabled and timed-out hits have no eligible target.
        expectFalse(gesture.press(eligible: false))
        expectFalse(gesture.ownsPress)
        let release = gesture.release(sameButton: true)
        expectFalse(release.consume)
        expectFalse(release.hide)
    }

    func testOutsideReleaseAndCancellationKeepOwnership() {
        var gesture = YellowButtonGesture()
        _ = gesture.press(eligible: true)
        let outside = gesture.release(sameButton: false)
        expectTrue(outside.consume)
        expectFalse(outside.hide)
        _ = gesture.press(eligible: true)
        gesture.cancel()
        expectTrue(gesture.ownsPress)
        // Even a repeated down must not revive a cancelled press.
        expectTrue(gesture.press(eligible: true))
        let cancelled = gesture.release(sameButton: true)
        expectTrue(cancelled.consume)
        expectFalse(cancelled.hide)
        expectFalse(gesture.press(eligible: false))
        expectFalse(gesture.release(sameButton: true).consume)
        expectTrue(gesture.press(eligible: true))
        expectTrue(gesture.release(sameButton: true).hide)
    }

    func testQueuedActionsCannotSurviveDisablePauseOrTapLoss() {
        var gate = YellowButtonActionGate()
        expectFalse(gate.accepts(gate.generation))
        gate.setEnabled(true)
        let beforePause = gate.generation
        expectTrue(gate.accepts(beforePause))
        gate.setEnabled(true) // A harmless permission recheck preserves valid work.
        expectTrue(gate.accepts(beforePause))
        gate.setEnabled(false)
        expectFalse(gate.accepts(beforePause))
        gate.setEnabled(true)
        expectFalse(gate.accepts(beforePause))
        let beforeTapLoss = gate.generation
        gate.invalidate()
        expectFalse(gate.accepts(beforeTapLoss))
        expectTrue(gate.accepts(gate.generation))
    }
}

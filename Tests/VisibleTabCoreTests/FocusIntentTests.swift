import Foundation
import VisibleTabCore

final class FocusIntentTests {
    private let a = SwitcherTargetID.window(pid: 1, number: 10)
    private let b = SwitcherTargetID.window(pid: 2, number: 20)

    func testRevealWaitsForSelectedAppAndOnlyRunsOnce() {
        var gate = ApplicationRevealGate()
        expectFalse(gate.acknowledge(1))
        gate.wait(for: 1)
        expectFalse(gate.acknowledge(2))
        expectTrue(gate.acknowledge(1))
        expectFalse(gate.acknowledge(1))
    }

    func testCancelledOrSupersededRevealCannotResume() {
        var gate = ApplicationRevealGate()
        var policy = FocusIntentPolicy()
        let old = policy.request(.application(1), now: 10)
        gate.wait(for: 1)
        gate.cancel()
        _ = policy.beginSelection(now: 10.01)
        expectFalse(gate.acknowledge(1))
        expectFalse(policy.isCurrent(old))
        let latest = policy.request(.application(2), now: 10.02)
        gate.wait(for: 2)
        expectFalse(gate.acknowledge(1))
        expectTrue(gate.acknowledge(2))
        expectTrue(policy.isCurrent(latest))
    }

    func testRevealUsesObservedStateRatherThanRequestReturnValue() {
        var gate = ApplicationRevealGate()
        gate.wait(for: 1)
        let cocoaRequestAccepted = false
        expectFalse(cocoaRequestAccepted)
        expectFalse(gate.observe(pid: 1, hidden: nil))
        expectFalse(gate.observe(pid: 1, hidden: true))
        expectFalse(gate.observe(pid: 2, hidden: false))
        // A negative advisory return must not discard an actual observed reveal.
        expectTrue(gate.observe(pid: 1, hidden: false))
        expectFalse(gate.acknowledge(1))
        gate.wait(for: 1)
        gate.cancel()
        expectFalse(gate.observe(pid: 1, hidden: false))
    }

    func testRevealedWindowNeedsBothRealKeyboardAndWindowFocus() {
        let app = SwitcherTargetID.application(1)
        expectFalse(FocusConfirmation.matches(target: app, expectedWindow: a,
                                               frontmostPID: 2, keyboardPID: 2, window: a))
        expectFalse(FocusConfirmation.matches(target: app, expectedWindow: a,
                                               frontmostPID: 1, keyboardPID: 2, window: a))
        expectFalse(FocusConfirmation.matches(target: app, expectedWindow: a,
                                               frontmostPID: 1, keyboardPID: 1, window: nil))
        expectFalse(FocusConfirmation.matches(target: app, expectedWindow: a,
                                               frontmostPID: 1, keyboardPID: 1,
                                               window: .window(pid: 1, number: 11)))
        expectTrue(FocusConfirmation.matches(target: app, expectedWindow: a,
                                              frontmostPID: 1, keyboardPID: 1, window: a))
        expectTrue(FocusConfirmation.matches(target: app, expectedWindow: nil,
                                              frontmostPID: 1, keyboardPID: 1, window: nil))
        expectFalse(FocusConfirmation.matches(target: a, expectedWindow: nil,
                                               frontmostPID: 1, keyboardPID: 1, window: nil))
    }

    func testOpeningNextSelectionInvalidatesPreviousCompletion() {
        var policy = FocusIntentPolicy()
        let old = policy.request(a, now: 10)
        expectEqual(policy.beginSelection(now: 10.01), a)
        expectFalse(policy.isCurrent(old))
        expectFalse(policy.complete(old, observed: true))
        let latest = policy.request(b, now: 10.02)
        expectFalse(policy.complete(old, observed: false))
        expectTrue(policy.complete(latest, observed: true))
        expectEqual(policy.beginSelection(now: 10.03), b)
    }

    func testLateOwnActivationDoesNotCancelNextSelection() {
        var policy = FocusIntentPolicy()
        _ = policy.request(a, now: 10)
        _ = policy.beginSelection(now: 10.01)
        let newest = policy.request(b, now: 10.02)
        expectTrue(policy.consumeActivation(pid: a.pid, now: 10.03))
        expectTrue(policy.isCurrent(newest))
        expectTrue(policy.consumeActivation(pid: b.pid, now: 10.04))
        expectFalse(policy.consumeActivation(pid: 99, now: 10.04))
        expectFalse(policy.consumeActivation(pid: a.pid, now: 10.05))
    }

    func testExternalCancellationAndNotificationExpiry() {
        var policy = FocusIntentPolicy()
        let revision = policy.request(a, now: 10)
        policy.cancel()
        expectFalse(policy.isCurrent(revision))
        expectFalse(policy.consumeActivation(pid: a.pid, now: 10.01))
        expectNil(policy.beginSelection(now: 10.02))
        _ = policy.request(b, now: 11)
        expectFalse(policy.consumeActivation(pid: b.pid, now: 12))
        expectNil(policy.beginSelection(now: 12))
    }

    func testFailureDoesNotCreateLogicalRecency() {
        var policy = FocusIntentPolicy()
        let revision = policy.request(a, now: 10)
        expectTrue(policy.complete(revision, observed: false))
        expectNil(policy.beginSelection(now: 10.01))
        // Even a failed readback can be followed by a late notification from the
        // already-sent request, so it is recognized without claiming real focus.
        expectTrue(policy.consumeActivation(pid: a.pid, now: 10.02))
    }

    func testRapidSwitchAcrossAppGroupsUsesLogicalOrigin() {
        var history = WindowHistory()
        let a2 = SwitcherTargetID.window(pid: 1, number: 11)
        history.update(frontToBack: [a, a2, b])
        var policy = FocusIntentPolicy()
        _ = policy.request(b, now: 10)
        let origin = policy.beginSelection(now: 10.01)
        let apps = FocusIntentPolicy.prioritizing(origin?.pid, in: [1, 2])
        let windows = FocusIntentPolicy.prioritizing(origin, in: history.order)
        let ids = WindowHistory.group(windows, applicationOrder: apps)
        expectEqual(ids, [b, a, a2])
        let selection = SelectionSession(ids: ids, currentID: origin)
        expectEqual(selection.selectedID, a)
        expectEqual(history.order, [a, a2, b]) // Real MRU is still unconfirmed.
        let latest = policy.request(a, now: 10.02)
        expectTrue(policy.complete(latest, observed: true))
        history.activate(a)
        expectEqual(history.order.first, a)
    }

    func testRapidSameAppWindowSwitchBouncesCorrectly() {
        let a2 = SwitcherTargetID.window(pid: 1, number: 11)
        let actualHistory = [a, a2, b]
        var policy = FocusIntentPolicy()
        _ = policy.request(a2, now: 10)
        let origin = policy.beginSelection(now: 10.01)
        let ids = WindowHistory.group(FocusIntentPolicy.prioritizing(origin, in: actualHistory), applicationOrder: [1, 2])
        expectEqual(SelectionSession(ids: ids, currentID: origin).selectedID, a)
        expectEqual(actualHistory, [a, a2, b])
    }

    func testOldSnapshotsCannotUndoConfirmedFocus() {
        var epoch = WindowSnapshotEpoch()
        let before = epoch.revision
        epoch.setTransitioning(true)
        expectFalse(epoch.accepts(before))
        expectFalse(epoch.canRecordFocus)
        let during = epoch.revision
        expectTrue(epoch.accepts(during))
        epoch.setTransitioning(false)
        expectFalse(epoch.accepts(during))
        expectTrue(epoch.canRecordFocus)
        expectTrue(epoch.accepts(epoch.revision))
        let after = epoch.revision
        epoch.setTransitioning(true)
        epoch.setTransitioning(false) // A new shortcut cancels the pending action.
        expectFalse(epoch.accepts(after))
    }

    func testConfirmedTargetHasBoundedLifetime() {
        var policy = FocusIntentPolicy()
        let revision = policy.request(.application(2), now: 10)
        expectTrue(policy.complete(revision, observed: true))
        expectEqual(policy.beginSelection(now: 10.1), .application(2))
        _ = policy.request(.application(1), now: 11)
        expectNil(policy.beginSelection(now: 12))
        expectEqual(FocusIntentPolicy.prioritizing(99, in: [1, 2]), [1, 2])
    }

    func testExternalAppChangeDoesNotUsePreviousAppsFocusedWindow() {
        var history = WindowHistory()
        let b2 = SwitcherTargetID.window(pid: 2, number: 21)
        history.update(frontToBack: [a, b, b2])
        history.activate(b2)
        expectEqual(history.current(focused: a, frontmostPID: 2), b2)
        expectEqual(history.current(focused: b, frontmostPID: 2), b)
        expectNil(history.current(focused: a, frontmostPID: 99))
        var epoch = WindowSnapshotEpoch()
        let old = epoch.revision
        epoch.invalidate() // A different app is now foreground, without our commit.
        expectFalse(epoch.accepts(old))
        expectTrue(epoch.canRecordFocus)
    }

    func testKeyWindowRecordIsPaddedAndOutsideContent() {
        let bytes = KeyWindowEventRecord.bytes(window: 0x12345678)
        expectEqual(bytes.count, 256)
        expectEqual(bytes[4], 248)
        expectEqual(bytes[8], 1) // Down only: never post a matching up/click.
        expectEqual(bytes[58], 16)
        expectEqual(Array(bytes[60..<64]), [0x78, 0x56, 0x34, 0x12])
        let x = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: Double.self) }
        let y = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: Double.self) }
        expectEqual(x, 300_000)
        expectEqual(y, 300_000)
        let fields = Set([4, 8, 58] + Array(32..<48) + Array(60..<64))
        expectTrue(bytes.enumerated().allSatisfy { fields.contains($0.offset) || $0.element == 0 })
        expectTrue(bytes[248..<256].allSatisfy { $0 == 0 })
    }
}

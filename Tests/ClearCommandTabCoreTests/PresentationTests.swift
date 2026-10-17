import Foundation
import ClearCommandTabCore

final class PresentationTests {
    func testQuickMRUCommitNeverRevealsPanel() {
        var presentation = SelectionPresentation()
        var history = ApplicationHistory(excludedID: 99)
        history.update([.init(id: 1, persistenceID: "a", name: "A"),
                        .init(id: 2, persistenceID: "b", name: "B")])
        history.activate(1)
        let session = SwitcherSession(ids: history.visible.map(\.id), currentID: 1)
        presentation.begin(mode: .applications, now: 10)
        expectEqual(session.selectedID, 2)
        expectFalse(presentation.permitsDisplay(now: 10.149))
        // Release still commits the chosen MRU app; only presentation is cancelled.
        let committed = session.selectedID
        presentation.cancel()
        history.activate(committed!)
        expectEqual(history.visible.first?.id, 2)
        expectFalse(presentation.permitsDisplay(now: 10.150))
        expectFalse(presentation.permitsDisplay(now: 11))
    }

    func testHeldChordsRevealAt150Milliseconds() {
        for mode in [SwitcherMode.applications, .hiddenApplications, .windows] {
            var presentation = SelectionPresentation()
            presentation.begin(mode: mode, now: 10)
            expectFalse(presentation.permitsDisplay(now: 10))
            expectFalse(presentation.permitsDisplay(now: 10.1499))
            expectTrue(presentation.permitsDisplay(now: 10.150))
            expectTrue(abs(presentation.delayRemaining(now: 10.050) - 0.100) < 0.000001)
        }
    }

    func testFurtherNavigationShowsImmediately() {
        for mode in [SwitcherMode.applications, .hiddenApplications, .windows] {
            var presentation = SelectionPresentation()
            presentation.begin(mode: mode, now: 10)
            presentation.navigate(now: 10.020)
            expectTrue(presentation.permitsDisplay(now: 10.020))
            expectEqual(presentation.delayRemaining(now: 10.020), 0)
            presentation.cancel()
            presentation.navigate(now: 10.030)
            expectFalse(presentation.permitsDisplay(now: 10.030))
        }
    }

    func testQuickWindowCommitNeverRevealsPanel() {
        let first = SwitcherTargetID.window(pid: 1, number: 101)
        let second = SwitcherTargetID.window(pid: 1, number: 102)
        var history = WindowHistory()
        history.update(frontToBack: [first, second])
        let session = SelectionSession(ids: history.groupedOrder, currentID: first)
        var presentation = SelectionPresentation()
        presentation.begin(mode: .windows, now: 10)
        expectEqual(session.selectedID, second)
        // A discovery callback before the deadline cannot reveal the window panel.
        expectFalse(presentation.permitsDisplay(now: 10.050))
        expectFalse(presentation.permitsDisplay(now: 10.149))
        presentation.cancel()
        history.activate(session.selectedID)
        expectEqual(history.order.first, second)
        expectFalse(presentation.permitsDisplay(now: 10.150))
        expectFalse(presentation.permitsDisplay(now: 11))
    }

    func testRestartedGestureDoesNotUseOldDisplayDeadline() {
        var presentation = SelectionPresentation()
        presentation.begin(mode: .applications, now: 10)
        presentation.cancel()
        presentation.begin(mode: .hiddenApplications, now: 10.100)
        expectFalse(presentation.permitsDisplay(now: 10.150))
        expectTrue(presentation.permitsDisplay(now: 10.250))
        presentation.cancel()
        presentation.begin(mode: .windows, now: 11)
        expectFalse(presentation.permitsDisplay(now: 11))
        expectFalse(presentation.permitsDisplay(now: 11.1499))
        expectTrue(presentation.permitsDisplay(now: 11.150))
    }

    func testUnverifiedFocusDoesNotSoundLikeRejectedAction() {
        expectFalse(FocusResult.confirmed.shouldBeep)
        expectFalse(FocusResult.unverified.shouldBeep)
        expectTrue(FocusResult.failed.shouldBeep)
    }
}

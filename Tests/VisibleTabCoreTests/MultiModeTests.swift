import Foundation
import VisibleTabCore

final class MultiModeTests {
    func testGroupingByAppThenWindowRecency() {
        let a1 = SwitcherTargetID.window(pid: 1, number: 10)
        let a2 = SwitcherTargetID.window(pid: 1, number: 11)
        let b1 = SwitcherTargetID.window(pid: 2, number: 20)
        let b2 = SwitcherTargetID.window(pid: 2, number: 21)
        var history = WindowHistory()
        history.update(frontToBack: [a1, b1, a2, b2])
        expectEqual(history.groupedOrder, [a1, a2, b1, b2])
        history.activate(b2)
        expectEqual(history.groupedOrder, [b2, b1, a1, a2])
        expectEqual(history.groupedOrder(applicationOrder: [1, 2]), [a1, a2, b2, b1])
        expectEqual(history.groupedOrder(applicationOrder: [99, 1, 1]), [a1, a2, b2, b1])
        history.update(frontToBack: [a2, b1, b2])
        expectEqual(history.groupedOrder(applicationOrder: [1, 2]), [a2, b2, b1])
    }

    func testNewWindowJoinsItsGroupWithoutMovingSelection() {
        let a1 = SwitcherTargetID.window(pid: 1, number: 10)
        let a2 = SwitcherTargetID.window(pid: 1, number: 11)
        let b1 = SwitcherTargetID.window(pid: 2, number: 20)
        var session = SelectionSession(ids: [a1, b1], currentID: a1)
        session.reconcile(visibleIDs: [a1, a2, b1])
        session.regroupWindows()
        expectEqual(session.ids, [a1, a2, b1])
        expectEqual(session.selectedID, b1)
        session.advance(-1)
        expectEqual(session.selectedID, a2)
        session.reconcile(visibleIDs: [])
        session.regroupWindows()
        expectNil(session.selectedID)
    }

    func testRevealActivatesDespiteStaleHiddenFlag() {
        let cachedHidden = true // Cocoa does not refresh this until the next run-loop turn.
        var calls: [String] = []
        let accepted = ApplicationSwitch.commit(revealHidden: true, isHidden: cachedHidden, isTerminated: false,
                                                unhide: { calls.append("unhide"); return true },
                                                activate: { calls.append("activate"); return true })
        expectTrue(accepted)
        expectEqual(calls, ["unhide", "activate"])
        expectTrue(cachedHidden)
    }

    func testFailedRevealAndTerminatedAppDoNotActivate() {
        var activations = 0
        expectFalse(ApplicationSwitch.commit(revealHidden: true, isHidden: true, isTerminated: false,
                                              unhide: { false }, activate: { activations += 1; return true }))
        expectFalse(ApplicationSwitch.commit(revealHidden: true, isHidden: true, isTerminated: true,
                                              unhide: { true }, activate: { activations += 1; return true }))
        expectFalse(ApplicationSwitch.commit(revealHidden: false, isHidden: true, isTerminated: false,
                                              unhide: { true }, activate: { activations += 1; return true }))
        expectEqual(activations, 0)
        expectTrue(ApplicationSwitch.commit(revealHidden: false, isHidden: false, isTerminated: false,
                                             unhide: { false }, activate: { activations += 1; return true }))
        expectEqual(activations, 1)
    }

    func testShortcutDispatch() {
        expectEqual(SwitcherMode.starting(with: [.command]), .applications)
        expectEqual(SwitcherMode.starting(with: [.command, .shift]), .applications)
        expectEqual(SwitcherMode.starting(with: [.option]), .windows)
        expectEqual(SwitcherMode.starting(with: [.option, .shift]), .windows)
        expectEqual(SwitcherMode.starting(with: [.command, .option]), .hiddenApplications)
        expectEqual(SwitcherMode.starting(with: [.command, .option, .shift]), .hiddenApplications)
        expectNil(SwitcherMode.starting(with: []))
        expectNil(SwitcherMode.starting(with: [.shift]))
        expectNil(SwitcherMode.starting(with: [.control, .command]))
        expectNil(SwitcherMode.starting(with: [.control, .option]))
    }

    func testModifierReleaseAndModeLock() {
        expectTrue(SwitcherMode.hiddenApplications.isHeld(by: [.command]))
        expectTrue(SwitcherMode.hiddenApplications.permits([.command]))
        expectFalse(SwitcherMode.hiddenApplications.isHeld(by: [.option]))
        expectTrue(SwitcherMode.windows.isHeld(by: [.option]))
        expectFalse(SwitcherMode.windows.isHeld(by: [.command]))
        expectFalse(SwitcherMode.windows.permits([.option, .command]))
        expectFalse(SwitcherMode.applications.permits([.command, .option]))
        expectFalse(SwitcherMode.hiddenApplications.permits([.command, .control]))
        for mode in [SwitcherMode.applications, .hiddenApplications, .windows] {
            expectFalse(mode.isHeld(by: []))
        }
    }

    func testHiddenAppsRemainInMRU() {
        var history = ApplicationHistory(excludedID: 99)
        history.update([.init(id: 1, persistenceID: "one", name: "Visible"),
                        .init(id: 2, persistenceID: "two", name: "Hidden", isHidden: true),
                        .init(id: 3, persistenceID: "three", name: "Older", isHidden: true)])
        history.activate(3)
        expectEqual(history.hidden.map(\.id), [3, 2])
        expectEqual(history.visible.map(\.id), [1])
        let session = SwitcherSession(ids: history.hidden.map(\.id), currentID: 1)
        expectEqual(session.selectedID, 3)
        expectEqual(SwitcherSession(ids: history.hidden.map(\.id), currentID: 1, backwards: true).selectedID, 2)
        history.update([.init(id: 1, persistenceID: "one", name: "Visible"),
                        .init(id: 2, persistenceID: "two", name: "Hidden", isHidden: true),
                        .init(id: 3, persistenceID: "three", name: "Revealed")])
        expectEqual(history.hidden.map(\.id), [2])
        expectEqual(history.visible.map(\.id), [3, 1])
    }

    func testIndependentWindowIdentityAndRecency() {
        let first = SwitcherTargetID.window(pid: 1, number: 10)
        let second = SwitcherTargetID.window(pid: 1, number: 11)
        let third = SwitcherTargetID.window(pid: 2, number: 12)
        expectEqual(Set([SwitcherTargetID.application(1), first, second]).count, 3)
        var history = WindowHistory()
        history.update(frontToBack: [first, second, third])
        history.activate(second)
        expectEqual(history.order, [second, first, third])
        for expected in [first, second, first, second] {
            let session = SelectionSession(ids: history.order, currentID: history.order.first)
            expectEqual(session.selectedID, expected)
            history.activate(expected)
        }
        history.update(frontToBack: [third, first, second, second])
        expectEqual(history.order, [second, first, third])
        history.update(frontToBack: [third, first])
        expectEqual(history.order, [first, third])
    }

    func testWindowSessionReconciliation() {
        let first = SwitcherTargetID.window(pid: 1, number: 10)
        let second = SwitcherTargetID.window(pid: 1, number: 11)
        let third = SwitcherTargetID.window(pid: 2, number: 12)
        var session = SelectionSession(ids: [first, second, third], currentID: first)
        expectEqual(session.selectedID, second)
        session.reconcile(visibleIDs: [third, first])
        expectEqual(session.selectedID, third)
        expectEqual(session.ids, [first, third])
        session.reconcile(visibleIDs: [])
        expectNil(session.selectedID)
        expectNil(SelectionSession<SwitcherTargetID>(ids: [], currentID: nil).selectedID)
        expectEqual(SelectionSession(ids: [first], currentID: first).selectedID, first)
    }

    func testWindowTitleLayout() {
        for count in [1, 3, 18, 50] {
            let available = CGSize(width: 1440, height: 900)
            let apps = SwitcherLayout(applicationCount: count, availableSize: available)!
            let windows = SwitcherLayout(applicationCount: count, availableSize: available, showsTitles: true)!
            expectEqual(windows.size.width, apps.size.width)
            expectTrue(windows.titleBandHeight > 0)
            expectEqual(windows.tileFrame(at: 0).height, windows.rowHeight)
            expectTrue(windows.rowBottom + windows.rowHeight <= windows.size.height)
            expectTrue(windows.size.height > apps.size.height)
        }
    }
}

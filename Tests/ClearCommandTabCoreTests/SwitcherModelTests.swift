import Foundation
import ClearCommandTabCore

final class SwitcherModelTests {
    func app(_ id: Int32, _ name: String, hidden: Bool = false, regular: Bool = true) -> ApplicationRecord {
        .init(id: id, persistenceID: "app.\(id)", name: name, isHidden: hidden, isRegular: regular)
    }

    func testStrictHiddenFilterAndExclusions() {
        var history = ApplicationHistory(excludedID: 99)
        history.update([app(1, "Finder"), app(2, "Hidden", hidden: true),
                        app(3, "Minimized"), app(4, "No windows"),
                        app(5, "Other Space"), app(6, "Menu bar", regular: false), app(99, "Self")])
        expectEqual(Set(history.visible.map(\.id)), [1, 3, 4, 5])
    }

    func testInitialOrderAndRememberedOrder() {
        var history = ApplicationHistory(excludedID: 99, rememberedOrder: ["app.3", "app.3", "app.1"])
        history.update([app(1, "Z"), app(2, "A"), app(3, "B")])
        expectEqual(history.order, [3, 1, 2])
        history.activate(2)
        expectEqual(history.visible.map(\.id), [2, 3, 1])
        expectEqual(history.rememberedOrder, ["app.2", "app.3", "app.1"])
    }

    func testHiddenHistorySurvivesUnhideAndTermination() {
        var history = ApplicationHistory(excludedID: 99)
        history.update([app(1, "A"), app(2, "B"), app(3, "C")])
        history.activate(2)
        history.update([app(1, "A"), app(2, "B", hidden: true), app(3, "C")])
        expectEqual(history.visible.map(\.id), [1, 3])
        history.update([app(1, "A"), app(2, "B"), app(3, "C")])
        expectEqual(history.visible.map(\.id), [2, 1, 3])
        history.update([app(1, "A"), app(3, "C")])
        expectEqual(history.order, [1, 3])
    }

    func testRepeatedQuickSwitching() {
        var history = ApplicationHistory(excludedID: 99)
        history.update([app(1, "A"), app(2, "B"), app(3, "C")])
        for expected: Int32 in [2, 1, 2, 1] {
            let session = SwitcherSession(ids: history.visible.map(\.id), currentID: history.order.first)
            expectEqual(session.selectedID, expected)
            history.activate(expected)
        }
    }

    func testReverseAndCircularNavigation() {
        var session = SwitcherSession(ids: [1, 2, 3], currentID: 1, backwards: true)
        expectEqual(session.selectedID, 3)
        session.advance(1)
        expectEqual(session.selectedID, 1)
        session.advance(-1)
        expectEqual(session.selectedID, 3)
        session.select(2)
        expectEqual(session.selectedID, 2)
    }

    func testMissingForegroundDoesNotSkipFirstVisibleApp() {
        expectEqual(SwitcherSession(ids: [1, 2], currentID: 9).selectedID, 1)
        expectEqual(SwitcherSession(ids: [1, 2], currentID: 9, backwards: true).selectedID, 2)
    }

    func testRemovingSelectionKeepsOriginalSuccessor() {
        var session = SwitcherSession(ids: [1, 2, 3, 4], currentID: 1)
        session.reconcile(visibleIDs: [4, 3, 1])
        expectEqual(session.ids, [1, 3, 4])
        expectEqual(session.selectedID, 3)
        session.select(4)
        session.reconcile(visibleIDs: [3, 1])
        expectEqual(session.selectedID, 1)
    }

    func testReconcileDoesNotReorderAndAppendsNewApps() {
        var session = SwitcherSession(ids: [1, 2, 3], currentID: 1)
        session.reconcile(visibleIDs: [3, 2, 1, 4])
        expectEqual(session.ids, [1, 2, 3, 4])
        expectEqual(session.selectedID, 2)
    }

    func testEmptyAndSingleApplication() {
        var empty = SwitcherSession(ids: [], currentID: nil)
        empty.advance(1)
        expectNil(empty.selectedID)
        var single = SwitcherSession(ids: [1], currentID: 1)
        expectEqual(single.selectedID, 1)
        single.advance(-1)
        expectEqual(single.selectedID, 1)
        single.reconcile(visibleIDs: [])
        expectNil(single.selectedID)
    }

    func testConsumedKeyUpSurvivesSessionEndAndRepeat() {
        var ownership = KeyOwnership()
        ownership.consumeDown(48)
        ownership.consumeDown(48)
        expectFalse(ownership.consumeUp(0))
        expectTrue(ownership.consumeUp(48))
        expectFalse(ownership.consumeUp(48))
        ownership.consumeDown(48)
        ownership.reset()
        expectFalse(ownership.consumeUp(48))
    }
}

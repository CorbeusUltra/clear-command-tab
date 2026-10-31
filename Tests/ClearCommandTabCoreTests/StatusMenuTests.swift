import ClearCommandTabCore

final class StatusMenuTests {
    func testMenuActionsWaitForTrackingAndExecuteOnce() {
        for command: StatusMenuCommand in [.settings, .about, .guide, .togglePause, .quit] {
            var menu = StatusMenuSession()
            menu.beginTracking()
            menu.menuWillOpen()
            expectTrue(menu.deferCommand(command))
            menu.menuDidClose()
            expectTrue(menu.isTracking)
            expectTrue(menu.deferCommand(command))
            expectEqual(menu.finishTracking(), command)
            expectFalse(menu.isTracking)
            expectNil(menu.finishTracking())
        }
    }

    func testClosingMenuDoesNotEndItsTrackingCall() {
        var menu = StatusMenuSession()
        menu.beginTracking()
        menu.menuWillOpen()
        expectTrue(menu.deferCommand(.settings))
        menu.menuDidClose()
        expectFalse(menu.isOpen)
        expectTrue(menu.isTracking)
        expectEqual(StatusMenuCommand.matching(menuIsOpen: menu.isTracking, characters: ",", modifiers: .command), .settings)
        // A native Settings action delivered after menuDidClose must also defer.
        expectTrue(menu.deferCommand(.settings))
        expectEqual(menu.finishTracking(), .settings)
        expectFalse(menu.isTracking)
        expectNil(StatusMenuCommand.matching(menuIsOpen: menu.isTracking, characters: ",", modifiers: .command))
        expectNil(menu.finishTracking())
        expectFalse(menu.deferCommand(.settings))
    }

    func testOrdinaryDismissalDoesNotRequestSettings() {
        var menu = StatusMenuSession()
        menu.beginTracking()
        menu.menuWillOpen()
        menu.menuDidClose()
        expectNil(menu.finishTracking())
        menu.beginTracking()
        menu.menuWillOpen()
        expectTrue(menu.deferCommand(.quit))
        menu.menuDidClose()
        expectEqual(menu.finishTracking(), .quit)
        menu.beginTracking()
        menu.menuWillOpen()
        menu.menuDidClose()
        expectNil(menu.finishTracking())
    }

    func testShortcutsOnlyBelongToAnOpenMenu() {
        for character in [",", "q", "Q"] {
            expectNil(StatusMenuCommand.matching(menuIsOpen: false, characters: character, modifiers: .command))
        }
        expectEqual(StatusMenuCommand.matching(menuIsOpen: true, characters: ",", modifiers: .command), .settings)
        expectEqual(StatusMenuCommand.matching(menuIsOpen: true, characters: "q", modifiers: .command), .quit)
        expectEqual(StatusMenuCommand.matching(menuIsOpen: true, characters: "Q", modifiers: .command), .quit)
    }

    func testUnrelatedMenuKeysPassThrough() {
        for flags: ShortcutModifiers in [[], .option, [.command, .option], [.command, .control], [.command, .shift]] {
            expectNil(StatusMenuCommand.matching(menuIsOpen: true, characters: ",", modifiers: flags))
            expectNil(StatusMenuCommand.matching(menuIsOpen: true, characters: "q", modifiers: flags))
        }
        for character in [nil, "", ";", "m", "a", "\u{1b}"] {
            expectNil(StatusMenuCommand.matching(menuIsOpen: true, characters: character, modifiers: .command))
        }
    }
}

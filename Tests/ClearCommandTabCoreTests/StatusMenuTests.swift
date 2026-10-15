import ClearCommandTabCore

final class StatusMenuTests {
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

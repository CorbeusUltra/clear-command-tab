import Foundation

// Command Line Tools do not ship XCTest. These checks need only the Swift runtime.
private var failures: [String] = []

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures.append("\(file):\(line): expected \(expected), received \(actual)") }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { failures.append("\(file):\(line): expected nil") }
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    expectEqual(value, false, file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    expectEqual(value, true, file: file, line: line)
}

let checks = SwitcherModelTests()
let layoutChecks = SwitcherLayoutTests()
let interactionChecks = PointerAndBadgeTests()
let modeChecks = MultiModeTests()
let focusChecks = FocusIntentTests()
let cases: [(String, () -> Void)] = [
    ("reveal observes real state despite a negative advisory return", focusChecks.testRevealUsesObservedStateRatherThanRequestReturnValue),
    ("reveal waits for the selected app and resumes once", focusChecks.testRevealWaitsForSelectedAppAndOnlyRunsOnce),
    ("cancelled or superseded reveal cannot resume", focusChecks.testCancelledOrSupersededRevealCannotResume),
    ("revealed window requires real keyboard and exact window focus", focusChecks.testRevealedWindowNeedsBothRealKeyboardAndWindowFocus),
    ("new selection invalidates old focus completion", focusChecks.testOpeningNextSelectionInvalidatesPreviousCompletion),
    ("late own activation preserves the next selection", focusChecks.testLateOwnActivationDoesNotCancelNextSelection),
    ("external cancellation and bounded activation attribution", focusChecks.testExternalCancellationAndNotificationExpiry),
    ("failed focus does not invent logical recency", focusChecks.testFailureDoesNotCreateLogicalRecency),
    ("rapid switching across app groups uses pending origin", focusChecks.testRapidSwitchAcrossAppGroupsUsesLogicalOrigin),
    ("rapid same-app window switching bounces correctly", focusChecks.testRapidSameAppWindowSwitchBouncesCorrectly),
    ("old snapshots cannot overwrite confirmed focus", focusChecks.testOldSnapshotsCannotUndoConfirmedFocus),
    ("confirmed logical targets expire", focusChecks.testConfirmedTargetHasBoundedLifetime),
    ("external app changes discard the previous app's focused window", focusChecks.testExternalAppChangeDoesNotUsePreviousAppsFocusedWindow),
    ("key-window record padding and off-content down-only format", focusChecks.testKeyWindowRecordIsPaddedAndOutsideContent),
    ("app groups follow app MRU and preserve window MRU", modeChecks.testGroupingByAppThenWindowRecency),
    ("new windows join their group without changing selection", modeChecks.testNewWindowJoinsItsGroupWithoutMovingSelection),
    ("reveal activates despite Cocoa's stale hidden cache", modeChecks.testRevealActivatesDespiteStaleHiddenFlag),
    ("failed reveal/terminated/hidden ordinary targets do not activate", modeChecks.testFailedRevealAndTerminatedAppDoNotActivate),
    ("three shortcut modes and modifier priority", modeChecks.testShortcutDispatch),
    ("modifier release commits the opening mode", modeChecks.testModifierReleaseAndModeLock),
    ("hidden-app mode preserves recency", modeChecks.testHiddenAppsRemainInMRU),
    ("window identities and independent MRU", modeChecks.testIndependentWindowIdentityAndRecency),
    ("window closure and empty/single sessions", modeChecks.testWindowSessionReconciliation),
    ("titles fit count-adaptive window rows", modeChecks.testWindowTitleLayout),
    ("strict hidden filter and exclusions", checks.testStrictHiddenFilterAndExclusions),
    ("initial and remembered order", checks.testInitialOrderAndRememberedOrder),
    ("hide/unhide preserves history; termination removes app", checks.testHiddenHistorySurvivesUnhideAndTermination),
    ("repeated quick switching", checks.testRepeatedQuickSwitching),
    ("reverse and circular navigation", checks.testReverseAndCircularNavigation),
    ("hidden/accessory foreground selects first visible app", checks.testMissingForegroundDoesNotSkipFirstVisibleApp),
    ("removing selection keeps original successor", checks.testRemovingSelectionKeepsOriginalSuccessor),
    ("live reconciliation preserves order and adds new apps", checks.testReconcileDoesNotReorderAndAppendsNewApps),
    ("zero and one application", checks.testEmptyAndSingleApplication),
    ("consumed key-up survives cancellation and repeats", checks.testConsumedKeyUpSurvivesSessionEndAndRepeat),
    ("panel width follows application count", layoutChecks.testCompactWidthGrowsWithApplicationCount),
    ("dense rows shrink before overflowing", layoutChecks.testLargeCountsShrinkBothWidthAndHeightBeforeScrolling),
    ("caption follows selection without clipping", layoutChecks.testCaptionTracksSelectionAndStaysInsidePanel),
    ("caption remains visible after scrolling and on small displays", layoutChecks.testCaptionAfterOverflowScrollAndSmallDisplay),
    ("stationary pointer cannot override keyboard selection", interactionChecks.testStationaryPointerAndRealMovement),
    ("badges preserve actual Dock labels and suppress empty counts", interactionChecks.testActualBadgeLabels),
]
for (name, check) in cases {
    let before = failures.count
    check()
    print("\(failures.count == before ? "PASS" : "FAIL") \(name)")
}
for failure in failures { fputs("\(failure)\n", stderr) }
print("\(cases.count) checks, \(failures.count) failed assertions")
exit(failures.isEmpty ? 0 : 1)

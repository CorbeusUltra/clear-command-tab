# Testing

Run `zsh scripts/check.sh` in a macOS display session. Add `--render` to write hidden-view light/dark previews under `.build/SettingsPreviews`. These checks do not display windows or change the real app's preferences or permissions.

The enabled app shortcuts are Command-Tab and Command-Option-Tab. Dispatch checks require Option-Tab and Shift-Option-Tab to return no mode; the real Guide is checked for the same availability. Window-model and focus checks remain useful for shared app-focus behavior and the [parked feature](PARKED_FEATURES.md).

## Layers and intent

| Layer | Exercised behavior |
| --- | --- |
| Core scenarios | MRU and selection reconciliation, hidden/revealed apps, cancellation, deferred focus, consumed key ownership, yellow-button gesture lifetime, adaptive layouts |
| AppKit integration | Actual Settings controls and accessibility outputs, conditional permission actions, paused/failed operation states, restoration of stored Matte values and materials, tab sizing/scrolling, live content/selection/icon updates |
| Icon integration | Runtime Python/Matplotlib artwork identification and safe fallbacks |
| Installer black box | Real script with isolated inputs: fresh install, one build, prepared install, refusal on bad inputs/running app/probe failure, copy failure preserving the old installation, safe replacement |
| Opt-in OS integration | Actual fixture windows through production WindowTracker and FocusCoordinator: cross/same-app focus, hidden reveal, minimize/restore, close/reconciliation, minimized-only and windowless activation |

Installer checks mock process/signature/copy boundaries rather than source text. Successful replacement sends only a newly created fixture installation to macOS Trash. It never changes the user's installed application or keychain. That case is skipped where the Trash tool is unavailable.

The review removed assertions about literal local booleans and repeated focus-history expectations already covered by the focused scenario suite. ABI byte checks remain because offsets, padding and payload sizes cross an OS boundary. Tests are selected for observable outcomes and failure recovery, not counts or line coverage.

The panel cache regression checks edit content while retaining target IDs, inspect actual accessible destinations, move selection, and verify that replacing an icon changes rendered output. They do not simply assert the new cache predicate.

## Live focus checks (explicit opt-in)

```sh
CCT_LIVE_PREPARE_ONLY=1 zsh scripts/check-live-integration.sh
# Manually grant Accessibility to .build/LiveIntegrationChecks/Host.app.
python3 scripts/run-live-checks.py .build/LiveIntegrationChecks/Host.app .build/LiveIntegrationChecks/report.json
```

The distinct host is named **ClearCommandTab Integration Checks**. Its permission is separate from ClearCommandTab. The test launches two document-free fixture apps, switches only their windows, terminates them gracefully, and restores the previous foreground app. It does not inject keyboard events or edit permissions. Code 77 means unavailable permission/capability, never success. Run only when short visible focus changes are acceptable. Rebuild with `zsh scripts/check-live-integration.sh` after source changes.

Each run uses a fresh report path, so a stale successful result cannot mask a launch failure. Latencies span commit through confirmed OS foreground/keyboard focus, rather than physical key input through display presentation.

## Remaining manual coverage

Physical shortcuts through the global event tap, pointer interactions on other apps' yellow controls, Secure Input, permission revocation, sleep/wake, Spaces/fullscreen, multiple displays and a subsequent login remain target-machine scenarios. Synthetic input does not reliably exercise the real global tap. Hidden-view rendering checks layout and drawing, but does not prove behind-window glass appearance or system compositor behavior. See VALIDATION.md for the actual execution status.

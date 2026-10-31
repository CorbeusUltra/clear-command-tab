# Testing

Run `zsh scripts/check.sh` in a macOS display session. Add `--render` to write hidden-view light/dark previews under `.build/SettingsPreviews`. These checks do not display windows or change the real app's preferences or permissions.

The enabled app shortcuts are Command-Tab and Command-Option-Tab. Dispatch checks require Option-Tab and Shift-Option-Tab to return no mode; the real Guide is checked for the same availability. Window-model and focus checks remain useful for shared app-focus behavior and the [parked feature](PARKED_FEATURES.md).

## Layers and intent

| Layer | Exercised behavior |
| --- | --- |
| Core scenarios | MRU and selection reconciliation, hidden/revealed apps, cancellation, deferred focus, consumed key ownership, yellow-button gesture lifetime, adaptive layouts |
| AppKit integration | Actual Settings controls and accessibility outputs, automatic permission presentation, explicit/login/service launch classification, paused/failed operation states, restoration of stored matte values and materials, tab sizing/scrolling, live content/selection/icon updates |
| Icon integration | Runtime Python/Matplotlib artwork identification and safe fallbacks; adaptive artwork across light/dark/light drawing |
| Native own-icon catalog | Existing arrow geometry/palettes, macOS-only `.icon` compilation, real light/dark Assets.car stacks and packaged resources |
| Installer black box | Real script with isolated inputs: fresh install, one build, prepared install, refusal on bad inputs/running app/probe failure, copy failure preserving the old installation, safe replacement |
| Opt-in OS integration | Actual fixture windows through production WindowTracker and FocusCoordinator: cross/same-app focus, app return with deliberately stale cached window, hidden reveal, minimize/restore, close/reconciliation, minimized-only and windowless activation |

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

## Hidden lifecycle and keyboard recovery

```sh
zsh scripts/check-application-lifecycle.sh
zsh scripts/check-keyboard-recovery.sh
```

The lifecycle check uses an isolated notification center, existing read-only application metadata and injected running-app snapshots/liveness. It reproduces a terminated app retained in a stale snapshot, late activation, a missing termination event, selection succession and an empty final list. It stops only a disposable `/bin/sleep` child to verify real kernel liveness. Two existing regular apps are required; otherwise exit 77 indicates a skip.

It also changes only its own process's appearance while an injected icon resolver is blocked. The test verifies the real effectiveAppearance observation refreshes artwork without app activation and rejects the old in-flight image. It does not change the system theme.

The same suite now supplies arbitrary changing images to the production tracker and checks visible-only refresh, round-robin coverage, nil/unchanged-image retention, timer stop and late completion after termination. `check-application-icons.sh` independently changes the contents of the same drawing NSImage between rasterizations. Neither test claims another app publishes its custom Dock content through NSRunningApplication.

The hidden Settings suite tests Command-W separately for Settings, Guide and About using local NSEvent dispatch to the actual NSWindow, and compares native close callbacks with the red button. It asserts no Quit request. Independent hidden fixtures are used because an already closed window correctly emits no repeated close notification.

Run `zsh scripts/check-icon-catalog.sh` for only ClearCommandTab's native logo pipeline, or `python3 Tests/IconCatalogChecks/main.py .build/ClearCommandTab.app` to inspect the already compiled and packaged result. The checks read the `.icon` manifest and actual assetutil catalog metadata and compare the glyph bytes against the original production arrow renderer. About appearance transitions remain covered by the Settings suite. See [API boundaries](APPLICATION_ICONS.md) for the distinction between these subjects and remaining UI/OS coverage.

The keyboard check runs a prohibited-activation, windowless host signed with the app's configured identity. It uses existing Accessibility trust or exits 77 without prompting. Its delegate passes every real event through and never posts input. The check disables its own native tap without a timeout callback, waits for automatic recovery, exercises the timeout handler and confirms Stop prevents recovery. It never disables the installed app's tap. The runner unregisters the temporary host afterward. Results describe native tap recovery, not a physical shortcut or the exact ChatGPT quit sequence.

## Remaining manual coverage

Physical shortcuts through the global event tap, pointer interactions on other apps' yellow controls, Secure Input, permission revocation, sleep/wake, Spaces/fullscreen, multiple displays and a subsequent login remain target-machine scenarios. Synthetic input does not reliably exercise the real global tap. Hidden-view rendering checks layout and drawing, but does not prove behind-window glass appearance or system compositor behavior. See VALIDATION.md for the actual execution status.

## Complete non-visible regression command

`zsh scripts/check.sh --all` runs the standard suites, lifecycle/cache/queue checks,
native own-logo compilation and read-only source-export validation. It does not
run global input, focus-changing fixture checks or request new permission.

Lifecycle checks now use in-memory preferences. They block the utility icon queue
to verify cancellation before decoding and preservation of required appearance
work. Injected scanner results exercise the production targeted merge, geometry
coalescing and unchanged-snapshot paths. Check-only builds dispatch local mouse
objects to the production callback using fake hits, without installing a mouse
tap or posting events. Focus dispatch tests substitute both activation paths to
verify exactly one public fallback and cancellation, without activating an app.
These checks do not prove physical click timing or every app's AX compatibility.

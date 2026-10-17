# Validation status

Publication preparation dated 2026-10-17. Bundle version remains 0.4.12, build 20.

## Execution record

- Core release scenarios: 55, no failed assertions.
- Runtime artwork checks: 20, no failed assertions.
- Hidden AppKit integration: 69 assertions, no failures. Includes permission/Grant visibility, paused/error states, restoration of stored Matte values, tab sizing and constrained-height scrolling, and cached-content regressions.
- Installer black-box scenarios: 11 passed, including failure preservation and actual Trash replacement of a newly created fixture only.
- Hidden light/dark previews rendered for permission states, Guide, About and Matte. Matte panel images are byte-identical before/after navigation optimization. Other window images include native inactive toolbar rendering variability; they are reviewed visually rather than treated as stable pixel goldens.

- Native Apple Silicon release and x86_64 cross-compilation passed. Intel execution remains untested.
- A fresh curated export compiled and packaged successfully with no personal configuration or certificate; its development signature is explicitly ad hoc. macOS 27 SDK / Command Line Tools emitted missing optional framework/library search-path warnings, but linking and strict signature verification succeeded.
- Authorized distinct GUI host: live focus/discovery scenarios passed with no failures, including 12 cross-app window switches, same-app switching, four hidden reveals, minimize/restore, closing the selected window, minimized-only and windowless apps, and unchanged target dimensions. The previous foreground was restored and fixtures terminated.

Final installed-app verification is recorded below. Benchmarks and their limits are in [PERFORMANCE.md](docs/PERFORMANCE.md).

## Limits

Passing logic or hidden-view checks does not prove physical global-shortcut interception or behind-window compositor appearance. Physical keys, yellow-button pointer interaction, fullscreen/Spaces, multiple displays, Secure Input, permission revocation, sleep/wake and actual launch at login remain manual target-machine scenarios. A valid signature does not establish Accessibility trust; the installed GUI process must report its own operational state.

The author delegated the licence decision on 2026-10-17. GPL-3.0-only is selected for the current project, with the upstream notices preserved. The provenance audit still records limits in the historical evidence; this is not a claim of MIT compatibility. Future binary distribution must include the licence/notices and provide corresponding source under GPLv3. No publication or push was performed.

## Installed result

- The existing app quit gracefully. The already signed release bundle was installed with `--no-build`; installation did not rebuild or sign again. The previous installation was moved to macOS Trash.
- The installed executable's SHA-256 matches the prepared executable, strict signature verification passes, and exactly one running instance uses the installed Applications path.
- Before Option-Tab retirement, the installed GUI process logged **Ready** for all three switching modes. This is its own status after GUI launch, rather than trust inferred from a terminal diagnostic. No app settings or permission records were reset.
- A 30-second idle observation sampled 0.0% CPU throughout; cumulative process CPU rose by 0.01 seconds. Physical footprint: 24.7 MiB, peak 27.5 MiB. The earlier instance measured 40.5 MiB / 47.8 MiB, but had a different lifetime and workload: these figures do not establish a memory saving from the navigation change. Controlled benchmark peak RSS is effectively unchanged.
- No remote is configured; no commit, push, repository creation or publication was performed. Local history and private note backups remain intact. The curated export deliberately excludes them.

## Option-Tab retirement — 2026-10-17

- README credit uses the author's requested wording. The current product advertises only Command-Tab and Command-Option-Tab.
- The shortcut dispatcher leaves Option-Tab and Shift-Option-Tab unclaimed. The retained window mode, models, shared discovery/focus code and checks are documented in `docs/PARKED_FEATURES.md`; the private snapshot is excluded from exports.
- Release checks passed: 55 core scenarios, 20 icon checks, 69 hidden AppKit assertions, and 11 installer scenarios. The Guide was rendered in light/dark appearance; the dark rendering was inspected.
- The app quit gracefully, the already signed bundle was installed with `--no-build`, and the installed app relaunched. Its binary matches the prepared build, strict signature verification passes, and exactly one process runs from the installed path.
- The GUI process reports **Ready** with only the two app shortcuts. Neither app preferences nor permission entries were reset. Physical global-tap shortcuts were not injected; the shortcut dispatcher and actual Guide controls are covered by the checks.

## Application identity migration — 2026-10-17

- The author selected `io.github.corbeusultra.ClearCommandTab`. Bundle metadata, runtime notifications/logs, signing and fixture/preview identifiers are aligned.
- Checks passed: 55 core scenarios, 20 icon checks, 69 hidden AppKit assertions and 11 installer scenarios. Fixture bundle identifiers were built and checked against the new namespace.
- The old app quit gracefully; five preference values were copied into the empty new domain and verified independently before launch. The old domain and private backups are retained. The launched app retains glass appearance, menu-icon visibility and yellow-button behavior preferences.
- The bundle was signed once with the stable certificate and installed with `--no-build`. Metadata and code-signing identifier both match the selected identity, the installed executable matches the prepared build, and exactly one GUI process runs from the installed path.
- That GUI process reports **Accessibility permission required**, as expected after the identity change. The author chose to complete the renewed authorization later. Shortcut and yellow-button interception are therefore not operational until that manual step is completed; no ready state is claimed. No TCC/permission record was edited or reset.
- Launch-at-login and the separate macOS menu-bar allowance remain system-managed; the preference copy does not claim to transfer those approvals. The current GUI controls report their current native state.

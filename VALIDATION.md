# Validation

Target: Apple silicon Mac, macOS 27.0.1 (26A434), Apple Swift 6.4.

## Version 0.4.2: native focus and fast-selection synchronization

- The user explicitly approved direct native focus comparable to AltTab. The approved glass and panel source files remain byte-for-byte unchanged, with the same SHA-256 values recorded for 0.4.1. The paused menu-bar icon and app-MRU/window-MRU grouping remain unchanged.
- All three modes now share one user-interactive serial focus queue. The optional `GetProcessForPID`, `_SLPSSetFrontProcessWithOptions`, and `SLPSPostEventRecordTo` functions are resolved at runtime. Process lookup was probed against the diagnostic process only; process serial number size is 8 bytes and lookup returned success. Runtime bridge availability, window identity, and glass availability all reported true. No focus/activation/event-posting call was made in the diagnostic probe.
- Native commits front the target process as user intent, make its window key with a zero-initialized 256-byte off-content down-only record, and perform AX Raise. Native window commits do not issue a later public app activation. App commits reveal only the selected hidden app and do not restore minimized windows or reopen documents. Missing optional symbols use a public fallback, explicitly reported in status/diagnostics.
- Confirmation checks both the observed system AX focused application and the foreground app. Window commits additionally require the exact AX focused window ID. Request acceptance and AX Raise return codes are not treated as proof of focus. Readback is bounded to 800 ms, runs off-main, and never retries activation. Cancellation guards every remaining action and completion; physical clicks/typing, new selection, pause, permission loss, and Space/session changes cancel pending work.
- Rapid repeated selections use the preceding logical target to compute a local candidate order, without prematurely changing confirmed MRU. Expected previous-commit activation notifications are consumed once for at most 800 ms, preventing a late acknowledgement from dismissing the next panel. Snapshots begun before a focus or foreground transition are invalidated; cold-discovery callbacks are preserved for the next scan. A cached focused window from another foreground app is no longer used as the current window.
- 36 regression checks passed in debug and release. New checks cover superseded completion, late own activation, external cancellation/expiry, failed focus, rapid same-app and cross-app switching, old snapshots, external foreground changes, and exact record padding/window ID/off-content coordinates. These model checks validate synchronization and encoding, not real WindowServer behavior or end-to-end latency.
- Pre-update sources and installed 0.4.1 app backed up in `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-204957-before-0.4.2/`. The old instance quit normally; the installer moved its installed bundle to Trash before installing the signed 0.4.2 build 10 at `/Users/lucas/Applications/VisibleTab.app`. Strict signature verification passed and the installed executable matches the release build. VisibleTab is closed.
- No real-app/window focus test, overlay, Settings automation, or authentication was performed. The workflow stops for the user to renew Accessibility themselves. Ready and real focus/latency remain unverified until the physical-keyboard acceptance check.

Manual acceptance after permission renewal: select a hidden app with Command-Option-Tab and immediately type in it; rapidly repeat Option-Tab within one app and across app groups; change foreground app and immediately use Option-Tab; check ordinary Command-Tab, Escape/immediate typing, unchanged glass, and Space behavior.

## Version 0.4.1: responsiveness, grouped windows, and hidden-app focus

- The user approved the 0.4.0 glass color. `GlassProfile.swift` and `SwitcherPanel.swift` are byte-for-byte unchanged. SHA-256: glass `fe7ce5c9f2193a9bfb14cec814aeb8c897bd8c8c6b5c8592c26a8bbe95833249`; panel `5e0c45dccee3b615e48cf2bc5587baedb5f5d5968bfd747e72b8b06b452c72eb`.
- Removed the 150 ms overlay delay. Opening a mode now schedules rendering on the next main-queue turn using cached names, bundle identities, bitmaps, Dock PID, and display placement. No icon refresh or warm full-window scan is initiated by a shortcut.
- Icon fetching/rasterization runs on a utility queue, with per-app coalescing, five-second activation throttling, and bounded launch retries. Activation notifications no longer re-enumerate all apps or reload icons synchronously. Icon completions update only the view, without triggering window discovery.
- A headless benchmark of the old synchronous nine-app icon refresh measured 854.0 ms for the first pass, followed by 363.9, 362.2, 361.1 and 360.1 ms. A cached nine-app metadata pass averaged 0.00163 ms. The benchmark intentionally excludes overlay rendering and real app activation; it is not an end-to-end shortcut latency claim. Report: `.build/LatencyCheck-0.4.1/report.json`.
- Existing permission/Secure Input checks measured approximately 0.41 ms per event and are retained. Idle sampling showed the main loop predominantly waiting; the identified issue is work performed during switching, not an idle CPU loop.
- Window focus has an independent user-interactive queue, a shorter 30 ms AX timeout, a single eligibility/identity preflight, and cancellation on superseding requests, pause, or Space changes. It does not wait behind the 700 ms discovery budget. Partial snapshot processing no longer queries WindowServer on the UI thread. Cold selection never commits after the modifier has already been released.
- Hidden-app reveal and activation share a testable commit sequence: Cocoa keeps `isHidden` cached until a later run-loop turn, so an accepted `unhide()` is followed by activation without re-reading that stale flag. The public app activation API is unchanged.
- Window groups follow app MRU, with window MRU inside each group. Reconciliation keeps new windows adjacent to their app and preserves selection. Current application visibility immediately filters stale window snapshots.
- Pre-update sources and installed 0.4.0 app backed up in `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-200721-before-0.4.1/`.
- The paused menu-bar button retains the usual arrow symbol and uses AppKit's disabled appearance to dim it; it remains clickable.
- 26 core checks passed in debug and release. The signed 0.4.1 release (build 9) was installed at `/Users/lucas/Applications/VisibleTab.app`; strict signature verification passed. The old instance quit normally, the old installed bundle was moved to Trash, and the new instance remains closed pending the user's permission renewal. Its installed executable matches the release build. No Ready status or end-to-end latency result is claimed before that handoff. No real app/window activation or visual overlay was automated. The user handles renewed permission and the physical-keyboard acceptance checks.

Manual acceptance: verify immediate opening and repeated cycling in all three modes, prompt focus at modifier release (especially hidden apps), app-group/window-MRU order, unchanged glass, Escape/keyboard recovery, and Space/multiple-monitor behavior. Headless timings cannot replace these checks.

## Version 0.4.0: three modes and reversible glass experiment

- Pre-update sources and installed 0.3.4 bundle preserved in `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-191554-before-0.4.0/` before editing. Current glass remains selectable without reinstalling.
- Added distinct application/window target identities, explicit shortcut dispatch and modifier ownership, a hidden-app MRU view, and window MRU. Original Command-Tab filtering is unchanged. Hidden-mode commit unhides only the chosen app; cancel does not unhide apps. Window mode excludes minimized windows and hidden apps, and matches on-screen windows using an optional runtime identity bridge.
- Window discovery and Accessibility subscription/focus work run on a serial queue. Per-element messaging timeouts are 60 ms; discovery has a 700 ms soft budget, with an already-started IPC call permitted to finish. Cold selection is canceled after 900 ms. There is no idle window polling. Space transitions invalidate outstanding snapshots and selections.
- Left-click toggles all modes; right-click/Control-click opens Settings/Quit. Window tiles include titles, separate from ordinary app-mode captions. Existing pointer gating, badges, responsive layout, Secure Input fallback, key/nonactivating focus handling, and ordinary-mode H/Q are retained.
- Glass choice Current/AltTab constructs either the previous public-clear material or clear with guarded internal variant 3. The setter's signature is `v24@0:8q16` on this Mac. Runtime identity bridge and guarded glass profile availability both checked true without opening an overlay.
- 22 core checks passed in debug and release, with zero failed assertions. Coverage includes existing filtering/history/layout/pointer/badge behavior, three-mode routing, modifier-release priority, hidden MRU, distinct windows of one app, window recency and reconciliation, empty/single lists, and per-window title geometry.
- Read-only diagnostics successfully rasterized icons for all 9 regular apps in the live snapshot. No regular Python GUI app was present; the Matplotlib source/cache diagnosis and comparison against native Command-Tab remain pending. Refresh and rasterization improvements are implemented but the specific reported Python issue is not claimed fixed.
- No overlay, real window focus action, permission-setting edit, or physical-keyboard integration test was performed for this version. The 0.4.0 release bundle (build 8) was built and installed at `/Users/lucas/Applications/VisibleTab.app`; strict signature verification passed. The old installed bundle was moved to Trash by the installer, in addition to the dated backup. The old instance quit via a normal NSRunningApplication termination request. The new app was left closed for the user to open and renew permission; no Ready status is claimed. User handoff for renewed Accessibility permission is required before live tests.

### Required manual acceptance after permission renewal

1. Left-click pause/resume; right-click Settings/Quit. Native Command-Tab must return while paused.
2. Visible app switching unchanged, including minimized/windowless apps; Shift, arrows, pointer movement, Escape and immediate keyboard recovery.
3. Hide two apps, cycle Command-Option-Tab, cancel and verify neither was revealed. Commit one, including releasing Option before Command, and verify only that app becomes visible.
4. Open multiple windows of one app and another app. Verify window titles, previous-window switching, Shift, modifier release, covered-window inclusion, minimized/hidden/other-Space exclusions, closure during selection, Space changes and multiple monitors.
5. Compare Current and AltTab glass on white and dark backdrops, checking selection contrast, refraction and artefacts. Switch to Current immediately if the experiment is unsuitable.
6. Reproduce the original Matplotlib window from VS Code, compare its icon with native Command-Tab, and collect icon diagnostics if it still differs.

## Version 0.3.4: selection contrast on bright backdrops

- The user reported that selection becomes indistinguishable on a white backdrop. The previous custom indicator drew `labelColor` at 16% opacity; in dark appearance this is white, so it provides no contrast over white content beneath clear glass.
- Replaced that custom fill with a single AppKit `NSVisualEffectView` using `.selection`, `.withinWindow`, `.active`, and `isEmphasized = false`. It sits behind the icon cells, follows the selected tile, uses the same rounded geometry, and scrolls with the row. Icon artwork and badges are not made vibrant. Public clear glass and key-window handling are unchanged.
- Release bundle build and strict signature verification passed. No core-model behavior changed.
- A comparison harness was prepared for white and black backdrops. Computer Use repeatedly failed with `cgWindowNotFound`, including when targeting the installed app; a native window diagnostic confirmed the temporary window was onscreen. No successful screenshot was obtained, so visual contrast improvement is **not yet verified**.
- At this initial checkpoint, installation and the user's live white-background confirmation were pending. Before the 0.4.0 update, the installed bundle was verified as 0.3.4 and backed up; no additional live contrast result is recorded here.

## Version 0.3.3: active public clear glass and larger badges

- The user confirmed that the existing public-clear panel still rendered incorrectly and asked for larger badges. A controlled behind-window comparison of root, inset, and grouped layouts remained opaque in all three cases. Adding public behind-window visual-effect underlays (under-window, sidebar, HUD) did not resolve it either, as confirmed by the user.
- A comparison holding the clear style/backdrop constant while changing key-window eligibility revealed the decisive difference: the user confirmed **Key .clear** displays the backdrop/refraction and changes when it loses key state. The final implementation uses the public `.clear` material and a nonactivating panel that can become key; it uses no private rendering method, underlay, or screenshot of the desktop.
- A three-second GUI harness using the production `SwitcherPanel` verified that it becomes key, keeps the original NSWorkspace foreground application, dismisses successfully, releases key status, and preserves the original foreground application afterward. All five assertions passed. The harness appeared near the screen edge and exited automatically.
- Badge diameter increased from 36 to 48 points for a 144-point tile (+33%); text increased from 23 to 30 points. Minimum badge/text sizes increase accordingly for dense layouts, and badges remain constrained to their cells.
- Version 0.3.3 release build and strict signature verification passed. The installed GUI reports **Ready** after refreshing only VisibleTab's existing permission entry. Settings windows were closed. All diagnostic processes are stopped and their temporary sources/bundles/reports were moved to Trash.
- Physical keyboard checks of Command release, Escape, and an unrelated shortcut after cancellation remain necessary because tool-injected events bypass the global tap. Final installed appearance requires a live user check.

## Version 0.3.2: public clear glass

- The user reported a white-point artifact and insufficient native refraction with the internal profile. A controlled public-API comparison showed `.regular` and `.clear` on the same striped in-window backdrop: both refracted the edges, while `.clear` preserved the center detail and produced pronounced edge lensing. The user explicitly selected **public .clear**.
- The comparison window appeared near a screen edge, not in the center, and automatically exited after six seconds. The observed refraction belongs to this controlled in-window case; production behind-window appearance remains a separate live check.
- Removed the private glass implementation entirely (source moved to Trash). Production uses plain `NSGlassEffectView`, `.clear`, nil tint, and default noninteractive state. No private selectors or global preference mapping remain. Badges, adaptive size, and pointer-motion gating are retained.
- Release build and strict signature verification passed; 0.3.2 is installed at the existing path. Only VisibleTab's permission entry was renewed; its GUI reported **Ready**. Settings windows were closed and the disposable comparison app/source moved to Trash. Production visual confirmation is pending.
- The previous assertion that private methods were necessary for refraction was too strong: Apple's public API supplies refraction, demonstrated by the comparison above. An exact match to Apple's private switcher is not guaranteed.

## Version 0.3.1: extended clear compositor and badge styling

- The user confirmed 0.3.0 pointer behavior and visible notification badges, but reported that public Liquid Glass and badge styling still differed from Apple. The user explicitly approved private rendering methods to prioritize visual fidelity.
- Runtime introspection on macOS 27 verified the names and integer argument/return encodings of four glass properties. The minimum global tint now enables the internal clear compositor (variant 13, interaction 1, scrim 0, subdued 0). A no-window probe instantiated the production view and verified these values before and after layout without displaying an overlay.
- The profile is limited to the verified major OS and checked method signatures. Unsupported runtimes use public regular glass. Nonzero system tint and Reduce Transparency/Increase Contrast retain the standard material. Preferences are refreshed when a new panel opens, with no idle polling or writes to system preferences.
- Badges use larger circles and lighter number typography, an optical top-right anchor, a subtle red gradient/shadow, and no white outline. Wide labels and small icons remain inside their cells. These are custom badges; an exact match to Apple's private badge renderer is not claimed.
- Version 0.3.1 release build and strict bundle-signature verification passed. The current bundle was installed at the same path, with the previous bundle moved to Trash. After the user completed Touch ID, only VisibleTab's permission entry was renewed; the installed GUI reported **Ready**. Settings windows were closed afterward.
- The transparent compositor's actual appearance and revised badge styling still require live visual confirmation. No visual overlay was opened for development.

## Version 0.3.0: system glass appearance, badges, and pointer selection

- Replaced the forced clear variant with standard adaptive Liquid Glass, removed custom tint, and explicitly disabled clip-view background painting. The global Liquid Glass tint amount was observed as 0 and Reduce Transparency as disabled; no system preference was changed. Live visual matching remains to be confirmed.
- Sixteen core checks pass in debug and release. New checks cover a stationary pointer beneath an opening/reframed panel, repeated stationary events after keyboard selection, real movement, jitter, session reset, and actual numeric/symbol badge labels.
- The production badge reader queried the live Dock and returned `com.apple.reminders: "1"`, matching the user's report. Dock queries run on a background queue with bounded accessibility IPC and coalesced requests, once per second only during a selection. No idle badge timer or notification-content access was added.
- Existing cells update badges without requiring application-list changes. Mouse tracking responds to movement rather than entry; clicks and accessibility presses still activate immediately.
- Version 0.3.0 was installed at the existing application path, with the previous bundle moved to Trash. Release build, property list, and strict signature verification passed. The obsolete VisibleTab permission entry was replaced with the current bundle without changing permission scope; the installed GUI reported **Ready**.
- No preview overlay was opened during this revision. Actual held-key pointer behavior, badge rendering, and Liquid Glass transparency require a live user check because synthesized automation bypasses the global event tap.

## Version 0.2.0: native glass and adaptive layout

- Native `NSGlassEffectView` clear material is used on macOS 26+, with the actual content owned by the effect view; macOS 14–15 uses the existing fallback. No fake glass image or private API is used.
- The selected caption follows its icon; optical icon padding is no longer applied twice. Panel, selection, margins, and icon sizes were adjusted toward the native switcher.
- Fourteen model/layout checks pass in debug and release. New cases cover width growth with app count, simultaneous icon/height reduction for dense rows, overflow only after the minimum icon size, bounded captions at both edges and after scrolling, small screens, and zero apps.
- The three-icon light preview was rendered and visually inspected on the target Mac. It measured 528 by 210 logical points, with correctly positioned caption and rounded glass boundary. Other icon counts are covered by layout checks; dark/dense live screenshots were not completed.
- The preview was stopped immediately when the user reported it obscured the desktop. All previews now automatically exit after six seconds (a developer override is bounded to 2–30 seconds). No further overlays were opened after that request.
- The generated preview bundles and downloaded visual reference were moved to Trash after testing.
- Release bundle builds and code-signature verification passed. Installation and renewed Accessibility status are checked separately below.
- Version 0.2.0 installed at the original application path; the previous bundle was moved to Trash. All generated preview processes are stopped. GUI launch requests renewed Accessibility permission after recompilation, even though terminal-launched diagnostics report trust inherited from their launch context. The actual GUI status is the authoritative check.
- Permission repair completed: `tccd` logged a mismatch between the 0.1 and 0.2 code requirements, which persisted after toggling the existing entry and restarting. The user completed Touch ID. Only VisibleTab's obsolete permission entry was removed, then the current bundle was added through System Settings. **Check permission** returned **Ready**, confirming the installed GUI process's event tap is active. No additional permission scope was requested.
- On the target macOS 27 installation, the permission page is named **Device Control and Data Access** under Privacy & Security. The existing `Privacy_Accessibility` deep link opens that page.

## Version 0.1.0 checks (historical)

- Release application built successfully with Command Line Tools only, without third-party dependencies.
- Installed at `/Users/lucas/Applications/VisibleTab.app`; bundle structure, property list, and ad hoc signature verified.
- Ten executable model checks passed in both debug and release builds with zero failed assertions: strict hidden filter, regular/self exclusions, remembered MRU order, hide/unhide and termination, repeated quick switching, reverse/wrap navigation, an accessory/hidden foreground app, selection removal, live reconciliation, empty/single lists, and consumed key-up ownership.
- Settings window rendered and visually inspected. The permission status, optional menu bar icon, Pause/Quit, and initially disabled Launch at login controls are present and fit the window.
- Disposable test apps A and B built for safe live Hide/Quit/minimize/windowless checks. These have no user documents or saved data.

## Version 0.1.0 live checks (historical)

- Accessibility permission granted by the user; the installed app reports **Ready** and the event tap is enabled.
- AltTab quit without changing its preferences. Its existing Launch at login setting remains enabled; avoid launching both switchers on the same shortcut.
- The user confirmed that a held Command-Tab displays the panel, hidden apps are absent, and releasing Command switches to the selected app.
- The panel was rendered in an isolated preview and visually inspected: one row of correctly rendered app icons, a selection background, and the selected app's name. Hidden apps were excluded.
- Disposable app A was hidden through its native Hide menu. The read-only diagnostic confirmed `hidden: true`; its icon disappeared from the preview while app B remained.
- App B remained in the preview after its window was minimized and after its only window was closed. The test app intentionally stays running without windows.
- Pause changed the status to **Paused**; Resume recreated the event tap and returned to **Ready**.
- The menu icon setting was toggled off, the settings closed and reopened successfully, then the icon setting restored to its initial on state. Reopening retained a single installed instance.
- Both disposable apps and the isolated preview were quit. Their generated bundles were moved to Trash; the fixture build script can recreate them.

The automation tool's synthesized keyboard shortcuts did not exercise the global event tap reliably, so the live keyboard confirmation above is user-observed. App state, panel contents, and settings controls were checked separately.

## Version 0.1.0 performance (historical)

- Installed release executable: approximately 268 KiB on disk, excluding the icon and system frameworks.
- `vmmap -summary` reported a **29.0 MiB physical footprint**, with **32.5 MiB peak**, after the live checks. RSS varies with memory compression and is not used as the primary memory figure.
- Final 30-second observation: nine CPU samples at 0.0%, one transient sample at 0.5%; cumulative CPU time rose from 9.40 to 9.42 seconds (approximately 0.02 seconds consumed). This is an observation on this Mac, not a resource-use guarantee.
- Earlier observations overlapped onboarding and UI tests and are not treated as idle measurements.
- The intentional panel delay is 150 ms. Keyboard-to-activation latency has not been instrumented or quantified; the user confirmed successful switching.

## Remaining scenarios

- Live repeated quick Command-Tab, Shift-Tab, Escape, arrows, hover/click, and H/Q within a held selection; these routes are implemented, with model-level coverage where applicable.
- Live reappearance after unhide and activation of minimized/windowless apps without restoration; the filter and use of activation rather than reopen are verified in code.
- Native fallback during missing/revoked permission or interception loss, beyond the observed first-launch onboarding state.
- Space changes, fullscreen, multiple displays, Secure Input, revoked permission, sleep/wake.
- Launch at login registration, approval, and an actual subsequent login. Autostart remains disabled until the user enables it.

The app is a native approximation of Apple's panel, with its own observed history. A first run cannot reproduce Apple's private historical ordering. Ad hoc signing may require renewed Accessibility approval after updates.

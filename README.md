# ClearCommandTab

Formerly **VisibleTab**. The technical bundle identifier remains `local.lucas.VisibleTab` to preserve existing preferences and signing identity during the rename.

A small native macOS switcher with three modes. **Command-Tab** excludes only applications hidden with Hide / Command-H, preserving minimized, windowless, and other-Space apps. **Command-Option-Tab** reveals a selected hidden app. **Option-Tab** switches between non-minimized windows of visible apps on the current Space, with an icon and title for each window.

## Build and install

Requires macOS 14 or later and Swift 6 tools (Xcode or Command Line Tools). There are no third-party dependencies.

```sh
cd /Users/lucas/Documents/code/all/clear-command-tab
swift run ClearCommandTabChecks
zsh scripts/install-app.sh
open /Users/lucas/Applications/ClearCommandTab.app
```

The installer refuses to replace a running instance. An existing installation (including the former `VisibleTab.app`) is moved to the macOS Trash before replacement. The app is signed with the existing local Apple Development certificate through `scripts/sign-app.sh`. The certificate and bundle identifier are kept stable across updates; the installer never silently falls back to ad hoc signing. The migration from the earlier ad hoc identity requires one renewed Accessibility grant. Subsequent builds should retain that grant as long as their designated requirement remains compatible. This is a local development app, not a notarized distribution build.

## Local version history

This project is a local Git repository on `main`. No remote is configured and nothing is published. Completed changes are recorded as local commits instead of creating another source/app backup directory for each update. Build outputs and app bundles are ignored.

```sh
git log --oneline --decorate
git tag --list
```

The existing source snapshots were imported as tags `v0.3.4` and `v0.4.0` through `v0.4.6`. Each imported source file was checked against its original backup. The former expanded backup folders, including signed apps and restore notes, are preserved in `/Users/lucas/Documents/code/all/clear-command-tab-archives/visible-tab-backups-through-0.4.5.zip`. The pre-fix installed app is retained as `ClearCommandTab-0.4.6-build14.zip` in that directory. Compressed archives avoid advertising old app bundles to Spotlight. Historical paths in the release notes describe their original locations.

## First launch

1. Quit other switchers that capture Command-Tab (such as AltTab).
2. Open ClearCommandTab. Click **Grant Accessibility…** and enable ClearCommandTab in **System Settings → Privacy & Security → Accessibility**. If macOS asks to authenticate, complete that step yourself.
3. Return to ClearCommandTab and click **Check permission**. The status should read **Ready**.
4. Close the settings window and use Command-Tab.

No Screen Recording permission is needed: ClearCommandTab uses app icons and window bounds, not screenshots or window contents. It does not access the network or record typed text.

On macOS 27, the permission page is named **Device Control and Data Access** under **Privacy & Security**; the app's permission button opens it directly. When migrating from an old ad hoc build to the stable signed identity, an enabled switch can still reference the old binary signature. If toggling it and restarting do not restore **Ready**, select only ClearCommandTab in that list, remove its permission entry, then use **Add** to select `/Users/lucas/Applications/ClearCommandTab.app` and enable the current app. This removes a permission record, not the app or its files.

## Settings window

The native toolbar has three tabs: **Settings** for glass, startup, menu-bar visibility and permissions; **Guide** for the three shortcuts and quick-switch behavior; **About** for the app icon, version/build and credits. The glass labels are **fully transparent** (previously Current) and **original** (previously AltTab). Only their names changed; existing selections and rendering are preserved.

## Controls

| Input | Action |
| --- | --- |
| Left-click the menu bar icon | Pause / resume all three modes |
| Right-click or Control-click the menu bar icon | Open the menu with Settings and Quit |
| Quick Command-Tab | Switch to the previously active visible app |
| Command-Option-Tab | Cycle hidden apps; release Command to reveal the selection |
| Option-Tab | Cycle grouped current-Space windows; release Option to focus the selection |
| Hold Command or Option, then Tab | Display the panel after 150 ms; a quick release switches immediately without showing it |
| Shift-Tab | Move backward |
| Left / Right arrow | Move backward / forward |
| Release Command | Activate the selected app |
| Escape | Cancel |
| H in Command-Tab | Hide the selected app and remove it from the list |
| Q in Command-Tab | Request a normal quit; never force quit |
| Move the pointer over / click an icon | Select / activate that app |

Selection wraps at both ends and remains in the mode selected by the opening chord. Releasing Option before Command in the hidden-app mode does not change its mode or reveal anything early. Escape leaves all hidden apps hidden. Unknown shortcuts, Control chords, and modifiers belonging to another mode cancel selection and pass through. H and Q retain their original behavior in the ordinary Command-Tab mode.

Window mode includes covered windows on the current Space across connected screens. It excludes hidden apps, minimized windows, windowless placeholders, inactive tabs, and utility panels. App and window MRU are separate. Window groups follow app MRU; each group keeps its own window MRU. Newly discovered windows join their app group without changing the current selection. A first run uses front-to-back window order until focus changes are observed. Window discovery runs asynchronously. Normal switching uses already-known destinations and does not request a new full scan. At startup or after a Space change, hold Option while the initial window snapshot is gathered. Releasing it before any destinations are ready cancels immediately, rather than activating a window later. Cold discovery is bounded to 900 ms. Unsupported or unresponsive Accessibility windows may be omitted. Focus uses an optional native front-process/key-window bridge followed by Accessibility Raise. Actual foreground and keyboard focus are read back before updating MRU; an accepted API request alone does not count as success. If the bridge is missing, public app activation and AX attributes remain a fallback with weaker focus guarantees.

All three modes use the same 150 ms presentation delay. Releasing the held modifier switches immediately without displaying the panel; further Tab/arrow navigation displays it immediately.

A stationary pointer does not select an icon when the panel opens beneath it. Pointer selection starts after actual movement of at least one logical point; clicks remain immediate.

The right-click menu provides **Settings…** (Command-,) and **Quit ClearCommandTab** (Command-Q), with a disabled status label. These key equivalents act on ClearCommandTab while its menu is open. The icon stays highlighted until the menu closes. There is no redundant Pause / Resume menu action. A left click toggles Pause / Resume. The same menu-bar arrow symbol is dimmed while paused, instead of being replaced by a pause glyph. Pause or Quit returns keyboard shortcuts to macOS and the foreground app; the menu stays accessible while paused. Pause remains temporary, as in earlier versions. **Show menu bar icon** can be disabled; reopen ClearCommandTab from Applications or Spotlight to reach the settings again. Reopening does not start another instance.

**Launch at login** is off initially. It uses macOS Service Management and can require approval in **System Settings → General → Login Items & Extensions**.

AltTab's existing preferences are preserved, including its own launch-at-login setting. Before enabling ClearCommandTab at login, disable AltTab's automatic launch or ensure it uses a different shortcut.

## Design and limits

- Swift and AppKit, with a testable model separate from the UI and keyboard integration.
- Application state follows NSWorkspace notifications. Window state follows Accessibility notifications and Space changes, with coalesced reads on a discovery queue, per-element timeouts, and a bounded discovery pass. All three modes share a serial user-interactive focus queue, so actions never wait behind a full discovery scan. A new selection cancels outstanding actions and confirmation for an older commit. Confirmation reads are bounded to 800 ms and never retry activation; physical input, unrelated activation, pause, or a Space/session change cancels pending work. WindowServer metadata reads stay outside the UI and global keyboard callback. No periodic window polling or screenshots are used. A 100 ms watchdog exists only during a held selection to dismiss a stale panel if Secure Input prevents the modifier release from reaching the event tap.
- MRU order is observed by ClearCommandTab and remembered by app identity between launches. It cannot read Apple's private switching history. The first launch places the foreground app first, followed by alphabetical app names.
- The panel is nonactivating, so the foreground application remains unchanged while selecting. It temporarily becomes the key window to keep native clear glass in its active appearance; dismissal releases that keyboard focus before activating the selected app. Selecting an app activates all its windows, without reopening documents or restoring minimized windows.
- Secure Input can temporarily restore the native switcher. Missing Accessibility permission or an event-tap failure also leaves the native switcher available.
- On macOS 26 and later, **Settings → Glass effect → fully transparent** uses the previous public `NSGlassEffectView` `.clear` style. **original**, the initial profile, applies the optional internal `set_variant:` value 3 to that same clear material, inspired by [AltTab's material implementation](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/main-window/TilesPanelBackgroundView.swift). The method and its signature are checked before use; unavailable profiles fall back to fully transparent. Switching back to fully transparent constructs a fresh public view, without guessing a private reset value. Content, key-window handling, badges, and selection material are shared. An exact native visual match is not claimed. macOS 14–15 retains the older material; system appearance settings are never changed.
- The optional `_AXUIElementGetWindow` bridge identifies windows so they can be matched to the public on-screen WindowServer list. It is resolved at runtime and used only for identity, with no injection or system changes. If unavailable, Option-Tab is disabled with an explanation; both app modes remain functional.
- Application icons are rasterized from the actual running app's icon. They load on a background queue at discovery, refresh individually on activation (throttled to five seconds), and receive four bounded launch retries to avoid keeping an early placeholder indefinitely. Panel opening uses the cached bitmap without any icon query or decoding. Icon resolution runs outside both the global keyboard callback and the UI thread. App names, bundle identities, Dock PID, and screen placement are also cached for the switching path. The original optical margins are retained. Matplotlib's reported white-icon issue still needs a reproduction from VS Code to establish whether the source icon itself is wrong or the previous cache/rendering was responsible.
- App badges come from the Dock's accessibility status labels and match apps by bundle identity. They refresh asynchronously once per second only while switching, using the existing Accessibility permission. Apps without an exposed Dock badge have no badge; notification contents are never read.
- The panel is a native approximation, not Apple's private UI. Its width follows the app count, with full-size icons when there is room. Dense rows proportionally reduce icons, gaps, margins, and panel height. Horizontal scrolling is used only after reaching the minimum readable icon size. The selected app's name follows its icon and stays within the panel.
- Selection uses AppKit's neutral selection material within the window, behind the app icon, instead of a theme-dependent white/black translucent fill. The native clear glass remains the outer surface.
- Resizing is animated only for an already visible panel and respects Reduce Motion. The glass material follows the system appearance and accessibility rendering.
- Space changes, session changes, sleep, clicks outside the panel, and unrelated app activations cancel a pending selection. An expected activation from our previous commit is recognized once for up to 800 ms and cannot dismiss a newer selection. Focus snapshots are versioned on focus transitions and foreground changes; stale responses cannot restore the old focus or MRU. A rapid selection uses the previous logical target to choose the next destination without modifying confirmed history.

The glass profile, settings, and a bounded app-order history are stored in the `local.lucas.VisibleTab` UserDefaults domain. No keystroke history is stored.

## Development checks

```sh
swift run ClearCommandTabChecks
zsh scripts/build-app.sh
.build/ClearCommandTab.app/Contents/MacOS/ClearCommandTab --diagnostics
open .build/ClearCommandTab.app --args --preview
```

`--diagnostics` prints a local JSON snapshot of running applications, executable/bundle paths, raster-icon sizes and hashes, Dock badges, optional bridge availability, and Accessibility trust, then exits. Icon hashes describe app artwork only; no screenshots or window content are read. `--preview` displays the panel without intercepting shortcuts or activating apps and **automatically quits after six seconds**. `--preview-count=3`, `--preview-light`, and `--preview-dark` provide visual QA cases; `--preview-duration=N` sets a lifetime between 2 and 30 seconds. Neither mode is required for everyday use.

Accessibility trust depends on the launch context: a diagnostic executable started in a trusted terminal can report `true` while the app launched from Applications still lacks permission. Use the installed app's **Ready** status to verify that its actual event tap is enabled.

`python3 scripts/build-previews.py` creates isolated preview bundles under `.build/GlassPreviews/` for 1, 3, 18, and 50 icons, plus a dark case. It moves any previous generated preview directory to Trash before rebuilding it. These are development artifacts, not launch-at-login items.

Native effect reference: [Apple's NSGlassEffectView documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview).

See [VALIDATION.md](VALIDATION.md) for checks performed on the target Mac and remaining manual scenarios.

`swift run ClearCommandTabChecks` uses an executable test runner because this Mac's Command Line Tools do not contain XCTest. To build two disposable document-free apps for integration tests, run `zsh scripts/build-fixtures.sh`; the bundles are created under `.build/Fixtures/`.

## Version 0.4.0 rollback and validation handoff

The pre-update sources and installed app are preserved at:

`/Users/lucas/Documents/code/all/visible-tab-backups/20261014-191554-before-0.4.0/`

For a visual rollback, choose **Settings → Glass → Current**; no rebuild or permission renewal is needed. For a full rollback, quit VisibleTab, move the installed bundle to Trash with `/usr/bin/trash -s /Users/lucas/Applications/VisibleTab.app`, then copy the backed-up `VisibleTab.app` to `/Users/lucas/Applications/`. `source/` preserves the complete source before this update.

During the one-time migration from ad hoc signing, the user renews Accessibility themselves and clicks **Check permission**. Later updates preserve the signing identity and should not require that manipulation. Check the installed app's actual Ready status; terminal diagnostics inherit their launch context and are not proof of the installed app's grant. Any required Settings/authentication remains a manual user handoff.

## Version 0.4.1 responsiveness fix

The approved glass and panel rendering files are unchanged from 0.4.0. The 150 ms display delay and the per-opening synchronous icon refresh were removed. A headless reproduction of the previous nine-app icon refresh took about 360 ms on warm passes and 854 ms on the first pass; this work now runs off the UI thread and is not started by a shortcut. These are data-preparation measurements, not an end-to-end activation benchmark.

Hidden-app commit no longer checks the same cached `isHidden` bit immediately after `unhide()`: an accepted reveal is followed directly by an activation request. Public API activation remains asynchronous; actual focus and perceived timing must be verified with physical keyboard input after renewed permission.

Pre-fix sources and app are backed up in `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-200721-before-0.4.1/`. The installer still leaves permission renewal to the user.

## Version 0.4.2 focus and fast-switching fix

The approved glass and panel files are unchanged. The former public activation request could reveal a hidden app without making it keyboard-active. With the user's explicit approval, validated commits now optionally use `GetProcessForPID`, `_SLPSSetFrontProcessWithOptions`, and `SLPSPostEventRecordTo`, resolved at runtime. App mode brings all windows forward; window mode addresses only the selected current-Space window. A targeted down-only key-window record uses a padded zeroed buffer and a point far outside window content; it does not move the pointer or post a matching mouse-up. The native path is followed by AX Raise, without a later public activation call that could change the chosen window. The protocol is informed by [AltTab's native focus wrapper](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift) and [focus implementation](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/Window.swift). Private APIs remain optional and can change with macOS.

Foreground-app and system Accessibility keyboard focus are independently checked after the request. Window mode additionally checks the exact focused window ID. Only observed focus updates real MRU. Each new selection invalidates previous actions/completions, preserves a short-lived logical origin for rapid switching, and recognizes a previous commit's delayed activation without closing the new panel. Discovery responses started before a focus or foreground transition are discarded and refreshed. A cached focused window belonging to the former foreground app is no longer used after an external app change. App groups still follow app MRU, with window MRU inside each group.

The pre-update source and 0.4.1 app are backed up at `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-204957-before-0.4.2/`. Permission renewal and physical shortcut acceptance remain a manual user handoff. No end-to-end focus or latency result is claimed from model tests or symbol availability alone.

## Version 0.4.3 hidden-app reveal sequencing

A physical-keyboard trace on this Mac confirmed Reminders left Hide and appeared behind iTerm2 while the foreground and system AX focused app remained iTerm2. Its main window was already identifiable while hidden, so a missing window alone did not explain the failure. The old focus path ran immediately after `unhide()` returned, although the SDK defines that result as a successfully sent request, not completed unhide. The trace showed the unhide notification and visible surface arriving after modifier release; it did not capture the old native call's return code, so the exact rejection/override mechanism remains unproven.

Hidden commits now register a one-shot acknowledgement gate before calling `unhide()`. Only the selected app's `NSWorkspace.didUnhideApplicationNotification` releases it, with a later-run-loop `isHidden == false` fast path for an already-revealed app. After that handoff, the app's real main/focused window receives the same user-generated native front/key/Raise operation as Option-Tab. Revealing restores its other windows; no additional bulk-front flag is used for this path. Visible-app Command-Tab and Option-Tab retain their existing modes. If a window was selected for reveal, confirmation requires that exact focused window as well as both foreground and keyboard-focus PIDs.

The gate resumes once, ignores unrelated or duplicate notices, and is discarded on cancellation, superseding selection, or the existing 800 ms deadline. It never schedules a late activation after cancellation. The approved glass and panel files are unchanged. A bounded set of unified-log entries under subsystem `local.lucas.VisibleTab`, category `RevealFocus`, records only hidden-commit stages, native/AX result codes, process/window IDs, cancellation, and confirmation; no key contents, document titles, screenshots, or notification contents are logged. These entries make another failed user test diagnosable without guessing the missing stage.

The 0.4.2 app/source backup is `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-223317-before-0.4.3/`. After installation, the user renews Accessibility themselves before the physical-keyboard acceptance check. Compilation, synchronization tests, and the old-version trace do not establish that the new focus behavior is fixed at runtime.

## Version 0.4.4 observed reveal and stable signing

The 0.4.3 user-test log contained a reveal request followed two milliseconds later by `complete success=false`, with no acknowledgement, native front, key-window, or AX Raise entries. This identifies the early reveal guard as the failed stage, rather than a completed focus request being overridden. The old code aborted when Cocoa's `unhide()` returned false, although the user observed the app reappearing.

Reveal now writes the public application `AXHidden` attribute to false on the focus queue. Actual AX hidden-state observations or the matching unhide notification release the existing one-shot gate. If that attribute is unsupported, Cocoa unhide remains a fallback, but its negative advisory return no longer discards a subsequently observed reveal. A few bounded readiness reads run only for the pending reveal, under the same cancellation/revision checks and 800 ms deadline. No late reactivation retry, document reopening, or restoration of minimized windows is added. Existing visible-app/window paths and the approved rendering are unchanged.

Earlier builds used `codesign --sign -`: their designated requirement was the changing executable code hash. Updates now use the existing valid Apple Development certificate, pinned by public certificate fingerprint in `scripts/sign-app.sh` (override: `VISIBLETAB_SIGNING_IDENTITY`). Private key material is neither exported nor changed. This script refuses the ad hoc pseudo-identity and fails if the configured certificate cannot sign. Default certificate-based requirements remain stable when the program changes. Two separately compiled and signed probe programs had different code hashes and identical designated requirements; the second passed `codesign --verify -R` against the first's requirement. Report: `.build/SigningProbe/report.json`. This validates code-identity continuity, not a live TCC update before the initial migration grant. [Apple's code signing identity guidance](https://developer.apple.com/library/archive/technotes/tn2206/) explains how designated requirements identify updates.

The 0.4.3 source/app backup is `/Users/lucas/Documents/code/all/visible-tab-backups/20261014-231206-before-0.4.4/`. One final manual Accessibility renewal is expected when moving from the old hash-based identity to the certificate-based identity. Future normal updates should preserve permission; this must still be confirmed by the installed app's Ready status after such an update, rather than by a trusted terminal diagnostic.

## Version 0.4.5 switching feedback, quick-flip presentation, and native status menu

A read-only log inspection found accepted native front/key requests followed by timed-out AX reads (including missing window IDs), with some later confirmations and some 800 ms expirations. The previous Boolean completion converted every unconfirmed result into `NSSound.beep()`. Focus results now distinguish confirmed, unverified, and explicitly failed requests. Unverified AX reads/deadlines are quiet and do not invent confirmed history; explicit action failures retain the error signal. Confirmation reads use their own utility queue with 100 ms AX timeouts, while new actions keep their independent user-interactive queue and short timeouts. Cached MRU windows are rechecked against live WindowServer ownership and used for app commits, avoiding a fresh AX main/focused-window lookup in the common path. A last-known app window survives Hide, is removed with its app or on Space invalidation, and must be known non-minimized if not on screen.

Ordinary and hidden-app panels wait 150 ms before first display. Releasing the owning modifier sooner commits immediately with no panel; the delay affects presentation only. A second Tab or arrow navigation displays the panel immediately for deliberate cycling. Window mode keeps immediate display. Generation, held-modifier, and presentation guards prevent an old delayed display from reopening after release/Escape or during a later gesture.

The menu behavior was compared with [KeepingYouAwake's status item controller](https://github.com/newmarcel/KeepingYouAwake/blob/main/Packages/KYAStatusItemUI/Sources/KYAStatusItemUI/KYAStatusItemController.m) and [menu definitions](https://github.com/newmarcel/KeepingYouAwake/blob/main/KeepingYouAwake/KYAMainMenu/KYAMainMenu.m). VisibleTab uses the modern status-item `menu` property rather than KeepingYouAwake's deprecated popup API. It associates the menu only while open, restores left-click toggling on close, keeps the icon highlighted during tracking, removes the Pause / Resume row, and assigns Command-, and Command-Q to explicit VisibleTab targets. Keyboard interception passes through while its menu is tracking. The settings window's separate Pause control remains useful when the icon is hidden.

The certificate-based signer, bundle identifier, and install path remain unchanged. Permission should persist across this update; the actual installed app's Ready state is still the runtime check. Startup/permission status changes emit a concise Lifecycle log for that check without relying on terminal trust. The approved glass and panel rendering files are unchanged. Pre-update source and app are backed up at `/Users/lucas/Documents/code/all/visible-tab-backups/20261015-222956-before-0.4.5/`.

## Version 0.4.6: ClearCommandTab, quick window switching, and settings tabs

The project folder is now `/Users/lucas/Documents/code/all/clear-command-tab`, and the app is `/Users/lucas/Applications/ClearCommandTab.app`. Build products, source modules, menu labels and development commands use ClearCommandTab. Historical backup paths and release notes retain the names used when those snapshots were created. The legacy bundle identifier, preference domain, notification names and certificate-based signing identity are intentionally preserved.

Option-Tab now uses the same 150 ms presentation gate as both app modes. A quick release still commits immediately; further navigation displays immediately. Window ordering and focus paths are unchanged.

Settings uses native toolbar tabs (Settings, Guide, About), following the structure of [KeepingYouAwake's settings window](https://github.com/newmarcel/KeepingYouAwake/blob/main/KeepingYouAwake/Settings/KYASettingsWindow/KYASettingsWindow.m). About reads its version/build from the bundle. The glass choices are renamed fully transparent / original without changing the stored current / altTab values or either effect.

## Version 0.4.7: reliable menu shortcut routing and local Git history

Command-, and Command-Q have an explicit route while the status menu is open. When switching's event tap is active, matching key-downs, repeats and key-ups are consumed, the native menu is cancelled on its tracking run loop, and the requested action runs after menu dismissal. No key is reposted to the foreground app. Outside the menu, those shortcuts remain the foreground app's commands. The native [NSMenuDelegate key-equivalent callback](https://developer.apple.com/documentation/appkit/nsmenudelegate/menuhaskeyequivalent(_:for:target:action:)) also resolves explicit targets, including when switching is paused and its tap is stopped. Character matching follows the current keyboard layout, without a US physical-key assumption.

The earlier failure was reported during right-click menu tracking. A hidden probe confirmed that the current French layout generates a comma and that an inactive native menu can match it. Thus normal character mapping was not the reproduced failure; an explicit menu-scoped routing path addresses the remaining delivery/tracking ambiguity. Actual right-click/physical-key acceptance is still a manual check.

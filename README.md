# VisibleTab

A small native macOS application switcher that excludes **only apps hidden with Hide / Command-H**. One icon represents one app. Minimized windows, windowless apps, Finder, and apps on other Spaces remain in the list.

## Build and install

Requires macOS 14 or later and Swift 6 tools (Xcode or Command Line Tools). There are no third-party dependencies.

```sh
cd /Users/lucas/Documents/code/all/visible-tab
swift run VisibleTabChecks
zsh scripts/install-app.sh
open /Users/lucas/Applications/VisibleTab.app
```

The installer refuses to replace a running instance. An existing installation is moved to the macOS Trash before replacement. The app is signed ad hoc for local use; it is not notarized for distribution. A rebuild can require renewed Accessibility permission.

## First launch

1. Quit other switchers that capture Command-Tab (such as AltTab).
2. Open VisibleTab. Click **Grant Accessibility…** and enable VisibleTab in **System Settings → Privacy & Security → Accessibility**. If macOS asks to authenticate, complete that step yourself.
3. Return to VisibleTab and click **Check permission**. The status should read **Ready**.
4. Close the settings window and use Command-Tab.

No Screen Recording permission is needed: VisibleTab uses app icons and window bounds, not screenshots or window contents. It does not access the network or record typed text.

On macOS 27, the permission page is named **Device Control and Data Access** under **Privacy & Security**; the app's permission button opens it directly. Following an ad hoc rebuild, an enabled switch can still reference the old binary signature. If toggling it and restarting do not restore **Ready**, select only VisibleTab in that list, remove its permission entry, then use **Add** to select `/Users/lucas/Applications/VisibleTab.app` and enable the current app. This removes a permission record, not the app or its files.

## Controls

| Input | Action |
| --- | --- |
| Quick Command-Tab | Switch to the previously active visible app |
| Hold Command, then Tab | Display the switcher after 150 ms and move forward |
| Shift-Tab | Move backward |
| Left / Right arrow | Move backward / forward |
| Release Command | Activate the selected app |
| Escape | Cancel |
| H | Hide the selected app and remove it from the list |
| Q | Request a normal quit; never force quit |
| Move the pointer over / click an icon | Select / activate that app |

Selection wraps at both ends. H and Q use the current keyboard layout. Unknown shortcuts and Option/Control chords cancel the switcher and are passed to the foreground app. Hidden apps remain accessible through the Dock or Spotlight.

A stationary pointer does not select an icon when the panel opens beneath it. Pointer selection starts after actual movement of at least one logical point; clicks remain immediate.

The menu provides **Pause / Resume**, **Settings…**, and **Quit VisibleTab**. Pause or Quit returns Command-Tab to macOS. **Show menu bar icon** can be disabled; reopen VisibleTab from Applications or Spotlight to reach the settings again. Reopening does not start another instance.

**Launch at login** is off initially. It uses macOS Service Management and can require approval in **System Settings → General → Login Items & Extensions**.

AltTab's existing preferences are preserved, including its own launch-at-login setting. Before enabling VisibleTab at login, disable AltTab's automatic launch or ensure it uses a different shortcut.

## Design and limits

- Swift and AppKit, with a testable model separate from the UI and keyboard integration.
- Application state follows NSWorkspace notifications. No idle polling, previews, or window enumeration loop. A 100 ms watchdog exists only during a held selection to dismiss a stale panel if Secure Input prevents the modifier release from reaching the event tap.
- MRU order is observed by VisibleTab and remembered by app identity between launches. It cannot read Apple's private switching history. The first launch places the foreground app first, followed by alphabetical app names.
- The panel is nonactivating, so the foreground application remains unchanged while selecting. It temporarily becomes the key window to keep native clear glass in its active appearance; dismissal releases that keyboard focus before activating the selected app. Selecting an app activates all its windows, without reopening documents or restoring minimized windows.
- Secure Input can temporarily restore the native switcher. Missing Accessibility permission or an event-tap failure also leaves the native switcher available.
- On macOS 26 and later, the panel uses the public native Liquid Glass `NSGlassEffectView` with `.clear` style and no custom tint, forced interaction state, or private rendering methods. This style was chosen by the user after a side-by-side comparison with `.regular` on a contrasting backdrop. The scroll and clip views have transparent backgrounds. VisibleTab does not change system appearance settings. macOS 14–15 retains the older material.
- App badges come from the Dock's accessibility status labels and match apps by bundle identity. They refresh asynchronously once per second only while switching, using the existing Accessibility permission. Apps without an exposed Dock badge have no badge; notification contents are never read.
- The panel is a native approximation, not Apple's private UI. Its width follows the app count, with full-size icons when there is room. Dense rows proportionally reduce icons, gaps, margins, and panel height. Horizontal scrolling is used only after reaching the minimum readable icon size. The selected app's name follows its icon and stays within the panel.
- Selection uses AppKit's neutral selection material within the window, behind the app icon, instead of a theme-dependent white/black translucent fill. The native clear glass remains the outer surface.
- Resizing is animated only for an already visible panel and respects Reduce Motion. The glass material follows the system appearance and accessibility rendering.
- Space changes, session changes, sleep, clicks outside the panel, and unrelated app activations cancel a pending selection.

Settings and a bounded app-order history are stored in the `local.lucas.VisibleTab` UserDefaults domain. No keystroke history is stored.

## Development checks

```sh
swift run VisibleTabChecks
zsh scripts/build-app.sh
.build/VisibleTab.app/Contents/MacOS/VisibleTab --diagnostics
open .build/VisibleTab.app --args --preview
```

`--diagnostics` prints a local JSON snapshot of running applications, Dock badges, and Accessibility trust, then exits. `--preview` displays the panel without intercepting shortcuts or activating apps and **automatically quits after six seconds**. `--preview-count=3`, `--preview-light`, and `--preview-dark` provide visual QA cases; `--preview-duration=N` sets a lifetime between 2 and 30 seconds. Neither mode is required for everyday use.

Accessibility trust depends on the launch context: a diagnostic executable started in a trusted terminal can report `true` while the app launched from Applications still lacks permission. Use the installed app's **Ready** status to verify that its actual event tap is enabled.

`python3 scripts/build-previews.py` creates isolated preview bundles under `.build/GlassPreviews/` for 1, 3, 18, and 50 icons, plus a dark case. It moves any previous generated preview directory to Trash before rebuilding it. These are development artifacts, not launch-at-login items.

Native effect reference: [Apple's NSGlassEffectView documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview).

See [VALIDATION.md](VALIDATION.md) for checks performed on the target Mac and remaining manual scenarios.

`swift run VisibleTabChecks` uses an executable test runner because this Mac's Command Line Tools do not contain XCTest. To build two disposable document-free apps for integration tests, run `zsh scripts/build-fixtures.sh`; the bundles are created under `.build/Fixtures/`.

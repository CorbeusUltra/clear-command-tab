# Change history

## 0.4.28 — follow the macOS Spaces preference

- Read the global application-switching Spaces preference for each selection. When disabled, prefer windows on currently visible Spaces and avoid requesting all application windows; preserve the existing behavior when enabled.

## 0.4.27 — native About icon rendering

- Prefer the public AppKit application icon in About, matching ScreenshotOCR, while retaining its native adaptive representations and system icon-style choices. Refresh on presentation/appearance events without polling or changing the app icon itself.
- Retain explicit light/dark resources only as a fallback when AppKit does not supply an image. Preserve the neutral palettes, arrows, menu template and existing switching behavior.

## 0.4.26 — matching neutral logo backgrounds

- Match ScreenshotOCR's native icon backgrounds: light gray #F7F7F7 and charcoal #1F1F1F, retaining black/white arrows and their exact paths.
- Apply matching explicit sRGB colors to native catalog variants, About ICNS resources and selected previews. Render flat tiles with a solid fill to avoid gradient color conversion/dithering; preserve the existing menu template and native arrow mask.

## 0.4.25 — ClearCmdTab and matching About pages

- Rename the public app, installed bundle and executable to ClearCmdTab; retain the bundle ID, signing identity, preference keys, Swift modules and GitHub URL. Safely migrate the previous bundle name while preserving its root for login references.
- Match ScreenTextOCR About: parenthesized build on the version line, concise ordered description, original author link and one repository row. Remove the separate build/footer text.

## 0.4.24 — process observation lifetime and direct Settings launch

- Retain each observed process wrapper until its launch observation is explicitly invalidated. Release one-shot launch registrations after completion and invalidate them before tracker teardown, fixing repeated crashes during workspace refresh.
- Open Settings on the first explicit Finder/Spotlight launch, with login/service launches remaining quiet. Ignore dead process records when handing an open request to an existing instance.
- Show the current Accessibility authorization automatically instead of gating it on a manual check flag. Keep macOS as the permission source of truth; do not persist a possibly stale grant.
- Rename the Glass effect option to lowercase `matte` without changing its stored value or rendering.

## 0.4.23 — native system icon styles

- Use public Quick Look icon rendering for ordinary application-bundle artwork so the switcher follows the system's icon/widget style, including automatic dark icons for VS Code. A DarkAqua drawing context alone did not apply this style.
- Preserve distinct runtime images and the Python/Matplotlib fallback. Coalesce native requests, bound the in-memory cache to 16 MiB/64 entries, expire it after five seconds of targeted reads, and reject stale appearance generations. A failed/timed-out renderer retains the original valid image.
- Keep icon rendering outside keyboard handling. No permanent icon polling, screenshot feed, private icon API or new permission is used.

## 0.4.22 — bounded background work and targeted window updates

- Cancel queued visibility-only icon work before decoding after the panel closes; retain required launch/appearance refreshes and stale-result rejection.
- Cache positive native Matplotlib resource discovery by process launch identity, bounded in memory; retry missing or invalid resources and preserve adaptive rendering.
- Discover yellow-button regions in the background. Ordinary clicks in known window content bypass AX and WindowServer queries; uncertain controls/windows retain the original validated hit test. Suspend the mouse tap when disabled, after completing an already-owned gesture.
- Coalesce window events by affected app/window. Moves/resizes refresh geometry without enumerating app windows; app discovery preserves unrelated/partial cached results. App mode avoids unused window-title reads and subscriptions.
- Skip unchanged app-order preference writes and omit transient PID identifiers from durable recency. Prune unused badge lookup entries and move detailed success traces to debug logging.
- Use one public focus fallback when a present private bridge rejects an action, within the same cancellable intent; never retry a successfully sent action after unconfirmed readback.
- Restore portable validation notes and the source export. Add read-only export validation and a complete non-visible `scripts/check.sh --all` command.

## 0.4.21

- Refresh public app artwork by appearance/events and while its cells are on screen; prioritize selection, coalesce background reads and skip redraws for unchanged pixels. Preserve process/revision rejection and Python/Matplotlib fallback.
- Document the distinction between public application artwork, custom Dock drawing and separately exposed badges; do not fabricate dynamic Dock or CPU content.
- Package native Finder/Spotlight light/dark logo variants through macOS-only Xcode asset compilation, retaining the exact current arrows/palettes, adaptive About artwork and menu template.
- Close Settings/Guide/About with local Command-W using AppKit's standard close-button action, without quitting the service.

## 0.4.20

- Restore unmodified AppKit buttons, popup arrows and window background, matching ScreenTextOCR's native Settings construction. Remove the custom gray bezels introduced in 0.4.19.
- Correct the executable's SDK metadata while retaining macOS 14 as the deployment target, so macOS selects current AppKit appearance. Verify the linked SDK and minimum OS before signing.

## 0.4.19

- Lighten the Settings window background in dark appearance and use deeper neutral gray action buttons and glass selector, retaining native AppKit layout and interactions in the style of ScreenTextOCR.

## 0.4.18

- Add Quit ClearCommandTab at the bottom of Settings, sharing the window's Command-Q termination action across Settings, Guide and About.
- Load About artwork directly from bundled icon resources so a cached system application icon cannot retain the old blue logo.

## 0.4.17

- Use black arrows on a white tile in light About and Finder; use white arrows on a black tile in dark About.
- Match the menu-bar arrows to the app logo while retaining automatic macOS tinting and existing status indicators.

## 0.4.16

- Refresh cached app icons automatically when the effective appearance changes, render using that appearance and discard loads started under an older theme.
- Resolve an app's actual focused/main window before consulting cached history or activating it, so a stale browser-window entry cannot override the app's last selected window.
- Confirm the resolved window as well as the application after ordinary app switching.

## 0.4.15

- Use Status: Active / Inactive in Settings while retaining separate permission and failure details.
- Shorten the menu entries to About and Guide; use Guide consistently for the help page.
- Explain the yellow button's normal window minimization, optional app-wide Hide and native Command-click / Option-click behavior.
- Link About to the public CorbeusUltra/clear-command-tab GitHub repository.

## 0.4.14

- Restore ordinary native menu-bar clicks: clicking the icon opens the menu instead of pausing the service.
- Add Pause / Resume to the menu while retaining the Settings control and dimmed paused icon.
- Add direct About and Help actions. Help opens the existing Guide; Settings always opens its own tab. Page and pause actions wait for native menu tracking to finish.

## 0.4.13

- Remove a terminated application directly from switching history and cached presentation, even when the macOS running-app snapshot is stale. Ignore late activation notifications for the same terminated instance.
- Check cached process liveness before opening/committing a selection and while a selection is held, so a missed termination event cannot leave a dead destination indefinitely.
- Recover a silently disabled keyboard event tap without requiring another app activation. Cancel stale selection state on recovery and keep Pause/Stop authoritative.
- Add hidden lifecycle and native event-tap recovery checks; no input injection or new permission is required.

## Earlier preparation

- Adopt `io.github.corbeusultra.ClearCommandTab` as bundle/runtime identity; preserve existing preferences through a private local migration. macOS permissions may require renewed approval.

- Park Option-Tab window switching; keep its implementation and checks while advertising only the two app shortcuts.
- Credit OpenAI Codex assistance in the README.

- Portable build and signing configuration; safe staged installation of a prepared bundle.
- Provenance audit, third-party notices, and curated source export without local history. Adopt GPL-3.0-only for compatibility with the referenced AltTab adaptations; retain upstream notices.
- Integration checks for actual AppKit controls, installer failure recovery, and opt-in fixture-window focus scenarios.
- Avoid redundant cell content/layout updates during cached panel navigation, with measured before/after results.

## 0.4.12

- Native Settings, Guide and About tabs; theme-adaptive Matte appearance alongside existing glass profiles.
- Explicit Accessibility check with readable status and conditional Grant action; separate interception errors.
- Optional yellow-button Hide with a native drawn illustration immediately after its label.
- Separate version/build labels, author profile link, optional repository metadata, and selected dark artwork.

Earlier development snapshots are present in the public Git history. Machine-specific backups are not part of the curated source export.

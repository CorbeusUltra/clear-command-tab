> **Heads-up : this was vibe-coded.** Every line in this repo was written in an extended conversation with AI. No human reviewed each commit for correctness line-by-line. Treat it as a hobby-grade tool that happens to work, not as battle-tested software. Contributions, bug reports, and "actually this is wrong" corrections are all very welcome.


# ClearCmdTab

A native macOS app switcher with two shortcuts:

| Shortcut 	     |     | Destinations                                          |
| ------------------ | --- | ---                                                   |
| Command-Tab        | ⌘   + ⇆  | Visible apps, including minimized and windowless apps |
| Command-Option-Tab | ⌘⌥ + ⇆ | Hidden apps; reveal the selected app                  |

Hold the opening modifier to browse, add Shift to go backward, and release it to switch. A quick tap switches immediately; the panel appears after 150 ms when held. Arrow keys navigate and Escape cancels. Command-Tab excludes apps hidden with Hide / Command-H.

Terminated apps are removed directly on the macOS termination event. A cheap process-liveness backstop covers delayed or missing events without reading icons or enumerating windows in the shortcut callback. If macOS disables the keyboard event tap silently, a one-second health check attempts recovery while switching is enabled. Pause and Quit stop that check; Secure Input is still respected.

**Licence: [GPL-3.0-only](LICENSE).** Commercial use, modification and redistribution are allowed under GPLv3; distributing a covered binary requires corresponding source under its terms. This choice preserves compatibility with the referenced AltTab adaptations. See [licensing](docs/LICENSING.md), [provenance](docs/PROVENANCE.md) and [third-party notices](THIRD_PARTY_NOTICES.md). This folder is not a notarized release.

## Requirements

- macOS 14 or later to run. Liquid Glass requires macOS 26 or later; older systems use the fallback material.
- Swift 6 tools and a macOS 26 SDK or newer to compile (`NSGlassEffectView` is referenced at build time). The native application logo additionally requires Xcode's existing macOS asset tools (`actool`). No iOS/Simulator component installation is required; `CCT_ASSET_DEVELOPER_DIR` can select asset tools without changing the selected Swift toolchain.
- Python 3 for installer checks and optional integration tooling. No external Swift packages or downloaded binary dependencies.
- A logged-in macOS display session for AppKit checks and benchmarks.

## Build and install

From the project directory:

```sh
zsh scripts/check.sh --all
zsh scripts/build-app.sh
# Quit the currently running ClearCmdTab before installation.
zsh scripts/install-app.sh --no-build
open "$HOME/Applications/ClearCmdTab.app"
```

The build creates `.build/ClearCmdTab.app`. A fresh checkout explicitly uses ad hoc signing for local development. For updates that should retain Accessibility identity, use a stable local signing certificate: copy `config/build.env.example` to `.local/build.env` and configure `CCT_SIGNING_IDENTITY`. Personal configuration is ignored and excluded from source exports. A configured certificate failure stops the build; it never silently falls back to ad hoc signing. Signing alone does not notarize an app.

Use `scripts/build-app.sh` for the app bundle: it records and verifies the selected SDK independently of the macOS 14 deployment target. This avoids older compatibility styling caused by incorrect SDK metadata in some Swift Build versions. Settings uses standard AppKit window colors, rounded buttons and popup drawing, following the system appearance.

`--no-build` installs the already signed bundle without recompiling or requesting the signing key again. The installer verifies a staged copy before moving an existing installation to macOS Trash. It refuses a running app, an invalid signature, or a failed process check. On systems without `/usr/bin/trash`, an existing app must first be moved to Trash manually in Finder. A standalone `zsh scripts/install-app.sh` builds once and installs.

Optional environment settings: `CCT_INSTALL_DIR` changes the destination directory and `CCT_BUNDLE_PATH` changes the prepared bundle path. The bundle identifier is `io.github.corbeusultra.ClearCommandTab`, distinct from the display name. The public-name change preserves the existing bundle identity, saved preferences and stable signing requirement; it is not a new application identity. See [application identity](docs/APPLICATION_IDENTITY.md).

## First launch and permissions

Quit other switchers using the same shortcuts. Open ClearCmdTab once from Applications or Spotlight to show Settings. Accessibility is checked automatically; enable it through **Grant permission…** if needed. Returning from System Settings refreshes the current authorization without forgetting macOS's existing grant. **Check permission** remains available for a manual retry. Accessibility should show **Granted** and status **Active**. Paused or unavailable service shows **Status: Inactive**, with permission and interception failures reported separately. Login/service launches stay in the background.

No Screen Recording permission is requested. The app reads app/window metadata and icons, not window contents, and has no network client or typed-text logging. Accessibility necessarily permits broader system access; enable it only for a build you trust.

If permission stops working after changing signing identity, check that System Settings references the installed app. Re-add only that app if required. A terminal-launched diagnostic cannot prove that the GUI app has permission.

## Settings and everyday use

- **Settings** contains glass appearance, login launch, menu-bar visibility, optional yellow-button Hide, and status. **Guide** describes shortcuts. **About** shows author, version and build separately.
- **matte** uses opaque theme-adaptive colors with no glass or blur. The other glass profiles retain their existing rendering.
- **Yellow button hides app** changes a plain click on another app's yellow button from minimizing one window to the Dock into hiding all windows of that app, like Command-H. Command-click or Option-click keeps normal macOS behavior. Its yellow illustration is drawn with AppKit; it is decorative. Pause suspends switching and this optional behavior. Yellow-button regions are prepared from window events in the background, so ordinary clicks in known window content need no synchronous accessibility query. Unknown controls retain the validated public hit-test fallback.
- Click the menu-bar icon to open its native menu: **Pause / Resume**, **Settings…** (Command-,), **Guide**, **About**, and **Quit ClearCmdTab** (Command-Q). About and Guide open their pages directly. Pause / Resume remains available in Settings. The icon dims while paused. Reopening the app opens Settings even when its icon is hidden. Command-W closes Settings, Guide or About through the native close-button action and keeps the service running. Command-Q quits while a settings tab is active.
- macOS may separately restrict menu-bar visibility. Use **Menu Bar Settings…** to inspect the system setting; the app cannot read or override that permission.
- Quit from the bottom of Settings or press Command-Q in Settings, Guide or About.
- About uses AppKit’s public `NSApp.applicationIconImage`, preserving the system-rendered image and native icon-style choices. The bundled light-gray (`#F7F7F7`) and charcoal (`#1F1F1F`) images are fallback resources only if the system image is unavailable. Finder/Spotlight use native variants from `AppIcon.icon`, compiled into `Assets.car`, with the legacy ICNS as fallback. The menu retains its template arrows and macOS tinting. The arrow paths and palettes are shared with the current artwork. See [selected artwork and construction](Design/SelectedLogo/README.md).

About links to the [GitHub repository](https://github.com/CorbeusUltra/clear-command-tab), configured through `GitHubRepositoryURL` in `Resources/Info.plist`. An empty value displays **GitHub repository — Coming soon**; a valid HTTPS URL enables the link. Version and Build come from the bundle. Build distinguishes constructions of the same version.

## Development and verification

Third-party application artwork is separate from ClearCmdTab's own logo build. Cached images follow appearance changes; while the switcher is visible, the selected app and one other on-screen app refresh every 500 ms. Unchanged pixels do not redraw the panel. Closing cancels queued visibility-only decoding and stops its timer; required launch/appearance work remains valid. Positive native Matplotlib resource discovery is cached only in memory by process launch identity. Public application images do not promise another process's custom Dock view or CPU graph. Existing Dock badge reading remains separate. See [API boundaries and icon tests](docs/APPLICATION_ICONS.md).

See [testing](docs/TESTING.md), [measured performance](docs/PERFORMANCE.md), [validation](VALIDATION.md), and [change history](CHANGELOG.md). Private focus/rendering APIs are guarded and may change with macOS; unsupported capabilities retain fallbacks. Fullscreen, Spaces, multiple displays, Secure Input, and login behavior require live checks on the target OS.

Window-only switching is currently parked; its implementation is retained for later work. See [parked features](docs/PARKED_FEATURES.md).

Create a curated source copy, without Git history, local settings, builds or abandoned designs:

```sh
python3 scripts/export-source.py .dist/ClearCommandTab-source
```

`python3 scripts/export-source.py --check` validates the source selection without creating a copy. The exporter refuses an existing destination and writes a SHA-256 manifest. It includes LICENSE and third-party notices. It does not initialize Git, publish, or push. This optional export is not needed to update the existing public repository. See [publication privacy and file selection](docs/PUBLISHING.md) before committing or pushing changes.

## Public name and identity

The installed application and executable are named **ClearCmdTab**. The source folder,
Swift module names, existing GitHub URL and bundle identifier
`io.github.corbeusultra.ClearCommandTab` remain unchanged. Keeping the identifier and
stable signing requirement preserves the existing preference/permission identity.
The installer migrates `ClearCommandTab.app` to `ClearCmdTab.app` while preserving
its root directory for existing login references; it refuses conflicting installed names.
Internal system records may still show the historical identifier, and Spotlight may
need time to update its index. About uses `Version x.y.z (build)`, an ordered short
description, the existing author link and the configured GitHub repository link.

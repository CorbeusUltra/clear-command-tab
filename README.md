# ClearCommandTab

A native macOS app switcher with two shortcuts:

| Shortcut 	     |     | Destinations                                          |
| ------------------ | --- | ---                                                   |
| Command-Tab        | ⌘   + ⇆  | Visible apps, including minimized and windowless apps |
| Command-Option-Tab | ⌘⌥ + ⇆ | Hidden apps; reveal the selected app                  |

Hold the opening modifier to browse, add Shift to go backward, and release it to switch. A quick tap switches immediately; the panel appears after 150 ms when held. Arrow keys navigate and Escape cancels. Command-Tab excludes apps hidden with Hide / Command-H.

**Licence: [GPL-3.0-only](LICENSE).** Commercial use, modification and redistribution are allowed under GPLv3; distributing a covered binary requires corresponding source under its terms. This choice preserves compatibility with the referenced AltTab adaptations. See [licensing](docs/LICENSING.md), [provenance](docs/PROVENANCE.md) and [third-party notices](THIRD_PARTY_NOTICES.md). This folder is not a notarized release.

## Requirements

- macOS 14 or later to run. Liquid Glass requires macOS 26 or later; older systems use the fallback material.
- Swift 6 tools and a macOS 26 SDK or newer to compile (`NSGlassEffectView` is referenced at build time). Xcode or compatible Command Line Tools must be selected with `xcode-select`.
- Python 3 for installer checks and optional integration tooling. No external Swift packages or downloaded binary dependencies.
- A logged-in macOS display session for AppKit checks and benchmarks.

## Build and install

From the project directory:

```sh
zsh scripts/check.sh
zsh scripts/build-app.sh
# Quit the currently running ClearCommandTab before installation.
zsh scripts/install-app.sh --no-build
open "$HOME/Applications/ClearCommandTab.app"
```

The build creates `.build/ClearCommandTab.app`. A fresh checkout explicitly uses ad hoc signing for local development. For updates that should retain Accessibility identity, use a stable local signing certificate: copy `config/build.env.example` to `.local/build.env` and configure `CCT_SIGNING_IDENTITY`. Personal configuration is ignored and excluded from source exports. A configured certificate failure stops the build; it never silently falls back to ad hoc signing. Signing alone does not notarize an app.

`--no-build` installs the already signed bundle without recompiling or requesting the signing key again. The installer verifies a staged copy before moving an existing installation to macOS Trash. It refuses a running app, an invalid signature, or a failed process check. On systems without `/usr/bin/trash`, an existing app must first be moved to Trash manually in Finder. A standalone `zsh scripts/install-app.sh` builds once and installs.

Optional environment settings: `CCT_INSTALL_DIR` changes the destination directory and `CCT_BUNDLE_PATH` changes the prepared bundle path. The bundle identifier is `io.github.corbeusultra.ClearCommandTab`, distinct from the display name. The local pre-publication update preserves saved preferences; macOS may require fresh Accessibility approval after this identity change. See [application identity](docs/APPLICATION_IDENTITY.md).

## First launch and permissions

Quit other switchers using the same shortcuts. Open ClearCommandTab, choose **Check permission**, and enable Accessibility through **Grant permission…** if needed. Return to the app and check again. Accessibility should show **Granted** and shortcuts **Active**. Permission and interception failures are reported separately, including while paused. The initial **Not checked** state deliberately hides the Grant action.

No Screen Recording permission is requested. The app reads app/window metadata and icons, not window contents, and has no network client or typed-text logging. Accessibility necessarily permits broader system access; enable it only for a build you trust.

If permission stops working after changing signing identity, check that System Settings references the installed app. Re-add only that app if required. A terminal-launched diagnostic cannot prove that the GUI app has permission.

## Settings and everyday use

- **Settings** contains glass appearance, login launch, menu-bar visibility, optional yellow-button Hide, and status. **Guide** describes shortcuts. **About** shows author, version and build separately.
- **Matte** uses opaque theme-adaptive colors with no glass or blur. The other glass profiles retain their existing rendering.
- **Yellow button hides app** changes a plain click on another app's yellow button into Hide for the entire app. Modified clicks keep macOS behavior. Its yellow illustration is drawn with AppKit; it is decorative. Pause suspends switching and this optional behavior.
- Left-click the menu-bar icon to pause/resume. Right-click or Control-click for Settings and Quit. Reopening the app opens Settings even when its icon is hidden. Command-Q quits while a settings tab is active.
- macOS may separately restrict menu-bar visibility. Use **Menu Bar Settings…** to inspect the system setting; the app cannot read or override that permission.
- About follows light/dark appearance. The dark artwork uses black arrows on deeper blue; the Finder icon stays original. See [selected artwork and construction](Design/SelectedLogo/README.md).

`GitHubRepositoryURL` in `Resources/Info.plist` is optional. An empty value displays **GitHub repository — Coming soon**; a valid HTTPS URL enables the link. Version and Build come from the bundle. Build distinguishes constructions of the same version.

## Development and verification

See [testing](docs/TESTING.md), [measured performance](docs/PERFORMANCE.md), [validation](VALIDATION.md), and [change history](CHANGELOG.md). Private focus/rendering APIs are guarded and may change with macOS; unsupported capabilities retain fallbacks. Fullscreen, Spaces, multiple displays, Secure Input, and login behavior require live checks on the target OS.

Window-only switching is currently parked; its implementation is retained for later work. See [parked features](docs/PARKED_FEATURES.md).

Create a curated source copy, without Git history, local settings, builds or abandoned designs:

```sh
python3 scripts/export-source.py .dist/ClearCommandTab-source
```

The exporter refuses an existing destination and writes a SHA-256 manifest. It includes LICENSE and third-party notices. It does not initialize Git, publish, or push. Start the public repository from this export with a new history: the existing development history retains older local paths and author metadata. See [publication privacy and file selection](docs/PUBLISHING.md) before creating a public repository.

## Author

Created and maintained by CorbeusUltra with the help of OpenAI Codex.
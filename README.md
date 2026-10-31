> **Heads-up : this was vibe-coded.** Every line in this repo was written in an extended conversation with AI. No human reviewed each commit for correctness line-by-line. Treat it as a hobby-grade tool that happens to work, not as battle-tested software. Contributions, bug reports, and "actually this is wrong" corrections are all very welcome.

# ClearCmdTab

A native macOS app switcher for visible and hidden applications.

| Shortcut | Switch between |
| --- | --- |
| Command-Tab `⌘ + ⇆` | Visible apps, including minimized and windowless apps |
| Command-Option-Tab `⌘⌥ + ⇆` | Hidden apps (reveal the selected app) |

Hold the opening modifier to browse, add Shift to go backward, and release it to switch. A quick tap switches immediately; holding shows the panel after 150 ms. Use the arrow keys to navigate or Escape to cancel. Command-Tab excludes apps hidden with Hide / Command-H `⌘ + H`.

## Requirements

- macOS 14 or later; Liquid Glass requires macOS 26 or later.
- To build: Swift 6 tools, a macOS 26 SDK or newer, and Xcode's macOS asset tools. Python 3 is needed for checks.

## Build and install

From the project directory:

```sh
zsh scripts/check.sh --all
zsh scripts/build-app.sh
# Quit the currently running ClearCmdTab before installation.
zsh scripts/install-app.sh --no-build
open "$HOME/Applications/ClearCmdTab.app"
```

A fresh checkout uses ad hoc signing for local development. For stable Accessibility identity across updates, configure a local signing certificate as described in [building and installation](docs/BUILDING.md). This is not a notarized release.

## First launch and permissions

Quit other switchers using the same shortcuts. Open ClearCmdTab from Applications or Spotlight, then use **Grant permission…** if Accessibility access is needed. Settings should show **Accessibility: Granted** and **Status: Active**. Use **Check permission** to retry if needed.

The app does not request Screen Recording permission. It reads app/window metadata and icons, not window contents, and has no network client or typed-text logging. Accessibility grants broad system access, so enable it only for a build you trust.

## Settings

Choose a glass appearance, launch at login and menu-bar visibility in Settings. You can optionally make a plain click on another app's yellow button hide that app instead of minimizing its window. The menu bar provides Pause / Resume, Settings, Guide, About and Quit. See the [usage guide](docs/USAGE.md) for details.

## Documentation

- [Building and installation](docs/BUILDING.md), [usage](docs/USAGE.md) and [testing](docs/TESTING.md)
- [Application icons](docs/APPLICATION_ICONS.md), [performance](docs/PERFORMANCE.md) and [parked features](docs/PARKED_FEATURES.md)
- [Change history](CHANGELOG.md), [validation](VALIDATION.md) and [publication and privacy](docs/PUBLISHING.md)

ClearCmdTab uses guarded private focus/rendering APIs that may change with macOS. Fullscreen, Spaces, multiple displays, Secure Input and login behavior require live checks on the target OS.

## Licence

[GPL-3.0-only](LICENSE). See [licensing](docs/LICENSING.md), [provenance](docs/PROVENANCE.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

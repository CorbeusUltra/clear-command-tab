# Building and installation

Building requires Swift 6 tools, a macOS 26 SDK or newer and Xcode's macOS asset tools (`actool`); iOS and Simulator components are not required. `CCT_ASSET_DEVELOPER_DIR` can select asset tools without changing the selected Swift toolchain. Python 3 is required for installer checks and optional integration tooling. AppKit checks and benchmarks need a logged-in macOS display session. There are no external Swift packages or downloaded binary dependencies.

Run the non-visible checks with `zsh scripts/check.sh --all`; see [testing](TESTING.md) for their coverage and live-check limitations.

Use `zsh scripts/build-app.sh` to create `.build/ClearCmdTab.app`. The script records and verifies the selected SDK separately from the macOS 14 deployment target, avoiding older compatibility styling from incorrect SDK metadata. A fresh checkout uses ad hoc signing. To preserve Accessibility identity across updates, copy `config/build.env.example` to `.local/build.env` and configure a stable `CCT_SIGNING_IDENTITY`. That personal configuration is ignored and excluded from source exports. A configured certificate failure stops the build instead of falling back to ad hoc signing. Signing alone does not notarize the app.

Quit the running application before running `zsh scripts/install-app.sh --no-build`. The installer verifies a staged copy and refuses a running app, invalid signature or failed process check. It moves an existing installation to macOS Trash; if `/usr/bin/trash` is unavailable, move the existing app to Trash manually in Finder first. `--no-build` installs the prepared signed bundle without compiling or requesting the signing key again. Running `zsh scripts/install-app.sh` without that option builds once and installs.

`CCT_INSTALL_DIR` changes the destination directory and `CCT_BUNDLE_PATH` changes the prepared bundle path. The installer migrates `ClearCommandTab.app` to `ClearCmdTab.app` while preserving its root for login references; it refuses conflicting installed names. The source folder, Swift module names and bundle identifier remain unchanged. See [application identity](APPLICATION_IDENTITY.md).

If Accessibility stops working after a signing identity change, check that System Settings references the installed app and re-add only that app if needed. A terminal-launched diagnostic cannot establish that the GUI app has permission.

About uses the system application image, with bundled light/dark resources as a fallback. See [selected artwork](../Design/SelectedLogo/README.md) and [application icons](APPLICATION_ICONS.md). About's repository link is configured by `GitHubRepositoryURL` in `Resources/Info.plist`; an empty value displays a coming-soon label. Version and build are read from bundle metadata.

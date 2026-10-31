# Code and asset provenance audit

Audit date: 2026-10-17. This is a technical provenance review. Following the author's delegated decision on the same date, **the project is licensed GPL-3.0-only** to preserve compatibility with the referenced AltTab adaptations. See [the licensing decision](LICENSING.md) and [LICENSE](../LICENSE). The evidence below does not establish that the complete application could instead be offered under MIT.

## Findings

| Area | Evidence and source | Assessment |
| --- | --- | --- |
| Native focus bridge and key-window event record | `FocusCoordinator.swift`, `ClearCommandTabCore/FocusIntent.swift`; local development notes explicitly reference AltTab's focus protocol | Potential adaptation covered conservatively by the GPLv3 project choice; new names or additional guards do not remove upstream obligations |
| Original glass profile | `GlassProfile.swift`; guarded `set_variant:` invocation with value 3; local notes and source explicitly cite AltTab | Same historical provenance limit, with GPLv3 compatibility retained; the public clear and Matte paths are separate implementations |
| Status menu / toolbar structure | Development notes reference KeepingYouAwake; current Swift/AppKit implementation was compared with its Objective-C menu and settings controllers | Design/API reference; no wholesale file import found. Include the MIT attribution conservatively |
| Matplotlib icon fallback | `ApplicationIcon.swift` discovers a loaded backend and reads artwork from the user's own installed package at runtime | No Matplotlib source, artwork, or binary is bundled. Runtime artwork remains owned by the package; this does not grant redistribution rights to screenshots or repackaged icons |
| App logos, dark variant, yellow illustration | Original normalized `NSBezierPath` drawing code in the repository | Locally authored code-native artwork. No downloaded bitmap, external icon pack, or raster image generator used |
| App icons / menu symbols | Running applications' runtime artwork and system-supplied SF Symbols | Not bundled as third-party assets; system frameworks/font files are not redistributed |
| Package / tests / scripts | No remote SwiftPM dependencies or third-party binary frameworks | Audit found no vendored dependency tree or embedded signing key. API use alone is not proof of copied expression, but absence of a dependency does not clear adapted code |

## Pinned upstream references

References were downloaded and inspected at these exact revisions. They document the audit inputs, not the unknown exact revision consulted during early development.

- AltTab, GPL-3.0: revision [`ab1bda4769d3ada5f20b3a4b6c304b975fcf61da`](https://github.com/lwouis/alt-tab-macos/tree/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da).
  [Licence](https://github.com/lwouis/alt-tab-macos/blob/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da/LICENCE.md),
  [native event protocol](https://github.com/lwouis/alt-tab-macos/blob/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da/src/macos/api-wrappers/SkyLight.framework.swift),
  [glass variant](https://github.com/lwouis/alt-tab-macos/blob/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da/src/switcher/main-window/TilesPanelBackgroundView.swift),
  [focus behaviour](https://github.com/lwouis/alt-tab-macos/blob/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da/src/switcher/state/Window.swift).
- KeepingYouAwake, MIT: revision [`2be93dd7f390b23fbca934ff3b1ac03468a80077`](https://github.com/newmarcel/KeepingYouAwake/tree/2be93dd7f390b23fbca934ff3b1ac03468a80077).
  [Licence](https://github.com/newmarcel/KeepingYouAwake/blob/2be93dd7f390b23fbca934ff3b1ac03468a80077/LICENSE),
  [settings controller](https://github.com/newmarcel/KeepingYouAwake/blob/2be93dd7f390b23fbca934ff3b1ac03468a80077/KeepingYouAwake/Settings/KYASettingsWindow/KYASettingsWindow.m).
- [Matplotlib licence](https://github.com/matplotlib/matplotlib/blob/main/LICENSE/LICENSE): runtime-only package/artwork lookup, no redistributed copy.

Upstream licence texts are retained under `docs/licenses/` for reference and attribution. Those upstream texts retain their original scope; the root LICENSE and licensing notice state the project terms.

## GPLv3 decision and limits on permissive relicensing

The local Git history imports earlier source snapshots rather than preserving every original development step. It cannot establish a complete clean-room origin for the explicitly adapted focus/glass portions. Comparing current files with upstream confirms shared protocols/constants and referenced techniques, but a similarity scan cannot decide copyright or derivative-work status.

Attribution alone is not a substitute for licence compatibility. Before adopting MIT for the complete application, establish that the relevant implementation is independently authored and legally separable, obtain appropriate permission from the relevant rights holders, or resolve the affected implementation's licensing another way. A mechanical rewrite is not evidence of independence. Preserving the current behaviour and appearance takes precedence over silently replacing these parts during this preparation task.

The root `LICENSE` contains the unmodified GPLv3 text; the project declaration is `GPL-3.0-only`. This conservative choice addresses compatibility with the known GPL reference without inventing permission to relicense upstream material under MIT or future licence versions. The author has delegated this decision; no additional project restriction or dual-licensing claim is added.

## Local history and privacy

An optional curated source export excludes `.git`, personal build configuration, generated builds, and abandoned logo proposals. The existing repository and its older Git history are public; older commits contain machine-specific paths and author metadata. An export does not sanitize that already-published history. Some local notes remain outside the repository.

The author selected `io.github.corbeusultra.ClearCommandTab` as the bundle/runtime identity. Previous settings were migrated locally without keeping a personal legacy identifier in current runtime code; the earlier identifier remains in public history. This identity change may require fresh permission approval; see [application identity](APPLICATION_IDENTITY.md). The current identifier is not a signing credential or an absolute machine path.

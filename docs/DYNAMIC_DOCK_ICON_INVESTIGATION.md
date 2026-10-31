# Dynamic Dock artwork investigation

Date: 2026-10-24. Investigation only; no application code, preference, permission,
installed bundle or running service was changed.

## Finding

On this Mac, the native application switcher is implemented inside the Dock.
Its rendering code can use the Dock's own tile image directly, including a
replacement image. That is a different data source from the public
`NSRunningApplication.icon` consumed by ClearCommandTab and AltTab.

This explains how Apple's switcher can have access to custom Dock artwork without
requiring Icon Composer, or a public cross-process icon-image reader. It does not
prove the appearance of every tile in every native switcher presentation.

No supported public API for retrieving another application's complete custom
Dock drawing was identified. This is a scoped research result, not a proof that
no undocumented technique could ever work.

## Installed system evidence

Read-only disassembly of the arm64e slices of the installed Apple binaries on
macOS 27.0.1 (26A434):

| Binary | UUID |
| --- | --- |
| Activity Monitor | 34FB86D4-D941-3BA4-950A-F40F4286AC27 |
| Dock | 3BDF6A3B-866B-3C07-920C-E9E7FB57B56B |

### Activity Monitor publishes a custom view

- `SMCPUMonitor.preferencesChanged`, for mode 6, obtains
  `cpuHistoryDockIconHostWindow.contentView` and assigns it to `NSApp.dockTile.contentView`
  (assignment at unslid address `0x100003A50`).
- `SMCPUMonitor.loadStandardDock` assigns its CPU-usage window's content view to
  the application Dock tile (`0x10003D014`), then calls `display` (`0x10003D040`).
- `SMBase.updateDockIcon` reads `IconType`; for a nonzero mode it calls
  `NSApp.dockTile.display` (`0x1000029DC`).
- The existing saved preference was read, not changed: `IconType = 6`. This
  identifies the saved CPU-history branch; it is not a direct observation of the
  running view's state or of visible pixels.

The public [NSDockTile.contentView API](https://developer.apple.com/documentation/appkit/nsdocktile/contentview)
and installed SDK header describe an owner-supplied NSView whose drawing is
requested with `display`. The `owner` is an NSApplication or NSWindow in that
process. The property is not a remote-view lookup by PID.

### The native switcher reads Dock-internal tile contents

- `ASAppSwitcher.show:` looks up each process in the Dock's tile collection and
  calls `getImage:glassCompositingFilter:` (`0x100090BA8`), then adds that image to
  its icon list.
- `Tile.getImage:glassCompositingFilter:` delegates to its tile layer.
- `DOCKTileLayer.getImage:glassCompositingFilter:` returns the image layer's
  `contents` (`0x100087CAC`), along with its glass configuration.
- `DOCKProcessTile.dockExtraSetCustomIconImage:usesIconServices:withContext:`
  supplies a replacement image via
  `setReplacementExtraImage:usesIconServices:glassCompositingFilter:`
  (`0x10004AFCC`).
- The tile image update path calls `imageChanged:forProcess:` on the internal
  switcher. `ASAppSwitcher.imageChanged:forProcess:` updates the displayed entry
  with `setImage:atIndex:` (`0x100091608`).

These methods belong to objects inside the Dock executable. Merely knowing their
names does not expose the Dock's objects to another process. No injection,
debugger attachment or private function invocation was attempted.

## Live public-image measurements

The existing public-image diagnostic was run in two separate, fresh helper
processes against the already-running Activity Monitor (PID 39531). Each made
four reads with the main run loop allowed to advance between reads. The probe
also rendered explicit light and dark appearances using the existing icon code.

All eight unqualified public-image reads returned the same bitmap SHA-256:

`ae0c0b80cf0a560c66659886d8e442f9b16f8b09a98da4c560884248d231001f`

Each appearance also remained stable across these samples. Starting a second
reader discards the first reader's process-local image state: this is evidence
against a stale image held only in ClearCommandTab's cache. It does not eliminate
system-side caching, prove the CPU graph was visibly changing, or establish that
CPU usage was constant. No Dock or screen pixels were captured.

A separate final comparison rendered the public process image and the app
bundle's file icon at the same size/appearance. They were byte-identical. The
saved PNG was inspected: it is the standard Activity Monitor logo, not a sampled
CPU-history graph. This identifies the image returned in that comparison; it
still does not observe the Dock's actual current drawing.

A separate bounded Accessibility probe checked its own existing trust without
requesting access. It was not trusted, so it skipped the Dock traversal. No
claim about live Dock attribute availability follows from this skipped probe;
it says nothing about the installed ClearCommandTab GUI's permission.

## Other API/source checks

- The installed public SDK documents `NSRunningApplication.icon` as the app's
  icon; unlike `finishedLaunching`, it does not document KVO change observation.
- The public `NSDockTile` interface supplies an owner's view, badge label and
  display action, not a cross-process image getter.
- HIServices' exported symbol list contains private `CoreDock` image setters,
  context/window functions and rendering functions. Exported symbols alone do
  not establish supported signatures, pixel-read semantics, permissions or a
  safe general reader. None was called.
- AltTab's `Application.fetchAppIcon` calls `runningApplication.icon`, followed
  by rasterization. It does not implement a special custom-Dock-image reader in
  that path. Source tree revision inspected:
  `c500294bdb01186011a5c64a412b04cef9931bef`.
  [Source](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/state/Application.swift).
- Icon Composer / `.icon` / `actool` / `Assets.car` author an application's own
  packaged artwork. They provide no extra authority to read another process's
  custom Dock rendering.

## Consequences and outstanding checks

The current general public-icon fallback is appropriate when custom pixels are
not published. More polling or refreshing every keyboard event cannot create
information absent from the public image result. No Activity Monitor-specific
graph or CPU data should be synthesized.

The user subsequently confirmed that the CPU graph is visible in the native
Apple switcher with ClearCommandTab paused. This establishes the reported visual
gap by user observation, independently of the tool's public-image measurements.
The internal Dock implementation explains access, but does not supply a reusable
public API.

A separate exploration of undocumented Dock communication might find a usable
reader, but none has been demonstrated here. Screen cropping/continuous capture
does not meet the existing requirements and was not used. There is no production
feature to install from this investigation, and no rebuild/relaunch was needed.

Local evidence (ignored build artifacts): `.build/DynamicDockInvestigation/`.
It contains method excerpts, disassemblies, upstream source snapshots, two public
image reports, the skipped Accessibility report and a machine-readable summary.

## Private reader feasibility follow-up

The user explicitly requested a feasibility study after confirming the native
switcher's graph. The follow-up examined the installed implementation, not just
symbol names or old online declarations. No candidate image API was invoked.

### Examined routes

| Route | Verified evidence | Feasibility conclusion |
| --- | --- | --- |
| `CoreDockGetProcessWindow` | Its entire current function is four instructions: write zero to the output, return `-50` (`paramErr`). | Not a window/image reader on this build. |
| `CoreDockGetProcessContext` | Returns a cached local context; if absent, calls `_createDockTileContext`. That helper allocates bitmap storage with `mmap` / `CGBitmapContextCreate` and installs a flush callback. AppKit's own `_getDockContext:andSize:` calls it to draw its content. No target PID is consumed in this path. | A producer-side drawing context, not a reader of a target app's existing tile. Merely calling it would not fetch Activity Monitor's image. |
| `CoreDockRenderWindowIntoContext` | Calls `SLSGetScreenRectForWindow`, `SLSCaptureWindowsContentsToRect` and `CGContextDrawImage`. | A window-capture path, not a capture-free icon source. No capture was attempted, and permissions/quality for this route were not tested. |
| `NSDockTile._tileImage` | Its implementation examines its local owner and selects `NSApplication._iconImage` or `NSWindow.miniwindowImage`. | Private, but still local to the owner. It does not offer remote lookup or retrieve the custom drawing displayed by a different process. |
| `Tile.getImage:glassCompositingFilter:` and `ASAppSwitcher` | These are objects/methods inside the Dock executable. They are not supplied as Dock objects in the helper's AppKit runtime. | A selector name does not confer cross-process object access. No independent reader demonstrated. |
| Dock connection / extra protocol | Inspected AppKit's `NSDockConnection` method inventory and the Dock's `DockExtraServer` methods/message strings. The extra path includes setup, menu commands, scale/appearance messages and incoming custom-image updates; the image is retained inside the Dock. | No observer/subscription/image-copy service available to an independent app was identified in these paths. This is not an exhaustive proof about every possible private IPC request. No XPC/Mach messages were sent to test guessed protocols. |
| WindowServer exports / surfaces | Parsed the export tries of this helper's loaded SkyLight (2,914 exports) and HIServices (624 exports). Reviewed Dock/icon/surface candidates; there are surface and capture APIs but no identified per-app custom-tile image getter. | No general direct reader demonstrated. A name-based export review cannot establish that no other undocumented technique exists. No foreign surface was accessed. |

The helper loaded libraries and read their own mapped executable code and
metadata. Calls through imported branches were identified by resolving their
local import slots; method selector stubs were decoded separately. This is not
remote-process memory access or attaching a debugger to the Dock. Instruction
dumps are bounded to the symbol being inspected, so adjacent functions are not
misattributed to a candidate merely because it has a promising name.

### Implementation and performance assessment

- **Direct independent reader:** not demonstrated. No implementation effort or
  latency estimate can honestly be given for a working bridge that has not been
  found. More refresh calls cannot fix the absence of accessible source pixels.
- **Capturing Dock/window output:** could obtain rendered pixels in principle,
  but would be a separate capture feature with permission, scaling, hidden-Dock,
  display/Space and image-to-app matching questions. No proof of acceptable
  fidelity or cost was obtained. It does not meet the existing capture-free goal.
- **Code executing inside the Dock:** could theoretically access its actual
  internal tile objects. That would require a separate injection/modification
  mechanism, not simply linking a private framework. SIP is enabled on this Mac;
  no injection or system-protection change was attempted. This study does not
  establish an exact set of privileges/protection changes required by a specific
  injection technique. Such an architecture would contradict the goal of a
  lightweight independent switcher and couple failures to a system process.
- **App-specific graph synthesis:** would not retrieve the app's actual drawing,
  would not generalize, and is outside the requested behavior.

Recommendation: retain the existing public icon path and fallback. Do not add a
production private-Dock bridge until an independent, reproducible pixel reader
has first been demonstrated. The current result is **no verified implementation
meeting all the constraints**, not a mathematical impossibility claim about
macOS. No production change or reinstall was needed for this study.

Follow-up evidence: `.build/DynamicDockFeasibility/summary.json`, bounded local
function dumps, resolved-call metadata, runtime class inventory and export lists.
Checks verified the evidence files and the four-instruction stub; no application
regression run or timing benchmark was needed/performed because application code
and behavior did not change.

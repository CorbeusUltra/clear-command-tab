# Application images, own artwork, and window closing

## 1. Third-party application images

`ApplicationIcon` reads the public [NSRunningApplication.icon](https://developer.apple.com/documentation/appkit/nsrunningapplication/icon), re-querying the process record on each background refresh. It resolves/rasterizes using the captured AppKit appearance. A copy with caching disabled prevents an unchanged NSImage identity from freezing a custom drawing representation. The original image and its optical margins are preserved. The enclosing app-bundle icon remains a fallback. With no valid artwork, the panel uses a generic application symbol rather than ClearCommandTab's own logo. The existing Python/Matplotlib fallback still requires a Python placeholder and an actually loaded native Matplotlib backend; it never guesses from an installed package.

Window appearance and the system's **Icon & widget style** are separate. On macOS 27.0.1, VS Code's public application/file NSImage still rasterized with a white background in a DarkAqua context while Finder displayed its dark variant. For ordinary bundle artwork, the production tracker now asynchronously requests a public [Quick Look icon representation](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator/request), with `iconMode=true` and representation type `.icon`. Quick Look supplies the selected system style; it does not read another app's Dock pixels. An image differing from the bundle's ordinary image bypasses this styling step, preserving custom runtime artwork and Matplotlib.

Native requests coalesce by bundle, pixel size, drawing appearance and source-pixel digest. The cache is memory-only, bounded to 16 MiB and 64 images, with a five-second lifetime. Expiry is checked only when an existing event or visible-cell refresh requests that app; it creates no new polling timer. Appearance changes invalidate both the tracker revision and native cache generation, so a late native result cannot populate the new generation. The system renderer has a two-second cancellation deadline and returns the valid base icon on failure. Pixel normalization/comparison remains on utility queues; keyboard handling never waits for Quick Look.

`ApplicationTracker` keeps the asynchronous utility queue, coalesced reads and last valid bitmap. An appearance revision, per-app launch invalidation and process identity reject late results. Pixel comparison runs on the utility queue; unchanged images do not trigger panel redraws. Launch, activation, bounded launch retries and effective-appearance events continue to refresh the cache. `finishedLaunching` KVO adds a targeted refresh; the SDK documents that property as observable, whereas `icon` has no documented change notification contract. No undocumented icon-change notification is assumed.

Actual panel presentation supplies only cell IDs intersecting the scroll viewport. It schedules one background refresh of that set. While visible, a common-mode 500 ms timer reads the selected app plus one other visible app in round-robin order. Navigation/newly visible cells get targeted asynchronous refreshes. A fast switch that never presents the panel does not start the timer. Closing, cancelling, pausing or quitting clears the visible set and stops it. Visibility-only queued loads are cancelled before decoding; required launch/appearance loads are preserved, including when coalesced behind a cancelled visible request. Positive Matplotlib resource URLs are cached in memory by PID and launch date, never as a frozen appearance image. Missing backends are retried; missing files invalidate a positive discovery. There is no idle all-app icon polling, screen capture, app whitelist, remote-process memory reading or CPU-data reconstruction.

### Public API boundary

These surfaces are distinct:

| Surface | What can be read here |
| --- | --- |
| Application icon | Artwork exposed by NSRunningApplication and the bundle/file icon API, under the selected drawing appearance |
| Runtime `NSImage` | Changes are reflected when the provider exposes them through that application-image API; a custom NSImage drawing representation is rerasterized |
| Dock `applicationIconImage` | An app can assign its own [NSApplication.applicationIconImage](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage); this does not establish a public cross-process live-image feed |
| Custom Dock view | [NSDockTile.contentView](https://developer.apple.com/documentation/appkit/nsdocktile/contentview) is an in-process NSView drawn explicitly by its owner. No public API here exports another process's rendered view |
| Badges | Existing Dock Accessibility `AXStatusLabel` reading, on its own queue and without fabrication. It is a label, not image pixels, a generic notification database or custom Dock content |

Activity Monitor is an example, not a special case in the implementation. Its Dock CPU graph is shown only if that content is exposed as the public application image. If the graph is retained in custom Dock drawing, the correct application logo remains visible. A static image returned by the API is not proof that the Dock is static or that CPU usage is zero. No CPU figures, badges or graph are invented. No additional permission is requested for these image reads.

The appearance tests use native AppKit drawing under light/dark/light contexts; tracker tests inject changing artwork from arbitrary existing process records. Separate native-style cache checks cover asynchronous coalescing, expiration, source changes, failures, invalidation and memory limits. A real system transition is required to validate automatic icon styles: changing only a helper's NSAppearance does not change the global icon/widget style. These tests do not establish universal publication of every app's custom Dock content.

## 2. ClearCommandTab's own logo

`Resources/AppIcon.icon` defines light-gray/charcoal backgrounds (0.97/0.12, matching ScreenshotOCR) and black/white arrows. `Assets/Arrows.png` is generated by `make-icon.swift --native-glyph` using the existing production `drawArrows` function, without tracing or changing either arrow. Glass, specular effects and translucency are disabled in the source document. Selected design PNGs and About ICNS resources use these same backgrounds. Arrow geometry and the menu template are unchanged.

`compile-icon.sh` uses the installed Xcode `actool` with `--platform macosx --target-device mac`, compiling `Assets.car`. `CFBundleIconName=AppIcon` declares native variants; `CFBundleIconFile` retains the legacy ICNS. About uses the public `NSApp.applicationIconImage` without rasterizing it, as ScreenshotOCR does; its native image representations remain under AppKit control. It rereads the image on presentation/appearance events, with no timer. Explicit light/dark ICNS files are a fallback only if the system image is unavailable. The system’s icon/widget style, not a forced window-theme bitmap, determines native appearance. The menu keeps its existing template PNG. Nothing in this compiler path affects third-party icons. No global `xcode-select`, mobile download, Finder restart or icon-cache reset is performed.

`python3 Tests/IconCatalogChecks/main.py [PREPARED_APP]` verifies the existing compiled catalog. `zsh scripts/check-icon-catalog.sh [PREPARED_APP]` also runs the macOS compiler first. Checks cover exact generated glyph bytes, the original palettes, compiled light/dark stacks, bundle declarations and optional packaged resources. Actual Finder/Spotlight style selection remains an OS/UI acceptance check.

## 3. Settings window close

Command-W is a local key equivalent on `SettingsAppWindow` and calls [NSWindow.performClose](https://developer.apple.com/documentation/appkit/nswindow/performclose(_:)), the standard red-button action. AppKit handles delegate approval, window closing and `windowWillClose`; the existing close callback cancels pending settings focus. The retained controller and accessory service stay alive. The global event tap does not claim Command-W, and Command-Q remains the separate Quit action.

Hidden AppKit fixtures cover Command-W independently on Settings, Guide and About, red-button callback parity and absence of a Quit request. Already-closed hidden windows do not produce repeated native close notifications; physical close/reopen interaction is a separate manual acceptance scenario.

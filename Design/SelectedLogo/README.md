# Selected light and dark logos

![Selected light and dark artwork](comparison.png)

The light variant is the original blue tile with white arrows. The dark variant keeps the exact same arrow geometry and rounded tile, with black arrows and a deeper blue gradient. The blue remains bright enough to distinguish the black strokes at About size.

The artwork is drawn directly by AppKit in `scripts/make-icon.swift`, with shared `NSBezierPath` geometry. Only the gradient and arrow color differ. No external artwork or generated raster imagery is used.

- `light/` and `dark/` contain transparent PNGs at 88, 176, 512 and 1024 pixels for About previews and future GitHub artwork.
- `comparison.png` shows the selected pair in their intended appearances.
- About follows the window's effective appearance, including changes while the window is open. If the dark resource is missing in a development run, it retains the original image.
- The app bundle contains `ClearCommandTab.icns` and `ClearCommandTab-dark.icns`. The standard Finder/app icon remains the original; About uses the dark resource in dark appearance. The menu-bar template symbol continues to use the tint supplied by macOS.

Regenerate assets or an individual icon:

```sh
swift scripts/make-icon.swift --selected-assets Design/SelectedLogo
swift scripts/make-icon.swift /tmp/ClearCommandTab.icns
swift scripts/make-icon.swift --dark /tmp/ClearCommandTab-dark.icns
```

The default production generator output remains byte-identical to the original light icon. `scripts/build-app.sh` packages both resources and signs the resulting bundle.

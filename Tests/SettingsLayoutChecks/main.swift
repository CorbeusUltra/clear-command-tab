import AppKit
import ClearCommandTabCore

// Three layers: pure status decisions, AppKit interactions/layout, optional render QA.
// No windows are ordered on screen and no real permission or input is changed.
var failures: [String] = []
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { failures.append(message) }
}

func checkStatusDecisions() {
    let unchecked = SettingsStatus(permissionChecked: false, accessibilityGranted: false, keyboardRunning: false, paused: false)
    check(unchecked.accessibility == .notChecked && !unchecked.showsGrantPermission,
          "A background check must not expose Grant permission before the user's check")
    let denied = SettingsStatus(permissionChecked: true, accessibilityGranted: false, keyboardRunning: false, paused: false)
    check(denied.accessibility == .notGranted && denied.showsGrantPermission, "A denied explicit check must offer Grant permission")
    let tapFailure = SettingsStatus(permissionChecked: true, accessibilityGranted: true, keyboardRunning: false, paused: false)
    check(tapFailure.accessibility == .granted && tapFailure.switching == .unavailable && !tapFailure.showsGrantPermission,
          "An event-tap failure must not be mistaken for denied Accessibility")
    let paused = SettingsStatus(permissionChecked: true, accessibilityGranted: false, keyboardRunning: false,
                                paused: true, detail: "Tap stopped", yellowButtonFailure: "Tap stopped")
    check(paused.accessibility == .notGranted && paused.switching == .paused && paused.showsGrantPermission,
          "Accessibility must still be checked while paused")
    check(paused.detail == nil && paused.yellowButtonFailure == nil, "Intentional pause must not report interception failures")
    let revoked = SettingsStatus(permissionChecked: true, accessibilityGranted: false, keyboardRunning: true, paused: false)
    check(revoked.switching == .permissionRequired, "Permission loss must override stale keyboard readiness")
    let preview = SettingsStatus(permissionChecked: true, accessibilityGranted: true, keyboardRunning: false, paused: false, preview: true)
    check(preview.accessibility == .notChecked && preview.switching == .preview && !preview.showsGrantPermission,
          "A preview must not claim or request actual permission")
}
checkStatusDecisions()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let info = (NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")) as? [String: Any]) ?? [:]
    check(info["CFBundleIdentifier"] as? String == ApplicationIdentity.bundleIdentifier,
          "Bundle metadata must match the identity used by relaunch notifications and runtime services")
    if let icon = NSImage(contentsOf: root.appendingPathComponent(".build/ClearCommandTab.app/Contents/Resources/ClearCommandTab.icns")) {
        app.applicationIconImage = icon
    }
    let logoDirectory = root.appendingPathComponent("Design/SelectedLogo")
    guard let darkArtwork = NSImage(contentsOf: logoDirectory.appendingPathComponent("dark/app-176.png")),
          let darkBitmap = NSBitmapImageRep(data: try! Data(contentsOf: logoDirectory.appendingPathComponent("dark/app-176.png"))),
          let lightBitmap = NSBitmapImageRep(data: try! Data(contentsOf: logoDirectory.appendingPathComponent("light/app-176.png"))) else {
        fatalError("Missing selected logo assets")
    }
    let darkArrow = darkBitmap.colorAt(x: 88, y: 63)!.usingColorSpace(.deviceRGB)!
    let lightArrow = lightBitmap.colorAt(x: 88, y: 63)!.usingColorSpace(.deviceRGB)!
    check(darkArrow.redComponent < 0.01 && darkArrow.greenComponent < 0.01 && darkArrow.blueComponent < 0.01,
          "The selected dark logo must have black arrows")
    check(lightArrow.redComponent > 0.99 && lightArrow.greenComponent > 0.99 && lightArrow.blueComponent > 0.99,
          "The original light logo must retain white arrows")
    let settings = SettingsWindow(info: info, darkIcon: darkArtwork)
    guard let window = settings.window, let tabs = window.contentViewController as? NSTabViewController else {
        fatalError("Missing Settings window/tabs")
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func control<T: NSView>(_ id: String, as type: T.Type) -> T {
        for item in tabs.tabViewItems {
            if let view = item.viewController?.view,
               let result = descendants(view).first(where: { $0.identifier?.rawValue == id }) as? T { return result }
        }
        fatalError("Missing control: \(id)")
    }
    let permission = control("accessibilityStatus", as: NSTextField.self)
    let grant = control("grantPermission", as: NSButton.self)
    let checkButton = control("checkPermission", as: NSButton.self)
    let glass = control("glassChoice", as: NSPopUpButton.self)
    let screen = NSRect(x: 0, y: 0, width: 1600, height: 1200)
    @MainActor func select(_ index: Int) -> CGFloat {
        tabs.selectedTabViewItemIndex = index
        settings.fitSelectedPage(visibleFrame: screen)
        return window.frame.height
    }
    @MainActor func update(checked: Bool = true, trusted: Bool = true, running: Bool = true,
                           paused: Bool = false, detail: String? = nil, yellow: String? = nil) {
        settings.update(status: SettingsStatus(permissionChecked: checked, accessibilityGranted: trusted,
            keyboardRunning: running, paused: paused, detail: detail, yellowButtonFailure: yellow),
            iconVisible: true, glassProfile: .matte, yellowButtonHidesApp: true)
        settings.fitSelectedPage(visibleFrame: screen)
    }

    // Real button -> callback -> typed state -> visible controls. No AX prompt.
    update(checked: false, trusted: false, running: false)
    check(permission.stringValue == "Not checked" && grant.isHidden, "Initially show Not checked without a Grant button")
    check(permission.textColor == .secondaryLabelColor, "Unchecked status must be neutral")
    var trusted = false
    var checkClicks = 0
    settings.onCheckPermission = {
        checkClicks += 1
        update(trusted: trusted, running: trusted)
    }
    checkButton.performClick(nil)
    check(checkClicks == 1 && permission.stringValue == "Not granted" && !grant.isHidden,
          "The actual Check button must reveal Grant only after a denied check")
    check(permission.textColor == .systemRed, "Denied permission must be red")
    let deniedHeight = select(0)
    trusted = true
    checkButton.performClick(nil)
    check(checkClicks == 2 && permission.stringValue == "Granted" && grant.isHidden, "Rechecking must clear a stale Grant action")
    check(permission.textColor == .systemGreen, "Granted permission must be green")
    update(running: false)
    check(permission.stringValue == "Granted" && grant.isHidden, "A keyboard failure must preserve the permission result")
    check(control("switchingStatus", as: NSTextField.self).textColor == .systemRed, "A keyboard failure must have a separate red status")
    update(trusted: false, running: false, paused: true)
    check(permission.stringValue == "Not granted" && !grant.isHidden, "Paused permission loss must update the UI")
    update()

    // Preference compatibility and selection callbacks with no writes to real user defaults.
    let preferences = UserDefaults(suiteName: "local.ClearCommandTab.Checks.\(UUID().uuidString)")!
    for (stored, expected) in [("current", GlassProfile.current), ("altTab", .altTab), ("matte", .matte)] {
        preferences.setVolatileDomain([GlassProfile.preferenceKey: stored], forName: UserDefaults.argumentDomain)
        check(GlassProfile.selected(in: preferences) == expected, "Stored profile \(stored) must remain compatible")
    }
    settings.onGlassProfile = { selected in
        preferences.setVolatileDomain([GlassProfile.preferenceKey: selected.rawValue], forName: UserDefaults.argumentDomain)
    }
    glass.selectItem(withTitle: "Matte")
    glass.sendAction(glass.action!, to: glass.target)
    check(GlassProfile.selected(in: preferences) == .matte && glass.titleOfSelectedItem == "Matte",
          "The actual popup must emit a restorable Matte preference")
    preferences.setVolatileDomain([GlassProfile.preferenceKey: "unknown"], forName: UserDefaults.argumentDomain)
    check(GlassProfile.selected(in: preferences) == .current, "Unknown stored profiles must keep the existing fallback")

    // Verify the actual surface tree, rather than only testing the enum's names.
    let matte = GlassProfile.matte.makeSurface(content: NSView())
    let matteSelection = GlassProfile.matte.makeSelection()
    check(!descendants(matte).contains { $0 is NSVisualEffectView } && !(matteSelection is NSVisualEffectView),
          "Matte background and selection must not contain a visual-effect view")
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        matte.appearance = NSAppearance(named: appearance)
        matteSelection.appearance = matte.appearance
        matte.effectiveAppearance.performAsCurrentDrawingAppearance { matte.updateLayer(); matteSelection.updateLayer() }
        check(matte.layer?.backgroundColor?.alpha == 1 && matteSelection.layer?.backgroundColor?.alpha == 1,
              "Matte surfaces must be fully opaque in \(appearance.rawValue)")
        check(matte.layer?.backgroundColor != matteSelection.layer?.backgroundColor,
              "Matte selection must remain distinguishable from its background in \(appearance.rawValue)")
    }
    check(GlassProfile.current.makeSelection() is NSVisualEffectView && GlassProfile.altTab.makeSelection() is NSVisualEffectView,
          "Existing glass selections must keep their native material")

    // Real content sizing, state transitions, and screen limits.
    let settingsHeight = select(0)
    _ = select(1)
    let guideLabels = descendants(tabs.tabViewItems[1].viewController!.view)
        .compactMap { ($0 as? NSTextField)?.stringValue }
    check(guideLabels.contains("⌘Tab") && guideLabels.contains("⌘⌥Tab") && !guideLabels.contains("⌥Tab"),
          "Guide must advertise the two app shortcuts without the parked window shortcut")
    let aboutHeight = select(2)
    check(aboutHeight < settingsHeight, "About must size to its shorter content")
    check(abs(window.contentView!.frame.width - 560) < 1, "The content width must stay 560")
    check(abs(deniedHeight - settingsHeight) < 1, "Showing Grant alongside Check must not add a redundant row")
    for _ in 0..<3 {
        let top = window.frame.maxY
        check(abs(select(0) - settingsHeight) < 1 && abs(select(2) - aboutHeight) < 1,
              "Tab switching must not accumulate height drift")
        check(abs(window.frame.maxY - top) < 1, "Resizing must preserve the top edge")
    }
    _ = select(0)
    let longMessage = Array(repeating: "An interception error must remain fully readable.", count: 12).joined(separator: "\n")
    update(detail: longMessage, yellow: "Mouse interception unavailable. Click Check permission to retry.")
    check(window.frame.height > settingsHeight, "Visible error text must increase the natural height")
    check(!control("yellowButtonStatus", as: NSTextField.self).isHidden, "Mouse failures must have their own visible row")
    let smallScreen = NSRect(x: 0, y: 0, width: 800, height: 260)
    settings.fitSelectedPage(visibleFrame: smallScreen)
    check(window.frame.height <= smallScreen.height, "A short screen must bound the frame")
    if let page = tabs.tabViewItems[0].viewController?.view as? NSScrollView {
        check(page.documentView!.frame.height > page.contentView.bounds.height && page.hasVerticalScroller,
              "Overflow must remain in a scrollable document")
    } else { failures.append("Missing Settings scroll view") }
    update()
    check(control("switchingDetail", as: NSTextField.self).isHidden && control("yellowButtonStatus", as: NSTextField.self).isHidden,
          "Recovery must remove stale error rows")
    let shifted = SettingsWindowFrame.fitting(NSRect(x: 1600, y: -100, width: 560, height: 800),
        documentHeight: 300, chromeHeight: 80, visibleFrame: NSRect(x: 100, y: 100, width: 900, height: 700))
    check(shifted.minX >= 100 && shifted.maxX <= 1000 && shifted.minY >= 100 && shifted.maxY <= 800,
          "Frame must stay inside a screen with a nonzero origin")

    // About uses metadata. An empty/invalid URL remains a noninteractive placeholder.
    _ = select(2)
    let aboutIcon = control("aboutIcon", as: NSImageView.self)
    window.appearance = NSAppearance(named: .aqua)
    let originalIcon = aboutIcon.image
    window.appearance = NSAppearance(named: .darkAqua)
    check(aboutIcon.image === darkArtwork, "About must switch to the black-arrow icon when its window becomes dark")
    window.appearance = NSAppearance(named: .aqua)
    check(aboutIcon.image === originalIcon, "About must restore the original icon when returning to light appearance")
    let fallbackIcon = AppearanceIconView(light: originalIcon!, dark: nil)
    fallbackIcon.appearance = NSAppearance(named: .darkAqua)
    check(fallbackIcon.image === originalIcon, "A missing dark resource must retain the original icon")
    check(control("repositoryPlaceholder", as: NSTextField.self).stringValue.contains("Coming soon"), "Unconfigured GitHub must be a text placeholder")
    let aboutLabels = descendants(tabs.tabViewItems[2].viewController!.view).compactMap { ($0 as? NSTextField)?.stringValue }
    check(aboutLabels.contains("Version \(info["CFBundleShortVersionString"] ?? "Development")") &&
          aboutLabels.contains("Build \(info["CFBundleVersion"] ?? "")"), "Version and build must be separate labels from bundle metadata")
    let linked = SettingsWindow(info: ["GitHubRepositoryURL": "https://github.com/example/clear-command-tab"])
    let linkedTabs = linked.window!.contentViewController as! NSTabViewController
    check(descendants(linkedTabs.tabViewItems[2].viewController!.view).contains {
        $0.identifier?.rawValue == "repositoryLink" && $0 is NSButton
    }, "Configured HTTPS repository metadata must enable a link")
    let invalid = SettingsWindow(info: ["GitHubRepositoryURL": "file:///tmp/repository"])
    let invalidTabs = invalid.window!.contentViewController as! NSTabViewController
    check(descendants(invalidTabs.tabViewItems[2].viewController!.view).contains {
        $0.identifier?.rawValue == "repositoryPlaceholder"
    }, "Invalid repository metadata must not become a clickable link")

    // Exercise material replacement on the real hidden panel, including its selection.
    let panel = SwitcherPanel()
    let items = (1...3).map { SwitcherItem(id: .application(Int32($0)), name: "Application \($0)", icon: nil) }
    if let display = NSScreen.main {
        check(panel.prepare(items: items, selected: items[1].id, screen: display), "Panel content must prepare without presentation")
        let originalSize = panel.frame.size
        for profile in [GlassProfile.matte, .current, .altTab, .matte] {
            panel.applyGlassProfile(profile)
            check(panel.prepare(items: items, selected: items[1].id, screen: display), "Material replacement must retain panel content")
            check(panel.frame.size == originalSize, "Material replacement must retain panel geometry")
            if profile == .matte {
                let views = descendants(panel.contentView!)
                check(!views.contains { $0 is NSVisualEffectView } && views.filter { $0 is MatteSurface }.count == 2,
                      "The real Matte panel must have solid background/selection and no effect views")
            }
        }
    } else { failures.append("No display available for hidden panel geometry checks") }
    check(!panel.isVisible && !panel.isKeyWindow, "Panel checks must not show or focus the switcher")

    // User-visible updates with stable IDs must survive the cached-navigation path.
    if let display = NSScreen.main {
        var edited = items
        edited[1] = SwitcherItem(id: items[1].id, name: "Renamed fixture", icon: nil,
            badge: "9", windowTitle: "Edited document")
        panel.prepare(items: edited, selected: edited[1].id, screen: display)
        let cells = descendants(panel.contentView!).filter { $0.accessibilityRole() == .button }
        check(cells.contains { $0.accessibilityLabel()?.contains("Renamed fixture: Edited document") == true &&
            String(describing: $0.accessibilityValue() ?? "").contains("Badge: 9") },
              "Renaming, editing a title and changing a badge must update the actual accessible destination")
        panel.prepare(items: edited, selected: edited[0].id, screen: display)
        check(cells.filter { String(describing: $0.accessibilityValue() ?? "").contains("Selected") }.count == 1,
              "Moving selection must leave exactly one accessible destination selected")
        let drawing = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawing.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        drawing.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let content = panel.contentView!
        func pixels() -> Data {
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        let before = pixels()
        edited[0] = SwitcherItem(id: edited[0].id, name: edited[0].name, icon: drawing.makeImage())
        panel.prepare(items: edited, selected: edited[0].id, screen: display)
        check(pixels() != before, "A new bitmap with otherwise identical content must update the rendered icon")
        panel.prepare(items: items, selected: items[1].id, screen: display)
    }

    if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--render-dir=") }) {
        let directory = URL(fileURLWithPath: String(argument.dropFirst("--render-dir=".count)))
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            window.appearance = app.appearance
            for (stateName, checked, allowed) in [("unchecked", false, false), ("denied", true, false), ("granted", true, true)] {
                update(checked: checked, trusted: allowed, running: allowed)
                _ = select(0)
                render(window, to: directory.appendingPathComponent("settings-\(name)-\(stateName).png"))
            }
            _ = select(1)
            render(window, to: directory.appendingPathComponent("guide-\(name).png"))
            _ = select(2)
            render(window, to: directory.appendingPathComponent("about-\(name).png"))
            panel.appearance = app.appearance
            panel.applyGlassProfile(.matte)
            if let display = NSScreen.main {
                panel.prepare(items: items, selected: items[1].id, screen: display)
                render(panel, to: directory.appendingPathComponent("matte-\(name).png"))
            }
        }
        print("Rendered hidden AppKit views to \(directory.path)")
    }
    check(!window.isVisible && !linked.window!.isVisible && !invalid.window!.isVisible, "Checks must never show a window")
}

@MainActor func render(_ window: NSWindow, to url: URL) {
    let view = window.contentView!.superview!
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        failures.append("Could not render \(url.lastPathComponent)"); return
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
for failure in failures { fputs("FAIL \(failure)\n", stderr) }
print("Settings: \(assertions) assertions, \(failures.count) failures; no window was shown")
exit(failures.isEmpty ? 0 : 1)

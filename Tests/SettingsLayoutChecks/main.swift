import AppKit
import Carbon
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
          "Before any permission result, the view must not assume a grant or a denial")
    let ready = SettingsStatus(permissionChecked: true, accessibilityGranted: true, keyboardRunning: true, paused: false)
    check(ready.accessibility == .granted && ready.switching == .active && !ready.showsGrantPermission,
          "An automatic successful permission query must immediately display Granted and Active")
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

func checkLaunchRequests() {
    func event(origin: AEKeyword? = nil, id: AEEventID = AEEventID(kAEOpenApplication)) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: id,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let origin { event.setParam(NSAppleEventDescriptor(enumCode: origin), forKeyword: AEKeyword(keyAEPropData)) }
        return event
    }
    check(ApplicationLaunch.opensSettings(event()), "A single explicit cold open must request Settings")
    check(!ApplicationLaunch.opensSettings(event(origin: AEKeyword(keyAELaunchedAsLogInItem))),
          "Login launch must not open Settings")
    check(!ApplicationLaunch.opensSettings(event(origin: AEKeyword(keyAELaunchedAsServiceItem))),
          "Background service launch must not open Settings")
    check(!ApplicationLaunch.opensSettings(event(id: AEEventID(kAEQuitApplication))),
          "Unrelated Apple events must not open Settings")
}
checkLaunchRequests()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let info = (NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")) as? [String: Any]) ?? [:]
    check(info["CFBundleIdentifier"] as? String == ApplicationIdentity.bundleIdentifier,
          "Bundle metadata must match the identity used by relaunch notifications and runtime services")
    check(["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"].allSatisfy {
        info[$0] as? String == ApplicationIdentity.displayName
    }, "Public bundle, executable and interface names must agree while the bundle identity remains stable")
    if let icon = NSImage(contentsOf: root.appendingPathComponent(".build/ClearCmdTab.app/Contents/Resources/ClearCommandTab.icns")) {
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
    check(darkArrow.redComponent > 0.99 && darkArrow.greenComponent > 0.99 && darkArrow.blueComponent > 0.99,
          "The selected dark logo must have white arrows")
    check(lightArrow.redComponent < 0.01 && lightArrow.greenComponent < 0.01 && lightArrow.blueComponent < 0.01,
          "The selected light logo must have black arrows")
    let resourcePath = [".build/ClearCmdTab.app", ".build/ClearCommandTab.app"]
        .map { root.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }!
    let resources = Bundle(url: resourcePath)!
    let cachedBlueIcon = NSImage(size: NSSize(width: 176, height: 176), flipped: false) { rect in
        NSColor.blue.setFill()
        rect.fill()
        return true
    }
    app.applicationIconImage = cachedBlueIcon
    let settings = SettingsWindow(info: info, darkIcon: darkArtwork, resourceBundle: resources)
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
    let quit = control("quitApplication", as: NSButton.self)
    check((quit.superview as? NSStackView)?.arrangedSubviews.last === quit,
          "Quit must be the final control at the bottom of Settings")
    let appWindow = window as! SettingsAppWindow
    var quitRequests = 0
    appWindow.onQuit = { quitRequests += 1 }
    quit.performClick(nil)
    check(quitRequests == 1, "The actual Quit button must request application termination")
    for page in [SettingsWindow.Page.settings, .guide, .about] {
        settings.selectPage(page)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "q",
            charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
        let before = quitRequests
        check(window.performKeyEquivalent(with: event) && quitRequests == before + 1,
              "Command-Q must request Quit exactly once in \(page)")
    }
    let beforeUnrelatedKeys = quitRequests
    for modifiers: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .option]] {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "q",
            charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
        _ = window.performKeyEquivalent(with: event)
    }
    check(quitRequests == beforeUnrelatedKeys, "Plain Q and modified Command-Q must not quit")
    var closes = 0
    settings.onClose = { closes += 1 }
    let quitsBeforeClose = quitRequests
    for page in [SettingsWindow.Page.settings, .guide, .about] {
        // Each hidden fixture can close once. Closing an already closed window
        // correctly emits no second native notification; reopening is a GUI test.
        let closing = SettingsWindow(info: info, darkIcon: darkArtwork, resourceBundle: resources)
        closing.selectPage(page)
        closing.onClose = { closes += 1 }
        let closeWindow = closing.window as! SettingsAppWindow
        closeWindow.onQuit = { quitRequests += 1 }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: closeWindow.windowNumber, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        let before = closes
        check(closeWindow.performKeyEquivalent(with: event) && closes == before + 1,
              "Command-W must follow the native close/delegate path exactly once in \(page)")
        check(quitRequests == quitsBeforeClose && closing.window === closeWindow && !closeWindow.isVisible,
              "Command-W keeps the service and reusable settings controller alive in \(page)")
    }
    let redButtonFixture = SettingsWindow(info: info, darkIcon: darkArtwork, resourceBundle: resources)
    redButtonFixture.onClose = { closes += 1 }
    (redButtonFixture.window as! SettingsAppWindow).onQuit = { quitRequests += 1 }
    let beforeRedButton = closes
    redButtonFixture.window!.standardWindowButton(.closeButton)!.performClick(nil)
    check(closes == beforeRedButton + 1 && quitRequests == quitsBeforeClose,
          "The red close button and Command-W use the same close callback without quitting")
    for (page, title) in [(SettingsWindow.Page.about, "About"), (.guide, "Guide"), (.settings, "Settings"), (.about, "About")] {
        settings.selectPage(page)
        check(tabs.tabViewItems[tabs.selectedTabViewItemIndex].label == title,
              "Direct page route must select \(title), regardless of previous tab")
        check(!window.isVisible, "Selecting a page must not show a window before menu tracking ends")
    }
    settings.selectPage(.settings)
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

    let pause = tabs.tabViewItems.compactMap { $0.viewController?.view }
        .flatMap(descendants).compactMap { $0 as? NSButton }.first { $0.title == "Pause" }!
    var settingsPaused = false
    settings.onTogglePause = {
        settingsPaused.toggle()
        update(running: !settingsPaused, paused: settingsPaused)
    }
    pause.performClick(nil)
    check(settingsPaused && pause.title == "Resume" && control("switchingStatus", as: NSTextField.self).stringValue == "Status: Inactive",
          "Settings must retain a functioning Pause action after adding the menu action")
    pause.performClick(nil)
    check(!settingsPaused && pause.title == "Pause", "Settings Resume must restore the normal action")

    // Preference compatibility and selection callbacks with no writes to real user defaults.
    let preferences = UserDefaults(suiteName: "local.ClearCommandTab.Checks.\(UUID().uuidString)")!
    for (stored, expected) in [("current", GlassProfile.current), ("altTab", .altTab), ("matte", .matte)] {
        preferences.setVolatileDomain([GlassProfile.preferenceKey: stored], forName: UserDefaults.argumentDomain)
        check(GlassProfile.selected(in: preferences) == expected, "Stored profile \(stored) must remain compatible")
    }
    settings.onGlassProfile = { selected in
        preferences.setVolatileDomain([GlassProfile.preferenceKey: selected.rawValue], forName: UserDefaults.argumentDomain)
    }
    glass.selectItem(withTitle: "matte")
    glass.sendAction(glass.action!, to: glass.target)
    check(GlassProfile.selected(in: preferences) == .matte && glass.titleOfSelectedItem == "matte",
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
    let aquaAppearance = NSAppearance(named: .aqua)!, darkAppearance = NSAppearance(named: .darkAqua)!
    var expectedLight: NSImage?, expectedDark: NSImage?
    aquaAppearance.performAsCurrentDrawingAppearance { expectedLight = app.applicationIconImage }
    check(ApplicationIcon.samePixels(ApplicationIcon.rasterize(originalIcon, appearance: aquaAppearance),
                                    ApplicationIcon.rasterize(expectedLight, appearance: aquaAppearance)),
          "About uses the public system application image, including AppKit's treatment of a custom icon")
    window.appearance = NSAppearance(named: .darkAqua)
    darkAppearance.performAsCurrentDrawingAppearance { expectedDark = app.applicationIconImage }
    check(ApplicationIcon.samePixels(ApplicationIcon.rasterize(aboutIcon.image, appearance: darkAppearance),
                                    ApplicationIcon.rasterize(expectedDark, appearance: darkAppearance)),
          "A dark window must use AppKit's native result rather than forcing a bundled dark bitmap")
    window.appearance = NSAppearance(named: .aqua)
    check(ApplicationIcon.samePixels(ApplicationIcon.rasterize(aboutIcon.image, appearance: aquaAppearance),
                                    ApplicationIcon.rasterize(expectedLight, appearance: aquaAppearance)),
          "About restores AppKit's native result after appearance changes")
    let lightResource = NSImage(contentsOf: resources.url(forResource: "ClearCommandTab", withExtension: "icns")!)!
    let fallbackIcon = AppearanceIconView(light: lightResource, dark: darkArtwork, systemIcon: { nil })
    fallbackIcon.appearance = NSAppearance(named: .darkAqua)
    check(fallbackIcon.image === darkArtwork, "Missing system artwork falls back to the bundled dark resource")
    fallbackIcon.appearance = NSAppearance(named: .aqua)
    check(fallbackIcon.image === lightResource, "Fallback follows the window appearance and restores light artwork")
    let missingDark = AppearanceIconView(light: lightResource, dark: nil, systemIcon: { nil })
    missingDark.appearance = NSAppearance(named: .darkAqua)
    check(missingDark.image === lightResource, "A missing dark fallback retains valid light artwork")
    var currentNative: NSImage? = originalIcon
    let refreshed = AppearanceIconView(light: lightResource, dark: darkArtwork, systemIcon: { currentNative })
    currentNative = darkArtwork
    refreshed.refreshImage()
    check(refreshed.image === darkArtwork, "Refreshing About reads a changed native application image")
    let unconfigured = SettingsWindow(info: [:])
    let unconfiguredTabs = unconfigured.window!.contentViewController as! NSTabViewController
    check(descendants(unconfiguredTabs.tabViewItems[2].viewController!.view).contains {
        $0.identifier?.rawValue == "repositoryLink" && ($0 as? NSButton)?.isEnabled == false
    }, "Unconfigured GitHub must retain a disabled repository row")
    check(control("repositoryLink", as: NSButton.self).isEnabled,
          "The bundled public repository must appear as an enabled About link")
    let aboutLabels = descendants(tabs.tabViewItems[2].viewController!.view).compactMap { ($0 as? NSTextField)?.stringValue }
    check(aboutLabels.contains("Version \(info["CFBundleShortVersionString"] ?? "Development") (\(info["CFBundleVersion"] ?? ""))") &&
          !aboutLabels.contains(where: { $0.hasPrefix("Build ") }), "Version and build share one line with parenthesized build metadata")
    check(aboutLabels.contains("Free, open-source, native macOS app.\nSwitch between visible apps with Command-Tab.") &&
          !aboutLabels.contains("Runs locally. No accounts or analytics."), "About contains the requested concise ordered description without an extra footer")
    check(aboutLabels.contains(ApplicationIdentity.displayName) && window.title == "\(ApplicationIdentity.displayName) Settings",
          "The new public app name is consistent in About and the window title")
    check((control("repositoryLink", as: NSButton.self).superview as? NSStackView)?.arrangedSubviews.count == 6,
          "About contains only icon, name, version/build, description, author and repository")
    let linked = SettingsWindow(info: ["GitHubRepositoryURL": "https://github.com/example/clear-command-tab"])
    let linkedTabs = linked.window!.contentViewController as! NSTabViewController
    check(descendants(linkedTabs.tabViewItems[2].viewController!.view).contains {
        $0.identifier?.rawValue == "repositoryLink" && $0 is NSButton
    }, "Configured HTTPS repository metadata must enable a link")
    let invalid = SettingsWindow(info: ["GitHubRepositoryURL": "file:///tmp/repository"])
    let invalidTabs = invalid.window!.contentViewController as! NSTabViewController
    check(descendants(invalidTabs.tabViewItems[2].viewController!.view).contains {
        $0.identifier?.rawValue == "repositoryLink" && ($0 as? NSButton)?.isEnabled == false
    }, "Invalid repository metadata must not become a clickable link")

    // Exercise material replacement on the real hidden panel, including its selection.
    let panel = SwitcherPanel()
    let items = (1...3).map { SwitcherItem(id: .application(Int32($0)), name: "Application \($0)", icon: nil) }
    if let display = NSScreen.main {
        check(panel.prepare(items: items, selected: items[1].id, screen: display), "Panel content must prepare without presentation")
        check(Set(panel.visibleApplicationPIDs) == Set(items.map(\.id.pid)),
              "Compact panel exposes only the actual visible app IDs for live refresh")
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
        let dense = (1...100).map { SwitcherItem(id: .application(Int32($0)), name: "Fixture \($0)", icon: nil) }
        panel.prepare(items: dense, selected: dense[0].id, screen: display)
        let leftViewport = panel.visibleApplicationPIDs
        panel.prepare(items: dense, selected: dense[99].id, screen: display)
        check(leftViewport.count < dense.count && leftViewport.contains(1) && !leftViewport.contains(100),
              "Dense panel does not poll artwork beyond its visible viewport")
        check(panel.visibleApplicationPIDs.contains(100) && !panel.visibleApplicationPIDs.contains(1),
              "Scrolling updates the live icon targets to the newly visible app set")
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
    check(!window.isVisible && !linked.window!.isVisible && !invalid.window!.isVisible && !unconfigured.window!.isVisible, "Checks must never show a window")
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

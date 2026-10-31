import AppKit
import Darwin
import ClearCommandTabCore

/// A KVO token does not keep its observed object alive. In particular, a
/// workspace refresh can replace an NSRunningApplication wrapper for the same
/// process. Unregister before releasing the last reference to that wrapper.
final class RetainedObservation<Subject: NSObject> {
    let subject: Subject
    private var token: NSKeyValueObservation?

    init<Value>(_ subject: Subject, keyPath: KeyPath<Subject, Value>, change: @escaping (Subject) -> Void) {
        self.subject = subject
        token = subject.observe(keyPath, options: [.initial, .new]) { object, _ in change(object) }
    }

    func invalidate() {
        withExtendedLifetime(subject) { token?.invalidate(); token = nil }
    }

    deinit { withExtendedLifetime(subject) { token?.invalidate() } }
}

struct ApplicationPresentation {
    let name: String
    let bundleIdentifier: String?
}

/// Only visibility-driven work is disposable. A later launch/appearance request
/// is kept separately, so cancelling a panel cannot suppress a required refresh.
private final class IconLoadTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let visibleOnly: Bool
    init(visibleOnly: Bool) { self.visibleOnly = visibleOnly }
    var valid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

@MainActor
final class ApplicationTracker {
    private(set) var history: ApplicationHistory
    private(set) var applications: [Int32: NSRunningApplication] = [:]
    private(set) var presentations: [Int32: ApplicationPresentation] = [:]
    private(set) var icons: [Int32: CGImage] = [:]
    private(set) var frontmostPID: Int32?
    private(set) var dockPID: Int32?
    var onChange: ((Bool) -> Void)?
    var onIconsChanged: (() -> Void)?
    private var records: [Int32: ApplicationRecord] = [:]
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?
    private var iconRetries: [Int32: DispatchWorkItem] = [:]
    private var retriedIcons: Set<Int32> = []
    private var iconInFlight: [Int32: IconLoadTicket] = [:]
    private var deferredIcons: [Int32: Bool] = [:] // true = visibility only
    private var lastIconRefresh: [Int32: TimeInterval] = [:]
    private var appearanceObservation: NSKeyValueObservation?
    private var iconRevision: UInt64 = 0
    private var iconInvalidations: [Int32: UInt64] = [:]
    private var launchObservations: [Int32: RetainedObservation<NSRunningApplication>] = [:]
    private var visibleIconPIDs: [Int32] = []
    private var selectedIconPID: Int32?
    private var visibleIconCursor = 0
    private var visibleIconGeneration: UInt64 = 0
    private var visibleIconTimer: Timer?
    private let launchIconRetryDelays: [Double]
    private let iconQueue = DispatchQueue(label: ApplicationIdentity.bundleIdentifier + ".icons", qos: .utility)
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var lastSavedOrder: [String]
    private let workspace = NSWorkspace.shared
    private let runningApplications: () -> [NSRunningApplication]
    private let processIsRunning: (Int32) -> Bool
    private let iconResolver: (NSRunningApplication, Int, NSAppearance) -> CGImage?
    private let iconStyler: ApplicationIconStyler?
    private var terminatedApplications: [Int32: NSRunningApplication] = [:]

    init(defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         runningApplications: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
         processIsRunning: @escaping (Int32) -> Bool = ApplicationTracker.processIsRunning,
         launchIconRetryDelays: [Double] = [0.2, 0.6, 1.5, 3],
         iconResolver: ((NSRunningApplication, Int, NSAppearance) -> CGImage?)? = nil) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        lastSavedOrder = defaults.stringArray(forKey: "applicationOrder") ?? []
        self.runningApplications = runningApplications
        self.processIsRunning = processIsRunning
        self.iconResolver = iconResolver ?? { ApplicationIcon.resolve($0, pixels: $1, appearance: $2) }
        // Injected resolvers already supply final test artwork. Production also
        // asks the public system renderer for the user's icon/widget style.
        iconStyler = iconResolver == nil ? ApplicationIconStyler() : nil
        self.launchIconRetryDelays = launchIconRetryDelays
        history = ApplicationHistory(excludedID: ProcessInfo.processInfo.processIdentifier,
                                     rememberedOrder: lastSavedOrder)
        iconQueue.async { _ = ApplicationIcon.fallback }
        refresh()
        frontmostPID = liveFrontmostPID
        if let frontmostPID { history.activate(frontmostPID) }
        let center = notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let pid = app?.processIdentifier
                    let activated = name == NSWorkspace.didActivateApplicationNotification
                    if name == NSWorkspace.didTerminateApplicationNotification, let app {
                        // The event is authoritative even if runningApplications still
                        // contains this instance during asynchronous app shutdown.
                        self.removeApplication(app)
                    } else if activated {
                        guard let app, self.isLive(app) else { return }
                        self.frontmostPID = pid
                        if let pid, self.applications[pid] == nil, app.activationPolicy == .regular { self.refresh() }
                        if let pid {
                            self.history.activate(pid)
                            self.requestIcon(pid, force: false)
                            self.scheduleSave()
                        }
                    } else if let pid, let record = self.records[pid],
                              name == NSWorkspace.didHideApplicationNotification || name == NSWorkspace.didUnhideApplicationNotification {
                        // The notification supplies the new state; do not re-query every app.
                        self.records[pid] = ApplicationRecord(id: pid, persistenceID: record.persistenceID,
                                                             name: record.name,
                                                             isHidden: name == NSWorkspace.didHideApplicationNotification)
                        self.history.update(Array(self.records.values))
                    } else { self.refresh() }
                    self.onChange?(activated)
                }
            })
        }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // Resolve the latest value on the UI loop, even if several appearance
            // notifications arrive during one system transition.
            DispatchQueue.main.async { self?.refreshIconsForAppearanceChange() }
        }
    }

    func refreshIconsForAppearanceChange() {
        iconRevision &+= 1
        iconStyler?.invalidate()
        for pid in applications.keys { requestIcon(pid, force: true) }
    }

    /// Called after actual panel presentation, never on a quick invisible switch.
    /// Only the selected app plus one other displayed app are refreshed per tick.
    /// There is no timer while the panel is closed and no global app polling.
    func setVisibleIconTargets(_ pids: [Int32], selected: Int32?) {
        var seen: Set<Int32> = []
        let targets = pids.filter { applications[$0] != nil && seen.insert($0).inserted }
        let wasEmpty = visibleIconPIDs.isEmpty
        let oldSelection = selectedIconPID
        let added = targets.filter { !visibleIconPIDs.contains($0) }
        for (pid, ticket) in iconInFlight where ticket.visibleOnly && !targets.contains(pid) { ticket.cancel() }
        deferredIcons = deferredIcons.filter { !$0.value || targets.contains($0.key) }
        visibleIconPIDs = targets
        selectedIconPID = selected.flatMap { targets.contains($0) ? $0 : nil }
        guard !targets.isEmpty else {
            visibleIconGeneration &+= 1
            visibleIconTimer?.invalidate()
            visibleIconTimer = nil
            visibleIconCursor = 0
            return
        }
        if wasEmpty {
            visibleIconGeneration &+= 1
            visibleIconCursor = 0
            let generation = visibleIconGeneration
            // One initial refresh of the displayed set; defer even scheduling
            // until after the caller has returned from handling its input event.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visibleIconGeneration == generation else { return }
                if let pid = self.selectedIconPID { self.requestIcon(pid, force: true, visibleOnly: true) }
                for pid in self.visibleIconPIDs where pid != self.selectedIconPID { self.requestIcon(pid, force: true, visibleOnly: true) }
            }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibleIcons() }
            }
            timer.tolerance = 0.1
            visibleIconTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            var changedTargets = added
            if oldSelection != selectedIconPID, let pid = selectedIconPID {
                changedTargets.removeAll { $0 == pid }
                changedTargets.insert(pid, at: 0)
            }
            guard !changedTargets.isEmpty else { return }
            let generation = visibleIconGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visibleIconGeneration == generation else { return }
                for pid in changedTargets where self.visibleIconPIDs.contains(pid) { self.requestIcon(pid, force: true, visibleOnly: true) }
            }
        }
    }

    private func refreshVisibleIcons() {
        guard !visibleIconPIDs.isEmpty else { return }
        if let pid = selectedIconPID { requestIcon(pid, force: true, visibleOnly: true) }
        let others = visibleIconPIDs.filter { $0 != selectedIconPID }
        guard !others.isEmpty else { return }
        let pid = others[visibleIconCursor % others.count]
        visibleIconCursor = (visibleIconCursor + 1) % others.count
        requestIcon(pid, force: true, visibleOnly: true)
    }

    deinit {
        for observation in launchObservations.values { observation.invalidate() }
        visibleIconTimer?.invalidate()
        saveWork?.cancel()
        for observer in observers { notificationCenter.removeObserver(observer) }
        for work in iconRetries.values { work.cancel() }
        for ticket in iconInFlight.values { ticket.cancel() }
    }

    var windowInputs: [WindowApplication] {
        records.values.map { .init(pid: $0.id, hidden: $0.isHidden) }
    }

    func recordConfirmedActivation(_ pid: Int32) {
        guard let app = applications[pid], isLive(app) else { return }
        frontmostPID = pid
        history.activate(pid)
        scheduleSave()
    }

    func refresh() {
        dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        let snapshot = runningApplications()
        let running = snapshot.filter {
            isLive($0) && $0.activationPolicy == .regular &&
            $0.processIdentifier > 0 && (ownBundle == nil || $0.bundleIdentifier != ownBundle)
        }
        terminatedApplications = terminatedApplications.filter { pid, retired in
            snapshot.contains { $0.processIdentifier == pid && $0.launchDate == retired.launchDate }
        }
        frontmostPID = liveFrontmostPID
        applications = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        ApplicationIcon.retainResources(for: Set(applications.keys))
        for (pid, ticket) in iconInFlight where applications[pid] == nil { ticket.cancel() }
        deferredIcons = deferredIcons.filter { applications[$0.key] != nil }
        for pid in Array(iconRetries.keys) where applications[pid] == nil {
            iconRetries.removeValue(forKey: pid)?.cancel()
        }
        icons = icons.filter { applications[$0.key] != nil }
        lastIconRefresh = lastIconRefresh.filter { applications[$0.key] != nil }
        iconInvalidations = iconInvalidations.filter { applications[$0.key] != nil }
        presentations = presentations.filter { applications[$0.key] != nil }
        retriedIcons.formIntersection(applications.keys)
        launchObservations = launchObservations.filter { pid, observation in
            applications[pid].map { $0.launchDate == observation.subject.launchDate } ?? false
        }
        records = Dictionary(running.map { app in
            let pid = app.processIdentifier
            let presentation = presentations[pid] ?? ApplicationPresentation(name: app.localizedName ?? "Application",
                                                                             bundleIdentifier: app.bundleIdentifier)
            presentations[pid] = presentation
            return (pid, ApplicationRecord(id: pid,
                                           persistenceID: presentation.bundleIdentifier ?? app.bundleURL?.path ?? "pid:\(pid)",
                                           name: presentation.name, isHidden: app.isHidden))
        }, uniquingKeysWith: { first, _ in first })
        history.update(Array(records.values))
        for pid in applications.keys where retriedIcons.insert(pid).inserted {
            requestIcon(pid, force: true)
            retryLaunchIcon(pid, attempt: 0)
            if let app = applications[pid], !app.isFinishedLaunching {
                // Unlike icon, finishedLaunching is documented as KVO-observable.
                launchObservations[pid] = RetainedObservation(app, keyPath: \.isFinishedLaunching) { [weak self] app in
                    DispatchQueue.main.async {
                        guard let self, self.launchObservations[pid]?.subject === app,
                              let current = self.applications[pid], current.launchDate == app.launchDate,
                              app.isFinishedLaunching else { return }
                        // This is a one-shot launch observer, not a permanent
                        // registration on every process the tracker has seen.
                        self.launchObservations.removeValue(forKey: pid)?.invalidate()
                        self.iconInvalidations[pid, default: 0] &+= 1
                        self.requestIcon(pid, force: true)
                    }
                }
            }
        }
    }

    // Cheap kernel liveness checks, without icon decoding, AX or full enumeration.
    // This recovers from a lost/delayed workspace event before opening/committing.
    func pruneTerminatedApplications() {
        let dead = applications.values.filter { !isLive($0) }
        guard !dead.isEmpty else { return }
        for app in dead { removeApplication(app) }
        onChange?(false)
    }

    nonisolated static func processIsRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    private func isLive(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, processIsRunning(app.processIdentifier) else { return false }
        let retired = terminatedApplications[app.processIdentifier]
        return retired == nil || retired?.launchDate != app.launchDate
    }

    private var liveFrontmostPID: Int32? {
        guard let app = workspace.frontmostApplication, isLive(app) else { return nil }
        return app.processIdentifier
    }

    private func removeApplication(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // A late notification from an old instance must not remove a reused PID.
        if let current = applications[pid], current.launchDate != app.launchDate { return }
        terminatedApplications[pid] = app
        applications[pid] = nil
        presentations[pid] = nil
        records[pid] = nil
        icons[pid] = nil
        launchObservations.removeValue(forKey: pid)?.invalidate()
        iconInvalidations[pid] = nil
        visibleIconPIDs.removeAll { $0 == pid }
        if selectedIconPID == pid { selectedIconPID = nil }
        if visibleIconPIDs.isEmpty { setVisibleIconTargets([], selected: nil) }
        iconRetries.removeValue(forKey: pid)?.cancel()
        retriedIcons.remove(pid)
        deferredIcons[pid] = nil
        iconInFlight[pid]?.cancel()
        ApplicationIcon.forgetResources(for: pid)
        lastIconRefresh[pid] = nil
        history.update(Array(records.values))
        if frontmostPID == pid { frontmostPID = liveFrontmostPID }
    }

    private func requestIcon(_ pid: Int32, force: Bool, visibleOnly: Bool = false) {
        guard let app = applications[pid], !app.isTerminated else { return }
        guard !visibleOnly || visibleIconPIDs.contains(pid) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || icons[pid] == nil || now - lastIconRefresh[pid, default: 0] >= 5 else { return }
        guard iconInFlight[pid] == nil else {
            if force || !visibleOnly {
                // A required request must not be downgraded by a later hover.
                deferredIcons[pid] = (deferredIcons[pid] ?? true) && visibleOnly
            }
            return
        }
        let ticket = IconLoadTicket(visibleOnly: visibleOnly)
        iconInFlight[pid] = ticket
        let revision = iconRevision
        let invalidation = iconInvalidations[pid, default: 0]
        let previousImage = icons[pid]
        let appearanceName = NSApplication.shared.effectiveAppearance.name
        let resolve = iconResolver
        let styler = iconStyler
        let styleGeneration = styler?.generation
        let queue = iconQueue
        let pixels = min(512, max(256, Int(144 * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2))))
        iconQueue.async { [weak self] in
            // NSRunningApplication is thread-safe; no image decoding runs on the UI loop.
            let appearance = NSAppearance(named: appearanceName) ?? NSAppearance(named: .aqua)!
            let image = ticket.valid ? autoreleasepool { resolve(app, pixels, appearance) } : nil
            let finish: (CGImage?) -> Void = { [weak self] image in
                let changed = image != nil && !ApplicationIcon.samePixels(previousImage, image)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.iconInFlight[pid] = nil
                    if ticket.valid { self.lastIconRefresh[pid] = ProcessInfo.processInfo.systemUptime }
                    if ticket.valid, self.iconRevision == revision, self.iconInvalidations[pid, default: 0] == invalidation,
                       let current = self.applications[pid], current == app,
                       current.launchDate == app.launchDate, !app.isTerminated, let image, changed {
                        self.icons[pid] = image
                        self.onIconsChanged?()
                    }
                    if let visibleOnly = self.deferredIcons.removeValue(forKey: pid) {
                        self.requestIcon(pid, force: true, visibleOnly: visibleOnly)
                    }
                }
            }
            if let styler, ticket.valid, let image,
               let bundle = ApplicationIcon.styleBundleURL(for: app, matching: image, pixels: pixels, appearance: appearance),
               ticket.valid {
                styler.image(for: bundle, base: image, pixels: pixels, appearance: appearanceName,
                             generation: styleGeneration) { styled in
                    // Quick Look calls back on its own queue; keep comparison
                    // and all remaining pixel work on our utility queue.
                    queue.async { finish(styled) }
                }
            } else { finish(image) }
        }
    }

    private func retryLaunchIcon(_ pid: Int32, attempt: Int) {
        let delays = launchIconRetryDelays
        guard attempt < delays.count else { iconRetries[pid] = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.applications[pid] != nil else { return }
            self.requestIcon(pid, force: true)
            self.retryLaunchIcon(pid, attempt: attempt + 1)
        }
        iconRetries[pid]?.cancel()
        iconRetries[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt], execute: work)
    }

    func save() {
        saveWork?.cancel()
        saveWork = nil
        let order = history.rememberedOrder
        guard order != lastSavedOrder else { return }
        defaults.set(order, forKey: "applicationOrder")
        lastSavedOrder = order
    }

    private func scheduleSave() {
        saveWork?.cancel()
        saveWork = nil
        guard history.rememberedOrder != lastSavedOrder else { return }
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

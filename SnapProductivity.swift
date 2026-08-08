import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement

final class SnapLogger {
    static let shared = SnapLogger()
    private let queue = DispatchQueue(label: "com.safibaig.SnapProductivity.logger")
    private let url: URL

    private init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        url = logs.appendingPathComponent("Snap-Productivity.log")
    }

    func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        queue.async { [url] in
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: url) else { return }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}

private let bundleIdentifier = "com.safibaig.SnapProductivity"

final class HotkeyManager {
    enum State {
        case stopped
        case installed
        case failed(String)
    }

    private(set) var state: State = .stopped
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var delegate: SnapProductivityDelegate?

    init(delegate: SnapProductivityDelegate) {
        self.delegate = delegate
    }

    func start() {
        stop()
        SnapLogger.shared.log("HotkeyManager.start() — AXIsProcessTrusted=\(AXIsProcessTrusted())")

        // CGEvent taps that observe global keyboard input require Input Monitoring.
        // Ask macOS for that permission explicitly instead of assuming Accessibility
        // is sufficient. This also gives us a precise diagnostic if the tap fails.
        let listenAllowed = CGPreflightListenEventAccess()
        SnapLogger.shared.log("CGPreflightListenEventAccess=\(listenAllowed)")
        if !listenAllowed {
            let requested = CGRequestListenEventAccess()
            SnapLogger.shared.log("CGRequestListenEventAccess returned \(requested)")
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let listenMask = Self.eventMask(for: .keyDown)
        if let probeTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: listenMask,
            callback: snapEventTapCallback,
            userInfo: context
        ) {
            SnapLogger.shared.log("Listen-only keyboard tap CREATED — Input Monitoring is working")
            CFMachPortInvalidate(probeTap)
        } else {
            SnapLogger.shared.log("Listen-only keyboard tap FAILED — Input Monitoring is NOT available to this app")
        }

        let mask =
            Self.eventMask(for: .keyDown) |
            Self.eventMask(for: .tapDisabledByTimeout) |
            Self.eventMask(for: .tapDisabledByUserInput)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: snapEventTapCallback,
            userInfo: context
        ) else {
            state = .failed("Keyboard event tap could not be created. Check Input Monitoring and Accessibility.")
            SnapLogger.shared.log("CGEvent.tapCreate(defaultTap) FAILED — Input Monitoring=\(CGPreflightListenEventAccess()), Accessibility=\(AXIsProcessTrusted())")
            delegate?.updateStatus()
            return
        }

        guard let newSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            newTap,
            0
        ) else {
            state = .failed("Could not create the keyboard event run-loop source.")
            delegate?.updateStatus()
            return
        }

        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        state = .installed
        SnapLogger.shared.log("CGEvent event tap CREATED and ENABLED")
        delegate?.updateStatus()
    }

    private static func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
        state = .stopped
    }

    func restart() {
        start()
    }

    fileprivate func process(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        // Match Command + number only. Shift, Option, Control, and Fn must not be held.
        // This prevents shortcuts such as Command+Shift+4 from being intercepted.
        guard flags.contains(.maskCommand),
              !flags.contains(.maskShift),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskSecondaryFn) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard let slot = Self.slot(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.performShortcut(slot: slot)
        }

        // Consume only bare Command+0 through Command+9.
        return nil
    }

    private static func slot(for keyCode: Int64) -> Int? {
        switch keyCode {
        case 29: return 0
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }
}

private func snapEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    return manager.process(event, type: type)
}

final class DockReader {
    struct DockApp {
        let url: URL
        let title: String
        let bundleID: String?
    }

    func applications() -> [DockApp] {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first else {
            SnapLogger.shared.log("DockReader: Dock process not found")
            return []
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        SnapLogger.shared.log("DockReader: Dock pid=\(dock.processIdentifier)")
        var value: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            dockElement,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
        let children = value as? [AXUIElement] else {
            SnapLogger.shared.log("DockReader: AXUIElementCopyAttributeValue(children) FAILED")
            return []
        }

        var apps: [DockApp] = []
        for child in children {
            collect(from: child, into: &apps)
        }

        // Finder is always slot 0 and is excluded from the numbered Dock list.
        let filtered = apps.filter { $0.bundleID != "com.apple.finder" }
        SnapLogger.shared.log("DockReader: found \(filtered.count) numbered apps")
        return filtered
    }

    private func collect(from element: AXUIElement, into apps: inout [DockApp]) {
        if let role = attribute(element, kAXRoleAttribute) as? String,
           role == "AXDockItem" {
            if let url = dockURL(element), url.pathExtension == "app" {
                let title = (attribute(element, kAXTitleAttribute) as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let bundleID = Bundle(url: url)?.bundleIdentifier
                apps.append(DockApp(url: url, title: title, bundleID: bundleID))
            }
            return
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] else {
            return
        }

        for child in children {
            collect(from: child, into: &apps)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func dockURL(_ element: AXUIElement) -> URL? {
        if let value = attribute(element, kAXURLAttribute) {
            if let url = value as? URL {
                return url
            }
            if let path = value as? String {
                return URL(fileURLWithPath: path)
            }
        }

        if let title = attribute(element, kAXTitleAttribute) as? String {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let common = [
                home.appendingPathComponent("Applications/\(title).app"),
                URL(fileURLWithPath: "/Applications/\(title).app")
            ]
            if let match = common.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return match
            }
        }

        return nil
    }
}

final class SnapProductivityDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeys: HotkeyManager?
    private let dockReader = DockReader()
    private var startupMessage = "Starting…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        SnapLogger.shared.log("=== Snap-Productivity 1.0.4 launched ===")
        SnapLogger.shared.log("Bundle path: \(Bundle.main.bundlePath)")
        SnapLogger.shared.log("PID: \(ProcessInfo.processInfo.processIdentifier)")
        SnapLogger.shared.log("AXIsProcessTrusted at launch: \(AXIsProcessTrusted())")
        NSApp.setActivationPolicy(.accessory)

        // Register this app as a macOS Login Item so it starts automatically.
        do {
            try SMAppService.mainApp.register()
            SnapLogger.shared.log("Login Item registration: SUCCESS")
        } catch {
            SnapLogger.shared.log("Login Item registration: FAILED — \(error.localizedDescription)")
        }

        // Create the status item FIRST so a running process is always observable.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌘"
        item.button?.toolTip = "Snap-Productivity"
        item.isVisible = true
        statusItem = item
        SnapLogger.shared.log("Status item created")

        updateStatus()

        guard AXIsProcessTrusted() else {
            startupMessage = "Accessibility permission is OFF"
            SnapLogger.shared.log("Accessibility permission is OFF; hotkeys will NOT start")
            updateStatus()
            openAccessibilitySettings()
            return
        }

        hotkeys = HotkeyManager(delegate: self)
        hotkeys?.start()
        SnapLogger.shared.log("Hotkey manager state after start: \(String(describing: hotkeys?.state))")

        updateStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.stop()
    }

    func updateStatus() {
        guard let item = statusItem else { return }

        let menu = NSMenu()

        let header = NSMenuItem(title: "Snap-Productivity", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let axOK = AXIsProcessTrusted()
        let ax = NSMenuItem(
            title: axOK ? "✓ Accessibility" : "✗ Accessibility — REQUIRED",
            action: axOK ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        ax.target = self
        menu.addItem(ax)

        let tapOK: Bool
        if case .installed = hotkeys?.state {
            tapOK = true
        } else {
            tapOK = false
        }

        let tap = NSMenuItem(
            title: tapOK ? "✓ Keyboard Monitor" : "✗ Keyboard Monitor — NOT RUNNING",
            action: nil,
            keyEquivalent: ""
        )
        tap.isEnabled = false
        menu.addItem(tap)

        let count = dockReader.applications().count
        let dock = NSMenuItem(
            title: count > 0 ? "✓ Dock Access — \(count) numbered apps"
                             : "✗ Dock Access — no apps found",
            action: nil,
            keyEquivalent: ""
        )
        dock.isEnabled = false
        menu.addItem(dock)

        if !startupMessage.isEmpty && startupMessage != "Starting…" {
            menu.addItem(.separator())
            let message = NSMenuItem(title: startupMessage, action: nil, keyEquivalent: "")
            message.isEnabled = false
            menu.addItem(message)
        }

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload", action: #selector(reload), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let accessibility = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)

        let input = NSMenuItem(
            title: "Open Input Monitoring Settings…",
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        input.target = self
        menu.addItem(input)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Snap-Productivity",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    func performShortcut(slot: Int) {
        SnapLogger.shared.log("Shortcut received: Command+\(slot)")
        startupMessage = "Last shortcut: ⌘\(slot)"
        updateStatus()

        if slot == 0 {
            toggleFinder()
            return
        }

        let apps = dockReader.applications()
        let index = slot - 1

        guard index >= 0, index < apps.count else {
            NSSound.beep()
            startupMessage = "⌘\(slot): no matching Dock app"
            updateStatus()
            return
        }

        let dockApp = apps[index]

        if let running = runningApplication(for: dockApp) {
            if running.isActive && hasVisibleWindow(for: running) {
                SnapLogger.shared.log("Hiding active app: \(dockApp.title)")
                running.hide()
            } else {
                SnapLogger.shared.log("Showing app: \(dockApp.title) — pid=\(running.processIdentifier)")
                showApplication(running, title: dockApp.title)
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(
            at: dockApp.url,
            configuration: config
        ) { [weak self] launchedApp, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.startupMessage = "Launch failed: \(error.localizedDescription)"
                    self.updateStatus()
                }
                return
            }

            guard let launchedApp else {
                DispatchQueue.main.async {
                    self.startupMessage = "Launch succeeded, but macOS returned no application."
                    self.updateStatus()
                }
                return
            }

            // Launch completion only means the process has launched. Some macOS apps
            // (notably Messages) create their first window shortly afterwards.
            // Wait asynchronously for the AX window tree to become available, then
            // raise the window. This never blocks the hotkey handler or adds polling
            // while the app is idle.
            self.showLaunchedApplication(launchedApp, title: dockApp.title)
        }
    }

    private func runningApplication(for dockApp: DockReader.DockApp) -> NSRunningApplication? {
        if let bundleID = dockApp.bundleID,
           let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) {
            SnapLogger.shared.log("Target resolved: \(dockApp.title) — pid=\(running.processIdentifier) — \(dockApp.url.path)")
            return running
        }

        // Bundle identifiers are not always available from Dock Accessibility.
        // Resolve the exact Dock URL through NSWorkspace instead of failing over
        // to an unrelated process or treating the app as unresolvable.
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: dockApp.url),
           let bundleID = Bundle(url: appURL)?.bundleIdentifier,
           let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) {
            SnapLogger.shared.log("Target resolved via URL: \(dockApp.title) — pid=\(running.processIdentifier)")
            return running
        }

        return nil
    }

    private func applicationAXElement(for running: NSRunningApplication) -> AXUIElement {
        AXUIElementCreateApplication(running.processIdentifier)
    }

    private func windows(for running: NSRunningApplication) -> [AXUIElement] {
        let appElement = applicationAXElement(for: running)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func setAXBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef)
    }

    private func hasVisibleWindow(for running: NSRunningApplication) -> Bool {
        for window in windows(for: running) {
            let minimized = axBool(window, kAXMinimizedAttribute) ?? false
            let subrole = (attribute(window, kAXSubroleAttribute) as? String) ?? ""
            if !minimized && (subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String || subrole.isEmpty) {
                return true
            }
        }
        return false
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func showLaunchedApplication(_ running: NSRunningApplication, title: String) {
        SnapLogger.shared.log("Launch completed: \(title) — pid=\(running.processIdentifier)")

        // A newly launched application may not have created its first AX window
        // yet. Check a small number of times over a short window, stopping as soon
        // as a usable window appears. This is event-driven/asynchronous and only
        // runs for the brief launch transition; there is no permanent polling.
        let delays: [TimeInterval] = [0.0, 0.03, 0.08, 0.15, 0.30, 0.50]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak running] in
                guard let self, let running, !running.isTerminated else { return }

                running.unhide()
                running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                self.raiseWindows(of: running, title: title)

                if self.hasUsableWindow(for: running) {
                    SnapLogger.shared.log("Launch window ready: \(title)")
                } else if delay == delays.last {
                    SnapLogger.shared.log("Launch window not available after retry window: \(title)")
                }
            }
        }
    }

    private func hasUsableWindow(for running: NSRunningApplication) -> Bool {
        return !windows(for: running).isEmpty
    }

    private func showApplication(_ running: NSRunningApplication, title: String) {
        // Unhide and activate first. Some macOS apps need a second pass after
        // activation before their Accessibility window tree becomes current.
        running.unhide()
        running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        raiseWindows(of: running, title: title)

        // A tiny asynchronous retry handles apps such as Messages whose window
        // server state is updated just after activation. No animation is added.
        DispatchQueue.main.async { [weak self, weak running] in
            guard let self, let running else { return }
            self.raiseWindows(of: running, title: title)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak running] in
            guard let self, let running else { return }
            if !running.isActive || !self.hasVisibleWindow(for: running) {
                running.unhide()
                running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            self.raiseWindows(of: running, title: title)
        }
    }

    private func raiseWindows(of running: NSRunningApplication, title: String) {
        let appElement = applicationAXElement(for: running)
        var mainWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow) == .success {
            let window = mainWindow as! AXUIElement
            setAXBool(window, kAXMinimizedAttribute, false)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            SnapLogger.shared.log("Raised main window: \(title)")
        }

        // If there is no main window, raise the first non-minimized window.
        for window in windows(for: running) {
            let minimized = axBool(window, kAXMinimizedAttribute) ?? false
            if minimized {
                setAXBool(window, kAXMinimizedAttribute, false)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if !minimized { break }
        }
    }

    private func toggleFinder() {
        if let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder")
            .first {

            if finder.isActive && hasVisibleWindow(for: finder) {
                finder.hide()
            } else {
                showApplication(finder, title: "Finder")
            }
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] launchedApp, error in
                guard let self else { return }
                if let error {
                    SnapLogger.shared.log("Finder launch failed: \(error.localizedDescription)")
                    return
                }
                if let launchedApp {
                    self.showLaunchedApplication(launchedApp, title: "Finder")
                }
            }
        }
    }

    @objc private func reload() {
        SnapLogger.shared.log("Reload requested")
        startupMessage = "Reloading…"
        updateStatus()

        guard AXIsProcessTrusted() else {
            startupMessage = "Accessibility permission is OFF"
            updateStatus()
            openAccessibilitySettings()
            return
        }

        if hotkeys == nil {
            hotkeys = HotkeyManager(delegate: self)
        }
        hotkeys?.restart()

        startupMessage = "Ready"
        updateStatus()
    }

    @objc func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = SnapProductivityDelegate()
SnapLogger.shared.log("NSApplication starting run loop")
app.delegate = delegate
app.run()

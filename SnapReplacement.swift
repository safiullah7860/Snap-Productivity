import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement

final class SnapLogger {
    static let shared = SnapLogger()
    private let queue = DispatchQueue(label: "com.safibaig.SnapReplacement.logger")
    private let url: URL

    private init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        url = logs.appendingPathComponent("SnapReplacement.log")
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

private let bundleIdentifier = "com.safibaig.SnapReplacement141"

final class HotkeyManager {
    enum State {
        case stopped
        case installed
        case failed(String)
    }

    private(set) var state: State = .stopped
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var delegate: SnapReplacementDelegate?

    init(delegate: SnapReplacementDelegate) {
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
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard let slot = Self.slot(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.performShortcut(slot: slot)
        }

        // Consume only Command+0 through Command+9.
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

final class SnapReplacementDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeys: HotkeyManager?
    private let dockReader = DockReader()
    private var startupMessage = "Starting…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        SnapLogger.shared.log("=== SnapReplacement 1.4.1 launched ===")
        SnapLogger.shared.log("Bundle path: \(Bundle.main.bundlePath)")
        SnapLogger.shared.log("PID: \(ProcessInfo.processInfo.processIdentifier)")
        SnapLogger.shared.log("AXIsProcessTrusted at launch: \(AXIsProcessTrusted())")
        NSApp.setActivationPolicy(.accessory)

        // Create the status item FIRST so a running process is always observable.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌘"
        item.button?.toolTip = "SnapReplacement"
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

        let header = NSMenuItem(title: "SnapReplacement", action: nil, keyEquivalent: "")
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
            title: "Quit SnapReplacement",
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

        if let bundleID = dockApp.bundleID,
           let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {

            if running.isActive {
                running.hide()
            } else {
                running.unhide()
                running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(
            at: dockApp.url,
            configuration: config
        ) { [weak self] _, error in
            if let error {
                DispatchQueue.main.async {
                    self?.startupMessage = "Launch failed: \(error.localizedDescription)"
                    self?.updateStatus()
                }
            }
        }
    }

    private func toggleFinder() {
        if let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder")
            .first {

            if finder.isActive {
                finder.hide()
            } else {
                finder.unhide()
                finder.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
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
let delegate = SnapReplacementDelegate()
SnapLogger.shared.log("NSApplication starting run loop")
app.delegate = delegate
app.run()

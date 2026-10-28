import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ProcessLinkKit
import ScreenCaptureKit

/// Local task capture. It samples the frontmost application every two seconds
/// and, only when explicitly enabled, adds window-title samples, local window
/// screenshots and keystroke/mouse **counts**. It never records key codes,
/// clipboard, page text or a person's name. The content-rich options are off
/// by default and each one is a separate toggle.
@MainActor
@Observable
final class ActivityCapture {
    static let shared = ActivityCapture()
    static let screenshotInterval: TimeInterval = 30

    struct Options: Equatable {
        var windowTitles = false
        var screenshots = false
        var inputCounts = false
    }

    struct LiveApp: Identifiable {
        var id: String { bundleID.isEmpty ? name : bundleID }
        var name: String
        var bundleID: String
        var minutes: Double = 0
        var idleMinutes: Double = 0
        var switches: Int = 0
    }

    struct LiveWindow: Identifiable {
        var id: String { "\(appName)|\(title)" }
        var appName: String
        var title: String
        var minutes: Double = 0
        var samples: Int = 0
    }

    struct Shot: Identifiable {
        var id: UUID = UUID()
        var path: String
        var appName: String
        var capturedAt: Date
    }

    struct Result {
        var sessionID: String
        var startedAt: Date
        var endedAt: Date
        var activeMinutes: Double
        var idleMinutes: Double
        var switches: Int
        var keystrokes: Int
        var clicks: Int
        var apps: [LiveApp]
        var windows: [LiveWindow]
        var shots: [Shot]
    }

    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var lastTick: Date?
    private(set) var apps: [String: LiveApp] = [:]
    private(set) var windows: [String: LiveWindow] = [:]
    private(set) var shots: [Shot] = []
    private(set) var activeMinutes: Double = 0
    private(set) var idleMinutes: Double = 0
    private(set) var switches: Int = 0
    private(set) var keystrokes: Int = 0
    private(set) var clicks: Int = 0
    private(set) var options = Options()
    private(set) var screenshotDirectory: URL?
    private(set) var screenshotError: String?
    private(set) var isCapturingShot = false

    private var lastApp: String?
    private var lastShotAt = Date.distantPast
    private var sessionID = ""
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    // MARK: Permission state

    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func openPrivacyPane(_ pane: String) {
        let slug = pane == "screen" ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(slug)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Session

    func start(options: Options = Options()) {
        guard !isRunning else { return }
        self.options = options
        isRunning = true
        startedAt = .now
        lastTick = .now
        sessionID = "cap-\(UUID().uuidString.prefix(8))"
        apps = [:]
        windows = [:]
        shots = []
        activeMinutes = 0
        idleMinutes = 0
        switches = 0
        keystrokes = 0
        clicks = 0
        lastApp = nil
        lastShotAt = .distantPast
        screenshotError = nil
        screenshotDirectory = Self.captureRoot.appendingPathComponent(sessionID, isDirectory: true)
        if options.screenshots {
            try? FileManager.default.createDirectory(at: screenshotDirectory!, withIntermediateDirectories: true)
        }
        startInputMonitors(if: options.inputCounts)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() -> Result? {
        guard isRunning, let startedAt else { return nil }
        tick()
        isRunning = false
        timer?.invalidate()
        timer = nil
        stopInputMonitors()
        let ended = Date.now
        return Result(
            sessionID: sessionID, startedAt: startedAt, endedAt: ended,
            activeMinutes: activeMinutes, idleMinutes: idleMinutes,
            switches: switches, keystrokes: keystrokes, clicks: clicks,
            apps: apps.values.sorted { $0.minutes > $1.minutes },
            windows: windows.values.sorted { $0.minutes > $1.minutes },
            shots: shots.sorted { $0.capturedAt < $1.capturedAt })
    }

    func reset() {
        apps = [:]
        windows = [:]
        shots = []
        activeMinutes = 0
        idleMinutes = 0
        switches = 0
        keystrokes = 0
        clicks = 0
        startedAt = nil
        lastApp = nil
        sessionID = ""
        screenshotDirectory = nil
        screenshotError = nil
    }

    // MARK: Sampling

    private func tick() {
        guard isRunning else { return }
        let now = Date.now
        let elapsed = min(10, max(0, now.timeIntervalSince(lastTick ?? now)))
        lastTick = now
        guard elapsed > 0 else { return }

        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? "Unknown"
        let bundle = front?.bundleIdentifier ?? ""
        if bundle == Bundle.main.bundleIdentifier { return }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let idle = idleSeconds >= 60

        var app = apps[bundle.isEmpty ? name : bundle] ?? LiveApp(name: name, bundleID: bundle)
        if idle {
            idleMinutes += elapsed / 60
            app.idleMinutes += elapsed / 60
        } else {
            activeMinutes += elapsed / 60
            app.minutes += elapsed / 60
        }
        if lastApp != nil, lastApp != app.name {
            switches += 1
            app.switches += 1
        }
        lastApp = app.name
        apps[app.id] = app

        guard !idle else { return }
        let window = frontmostWindow(pid: front?.processIdentifier)
        if options.windowTitles, let title = window?.title, !title.isEmpty {
            let masked = PIIScanner.scan(title).maskedText
            let key = "\(name)|\(masked)"
            var entry = windows[key] ?? LiveWindow(appName: name, title: masked)
            entry.minutes += elapsed / 60
            entry.samples += 1
            windows[key] = entry
        }
        if options.screenshots, let windowID = window?.id,
           now.timeIntervalSince(lastShotAt) >= Self.screenshotInterval {
            lastShotAt = now
            captureScreenshot(windowID: windowID, appName: name)
        }
    }

    private func frontmostWindow(pid: pid_t?) -> (id: CGWindowID, title: String)? {
        guard let pid else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in list {
            guard let owner = entry[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = entry[kCGWindowNumber as String] as? Int else { continue }
            let title = entry[kCGWindowName as String] as? String ?? ""
            return (CGWindowID(number), title)
        }
        return nil
    }

    private func captureScreenshot(windowID: CGWindowID, appName: String) {
        guard !isCapturingShot, Self.screenRecordingGranted, let directory = screenshotDirectory else { return }
        isCapturingShot = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    await MainActor.run { self.isCapturingShot = false }
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let width = max(320, min(1_200, window.frame.width * scale))
                config.width = Int(width)
                config.height = Int(max(200, min(800, window.frame.height * scale)))
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.62]) else {
                    throw NSError(domain: "ProcessLink.Capture", code: 2)
                }
                let url = directory.appendingPathComponent("\(Int(Date.now.timeIntervalSince1970)).jpg")
                try data.write(to: url, options: .atomic)
                await MainActor.run {
                    self.shots.append(Shot(path: url.path, appName: appName, capturedAt: .now))
                    self.isCapturingShot = false
                }
            } catch {
                await MainActor.run {
                    self.screenshotError = error.localizedDescription
                    self.isCapturingShot = false
                }
            }
        }
    }

    // MARK: Input counts (counts, never key codes or text)

    private func startInputMonitors(if enabled: Bool) {
        guard enabled else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor in self?.keystrokes += 1 }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.clicks += 1 }
        }
    }

    private func stopInputMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    // MARK: Retention

    static var captureRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ProcessLink/captures", isDirectory: true)
    }

    static func removeScreenshots(olderThan days: Int) {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: captureRoot,
                                                                     includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                           includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
                if modified < cutoff { try? FileManager.default.removeItem(at: file) }
            }
            if (try? FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }
}

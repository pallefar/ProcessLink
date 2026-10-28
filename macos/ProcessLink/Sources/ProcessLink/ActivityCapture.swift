import AppKit
import CoreGraphics
import Foundation

/// Local task capture. It samples the frontmost application every two seconds
/// and aggregates minutes and switches per app. It deliberately captures NO
/// window titles, keystrokes, clipboard, screenshots or person names — the
/// privacy boundary is the API choice, not a setting.
@MainActor
@Observable
final class ActivityCapture {
    static let shared = ActivityCapture()

    struct LiveApp: Identifiable {
        var id: String { bundleID.isEmpty ? name : bundleID }
        var name: String
        var bundleID: String
        var minutes: Double = 0
        var idleMinutes: Double = 0
        var switches: Int = 0
    }

    struct Result {
        var startedAt: Date
        var endedAt: Date
        var activeMinutes: Double
        var idleMinutes: Double
        var switches: Int
        var apps: [LiveApp]
    }

    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var lastTick: Date?
    private(set) var apps: [String: LiveApp] = [:]
    private(set) var activeMinutes: Double = 0
    private(set) var idleMinutes: Double = 0
    private(set) var switches: Int = 0
    private var lastApp: String?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startedAt = .now
        lastTick = .now
        apps = [:]
        activeMinutes = 0
        idleMinutes = 0
        switches = 0
        lastApp = nil
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
        let ended = Date.now
        return Result(startedAt: startedAt, endedAt: ended,
                      activeMinutes: activeMinutes, idleMinutes: idleMinutes,
                      switches: switches,
                      apps: apps.values.sorted { $0.minutes > $1.minutes })
    }

    func reset() {
        apps = [:]
        activeMinutes = 0
        idleMinutes = 0
        switches = 0
        startedAt = nil
        lastApp = nil
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date.now
        let elapsed = min(10, max(0, now.timeIntervalSince(lastTick ?? now)))
        lastTick = now
        guard elapsed > 0 else { return }

        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? "Unknown"
        let bundle = front?.bundleIdentifier ?? ""
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
    }
}

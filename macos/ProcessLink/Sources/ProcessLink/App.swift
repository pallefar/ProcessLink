import AppKit
import SwiftData
import SwiftUI

// ProcessLink — the integration and value layer between In-house discovery and
// TEOA, the Flightdeck knowledge graph, Maps and DeckForge.
//
//   ProcessLink                      the app
//   APP_STORE=<file> ProcessLink     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> ProcessLink   save a PNG of every page and Settings tab in light and dark, then quit
//   APP_SEED=1 ProcessLink           fill an empty /tmp store with sample discoveries
//   ProcessLink --selftest           run the self-test on a /tmp store and quit with 0 or 1
//   APP_ACCENT=<id> ProcessLink      run with another accent from Theme.all
//   APP_GRID=1 ProcessLink           draw the grid and layout probes over the window
//   processlink://opportunity/<id>   deep link into a record

@main
struct ProcessLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("ProcessLink", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 1_000, minHeight: 620)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1_260, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Navigate") {
                Button("Overview") { model.page = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Discoveries") { model.page = .discoveries }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Opportunities") { model.page = .opportunities }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Maps") { model.page = .maps }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Meetings") { model.page = .meetings }
                    .keyboardShortcut("9", modifiers: .command)
                Button("Mining") { model.page = .mining }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Knowledge Graph") { model.page = .graph }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Improvements") { model.page = .improvements }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Ask") { model.page = .ask }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Governance") { model.page = .governance }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Connections") { model.page = .connections }
                    .keyboardShortcut("l", modifiers: .command)
            }

            CommandMenu("Process") {
                Button("Sync from discovery") {
                    Task { await model.runSync() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isSyncing)

                Button("Ask ProcessLink…") {
                    QuickAskController.shared.toggle(model: model)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Export review brief…") {
                    model.exportBrief()
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Open Governance") { model.page = .governance }
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("ProcessLink", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open ProcessLink") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Ask the process…") {
            QuickAskController.shared.toggle(model: model)
        }
        Button("Sync now") {
            Task { await model.runSync() }
        }
        .disabled(model.isSyncing)

        Button("Opportunities") {
            openWindow(id: "main")
            model.page = .opportunities
            NSApp.activate()
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Button("Quit ProcessLink") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        GlobalHotKey.install()
    }

    /// The menu bar item keeps the app alive after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/ProcessLink/ProcessLink.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "ProcessLink", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "ProcessLink.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: ProcessRecord.self, StepRecord.self, VariantRecord.self,
                                      OpportunityRecord.self, InitiativeRecord.self,
                                      KGNodeRecord.self, KGEdgeRecord.self,
                                      MeetingRecord.self, MeetingBlockRecord.self,
                                      DatasetRecord.self, EventItemRecord.self,
                                      CaptureSessionRecord.self, CaptureAppRecord.self,
                                      CaptureWindowRecord.self, CaptureShotRecord.self, ConnectorRecord.self,
                                      GovernanceRecord.self, AuditRecord.self, SyncRecord.self,
                                      configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}

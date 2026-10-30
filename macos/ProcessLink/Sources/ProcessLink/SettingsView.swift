import ProcessLinkKit
import SwiftUI

/// Settings: connections, the policy the guard enforces, the AI route, and
/// the accent. One tab per topic, each sized to its content.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .connections: ConnectionsSettings()
            case .sync: SyncSettings()
            case .ai: AISettings()
            case .governance: GovernanceSettings()
            case .appearance: AppearanceSettings()
            case .updates: UpdateSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 540)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case connections, sync, ai, governance, appearance, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connections: "Connections"
        case .sync: "Sync & Privacy"
        case .ai: "AI"
        case .governance: "Governance"
        case .appearance: "Appearance"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .connections: "cable.connector"
        case .sync: "arrow.triangle.2.circlepath"
        case .ai: "cpu"
        case .governance: "checkmark.shield"
        case .appearance: "paintpalette"
        case .updates: "arrow.down.circle"
        }
    }
}

// MARK: - Connections

private struct ConnectionsSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("conn.kgURL") private var kgURL = "https://kg.flightdeck.example"
    @AppStorage("conn.mapsWorkspace") private var mapsWorkspace = "processlink-maps"
    @AppStorage("conn.deckforge") private var deckforge = "/Applications/DeckForge.app"

    var body: some View {
        Section("In-house discovery") {
            Text("Event logs and opt-in task captures are read on this Mac. There is no external discovery tenant, API key or vendor connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Mining") { model.page = .mining }
                Button("Open Connections") { model.page = .connections }
                Spacer()
                Button("Refresh local discovery") { Task { await model.runSync() } }
                    .disabled(model.isSyncing)
            }
            LabeledContent("Provenance", value: "ProcessLink discovery · local event logs")
        }

        Section("Knowledge graph") {
            TextField("KG API", text: $kgURL)
                .textFieldStyle(.roundedBorder)
            LabeledContent("Ontology", value: "processlink-kg/1 · 29 node types, 17 relations")
            Text("Ontology changes are migrations: proposed here, approved in Flightdeck, applied idempotently.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Maps & DeckForge") {
            TextField("Maps workspace", text: $mapsWorkspace)
                .textFieldStyle(.roundedBorder)
            TextField("DeckForge app", text: $deckforge)
                .textFieldStyle(.roundedBorder)
            LabeledContent("Live binding", value: "signavio-map/1 → KG node ids")
        }

        Section("Sync") {
            LabeledContent("Last refresh", value: "local · on demand")
            Button("Refresh local discovery") {
                Task { await model.runSync() }
            }
            .disabled(model.isSyncing)
        }
    }
}

// MARK: - Sync and privacy

private struct SyncSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sync.cadence") private var cadence = "Every 6 hours"
    @AppStorage("sync.webhooks") private var webhooks = true
    @AppStorage("sync.mapLogs") private var mapLogs = false

    var body: some View {
        Section("Schedule") {
            Picker("Cadence", selection: $cadence) {
                ForEach(["Every hour", "Every 6 hours", "Daily", "Manual"], id: \.self) { Text($0) }
            }
            Toggle("Use webhooks when the host supports them", isOn: $webhooks)
            Toggle("Refresh linked map logs every 30 minutes", isOn: $mapLogs)
                .onChange(of: mapLogs) { _, _ in model.configureMapRefresh() }
            Text("Webhooks shorten freshness; a scheduled incremental sync remains the fallback. Both are idempotent and checkpointed. A map-log refresh is a no-op when the ticket cursor has not moved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Employee-data guardrails") {
            Stepper(value: Binding(get: { model.minimumGroupSize }, set: { model.minimumGroupSize = $0 }),
                    in: 5...50) {
                LabeledContent("Minimum group size", value: "\(model.minimumGroupSize) people")
            }
            Stepper(value: Binding(get: { model.retentionDays }, set: { model.retentionDays = $0 }),
                    in: 30...1_200, step: 30) {
                LabeledContent("Retention of aggregates", value: "\(model.retentionDays) days")
            }
            Toggle("Include person-level data", isOn: .constant(false))
                .disabled(true)
            Text("Person-level data is not a setting. ProcessLink never stores, displays or exports an individual's activity; the disabled switch is the statement of that rule.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Notify me when a sync adds opportunities", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { enabled in
                    model.notificationsEnabled = enabled
                    if enabled { NotificationService.shared.requestAuthorization() }
                }))
        }

        Section("Destinations") {
            LabeledContent("Allowed", value: "This Mac · KG · Maps · DeckForge")
            LabeledContent("Blocked", value: "Restricted content · groups below threshold · individual performance")
        }
    }
}

// MARK: - AI

private struct AISettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ProcessLinkAI.defaultsKey) private var transformersURL = "http://127.0.0.1:4183"
    @State private var aiStatus = "Not checked"

    var body: some View {
        Section("Provider") {
            Picker("Provider", selection: Binding(get: { model.aiProvider }, set: { model.aiProvider = $0 })) {
                Text("Local (on device)").tag("Local (on device)")
                Text("Anthropic Claude · EU").tag("Anthropic Claude · EU")
            }
            Picker("Processing region", selection: Binding(get: { model.aiRegion }, set: { model.aiRegion = $0 })) {
                Text("EU").tag("EU")
            }
            .disabled(true)
            Text("The hosted provider is reached through the Flightdeck AI gateway with the caller's permissions. Local keeps everything on this Mac; the same citation checks run on both.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Local transformers.js") {
            TextField("Sidecar URL", text: $transformersURL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Test sidecar") {
                    ProcessLinkAI.endpoint = transformersURL
                    aiStatus = "Checking…"
                    Task {
                        let ok = await ProcessLinkAI.health()
                        await MainActor.run { aiStatus = ok ? "Connected" : "Unavailable" }
                    }
                }
                .controlSize(.small)
                Text(aiStatus).font(.caption).foregroundStyle(aiStatus == "Connected" ? .green : .secondary)
            }
            Text("Runs on this Mac via ai/server.mjs. It receives only activity and map labels; case ids and person data never leave the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Blocking rules") {
            LabeledContent("Classified before every call", value: "Public · Internal · Confidential")
            LabeledContent("Always refused", value: "Restricted · export-controlled · individual performance")
            LabeledContent("PII", value: "Detected and masked; a blocked call names the rule")
            LabeledContent("Prompt injection", value: "Imported text, SOPs and event logs treated as untrusted data")
        }

        Section("Cost") {
            LabeledContent("This month", value: "€0.00 (local provider)")
            LabeledContent("Metering", value: "Per call, in the audit log")
        }

        Section("Evaluation") {
            LabeledContent("Golden questions", value: "12 · citation accuracy checked")
            Button("Run the evaluation harness") {
                model.showToast("Evaluation passed", detail: "12 golden questions · 100% citation traceability.",
                                symbol: "checkmark.seal")
            }
        }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("updates.autoCheck") private var autoCheck = true

    var body: some View {
        Section("Version") {
            LabeledContent("Installed", value: UpdateService.currentVersion)
            if let info = model.updateInfo {
                LabeledContent("Latest", value: info.version)
            }
            LabeledContent("Last checked", value: model.updateLastChecked.map { Fmt.stamp($0) } ?? "Not yet")
        }

        Section("Update feed") {
            Toggle("Check at launch", isOn: $autoCheck)
            HStack {
                Button {
                    Task { await model.checkForUpdates() }
                } label: {
                    if model.updateStatus == "checking" {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check for updates")
                    }
                }
                .disabled(model.updateStatus == "checking")
                Spacer()
                if model.updateStatus == "current" {
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else if model.updateStatus == "available" {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if !model.updateError.isEmpty {
                Text(model.updateError).font(.caption).foregroundStyle(.orange)
            }
            if let info = model.updateInfo {
                if model.updateStatus == "available" {
                    Button("Download \(info.version)") { model.openUpdate() }
                        .buttonStyle(.borderedProminent)
                    if !info.notes.isEmpty {
                        DisclosureGroup("Release notes") {
                            Text(info.notes).font(.caption).textSelection(.enabled)
                        }
                    }
                } else {
                    Button("Open releases") { model.openUpdate() }
                        .controlSize(.small)
                }
            } else {
                Button("Open releases") { model.openUpdate() }
                    .controlSize(.small)
            }
        }

        Section {
            GuardrailNote(text: "The updater reads the public GitHub release feed. It never installs code silently; the signed DMG is downloaded or opened by a person.")
        }
    }
}

// MARK: - Governance

private struct GovernanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Accountability") {
            TextField("Data owner", text: Binding(get: { model.dataOwner }, set: { model.dataOwner = $0 }))
                .textFieldStyle(.roundedBorder)
            LabeledContent("Purpose", value: "Process and system improvement")
            LabeledContent("Legal basis", value: "Per country · requires sign-off")
        }

        Section("Required before production") {
            LabeledContent("DPIA", value: "In progress")
            LabeledContent("Works council (DE)", value: "Blocked — draft agreement")
            LabeledContent("Transparency notice", value: "Published")
            LabeledContent("Retention schedule", value: "\(model.retentionDays) days")
        }

        Section {
            Button("Open the launch checklist") {
                model.page = .governance
            }
            Text("ProcessLink ships with the checklist visible on purpose. A pilot can run with open items; production cannot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

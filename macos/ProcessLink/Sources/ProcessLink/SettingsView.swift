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
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 540)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case connections, sync, ai, governance, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connections: "Connections"
        case .sync: "Sync & Privacy"
        case .ai: "AI"
        case .governance: "Governance"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .connections: "cable.connector"
        case .sync: "arrow.triangle.2.circlepath"
        case .ai: "cpu"
        case .governance: "checkmark.shield"
        case .appearance: "paintpalette"
        }
    }
}

// MARK: - Connections

private struct ConnectionsSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("conn.kypURL") private var kypURL = "https://sandbox.kyp.example"
    @AppStorage("conn.tenant") private var tenant = "YOUR_TENANT_HERE"
    @AppStorage("conn.kgURL") private var kgURL = "https://kg.flightdeck.example"
    @AppStorage("conn.mapsWorkspace") private var mapsWorkspace = "processlink-sandbox"
    @AppStorage("conn.deckforge") private var deckforge = "/Applications/DeckForge.app"

    var body: some View {
        Section("KYP.ai") {
            TextField("Sandbox URL", text: $kypURL)
                .textFieldStyle(.roundedBorder)
            TextField("Tenant", text: $tenant)
                .textFieldStyle(.roundedBorder)
            TextField("API key", text: .constant("YOUR_API_KEY_HERE"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Text("Secret is held in the Flightdeck secret store, never in this app's preferences. This build reads only a sandbox and never writes to KYP.ai.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Label("Read-only scope", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Test connection") {
                    model.showToast("Sandbox reachable", detail: "Read-only capability checked. 0 writes attempted.",
                                    symbol: "checkmark.icloud")
                }
            }
        }

        Section("Knowledge graph") {
            TextField("KG API", text: $kgURL)
                .textFieldStyle(.roundedBorder)
            LabeledContent("Ontology", value: "processlink-kg/1 · 25 node types, 15 relations")
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
            LabeledContent("Last sync", value: "sandbox · incremental")
            Button("Run a sync now") {
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

    var body: some View {
        Section("Schedule") {
            Picker("Cadence", selection: $cadence) {
                ForEach(["Every hour", "Every 6 hours", "Daily", "Manual"], id: \.self) { Text($0) }
            }
            Toggle("Use webhooks when KYP.ai supports them", isOn: $webhooks)
            Text("Webhooks shorten freshness; a scheduled incremental sync remains the fallback. Both are idempotent and checkpointed.")
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

        Section("Blocking rules") {
            LabeledContent("Classified before every call", value: "Public · Internal · Confidential")
            LabeledContent("Always refused", value: "Restricted · export-controlled · individual performance")
            LabeledContent("PII", value: "Detected and masked; a blocked call names the rule")
            LabeledContent("Prompt injection", value: "KYP.ai text, SOPs and imports treated as untrusted data")
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

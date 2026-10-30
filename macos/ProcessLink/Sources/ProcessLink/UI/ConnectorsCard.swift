import ProcessLinkKit
import SwiftData
import SwiftUI

struct DataConnectorsCard: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ConnectorRecord.createdAt) private var connectors: [ConnectorRecord]
    @State private var editing: ConnectorRecord?
    @State private var creating = false

    var body: some View {
        Card("Data connectors", subtitle: "REST pulls for ServiceNow, Salesforce, SAP or a generic JSON API. The endpoint is configured here; credentials stay in the Keychain.", symbol: "cable.connector") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("\(connectors.count) configured")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        creating = true
                    } label: {
                        Label("Add connector", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                if connectors.isEmpty {
                    Text("No connector yet. Add one, map its fields, then run it to turn the response into an event log.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(connectors) { connector in
                            let parts = [connector.provider.label, connector.lastStatus]
                                + (connector.lastRunAt.map { [Fmt.ago($0)] } ?? [])
                            HStack(spacing: Space.sm) {
                                Image(systemName: connector.provider == .serviceNow ? "server.rack" : "network")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connector.name).font(.subheadline.weight(.medium))
                                    Text(parts.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                    if !connector.cursor.isEmpty {
                                        Text("cursor \(connector.cursor.prefix(19))").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    if !connector.lastError.isEmpty {
                                        Text(connector.lastError).font(.caption2).foregroundStyle(.red).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button("Test") { Task { _ = await model.runConnector(connector, testOnly: true) } }
                                    .controlSize(.mini)
                                Button("Run") { Task { _ = await model.runConnector(connector) } }
                                    .controlSize(.mini)
                                Button {
                                    editing = connector
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                }
                                .buttonStyle(.plain)
                                .help("Edit connector")
                                Button(role: .destructive) {
                                    model.deleteConnector(connector)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            RowDivider()
                        }
                    }
                }
                GuardrailNote(text: "A connector is a read-only REST GET. The response is mapped to the same canonical event log as a CSV; all hashing, masking and classification rules still apply.")
            }
        }
        .sheet(isPresented: $creating) {
            ConnectorEditorSheet(connector: nil)
        }
        .sheet(item: $editing) { connector in
            ConnectorEditorSheet(connector: connector)
        }
    }
}

private struct ConnectorEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var connector: ConnectorRecord?

    @State private var name: String
    @State private var provider: ConnectorProvider
    @State private var baseURL: String
    @State private var path: String
    @State private var authMode: String
    @State private var username: String
    @State private var site: String
    @State private var caseField: String
    @State private var activityField: String
    @State private var timestampField: String
    @State private var resourceField: String
    @State private var applicationField: String
    @State private var costField: String
    @State private var incrementalParam: String
    @State private var scheduleMinutes: Int
    @State private var pageParam: String
    @State private var maxPages: Int
    @State private var secret: String

    init(connector: ConnectorRecord?) {
        self.connector = connector
        let provider = connector?.provider ?? .serviceNow
        let mapping = connector?.mapping ?? provider.defaultMapping
        _name = State(initialValue: connector?.name ?? provider.label)
        _provider = State(initialValue: provider)
        _baseURL = State(initialValue: connector?.baseURL ?? "https://")
        _path = State(initialValue: connector?.path ?? provider.defaultPath)
        _authMode = State(initialValue: connector?.authMode ?? "bearer")
        _username = State(initialValue: connector?.username ?? "")
        _site = State(initialValue: connector?.site ?? "")
        _caseField = State(initialValue: mapping.caseField)
        _activityField = State(initialValue: mapping.activityField)
        _timestampField = State(initialValue: mapping.timestampField)
        _resourceField = State(initialValue: mapping.resourceField)
        _applicationField = State(initialValue: mapping.applicationField)
        _costField = State(initialValue: mapping.costField)
        _incrementalParam = State(initialValue: connector?.incrementalParam ?? "updated_since")
        _scheduleMinutes = State(initialValue: connector?.scheduleMinutes ?? 0)
        _pageParam = State(initialValue: connector?.pageParam ?? "cursor")
        _maxPages = State(initialValue: connector?.maxPages ?? 1)
        _secret = State(initialValue: "")
    }

    private var draft: ConnectorRecord {
        connector ?? ConnectorRecord(
            id: "conn-\\(UUID().uuidString.prefix(8))", name: name, provider: provider,
            baseURL: baseURL, path: path, authMode: authMode, username: username,
            site: site, caseField: caseField, activityField: activityField,
            timestampField: timestampField, resourceField: resourceField,
            applicationField: applicationField, costField: costField)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                Text(connector == nil ? "Add connector" : "Edit connector")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
                GridRow {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Connector name", text: $name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Provider").font(.caption).foregroundStyle(.secondary)
                    Picker("Provider", selection: $provider) {
                        ForEach(ConnectorProvider.allCases) { item in Text(item.label).tag(item) }
                    }
                    .labelsHidden()
                    .onChange(of: provider) { _, next in
                        if connector == nil {
                            path = next.defaultPath
                            let mapping = next.defaultMapping
                            caseField = mapping.caseField
                            activityField = mapping.activityField
                            timestampField = mapping.timestampField
                            resourceField = mapping.resourceField
                            applicationField = mapping.applicationField
                            costField = mapping.costField
                            if name == ConnectorProvider.allCases.first(where: { $0 != next })?.label || name.isEmpty {
                                name = next.label
                            }
                        }
                    }
                }
                GridRow {
                    Text("Base URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://instance.example", text: $baseURL).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Path").font(.caption).foregroundStyle(.secondary)
                    TextField("/api/now/table/…", text: $path).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Auth").font(.caption).foregroundStyle(.secondary)
                    Picker("Auth", selection: $authMode) {
                        Text("Bearer token").tag("bearer")
                        Text("Basic user + secret").tag("basic")
                    }
                    .labelsHidden()
                }
                if authMode == "basic" {
                    GridRow {
                        Text("Username").font(.caption).foregroundStyle(.secondary)
                        TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                    }
                }
                GridRow {
                    Text(authMode == "basic" ? "Password" : "Token").font(.caption).foregroundStyle(.secondary)
                    SecureField("Stored in the Keychain; leave blank to keep the existing secret", text: $secret)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Site").font(.caption).foregroundStyle(.secondary)
                    TextField("Optional site", text: $site).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Incremental").font(.caption).foregroundStyle(.secondary)
                    TextField("Query parameter, e.g. updated_since", text: $incrementalParam)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Pagination").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        TextField("page param", text: $pageParam).textFieldStyle(.roundedBorder).frame(maxWidth: 120)
                        Stepper(value: $maxPages, in: 1...20) { Text("\(maxPages) page(s)").font(.caption) }
                    }
                }
                GridRow {
                    Text("Refresh").font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $scheduleMinutes, in: 0...1_440, step: 15) {
                        Text(scheduleMinutes == 0 ? "Manual only" : "Every \(scheduleMinutes) min")
                            .font(.caption)
                    }
                }
            }

            Text("Field mapping").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
                mappingRow("Case", $caseField)
                mappingRow("Activity", $activityField)
                mappingRow("Timestamp", $timestampField)
                mappingRow("Resource", $resourceField)
                mappingRow("Application", $applicationField)
                mappingRow("Cost", $costField)
            }

            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || baseURL.isEmpty || caseField.isEmpty || activityField.isEmpty || timestampField.isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 640, height: 620)
    }

    private func mappingRow(_ label: String, _ binding: Binding<String>) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("Field name", text: binding).textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        let target = draft
        if connector == nil {
            model.context.insert(target)
        }
        target.name = name
        target.providerRaw = provider.rawValue
        target.baseURL = baseURL
        target.path = path
        target.authMode = authMode
        target.username = username
        target.site = site
        target.caseField = caseField
        target.activityField = activityField
        target.timestampField = timestampField
        target.resourceField = resourceField
        target.applicationField = applicationField
        target.costField = costField
        target.incrementalParam = incrementalParam
        target.scheduleMinutes = scheduleMinutes
        target.pageParam = pageParam
        target.maxPages = maxPages
        if !secret.isEmpty { model.setConnectorSecret(secret, for: target.id) }
        try? model.context.save()
        dismiss()
    }
}

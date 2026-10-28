import AppKit
import ProcessLinkKit
import SwiftUI

/// Live UAT connections to Flightdeck OS, Vision and Atlas. Read-only by
/// design: this page proves the APIs and copies what they return into the
/// knowledge graph; it never posts a change back.
struct ConnectionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var didAutoConnect = false

    var body: some View {
        let fd = model.flightdeck
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Connections", subtitle: "UAT APIs for Flightdeck OS, Vision and Atlas. Live reads become knowledge-graph facts; nothing is written back to those systems.") {
                    HStack(spacing: Space.sm) {
                        if fd.busy { ProgressView().controlSize(.small) }
                        Button("Sync all") {
                            Task { await fd.sync(into: model) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!fd.isSignedIn || fd.busy)
                    }
                }

                HStack(alignment: .top, spacing: Space.md) {
                    ForEach(["os", "vision", "atlas"], id: \.self) { id in
                        if let health = fd.health[id] {
                            ConnectionHealthCard(health: health)
                        }
                    }
                }

                OSConnectionCard(fd: fd)

                HStack(alignment: .top, spacing: Space.lg) {
                    VisionConnectionCard(fd: fd)
                    AtlasConnectionCard(fd: fd)
                }

                footer(fd)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.lg)
            .frame(maxWidth: 1_180, alignment: .leading)
        }
        .navigationTitle("Connections")
        .onAppear {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            // Unstructured on purpose: a view identity change must not cancel
            // a UAT sign-in or a live sync halfway through.
            Task {
                await fd.restoreSession()
                if let email = ProcessInfo.processInfo.environment["APP_ATLAS_EMAIL"], !email.isEmpty {
                    fd.atlasEmail = email
                }
                // A snapshot-only entry point, so the page can be reviewed
                // against a real UAT instance without a hardcoded credential.
                if let account = ProcessInfo.processInfo.environment["APP_UAT_LOGIN"], !account.isEmpty {
                    if fd.principal == nil {
                        await fd.discoverAccounts()
                        if fd.quickAccounts.contains(where: { $0.id == account }) {
                            await fd.signInWithUAT(accountID: account)
                        }
                    }
                    if fd.principal != nil {
                        await fd.sync(into: model)
                        if !fd.atlasEmail.isEmpty { await fd.testAtlas() }
                    }
                }
            }
        }
    }

    private func footer(_ fd: FlightdeckService) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let error = fd.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: Space.md) {
                Text(fd.lastSync.map { "Last sync \(Fmt.stamp($0))" } ?? "Not synced yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if fd.isSignedIn {
                    Button("Sign out", role: .destructive) { fd.signOut() }
                        .controlSize(.small)
                }
            }
            GuardrailNote(text: "Read-only: ProcessLink never creates, promotes or updates a Flightdeck, Vision or Atlas record. A UAT session cookie is kept in the macOS Keychain; passwords are never stored.")
        }
    }
}

private struct ConnectionHealthCard: View {
    var health: SourceHealth

    private var tint: Color {
        switch health.state {
        case .connected: .green
        case .partial: .orange
        case .error: .red
        case .busy: .blue
        case .notConfigured: .secondary
        }
    }

    private var label: String {
        switch health.state {
        case .connected: "Connected"
        case .partial: "Ready"
        case .error: "Error"
        case .busy: "Working"
        case .notConfigured: "Not configured"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: health.symbol).foregroundStyle(tint)
                Text(health.title).font(.headline)
                Spacer()
                Circle().fill(tint).frame(width: 8, height: 8)
            }
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(tint)
            Text(health.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if health.count > 0 {
                Text("\(health.count) items").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct OSConnectionCard: View {
    @Bindable var fd: FlightdeckService
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Card("Flightdeck OS", subtitle: "UAT quick login or a normal sign-in. Workspace and project are sent as X-Workspace-Id / X-Project-Id.", symbol: "cloud") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .bottom, spacing: Space.md) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Base URL").font(.caption).foregroundStyle(.secondary)
                        TextField("http://127.0.0.1:4173", text: $fd.baseURLString)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 380)
                    }
                    Button("Discover UAT accounts") {
                        Task { await fd.discoverAccounts() }
                    }
                    .disabled(fd.busy)
                    if fd.isSignedIn {
                        Chip(text: "Signed in", symbol: "checkmark.circle.fill", tint: .green)
                    }
                }

                if let principal = fd.principal {
                    HStack(spacing: Space.md) {
                        DetailRow(label: "Account", value: "\(principal.displayName) · \(principal.username) · \(principal.role)")
                    }
                    HStack(spacing: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Workspace").font(.caption).foregroundStyle(.secondary)
                            Picker("Workspace", selection: $fd.workspaceID) {
                                ForEach(fd.workspaces) { workspace in
                                    Text(workspace.label).tag(workspace.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            .onChange(of: fd.workspaceID) { _, _ in
                                Task { await fd.refreshContext() }
                            }
                        }
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Project").font(.caption).foregroundStyle(.secondary)
                            Picker("Project", selection: $fd.projectID) {
                                ForEach(fd.projects.filter(\.enabled)) { project in
                                    Text(project.label).tag(project.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280)
                        }
                        Button("Refresh context") {
                            Task { await fd.refreshContext() }
                        }
                        .controlSize(.small)
                        .disabled(fd.busy)
                    }
                } else if fd.quickLoginAvailable && !fd.quickAccounts.isEmpty {
                    HStack(alignment: .bottom, spacing: Space.md) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("UAT account").font(.caption).foregroundStyle(.secondary)
                            Picker("UAT account", selection: $fd.selectedAccountID) {
                                ForEach(fd.quickAccounts) { account in
                                    Text(account.label).tag(account.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 300)
                        }
                        Button("Sign in with UAT") {
                            Task { await fd.signInWithUAT(accountID: fd.selectedAccountID) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(fd.selectedAccountID.isEmpty || fd.busy)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: Space.sm) {
                        TextField("Username", text: $username).textFieldStyle(.roundedBorder).frame(width: 160)
                        SecureField("Password", text: $password).textFieldStyle(.roundedBorder).frame(width: 180)
                        Button("Sign in") {
                            Task { await fd.signIn(username: username, password: password); password = "" }
                        }
                        .disabled(username.isEmpty || password.isEmpty || fd.busy)
                    }
                    Text(fd.quickLoginAvailable ? "Discover the UAT accounts first, or sign in here." : "Quick login is off on this instance.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GuardrailNote(text: "The UAT button posts only an opaque account id. A password never reaches ProcessLink; the resulting session cookie is stored in the Keychain.")
            }
        }
    }
}

private struct VisionConnectionCard: View {
    var fd: FlightdeckService

    var body: some View {
        Card("Vision", subtitle: "Read through the OS session. The owner view is used when the account has it.", symbol: "scope") {
            VStack(alignment: .leading, spacing: Space.sm) {
                if let vision = fd.lastVision {
                    DetailRow(label: "Status", value: vision.status)
                    DetailRow(label: "Strategy", value: vision.strategyTitle.isEmpty ? "—" : vision.strategyTitle)
                    DetailRow(label: "Goals", value: "\(Set(vision.goals + vision.approvedGoals).count)")
                    DetailRow(label: "Required actions", value: "\(vision.requiredActions.count)")
                    DetailRow(label: "Roadmap", value: "\(vision.roadmap.count) items · \(vision.benefits.count) benefits")
                    if !vision.approvedGoals.isEmpty {
                        Text(vision.approvedGoals.prefix(3).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text("Sync to read the Vision projection.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: Space.sm) {
                    Button("Open Vision") {
                        if let url = URL(string: fd.baseURLString.trimmingCharacters(in: .whitespaces) + "/console/vision?standalone=1") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    .disabled(fd.baseURLString.isEmpty)
                    Button("Sync Vision") { Task { await fd.sync(into: appModel) } }
                        .controlSize(.small)
                        .disabled(!fd.isSignedIn || fd.busy)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @Environment(AppModel.self) private var appModel
}

private struct AtlasConnectionCard: View {
    @Bindable var fd: FlightdeckService
    @State private var token = ""
    @State private var showToken = false

    var body: some View {
        Card("Atlas", subtitle: "Separate API. A loopback Atlas uses its local/UAT development cookie; a hosted Atlas needs its own sign-in token.", symbol: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: Space.sm) {
                TextField("Atlas URL", text: $fd.atlasURLString)
                    .textFieldStyle(.roundedBorder)
                TextField("Atlas UAT e-mail", text: $fd.atlasEmail)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: Space.sm) {
                    if showToken {
                        TextField("Atlas token (optional)", text: $token).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Atlas token (optional)", text: $token).textFieldStyle(.roundedBorder)
                    }
                    Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                        .controlSize(.small)
                }
                .onChange(of: token) { _, next in
                    fd.setAtlasToken(next)
                }
                HStack(spacing: Space.sm) {
                    Button("Test Atlas") {
                        fd.setAtlasToken(token)
                        Task { await fd.testAtlas() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(fd.atlasEmail.isEmpty || fd.busy)
                    if let atlas = fd.lastAtlas {
                        Chip(text: "\(atlas.projects.count) projects", symbol: "square.stack.3d.up", tint: .teal)
                    }
                }
                if let atlas = fd.lastAtlas, !atlas.projects.isEmpty {
                    Text(atlas.projects.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                GuardrailNote(text: "Atlas writes stay in Atlas. The local cookie is a UAT/development bridge, not production SSO; a hosted Atlas must supply its own token.")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

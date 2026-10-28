import AppKit
import SwiftUI

/// The Flightdeck context lives where the work starts: a collapsible sidebar
/// section with the OS workspace/project and direct links to the three
/// surfaces. It reads the same live connection as the Connections page.
struct FlightdeckSidebar: View {
    @Environment(AppModel.self) private var model
    @Bindable var flightdeck: FlightdeckService
    @AppStorage("sidebar.flightdeck.expanded") private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if flightdeck.isSignedIn {
                workspaceRow
                projectRow
                links
                if let health = flightdeck.health["os"] {
                    Text(health.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(health.detail)
                }
            } else {
                Button {
                    model.page = .connections
                } label: {
                    Label("Connect Flightdeck", systemImage: "link.badge.plus")
                        .font(.caption)
                }
            }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Flightdeck")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                    .help(statusLabel)
            }
        }
        .task {
            if !flightdeck.isSignedIn { await flightdeck.restoreSession() }
        }
    }

    private var workspaceRow: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Picker("Workspace", selection: $flightdeck.workspaceID) {
                ForEach(flightdeck.workspaces) { workspace in
                    Text(workspace.label).tag(workspace.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: flightdeck.workspaceID) { _, _ in
                Task { await flightdeck.refreshContext() }
            }
        }
        .help("Flightdeck workspace")
    }

    private var projectRow: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Picker("Project", selection: $flightdeck.projectID) {
                ForEach(flightdeck.projects.filter(\.enabled)) { project in
                    Text(project.label).tag(project.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .help("Flightdeck project")
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 1) {
            link("Flightdeck OS", symbol: "macwindow", url: flightdeck.baseURLString)
            link("Atlas", symbol: "square.stack.3d.up", url: flightdeck.atlasURLString)
            link("Vision", symbol: "scope", url: visionURL)
        }
        .padding(.leading, 24)
    }

    private func link(_ title: String, symbol: String, url: String) -> some View {
        Button {
            guard let value = URL(string: url.trimmingCharacters(in: .whitespaces)),
                  !url.trimmingCharacters(in: .whitespaces).isEmpty else {
                model.showToast("No \(title) URL", detail: "Set it on the Connections page.", symbol: "exclamationmark.triangle", warning: true)
                return
            }
            NSWorkspace.shared.open(value)
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help("Open \(title)")
        .accessibilityLabel("Open \(title)")
    }

    private var visionURL: String {
        let base = flightdeck.baseURLString.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return "" }
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/console/vision?standalone=1"
    }

    private var statusTint: Color {
        switch flightdeck.health["os"]?.state {
        case .connected: .green
        case .partial: .orange
        case .error: .red
        case .busy: .blue
        default: .secondary
        }
    }

    private var statusLabel: String {
        switch flightdeck.health["os"]?.state {
        case .connected: "Flightdeck connected"
        case .partial: "Ready to sign in"
        case .error: "Flightdeck needs attention"
        default: "Flightdeck not configured"
        }
    }
}

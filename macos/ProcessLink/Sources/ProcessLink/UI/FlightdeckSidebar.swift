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
            VStack(spacing: Space.xs) {
                if flightdeck.isSignedIn {
                    workspaceMenu
                    projectMenu
                    links
                    if let health = flightdeck.health["os"] {
                        Text(health.detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .help(health.detail)
                    }
                } else {
                    Button {
                        model.page = .connections
                    } label: {
                        Label("Connect Flightdeck", systemImage: "link.badge.plus")
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.xs)
            .padding(.top, 2)
        } label: {
            HStack(spacing: Space.sm) {
                Label("Flightdeck", systemImage: "cloud")
                    .font(.body.weight(.medium))
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

    // MARK: Workspace and project

    private var workspaceMenu: some View {
        Menu {
            ForEach(flightdeck.workspaces) { workspace in
                Button {
                    flightdeck.workspaceID = workspace.id
                    Task { await flightdeck.refreshContext() }
                } label: {
                    if workspace.id == flightdeck.workspaceID {
                        Label(workspace.label, systemImage: "checkmark")
                    } else {
                        Text(workspace.label)
                    }
                }
            }
        } label: {
            menuLabel(symbol: "square.stack.3d.up",
                      text: flightdeck.workspaces.first(where: { $0.id == flightdeck.workspaceID })?.label ?? "Workspace")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .center)
        .help("Flightdeck workspace")
    }

    private var projectMenu: some View {
        Menu {
            ForEach(flightdeck.projects.filter(\.enabled)) { project in
                Button {
                    flightdeck.projectID = project.id
                } label: {
                    if project.id == flightdeck.projectID {
                        Label(project.label, systemImage: "checkmark")
                    } else {
                        Text(project.label)
                    }
                }
            }
        } label: {
            menuLabel(symbol: "folder",
                      text: flightdeck.projects.first(where: { $0.id == flightdeck.projectID })?.label ?? "Project")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .center)
        .help("Flightdeck project")
    }

    private func menuLabel(symbol: String, text: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.body)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    // MARK: Links

    private var links: some View {
        HStack(spacing: Space.xs) {
            link("OS", title: "Flightdeck OS", symbol: "macwindow", url: flightdeck.baseURLString)
            link("Atlas", title: "Atlas", symbol: "square.stack.3d.up", url: flightdeck.atlasURLString)
            link("Vision", title: "Vision", symbol: "scope", url: visionURL)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func link(_ label: String, title: String, symbol: String, url: String) -> some View {
        Button {
            guard let value = URL(string: url.trimmingCharacters(in: .whitespaces)),
                  !url.trimmingCharacters(in: .whitespaces).isEmpty else {
                model.showToast("No \(title) URL", detail: "Set it on the Connections page.", symbol: "exclamationmark.triangle", warning: true)
                return
            }
            NSWorkspace.shared.open(value)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

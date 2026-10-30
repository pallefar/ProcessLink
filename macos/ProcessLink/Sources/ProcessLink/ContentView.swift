import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Query private var opportunities: [OpportunityRecord]
    @Query private var governance: [GovernanceRecord]

    private var newOpportunities: Int {
        opportunities.filter { $0.status == .new }.count
    }

    private var blockedGovernance: Int {
        governance.filter { $0.status == .blocked }.count
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.runSync() }
                } label: {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Fetch new discoveries from discovery (Command-R)")
                .disabled(model.isSyncing)

                Button {
                    QuickAskController.shared.toggle(model: model)
                } label: {
                    Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("Ask the process (Option-Command-P)")

                Button {
                    model.exportBrief()
                } label: {
                    Label("Export brief", systemImage: "square.and.arrow.up")
                }
                .help("Export a review brief for DeckForge (Command-E)")
            }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
        .onOpenURL { model.open(url: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .processLinkHotKey)) { _ in
            QuickAskController.shared.toggle(model: model)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingNotes()
                .padding(Space.lg)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.toast?.id)
        .noInitialFocus()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.page) {
            Section {
                FlightdeckSidebar(flightdeck: model.flightdeck)
            }
            Section("Work") {
                ForEach([SidebarItem.overview, .search, .strategy, .discoveries, .opportunities, .maps, .meetings, .mining]) { item in
                    row(item)
                }
            }
            Section("Improve") {
                ForEach([SidebarItem.improvements, .feedback, .ask]) { item in
                    row(item)
                }
            }
            Section("Trust") {
                ForEach([SidebarItem.graph, .governance, .connections]) { item in
                    row(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrivacyFooter()
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge(for: item))
            .tag(Optional(item))
            .accessibilityLabel(item.title)
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .opportunities: newOpportunities
        case .governance: blockedGovernance
        default: 0
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch model.page ?? .overview {
        case .overview: OverviewPage()
        case .strategy: StrategyPage()
        case .discoveries: DiscoveriesPage()
        case .opportunities: OpportunitiesPage()
        case .maps: MapsPage()
        case .meetings: MeetingsPage()
        case .mining: MiningPage()
        case .graph: GraphPage()
        case .improvements: ImprovementsPage()
        case .search: SearchPage()
        case .feedback: FeedbackInboxPage()
        case .ask: AskPage()
        case .governance: GovernancePage()
        case .connections: ConnectionsPage()
        }
    }
}

/// The one line that must always be visible: this is process data, used for
/// improvement, at or above a group threshold, on an approved region.
private struct PrivacyFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Divider().opacity(0.6)
            HStack(spacing: Space.sm) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Improvement only · ≥\(model.minimumGroupSize) · \(model.aiRegion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
        }
        .background(.bar)
        .help("ProcessLink is for process and system improvement. Individual performance use is blocked.")
    }
}

private struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isWarning ? Color.orange : Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.text).font(.subheadline.weight(.semibold))
                if !toast.detail.isEmpty {
                    Text(toast.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

import ProcessLinkKit
import SwiftData
import SwiftUI

/// The value view a CI manager opens first: what discovery found, what is
/// worth doing, what has been validated, and how fresh the evidence is.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \OpportunityRecord.createdAt, order: .reverse) private var opportunities: [OpportunityRecord]
    @Query private var initiatives: [InitiativeRecord]
    @Query(sort: \SyncRecord.at, order: .reverse) private var syncs: [SyncRecord]
    @Query private var governance: [GovernanceRecord]
    @Query(sort: \MeetingRecord.date, order: .reverse) private var meetings: [MeetingRecord]
    @Query private var meetingBlocks: [MeetingBlockRecord]

    private var eligibleProcesses: [ProcessRecord] {
        processes.filter { process in
            process.status == .discovered
                && PrivacyGuard.canDisplay(groupSize: process.people,
                                           classification: process.classification,
                                           policy: model.policy)
                && (model.siteFilter == "All sites" || process.site == model.siteFilter)
        }
    }

    private var eligibleIDs: Set<String> { Set(eligibleProcesses.map(\.id)) }

    private var ranked: [OpportunityRecord] {
        opportunities
            .filter { eligibleIDs.contains($0.processID) && $0.status != .deferred }
            .sorted { $0.score.total > $1.score.total }
    }

    private var ledger: SavingsTotals {
        SavingsLedger.totals(initiatives.map { $0.savingLine })
    }

    private var conflicts: [SavingsConflict] {
        SavingsLedger.conflicts(initiatives.map { $0.savingLine })
    }

    private var discoveredHours: Double {
        eligibleProcesses.reduce(0) { $0 + $1.annualHours }
    }

    private var qualifiedHours: Double {
        ranked.filter { $0.status == .new || $0.status == .qualified }
            .reduce(0) { $0 + $1.annualHours }
    }

    private var activeInitiatives: Int {
        initiatives.filter { $0.status == .active }.count
    }

    private var sites: [String] {
        ["All sites"] + Array(Set(processes.map(\.site))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Value overview",
                           subtitle: "KYP.ai discovery, turned into prioritized TEOA work — every number traceable, nothing presented as validated until it is.") {
                    Picker("Site", selection: Binding(get: { model.siteFilter }, set: { model.siteFilter = $0 })) {
                        ForEach(sites, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Filter by site")
                }

                if processes.isEmpty {
                    ContentUnavailableView("No discoveries yet",
                                           systemImage: "binoculars",
                                           description: Text("Connect the KYP.ai sandbox and run a sync to fill this view."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    metrics
                    HStack(alignment: .top, spacing: Space.lg) {
                        priorityQueue
                        savingsPipeline
                    }
                    HStack(alignment: .top, spacing: Space.lg) {
                        freshness
                        governanceSummary
                    }
                    HStack(alignment: .top, spacing: Space.lg) {
                        nextMeetings
                        openActions
                    }

                    GuardrailNote(text: "Savings are estimates until an owner commits them and before/after evidence validates them under TE's rules. ProcessLink never presents a modelled number as a claim.")
                        .gridProbe("overview-guardrail", area: "overview")
                }
            }
            .padding(Space.margin)
        }
        .gridArea("overview")
        .navigationTitle("Overview")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var nextMeetings: some View {
        let upcoming = meetings.filter { $0.date >= model.now }.sorted { $0.date < $1.date }.prefix(3)
        return Card("Next meetings", subtitle: "Pages, not invites. Notes become graph facts.", symbol: "person.3.sequence") {
            if upcoming.isEmpty {
                Text("No meeting is scheduled. Start a daily huddle from Meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcoming)) { meeting in
                        Button {
                            model.selectedMeetingID = meeting.id
                            model.page = .meetings
                        } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: meeting.kind.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(meeting.title).font(.subheadline).foregroundStyle(.primary)
                                    Text("\(Fmt.day(meeting.date)) · \(meeting.durationMinutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if !meeting.site.isEmpty {
                                    Chip(text: meeting.site, tint: .secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Space.sm)
                        if meeting.id != upcoming.last?.id { RowDivider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var openActions: some View {
        let actions = meetingBlocks.filter { $0.kind == .action && !$0.checked }.prefix(3)
        return Card("Open actions", subtitle: "Commitments from meeting pages, not a task silo.", symbol: "checklist") {
            if actions.isEmpty {
                Text("Every recorded action is done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(actions)) { action in
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.text.isEmpty ? "Untitled action" : action.text)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(action.owner.isEmpty ? "Unassigned" : action.owner)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: Space.sm)
                            if let due = action.due {
                                Text(Fmt.day(due)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, Space.sm)
                        if action.id != actions.last?.id { RowDivider() }
                    }
                    Button("Open Meetings") { model.page = .meetings }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.top, Space.xs)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: Space.md) {
            MetricTile(title: "Discovered effort", value: Fmt.hoursPerYear(discoveredHours),
                       detail: "\(eligibleProcesses.count) processes in scope",
                       symbol: "binoculars", tint: .blue)
            MetricTile(title: "Opportunity pipeline", value: Fmt.hoursPerYear(qualifiedHours),
                       detail: "\(ranked.count) opportunities, estimate only",
                       symbol: "lightbulb", tint: .orange)
            MetricTile(title: "Validated savings", value: Fmt.hoursPerYear(ledger.validated),
                       detail: "\(CostModel.euro(hours: ledger.validated)) at €\(Int(CostModel.ratePerHour))/h",
                       symbol: "checkmark.seal", tint: .green)
            MetricTile(title: "Open initiatives", value: "\(activeInitiatives)",
                       detail: "\(initiatives.count) total in the portfolio",
                       symbol: "flag.pattern.checkered", tint: .purple)
        }
    }

    private var priorityQueue: some View {
        Card("Priority queue", subtitle: "Ranked by impact, ease, alignment and confidence.", symbol: "list.number") {
            VStack(spacing: 0) {
                ForEach(Array(ranked.prefix(4))) { opportunity in
                    Button {
                        model.selectedOpportunityID = opportunity.id
                        model.page = .opportunities
                    } label: {
                        HStack(alignment: .center, spacing: Space.md) {
                            Text("\(Int(opportunity.score.total.rounded()))")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.accentText)
                                .frame(width: 36, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opportunity.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(opportunity.processName) · \(opportunity.site)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Space.sm)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Fmt.hoursPerYear(opportunity.annualHours))
                                    .font(.subheadline.monospacedDigit())
                                Chip(text: opportunity.route.label, symbol: opportunity.route.symbol,
                                     tint: opportunity.route.tint)
                            }
                        }
                        .padding(.vertical, Space.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if opportunity.id != ranked.prefix(4).last?.id { RowDivider() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .gridProbe("overview-queue", area: "overview")
    }

    private var savingsPipeline: some View {
        Card("Savings pipeline", subtitle: "One claim per process and waste type.", symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: Space.md) {
                pipelineRow(.estimated, hours: ledger.estimated, all: ledger)
                pipelineRow(.committed, hours: ledger.committed, all: ledger)
                pipelineRow(.validated, hours: ledger.validated, all: ledger)

                if !conflicts.isEmpty {
                    Divider().opacity(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(conflicts.count) possible double count\(conflicts.count == 1 ? "" : "s") across initiatives. Resolve before the roll-up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider().opacity(0.6)
                HStack {
                    Text("At €\(Int(CostModel.ratePerHour))/hour")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(CostModel.euro(hours: ledger.validated) + " validated")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 300)
        .gridProbe("overview-pipeline", area: "overview")
    }

    private func pipelineRow(_ stage: SavingsStage, hours: Double, all: SavingsTotals) -> some View {
        let maxHours = max(all.estimated, all.committed, all.validated, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.sm) {
                SavingsChip(stage: stage)
                Spacer(minLength: Space.sm)
                Text(Fmt.hours(hours))
                    .font(.subheadline.monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(stage.tint)
                        .frame(width: max(4, proxy.size.width * (hours / maxHours)))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(stage.detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var freshness: some View {
        Card("Evidence freshness", subtitle: "Maps and opportunities are only as good as their last sync.", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(eligibleProcesses.sorted { $0.staleDays > $1.staleDays }.prefix(4)) { process in
                    HStack(spacing: Space.sm) {
                        Image(systemName: process.isStale ? "exclamationmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(process.isStale ? Color.orange : Color.green)
                            .accessibilityHidden(true)
                        Text(process.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text(process.isStale ? "\(process.staleDays) days — stale" : Fmt.ago(process.lastSynced))
                            .font(.caption)
                            .foregroundStyle(process.isStale ? Color.orange : Color.secondary)
                    }
                }
                if let last = syncs.first {
                    Divider().opacity(0.6)
                    Text("Last sync \(Fmt.ago(last.at)) · \(last.fetched) fetched · \(last.skipped) skipped by policy")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var governanceSummary: some View {
        Card("Launch posture", subtitle: "Nothing here is production-ready until the checklist is signed.", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(governance.filter { $0.status != .done }.sorted { $0.sortKey < $1.sortKey }.prefix(3)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: item.status.symbol)
                            .foregroundStyle(item.status.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline)
                            Text(item.owner).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: Space.sm)
                        Chip(text: item.status.label, tint: item.status.tint)
                    }
                }
                Button("Open the checklist") { model.page = .governance }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .frame(width: 300)
    }
}

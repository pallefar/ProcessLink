import ProcessLinkKit
import SwiftData
import SwiftUI

/// What KYP.ai found, process by process: variants, steps, provenance and the
/// two reasons a record can be shown as suppressed or blocked.
struct DiscoveriesPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \StepRecord.order) private var steps: [StepRecord]
    @Query(sort: \VariantRecord.share, order: .reverse) private var variants: [VariantRecord]
    @Query(sort: \MeetingRecord.date, order: .reverse) private var meetingNotes: [MeetingRecord]

    private var visible: [ProcessRecord] {
        processes
            .filter { model.siteFilter == "All sites" || $0.site == model.siteFilter }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status.rank < rhs.status.rank }
                if lhs.annualHours != rhs.annualHours { return lhs.annualHours > rhs.annualHours }
                return lhs.name < rhs.name
            }
    }

    private var selected: ProcessRecord? {
        visible.first { $0.id == model.selectedProcessID } ?? visible.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 380)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Discoveries")
        .onAppear {
            if model.selectedProcessID == nil { model.selectedProcessID = visible.first?.id }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Text("\(visible.count) processes")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    Picker("Site", selection: Binding(get: { model.siteFilter }, set: { model.siteFilter = $0 })) {
                        ForEach(["All sites"] + Array(Set(processes.map(\.site))).sorted(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                } label: {
                    Label(model.siteFilter, systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Filter by site")
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visible) { process in
                        Button {
                            model.selectedProcessID = process.id
                        } label: {
                            SelectableRow(selected: selected?.id == process.id) {
                                HStack(alignment: .top, spacing: Space.sm) {
                                    Image(systemName: symbol(for: process))
                                        .foregroundStyle(tint(for: process))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(process.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 8) {
                                            Text(process.site)
                                            Text("·")
                                            Text(process.valueStream)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        HStack(spacing: Space.xs) {
                                            StatusChip(status: process.status)
                                            if process.isStale && process.status == .discovered {
                                                Chip(text: "\(process.staleDays)d old", symbol: "clock.badge.exclamationmark", tint: .orange)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if process.status == .discovered {
                                        Text(Fmt.hoursPerYear(process.annualHours))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(process.name), \(process.site), \(process.status.label)")
                    }
                }
                .padding(Space.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let process = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(process)
                    if process.status == .discovered {
                        discoveredDetail(process)
                    } else {
                        guardedDetail(process)
                    }
                }
                .padding(Space.margin)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .id(process.id)
        } else {
            ContentUnavailableView("No discoveries",
                                   systemImage: "binoculars",
                                   description: Text("Run a sync against the KYP.ai sandbox to see mined processes."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ process: ProcessRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(process.name).font(.title2.weight(.semibold))
                Spacer(minLength: Space.sm)
                StatusChip(status: process.status)
                if process.status == .discovered {
                    ConfidenceChip(confidence: process.confidence)
                }
            }
            HStack(spacing: Space.sm) {
                Chip(text: process.site, symbol: "mappin.and.ellipse", tint: .blue)
                Chip(text: process.businessUnit, symbol: "building.2", tint: .secondary)
                Chip(text: process.valueStream, symbol: "arrow.right.to.line.compact", tint: .secondary)
                Chip(text: "Maturity \(process.maturity)/5", symbol: "chart.line.uptrend.xyaxis", tint: .secondary)
            }
            Text(process.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func discoveredDetail(_ process: ProcessRecord) -> some View {
        let processSteps = steps.filter { $0.processID == process.id }.sorted { $0.order < $1.order }
        let processVariants = variants.filter { $0.processID == process.id }
        let decision = PrivacyGuard.evaluate(groupSize: process.people, classification: process.classification,
                                             destination: .knowledgeGraph, purpose: .processImprovement,
                                             policy: model.policy)
        return VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .top, spacing: Space.md) {
                MetricTile(title: "Annual effort", value: Fmt.hoursPerYear(process.annualHours),
                           detail: "\(process.people) people, aggregate only", symbol: "clock", tint: .blue)
                MetricTile(title: "Median cycle", value: Fmt.minutes(process.cycleMinutes),
                           detail: "\(process.handoffs) handoffs in the main path", symbol: "timer", tint: .purple)
                MetricTile(title: "Rework", value: Fmt.percent(process.reworkRate),
                           detail: "Touches that repeat a step", symbol: "arrow.triangle.2.circlepath", tint: .orange)
                MetricTile(title: "Standard adherence", value: Fmt.percent(process.adherence),
                           detail: process.standardVersion, symbol: "ruler", tint: .teal)
            }
            .gridProbe("discoveries-metrics", area: "discoveries")

            Card("Variants", subtitle: "The same process, mined as \(process.variantCount) paths.", symbol: "arrow.triangle.swap") {
                VStack(spacing: Space.sm) {
                    ForEach(processVariants) { variant in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: Space.sm) {
                                Text(variant.name).font(.subheadline.weight(.medium))
                                Spacer(minLength: Space.sm)
                                Text(Fmt.percent(variant.share) + " of cases")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(variant.reworkRate > process.reworkRate
                                                   ? Color.orange : Palette.accent)
                                        .frame(width: max(4, proxy.size.width * variant.share))
                                }
                            }
                            .frame(height: 4)
                            .accessibilityHidden(true)
                            HStack(spacing: Space.lg) {
                                Label(Fmt.minutes(variant.cycleMinutes), systemImage: "timer")
                                Label(Fmt.percent(variant.reworkRate) + " rework", systemImage: "arrow.triangle.2.circlepath")
                                Text(variant.path).lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Card("Steps", subtitle: "Role and application as KYP.ai classified them. No person is shown.", symbol: "list.bullet.rectangle") {
                VStack(spacing: 0) {
                    stepHeader
                    ForEach(processSteps) { step in
                        stepRow(step, process: process)
                        if step.id != processSteps.last?.id { RowDivider() }
                    }
                }
            }

            HStack(alignment: .top, spacing: Space.lg) {
                Card("Provenance", subtitle: "Every fact carries its source and window.", symbol: "link") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Source", value: "KYP.ai task mining")
                        DetailRow(label: "KYP.ai id", value: process.kypID, mono: true)
                        DetailRow(label: "KG node", value: process.kgID, mono: true)
                        DetailRow(label: "Captured", value: "\(Fmt.day(process.capturedFrom)) – \(Fmt.day(process.capturedTo))")
                        DetailRow(label: "Synced", value: Fmt.stamp(process.lastSynced))
                        DetailRow(label: "Group size", value: "\(process.people) people · aggregate only")
                        DetailRow(label: "Classification", value: process.classification.label)
                    }
                }
                Card("Standard work", subtitle: "The documented path the mining is compared with.", symbol: "doc.text") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Document", value: process.standardDocument.isEmpty ? "Not linked" : process.standardDocument)
                        DetailRow(label: "Version", value: process.standardVersion.isEmpty ? "—" : process.standardVersion)
                        DetailRow(label: "Adherence", value: Fmt.percent(process.adherence))
                        DetailRow(label: "Deviating steps", value: "\(processSteps.filter { !$0.standardAligned }.count)")
                        GuardrailNote(text: "A standard-work change is proposed, never applied. A human owner approves the new standard.")
                    }
                }
            }

            if !meetingNotes.filter({ $0.processID == process.id }).isEmpty {
                meetingCard(process)
            }

            HStack(spacing: Space.md) {
                Button {
                    if let opportunity = bestOpportunity(for: process) {
                        model.selectedOpportunityID = opportunity.id
                        model.page = .opportunities
                    }
                } label: {
                    Label("Open best opportunity", systemImage: "lightbulb")
                }
                .buttonStyle(.borderedProminent)
                .disabled(bestOpportunity(for: process) == nil)

                Button {
                    model.selectedProcessID = process.id
                    model.selectedMapStepID = nil
                    model.page = .maps
                } label: {
                    Label("Open map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }

                Button {
                    model.selectedKGID = process.kgID
                    model.page = .graph
                } label: {
                    Label("KG node", systemImage: "circle.hexagongrid")
                }

                Spacer()
                Text(decision.allowed ? "Eligible for KG write" : decision.reason)
                    .font(.caption)
                    .foregroundStyle(decision.allowed ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
        }
    }

    private var stepHeader: some View {
        HStack(spacing: Space.sm) {
            Text("Step").frame(maxWidth: .infinity, alignment: .leading)
            Text("Role").frame(width: 104, alignment: .leading)
            Text("Application").frame(width: 104, alignment: .leading)
            Text("Time").frame(width: 52, alignment: .trailing)
            Text("Waste").frame(width: 128, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.bottom, Space.xs)
    }

    private func stepRow(_ step: StepRecord, process: ProcessRecord) -> some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Text("\(step.order + 1).")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(step.name).font(.subheadline).lineLimit(1)
                if step.handoffs > 0 {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("\(step.handoffs) handoff(s)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(step.role).font(.caption).foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading).lineLimit(1)
            Text(step.application).font(.caption).foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading).lineLimit(1)
            Text(Fmt.minutes(step.minutes)).font(.caption.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
            Chip(text: step.waste.label, symbol: step.waste.symbol, tint: wasteTint(step.waste))
                .frame(width: 128, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedKGID = step.kgID
            model.page = .graph
        }
        .help("Open \(step.kgID) in the knowledge graph")
    }

    private func guardedDetail(_ process: ProcessRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Card(process.status == .blocked ? "Blocked by classification" : "Suppressed by group size",
                 subtitle: process.statusReason,
                 symbol: process.status == .blocked ? "hand.raised" : "eye.slash") {
                VStack(alignment: .leading, spacing: Space.md) {
                    if process.status == .blocked {
                        Text("Restricted content never enters ProcessLink. The process appears here only so an operator can see that data exists and is being refused — there are no numbers, no steps and no variants to open.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.md) {
                            Chip(text: "Restricted", symbol: "lock", tint: .red)
                            Chip(text: "No AI call", symbol: "xmark.circle", tint: .red)
                            Chip(text: "No export", symbol: "xmark.circle", tint: .red)
                        }
                    } else {
                        Text("This group of \(process.people) people is below the \(model.minimumGroupSize)-person threshold. ProcessLink shows that the process exists and the reason it is hidden; it never computes or displays an aggregate for a group this small.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        DetailRow(label: "Group size", value: "\(process.people) people")
                        DetailRow(label: "Threshold", value: "\(model.minimumGroupSize) people")
                        DetailRow(label: "KYP.ai id", value: process.kypID, mono: true)
                    }
                    GuardrailNote(text: "The threshold is set by policy and reviewed with employee representatives; it is not a per-user preference.")
                }
            }

            HStack(spacing: Space.md) {
                Button("Open governance") { model.page = .governance }
                Spacer()
            }
        }
    }

    private func meetingCard(_ process: ProcessRecord) -> some View {
        Card("Meeting notes", subtitle: "Decisions and actions recorded about this process.", symbol: "person.3.sequence") {
            VStack(spacing: 0) {
                ForEach(meetingNotes.filter { $0.processID == process.id }.prefix(3)) { meeting in
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
                                Text("\(Fmt.day(meeting.date)) · \(meeting.owner)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Space.sm)
                    if meeting.id != meetingNotes.filter({ $0.processID == process.id }).prefix(3).last?.id {
                        RowDivider()
                    }
                }
            }
        }
    }

    private func bestOpportunity(for process: ProcessRecord) -> OpportunityRecord? {
        let opportunities = (try? model.context.fetch(FetchDescriptor<OpportunityRecord>())) ?? []
        return opportunities.filter { $0.processID == process.id && $0.status != .deferred }
            .max { $0.score.total < $1.score.total }
    }

    private func symbol(for process: ProcessRecord) -> String {
        switch process.status {
        case .discovered: "circle.fill"
        case .suppressed: "eye.slash"
        case .blocked: "hand.raised.fill"
        }
    }

    private func tint(for process: ProcessRecord) -> Color {
        switch process.status {
        case .discovered: process.isStale ? .orange : .green
        case .suppressed: .orange
        case .blocked: .red
        }
    }

    private func wasteTint(_ waste: WasteType) -> Color {
        switch waste {
        case .waiting: .blue
        case .rework: .orange
        case .overProcessing: .purple
        case .handoffs: .teal
        case .contextSwitching: .indigo
        case .defects: .red
        case .unusedTalent: .pink
        case .backlog: .brown
        }
    }
}

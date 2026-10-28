import AppKit
import ProcessLinkKit
import SwiftUI
import UniformTypeIdentifiers

/// The full mining workbench. Everything is derived from the imported event
/// log: filters, the process graph, cases, token replay, root causes and a
/// what-if calculation.
struct MiningWorkbench: View {
    enum ProcessView: String, CaseIterable, Identifiable {
        case dfg, tree, bpmn
        var id: String { rawValue }
        var label: String { self == .dfg ? "Flow graph" : self == .tree ? "Process tree" : "BPMN" }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case overview, process, cases, conformance, insights, simulate
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .process: "Process"
            case .cases: "Cases"
            case .conformance: "Conformance"
            case .insights: "Insights"
            case .simulate: "Simulate"
            }
        }
        var symbol: String {
            switch self {
            case .overview: "chart.bar.xaxis"
            case .process: "point.topleft.down.to.point.bottomright.curvepath"
            case .cases: "list.bullet.rectangle"
            case .conformance: "checkmark.seal"
            case .insights: "lightbulb"
            case .simulate: "slider.horizontal.3"
            }
        }
    }

    @Environment(AppModel.self) private var model
    var dataset: DatasetRecord
    var processes: [ProcessRecord]
    var steps: [StepRecord]
    var map: MapsBridge.Document?

    @State private var tab: Tab = .overview
    @State private var filter = MiningFilter()
    @State private var activityFilter = ""
    @State private var resourceFilter = ""
    @State private var attributeName = ""
    @State private var attributeValue = ""
    @State private var reworkOnly = false
    @State private var selectedActivity: String?
    @State private var selectedCaseID: String?
    @State private var caseSearch = ""
    @State private var referenceProcessID: String?
    @State private var rootOutcome: MiningOutcome = .slow
    @State private var simulation = MiningSimulation()
    @State private var showAllVariants = false
    @State private var processView: ProcessView = .dfg
    @State private var capacityRoles: [CapacityRole] = []
    @State private var arrivalPerDay: Double = 24
    @State private var capacityDays = 5
    @State private var capacityResult: CapacityResult?
    @State private var showMapMapping = false

    private var allEvents: [EventLogRecord] { model.events(for: dataset) }
    private var filteredEvents: [EventLogRecord] { ProcessMining.filter(allEvents, with: filter) }
    private var mined: MinedProcess {
        ProcessMining.mine(filteredEvents, name: dataset.name)
    }
    private var baseline: MinedProcess {
        ProcessMining.mine(allEvents, name: dataset.name)
    }

    private var mapReference: MapReference? {
        guard let map else { return nil }
        let mapSteps = map.nodes.compactMap { node -> MapStepRef? in
            guard node.type != "start" && node.type != "end" else { return nil }
            let stepID = node.link?.stepID ?? (node.stepID.isEmpty ? node.id : node.stepID)
            return MapStepRef(id: stepID, label: node.label,
                              role: node.role, system: node.system)
        }
        let stepIDs = Dictionary(uniqueKeysWithValues: map.nodes.map { node in
            (node.id, node.link?.stepID ?? (node.stepID.isEmpty ? node.id : node.stepID))
        })
        let mapEdges = map.edges.compactMap { edge -> MapEdgeRef? in
            guard let from = stepIDs[edge.source], let to = stepIDs[edge.target] else { return nil }
            return MapEdgeRef(from: from, to: to)
        }
        return MapReference(name: map.label, steps: mapSteps, edges: mapEdges)
    }

    private var mapMapping: [String: String] {
        guard let data = dataset.mapMappingJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return object
    }

    private var mapReport: MapMiningReport? {
        guard let mapReference, !allEvents.isEmpty else { return nil }
        return MapMining.conformance(events: allEvents, reference: mapReference, mapping: mapMapping)
    }

    private var referenceSteps: [String] {
        let id = referenceProcessID ?? processes.first(where: { process in
            !steps.filter { $0.processID == process.id }.isEmpty
        })?.id
        guard let id else { return [] }
        return steps.filter { $0.processID == id }.sorted { $0.order < $1.order }.map(\.name)
    }

    private var conformance: ConformanceReport? {
        guard !referenceSteps.isEmpty, !filteredEvents.isEmpty else { return nil }
        return ProcessMining.conformance(events: filteredEvents, reference: referenceSteps)
    }

    private var alignment: AlignmentReport? {
        guard !referenceSteps.isEmpty, !filteredEvents.isEmpty else { return nil }
        return Alignment.sequence(filteredEvents, reference: referenceSteps)
    }

    private var processTree: ProcessTree {
        InductiveDiscovery.tree(from: mined.caseRecords)
    }

    private var referenceProcess: ProcessRecord? {
        let id = referenceProcessID ?? processes.first(where: { process in
            !steps.filter { $0.processID == process.id }.isEmpty
        })?.id
        return processes.first { $0.id == id }
    }

    private var selectedCase: MinedCase? {
        mined.caseRecords.first { $0.id == selectedCaseID }
    }

    private var activityNames: [String] {
        baseline.activities.map(\.name).sorted()
    }

    private var resourceNames: [String] {
        Array(Set(allEvents.map(\.resource))).sorted()
    }

    private var attributeValues: [String: [String]] {
        var values: [String: Set<String>] = [:]
        for event in allEvents {
            for (key, value) in event.attributes where !value.isEmpty {
                values[key, default: []].insert(value)
            }
        }
        return values.mapValues { $0.sorted() }
    }

    private var filteredCases: [MinedCase] {
        let query = caseSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return mined.caseRecords }
        return mined.caseRecords.filter {
            $0.caseID.lowercased().contains(query) || $0.variant.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                datasetHeader
                filterBar
                tabBar
                switch tab {
                case .overview: overview
                case .process: processTab
                case .cases: casesTab
                case .conformance: conformanceTab
                case .insights: insightsTab
                case .simulate: simulateTab
                }
                footer
            }
            .padding(Space.margin)
            .frame(maxWidth: 1_200, alignment: .leading)
        }
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["APP_SNAPSHOT_MINING_TAB"],
               let requested = Tab(rawValue: raw) {
                tab = requested
            }
            if selectedCaseID == nil { selectedCaseID = mined.caseRecords.first?.id }
            if capacityRoles.isEmpty { capacityRoles = CapacitySimulation.defaultRoles(for: mined) }
        }
        .onChange(of: dataset.id) { _, _ in
            capacityRoles = CapacitySimulation.defaultRoles(for: mined)
            capacityResult = nil
        }
        .onChange(of: activityFilter) { _, _ in applyFilter() }
        .onChange(of: resourceFilter) { _, _ in applyFilter() }
        .onChange(of: attributeName) { _, _ in attributeValue = ""; applyFilter() }
        .onChange(of: attributeValue) { _, _ in applyFilter() }
        .onChange(of: reworkOnly) { _, _ in applyFilter() }
    }

    // MARK: Header and filters

    private var datasetHeader: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(dataset.name).font(.title2.weight(.semibold))
                Spacer()
                if filter.isActive {
                    Chip(text: "Filtered", symbol: "line.3.horizontal.decrease", tint: .orange)
                }
                Menu {
                    Button("Export cases as CSV…") { exportCases() }
                    Button("Export mining summary as JSON…") { exportSummary() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Chip(text: "\(mined.cases) of \(baseline.cases) cases", symbol: "shippingbox", tint: .secondary)
            }
            HStack(spacing: Space.xs) {
                Chip(text: dataset.sourceRaw == "sample" ? "In-house sample" : "CSV import",
                     symbol: "sparkles", tint: .blue)
                Chip(text: dataset.classification.label, symbol: "lock", tint: .secondary)
                if !dataset.site.isEmpty { Chip(text: dataset.site, symbol: "mappin.and.ellipse", tint: .secondary) }
                if let first = mined.firstTimestamp, let last = mined.lastTimestamp {
                    Chip(text: "\(Fmt.day(first)) – \(Fmt.day(last))", symbol: "calendar", tint: .secondary)
                }
                Chip(text: "\(mined.events) events", symbol: "list.bullet", tint: .secondary)
            }
            Text(dataset.notes).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filterBar: some View {
        HStack(spacing: Space.sm) {
            Picker("Activity", selection: $activityFilter) {
                Text("All activities").tag("")
                ForEach(activityNames, id: \.self) { name in Text(name).tag(name) }
            }
            .labelsHidden()
            .frame(width: 192)

            Picker("Role", selection: $resourceFilter) {
                Text("All roles").tag("")
                ForEach(resourceNames, id: \.self) { name in Text(name).tag(name) }
            }
            .labelsHidden()
            .frame(width: 160)

            if !attributeValues.isEmpty {
                Picker("Dimension", selection: $attributeName) {
                    Text("All dimensions").tag("")
                    ForEach(attributeValues.keys.sorted(), id: \.self) { key in Text(key).tag(key) }
                }
                .labelsHidden()
                .frame(width: 152)

                if !attributeName.isEmpty {
                    Picker("Value", selection: $attributeValue) {
                        Text("Any value").tag("")
                        ForEach(attributeValues[attributeName] ?? [], id: \.self) { value in Text(value).tag(value) }
                    }
                    .labelsHidden()
                    .frame(width: 132)
                }
            }

            Toggle("Rework only", isOn: $reworkOnly)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            Button("Reset") {
                filter = MiningFilter()
                activityFilter = ""
                resourceFilter = ""
                attributeName = ""
                attributeValue = ""
                reworkOnly = false
            }
            .controlSize(.small)
            .disabled(!filter.isActive)
        }
        .padding(Space.sm)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func applyFilter() {
        filter.activities = activityFilter.isEmpty ? [] : [activityFilter]
        filter.resources = resourceFilter.isEmpty ? [] : [resourceFilter]
        filter.attributes = attributeName.isEmpty || attributeValue.isEmpty
            ? [:] : [attributeName: attributeValue]
        filter.onlyRework = reworkOnly
        selectedActivity = nil
    }

    private var tabBar: some View {
        Picker("Mining view", selection: $tab) {
            ForEach(Tab.allCases) { item in
                Label(item.label, systemImage: item.symbol).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                MetricTile(title: "Cases", value: "\(mined.cases)", detail: "\(baseline.cases) before filters",
                           symbol: "shippingbox", tint: .blue)
                MetricTile(title: "Median cycle", value: Fmt.minutes(mined.medianCycleMinutes),
                           detail: "P90 \(Fmt.minutes(mined.p90CycleMinutes))", symbol: "timer", tint: .teal)
                MetricTile(title: "Rework", value: Fmt.percent(mined.reworkRate),
                           detail: "\(mined.casesWithRework) cases touched", symbol: "arrow.triangle.2.circlepath", tint: .orange)
                MetricTile(title: "Handoffs", value: Fmt.percent(mined.handoffRate),
                           detail: "\(mined.handovers.count) role pairs", symbol: "arrow.left.arrow.right", tint: .purple)
                MetricTile(title: "Cost / case", value: Fmt.euro(mined.costPerCase),
                           detail: mined.totalCost > 0 ? "\(Fmt.euro(mined.totalCost)) observed" : "No cost column",
                           symbol: "eurosign.circle", tint: .green)
                MetricTile(title: "Auto fit", value: "\(mined.automationCandidates.count)",
                           detail: "Score ≥ 0.55", symbol: "gearshape.2", tint: .indigo)
            }

            HStack(alignment: .top, spacing: Space.lg) {
                Card("Throughput", subtitle: "Cases per week; orange bars contain rework.", symbol: "chart.xyaxis.line") {
                    trend
                }
                .frame(maxWidth: .infinity)

                distributionCard

                Card("Data quality", subtitle: "What the import kept and skipped.", symbol: "checklist") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        DetailRow(label: "Rows", value: "\(dataset.eventCount) events")
                        DetailRow(label: "Case ids", value: "SHA-256, never raw")
                        DetailRow(label: "Attributes", value: "\(attributeValues.count) dimensions")
                        DetailRow(label: "Cost column", value: mined.totalCost > 0 ? Fmt.euro(mined.totalCost) : "None")
                        DetailRow(label: "Start / end", value: "\(mined.startActivities.first ?? "—") / \(mined.endActivities.first ?? "—")")
                        GuardrailNote(text: "A missing value stays missing. The miner never invents a cost, duration or person.")
                    }
                }
                .frame(width: 300)
            }

            if let map, let mapReport { mapCard(map, report: mapReport) }
            watchlistCard

            if filter.isActive { comparisonCard }

            HStack(alignment: .top, spacing: Space.lg) {
                variantsCard
                bottleneckCard
            }
        }
    }

    private var watchlistCard: some View {
        let alerts = ProcessMining.alerts(mined)
        return Card("Watchlist", subtitle: "Explainable signals, not automatic decisions.", symbol: "bell") {
            if alerts.isEmpty {
                Text("No threshold crossed in this view. That is not proof the process is healthy; check the data window and volume.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: Space.sm) {
                            Image(systemName: alert.symbol)
                                .foregroundStyle(alert.severity == .critical ? Color.red : alert.severity == .warning ? Color.orange : Color.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title).font(.subheadline.weight(.medium))
                                Text(alert.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(alert.severity.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        RowDivider()
                    }
                }
            }
        }
    }

    private func mapCard(_ map: MapsBridge.Document, report: MapMiningReport) -> some View {
        Card("Map model · \(map.label)", subtitle: "The map is the reference; the log is the evidence. Unmapped activities are not hidden.", symbol: "map") {
            HStack(spacing: Space.xl) {
                mapMetric("Steps observed", "\(report.stepsObserved)/\(report.stepsTotal)", report.stepCoverage)
                mapMetric("Mapped activities", "\(report.mappedActivities)", nil)
                mapMetric("Expected transitions", "\(report.observedTransitions)/\(report.expectedTransitions)", report.transitionCoverage)
                Spacer()
                Button("Map activities…") { showMapMapping = true }
                    .controlSize(.small)
            }
            if !report.unmappedActivities.isEmpty {
                Text("Not on the map: \(report.unmappedActivities.prefix(5).joined(separator: " · "))")
                    .font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
            if !report.unexpectedTransitions.isEmpty {
                Text("\(report.unexpectedTransitions.count) observed transition(s) are not in the map.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func mapMetric(_ title: String, _ value: String, _ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.headline.monospacedDigit())
            if let progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color.teal).frame(width: max(4, proxy.size.width * progress))
                    }
                }
                .frame(width: 100, height: 4)
            }
        }
    }

    private var distributionCard: some View {
        let cycles = mined.caseRecords.map(\.cycleMinutes).sorted()
        let maximum = max(1, cycles.max() ?? 1)
        let bucketCount = 6
        let buckets = (0..<bucketCount).map { index -> (String, Int) in
            let low = maximum * Double(index) / Double(bucketCount)
            let high = maximum * Double(index + 1) / Double(bucketCount)
            let count = cycles.filter { $0 >= low && ($0 < high || index == bucketCount - 1) }.count
            return ("\(Int(low))", count)
        }
        let peak = max(1, buckets.map(\.1).max() ?? 1)
        return Card("Cycle distribution", subtitle: "How many cases finish in each band.", symbol: "chart.bar") {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    VStack(spacing: 2) {
                        Text("\(bucket.1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.65))
                            .frame(width: 20, height: max(4, 54 * CGFloat(bucket.1) / CGFloat(peak)))
                        Text(bucket.0).font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Minutes per case · n=\(cycles.count)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 232)
    }

    private var comparisonCard: some View {
        Card("View comparison", subtitle: "The filter against the full event log.", symbol: "arrow.left.arrow.right") {
            HStack(spacing: Space.xl) {
                comparisonMetric("Cases", before: "\(baseline.cases)", after: "\(mined.cases)")
                comparisonMetric("Median cycle", before: Fmt.minutes(baseline.medianCycleMinutes),
                                 after: Fmt.minutes(mined.medianCycleMinutes))
                comparisonMetric("P90 cycle", before: Fmt.minutes(baseline.p90CycleMinutes),
                                 after: Fmt.minutes(mined.p90CycleMinutes))
                comparisonMetric("Rework", before: Fmt.percent(baseline.reworkRate),
                                 after: Fmt.percent(mined.reworkRate))
                comparisonMetric("Handoffs", before: Fmt.percent(baseline.handoffRate),
                                 after: Fmt.percent(mined.handoffRate))
                Spacer()
            }
        }
    }

    private func comparisonMetric(_ title: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.tertiary)
            Text(after).font(.headline.monospacedDigit())
            Text("was \(before)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var trend: some View {
        let periods = mined.periods
        let maxCases = max(1, periods.map(\.cases).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(periods) { period in
                VStack(spacing: 4) {
                    Text("\(period.cases)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(period.reworkRate > 0.1 ? Color.orange.opacity(0.75) : Color.accentColor.opacity(0.7))
                        .frame(width: 24, height: max(4, 80 * CGFloat(period.cases) / CGFloat(maxCases)))
                    Text(period.label.suffix(3)).font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly case volume")
    }

    private var variantsCard: some View {
        Card("Variants", subtitle: "Every distinct path, ranked by case count.", symbol: "arrow.triangle.swap",
             ) {
            VStack(spacing: Space.md) {
                ForEach(Array((showAllVariants ? mined.variants : Array(mined.variants.prefix(5))))) { variant in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Space.sm) {
                            Text(variant.sequence.prefix(5).joined(separator: " → "))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Spacer(minLength: Space.sm)
                            Text(Fmt.percent(variant.share)).font(.subheadline.monospacedDigit())
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(variant.hasRework ? Color.orange : Color.accentColor)
                                    .frame(width: max(4, proxy.size.width * variant.share))
                            }
                        }
                        .frame(height: 4)
                        Text("\(variant.cases) cases · \(Fmt.minutes(variant.averageCycleMinutes)) avg · \(Fmt.percent(variant.reworkRate)) rework")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if mined.variants.count > 5 {
                    Button(showAllVariants ? "Show fewer" : "Show all \(mined.variants.count)") {
                        showAllVariants.toggle()
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottleneckCard: some View {
        Card("Bottlenecks", subtitle: "Wait, rework and automation fit by activity.", symbol: "chart.bar.xaxis") {
            VStack(spacing: 0) {
                HStack(spacing: Space.sm) {
                    Text("Activity").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Wait").frame(width: 56, alignment: .trailing)
                    Text("Rework").frame(width: 56, alignment: .trailing)
                    Text("Fit").frame(width: 44, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.tertiary)
                ForEach(Array(mined.activities.sorted { $0.averageWaitMinutes > $1.averageWaitMinutes }.prefix(7))) { activity in
                    HStack(spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.name).font(.subheadline).lineLimit(1)
                            Text(activity.resources.prefix(2).joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.minutes(activity.averageWaitMinutes)).font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
                        Text("\(activity.reworkCount)").font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
                        Text(Fmt.percent(activity.automationScore))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(activity.automationScore >= 0.55 ? .green : .secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    RowDivider()
                }
            }
        }
        .frame(width: 432)
    }

    // MARK: Process

    private var processTab: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Picker("Model", selection: $processView) {
                ForEach(ProcessView.allCases) { view in Text(view.label).tag(view) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch processView {
            case .dfg:
                Card("Discovered process", subtitle: "Activities and directly-follows edges; width is frequency, hue is wait.", symbol: "point.topleft.down.to.point.bottomright.curvepath") {
                    MiningProcessGraph(mined: mined, selected: selectedActivity) { name in
                        selectedActivity = name
                    }
                    .frame(height: 240)
                    .overlay(alignment: .topTrailing) {
                        Text("\(mined.activities.count) activities · scroll →")
                            .font(.caption2).foregroundStyle(.tertiary).padding(4)
                    }
                }
            case .tree:
                Card("Block-structured process tree", subtitle: "Sound by construction; every observed case is accepted.", symbol: "tree") {
                    HStack {
                        Chip(text: processTree.isSound ? "Sound" : "Check", symbol: "checkmark.seal", tint: .green)
                        Text("\(processTree.activityNames.count) activities · \(mined.variants.count) branches")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Export BPMN…") { exportBPMN() }.controlSize(.small)
                    }
                    ScrollView {
                        Text(processTree.outline())
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.sm)
                    }
                    .frame(maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            case .bpmn:
                Card("BPMN 2.0", subtitle: "Paired XOR gateways from the process tree; import it into a BPMN editor.", symbol: "doc.text") {
                    HStack {
                        Chip(text: "Sound by construction", symbol: "checkmark.seal", tint: .green)
                        Spacer()
                        Button("Export BPMN…") { exportBPMN() }.controlSize(.small)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        Text(InductiveDiscovery.bpmn(processTree, name: dataset.name))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if let activity = mined.activities.first(where: { $0.name == selectedActivity }) {
                activityDetail(activity)
            } else if processView == .dfg {
                Text("Click a shape to inspect it. Shapes are positioned by their earliest directly-follows order, not a force layout.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func exportBPMN() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(dataset.name.replacingOccurrences(of: " ", with: "-")).bpmn"
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let xml = InductiveDiscovery.bpmn(processTree, name: dataset.name)
        try? xml.write(to: url, atomically: true, encoding: .utf8)
        model.showToast("BPMN exported", detail: url.lastPathComponent, symbol: "doc.text")
    }

    private func activityDetail(_ activity: MinedActivity) -> some View {
        Card(activity.name, subtitle: "\(activity.events) events across \(activity.cases) cases", symbol: "square.dashed") {
            HStack(alignment: .top, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    DetailRow(label: "Average wait", value: Fmt.minutes(activity.averageWaitMinutes))
                    DetailRow(label: "Rework events", value: "\(activity.reworkCount)")
                    DetailRow(label: "Handoffs", value: "\(activity.handoffs)")
                    DetailRow(label: "Roles", value: activity.resources.joined(separator: ", "))
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    DetailRow(label: "Automation fit", value: Fmt.percent(activity.automationScore))
                    Text(activity.automationReason).font(.caption).foregroundStyle(.secondary)
                    GuardrailNote(text: "Fit is a heuristic from volume, repetition and role spread. It is not an automation decision.")
                }
            }
        }
    }

    // MARK: Cases

    private var casesTab: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Card("Cases", subtitle: "\(filteredCases.count) cases in the current filter.", symbol: "list.bullet.rectangle") {
                TextField("Search case or variant", text: $caseSearch)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredCases) { record in
                            Button {
                                selectedCaseID = record.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(String(record.caseID.prefix(14)))
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text(Fmt.minutes(record.cycleMinutes)).font(.caption.monospacedDigit())
                                    }
                                    Text(record.variant).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    HStack(spacing: 4) {
                                        if record.reworkCount > 0 { Chip(text: "\(record.reworkCount) rework", tint: .orange) }
                                        if record.cost > 0 { Chip(text: Fmt.euro(record.cost), tint: .green) }
                                        if !record.attributes.isEmpty {
                                            Chip(text: record.attributes.values.first ?? "", tint: .secondary)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(selectedCase?.id == record.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 520)
            }
            .frame(width: 360)

            if let record = selectedCase {
                caseDetail(record)
            } else {
                ContentUnavailableView("Select a case", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private func caseDetail(_ record: MinedCase) -> some View {
        Card("Case \(record.caseID)", subtitle: "\(Fmt.minutes(record.cycleMinutes)) cycle · \(record.sequence.count) events", symbol: "clock") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Chip(text: "\(record.reworkCount) rework", symbol: "arrow.triangle.2.circlepath",
                         tint: record.reworkCount > 0 ? .orange : .green).fixedSize()
                    Chip(text: "\(record.handoffs) handoffs", symbol: "arrow.left.arrow.right", tint: .purple).fixedSize()
                    if record.cost > 0 { Chip(text: Fmt.euro(record.cost), symbol: "eurosign", tint: .green).fixedSize() }
                }
                if !record.attributes.isEmpty {
                    Text(record.attributes.keys.sorted().map { "\($0)=\(record.attributes[$0] ?? "")" }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(record.variant).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                ForEach(Array(record.events.enumerated()), id: \.offset) { index, event in
                    let previous = index > 0 ? record.events[index - 1] : nil
                    let delta = previous.map { event.timestamp.timeIntervalSince($0.timestamp) / 60 } ?? 0
                    HStack(alignment: .top, spacing: Space.sm) {
                        VStack(spacing: 0) {
                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                            if index < record.events.count - 1 {
                                Rectangle().fill(.quaternary).frame(width: 1, height: 32)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.activity).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(Fmt.stamp(event.timestamp)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text("\(event.resource) · \(event.application)\(delta > 0 ? " · +\(Fmt.minutes(delta))" : "")")
                                .font(.caption2).foregroundStyle(.secondary)
                            if !event.attributes.isEmpty {
                                Text(event.attributes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Conformance

    private var conformanceTab: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Card("Reference", subtitle: "Compare the filtered log with a documented path.", symbol: "checkmark.seal") {
                HStack(spacing: Space.sm) {
                    Text("Process").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        ForEach(processes.filter { process in
                            !steps.filter { $0.processID == process.id }.isEmpty
                        }) { process in
                            Button(process.name) { referenceProcessID = process.id }
                        }
                    } label: {
                        Text(referenceProcess?.name ?? "Choose a process")
                            .font(.subheadline)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    if let conformance {
                        Chip(text: "\(Fmt.percent(conformance.tokenFitness)) token fit",
                             symbol: "checkmark.seal",
                             tint: conformance.tokenFitness > 0.85 ? .green : .orange)
                    }
                }
                if let conformance {
                    HStack(spacing: Space.lg) {
                        MetricTile(title: "Sequence coverage", value: Fmt.percent(conformance.fitness),
                                   detail: "\(conformance.exactCases) exact cases", symbol: "text.line.first.and.arrowtriangle.forward", tint: .teal)
                        MetricTile(title: "Token replay", value: Fmt.percent(conformance.tokenFitness),
                                   detail: "\(conformance.missingTokens) missing · \(conformance.remainingTokens) remaining",
                                   symbol: "arrow.triangle.branch", tint: .orange)
                        MetricTile(title: "Deviating cases", value: "\(conformance.deviatingCases)",
                                   detail: "of \(conformance.totalCases)", symbol: "exclamationmark.triangle", tint: .red)
                    }
                    if let alignment {
                        MetricTile(title: "Optimal alignment", value: Fmt.percent(alignment.fitness),
                                   detail: "\(alignment.perfectCases) perfect · cost \(alignment.totalCost)",
                                   symbol: "arrow.left.arrow.right", tint: .purple)
                    }
                    if !conformance.missingActivities.isEmpty || !conformance.extraActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Missing: \(conformance.missingActivities.prefix(5).joined(separator: " · "))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Extra: \(conformance.extraActivities.prefix(5).joined(separator: " · "))")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("Choose a process with steps to compare.").font(.caption).foregroundStyle(.secondary)
                }
                GuardrailNote(text: "Sequence coverage and token replay answer different questions. Neither is a quality score; a deviation can be a local improvement.")
            }

            if conformance != nil {
                Card("Variant conformance", subtitle: "Which paths fit the reference and which do not.", symbol: "arrow.triangle.swap") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Variant").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Cases").frame(width: 60, alignment: .trailing)
                            Text("Exact").frame(width: 60, alignment: .trailing)
                            Text("Coverage").frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption).foregroundStyle(.tertiary)
                        ForEach(mined.variants.prefix(7)) { variant in
                            let report = ProcessMining.conformance(
                                events: filteredEvents.filter { event in
                                    mined.caseRecords.first(where: { $0.id == event.caseID })?.variant == variant.variant
                                }, reference: referenceSteps)
                            HStack {
                                Text(variant.sequence.prefix(3).joined(separator: " → "))
                                    .font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(variant.cases)").font(.caption.monospacedDigit()).frame(width: 60, alignment: .trailing)
                                Text("\(report.exactCases)").font(.caption.monospacedDigit()).frame(width: 60, alignment: .trailing)
                                Text(Fmt.percent(report.fitness)).font(.caption.monospacedDigit()).frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            RowDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: Insights

    private var insightsTab: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                Text("Root cause").font(.headline)
                Picker("Outcome", selection: $rootOutcome) {
                    ForEach(MiningOutcome.allCases) { outcome in Text(outcome.label).tag(outcome) }
                }
                .labelsHidden()
                .frame(width: 172)
                Spacer()
                Text("Correlation, not proof").font(.caption).foregroundStyle(.tertiary)
            }
            let causes = ProcessMining.rootCauses(mined.caseRecords, outcome: rootOutcome)
            if causes.isEmpty {
                Text("No attribute value has enough cases to compare. Import a case dimension such as region, case type or channel.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Space.md)], spacing: Space.md) {
                    ForEach(causes.prefix(6)) { cause in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Chip(text: cause.dimension, tint: .secondary)
                                Spacer()
                                let delta = cause.averageCycleMinutes - mined.meanCycleMinutes
                                Text(rootOutcome == .slow
                                     ? (delta >= 0 ? "+\(Int(delta.rounded())) min" : "\(Int(delta.rounded())) min")
                                     : Fmt.percent(cause.reworkRate))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(rootOutcome == .slow ? (delta >= 0 ? Color.orange : Color.green) : Color.orange)
                            }
                            Text(cause.value).font(.subheadline.weight(.semibold))
                            Text(cause.impactLabel).font(.caption).foregroundStyle(.secondary)
                            Text("\(cause.cases) cases · \(Fmt.minutes(cause.averageCycleMinutes)) average cycle")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(Space.md)
                        .background(Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            HStack(alignment: .top, spacing: Space.lg) {
                Card("Handover network", subtitle: "Role pairs and the wait between them.", symbol: "arrow.left.arrow.right") {
                    VStack(spacing: 0) {
                        ForEach(mined.handovers.prefix(8)) { handover in
                            HStack {
                                Text("\(handover.from) → \(handover.to)").font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(handover.count)×").font(.caption.monospacedDigit())
                                Text(Fmt.minutes(handover.averageWaitMinutes)).font(.caption2).foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            RowDivider()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Card("Automation candidates", subtitle: "Heuristic fit, for a human test.", symbol: "gearshape.2") {
                    if mined.automationCandidates.isEmpty {
                        Text("No activity clears the 0.55 fit threshold in this view.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(mined.automationCandidates.prefix(6)) { activity in
                                HStack {
                                    Text(activity.name).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.percent(activity.automationScore)).font(.caption.monospacedDigit())
                                        .foregroundStyle(.green)
                                    Text("\(activity.events) ev").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                                RowDivider()
                            }
                        }
                    }
                }
                .frame(width: 300)
            }
        }
    }

    // MARK: Simulate

    private var simulateTab: some View {
        let result = ProcessMining.simulate(mined.caseRecords, simulation)
        return VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .top, spacing: Space.lg) {
                Card("What if?", subtitle: "Pick steps to automate or remove, then reduce rework and wait.", symbol: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(mined.activities.prefix(8)) { activity in
                            HStack(spacing: Space.sm) {
                                Text(activity.name).font(.caption).lineLimit(1)
                                Spacer()
                                Toggle("Automate", isOn: Binding(
                                    get: { simulation.automate.contains(activity.name) },
                                    set: { on in
                                        if on { simulation.automate.insert(activity.name) } else { simulation.automate.remove(activity.name) }
                                    }))
                                .toggleStyle(.checkbox).font(.caption2)
                                Toggle("Remove", isOn: Binding(
                                    get: { simulation.remove.contains(activity.name) },
                                    set: { on in
                                        if on { simulation.remove.insert(activity.name) } else { simulation.remove.remove(activity.name) }
                                    }))
                                .toggleStyle(.checkbox).font(.caption2)
                            }
                        }
                        Divider()
                        HStack {
                            Text("Rework reduction").font(.caption)
                            Slider(value: $simulation.reworkReduction, in: 0...1, step: 0.1)
                            Text(Fmt.percent(simulation.reworkReduction)).font(.caption.monospacedDigit()).frame(width: 44)
                        }
                        HStack {
                            Text("Wait reduction").font(.caption)
                            Slider(value: $simulation.waitReduction, in: 0...1, step: 0.1)
                            Text(Fmt.percent(simulation.waitReduction)).font(.caption.monospacedDigit()).frame(width: 44)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: Space.md) {
                    MetricTile(title: "Projected median", value: Fmt.minutes(result.projectedMedianMinutes),
                               detail: "Baseline \(Fmt.minutes(result.baselineMedianMinutes))",
                               symbol: "timer", tint: .teal)
                    MetricTile(title: "Saved per case", value: Fmt.minutes(result.savedMedianMinutes),
                               detail: "\(result.casesAffected) cases affected", symbol: "arrow.down.right", tint: .green)
                    MetricTile(title: "Hours per 1,000", value: "\(Int(result.savedHoursPer1000.rounded())) h",
                               detail: "Estimate, not a validated saving", symbol: "function", tint: .orange)
                }
                .frame(width: 300)
            }

            Card("The arithmetic", subtitle: "Every assumption is stated.", symbol: "info.circle") {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(result.assumptions, id: \.self) { line in
                        HStack(alignment: .top, spacing: Space.sm) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GuardrailNote(text: "This is a wait arithmetic on observed cases, not a capacity model. Use the queue simulation below for staffing.")
                }
            }

            capacityCard
        }
    }

    private var capacityCard: some View {
        Card("Capacity and queues", subtitle: "Discrete-event simulation: arrivals, FIFO queues and finite role capacity.", symbol: "person.3.sequence") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.md) {
                    Text("Arrivals / day").font(.caption)
                    Stepper(value: $arrivalPerDay, in: 1...200, step: 1) {
                        Text("\(Int(arrivalPerDay))").font(.caption.monospacedDigit()).frame(width: 32)
                    }
                    Text("Days").font(.caption)
                    Stepper(value: $capacityDays, in: 1...60) {
                        Text("\(capacityDays)").font(.caption.monospacedDigit()).frame(width: 24)
                    }
                    Spacer()
                    Button("Run capacity simulation") {
                        capacityResult = CapacitySimulation.run(
                            mined, roles: capacityRoles,
                            arrivalPerDay: arrivalPerDay, days: capacityDays)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if capacityRoles.isEmpty {
                    Text("No roles in the current view.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach($capacityRoles) { $role in
                        HStack(spacing: Space.sm) {
                            Text(role.role).font(.caption).frame(width: 160, alignment: .leading)
                            Text("capacity").font(.caption2).foregroundStyle(.tertiary)
                            Stepper(value: $role.capacity, in: 1...20) {
                                Text("\(role.capacity)").font(.caption.monospacedDigit()).frame(width: 20)
                            }
                            Text("service").font(.caption2).foregroundStyle(.tertiary)
                            TextField("min", value: $role.serviceMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                            Text("min").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                if let result = capacityResult {
                    HStack(spacing: Space.md) {
                        MetricTile(title: "Median cycle", value: Fmt.minutes(result.medianCycleMinutes),
                                   detail: "P90 \(Fmt.minutes(result.p90CycleMinutes))", symbol: "timer", tint: .teal)
                        MetricTile(title: "Average wait", value: Fmt.minutes(result.averageWaitMinutes),
                                   detail: "\(result.cases) simulated cases", symbol: "hourglass", tint: .orange)
                        ForEach(result.utilization.prefix(3)) { role in
                            MetricTile(title: role.role, value: Fmt.percent(role.utilization),
                                       detail: "avg wait \(Fmt.minutes(role.averageWaitMinutes))",
                                       symbol: "person.2", tint: role.utilization > 0.9 ? .red : .green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.assumptions, id: \.self) { Text("• \($0)").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    // MARK: Export

    private func exportCases() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(dataset.name.replacingOccurrences(of: " ", with: "-"))-cases.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["case_id,variant,start,end,cycle_minutes,waiting_minutes,rework_events,handoffs,cost,attributes"]
        for record in mined.caseRecords {
            let attributes = record.attributes.keys.sorted()
                .map { "\($0)=\(record.attributes[$0] ?? "")" }
                .joined(separator: " | ")
            rows.append([
                record.caseID, record.variant,
                record.start.ISO8601Format(), record.end.ISO8601Format(),
                String(format: "%.1f", record.cycleMinutes),
                String(format: "%.1f", record.waitingMinutes),
                "\(record.reworkCount)", "\(record.handoffs)",
                String(format: "%.2f", record.cost), attributes,
            ].map(csv).joined(separator: ","))
        }
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        model.showToast("Cases exported", detail: "\(mined.caseRecords.count) rows · \(url.lastPathComponent)", symbol: "square.and.arrow.up")
    }

    private func exportSummary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(dataset.name.replacingOccurrences(of: " ", with: "-"))-mining.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let summary: [String: Any] = [
            "schema": "processlink-mining/1",
            "dataset": dataset.name,
            "cases": mined.cases,
            "events": mined.events,
            "medianCycleMinutes": mined.medianCycleMinutes,
            "p90CycleMinutes": mined.p90CycleMinutes,
            "reworkRate": mined.reworkRate,
            "handoffRate": mined.handoffRate,
            "totalCost": mined.totalCost,
            "filters": [
                "activity": activityFilter,
                "resource": resourceFilter,
                "attribute": attributeValue,
                "reworkOnly": reworkOnly,
            ],
            "activities": mined.activities.map { [
                "name": $0.name, "events": $0.events, "cases": $0.cases,
                "averageWaitMinutes": $0.averageWaitMinutes, "rework": $0.reworkCount,
                "handoffs": $0.handoffs, "automationScore": $0.automationScore,
            ] },
            "variants": mined.variants.map { [
                "path": $0.variant, "cases": $0.cases, "share": $0.share,
                "averageCycleMinutes": $0.averageCycleMinutes, "reworkRate": $0.reworkRate,
            ] },
            "periods": mined.periods.map { [
                "period": $0.label, "cases": $0.cases, "medianCycleMinutes": $0.medianCycleMinutes,
            ] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
            model.showToast("Mining summary exported", detail: url.lastPathComponent, symbol: "square.and.arrow.up")
        }
    }

    private func csv(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private var footer: some View {
        HStack(spacing: Space.md) {
            Button {
                model.createProcess(from: dataset)
            } label: {
                Label("Create discovered process", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.borderedProminent)
            Text("Writes the filtered view? No — the full dataset. \(mined.cases) cases in view, \(baseline.cases) in the dataset.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Delete dataset", role: .destructive) { model.deleteDataset(dataset) }
                .controlSize(.small)
        }
    }
}

private extension MinedVariant {
    /// The same key the case records use, for variant-level conformance.
    var variant: String { sequence.joined(separator: " → ") }
}


private struct MapActivityMappingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dataset: DatasetRecord
    let map: MapsBridge.Document
    let activities: [String]

    @State private var mapping: [String: String]

    init(dataset: DatasetRecord, map: MapsBridge.Document, activities: [String]) {
        self.dataset = dataset
        self.map = map
        self.activities = activities
        let data = dataset.mapMappingJSON.data(using: .utf8)
        let existing = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: String]) ?? [:]
        _mapping = State(initialValue: existing)
    }

    private var steps: [MapsBridge.Node] {
        map.nodes.filter { $0.type != "start" && $0.type != "end" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map activities to map steps").font(.title3.weight(.semibold))
                    Text("Only mapped activities count towards map coverage.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(activities, id: \.self) { activity in
                        HStack(spacing: Space.sm) {
                            Text(activity).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            Picker("Map step", selection: Binding(
                                get: { mapping[activity] ?? "" },
                                set: { value in
                                    if value.isEmpty { mapping.removeValue(forKey: activity) }
                                    else { mapping[activity] = value }
                                })) {
                                Text("Unmapped").tag("")
                                ForEach(steps) { step in
                                    Text(step.label).tag(step.link?.stepID ?? (step.stepID.isEmpty ? step.id : step.stepID))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 240)
                        }
                        .padding(.vertical, 4)
                        RowDivider()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Save mapping") {
                    if let data = try? JSONSerialization.data(withJSONObject: mapping, options: [.sortedKeys]) {
                        dataset.mapMappingJSON = String(data: data, encoding: .utf8) ?? "{}"
                        try? model.context.save()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.lg)
        .frame(width: 640, height: 620)
    }
}

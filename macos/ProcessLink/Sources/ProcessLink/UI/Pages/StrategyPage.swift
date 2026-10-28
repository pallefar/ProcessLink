import ProcessLinkKit
import SwiftData
import SwiftUI

/// The strategy layer: one function vision, a small set of bets, the KPIs that
/// prove movement, and the values that constrain the countermeasure. Every
/// initiative is traceable to all three.
struct StrategyPage: View {
    @Environment(AppModel.self) private var model
    @Query private var strategies: [StrategyRecord]
    @Query(sort: \StrategicBetRecord.order) private var bets: [StrategicBetRecord]
    @Query(sort: \KPIRecord.name) private var kpis: [KPIRecord]
    @Query(sort: \ValueRecord.order) private var values: [ValueRecord]
    @Query(sort: \InitiativeRecord.createdAt, order: .reverse) private var initiatives: [InitiativeRecord]

    @State private var editingVision = false
    @State private var editingKPI: KPIRecord?
    @State private var linkingInitiative: InitiativeRecord?
    @State private var syncingMapKPIs = false

    private var strategy: StrategyRecord? { strategies.first }
    private var linked: [InitiativeRecord] { initiatives.filter(\.hasStrategyLink) }
    private var unlinked: [InitiativeRecord] { initiatives.filter { !$0.hasStrategyLink } }
    private var onTrackKPIs: [KPIRecord] { kpis.filter(\.onTrack) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Strategy",
                           subtitle: "The function vision, the few bets that matter, the KPIs that prove movement, and the values that constrain how we improve.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(linked.count)/\(initiatives.count) initiatives linked",
                             symbol: unlinked.isEmpty ? "link" : "link.badge.plus",
                             tint: unlinked.isEmpty ? .green : .orange)
                        Chip(text: strategy?.horizon ?? "No horizon", symbol: "calendar", tint: .secondary)
                        Button {
                            syncingMapKPIs = true
                            Task {
                                _ = await model.flightdeck.syncMapKPIs(into: model)
                                syncingMapKPIs = false
                            }
                        } label: {
                            if syncingMapKPIs { ProgressView().controlSize(.small) }
                            else { Label("Sync Maps KPIs", systemImage: "arrow.triangle.2.circlepath") }
                        }
                        .controlSize(.small)
                        .disabled(syncingMapKPIs || !model.flightdeck.isSignedIn)
                        .help("Pull Flightdeck Maps goals, derived metrics and manual KPIs into Strategy")
                    }
                }

                if let strategy {
                    visionCard(strategy)
                } else {
                    ContentUnavailableView("No strategy yet", systemImage: "target",
                                           description: Text("Create the function vision before linking initiatives."))
                }

                HStack(spacing: Space.md) {
                    MetricTile(title: "Strategic bets", value: "\(bets.count)",
                               detail: "\(bets.filter { $0.statusRaw == "active" }.count) active",
                               symbol: "scope", tint: .purple)
                    MetricTile(title: "KPIs on target", value: "\(onTrackKPIs.count)/\(kpis.count)",
                               detail: "Progress against agreed targets", symbol: "chart.line.uptrend.xyaxis", tint: .teal)
                    MetricTile(title: "Linked initiatives", value: "\(linked.count)",
                               detail: unlinked.isEmpty ? "Portfolio fully traceable" : "\(unlinked.count) need a link",
                               symbol: "link", tint: unlinked.isEmpty ? .green : .orange)
                    MetricTile(title: "Values", value: "\(values.count)",
                               detail: "Behavioural guardrails", symbol: "checkmark.seal", tint: .blue)
                }

                HStack(alignment: .top, spacing: Space.lg) {
                    betsCard
                    valuesCard
                }

                kpiCard
                alignmentCard
            }
            .padding(Space.margin)
        }
        .gridArea("strategy")
        .navigationTitle("Strategy")
        .sheet(isPresented: $editingVision) {
            if let strategy { VisionEditor(strategy: strategy) }
        }
        .sheet(item: $editingKPI) { kpi in KPIEditor(kpi: kpi) }
        .sheet(item: $linkingInitiative) { initiative in
            InitiativeStrategyLinkSheet(initiative: initiative)
        }
    }

    // MARK: Vision

    private func visionCard(_ strategy: StrategyRecord) -> some View {
        Card("Function vision", subtitle: "\(strategy.functionName) · owned by \(strategy.owner)", symbol: "target") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(strategy.visionTitle)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Spacer()
                    Button("Edit") { editingVision = true }
                        .controlSize(.small)
                }
                Text(strategy.visionStatement)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) {
                    Chip(text: strategy.horizon, symbol: "calendar", tint: .secondary)
                    Chip(text: "Function: \(strategy.functionName)", symbol: "building.2", tint: .secondary)
                    Spacer()
                    Text("Updated \(Fmt.ago(strategy.updatedAt))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                GuardrailNote(text: "This is a human-owned statement. Linking an initiative does not prove impact; the KPI and before/after evidence do.")
            }
        }
    }

    // MARK: Bets and values

    private var betsCard: some View {
        Card("Strategic bets", subtitle: "Stable choices; initiatives change underneath them.", symbol: "scope") {
            if bets.isEmpty {
                Text("No bets defined.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(bets) { bet in
                        let kpi = kpis.first { $0.id == bet.primaryKPIID }
                        let count = initiatives.filter { $0.strategicBetID == bet.id }.count
                        VStack(alignment: .leading, spacing: Space.sm) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(bet.title).font(.headline)
                                Chip(text: bet.statusRaw.capitalized,
                                     tint: bet.statusRaw == "active" ? .green : .secondary)
                                Spacer()
                                Text(count == 1 ? "1 initiative" : "\(count) initiatives").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(bet.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Space.sm) {
                                Text("Owner \(bet.owner)").font(.caption2).foregroundStyle(.tertiary)
                                if let kpi {
                                    Text("· \(kpi.name)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                ForEach(bet.valueIDs, id: \.self) { id in
                                    if let value = values.first(where: { $0.id == id }) {
                                        Chip(text: value.name, tint: .blue)
                                    }
                                }
                            }
                            if let kpi {
                                progress(kpi)
                            }
                        }
                        .padding(.vertical, Space.sm)
                        if bet.id != bets.last?.id { RowDivider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var valuesCard: some View {
        Card("Values", subtitle: "The countermeasure has to respect these, not just hit the number.", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(values) { value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.name).font(.subheadline.weight(.semibold))
                        Text(value.statement).font(.caption).foregroundStyle(.secondary)
                        Text(value.behaviour).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(width: 320)
    }

    // MARK: KPIs

    private var kpiCard: some View {
        Card("KPIs", subtitle: "A KPI without a definition, baseline, current value and target is a slogan.", symbol: "chart.line.uptrend.xyaxis") {
            VStack(spacing: 0) {
                HStack {
                    Text("KPI").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Baseline").frame(width: 80, alignment: .trailing)
                    Text("Current").frame(width: 80, alignment: .trailing)
                    Text("Target").frame(width: 80, alignment: .trailing)
                    Text("Progress").frame(width: 160, alignment: .leading)
                    Text("").frame(width: 60)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)
                RowDivider()
                ForEach(kpis) { kpi in
                    HStack(alignment: .center, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kpi.name).font(.subheadline.weight(.medium))
                            Text(kpi.strategicBetID.isEmpty ? "No bet" : (bets.first { $0.id == kpi.strategicBetID }?.title ?? "Unknown bet"))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(display(kpi, kpi.baseline)).font(.caption.monospacedDigit()).frame(width: 80, alignment: .trailing)
                        Text(display(kpi, kpi.current)).font(.subheadline.weight(.semibold).monospacedDigit()).frame(width: 80, alignment: .trailing)
                        Text(display(kpi, kpi.target)).font(.caption.monospacedDigit()).frame(width: 80, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            progress(kpi)
                            Text(kpi.onTrack ? "On target" : kpi.direction.label)
                                .font(.caption2).foregroundStyle(kpi.onTrack ? .green : .secondary)
                        }
                        .frame(width: 160, alignment: .leading)
                        Button("Update") { editingKPI = kpi }
                            .controlSize(.mini)
                            .frame(width: 60)
                    }
                    .padding(.vertical, 4)
                    RowDivider()
                }
            }
        }
    }

    private func progress(_ kpi: KPIRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(kpi.onTrack ? Color.green : Color.orange)
                        .frame(width: max(4, proxy.size.width * kpi.progress))
                }
            }
            .frame(height: 4)
            HStack {
                Text("\(Int(kpi.progress * 100))% to target")
                Spacer()
                Text(kpi.cadence)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func display(_ kpi: KPIRecord, _ value: Double) -> String {
        kpi.unit == "%" ? "\(Int(value))%" : "\(Int(value)) \(kpi.unit)"
    }

    // MARK: Alignment

    private var alignmentCard: some View {
        Card("Initiative alignment", subtitle: "Every initiative needs a bet, a KPI and at least one value.", symbol: "link") {
            VStack(spacing: 0) {
                HStack {
                    Text("Initiative").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Strategic bet").frame(width: 192, alignment: .leading)
                    Text("KPI").frame(width: 168, alignment: .leading)
                    Text("Values").frame(width: 192, alignment: .leading)
                    Text("").frame(width: 76)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)
                RowDivider()
                ForEach(initiatives) { initiative in
                    HStack(spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(initiative.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(initiative.processName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(bets.first { $0.id == initiative.strategicBetID }?.title ?? "Not linked")
                            .font(.caption).foregroundStyle(initiative.strategicBetID.isEmpty ? .orange : .secondary)
                            .frame(width: 192, alignment: .leading).lineLimit(1)
                        Text(kpis.first { $0.id == initiative.kpiID }?.name ?? "Not linked")
                            .font(.caption).foregroundStyle(initiative.kpiID.isEmpty ? .orange : .secondary)
                            .frame(width: 168, alignment: .leading).lineLimit(1)
                        Text(valueNames(initiative).joined(separator: " · ").isEmpty ? "Not linked" : valueNames(initiative).joined(separator: " · "))
                            .font(.caption).foregroundStyle(initiative.valueIDs.isEmpty ? .orange : .secondary)
                            .frame(width: 192, alignment: .leading).lineLimit(1)
                        Button("Edit link") { linkingInitiative = initiative }
                            .controlSize(.mini)
                            .frame(width: 76)
                    }
                    .padding(.vertical, 4)
                    RowDivider()
                }
            }
        }
    }

    private func valueNames(_ initiative: InitiativeRecord) -> [String] {
        StrategyDefaults.valueNames(for: initiative.valueIDs, in: model.context)
    }
}

// MARK: - Editors

private struct VisionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let strategy: StrategyRecord

    @State private var functionName: String
    @State private var title: String
    @State private var statement: String
    @State private var horizon: String
    @State private var owner: String

    init(strategy: StrategyRecord) {
        self.strategy = strategy
        _functionName = State(initialValue: strategy.functionName)
        _title = State(initialValue: strategy.visionTitle)
        _statement = State(initialValue: strategy.visionStatement)
        _horizon = State(initialValue: strategy.horizon)
        _owner = State(initialValue: strategy.owner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Function vision").font(.title3.weight(.semibold))
            TextField("Function", text: $functionName).textFieldStyle(.roundedBorder)
            TextField("Vision title", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $statement).frame(height: 100).font(.body)
            HStack {
                TextField("Horizon", text: $horizon).textFieldStyle(.roundedBorder)
                TextField("Owner", text: $owner).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    strategy.functionName = functionName
                    strategy.visionTitle = title
                    strategy.visionStatement = statement
                    strategy.horizon = horizon
                    strategy.owner = owner
                    strategy.updatedAt = .now
                    try? model.context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || statement.isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 560)
    }
}

private struct KPIEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kpi: KPIRecord
    @State private var current: Double

    init(kpi: KPIRecord) {
        self.kpi = kpi
        _current = State(initialValue: kpi.current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(kpi.name).font(.title3.weight(.semibold))
            Text(kpi.definition).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Current").font(.caption)
                TextField("Current", value: $current, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text(kpi.unit).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Baseline \(kpi.baseline.formatted()) → target \(kpi.target.formatted())")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    kpi.current = current
                    kpi.updatedAt = .now
                    try? model.context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.lg)
        .frame(width: 460)
    }
}

struct InitiativeStrategyLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let initiative: InitiativeRecord
    @Query(sort: \StrategicBetRecord.order) private var bets: [StrategicBetRecord]
    @Query(sort: \KPIRecord.name) private var kpis: [KPIRecord]
    @Query(sort: \ValueRecord.order) private var values: [ValueRecord]

    @State private var betID: String
    @State private var kpiID: String
    @State private var valueIDs: Set<String>
    @State private var expectedChange: String
    @State private var contribution: String

    init(initiative: InitiativeRecord) {
        self.initiative = initiative
        _betID = State(initialValue: initiative.strategicBetID)
        _kpiID = State(initialValue: initiative.kpiID)
        _valueIDs = State(initialValue: Set(initiative.valueIDs))
        _expectedChange = State(initialValue: initiative.expectedKPIChange)
        _contribution = State(initialValue: initiative.visionContribution)
    }

    private var selectedBet: StrategicBetRecord? { bets.first { $0.id == betID } }
    private var eligibleKPIs: [KPIRecord] {
        guard !betID.isEmpty else { return kpis }
        return kpis.filter { $0.strategicBetID == betID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Link to strategy").font(.title3.weight(.semibold))
            Text(initiative.title).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strategic bet").font(.caption).foregroundStyle(.secondary)
                    Picker("Strategic bet", selection: $betID) {
                        Text("Select a bet").tag("")
                        ForEach(bets) { bet in Text(bet.title).tag(bet.id) }
                    }
                    .labelsHidden()
                    .onChange(of: betID) { _, _ in
                        if !eligibleKPIs.contains(where: { $0.id == kpiID }) {
                            kpiID = selectedBet?.primaryKPIID ?? eligibleKPIs.first?.id ?? ""
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("KPI").font(.caption).foregroundStyle(.secondary)
                    Picker("KPI", selection: $kpiID) {
                        Text("Select a KPI").tag("")
                        ForEach(eligibleKPIs) { kpi in Text(kpi.name).tag(kpi.id) }
                    }
                    .labelsHidden()
                }
            }
            Text("Values this countermeasure must respect").font(.caption).foregroundStyle(.secondary)
            ForEach(values) { value in
                Toggle(isOn: Binding(
                    get: { valueIDs.contains(value.id) },
                    set: { if $0 { valueIDs.insert(value.id) } else { valueIDs.remove(value.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value.name).font(.subheadline)
                        Text(value.statement).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            TextField("Expected KPI change", text: $expectedChange).textFieldStyle(.roundedBorder)
            TextField("Vision contribution", text: $contribution).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save link") {
                    initiative.strategicBetID = betID
                    initiative.kpiID = kpiID
                    initiative.valueIDsRaw = valueIDs.sorted().joined(separator: ",")
                    initiative.expectedKPIChange = expectedChange
                    initiative.visionContribution = contribution
                    try? model.context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(betID.isEmpty || kpiID.isEmpty || valueIDs.isEmpty
                          || contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 560)
    }
}

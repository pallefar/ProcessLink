import ProcessLinkKit
import SwiftData
import SwiftUI

/// Flightdeck Maps, generated from the discovered process and bound to KG
/// nodes. Shapes are live: the overlay is a query, not a screenshot.
struct MapsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \StepRecord.order) private var steps: [StepRecord]
    @Query(sort: \VariantRecord.share, order: .reverse) private var variants: [VariantRecord]
    @Query private var opportunities: [OpportunityRecord]

    private var eligible: [ProcessRecord] {
        processes.filter { $0.status == .discovered }
    }

    private var process: ProcessRecord? {
        eligible.first { $0.id == model.selectedProcessID } ?? eligible.first
    }

    private var processSteps: [StepRecord] {
        guard let process else { return [] }
        return steps.filter { $0.processID == process.id }.sorted { $0.order < $1.order }
    }

    private var processVariants: [VariantRecord] {
        guard let process else { return [] }
        return variants.filter { $0.processID == process.id }
    }

    private var selectedStep: StepRecord? {
        processSteps.first { $0.id == model.selectedMapStepID }
    }

    private var bestOpportunity: OpportunityRecord? {
        guard let process else { return nil }
        return opportunities.filter { $0.processID == process.id && $0.status != .deferred }
            .max { $0.score.total < $1.score.total }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Process map",
                           subtitle: "Generated from KYP.ai, bound shape by shape to the knowledge graph. Edits here propose a KG change; they never overwrite discovery.") {
                    HStack(spacing: Space.md) {
                        Picker("Process", selection: Binding(get: { process?.id }, set: { model.selectedProcessID = $0; model.selectedMapStepID = nil })) {
                            ForEach(eligible) { item in
                                Text(item.name).tag(Optional(item.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)
                        .accessibilityLabel("Process to map")

                        Button {
                            model.showToast("Map regenerated", detail: "\(processSteps.count) shapes re-bound to live KG nodes.",
                                            symbol: "arrow.triangle.2.circlepath")
                        } label: {
                            Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }

                if let process, !processSteps.isEmpty {
                    if process.isStale {
                        driftBanner(process)
                    }
                    mapCard(process)
                    HStack(alignment: .top, spacing: Space.lg) {
                        nodeInspector
                        variantCard
                    }
                    toBeCard(process)
                } else {
                    ContentUnavailableView("No map to draw",
                                           systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                           description: Text("A process with mined steps is needed. Blocked and suppressed records are never mapped."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(Space.margin)
        }
        .gridArea("maps")
        .navigationTitle("Maps")
        .onAppear {
            if model.selectedMapStepID == nil,
               let hottest = processSteps.max(by: { $0.minutes < $1.minutes }) {
                model.selectedMapStepID = hottest.id
            }
        }
    }

    private func driftBanner(_ process: ProcessRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("This map was last generated from evidence \(process.staleDays) days old. It no longer matches the latest discovery; regenerate or review before using it in a review.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            Button("Sync now") {
                Task { await model.runSync() }
            }
            .controlSize(.small)
        }
        .padding(Space.md)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        }
    }

    private func mapCard(_ process: ProcessRecord) -> some View {
        Card("As-is · \(process.name)",
             subtitle: "\(processSteps.count) steps · \(process.handoffs) handoffs · \(Fmt.minutes(process.cycleMinutes)) median cycle · every shape is a KG node",
             symbol: "point.topleft.down.to.point.bottomright.curvepath") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.md) {
                    Picker("Overlay", selection: Binding(get: { model.mapOverlay }, set: { model.mapOverlay = $0 })) {
                        ForEach(MapOverlay.allCases) { overlay in
                            Label(overlay.label, systemImage: overlay.symbol).tag(overlay)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 520)
                    Spacer()
                    overlayLegend
                }

                ProcessMapCanvas(steps: processSteps, overlay: model.mapOverlay,
                                 selectedID: selectedStep?.id,
                                 onSelect: { step in model.selectedMapStepID = step.id })

                Text("Drawn from \(process.kypID). Hue and the number on each shape carry the same overlay value; the number is the primary channel and the colour is the second.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var overlayLegend: some View {
        HStack(spacing: Space.xs) {
            Text("low").font(.caption2).foregroundStyle(.tertiary)
            LinearGradient(colors: [.green.opacity(0.35), .orange.opacity(0.7), .red.opacity(0.8)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 56, height: 8)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            Text("high").font(.caption2).foregroundStyle(.tertiary)
            Text("· \(model.mapOverlay.label)").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(model.mapOverlay.label) overlay, low to high")
    }

    @ViewBuilder
    private var nodeInspector: some View {
        Card("Shape detail", subtitle: "Click any shape on the map.", symbol: "cursorarrow.click") {
            if let step = selectedStep {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(step.name).font(.headline)
                        Spacer(minLength: Space.sm)
                        Chip(text: step.waste.label, symbol: step.waste.symbol, tint: .orange)
                    }
                    DetailRow(label: "Role", value: step.role)
                    DetailRow(label: "Application", value: step.application)
                    DetailRow(label: "Time", value: Fmt.minutes(step.minutes))
                    DetailRow(label: "Handoffs", value: "\(step.handoffs)")
                    DetailRow(label: "Rework share", value: Fmt.percent(step.reworkShare))
                    DetailRow(label: "Evidence", value: "\(step.evidenceCount) mined events")
                    DetailRow(label: "Standard", value: step.standardAligned ? "Aligned with the SOP" : "Deviates from the SOP")
                    DetailRow(label: "KG node", value: step.kgID, mono: true)
                    HStack(spacing: Space.md) {
                        Button("Open in KG") {
                            model.selectedKGID = step.kgID
                            model.page = .graph
                        }
                        .controlSize(.small)
                        Button("Open SOP") {
                            model.showToast("SOP linked", detail: "Knowledge Guardian will open the linked document.",
                                            symbol: "doc.text")
                        }
                        .controlSize(.small)
                        .disabled(process?.standardDocument.isEmpty ?? true)
                    }
                    GuardrailNote(text: "This shape shows an aggregate. There is no per-person drill-down, by design.")
                }
            } else {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Select a shape to see its KG binding and evidence.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Each shape carries frequency, cycle time, effort, rework and automation potential. Values come from the last successful sync.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var variantCard: some View {
        Card("Variant comparison", subtitle: "Where the paths diverge.", symbol: "arrow.triangle.swap") {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(processVariants.prefix(4)) { variant in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Space.sm) {
                            Text(variant.name).font(.subheadline)
                            Spacer(minLength: Space.sm)
                            Text(Fmt.minutes(variant.cycleMinutes)).font(.caption.monospacedDigit())
                            Text(Fmt.percent(variant.reworkRate) + " rework")
                                .font(.caption)
                                .foregroundStyle(variant.reworkRate > 0.3 ? Color.orange : Color.secondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(variant.reworkRate > 0.3 ? Color.orange : Palette.accent)
                                    .frame(width: max(4, proxy.size.width * variant.share))
                            }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                        Text(variant.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        }
        .frame(width: 340)
    }

    private func toBeCard(_ process: ProcessRecord) -> some View {
        Card("As-is vs to-be", subtitle: "A to-be map is an opportunity, not a promise. Projected saving stays an estimate until validated.", symbol: "rectangle.split.2x1") {
            if let opportunity = bestOpportunity {
                HStack(alignment: .top, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("As-is").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Fmt.hoursPerYear(process.annualHours))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text("\(processSteps.count) steps · \(Fmt.percent(process.reworkRate)) rework")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("To-be").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Fmt.hoursPerYear(max(0, process.annualHours - opportunity.annualHours)))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text("\(opportunity.route.label): \(opportunity.title)")
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    Spacer(minLength: Space.lg)
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Chip(text: "Projected −\(Fmt.hours(opportunity.annualHours))", symbol: "arrow.down.right", tint: .orange)
                        Text("Estimate · \(Fmt.percent(opportunity.confidence)) confidence")
                            .font(.caption).foregroundStyle(.tertiary)
                        Button("Open opportunity") {
                            model.selectedOpportunityID = opportunity.id
                            model.page = .opportunities
                        }
                        .controlSize(.small)
                    }
                }
            } else {
                Text("No opportunity is linked to this process yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - The canvas

/// Swimlanes by role, steps left to right, one arrow per handoff. Built from
/// plain SwiftUI shapes so it can be snapshotted and read by VoiceOver; a
/// production build hands the same node/edge data to DiagramForge.
struct ProcessMapCanvas: View {
    var steps: [StepRecord]
    var overlay: MapOverlay
    var selectedID: String?
    var onSelect: (StepRecord) -> Void

    private var lanes: [String] {
        var seen: [String] = []
        for step in steps where !seen.contains(step.role) { seen.append(step.role) }
        return seen
    }

    private func overlayValue(_ step: StepRecord) -> Double {
        switch overlay {
        case .cycleTime:
            let maxMinutes = max(steps.map(\.minutes).max() ?? 1, 1)
            return step.minutes / maxMinutes
        case .handoffs:
            let maxHandoffs = max(steps.map(\.handoffs).max() ?? 1, 1)
            return Double(step.handoffs) / Double(maxHandoffs)
        case .rework:
            let maxRework = max(steps.map(\.reworkShare).max() ?? 0.01, 0.01)
            return step.reworkShare / maxRework
        case .automation:
            return Self.automationPotential(step.waste)
        }
    }

    private func overlayText(_ step: StepRecord) -> String {
        switch overlay {
        case .cycleTime: Fmt.minutes(step.minutes)
        case .handoffs: "\(step.handoffs) handoff\(step.handoffs == 1 ? "" : "s")"
        case .rework: Fmt.percent(step.reworkShare) + " rework"
        case .automation: Fmt.percent(Self.automationPotential(step.waste)) + " fit"
        }
    }

    static func automationPotential(_ waste: WasteType) -> Double {
        switch waste {
        case .unusedTalent: 0.9
        case .overProcessing: 0.8
        case .rework: 0.65
        case .handoffs: 0.6
        case .contextSwitching: 0.5
        case .defects: 0.45
        case .waiting: 0.35
        case .backlog: 0.25
        }
    }

    private func heat(_ value: Double) -> Color {
        let clamped = min(1, max(0, value))
        if clamped < 0.5 {
            return Color.green.mix(with: .orange, by: clamped * 2)
        }
        return Color.orange.mix(with: .red, by: (clamped - 0.5) * 2)
    }

    private let laneHeight: CGFloat = 116
    private let labelWidth: CGFloat = 120

    private var canvasHeight: CGFloat { CGFloat(max(lanes.count, 1)) * laneHeight + 16 }

    var body: some View {
        GeometryReader { proxy in
            // A 500-node production map gets a viewport and a scroll; the demo
            // map keeps every shape legible instead of squeezing six lanes
            // into one screen and clipping the last step.
            // Fit the columns when they can be legible; scroll only when the
            // process is wider than the window (a real 500-node map always is).
            let available = proxy.size.width - labelWidth - 32
            let columnWidth = max(178, available / CGFloat(max(steps.count, 1)))
            let nodeWidth = min(160, columnWidth - 18)
            let needed = labelWidth + 32 + columnWidth * CGFloat(steps.count)
            let canvasWidth = max(needed, proxy.size.width)

            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(lanes.enumerated()), id: \.element) { index, lane in
                        let y = CGFloat(index) * laneHeight + 8
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(index.isMultiple(of: 2)
                                  ? Color(nsColor: .controlBackgroundColor).opacity(0.55)
                                  : Color(nsColor: .windowBackgroundColor).opacity(0.35))
                            .frame(width: canvasWidth, height: laneHeight - 8)
                            .offset(y: y) // grid: ok computed lane geometry

                        HStack(spacing: Space.xs) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(lane)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(width: labelWidth - 16, alignment: .leading)
                        .offset(x: 12, y: y + (laneHeight - 8) / 2 - 14) // grid: ok computed lane geometry
                    }

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0, let laneIndex = lanes.firstIndex(of: step.role),
                           let previousLane = lanes.firstIndex(of: steps[index - 1].role) {
                            let x1: CGFloat = labelWidth + 16 + CGFloat(index - 1) * columnWidth
                            let x2: CGFloat = labelWidth + 16 + CGFloat(index) * columnWidth
                            let y1: CGFloat = CGFloat(previousLane) * laneHeight + laneHeight / 2 + 4
                            let y2: CGFloat = CGFloat(laneIndex) * laneHeight + laneHeight / 2 + 4
                            let from = CGPoint(x: x1 + nodeWidth, y: y1)
                            let to = CGPoint(x: x2, y: y2)
                            FlowEdgeShape(from: from, to: to)
                                .stroke(Color.secondary.opacity(0.45),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .accessibilityHidden(true)
                        }
                    }

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let laneIndex = lanes.firstIndex(of: step.role) ?? 0
                        let value = overlayValue(step)
                        let x: CGFloat = labelWidth + 16 + CGFloat(index) * columnWidth
                        let y: CGFloat = CGFloat(laneIndex) * laneHeight + (laneHeight - 8) / 2 - 30
                        MapNodeView(step: step, overlayText: overlayText(step),
                                    heat: heat(value), selected: selectedID == step.id,
                                    width: nodeWidth, showWaste: nodeWidth >= 140)
                            .frame(width: nodeWidth)
                            .offset(x: x, y: y) // grid: ok computed lane geometry
                            .onTapGesture { onSelect(step) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(step.name), \(step.role), \(overlayText(step))")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .overlay(alignment: .bottomTrailing) {
                if needed > proxy.size.width + 1 {
                    Chip(text: "Scroll for the remaining steps", symbol: "arrow.right", tint: .secondary)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .trailing) {
                if needed > proxy.size.width + 1 {
                    LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 36)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: canvasHeight)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MapNodeView: View {
    var step: StepRecord
    var overlayText: String
    var heat: Color
    var selected: Bool
    var width: CGFloat
    var showWaste: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(step.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if step.waste == .handoffs {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.application)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(overlayText)
                    .font(.caption2.weight(.medium).monospacedDigit())
                Spacer(minLength: 0)
                if showWaste {
                    Text(step.waste.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Image(systemName: step.waste.symbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 60)
        .background(heat.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Palette.accent : Color(nsColor: .separatorColor),
                              lineWidth: selected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("\(step.name) · \(step.application) · \(overlayText)")
    }
}

/// A left-to-right flow with a visible arrowhead, so direction never depends
/// on colour or animation.
private nonisolated struct FlowEdgeShape: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = max(24, (to.x - from.x) * 0.45)
        path.move(to: from)
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + dx, y: from.y),
                      control2: CGPoint(x: to.x - dx, y: to.y))

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = 6
        let left = CGPoint(x: to.x - head * cos(angle - .pi / 7),
                           y: to.y - head * sin(angle - .pi / 7))
        let right = CGPoint(x: to.x - head * cos(angle + .pi / 7),
                            y: to.y - head * sin(angle + .pi / 7))
        path.move(to: to)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// Mixes two colors in sRGB. Used only for the heat ramp, where a
    /// continuous scale is the point and the number is always printed too.
    func mix(with other: Color, by amount: Double) -> Color {
        let t = min(1, max(0, amount))
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .systemGray
        let target = NSColor(other).usingColorSpace(.sRGB) ?? .systemGray
        return Color(nsColor: NSColor(
            srgbRed: base.redComponent + (target.redComponent - base.redComponent) * t,
            green: base.greenComponent + (target.greenComponent - base.greenComponent) * t,
            blue: base.blueComponent + (target.blueComponent - base.blueComponent) * t,
            alpha: base.alphaComponent + (target.alphaComponent - base.alphaComponent) * t))
    }
}

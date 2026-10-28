import ProcessLinkKit
import SwiftData
import SwiftUI

/// The shared backbone, explored visually: a radial canvas, search, quality
/// filters, backlinks, and a human review queue for uncertain matches.
struct GraphPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \KGNodeRecord.name) private var nodes: [KGNodeRecord]
    @Query private var edges: [KGEdgeRecord]
    @Query private var processes: [ProcessRecord]
    @Query private var meetings: [MeetingRecord]
    @Query private var initiatives: [InitiativeRecord]
    @Query private var opportunities: [OpportunityRecord]

    private var graphNodes: [GraphNode] {
        nodes.map { GraphNode(id: $0.id, kind: $0.kind, name: $0.name,
                              confidence: $0.confidence,
                              validTo: $0.validTo) }
    }

    private var graphEdges: [GraphEdge] {
        edges.map { GraphEdge(from: $0.fromID, to: $0.toID,
                              predicate: $0.predicate, confidence: $0.confidence) }
    }

    private var orphanIDs: Set<String> { KGGraph.orphanIDs(nodes: graphNodes, edges: graphEdges) }

    private var duplicates: [DuplicatePair] {
        KGGraph.duplicatePairs(nodes: graphNodes.filter { $0.validTo == nil }, threshold: 0.78)
    }

    private var duplicateIDs: Set<String> {
        Set(duplicates.flatMap { [$0.left, $0.right] })
    }

    private var suggested: [KGNodeRecord] { nodes.filter { $0.review == .suggested } }

    private var ordered: [KGNodeRecord] {
        nodes.sorted { lhs, rhs in
            let left = KGKind.allCases.firstIndex(of: lhs.kind) ?? 99
            let right = KGKind.allCases.firstIndex(of: rhs.kind) ?? 99
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func matchesQuality(_ node: KGNodeRecord) -> Bool {
        switch model.graphQuality {
        case .all: return true
        case .review: return node.review == .suggested
        case .orphan: return orphanIDs.contains(node.id)
        case .duplicate: return duplicateIDs.contains(node.id)
        case .stale: return node.validTo != nil
        case .changed: return node.updatedAt > model.now.addingTimeInterval(-7 * 86_400)
        }
    }

    private func matchesSearch(_ node: KGNodeRecord) -> Bool {
        let query = model.graphSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return node.name.lowercased().contains(query)
            || node.id.lowercased().contains(query)
            || node.note.lowercased().contains(query)
    }

    private var filtered: [KGNodeRecord] {
        ordered.filter { node in
            (model.graphFilter == nil || node.kind == model.graphFilter)
                && matchesQuality(node) && matchesSearch(node)
        }
    }

    private var selected: KGNodeRecord? {
        nodes.first { $0.id == model.selectedKGID }
            ?? suggested.first
            ?? filtered.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Knowledge graph",
                           subtitle: "The shared semantic backbone. KYP.ai facts, meetings, decisions and actions become nodes with provenance; ProcessLink proposes, a human confirms.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(nodes.count) nodes", symbol: "circle.hexagongrid", tint: .blue)
                        Chip(text: "\(edges.count) edges", symbol: "arrow.triangle.branch", tint: .purple)
                        Chip(text: "\(suggested.count) to review", symbol: "person.crop.circle.badge.questionmark", tint: .orange)
                    }
                }

                metrics
                qualityBar
                graphCard
                if !suggested.isEmpty { reviewQueue }
                HStack(alignment: .top, spacing: Space.lg) {
                    nodeColumn
                    detail
                }
            }
            .padding(Space.margin)
        }
        .gridArea("graph")
        .navigationTitle("Knowledge Graph")
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: Space.md) {
            MetricTile(title: "Nodes", value: "\(nodes.count)",
                       detail: "\(Set(nodes.map(\.kind)).count) of 29 types in use",
                       symbol: "circle.hexagongrid", tint: .blue)
            MetricTile(title: "Edges", value: "\(edges.count)",
                       detail: "Provenance on every one", symbol: "arrow.triangle.branch", tint: .purple)
            MetricTile(title: "Orphans", value: "\(orphanIDs.count)",
                       detail: orphanIDs.isEmpty ? "Every node is connected" : "Nodes with no relation",
                       symbol: "link.badge.plus", tint: orphanIDs.isEmpty ? .green : .orange)
            MetricTile(title: "Duplicate candidates", value: "\(duplicates.count)",
                       detail: "Name matches a human reviews", symbol: "doc.on.doc",
                       tint: duplicates.isEmpty ? .green : .orange)
        }
    }

    private var qualityBar: some View {
        HStack(spacing: Space.xs) {
            ForEach(GraphQuality.allCases) { quality in
                Button {
                    model.graphQuality = quality
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: quality.symbol).font(.caption2)
                        Text(quality.label).font(.caption)
                        Text("\(count(for: quality))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.graphQuality == quality ? Palette.accent.opacity(0.14) : Color.clear,
                                in: Capsule())
                    .overlay { Capsule().strokeBorder(.separator, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.graphQuality == quality ? .isSelected : [])
            }
            Spacer()
            Text("\(filtered.count) shown")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func count(for quality: GraphQuality) -> Int {
        switch quality {
        case .all: nodes.count
        case .review: suggested.count
        case .orphan: orphanIDs.count
        case .duplicate: duplicateIDs.count
        case .stale: nodes.filter { $0.validTo != nil }.count
        case .changed: nodes.filter { $0.updatedAt > model.now.addingTimeInterval(-7 * 86_400) }.count
        }
    }

    private var graphCard: some View {
        Card("Graph", subtitle: "Click a node to focus its neighbourhood. Positions are stable, not simulated.", symbol: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField("Search nodes, ids, notes", text: Binding(
                            get: { model.graphSearch },
                            set: { model.graphSearch = $0 }))
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !model.graphSearch.isEmpty {
                            Button {
                                model.graphSearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 4)
                    .frame(width: 260)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Picker("Type", selection: Binding(
                        get: { model.graphFilter },
                        set: { model.graphFilter = $0 })) {
                        Text("All types").tag(KGKind?.none)
                        ForEach(KGKind.allCases.filter { kind in nodes.contains { $0.kind == kind } }) { kind in
                            Text(kind.label).tag(Optional(kind))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Node type")

                    Spacer()

                    if let focused = nodes.first(where: { $0.id == model.selectedKGID }) {
                        Chip(text: "Focused: \(focused.name)", symbol: "scope", tint: .blue)
                        Button("Reset") { model.selectedKGID = nil }
                            .controlSize(.small)
                    }
                }

                GraphCanvas(nodes: nodes, edges: edges, selectedID: model.selectedKGID) { id in
                    model.selectedKGID = id
                }

                HStack(spacing: Space.md) {
                    legend(.process, "Process")
                    legend(.step, "Step")
                    legend(.opportunity, "Opportunity")
                    legend(.initiative, "Initiative")
                    legend(.meeting, "Meeting")
                    legend(.decision, "Decision")
                    legend(.action, "Action")
                    Spacer()
                    Text("Edge thickness and opacity: confidence and focus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func legend(_ kind: KGKind, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(.secondary.opacity(0.35))
                .overlay { Circle().strokeBorder(.secondary, lineWidth: 1) }
                .frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var reviewQueue: some View {
        Card("Entity resolution queue",
             subtitle: "Low-confidence matches are proposals. They stay separate until a human confirms or rejects them.",
             symbol: "person.crop.circle.badge.questionmark") {
            VStack(spacing: 0) {
                ForEach(suggested) { node in
                    HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                        Image(systemName: node.kind.symbol)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name).font(.subheadline.weight(.medium))
                            Text(node.note.isEmpty ? "Proposed by entity resolution." : node.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: Space.sm)
                        ConfidenceChip(confidence: node.confidence)
                        if let target = mergeTarget(node) {
                            Button("Merge into \(target.name)") {
                                model.confirmKGNode(node, mergeInto: target.id)
                            }
                            .controlSize(.small)
                        }
                        Button("Keep separate") { model.confirmKGNode(node, mergeInto: nil) }
                            .controlSize(.small)
                        Button("Reject", role: .destructive) { model.rejectKGNode(node) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, Space.sm)
                    if node.id != suggested.last?.id { RowDivider() }
                }
            }
        }
    }

    private var nodeColumn: some View {
        Card("Nodes", subtitle: "Filtered by quality and search.", symbol: "line.3.horizontal.decrease") {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { node in
                        Button {
                            model.selectedKGID = node.id
                        } label: {
                            SelectableRow(selected: selected?.id == node.id) {
                                HStack(spacing: Space.sm) {
                                    Image(systemName: node.kind.symbol)
                                        .frame(width: 20)
                                        .foregroundStyle(node.review == .suggested ? .orange : .secondary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(node.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text("\(node.kind.label) · \(edges.filter { $0.fromID == node.id || $0.toID == node.id }.count) edges")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                    if node.review == .suggested {
                                        Chip(text: "Review", tint: .orange)
                                    } else if node.validTo != nil {
                                        Chip(text: "Closed", tint: .secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text("No node matches this filter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(Space.md)
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: 420)
        }
        .frame(width: 380)
    }

    @ViewBuilder
    private var detail: some View {
        if let node = selected {
            Card(node.kind.label, subtitle: node.name, symbol: node.kind.symbol) {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.sm) {
                        Chip(text: node.validTo == nil ? node.review.label : "Closed",
                             symbol: node.review == .suggested ? "questionmark.circle" : "checkmark.circle",
                             tint: node.validTo != nil ? .secondary : node.review == .suggested ? .orange : .green)
                        ConfidenceChip(confidence: node.confidence)
                        if let meeting = meeting(for: node) {
                            Button("Open meeting") {
                                model.selectedMeetingID = meeting.id
                                model.page = .meetings
                            }
                            .controlSize(.small)
                        }
                        if let process = relatedProcess(node) {
                            Button("Open process") {
                                model.selectedProcessID = process.id
                                model.page = .discoveries
                            }
                            .controlSize(.small)
                        }
                        if let initiative = relatedInitiative(node) {
                            Button("Open initiative") {
                                model.selectedInitiativeID = initiative.id
                                model.page = .improvements
                            }
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Node id", value: node.id, mono: true)
                        DetailRow(label: "Source", value: node.source)
                        DetailRow(label: "Source id", value: node.sourceID, mono: true)
                        DetailRow(label: "Valid from", value: Fmt.day(node.validFrom))
                        if let validTo = node.validTo {
                            DetailRow(label: "Valid to", value: Fmt.day(validTo))
                        }
                        DetailRow(label: "Last changed", value: Fmt.stamp(node.updatedAt))
                        if !node.note.isEmpty {
                            DetailRow(label: "Note", value: node.note)
                        }
                    }

                    Divider().opacity(0.6)

                    if !outgoing(node).isEmpty {
                        Text("Outgoing").font(.headline)
                        relationList(outgoing(node))
                    }
                    if !incoming(node).isEmpty {
                        Text("Backlinks").font(.headline)
                        relationList(incoming(node))
                    }
                    if outgoing(node).isEmpty && incoming(node).isEmpty {
                        Text("No relations yet. An orphan node is a data-quality finding, not an error to hide.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if node.review == .suggested {
                        HStack(spacing: Space.md) {
                            if let target = mergeTarget(node) {
                                Button("Merge into \(target.name)") {
                                    model.confirmKGNode(node, mergeInto: target.id)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Button("Confirm as separate") { model.confirmKGNode(node, mergeInto: nil) }
                            Button("Reject", role: .destructive) { model.rejectKGNode(node) }
                        }
                    }

                    GuardrailNote(text: "Every fact carries source, confidence and validity. A merge closes the losing node and moves its edges; changes are proposals, not silent overwrites.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("No node selected", systemImage: "circle.hexagongrid")
                .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private struct Relation: Identifiable {
        var id: String
        var label: String
        var otherID: String
        var otherName: String
        var confidence: Double
    }

    private func outgoing(_ node: KGNodeRecord) -> [Relation] {
        edges.filter { $0.fromID == node.id }.map { edge in
            Relation(id: edge.id, label: edge.predicate.label, otherID: edge.toID,
                     otherName: nodes.first { $0.id == edge.toID }?.name ?? edge.toID,
                     confidence: edge.confidence)
        }
    }

    private func incoming(_ node: KGNodeRecord) -> [Relation] {
        edges.filter { $0.toID == node.id }.map { edge in
            Relation(id: edge.id, label: "← " + edge.predicate.label, otherID: edge.fromID,
                     otherName: nodes.first { $0.id == edge.fromID }?.name ?? edge.fromID,
                     confidence: edge.confidence)
        }
    }

    private func relationList(_ relations: [Relation]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(relations) { relation in
                Button {
                    model.selectedKGID = relation.otherID
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(relation.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 124, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(relation.otherName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text(Fmt.percent(relation.confidence))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mergeTarget(_ node: KGNodeRecord) -> KGNodeRecord? {
        guard let edge = edges.first(where: { $0.fromID == node.id && $0.predicate == .variantOf }) else { return nil }
        return nodes.first { $0.id == edge.toID }
    }

    private func relatedProcess(_ node: KGNodeRecord) -> ProcessRecord? {
        processes.first { $0.kgID == node.id || (!node.processID.isEmpty && $0.id == node.processID) }
    }

    private func relatedInitiative(_ node: KGNodeRecord) -> InitiativeRecord? {
        guard node.kind == .initiative else { return nil }
        return initiatives.first { "kg-ini-\($0.id)" == node.id }
    }

    private func meeting(for node: KGNodeRecord) -> MeetingRecord? {
        if node.kind == .meeting {
            return meetings.first { $0.kgID == node.id }
        }
        guard node.kind == .decision || node.kind == .action else { return nil }
        guard let edge = edges.first(where: { $0.fromID == node.id && $0.predicate == .documentedIn }) else { return nil }
        return meetings.first { $0.kgID == edge.toID }
    }
}

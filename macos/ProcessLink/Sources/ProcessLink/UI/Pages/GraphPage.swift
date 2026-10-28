import ProcessLinkKit
import SwiftData
import SwiftUI

/// The graph the rest of the product stands on: typed nodes, typed edges,
/// provenance, and a human review queue for uncertain matches.
struct GraphPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \KGNodeRecord.name) private var nodes: [KGNodeRecord]
    @Query private var edges: [KGEdgeRecord]
    @Query private var processes: [ProcessRecord]

    private var kinds: [KGKind] {
        KGKind.allCases.filter { kind in nodes.contains { $0.kind == kind } }
    }

    private var ordered: [KGNodeRecord] {
        nodes.sorted { lhs, rhs in
            let left = KGKind.allCases.firstIndex(of: lhs.kind) ?? 99
            let right = KGKind.allCases.firstIndex(of: rhs.kind) ?? 99
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var filtered: [KGNodeRecord] {
        guard let filter = model.graphFilter else { return ordered }
        return ordered.filter { $0.kind == filter }
    }

    private var suggested: [KGNodeRecord] {
        nodes.filter { $0.review == .suggested }
    }

    private var selected: KGNodeRecord? {
        filtered.first { $0.id == model.selectedKGID }
            ?? nodes.first { $0.id == model.selectedKGID }
            ?? suggested.first
            ?? filtered.first
    }

    private var edgeCount: (KGNodeRecord) -> Int {
        { node in
            edges.filter { $0.fromID == node.id || $0.toID == node.id }.count
        }
    }

    private var orphanCount: Int {
        nodes.filter { edgeCount($0) == 0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Knowledge graph",
                           subtitle: "The shared semantic backbone. KYP.ai facts become nodes with provenance; ProcessLink proposes, a human confirms.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(nodes.count) nodes", symbol: "circle.hexagongrid", tint: .blue)
                        Chip(text: "\(edges.count) edges", symbol: "arrow.triangle.branch", tint: .purple)
                        Chip(text: "\(suggested.count) to review", symbol: "person.crop.circle.badge.questionmark", tint: .orange)
                    }
                }

                metrics
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
                       detail: "\(kinds.count) of 25 proposed types in use", symbol: "circle.hexagongrid", tint: .blue)
            MetricTile(title: "Edges", value: "\(edges.count)",
                       detail: "Provenance on every one", symbol: "arrow.triangle.branch", tint: .purple)
            MetricTile(title: "Orphans", value: "\(orphanCount)",
                       detail: orphanCount == 0 ? "Every node is connected" : "Nodes with no relation",
                       symbol: "exclamationmark.circle", tint: orphanCount == 0 ? .green : .orange)
            MetricTile(title: "Uncertain matches", value: "\(suggested.count)",
                       detail: "Never merged without a human", symbol: "person.crop.circle.badge.questionmark",
                       tint: suggested.isEmpty ? .green : .orange)
        }
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
                        Button("Keep separate") {
                            model.confirmKGNode(node, mergeInto: nil)
                        }
                        .controlSize(.small)
                        Button("Reject", role: .destructive) {
                            model.rejectKGNode(node)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, Space.sm)
                    if node.id != suggested.last?.id { RowDivider() }
                }
            }
        }
    }

    private var nodeColumn: some View {
        Card("Nodes", subtitle: "Filter by type.", symbol: "line.3.horizontal.decrease") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Picker("Type", selection: Binding(
                        get: { model.graphFilter },
                        set: { model.graphFilter = $0 })) {
                        Text("All types").tag(KGKind?.none)
                        ForEach(kinds) { kind in
                            Text(kind.label).tag(Optional(kind))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Filter nodes by type")

                    Spacer(minLength: Space.sm)
                    Text("\(filtered.count) shown")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

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
                                            .foregroundStyle(node.review == .suggested ? Color.orange : Color.secondary)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(node.name)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text("\(node.kind.label) · \(edgeCount(node)) edges")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer(minLength: 0)
                                        if node.review == .suggested {
                                            Chip(text: "Review", tint: .orange)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 280, maxHeight: 380)
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    private var detail: some View {
        if let node = selected {
            Card(node.kind.label, subtitle: node.name, symbol: node.kind.symbol) {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.sm) {
                        Chip(text: node.review.label,
                             symbol: node.review == .suggested ? "questionmark.circle" : "checkmark.circle",
                             tint: node.review == .suggested ? .orange : .green)
                        ConfidenceChip(confidence: node.confidence)
                        if let process = relatedProcess(node) {
                            Button("Open process") {
                                model.selectedProcessID = process.id
                                model.page = .discoveries
                            }
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Node id", value: node.id, mono: true)
                        DetailRow(label: "Source", value: node.source)
                        DetailRow(label: "Source id", value: node.sourceID, mono: true)
                        DetailRow(label: "Valid from", value: Fmt.day(node.validFrom))
                        DetailRow(label: "Last changed", value: Fmt.stamp(node.updatedAt))
                        if !node.note.isEmpty {
                            DetailRow(label: "Note", value: node.note)
                        }
                    }

                    Divider().opacity(0.6)

                    Text("Relations").font(.headline)
                    if relations(for: node).isEmpty {
                        Text("No relations yet. An orphan node is a data-quality finding, not an error to hide.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            ForEach(relations(for: node)) { relation in
                                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                    Text(relation.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 112, alignment: .leading)
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
                                .onTapGesture { model.selectedKGID = relation.otherID }
                            }
                        }
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

                    GuardrailNote(text: "Every fact carries source, confidence and validity. A point-in-time query can reconstruct what the graph said last quarter; changes are proposals, not silent overwrites.")
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

    private func relations(for node: KGNodeRecord) -> [Relation] {
        edges.compactMap { edge in
            guard edge.fromID == node.id || edge.toID == node.id else { return nil }
            let outgoing = edge.fromID == node.id
            let otherID = outgoing ? edge.toID : edge.fromID
            let other = nodes.first { $0.id == otherID }
            return Relation(id: edge.id,
                            label: outgoing ? edge.predicate.label : "← " + edge.predicate.label,
                            otherID: otherID,
                            otherName: other?.name ?? otherID,
                            confidence: edge.confidence)
        }
    }

    private func mergeTarget(_ node: KGNodeRecord) -> KGNodeRecord? {
        guard let edge = edges.first(where: { $0.fromID == node.id && $0.predicate == .variantOf }) else { return nil }
        return nodes.first { $0.id == edge.toID }
    }

    private func relatedProcess(_ node: KGNodeRecord) -> ProcessRecord? {
        processes.first { $0.kgID == node.id || $0.id == node.processID }
    }
}

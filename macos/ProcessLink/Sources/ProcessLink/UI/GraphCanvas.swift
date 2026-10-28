import ProcessLinkKit
import SwiftUI

/// The graph, drawn two ways:
///   • overview — a layered left-to-right map: process → opportunity →
///     initiative → meeting → decision, which is how the work actually flows;
///   • focused — one node in the centre with its neighbourhood around it.
/// Positions are deterministic, so a screenshot and a returning user see the
/// same picture. No force simulation runs in the UI.
struct GraphCanvas: View {
    var nodes: [KGNodeRecord]
    var edges: [KGEdgeRecord]
    var selectedID: String?
    var onSelect: (String) -> Void

    private let overviewKinds: Set<KGKind> = [
        .process, .opportunity, .initiative, .meeting, .decision, .hoshinObjective,
    ]

    private var displayNodes: [KGNodeRecord] {
        selectedID == nil ? nodes.filter { overviewKinds.contains($0.kind) } : nodes
    }

    private func colour(_ kind: KGKind) -> Color {
        switch kind {
        case .process: .blue
        case .step: .teal
        case .application: .indigo
        case .role, .team, .site, .businessUnit: .secondary
        case .valueStream: .mint
        case .opportunity: .orange
        case .initiative: .purple
        case .savingsRecord: .green
        case .hoshinObjective: .red
        case .meeting: .pink
        case .decision: .green
        case .action: .yellow
        default: .secondary
        }
    }

    private func radius(_ kind: KGKind) -> CGFloat {
        switch kind {
        case .process: 15
        case .opportunity, .initiative, .meeting: 11
        case .step, .decision, .action: 8
        default: 6
        }
    }

    private func label(_ node: KGNodeRecord, total: Int) -> Bool {
        if node.id == selectedID { return true }
        if node.review == .suggested { return true }
        if total > 50 { return node.kind == .process || node.kind == .meeting }
        return node.kind != .decision && node.kind != .action
    }

    private func positions(in size: CGSize) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        let selectedEdges = edges.map {
            GraphEdge(from: $0.fromID, to: $0.toID, predicate: $0.predicate, confidence: $0.confidence)
        }

        if let selectedID, let focus = nodes.first(where: { $0.id == selectedID }) {
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let usable = min(size.width, size.height) / 2 - 54
            result[focus.id] = centre

            let first = Array(KGGraph.neighbours(of: focus.id, in: selectedEdges))
            placeRadial(nodes.filter { first.contains($0.id) }, centre: centre,
                        radius: usable * 0.58, into: &result)

            let secondIDs = KGGraph.neighbourhood(of: focus.id, in: selectedEdges, depth: 2)
            let second = nodes.filter {
                secondIDs.contains($0.id) && !first.contains($0.id) && $0.id != focus.id
            }
            placeRadial(second, centre: centre, radius: usable * 0.95, into: &result)
            return result
        }

        // Layered overview. Columns follow the value path; nodes stack
        // vertically inside a column.
        let columns: [(Set<KGKind>, CGFloat)] = [
            ([.process], 0.10),
            ([.opportunity], 0.32),
            ([.initiative], 0.54),
            ([.meeting, .decision], 0.72),
            ([.hoshinObjective], 0.92),
        ]
        let top: CGFloat = 38
        let bottom = size.height - 38
        for (kinds, x) in columns {
            let values = displayNodes
                .filter { kinds.contains($0.kind) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !values.isEmpty else { continue }
            let spacing = values.count > 1 ? (bottom - top) / CGFloat(values.count - 1) : 0
            for (index, node) in values.enumerated() {
                result[node.id] = CGPoint(x: size.width * x, y: top + spacing * CGFloat(index))
            }
        }
        return result
    }

    private func placeRadial(_ values: [KGNodeRecord], centre: CGPoint, radius: CGFloat,
                             into result: inout [String: CGPoint]) {
        guard !values.isEmpty else { return }
        for (index, node) in values.enumerated() {
            let angle = (Double(index) / Double(values.count)) * 2 * .pi - .pi / 2
            result[node.id] = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius,
                                      y: centre.y + CGFloat(sin(angle)) * radius)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let points = positions(in: proxy.size)
            let shown = displayNodes.filter { points[$0.id] != nil }
            ZStack {
                Canvas { context, _ in
                    for edge in edges {
                        guard let a = points[edge.fromID], let b = points[edge.toID] else { continue }
                        let focused = edge.fromID == selectedID || edge.toID == selectedID
                        var path = Path()
                        path.move(to: a)
                        if selectedID == nil {
                            // A soft elbow reads as a value path, not a web.
                            let mid = CGPoint(x: (a.x + b.x) / 2, y: a.y)
                            path.addCurve(to: b, control1: mid, control2: CGPoint(x: mid.x, y: b.y))
                        } else {
                            path.addLine(to: b)
                        }
                        context.stroke(path,
                                       with: .color(Color.secondary.opacity(focused ? 0.5 : 0.16)),
                                       lineWidth: focused ? 1.4 : 0.8)
                    }
                }
                .accessibilityHidden(true)

                // Column headers: the value path is the point of the layout.
                columnHeader("Process", x: 0.10, width: proxy.size.width)
                columnHeader("Opportunity", x: 0.32, width: proxy.size.width)
                columnHeader("Initiative", x: 0.54, width: proxy.size.width)
                columnHeader("Meeting / decision", x: 0.72, width: proxy.size.width)
                columnHeader("Objective", x: 0.92, width: proxy.size.width)

                ForEach(shown) { node in
                    let point = points[node.id] ?? .zero
                    Button {
                        onSelect(node.id)
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(colour(node.kind).opacity(0.2))
                                .overlay {
                                    Circle().strokeBorder(colour(node.kind).opacity(node.review == .suggested ? 0.95 : 0.7),
                                                          lineWidth: selectedID == node.id ? 2.4 : 1)
                                }
                                .frame(width: radius(node.kind) * 2, height: radius(node.kind) * 2)
                            if label(node, total: shown.count) {
                                Text(shortName(node.name))
                                    .font(.system(size: 9.5, weight: selectedID == node.id ? .semibold : .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 104)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .position(point) // grid: ok computed graph coordinate
                    .accessibilityLabel("\(node.kind.label), \(node.name)")
                    .help("\(node.kind.label) · \(node.name)")
                }
            }
        }
        .frame(minHeight: 380)
        .background {
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 0, through: size.width, by: 24) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: 24) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(Color.secondary.opacity(0.055)), lineWidth: 0.5) // grid: ok hairline canvas stroke
            }
        }
    }

    private func columnHeader(_ text: String, x: CGFloat, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .position(x: width * x, y: 12) // grid: ok canvas column header
            .accessibilityHidden(true)
            .opacity(selectedID == nil ? 1 : 0)
    }

    private func shortName(_ name: String) -> String {
        name.count > 24 ? String(name.prefix(23)) + "…" : name
    }
}

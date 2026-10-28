import ProcessLinkKit
import SwiftUI

/// A deterministic directly-follows graph. Activities are placed in columns by
/// their longest path from a start activity; edge width is frequency and node
/// hue is average wait. Clicking a node selects the activity, it does not
/// mutate the log.
struct MiningProcessGraph: View {
    var mined: MinedProcess
    var selected: String?
    var onSelect: (String) -> Void

    private let nodeWidth: CGFloat = 120
    private let nodeHeight: CGFloat = 56
    private let columnWidth: CGFloat = 120
    private let rowHeight: CGFloat = 88

    private var ranks: [String: Int] {
        // Use the dominant path for column order. A longest-path walk over a
        // graph with rework loops never terminates, which is how the first
        // draft pushed activities off the canvas.
        var rank: [String: Int] = [:]
        var next = 0
        for activity in mined.topVariant?.sequence ?? [] where rank[activity] == nil {
            rank[activity] = next
            next += 1
        }
        for activity in mined.activities where rank[activity.name] == nil {
            rank[activity.name] = next
            next += 1
        }
        return rank
    }

    private var positions: [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        var rows: [Int: Int] = [:]
        let rank = ranks
        for activity in mined.activities.sorted(by: {
            (rank[$0.name] ?? 0) == (rank[$1.name] ?? 0)
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : (rank[$0.name] ?? 0) < (rank[$1.name] ?? 0)
        }) {
            let column = rank[activity.name] ?? 0
            let row = rows[column, default: 0]
            rows[column] = row + 1
            result[activity.name] = CGPoint(
                x: 24 + CGFloat(column) * columnWidth + nodeWidth / 2,
                y: 28 + CGFloat(row) * rowHeight + nodeHeight / 2)
        }
        return result
    }

    private var canvas: CGSize {
        let maxColumn = positions.values.map(\.x).max() ?? 0
        let maxRow = positions.values.map(\.y).max() ?? 0
        return CGSize(width: max(760, maxColumn + nodeWidth / 2 + 48),
                      height: max(280, maxRow + nodeHeight / 2 + 48))
    }

    private var maxWait: Double { max(1, mined.activities.map(\.averageWaitMinutes).max() ?? 1) }
    private var maxEdge: Int { max(1, mined.edges.map(\.count).max() ?? 1) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in mined.edges {
                        guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                        let start = CGPoint(x: from.x + nodeWidth / 2, y: from.y)
                        let end = CGPoint(x: to.x - nodeWidth / 2, y: to.y)
                        let mid = (start.x + end.x) / 2
                        var path = Path()
                        path.move(to: start)
                        path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y),
                                      control2: CGPoint(x: mid, y: end.y))
                        let width = 1 + 3.5 * CGFloat(edge.count) / CGFloat(maxEdge)
                        context.stroke(path, with: .color(Color.secondary.opacity(0.45)),
                                       style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }
                .frame(width: canvas.width, height: canvas.height)
                .accessibilityHidden(true)

                ForEach(mined.activities) { activity in
                    if let point = positions[activity.name] {
                        Button {
                            onSelect(activity.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.name).font(.caption.weight(.semibold)).lineLimit(2)
                                Text("\(activity.events) ev · \(Fmt.minutes(activity.averageWaitMinutes)) wait")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                Text(activity.resources.prefix(2).joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(width: nodeWidth, height: nodeHeight, alignment: .leading)
                            .background(heat(activity).opacity(0.20),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected == activity.name ? Color.accentColor : heat(activity).opacity(0.55),
                                                  lineWidth: selected == activity.name ? 2.2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .position(point) // grid: ok computed process graph coordinate
                        .accessibilityLabel("\(activity.name), \(activity.events) events, \(Fmt.minutes(activity.averageWaitMinutes)) average wait")
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height)
        }
    }

    private func heat(_ activity: MinedActivity) -> Color {
        let value = min(1, max(0, activity.averageWaitMinutes / maxWait))
        return value < 0.5 ? Color.green : Color.orange.mix(with: .red, by: (value - 0.5) * 2)
    }
}

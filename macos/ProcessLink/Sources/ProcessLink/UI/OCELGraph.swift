import ProcessLinkKit
import SwiftUI

/// A compact object-interaction graph. Objects are laid out in type columns;
/// lines are pairwise interactions. It is deliberately not a force layout:
/// deterministic positions make the same log look the same on every render.
struct OCELGraphView: View {
    let model: OCELModel

    var body: some View {
        GeometryReader { geometry in
            let points = layout(in: geometry.size)
            Canvas { context, _ in
                for interaction in model.interactions.prefix(120) {
                    guard let a = points[interaction.from], let b = points[interaction.to] else { continue }
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                }
                for object in model.objects.prefix(80) {
                    guard let point = points[object.id] else { continue }
                    let color = color(for: object.type)
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    if object.type == "case" {
                        context.draw(Text(object.label).font(.caption2).foregroundStyle(.secondary),
                                     at: CGPoint(x: point.x, y: point.y + 10), anchor: .top)
                    }
                }
            }
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 192)
        .accessibilityLabel("Object interaction graph: \(model.objects.count) objects, \(model.interactions.count) links")
    }

    private func layout(in size: CGSize) -> [String: CGPoint] {
        let types = Array(Set(model.objects.map(\.type))).sorted()
        var result: [String: CGPoint] = [:]
        for (column, type) in types.enumerated() {
            let objects = model.objects.filter { $0.type == type }
            let x = size.width * (Double(column) + 0.5) / Double(max(1, types.count))
            for (row, object) in objects.enumerated() {
                let y = size.height * (Double(row) + 0.5) / Double(max(1, objects.count))
                result[object.id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private func color(for type: String) -> Color {
        switch type {
        case "case": .accentColor
        case "order": .green
        case "customer": .blue
        case "invoice": .orange
        case "employee": .purple
        default: .secondary
        }
    }
}

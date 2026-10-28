import ProcessLinkKit
import SwiftUI

// MARK: - Layout primitives

/// A content card. No glass: glass belongs to the control layer, not to
/// content, so this uses the system control background plus a hairline.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, subtitle: String? = nil, symbol: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let title {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        if let symbol {
                            Image(systemName: symbol)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(title).font(.headline)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

/// A page title and one line of context, with optional trailing controls.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// A label + value row used in provenance and evidence blocks.
struct DetailRow: View {
    var label: String
    var value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// A small label with an icon and a tinted capsule. The word is always there,
/// so colour is never the only channel.
struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.caption2.weight(.semibold))
            }
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(filled ? .white : tint)
        .background(filled ? tint : tint.opacity(0.12),
                    in: Capsule(style: .continuous))
        .overlay {
            if !filled {
                Capsule(style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusChip: View {
    var status: ProcessStatus

    var body: some View {
        switch status {
        case .discovered:
            Chip(text: "Discovered", symbol: "checkmark.circle", tint: .green)
        case .suppressed:
            Chip(text: "Suppressed", symbol: "eye.slash", tint: .orange)
        case .blocked:
            Chip(text: "Blocked", symbol: "hand.raised", tint: .red)
        }
    }
}

struct SavingsChip: View {
    var stage: SavingsStage

    var body: some View {
        switch stage {
        case .estimated:
            Chip(text: stage.label, symbol: "pencil.line", tint: .orange)
        case .committed:
            Chip(text: stage.label, symbol: "signature", tint: .blue)
        case .validated:
            Chip(text: stage.label, symbol: "checkmark.seal.fill", tint: .green)
        }
    }
}

struct ConfidenceChip: View {
    var confidence: Double

    private var band: ConfidenceBand {
        confidence >= 0.85 ? .high : confidence >= 0.65 ? .medium : .low
    }

    var body: some View {
        switch band {
        case .high:
            Chip(text: "\(Fmt.percent(confidence)) confidence", symbol: "checkmark.circle", tint: .green)
        case .medium:
            Chip(text: "\(Fmt.percent(confidence)) confidence", symbol: "circle.dashed", tint: .orange)
        case .low:
            Chip(text: "\(Fmt.percent(confidence)) · review", symbol: "exclamationmark.circle", tint: .red)
        }
    }
}

/// A labelled horizontal meter. `value` is 0 ... 100.
struct Meter: View {
    var label: String
    var value: Double
    var tint: Color = .accentColor
    var valueText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: Space.sm)
                Text(valueText ?? "\(Int(value.rounded()))")
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(100, max(0, value)), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityValue(valueText ?? "\(Int(value.rounded())) of 100")
        }
    }
}

/// A page-level number: value, label, and a one-line reading.
struct MetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

/// A one-line explanation that carries a guardrail, not decoration.
struct GuardrailNote: View {
    var text: String
    var symbol: String = "lock.shield"
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Rows in a section list, separated by a hairline with consistent insets.
struct RowDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

/// A selectable list row: one click selects, the whole row is the target.
struct SelectableRow<Content: View>: View {
    var selected: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shared tint for a route, so the same route reads the same everywhere.
extension Route {
    var tint: Color {
        switch self {
        case .eliminate: .red
        case .simplify: .orange
        case .standardize: .blue
        case .automate: .purple
        case .leave: .secondary
        }
    }
}

extension SavingsStage {
    var tint: Color {
        switch self {
        case .estimated: .orange
        case .committed: .blue
        case .validated: .green
        }
    }
}

extension GovernanceStatus {
    var tint: Color {
        switch self {
        case .done: .green
        case .inProgress: .blue
        case .blocked: .red
        case .notStarted: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .inProgress: "clock"
        case .blocked: "exclamationmark.octagon"
        case .notStarted: "circle"
        }
    }
}

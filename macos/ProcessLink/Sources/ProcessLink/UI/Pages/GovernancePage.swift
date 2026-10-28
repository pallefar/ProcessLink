import ProcessLinkKit
import SwiftData
import SwiftUI

/// The launch checklist and the guard, side by side. A policy nobody can test
/// is a policy nobody believes, so the page can be made to refuse something.
struct GovernancePage: View {
    @Environment(AppModel.self) private var model
    @Query private var governance: [GovernanceRecord]
    @Query(sort: \AuditRecord.at, order: .reverse) private var audits: [AuditRecord]

    @State private var demoResult: PrivacyDecision?
    @State private var demoTitle = ""
    @State private var piiSample = "Please fix case EMP-4821 for anna.schmidt@example.com, IBAN DE44 5001 0517 5407 3249 31."
    @State private var pii: PIIScan?

    private func items(in group: String) -> [GovernanceRecord] {
        governance.filter { $0.group == group }.sorted { $0.sortKey < $1.sortKey }
    }

    /// The order an owner reads the checklist in, not the query's order.
    private static let groupOrder = ["Data protection", "People", "Accountability", "AI & security"]

    private var groups: [String] {
        let present = Set(governance.map(\.group))
        let ordered = Self.groupOrder.filter { present.contains($0) }
        let extras = present.subtracting(ordered).sorted()
        return ordered + extras
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Governance",
                           subtitle: "Purpose limitation, group thresholds, classification, retention and the human gates. Nothing is production-ready until this list is signed.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(governance.filter { $0.status == .done }.count)/\(governance.count) done",
                             symbol: "checkmark.circle", tint: .green)
                        Chip(text: "\(governance.filter { $0.status == .blocked }.count) blocked",
                             symbol: "hand.raised", tint: .red)
                    }
                }

                HStack(alignment: .top, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        ForEach(groups, id: \.self) { group in
                            Card(group, subtitle: groupSubtitle(group), symbol: symbol(for: group), content: {
                                VStack(spacing: 0) {
                                    ForEach(items(in: group)) { item in
                                        governanceRow(item)
                                        if item.id != items(in: group).last?.id {
                                            RowDivider()
                                        }
                                    }
                                }
                            })
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Space.lg) {
                        guardDemo
                        purposeCard
                        flowCard
                    }
                    .frame(width: 360)
                }

                auditCard
            }
            .padding(Space.margin)
        }
        .gridArea("governance")
        .navigationTitle("Governance")
    }

    private func governanceRow(_ item: GovernanceRecord) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: item.status.symbol)
                .foregroundStyle(item.status.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.owner)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Space.sm)
            Chip(text: item.status.label, tint: item.status.tint)
            Menu {
                ForEach(GovernanceStatus.allCases, id: \.self) { status in
                    Button(status.label) { set(item, to: status) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help("Change status")
            .accessibilityLabel("Change status of \(item.title)")
        }
        .padding(.vertical, Space.sm)
    }

    private var guardDemo: some View {
        Card("Try the guard", subtitle: "Same code path as sync, export and every AI call.", symbol: "hand.raised") {
            VStack(alignment: .leading, spacing: Space.sm) {
                Button {
                    demo("Restricted record → AI gateway") {
                        PrivacyGuard.evaluate(groupSize: 14, classification: .restricted,
                                              destination: .aiGateway, purpose: .processImprovement,
                                              policy: model.policy)
                    }
                } label: {
                    Label("Send Restricted to the AI gateway", systemImage: "arrow.up.right.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    demo("4-person group → export") {
                        PrivacyGuard.evaluate(groupSize: 4, classification: .internalUse,
                                              destination: .export, purpose: .processImprovement,
                                              policy: model.policy)
                    }
                } label: {
                    Label("Export a 4-person group", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    demo("AI call with an e-mail address") {
                        let scan = PIIScanner.scan(piiSample)
                        pii = scan
                        return PrivacyGuard.evaluate(groupSize: 22, classification: .internalUse,
                                                     destination: .aiGateway, purpose: .processImprovement,
                                                     piiFindings: scan.total, policy: model.policy)
                    }
                } label: {
                    Label("Call AI with a PII sample", systemImage: "envelope.badge.shield.half.filled")
                }
                .buttonStyle(.bordered)

                if let demoResult {
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Chip(text: demoTitle, tint: .secondary)
                            Chip(text: demoResult.action.label,
                                 symbol: demoResult.allowed ? "checkmark.circle" : "xmark.octagon",
                                 tint: demoResult.allowed ? .green : .red, filled: true)
                        }
                        Text(demoResult.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(demoResult.rule)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        if let pii {
                            Text(pii.maskedText)
                                .font(.caption2)
                                .textSelection(.enabled)
                                .padding(Space.sm)
                                .background(Color(nsColor: .textBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var purposeCard: some View {
        Card("Purpose limitation", subtitle: "Built into the product, not just the policy.", symbol: "lock.shield") {
            VStack(alignment: .leading, spacing: Space.sm) {
                limit("No individual performance ranking, monitoring or HR use.")
                limit("No per-person drill-down and no leaderboard.")
                limit("Groups below \(model.minimumGroupSize) are suppressed at query time, not hidden in the UI.")
                limit("Restricted content is refused at the boundary, with a visible reason.")
                limit("Retention: aggregated facts \(model.retentionDays) days; raw capture stays in the local capture store.")
                Divider().opacity(0.6)
                DetailRow(label: "Data owner", value: model.dataOwner)
                DetailRow(label: "Purpose", value: "Process and system improvement")
            }
        }
    }

    private func limit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var flowCard: some View {
        Card("Where data goes", subtitle: "The data-flow contract in one card.", symbol: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: Space.sm) {
                flow("In-house discovery", "Event logs and opt-in task capture stay local. Titles, screenshots and input counts are separate opt-ins; no key codes, clipboard or person ids.", .blue)
                flow("ProcessLink", "Local store on this Mac. Purpose-limited, permission-filtered, audit-logged.", .purple)
                flow("Knowledge graph", "Nodes and edges with provenance; writes are idempotent and reviewable.", .teal)
                flow("Maps · TEOA · DeckForge", "Read the same nodes; edits become change proposals.", .orange)
                flow("AI gateway", "Optional, region-pinned, classification-gated, PII-masked. Local provider by default.", .red)
            }
        }
    }

    private func flow(_ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Circle().fill(tint).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var auditCard: some View {
        Card("Audit log", subtitle: "Append-only in the product: syncs, queries, AI calls, approvals and exports.", symbol: "list.bullet.rectangle.portrait") {
            VStack(spacing: 0) {
                HStack(spacing: Space.sm) {
                    Text("When").frame(width: 132, alignment: .leading)
                    Text("Action").frame(width: 192, alignment: .leading)
                    Text("Subject").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Actor").frame(width: 140, alignment: .leading)
                    Text("Class").frame(width: 80, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)

                ForEach(audits.prefix(9)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(Fmt.stamp(entry.at))
                            .font(.caption.monospacedDigit())
                            .frame(width: 132, alignment: .leading)
                        Text(entry.action)
                            .font(.caption.monospaced())
                            .frame(width: 192, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.subject)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.actor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.classification.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .help(entry.detail)
                    if entry.id != audits.prefix(9).last?.id { RowDivider() }
                }
            }
        }
    }

    private func demo(_ title: String, _ decision: () -> PrivacyDecision) {
        demoTitle = title
        demoResult = decision()
    }

    private func set(_ item: GovernanceRecord, to status: GovernanceStatus) {
        item.statusRaw = status.rawValue
        item.updatedAt = .now
        model.audit(action: "governance.\(status.rawValue)", subject: item.title,
                    detail: "Status changed to \(status.label).")
        try? model.context.save()
        model.showToast("Checklist updated", detail: "\(item.title) · \(status.label)", symbol: "checklist")
    }

    private func symbol(for group: String) -> String {
        switch group {
        case "Data protection": "lock.shield"
        case "People": "person.3"
        case "Accountability": "signature"
        case "AI & security": "cpu"
        default: "checkmark.shield"
        }
    }

    private func groupSubtitle(_ group: String) -> String {
        switch group {
        case "Data protection": "DPIA, legal basis per country, retention."
        case "People": "Works council, transparency, capture scope."
        case "Accountability": "Who owns the data and the numbers."
        case "AI & security": "Approved models, regions, and the guard."
        default: ""
        }
    }
}

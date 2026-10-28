import ProcessLinkKit
import SwiftData
import SwiftUI

/// The prioritized pipeline. One screen answers: what is worth doing, why
/// this route, what evidence supports it, and what a human must decide.
struct OpportunitiesPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \OpportunityRecord.annualHours, order: .reverse) private var opportunities: [OpportunityRecord]
    @Query private var processes: [ProcessRecord]

    private var ranked: [OpportunityRecord] {
        opportunities
            .filter { model.siteFilter == "All sites" || $0.site == model.siteFilter }
            .sorted { $0.score.total > $1.score.total }
    }

    private var selected: OpportunityRecord? {
        ranked.first { $0.id == model.selectedOpportunityID } ?? ranked.first
    }

    private func process(for opportunity: OpportunityRecord) -> ProcessRecord? {
        processes.first { $0.id == opportunity.processID }
    }

    private func isGuarded(_ opportunity: OpportunityRecord) -> Bool {
        guard let process = process(for: opportunity) else { return true }
        return process.status != .discovered
            || !PrivacyGuard.canDisplay(groupSize: process.people,
                                        classification: process.classification,
                                        policy: model.policy)
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Opportunities")
        .onAppear {
            if model.selectedOpportunityID == nil { model.selectedOpportunityID = ranked.first?.id }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Text("\(ranked.count) opportunities")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("score")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, opportunity in
                        Button {
                            model.selectedOpportunityID = opportunity.id
                        } label: {
                            SelectableRow(selected: selected?.id == opportunity.id) {
                                HStack(alignment: .top, spacing: Space.sm) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 16, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(opportunity.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 8) {
                                            Text(opportunity.processName)
                                            Text("·")
                                            Text(opportunity.site)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        HStack(spacing: Space.xs) {
                                            Chip(text: opportunity.route.label,
                                                 symbol: opportunity.route.symbol,
                                                 tint: opportunity.route.tint)
                                            if opportunity.statutory {
                                                Chip(text: "Human control", symbol: "hand.raised", tint: .blue)
                                            }
                                            if isGuarded(opportunity) {
                                                Chip(text: "Guarded", symbol: "lock", tint: .red)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(Int(opportunity.score.total.rounded()))")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .monospacedDigit()
                                        Text(isGuarded(opportunity) ? "hidden" : Fmt.hoursPerYear(opportunity.annualHours))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(opportunity.title), score \(Int(opportunity.score.total.rounded()))")
                    }
                }
                .padding(Space.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let opportunity = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(opportunity)
                    if isGuarded(opportunity) {
                        guarded(opportunity)
                    } else {
                        scoreCard(opportunity)
                        HStack(alignment: .top, spacing: Space.lg) {
                            recommendation(opportunity)
                            evidence(opportunity)
                        }
                        actions(opportunity)
                    }
                }
                .padding(Space.margin)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .id(opportunity.id)
        } else {
            ContentUnavailableView("No opportunities",
                                   systemImage: "lightbulb",
                                   description: Text("Promote a discovered process to create the first opportunity."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ opportunity: OpportunityRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(opportunity.title).font(.title2.weight(.semibold))
                Spacer(minLength: Space.sm)
                Chip(text: opportunity.status.label, tint: .secondary)
            }
            HStack(spacing: Space.sm) {
                Chip(text: opportunity.processName, symbol: "arrow.triangle.branch", tint: .blue)
                Chip(text: opportunity.site, symbol: "mappin.and.ellipse", tint: .secondary)
                Chip(text: opportunity.waste.label, symbol: opportunity.waste.symbol,
                     tint: opportunity.route.tint)
                Chip(text: opportunity.method.title, symbol: opportunity.method.symbol, tint: .secondary)
                ConfidenceChip(confidence: opportunity.confidence)
            }
        }
    }

    private func scoreCard(_ opportunity: OpportunityRecord) -> some View {
        let score = opportunity.score
        return Card("Why it ranks here", subtitle: "The arithmetic is shown, not hidden. Weights: impact 42%, ease 22%, alignment 18%, automation 10%, confidence 8%, minus risk.", symbol: "function") {
            HStack(alignment: .center, spacing: Space.xl) {
                ScoreRing(value: score.total)
                VStack(spacing: Space.md) {
                    Meter(label: "Impact (hours + error reduction)", value: score.impact, tint: .orange)
                    Meter(label: "Ease (effort estimate)", value: score.ease, tint: .blue)
                    Meter(label: "Hoshin alignment", value: score.alignment, tint: .purple)
                    Meter(label: "Automation suitability", value: score.automation, tint: .teal)
                    if score.riskPenalty > 0 {
                        Meter(label: "Risk penalty", value: score.riskPenalty * 5, tint: .red,
                              valueText: "−\(Int(score.riskPenalty.rounded())) pts")
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(score.reasoning, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(line).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func recommendation(_ opportunity: OpportunityRecord) -> some View {
        let recommendation = MethodRecommender.recommend(waste: opportunity.waste,
                                                         route: opportunity.route,
                                                         statutory: opportunity.statutory)
        return Card("Recommended path", subtitle: "TEOA order: eliminate → simplify → standardize → automate.", symbol: "arrow.right.circle") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Image(systemName: opportunity.route.symbol)
                        .font(.title3)
                        .foregroundStyle(opportunity.route.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(opportunity.route.label)
                            .font(.headline)
                        Text(opportunity.route.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().opacity(0.6)
                HStack(spacing: Space.sm) {
                    Image(systemName: recommendation.method.symbol)
                        .foregroundStyle(Palette.accentText)
                        .accessibilityHidden(true)
                    Text(recommendation.method.title).font(.subheadline.weight(.medium))
                }
                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if opportunity.statutory {
                    GuardrailNote(text: "Statutory or human-only control: automation is excluded by the rule, not by reviewer choice.",
                                  symbol: "hand.raised", tint: .blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func evidence(_ opportunity: OpportunityRecord) -> some View {
        Card("Evidence", subtitle: "Each figure traces to a KYP.ai object or a KG node.", symbol: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: Space.sm) {
                DetailRow(label: "Annual effort", value: Fmt.hoursPerYear(opportunity.annualHours))
                DetailRow(label: "Error reduction", value: "\(Int(opportunity.errorReductionPct.rounded()))%")
                DetailRow(label: "Effort estimate", value: "\(String(format: "%.0f", opportunity.effortWeeks)) weeks")
                DetailRow(label: "Risk", value: "\(opportunity.risk)/5")
                DetailRow(label: "Hoshin alignment", value: "\(opportunity.alignment)/5")
                DetailRow(label: "KYP.ai id", value: opportunity.processID, mono: true)
                DetailRow(label: "KG node", value: opportunity.kgID, mono: true)
                DetailRow(label: "Owner role", value: opportunity.ownerRole)
                Divider().opacity(0.6)
                Text(opportunity.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actions(_ opportunity: OpportunityRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Button {
                    start(opportunity, draftA3: false)
                } label: {
                    Label("Start initiative", systemImage: "flag.pattern.checkered")
                }
                .buttonStyle(.borderedProminent)
                .disabled(opportunity.status == .promoted)

                Button {
                    start(opportunity, draftA3: true)
                } label: {
                    Label("Draft A3", systemImage: "doc.text")
                }
                .disabled(opportunity.status == .promoted)

                Button {
                    model.setOpportunity(opportunity, to: .deferred)
                    model.showToast("Opportunity deferred", detail: opportunity.title, symbol: "pause.circle")
                } label: {
                    Label("Defer", systemImage: "pause.circle")
                }
                .disabled(opportunity.status == .deferred)

                Spacer()
            }
            GuardrailNote(text: "A promotion creates a local initiative and proposes a KG node. It never deploys an automation, changes a production system, or sends data outside the approved region.",
                          symbol: "checkmark.shield")
        }
    }

    private func guarded(_ opportunity: OpportunityRecord) -> some View {
        Card("Blocked by the privacy guard", subtitle: "This opportunity cannot be promoted.", symbol: "hand.raised") {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(guardReason(opportunity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let process = process(for: opportunity) {
                    DetailRow(label: "Process", value: process.name)
                    DetailRow(label: "Status", value: process.status.label)
                    DetailRow(label: "Reason", value: process.statusReason)
                }
                GuardrailNote(text: "The record stays visible so the refusal is auditable. Its numbers are not computed, not exported, and never sent to a model.")
            }
        }
    }

    private func guardReason(_ opportunity: OpportunityRecord) -> String {
        guard let process = process(for: opportunity) else { return "The source process is missing from the graph." }
        return PrivacyGuard.evaluate(groupSize: process.people, classification: process.classification,
                                     destination: .knowledgeGraph, purpose: .processImprovement,
                                     policy: model.policy).reason
    }

    private func start(_ opportunity: OpportunityRecord, draftA3: Bool) {
        guard let process = process(for: opportunity) else { return }
        if let initiative = model.promote(opportunity, process: process) {
            model.selectedInitiativeID = initiative.id
            if draftA3 {
                model.showA3ForInitiativeID = initiative.id
            }
        }
    }
}

/// A compact score ring. The number is the primary channel; the arc is the
/// second one, and both are labelled for VoiceOver.
struct ScoreRing: View {
    var value: Double
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, value / 100)))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of 100")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opportunity score")
        .accessibilityValue("\(Int(value.rounded())) of 100")
    }
}

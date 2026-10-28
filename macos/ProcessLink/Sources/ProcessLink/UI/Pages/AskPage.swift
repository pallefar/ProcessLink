import ProcessLinkKit
import SwiftUI

/// "Ask the process": a governed assistant over the graph and the mined
/// facts. Every number carries a citation; every unknown goes on a list.
struct AskPage: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                if model.answers.isEmpty {
                    intro
                } else {
                    ForEach(model.answers) { answer in
                        answerView(answer)
                            .id(answer.id)
                    }
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Ask")
        .gridArea("ask")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PageHeader("Ask the process",
                       subtitle: "Questions over KYP.ai discovery, the knowledge graph and TEOA work. Local provider by default; the hosted provider follows the same guard.")
            HStack(spacing: Space.sm) {
                Chip(text: model.aiProvider, symbol: "cpu", tint: .blue)
                Chip(text: "Region \(model.aiRegion)", symbol: "globe.europe.africa", tint: .secondary)
                Chip(text: "Purpose: improvement only", symbol: "lock.shield", tint: .green)
                Chip(text: "Groups ≥ \(model.minimumGroupSize)", symbol: "person.3", tint: .secondary)
                Spacer()
                if !model.answers.isEmpty {
                    Button("Clear") { model.answers.removeAll() }
                        .controlSize(.small)
                }
            }
            if model.answers.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Space.sm)],
                          alignment: .leading, spacing: Space.sm) {
                    ForEach(AskEngine.suggestions, id: \.self) { suggestion in
                        Button {
                            model.ask(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                                .overlay { Capsule().strokeBorder(.separator, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Space.margin)
    }

    private var intro: some View {
        Card("What this assistant may and may not do", subtitle: "The same rules as every other surface.", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: Space.sm) {
                rule("Reads only aggregated, permission-filtered facts from KYP.ai and the KG.")
                rule("Refuses individual performance questions and groups below the threshold.")
                rule("Masks personal-data patterns before a hosted AI call; local answers never leave this Mac.")
                rule("Never invents a number: a missing fact becomes a to-verify item, and a saving is labelled an estimate.")
                rule("Cites the KYP.ai object or KG node behind every figure, so a reviewer can open the evidence.")
            }
        }
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answerView(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Spacer(minLength: 80)
                Text(answer.question)
                    .font(.callout)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(answer.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.sm)
                    Chip(text: "\(Int((answer.confidence * 100).rounded()))% confidence",
                         symbol: "chart.bar", tint: answer.confidence >= 0.8 ? .green : .orange)
                }
                Text(answer.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !answer.citations.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(answer.citations) { citation in
                                citationChip(citation)
                            }
                        }
                        .accessibilityLabel("Sources for this answer")
                    }
                }

                if !answer.toVerify.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("To verify").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        ForEach(answer.toVerify, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(item).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
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

    private func citationChip(_ citation: Citation) -> some View {
        Button {
            if citation.kind == .kgNode {
                model.selectedKGID = citation.ref
                model.page = .graph
            }
        } label: {
            HStack(spacing: 4) {
                Text(citation.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(citation.label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
            .overlay { Capsule().strokeBorder(.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(citation.kind != .kgNode)
        .help(citation.ref)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Ask about handoffs, rework, variants, a process or freshness…", text: Binding(
                    get: { model.askDraft },
                    set: { model.askDraft = $0 }
                ))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(send)
                Button(action: send) {
                    Label("Ask", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.askDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? Color.secondary.opacity(0.45) : Palette.accent)
                .disabled(model.askDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (Return)")
            }
            .padding(Space.md)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            HStack {
                Text("Numbers trace to KYP.ai ids or KG nodes. Personal-data patterns are masked before any call.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Estimate ≠ validated saving")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Space.margin)
        .background(.bar)
    }

    private func send() {
        let question = model.askDraft
        model.ask(question)
    }
}

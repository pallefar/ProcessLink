import ProcessLinkKit
import SwiftData
import SwiftUI

/// An annotation/feedback subject. The id is stable, so a comment survives a
/// map reload or a process re-import.
struct FeedbackSubject: Identifiable, Hashable {
    var kind: FeedbackKind
    var subjectID: String
    var label: String
    var id: String { "\(kind.rawValue)|\(subjectID)" }
}

/// Threaded comments for one subject, in the same pattern as DiagramForge:
/// resolve/reopen, replies, @mentions and an explicit local-only boundary.
struct FeedbackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FeedbackRecord.createdAt) private var all: [FeedbackRecord]
    let subject: FeedbackSubject

    @State private var draft = ""
    @State private var replyTo: String?
    @State private var replyDraft = ""
    @State private var showResolved = false

    private var records: [FeedbackRecord] {
        all.filter { $0.kind == subject.kind && $0.subjectID == subject.subjectID }
    }
    private var roots: [FeedbackRecord] {
        records.filter { $0.parentID.isEmpty && (showResolved || !$0.resolved) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var openCount: Int { records.filter { $0.parentID.isEmpty && !$0.resolved }.count }
    private var resolvedCount: Int { records.filter { $0.parentID.isEmpty && $0.resolved }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: subject.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feedback · \(subject.kind.label)").font(.title3.weight(.semibold))
                    Text(subject.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("\(openCount) open · \(resolvedCount) resolved")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("Resolved", isOn: $showResolved)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Done") { dismiss() }
            }
            .padding(Space.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    if roots.isEmpty {
                        ContentUnavailableView("No feedback yet",
                                               systemImage: "bubble.left.and.text.bubble.right",
                                               description: Text("Leave a note, ask a question or @mention a role."))
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    ForEach(roots) { root in
                        thread(root)
                    }
                }
                .padding(Space.lg)
            }

            Divider()

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("New comment").font(.caption).foregroundStyle(.secondary)
                TextField("Comment or @mention a role…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Button("@ Mention") { draft += draft.isEmpty ? "@" : " @" }
                        .controlSize(.small)
                    Text("⌘↩ sends").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Send") {
                        guard model.addFeedback(kind: subject.kind, subjectID: subject.subjectID,
                                                subjectLabel: subject.label, body: draft) != nil else { return }
                        draft = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(Space.lg)
        }
        .frame(width: 640, height: 680)
        .onChange(of: subject.id) { _, _ in draft = ""; replyTo = nil }
    }

    @ViewBuilder
    private func thread(_ root: FeedbackRecord) -> some View {
        let replies = records.filter { $0.parentID == root.id }.sorted { $0.createdAt < $1.createdAt }
        VStack(alignment: .leading, spacing: Space.sm) {
            commentHeader(root)
            Text(root.body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            mentionRow(root)
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(replies) { reply in
                        HStack(alignment: .top, spacing: Space.sm) {
                            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                commentHeader(reply)
                                Text(reply.body).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, Space.sm)
                    }
                }
                .padding(.top, 2)
            }
            HStack(spacing: Space.md) {
                Button(root.resolved ? "Reopen" : "Resolve") {
                    model.setFeedbackResolved(root, resolved: !root.resolved)
                }
                .controlSize(.small)
                Button("Reply") { replyTo = replyTo == root.id ? nil : root.id }
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive) { model.deleteFeedback(root) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .controlSize(.small)
            }
            if replyTo == root.id {
                HStack(spacing: Space.sm) {
                    TextField("Reply…", text: $replyDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    Button("Send") {
                        guard model.addFeedback(kind: subject.kind, subjectID: subject.subjectID,
                                                subjectLabel: subject.label, body: replyDraft,
                                                parentID: root.id) != nil else { return }
                        replyDraft = ""
                        replyTo = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.md)
        .background(root.resolved ? Color.primary.opacity(0.03) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(root.resolved ? 0.72 : 1)
    }

    private func commentHeader(_ record: FeedbackRecord) -> some View {
        HStack(spacing: Space.sm) {
            Text(initials(record.author))
                .font(.caption2.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(record.author).font(.caption.weight(.semibold))
                Text(Fmt.ago(record.createdAt)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if record.resolved {
                Chip(text: "Resolved", symbol: "checkmark", tint: .green)
            }
        }
    }

    private func mentionRow(_ record: FeedbackRecord) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(record.mentions, id: \.self) { mention in
                Chip(text: mention, tint: .blue)
            }
        }
    }

    private func initials(_ value: String) -> String {
        value.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct FeedbackInboxPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \FeedbackRecord.createdAt, order: .reverse) private var all: [FeedbackRecord]
    @State private var filter = "Open"
    @State private var selected: FeedbackSubject?

    private var roots: [FeedbackRecord] {
        all.filter { record in
            guard record.parentID.isEmpty else { return false }
            switch filter {
            case "Open": return !record.resolved
            case "Resolved": return record.resolved
            default: return true
            }
        }
    }
    private var openCount: Int { all.filter { $0.parentID.isEmpty && !$0.resolved }.count }
    private var resolvedCount: Int { all.filter { $0.parentID.isEmpty && $0.resolved }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Feedback",
                           subtitle: "Annotations and questions on maps, shapes, processes, opportunities and initiatives. Comments stay on this Mac.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(openCount) open", symbol: "bubble.left.and.text.bubble.right", tint: .orange)
                        Chip(text: "\(resolvedCount) resolved", symbol: "checkmark", tint: .green)
                    }
                }

                HStack {
                    Picker("Show", selection: $filter) {
                        ForEach(["Open", "Resolved", "All"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    Spacer()
                    Text("Comments are local annotations, not writes to Flightdeck.")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                if roots.isEmpty {
                    ContentUnavailableView("No feedback in this view",
                                           systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text("Add feedback from a map shape or the map toolbar."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    Card("Threads", subtitle: "\(roots.count) conversations", symbol: "bubble.left.and.text.bubble.right") {
                        VStack(spacing: 0) {
                            ForEach(roots) { root in
                                let replies = all.filter { $0.parentID == root.id }.count
                                let meta = "\(root.author) · \(Fmt.ago(root.createdAt)) · \(replies) replies"
                                Button {
                                    selected = FeedbackSubject(kind: root.kind, subjectID: root.subjectID,
                                                               label: root.subjectLabel)
                                } label: {
                                    HStack(alignment: .top, spacing: Space.sm) {
                                        Image(systemName: root.kind.symbol)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(root.subjectLabel).font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary).lineLimit(1)
                                            Text(root.body).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(2).multilineTextAlignment(.leading)
                                            Text(meta)
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        if root.resolved {
                                            Chip(text: "Resolved", symbol: "checkmark", tint: .green)
                                        } else {
                                            Chip(text: "Open", tint: .orange)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, Space.sm)
                                if root.id != roots.last?.id { RowDivider() }
                            }
                        }
                    }
                }
            }
            .padding(Space.margin)
        }
        .gridArea("feedback")
        .navigationTitle("Feedback")
        .sheet(item: $selected) { FeedbackSheet(subject: $0) }
    }
}

/// Drop-in feedback button for a page's selected subject. The count is open
/// threads, not total comments.
struct FeedbackButton: View {
    @Environment(AppModel.self) private var model
    @Query private var all: [FeedbackRecord]
    let subject: FeedbackSubject
    @State private var showing = false

    private var count: Int {
        all.filter {
            $0.kind == subject.kind && $0.subjectID == subject.subjectID
                && $0.parentID.isEmpty && !$0.resolved
        }.count
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(count == 0 ? "Feedback" : "Feedback \(count)",
                  systemImage: "bubble.left.and.text.bubble.right")
        }
        .controlSize(.small)
        .help("Annotate \\(subject.label)")
        .sheet(isPresented: $showing) { FeedbackSheet(subject: subject) }
    }
}

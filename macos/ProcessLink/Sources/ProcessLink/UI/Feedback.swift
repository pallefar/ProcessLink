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
    @State private var showingAppFeedback = false
    @Query(sort: \AppFeedbackRecord.createdAt, order: .reverse) private var appFeedback: [AppFeedbackRecord]

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
                        Button("Export for PDF Studio") { model.exportFeedbackForPDFStudio() }
                            .controlSize(.small)
                        Button("Export CSV") { model.exportFeedbackCSV() }
                            .controlSize(.small)
                        Button("Send to PDF Studio") { model.sendFeedbackToPDFStudioInbox() }
                            .controlSize(.small)
                        Button("Send feedback") { showingAppFeedback = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
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

                Card("Product feedback", subtitle: "About ProcessLink itself. Separate from annotations; stays on this Mac.", symbol: "star.bubble") {
                    if appFeedback.isEmpty {
                        Text("No product feedback yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(appFeedback.prefix(5)) { item in
                            HStack(alignment: .top, spacing: Space.sm) {
                                Chip(text: item.priority.capitalized,
                                     tint: item.priority == "high" ? .red : item.priority == "low" ? .secondary : .blue)
                                Chip(text: item.rating == "ok" ? "OK" : item.rating == "minor" ? "Minor" : "Major",
                                     tint: item.rating == "ok" ? .green : item.rating == "minor" ? .orange : .red)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.comment).font(.caption).lineLimit(2)
                                    Text("\(item.author) · \(Fmt.ago(item.createdAt)) · \(item.page)")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
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
        .sheet(isPresented: $showingAppFeedback) { AppFeedbackSheet() }
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


private struct AppFeedbackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("feedback.author") private var author = "CI Manager (role)"
    @State private var rating = "ok"
    @State private var priority = "normal"
    @State private var category = ""
    @State private var comment = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                Text("Send feedback").font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }
            if sent {
                ContentUnavailableView("Feedback saved", systemImage: "checkmark.circle",
                                       description: Text("It stays on this Mac for review/export."))
                HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
            } else {
                Picker("How is it going?", selection: $rating) {
                    Text("OK").tag("ok")
                    Text("Minor issue").tag("minor")
                    Text("Major issue").tag("major")
                }
                .pickerStyle(.segmented)
                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low")
                    Text("Normal").tag("normal")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                TextField("Category (optional)", text: $category).textFieldStyle(.roundedBorder)
                TextField("Name / role", text: $author).textFieldStyle(.roundedBorder)
                TextField("What should we improve?", text: $comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...6)
                HStack {
                    Text("Saved locally; never sent to a model or the network.").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Save feedback") {
                        if model.addAppFeedback(rating: rating, priority: priority, category: category,
                                                comment: comment, author: author,
                                                page: model.page?.rawValue ?? "unknown") != nil {
                            sent = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Space.lg)
        .frame(width: 460)
    }
}

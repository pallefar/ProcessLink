import ProcessLinkKit
import SwiftData
import SwiftUI

/// Notion-style meeting pages: typed blocks, decisions and actions, linked to
/// the process and initiative they are about — and written into the graph.
struct MeetingsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \MeetingRecord.date, order: .reverse) private var meetings: [MeetingRecord]
    @Query private var blocks: [MeetingBlockRecord]
    @State private var search = ""

    private var filtered: [MeetingRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return meetings }
        return meetings.filter { meeting in
            meeting.title.lowercased().contains(query)
                || meeting.summary.lowercased().contains(query)
                || blocks.contains { $0.meetingID == meeting.id && $0.text.lowercased().contains(query) }
        }
    }

    private var selected: MeetingRecord? {
        filtered.first { $0.id == model.selectedMeetingID } ?? filtered.first
    }

    private func openActions(_ meeting: MeetingRecord) -> Int {
        blocks.filter { $0.meetingID == meeting.id && $0.kind == .action && !$0.checked }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 380)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Meetings")
        .onAppear {
            if model.selectedMeetingID == nil { model.selectedMeetingID = filtered.first?.id }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Text("\(filtered.count) pages")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    ForEach(MeetingKind.allCases) { kind in
                        Button {
                            model.createMeeting(kind: kind)
                        } label: {
                            Label(kind.label, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Start a meeting note from a template")
                .accessibilityLabel("New meeting note")
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.md)

            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search pages and notes", text: $search)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)

            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { meeting in
                        Button {
                            model.selectedMeetingID = meeting.id
                        } label: {
                            SelectableRow(selected: selected?.id == meeting.id) {
                                HStack(alignment: .top, spacing: Space.sm) {
                                    Image(systemName: meeting.kind.symbol)
                                        .foregroundStyle(meeting.kind == .leadership ? .purple : .secondary)
                                        .frame(width: 20)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(meeting.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 8) {
                                            Text(Fmt.day(meeting.date))
                                            Text("·")
                                            Text("\(meeting.durationMinutes) min")
                                            if !meeting.site.isEmpty {
                                                Text("·")
                                                Text(meeting.site)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        HStack(spacing: Space.xs) {
                                            Chip(text: meeting.kind.label, symbol: meeting.kind.symbol, tint: .secondary)
                                            if openActions(meeting) > 0 {
                                                Chip(text: "\(openActions(meeting)) open", symbol: "checklist", tint: .orange)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Chip(text: meeting.status.label,
                                         tint: meeting.status == .done ? .green : meeting.status == .notes ? .blue : .secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let meeting = selected {
            MeetingDetail(meeting: meeting)
                .id(meeting.id)
        } else {
            ContentUnavailableView {
                Label("No meeting pages", systemImage: "person.3.sequence")
            } description: {
                Text("Start a daily huddle, kaizen or A3 review from the New menu. Notes, decisions and actions stay linked to the process and the graph.")
            } actions: {
                Button("Start a daily huddle") { model.createMeeting(kind: .dailyHuddle) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Page

private struct MeetingDetail: View {
    @Environment(AppModel.self) private var model
    @Bindable var meeting: MeetingRecord
    @Query private var allBlocks: [MeetingBlockRecord]
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \InitiativeRecord.title) private var initiatives: [InitiativeRecord]
    @Query(sort: \MeetingRecord.date, order: .reverse) private var meetings: [MeetingRecord]

    private var blocks: [MeetingBlockRecord] {
        allBlocks.filter { $0.meetingID == meeting.id }.sorted { $0.order < $1.order }
    }

    private var openActions: [MeetingBlockRecord] {
        blocks.filter { $0.kind == .action && !$0.checked }
    }

    private var decisions: [MeetingBlockRecord] {
        blocks.filter { $0.kind == .decision }
    }

    private var linkedProcess: ProcessRecord? {
        processes.first { $0.id == meeting.processID }
    }

    private var linkedInitiative: InitiativeRecord? {
        initiatives.first { $0.id == meeting.initiativeID }
    }

    private var relatedMeetings: [MeetingRecord] {
        guard !meeting.processID.isEmpty else { return [] }
        return meetings.filter { $0.id != meeting.id && $0.processID == meeting.processID }.prefix(3).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                meta
                notes
                if !openActions.isEmpty { actionsCard }
                backlinks
            }
            .padding(Space.margin)
            .frame(maxWidth: 840, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                TextField("Meeting title", text: $meeting.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Spacer(minLength: Space.sm)
                Menu {
                    ForEach(MeetingStatus.allCases, id: \.self) { status in
                        Button(status.label) {
                            meeting.statusRaw = status.rawValue
                            meeting.updatedAt = model.now
                            try? model.context.save()
                        }
                    }
                    Divider()
                    Button("Mark done") { model.markMeetingDone(meeting) }
                    Button("Delete meeting", role: .destructive) { model.deleteMeeting(meeting) }
                } label: {
                    Chip(text: meeting.status.label,
                         tint: meeting.status == .done ? .green : meeting.status == .notes ? .blue : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change status")
                FeedbackButton(subject: FeedbackSubject(kind: .meeting, subjectID: meeting.id,
                                                        label: meeting.title))
            }
            TextField("One-line summary for the graph and the search", text: $meeting.summary)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Chip(text: meeting.kind.label, symbol: meeting.kind.symbol, tint: .secondary)
                if meeting.isRecurring {
                    Chip(text: meeting.cadence.isEmpty ? "Recurring" : meeting.cadence, symbol: "arrow.triangle.2.circlepath", tint: .teal)
                }
                if !meeting.site.isEmpty {
                    Chip(text: meeting.site, symbol: "mappin.and.ellipse", tint: .blue)
                }
                Chip(text: meeting.owner, symbol: "person", tint: .secondary)
                Spacer(minLength: Space.sm)
                DatePicker("", selection: $meeting.date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .fixedSize()
            }

            HStack(spacing: Space.sm) {
                Menu {
                    Button("No process") { model.linkMeeting(meeting, processID: "") }
                    Divider()
                    ForEach(processes) { process in
                        Button(process.name) { model.linkMeeting(meeting, processID: process.id) }
                    }
                } label: {
                    Label(linkedProcess?.name ?? "Link a process", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Button("No initiative") { model.linkMeeting(meeting, initiativeID: "") }
                    Divider()
                    ForEach(initiatives) { initiative in
                        Button(initiative.title) { model.linkMeeting(meeting, initiativeID: initiative.id) }
                    }
                } label: {
                    Label(linkedInitiative?.title ?? "Link an initiative", systemImage: "flag")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: Space.sm)
                Text(meeting.attendees.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var notes: some View {
        Card("Notes", subtitle: "Blocks, not a text box. Decisions and actions become graph facts.", symbol: "doc.text") {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(blocks) { block in
                    MeetingBlockRow(block: block, meeting: meeting)
                }
                if blocks.isEmpty {
                    Text("This page is empty. Add a block or insert a template.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Space.sm)
                }

                Divider().opacity(0.6)
                HStack(spacing: Space.md) {
                    Menu {
                        ForEach(BlockKind.allCases) { kind in
                            Button {
                                model.addBlock(to: meeting, kind: kind)
                            } label: {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label("Add block", systemImage: "plus")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Menu {
                        ForEach(MeetingKind.allCases) { kind in
                            Button(kind.label) { model.applyTemplate(kind, to: meeting) }
                        }
                    } label: {
                        Label("Insert template", systemImage: "doc.badge.plus")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()
                    Text("Autosaved")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, Space.sm)
            }
        }
    }

    private var actionsCard: some View {
        Card("Open actions", subtitle: "Same gate as an opportunity: an owner, a date, and a human decision to promote.", symbol: "checklist") {
            VStack(spacing: 0) {
                ForEach(openActions) { action in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Button {
                            model.toggle(action, meeting: meeting)
                        } label: {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark action done")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.text.isEmpty ? "Untitled action" : action.text)
                                .font(.subheadline)
                            HStack(spacing: Space.sm) {
                                Text(action.owner.isEmpty ? "Unassigned" : action.owner)
                                if let due = action.due {
                                    Text("· due \(Fmt.day(due))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: Space.sm)
                        Button("Promote") { model.promoteAction(action, meeting: meeting) }
                            .controlSize(.small)
                            .disabled(action.owner.isEmpty)
                    }
                    .padding(.vertical, Space.sm)
                    if action.id != openActions.last?.id { RowDivider() }
                }
            }
        }
    }

    private var backlinks: some View {
        Card("Linked in the graph", subtitle: "This page is a node, not a silo.", symbol: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: Space.sm) {
                DetailRow(label: "Meeting node", value: meeting.kgID, mono: true)
                DetailRow(label: "Process", value: linkedProcess?.name ?? "Not linked")
                DetailRow(label: "Initiative", value: linkedInitiative?.title ?? "Not linked")
                DetailRow(label: "Decisions", value: "\(decisions.count) recorded")
                DetailRow(label: "Actions", value: "\(blocks.filter { $0.kind == .action }.count) total · \(openActions.count) open")

                HStack(spacing: Space.md) {
                    Button("Open meeting node") {
                        model.selectedKGID = meeting.kgID
                        model.page = .graph
                    }
                    .controlSize(.small)

                    if let linkedProcess {
                        Button("Open process") {
                            model.selectedProcessID = linkedProcess.id
                            model.page = .discoveries
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                }

                if !relatedMeetings.isEmpty {
                    Divider().opacity(0.6)
                    Text("Other pages about this process")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(relatedMeetings) { other in
                        Button {
                            model.selectedMeetingID = other.id
                        } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: other.kind.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(other.title)
                                    .font(.subheadline)
                                Spacer()
                                Text(Fmt.day(other.date))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                GuardrailNote(text: "Attendees are roles, never people. Meeting notes are process evidence, not an attendance or performance record.")
            }
        }
    }
}

// MARK: - Block row

private struct MeetingBlockRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var block: MeetingBlockRecord
    var meeting: MeetingRecord

    private var dueBinding: Binding<Date> {
        Binding(
            get: { block.due ?? model.now },
            set: { block.due = $0 }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: block.kind.symbol)
                .font(.caption)
                .foregroundStyle(block.kind == .decision ? Color.green : block.kind == .action ? Color.orange : Color.secondary.opacity(0.7))
                .frame(width: 16)
                .padding(.top, 4)
                .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if block.kind.createsNode {
                    Button("Update graph node") { model.refreshBlockNode(block, meeting: meeting) }
                }
                Button("Add block below") { model.addBlock(to: meeting, kind: .text, after: block.order) }
                Divider()
                Button("Move up") { model.moveBlock(block, by: -1, meeting: meeting) }
                    .disabled(block.order == 0)
                Button("Move down") { model.moveBlock(block, by: 1, meeting: meeting) }
                Divider()
                Button("Delete block", role: .destructive) { model.deleteBlock(block, meeting: meeting) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .accessibilityLabel("Block actions")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading:
            TextField("Heading", text: $block.text)
                .textFieldStyle(.plain)
                .font(.headline)
                .padding(.top, 2)
        case .text:
            TextField("Write something", text: $block.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...12)
                .font(.callout)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("•").foregroundStyle(.tertiary)
                TextField("Bullet", text: $block.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .font(.callout)
            }
        case .checklist:
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Button {
                    model.toggle(block, meeting: meeting)
                } label: {
                    Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(block.checked ? .green : .secondary)
                }
                .buttonStyle(.plain)
                TextField("To-do", text: $block.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .foregroundStyle(block.checked ? Color.secondary : Color.primary)
            }
        case .decision:
            VStack(alignment: .leading, spacing: 2) {
                Chip(text: "Decision", symbol: "checkmark.bubble", tint: .green)
                TextField("What did we decide?", text: $block.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.callout)
                    .onSubmit { model.refreshBlockNode(block, meeting: meeting) }
            }
        case .action:
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Button {
                        model.toggle(block, meeting: meeting)
                    } label: {
                        Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(block.checked ? .green : .orange)
                    }
                    .buttonStyle(.plain)
                    TextField("What happens next?", text: $block.text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .foregroundStyle(block.checked ? Color.secondary : Color.primary)
                }
                HStack(spacing: Space.sm) {
                    TextField("Owner role", text: $block.owner)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 152)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit { model.refreshBlockNode(block, meeting: meeting) }
                    DatePicker("", selection: dueBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .controlSize(.small)
                        .fixedSize()
                    Button("Promote") { model.promoteAction(block, meeting: meeting) }
                        .controlSize(.mini)
                        .disabled(block.owner.isEmpty)
                }
                .padding(.leading, 24)
            }
        case .callout:
            TextField("Note for the room", text: $block.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.callout)
                .padding(Space.sm)
                .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .link:
            HStack(spacing: Space.sm) {
                Image(systemName: "link").foregroundStyle(.secondary)
                Text(linkLabel)
                    .font(.callout)
                Spacer()
                Button("Open") { openLink() }
                    .controlSize(.small)
                    .disabled(block.linkedID.isEmpty)
            }
            .padding(.vertical, 4)
        }
    }

    private var linkLabel: String {
        if block.linkedID.isEmpty { return "No linked record" }
        switch block.linkedKindRaw {
        case "process": return "Process · \(block.linkedID)"
        case "opportunity": return "Opportunity · \(block.linkedID)"
        case "initiative": return "Initiative · \(block.linkedID)"
        default: return block.linkedID
        }
    }

    private func openLink() {
        switch block.linkedKindRaw {
        case "process":
            model.selectedProcessID = block.linkedID
            model.page = .discoveries
        case "initiative":
            model.selectedInitiativeID = block.linkedID
            model.page = .improvements
        case "opportunity":
            model.selectedOpportunityID = block.linkedID
            model.page = .opportunities
        default:
            break
        }
    }
}

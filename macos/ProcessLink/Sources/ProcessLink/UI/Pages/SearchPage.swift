import SwiftData
import SwiftUI

/// One local search across the records a person actually navigates. It reads
/// only the local SwiftData store; no model or network call.
struct SearchPage: View {
    @Environment(AppModel.self) private var model
    @Query private var processes: [ProcessRecord]
    @Query private var opportunities: [OpportunityRecord]
    @Query private var initiatives: [InitiativeRecord]
    @Query private var meetings: [MeetingRecord]
    @State private var query = ""
    @State private var kind = "All"
    @FocusState private var searchFocused: Bool

    private struct Hit: Identifiable {
        var id: String
        var kind: String
        var title: String
        var detail: String
        var action: () -> Void
    }

    private var hits: [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var result: [Hit] = []
        for process in processes where [process.name, process.site, process.summary].joined(separator: " ").localizedCaseInsensitiveContains(q) {
            result.append(Hit(id: "p-\(process.id)", kind: "Process", title: process.name,
                              detail: "\(process.site) · \(process.businessUnit)") {
                model.selectedProcessID = process.id
                model.page = .discoveries
            })
        }
        for opportunity in opportunities where [opportunity.title, opportunity.processName, opportunity.site].joined(separator: " ").localizedCaseInsensitiveContains(q) {
            result.append(Hit(id: "o-\(opportunity.id)", kind: "Opportunity", title: opportunity.title,
                              detail: "\(opportunity.processName) · \(opportunity.waste.label)") {
                model.selectedOpportunityID = opportunity.id
                model.page = .opportunities
            })
        }
        for initiative in initiatives where [initiative.title, initiative.owner, initiative.processName].joined(separator: " ").localizedCaseInsensitiveContains(q) {
            result.append(Hit(id: "i-\(initiative.id)", kind: "Initiative", title: initiative.title,
                              detail: "\(initiative.owner) · \(initiative.stage.label)") {
                model.selectedInitiativeID = initiative.id
                model.page = .improvements
            })
        }
        for meeting in meetings where [meeting.title, meeting.kind.label].joined(separator: " ").localizedCaseInsensitiveContains(q) {
            result.append(Hit(id: "m-\(meeting.id)", kind: "Meeting", title: meeting.title,
                              detail: meeting.kind.label) {
                model.selectedMeetingID = meeting.id
                model.page = .meetings
            })
        }
        return result.filter { kind == "All" || $0.kind == kind }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                PageHeader("Search", subtitle: "Processes, opportunities, initiatives and meetings on this Mac.") {
                    Chip(text: "Local", symbol: "lock.shield", tint: .green)
                }
                TextField("Search ProcessLink…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($searchFocused)
                HStack(spacing: Space.sm) {
                    ForEach(["All", "Process", "Opportunity", "Initiative", "Meeting"], id: \.self) { value in
                        Button(value) { kind = value }
                            .buttonStyle(.bordered)
                            .tint(kind == value ? .accentColor : nil)
                            .controlSize(.small)
                    }
                }
                .padding(.bottom, Space.sm)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search your work", systemImage: "magnifyingglass",
                                           description: Text("Type a process, owner, site, meeting or opportunity."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if hits.isEmpty {
                    ContentUnavailableView("No match", systemImage: "magnifyingglass",
                                           description: Text("Try a shorter term or a site name."))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    Card("Results", subtitle: "\(hits.count) matches", symbol: "magnifyingglass") {
                        ForEach(hits) { hit in
                            Button {
                                hit.action()
                            } label: {
                                HStack(alignment: .top, spacing: Space.sm) {
                                    Text(hit.kind).font(.caption2).foregroundStyle(.tertiary)
                                        .frame(width: 80, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hit.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(hit.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, Space.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if hit.id != hits.last?.id { RowDivider() }
                        }
                    }
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .gridArea("search")
        .navigationTitle("Search")
        .task { searchFocused = true }
    }
}

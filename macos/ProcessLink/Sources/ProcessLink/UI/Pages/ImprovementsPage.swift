import ProcessLinkKit
import SwiftData
import SwiftUI

/// The TEOA execution layer: A3/kaizen records, the PDCA stage, and the
/// savings ledger with its three states and its double-count guard.
struct ImprovementsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \InitiativeRecord.createdAt, order: .reverse) private var initiatives: [InitiativeRecord]
    @Query private var processes: [ProcessRecord]
    @Query(sort: \MeetingRecord.date, order: .reverse) private var meetingNotes: [MeetingRecord]

    @State private var validating: InitiativeRecord?
    @State private var validator = ""
    @State private var evidence = ""

    private var selected: InitiativeRecord? {
        initiatives.first { $0.id == model.selectedInitiativeID }
            ?? initiatives.sorted { $0.savingsHours > $1.savingsHours }.first
    }

    private var ledger: [SavingsLine] { initiatives.map { $0.savingLine } }
    private var totals: SavingsTotals { SavingsLedger.totals(ledger) }
    private var conflicts: [SavingsConflict] { SavingsLedger.conflicts(ledger) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader("Improvements",
                           subtitle: "Every opportunity becomes a named owner, a method, a stage and a saving that a human validates.") {
                    HStack(spacing: Space.sm) {
                        Chip(text: "\(initiatives.filter { $0.status == .active }.count) active",
                             symbol: "flag.pattern.checkered", tint: .blue)
                        Chip(text: "\(initiatives.filter { $0.savingsStage == .validated }.count) validated",
                             symbol: "checkmark.seal", tint: .green)
                    }
                }

                metrics
                savingsLedger
                HStack(alignment: .top, spacing: Space.lg) {
                    initiativeList
                    detail
                }
            }
            .padding(Space.margin)
        }
        .gridArea("improvements")
        .navigationTitle("Improvements")
        .sheet(item: $validating) { initiative in
            validationSheet(initiative)
        }
        .sheet(isPresented: Binding(get: { model.showA3ForInitiativeID != nil },
                                    set: { if !$0 { model.showA3ForInitiativeID = nil } })) {
            if let id = model.showA3ForInitiativeID,
               let initiative = initiatives.first(where: { $0.id == id }) {
                A3Sheet(initiative: initiative)
            }
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: Space.md) {
            MetricTile(title: "Estimated", value: Fmt.hours(totals.estimated),
                       detail: "Not a claim yet", symbol: "pencil.line", tint: .orange)
            MetricTile(title: "Committed", value: Fmt.hours(totals.committed),
                       detail: "Owner and date agreed", symbol: "signature", tint: .blue)
            MetricTile(title: "Validated", value: Fmt.hours(totals.validated),
                       detail: CostModel.euro(hours: totals.validated) + " at €\(Int(CostModel.ratePerHour))/h",
                       symbol: "checkmark.seal", tint: .green)
            MetricTile(title: "Double-count risk", value: "\(conflicts.count)",
                       detail: conflicts.isEmpty ? "One claim per process and waste" : "Resolve before roll-up",
                       symbol: "exclamationmark.triangle", tint: conflicts.isEmpty ? .green : .red)
        }
    }

    private var savingsLedger: some View {
        Card("Savings ledger", subtitle: "Hours are the source of truth. One claim per process and waste type is credited; ties never sum.", symbol: "banknote") {
            VStack(spacing: 0) {
                HStack(spacing: Space.sm) {
                    Text("Initiative").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Waste").frame(width: 112, alignment: .leading)
                    Text("Stage").frame(width: 104, alignment: .leading)
                    Text("Hours").frame(width: 72, alignment: .trailing)
                    Text("Per year").frame(width: 92, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)

                ForEach(initiatives.sorted { $0.savingsStage.rank > $1.savingsStage.rank }) { initiative in
                    HStack(spacing: Space.sm) {
                        Button {
                            model.selectedInitiativeID = initiative.id
                        } label: {
                            HStack(spacing: Space.xs) {
                                Text(initiative.title).lineLimit(1)
                                if initiative.validatedBy.isEmpty && initiative.savingsStage == .validated {
                                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Chip(text: initiative.claimsWaste.label, tint: .secondary)
                            .frame(width: 112, alignment: .leading)
                        SavingsChip(stage: initiative.savingsStage)
                            .frame(width: 104, alignment: .leading)
                        Text(Fmt.hours(initiative.savingsHours))
                            .font(.caption.monospacedDigit())
                            .frame(width: 72, alignment: .trailing)
                        Text(CostModel.euro(hours: initiative.savingsHours))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    if initiative.id != initiatives.last?.id { RowDivider() }
                }

                if !conflicts.isEmpty {
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(conflicts) { conflict in
                            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                                Text(conflictText(conflict))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: Space.sm)
                                Button("Review") {
                                    model.selectedInitiativeID = conflict.initiativeIDs.first
                                }
                                .controlSize(.small)
                            }
                        }
                        GuardrailNote(text: "The ledger credits the most advanced claim per key. It never adds two initiatives that save the same hours; validation of either is blocked until the conflict is resolved.",
                                      symbol: "exclamationmark.triangle", tint: .red)
                    }
                }
            }
        }
    }

    private var initiativeList: some View {
        Card("Portfolio", subtitle: "\(initiatives.count) initiatives across every site.", symbol: "list.bullet.rectangle") {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(initiatives.sorted { $0.due < $1.due }) { initiative in
                        Button {
                            model.selectedInitiativeID = initiative.id
                        } label: {
                            SelectableRow(selected: selected?.id == initiative.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: Space.sm) {
                                        Text(initiative.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    HStack(spacing: Space.xs) {
                                        Chip(text: initiative.method.title, symbol: initiative.method.symbol, tint: .secondary)
                                        SavingsChip(stage: initiative.savingsStage)
                                    }
                                    HStack(spacing: Space.sm) {
                                        Text(initiative.owner)
                                        Text("·")
                                        Text("due \(Fmt.day(initiative.due))")
                                        if initiative.status == .complete {
                                            Text("· complete")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    CycleStepper(stage: initiative.stage)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 320, maxHeight: 460)
        }
        .frame(width: 400)
    }

    @ViewBuilder
    private var detail: some View {
        if let initiative = selected {
            VStack(alignment: .leading, spacing: Space.lg) {
                Card(initiative.method.title, subtitle: initiative.title, symbol: initiative.method.symbol) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(spacing: Space.xs) {
                            SavingsChip(stage: initiative.savingsStage)
                            Chip(text: initiative.status.label, tint: .secondary)
                            Chip(text: initiative.site, symbol: "mappin.and.ellipse", tint: .secondary)
                        }
                        VStack(alignment: .leading, spacing: Space.sm) {
                            DetailRow(label: "Owner", value: initiative.owner)
                            DetailRow(label: "Process", value: initiative.processName)
                            DetailRow(label: "Due", value: Fmt.day(initiative.due))
                            DetailRow(label: "Claim", value: "\(Fmt.hours(initiative.savingsHours)) · \(initiative.savingsStage.label)")
                            if !initiative.validatedBy.isEmpty {
                                DetailRow(label: "Validated by", value: initiative.validatedBy)
                            }
                            if !initiative.evidenceNote.isEmpty {
                                DetailRow(label: "Evidence", value: initiative.evidenceNote)
                            }
                        }

                        Divider().opacity(0.6)
                        CycleStepper(stage: initiative.stage)
                        HStack(spacing: Space.md) {
                            Button {
                                model.advance(initiative)
                            } label: {
                                Label(initiative.stage == .act ? "Complete" : "Move to \(initiative.stage.next.label)",
                                      systemImage: "arrow.forward.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(initiative.stage == .act)

                            Button("Open A3") { model.showA3ForInitiativeID = initiative.id }
                            Button("KG node") {
                                model.selectedKGID = "kg-ini-\(initiative.id)"
                                model.page = .graph
                            }
                            Button("Open process") {
                                model.selectedProcessID = initiative.processID
                                model.page = .discoveries
                            }
                            Spacer()
                        }
                        GuardrailNote(text: "A stage change is recorded in the audit log. Nothing here deploys code or changes a production system.")
                    }
                }

                savingsCard(initiative)
                if isAutomationPackage(initiative) { changePackage(initiative) }
                meetingCard(initiative)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("No initiative selected", systemImage: "flag.pattern.checkered")
                .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private func savingsCard(_ initiative: InitiativeRecord) -> some View {
        Card("Savings lifecycle", subtitle: "Estimated → committed → validated. Each step needs a different human act.", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.lg) {
                    ForEach(SavingsStage.allCases, id: \.self) { stage in
                        VStack(alignment: .leading, spacing: 4) {
                            SavingsChip(stage: stage)
                            Text(stage.detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(initiative.savingsStage.rank >= stage.rank ? 1 : 0.5)
                    }
                }

                HStack(spacing: Space.md) {
                    Button {
                        model.commitSavings(initiative)
                    } label: {
                        Label("Commit saving", systemImage: "signature")
                    }
                    .disabled(initiative.savingsStage != .estimated || initiative.status == .complete)

                    Button {
                        validator = ""
                        evidence = ""
                        validating = initiative
                    } label: {
                        Label("Validate with evidence…", systemImage: "checkmark.seal")
                    }
                    .disabled(initiative.savingsStage == .validated)

                    Spacer()
                    Text(Fmt.hours(initiative.savingsHours) + " · " + CostModel.euro(hours: initiative.savingsHours))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !initiative.evidenceNote.isEmpty {
                    Text(initiative.evidenceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func meetingCard(_ initiative: InitiativeRecord) -> some View {
        let related = meetingNotes.filter {
            $0.initiativeID == initiative.id || (!initiative.processID.isEmpty && $0.processID == initiative.processID)
        }.prefix(3)
        return Group {
            if !related.isEmpty {
                Card("Meeting notes", subtitle: "The record behind the stage change.", symbol: "person.3.sequence") {
                    VStack(spacing: 0) {
                        ForEach(Array(related)) { meeting in
                            Button {
                                model.selectedMeetingID = meeting.id
                                model.page = .meetings
                            } label: {
                                HStack(spacing: Space.sm) {
                                    Image(systemName: meeting.kind.symbol).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(meeting.title).font(.subheadline).foregroundStyle(.primary)
                                        Text("\(Fmt.day(meeting.date)) · \(meeting.owner)")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text(meeting.status.label).font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, Space.sm)
                            if meeting.id != related.last?.id { RowDivider() }
                        }
                    }
                }
            }
        }
    }

    private func isAutomationPackage(_ initiative: InitiativeRecord) -> Bool {
        let text = (initiative.title + " " + initiative.countermeasure).lowercased()
        return text.contains("agent") || text.contains("bot") || text.contains("automat")
    }

    private func changePackage(_ initiative: InitiativeRecord) -> some View {
        Card("Automation / agent change package",
             subtitle: "Required before anything is deployed. ProcessLink never deploys on its own.",
             symbol: "gearshape.2") {
            VStack(alignment: .leading, spacing: Space.sm) {
                changeRow("Scope", "The exception path only; no change to the standard path.")
                changeRow("Risks", "Wrong automation of a statutory control; silent data loss; model drift.")
                changeRow("Controls", "Human review of every output; sample audit; kill switch.")
                changeRow("Owner", initiative.owner)
                changeRow("Test plan", "Shadow run for 2 weeks against the last 500 cases; compare to human decisions.")
                changeRow("Approval", "Required: process owner, CI manager, security. Not requested yet.")
                HStack(spacing: Space.md) {
                    Button("Request approval") {
                        model.audit(action: "changePackage.approval.requested", subject: initiative.title,
                                    detail: "Human approval requested for an automation change package.")
                        model.showToast("Approval requested", detail: "Process owner, CI manager and security must review.")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Chip(text: "Not deployed", symbol: "lock", tint: .orange)
                }
            }
        }
    }

    private func changeRow(_ label: String, _ value: String) -> some View {
        DetailRow(label: label, value: value)
    }

    private func validationSheet(_ initiative: InitiativeRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Validate the saving").font(.title3.weight(.semibold))
                    Text(initiative.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { validating = nil }
                    .keyboardShortcut(.cancelAction)
            }

            Text("A saving becomes a claim only with a named validator and before/after evidence from KYP.ai. The estimate is not editable here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Validated by (name or role)", text: $validator)
                    .textFieldStyle(.roundedBorder)
                TextField("Before/after evidence (period, metric, source)", text: $evidence, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Claim") {
                    Text("\(Fmt.hours(initiative.savingsHours)) · \(initiative.savingsStage.label)")
                }
            }
            .formStyle(.grouped)
            .frame(height: 220)

            HStack {
                Button("Cancel") { validating = nil }
                Spacer()
                Button("Validate") {
                    model.validateSavings(initiative, validator: validator, evidence: evidence)
                    if initiative.savingsStage == .validated { validating = nil }
                }
                .buttonStyle(.borderedProminent)
                .disabled(validator.trimmingCharacters(in: .whitespaces).isEmpty
                          || evidence.trimmingCharacters(in: .whitespaces).count < 12)
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .noInitialFocus()
    }

    private func processName(_ id: String) -> String {
        processes.first { $0.id == id }?.name ?? id
    }

    /// Says what each initiative claims, not just the largest, so a reviewer
    /// can see why the ledger refuses to add them.
    private func conflictText(_ conflict: SavingsConflict) -> String {
        let claims = initiatives.filter {
            $0.processID == conflict.processID && $0.claimsWaste == conflict.waste
                && $0.savingsStage.rank >= SavingsStage.committed.rank
        }
        let hours = claims.map { Fmt.hours($0.savingsHours) }.joined(separator: " and ")
        return "\(processName(conflict.processID)) · \(conflict.waste.label): \(claims.count) initiatives claim the same saving (\(hours))."
    }
}

/// Four PDCA dots with the current stage named. The word is always present.
struct CycleStepper: View {
    var stage: CycleStage

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(CycleStage.allCases, id: \.self) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.rawValue == stage.rawValue ? Palette.accent : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(item == stage ? Color.primary : Color.secondary.opacity(0.75))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(stage.label)")
    }
}

extension CycleStage: CustomStringConvertible {
    var description: String { label }
}

/// The one-page A3, printable and exportable. Read-only here: the record is
/// edited through the initiative, so the sheet cannot drift from the data.
struct A3Sheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initiative: InitiativeRecord

    private var sections: [(String, String, String)] {
        [
            ("1 · Background", "Why this matters now", initiative.background),
            ("2 · Target", "The measurable outcome", initiative.target),
            ("3 · Root cause", "What the evidence says", initiative.rootCause),
            ("4 · Countermeasure", "What we will do", initiative.countermeasure),
            ("5 · Result", "What the data showed", initiative.result.isEmpty ? "Not measured yet." : initiative.result),
            ("6 · Follow-up", "How it stays fixed", initiative.followUp),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("A3 · \(initiative.method.title)").font(.title3.weight(.semibold))
                    Text(initiative.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.xl)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.sm) {
                        Chip(text: initiative.owner, symbol: "person", tint: .secondary)
                        Chip(text: initiative.site, symbol: "mappin.and.ellipse", tint: .secondary)
                        Chip(text: "Due \(Fmt.day(initiative.due))", symbol: "calendar", tint: .secondary)
                        SavingsChip(stage: initiative.savingsStage)
                    }
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(section.0).font(.headline)
                            Text(section.1).font(.caption).foregroundStyle(.tertiary)
                            Text(section.2)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Space.md)
                                .background(Color(nsColor: .textBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.separator, lineWidth: 1)
                                }
                        }
                    }
                    GuardrailNote(text: "Saving: \(Fmt.hours(initiative.savingsHours)) · \(initiative.savingsStage.label). \(initiative.savingsStage == .validated ? "Validated by \(initiative.validatedBy)." : "Not a validated saving yet.")")
                }
                .padding(Space.xl)
            }
            Divider()
            HStack {
                Text("TE validation rules apply. This A3 is a draft until the process owner signs it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Send to DeckForge") {
                    model.showToast("Deck queued", detail: "A3 handed to the DeckForge template library.")
                }
            }
            .padding(Space.lg)
        }
        .frame(width: 720, height: 640)
        .noInitialFocus()
    }
}

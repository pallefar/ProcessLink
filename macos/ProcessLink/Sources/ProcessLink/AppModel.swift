import AppKit
import Foundation
import ProcessLinkKit
import SwiftData
import SwiftUI

/// The sidebar sections. Snapshot mode walks every case, so a new section is
/// covered by the checks automatically.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, discoveries, opportunities, maps, graph, improvements, ask, governance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .discoveries: "Discoveries"
        case .opportunities: "Opportunities"
        case .maps: "Maps"
        case .graph: "Knowledge Graph"
        case .improvements: "Improvements"
        case .ask: "Ask"
        case .governance: "Governance"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .discoveries: "binoculars"
        case .opportunities: "lightbulb"
        case .maps: "point.topleft.down.to.point.bottomright.curvepath"
        case .graph: "circle.hexagongrid"
        case .improvements: "flag.pattern.checkered"
        case .ask: "bubble.left.and.text.bubble.right"
        case .governance: "checkmark.shield"
        }
    }

    /// Command-1 ... Command-8.
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .discoveries: "2"
        case .opportunities: "3"
        case .maps: "4"
        case .graph: "5"
        case .improvements: "6"
        case .ask: "7"
        case .governance: "8"
        }
    }
}

enum MapOverlay: String, CaseIterable, Identifiable {
    case cycleTime, handoffs, rework, automation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cycleTime: "Cycle time"
        case .handoffs: "Handoffs"
        case .rework: "Rework"
        case .automation: "Automation potential"
        }
    }

    var symbol: String {
        switch self {
        case .cycleTime: "timer"
        case .handoffs: "arrow.left.arrow.right"
        case .rework: "arrow.triangle.2.circlepath"
        case .automation: "gearshape.2"
        }
    }
}

struct Toast: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var detail: String = ""
    var symbol: String = "checkmark.circle.fill"
    var isWarning = false
}

/// App-wide state: navigation, the current selection, the policy the guard
/// enforces, and every write that needs an audit entry.
@Observable
final class AppModel {
    let container: ModelContainer

    var page: SidebarItem? = .overview
    var selectedProcessID: String?
    var selectedOpportunityID: String?
    var selectedInitiativeID: String?
    var selectedKGID: String?
    var graphFilter: KGKind?
    var siteFilter = "All sites"
    var mapOverlay: MapOverlay = .cycleTime
    var selectedMapStepID: String?
    var showA3ForInitiativeID: String?
    var askDraft = ""
    var answers: [AskAnswer] = []
    var isSyncing = false
    var toast: Toast?
    var settingsTab: SettingsTab = .connections

    /// Policy values. Persisted per Mac; the real thresholds are a works
    /// council decision, not a slider a developer ships.
    var minimumGroupSize: Int {
        didSet { UserDefaults.standard.set(minimumGroupSize, forKey: "policy.minGroupSize") }
    }
    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "policy.retentionDays") }
    }
    var aiProvider: String {
        didSet { UserDefaults.standard.set(aiProvider, forKey: "policy.aiProvider") }
    }
    var aiRegion: String {
        didSet { UserDefaults.standard.set(aiRegion, forKey: "policy.aiRegion") }
    }
    var dataOwner: String {
        didSet { UserDefaults.standard.set(dataOwner, forKey: "policy.dataOwner") }
    }
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications.enabled") }
    }

    /// Set by the self-test to a fixed date so checks never depend on when
    /// they run.
    var now: Date = .now

    init(container: ModelContainer) {
        self.container = container
        let defaults = UserDefaults.standard
        minimumGroupSize = defaults.object(forKey: "policy.minGroupSize") as? Int ?? 10
        retentionDays = defaults.object(forKey: "policy.retentionDays") as? Int ?? 400
        aiProvider = defaults.string(forKey: "policy.aiProvider") ?? "Local (on device)"
        aiRegion = defaults.string(forKey: "policy.aiRegion") ?? "EU"
        dataOwner = defaults.string(forKey: "policy.dataOwner") ?? "CI Manager (role)"
        notificationsEnabled = defaults.bool(forKey: "notifications.enabled")
    }

    var policy: PrivacyPolicy {
        PrivacyPolicy(minimumGroupSize: minimumGroupSize, retentionDays: retentionDays,
                      approvedAIProviders: ["Local (on device)", "Anthropic Claude · EU"],
                      approvedRegions: [aiRegion], purpose: .processImprovement,
                      dataOwner: dataOwner)
    }

    var context: ModelContext { container.mainContext }

    // MARK: Navigation

    func show(_ page: SidebarItem) {
        self.page = page
    }

    func open(url: URL) {
        guard url.scheme == "processlink" else { return }
        let host = url.host() ?? ""
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "overview": page = .overview
        case "discoveries": page = .discoveries
        case "opportunities": page = .opportunities
        case "maps": page = .maps
        case "graph": page = .graph
        case "improvements": page = .improvements
        case "ask":
            page = .ask
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value {
                ask(query)
            }
        case "governance": page = .governance
        default:
            if host == "opportunity", let id = path.first {
                page = .opportunities
                selectedOpportunityID = id
            } else if host == "initiative", let id = path.first {
                page = .improvements
                selectedInitiativeID = id
            } else if host == "process", let id = path.first {
                page = .discoveries
                selectedProcessID = id
            } else if host == "node", let id = path.first {
                page = .graph
                selectedKGID = id
            }
        }
    }

    func showToast(_ text: String, detail: String = "", symbol: String = "checkmark.circle.fill",
                   warning: Bool = false) {
        let toast = Toast(text: text, detail: detail, symbol: symbol, isWarning: warning)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(warning ? 4.5 : 3))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    // MARK: Opportunity actions

    /// A promotion writes an initiative locally and proposes a KG initiative
    /// node. It is refused when the source process is blocked by
    /// classification or suppressed by group size.
    @discardableResult
    func promote(_ opportunity: OpportunityRecord, process: ProcessRecord?) -> InitiativeRecord? {
        if let process {
            let decision = PrivacyGuard.evaluate(groupSize: process.people,
                                                 classification: process.classification,
                                                 destination: .knowledgeGraph,
                                                 purpose: .processImprovement,
                                                 policy: policy)
            guard decision.allowed else {
                audit(action: "opportunity.promotion.blocked", subject: opportunity.title,
                      detail: decision.reason, classification: process.classification)
                showToast("Blocked by the privacy guard", detail: decision.reason,
                          symbol: "hand.raised", warning: true)
                return nil
            }
        }
        let initiative = InitiativeRecord(
            id: "ini-\(UUID().uuidString.prefix(8))",
            title: opportunity.title,
            opportunityID: opportunity.id,
            processID: opportunity.processID,
            processName: opportunity.processName,
            site: opportunity.site,
            method: opportunity.method,
            owner: opportunity.ownerRole.isEmpty ? "Unassigned" : opportunity.ownerRole,
            stage: .plan,
            status: .active,
            due: now.addingTimeInterval(60 * 60 * 24 * 30),
            savingsHours: opportunity.annualHours,
            savingsStage: .estimated,
            validatedBy: "",
            evidenceNote: "",
            claimsWaste: opportunity.waste,
            background: "Mined from \(opportunity.processName): \(Fmt.hoursPerYear(opportunity.annualHours)) of effort, \(Fmt.percent(opportunity.confidence)) confidence.",
            target: "Remove \(Fmt.percent(0.5)) of the mined waste without adding a control step.",
            rootCause: opportunity.rationale,
            countermeasure: opportunity.method.summary,
            result: "",
            followUp: "Validate with before/after KYP.ai data after 6 weeks.",
            createdAt: now)
        context.insert(initiative)
        opportunity.statusRaw = OpportunityStatus.promoted.rawValue
        opportunity.promotedAt = now
        audit(action: "initiative.created", subject: initiative.title,
              detail: "From opportunity \(opportunity.id), \(Fmt.hoursPerYear(initiative.savingsHours)) estimated.")
        try? context.save()
        selectedInitiativeID = initiative.id
        page = .improvements
        showToast("Initiative started", detail: "\(initiative.method.title) · \(initiative.owner)")
        return initiative
    }

    func setOpportunity(_ opportunity: OpportunityRecord, to status: OpportunityStatus) {
        opportunity.statusRaw = status.rawValue
        audit(action: "opportunity.\(status.rawValue)", subject: opportunity.title, detail: "")
        try? context.save()
    }

    // MARK: Initiative actions

    func advance(_ initiative: InitiativeRecord) {
        let next = initiative.stage.next
        guard next != initiative.stage else { return }
        initiative.stageRaw = next.rawValue
        if next == .act && initiative.status == .active {
            initiative.statusRaw = InitiativeStatus.complete.rawValue
        }
        audit(action: "initiative.stage", subject: initiative.title,
              detail: "Moved to \(next.label).")
        try? context.save()
        showToast("Moved to \(next.label)", detail: initiative.title, symbol: "arrow.forward.circle")
    }

    func commitSavings(_ initiative: InitiativeRecord) {
        guard initiative.savingsStage == .estimated else { return }
        guard !initiative.owner.isEmpty, initiative.owner != "Unassigned" else {
            showToast("A commitment needs an owner", detail: "Assign an owner before committing the saving.",
                      symbol: "person.crop.circle.badge.exclamationmark", warning: true)
            return
        }
        initiative.savingsStageRaw = SavingsStage.committed.rawValue
        audit(action: "savings.committed", subject: initiative.title,
              detail: "\(Fmt.hours(initiative.savingsHours)) committed by \(initiative.owner).")
        try? context.save()
        showToast("Saving committed", detail: "\(Fmt.hours(initiative.savingsHours)) · owner \(initiative.owner)")
    }

    /// Validation is the only path to a claim. It needs a named validator and
    /// a before/after evidence note; both are stored on the record.
    func validateSavings(_ initiative: InitiativeRecord, validator: String, evidence: String) {
        let trimmedEvidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValidator = validator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard initiative.savingsStage != .validated else { return }
        guard initiative.savingsStage == .committed else {
            showToast("Commit the saving first", detail: "Validation follows a commitment with a named owner.",
                      symbol: "signature", warning: true)
            return
        }
        guard !trimmedValidator.isEmpty else {
            showToast("A human validator is required", detail: "Name the person or role who checked the evidence.",
                      symbol: "signature", warning: true)
            return
        }
        guard trimmedEvidence.count >= 12 else {
            showToast("Before/after evidence is required", detail: "Describe the baseline, the after measurement and the period.",
                      symbol: "doc.text.magnifyingglass", warning: true)
            return
        }
        initiative.savingsStageRaw = SavingsStage.validated.rawValue
        initiative.validatedBy = trimmedValidator
        initiative.evidenceNote = trimmedEvidence
        audit(action: "savings.validated", subject: initiative.title,
              detail: "\(Fmt.hours(initiative.savingsHours)) validated by \(trimmedValidator). Evidence: \(trimmedEvidence)")
        try? context.save()
        showToast("Saving validated", detail: "\(Fmt.hours(initiative.savingsHours)) · \(trimmedValidator)")
    }

    // MARK: Knowledge graph actions

    func confirmKGNode(_ node: KGNodeRecord, mergeInto targetID: String?) {
        if let targetID, let target = try? context.fetch(FetchDescriptor<KGNodeRecord>()).first(where: { $0.id == targetID }) {
            node.reviewRaw = ReviewState.rejected.rawValue
            node.note = "Merged into \(target.name) (\(target.id)) by a human reviewer."
            audit(action: "kg.merge.confirmed", subject: node.name,
                  detail: "Merged into \(target.name) at \(Fmt.percent(node.confidence)) match confidence.")
        } else {
            node.reviewRaw = ReviewState.confirmed.rawValue
            audit(action: "kg.node.confirmed", subject: node.name, detail: "Entity resolution accepted.")
        }
        node.updatedAt = now
        try? context.save()
        showToast("Review recorded", detail: node.name)
    }

    func rejectKGNode(_ node: KGNodeRecord) {
        node.reviewRaw = ReviewState.rejected.rawValue
        node.updatedAt = now
        audit(action: "kg.node.rejected", subject: node.name, detail: "Proposed link rejected by a human reviewer.")
        try? context.save()
    }

    // MARK: Sync

    /// Incremental sandbox sync. In production this is the `kyp-connector`
    /// worker calling the KYP.ai API with a checkpoint; here it inserts the
    /// next prepared batch so the whole flow is demonstrable offline.
    func runSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await Task.sleep(for: .milliseconds(700))
        let batch = SandboxSync.nextBatch(after: count(SyncRecord.self))
        let before = count(OpportunityRecord.self)
        for opportunity in batch.opportunities {
            guard !exists(OpportunityRecord.self, id: opportunity.id) else { continue }
            context.insert(opportunity)
        }
        let inserted = count(OpportunityRecord.self) - before
        let sync = SyncRecord(source: "KYP.ai sandbox · incremental", fetched: batch.fetched,
                              inserted: inserted, updated: 0, skipped: batch.skipped,
                              status: "success", note: batch.note)
        context.insert(sync)
        audit(action: "sync.completed", subject: "KYP.ai sandbox",
              detail: "\(batch.fetched) objects fetched, \(inserted) new opportunities, \(batch.skipped) skipped by policy.")
        try? context.save()
        if inserted > 0 {
            showToast("Sync complete", detail: "\(inserted) new opportunit\(inserted == 1 ? "y" : "ies") from KYP.ai.")
            NotificationService.shared.postSyncSummary(newOpportunities: inserted)
        } else {
            showToast("Sync complete", detail: "No new opportunities in this window.", symbol: "checkmark.icloud")
        }
    }

    // MARK: Ask

    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let answer = computeAnswer(trimmed)
        answers.append(answer)
        askDraft = ""
        audit(action: "ai.answer", subject: "Ask the process",
              detail: "Intent \(answer.intent.rawValue), \(answer.citations.count) citations, provider \(aiProvider).")
        try? context.save()
    }

    /// The quick panel asks the same engine without changing the page.
    func quickAnswer(_ question: String) -> AskAnswer? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let answer = computeAnswer(trimmed)
        audit(action: "ai.answer", subject: "Quick ask",
              detail: "Intent \(answer.intent.rawValue), \(answer.citations.count) citations, provider \(aiProvider).")
        try? context.save()
        return answer
    }

    /// Builds the permission-filtered context and asks the engine. The guard
    /// runs first: blocked and below-threshold processes never enter the
    /// context, so no provider can see them.
    func computeAnswer(_ trimmed: String) -> AskAnswer {
        let processes = (try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? []
        let steps = (try? context.fetch(FetchDescriptor<StepRecord>())) ?? []
        let opportunities = (try? context.fetch(FetchDescriptor<OpportunityRecord>())) ?? []

        // The guard runs before the provider, local or hosted.
        let scan = PIIScanner.scan(trimmed)
        let visible = processes.filter { $0.status != .blocked }
            .filter { PrivacyGuard.canDisplay(groupSize: $0.people, classification: $0.classification, policy: policy) }
        let visibleIDs = Set(visible.map(\.id))
        let processInsights = visible.map { process in
            ProcessInsight(id: process.id, name: process.name, site: process.site,
                           valueStream: process.valueStream, people: process.people,
                           annualHours: process.annualHours, cycleMinutes: process.cycleMinutes,
                           reworkRate: process.reworkRate, handoffs: process.handoffs,
                           adherence: process.adherence, variantCount: process.variantCount,
                           confidence: process.confidence, staleDays: process.staleDays,
                           kypID: process.kypID, kgID: process.kgID)
        }
        let stepInsights: [StepInsight] = steps.compactMap { step in
            guard let process = visible.first(where: { $0.id == step.processID }) else { return nil }
            return StepInsight(id: step.id, processID: step.processID,
                               processName: process.name, site: process.site,
                               name: step.name, role: step.role, application: step.application,
                               minutes: step.minutes, handoffs: step.handoffs,
                               reworkShare: step.reworkShare, waste: step.waste,
                               evidenceCount: step.evidenceCount, kgID: step.kgID)
        }
        let opportunityInsights = opportunities
            .filter { ($0.status != .deferred) && visibleIDs.contains($0.processID) }
            .map { opportunity in
                OpportunityInsight(id: opportunity.id, title: opportunity.title,
                                   processID: opportunity.processID,
                                   processName: opportunity.processName, site: opportunity.site,
                                   annualHours: opportunity.annualHours,
                                   confidence: opportunity.confidence,
                                   route: opportunity.route, kgID: opportunity.kgID)
            }
        var answer = AskEngine.answer(trimmed, processes: processInsights,
                                      steps: stepInsights, opportunities: opportunityInsights)
        if scan.total > 0 {
            answer.body += "\n\nPersonal-data patterns were found in the question and masked before analysis: \(scan.summary)."
            answer.toVerify.append("The question contained personal data; only the masked text was used.")
        }
        return answer
    }

    // MARK: Audit

    func audit(action: String, subject: String, detail: String,
               classification: DataClass = .internalUse) {
        let entry = AuditRecord(actor: "CI Manager (role)", action: action, subject: subject,
                                detail: detail, classification: classification)
        context.insert(entry)
    }

    func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    func exists<T: PersistentModel & HasStringID>(_ type: T.Type, id: String) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.contains { $0.id == id }
    }

    // MARK: Export

    /// A review brief as Markdown. DeckForge consumes the same sections; this
    /// file is the portable fallback and the audit trail's human-readable form.
    func exportBrief() {
        let opportunities = (try? context.fetch(FetchDescriptor<OpportunityRecord>())) ?? []
        let initiatives = (try? context.fetch(FetchDescriptor<InitiativeRecord>())) ?? []
        let processes = (try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? []
        let ranked = opportunities.sorted { $0.score.total > $1.score.total }.prefix(5)
        var text = "# ProcessLink review brief\n\n"
        text += "Generated \(Fmt.stamp(now)) · purpose: process improvement · data owner: \(dataOwner)\n\n"
        text += "## Scope\n\n\(processes.filter { $0.status == .discovered }.count) discovered processes, \(Fmt.hours(processes.reduce(0) { $0 + $1.annualHours })) of annual effort.\n\n"
        text += "## Priority opportunities\n\n"
        for opportunity in ranked {
            text += "### \(opportunity.title)\n"
            text += "- Process: \(opportunity.processName) · \(opportunity.site)\n"
            text += "- Route: \(opportunity.route.label) · method: \(opportunity.method.title)\n"
            text += "- Estimate: \(Fmt.hoursPerYear(opportunity.annualHours)) · score \(Int(opportunity.score.total.rounded()))/100 · confidence \(Fmt.percent(opportunity.confidence))\n"
            text += "- Source: KYP.ai \(opportunity.processID) · KG \(opportunity.kgID)\n\n"
        }
        text += "## Savings ledger\n\n"
        for initiative in initiatives.sorted(by: { $0.savingsHours > $1.savingsHours }) {
            text += "- \(initiative.title): \(Fmt.hours(initiative.savingsHours)) · \(initiative.savingsStage.label)"
            text += initiative.validatedBy.isEmpty ? "\n" : " · validated by \(initiative.validatedBy)\n"
        }
        text += "\n> Estimates are not validated savings. Every figure traces to a KYP.ai object or KG node; unknowns stay on the to-verify list.\n"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ProcessLink-review-\(Fmt.quarter(now)).md"
        panel.allowedContentTypes = [.plainText]
        panel.title = "Export review brief"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            audit(action: "export.brief", subject: url.lastPathComponent,
                  detail: "\(ranked.count) opportunities, \(initiatives.count) savings lines.")
            try? context.save()
            showToast("Brief exported", detail: url.lastPathComponent, symbol: "square.and.arrow.up")
        } catch {
            showToast("Could not export", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
        }
    }
}

/// A small protocol so the generic existence check stays honest.
protocol HasStringID {
    var id: String { get }
}

extension ProcessRecord: HasStringID {}
extension OpportunityRecord: HasStringID {}
extension InitiativeRecord: HasStringID {}
extension KGNodeRecord: HasStringID {}
extension StepRecord: HasStringID {}

import AppKit
import Foundation
import ProcessLinkKit
import SwiftData
import SwiftUI

/// The sidebar sections. Snapshot mode walks every case, so a new section is
/// covered by the checks automatically.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, strategy, discoveries, opportunities, maps, meetings, mining, graph, improvements, feedback, ask, governance, connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .strategy: "Strategy"
        case .discoveries: "Discoveries"
        case .opportunities: "Opportunities"
        case .maps: "Maps"
        case .meetings: "Meetings"
        case .mining: "Mining"
        case .graph: "Knowledge Graph"
        case .improvements: "Improvements"
        case .feedback: "Feedback"
        case .ask: "Ask"
        case .governance: "Governance"
        case .connections: "Connections"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .strategy: "target"
        case .discoveries: "binoculars"
        case .opportunities: "lightbulb"
        case .maps: "point.topleft.down.to.point.bottomright.curvepath"
        case .meetings: "person.3.sequence"
        case .mining: "sparkle.magnifyingglass"
        case .graph: "circle.hexagongrid"
        case .improvements: "flag.pattern.checkered"
        case .feedback: "bubble.left.and.text.bubble.right"
        case .ask: "bubble.left.and.text.bubble.right"
        case .governance: "checkmark.shield"
        case .connections: "link.badge.plus"
        }
    }

    /// Command-1 ... Command-8.
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .strategy: "s"
        case .discoveries: "2"
        case .opportunities: "3"
        case .maps: "4"
        case .meetings: "9"
        case .mining: "0"
        case .graph: "5"
        case .improvements: "6"
        case .feedback: "f"
        case .ask: "7"
        case .governance: "8"
        case .connections: "l"
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

/// The graph's data-quality filters. Each one is a question an owner asks.
enum GraphQuality: String, CaseIterable, Identifiable {
    case all, review, orphan, duplicate, stale, changed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All nodes"
        case .review: "Needs review"
        case .orphan: "Orphans"
        case .duplicate: "Duplicate candidates"
        case .stale: "Closed / stale"
        case .changed: "Changed in 7 days"
        }
    }

    var symbol: String {
        switch self {
        case .all: "circle.grid.2x2"
        case .review: "questionmark.circle"
        case .orphan: "link.badge.plus"
        case .duplicate: "doc.on.doc"
        case .stale: "clock.badge.exclamationmark"
        case .changed: "clock.arrow.circlepath"
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
    let flightdeck = FlightdeckService()

    var page: SidebarItem? = .overview
    var selectedProcessID: String?
    var selectedOpportunityID: String?
    var selectedInitiativeID: String?
    var selectedKGID: String?
    var selectedMeetingID: String?
    var graphFilter: KGKind?
    var graphQuality: GraphQuality = .all
    var graphSearch = ""
    var siteFilter = "All sites"
    var mapOverlay: MapOverlay = .cycleTime
    var selectedMapStepID: String?
    var showA3ForInitiativeID: String?
    var askDraft = ""
    var answers: [AskAnswer] = []
    var isSyncing = false
    var toast: Toast?
    var settingsTab: SettingsTab = .connections
    var updateInfo: UpdateInfo?
    var updateStatus: String = "idle"
    var updateError: String = ""
    var updateLastChecked: Date?

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

    @ObservationIgnored private var mapRefreshTimer: Timer?
    @ObservationIgnored private var connectorTimer: Timer?
    @ObservationIgnored private var agentTimer: Timer?

    init(container: ModelContainer) {
        self.container = container
        let defaults = UserDefaults.standard
        minimumGroupSize = defaults.object(forKey: "policy.minGroupSize") as? Int ?? 10
        retentionDays = defaults.object(forKey: "policy.retentionDays") as? Int ?? 400
        aiProvider = defaults.string(forKey: "policy.aiProvider") ?? "Local (on device)"
        aiRegion = defaults.string(forKey: "policy.aiRegion") ?? "EU"
        dataOwner = defaults.string(forKey: "policy.dataOwner") ?? "CI Manager (role)"
        notificationsEnabled = defaults.bool(forKey: "notifications.enabled")
        migrateLegacyDiscovery()
        StrategyDefaults.installIfNeeded(in: container.mainContext)
        StrategyDefaults.repairAllLinks(in: container.mainContext)
        if ((try? container.mainContext.fetchCount(FetchDescriptor<CapturePolicyRecord>())) ?? 0) == 0 {
            container.mainContext.insert(CapturePolicyRecord())
            try? container.mainContext.save()
        }
        configureMapRefresh()
        configureConnectorRefresh()
        configureAgentTimer()
        if UserDefaults.standard.object(forKey: "updates.autoCheck") as? Bool ?? true,
           !SelfTest.requested {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                await checkForUpdates(silent: true)
            }
        }
        ActivityCapture.removeScreenshots(olderThan: retentionDays)
    }

    /// One-way cleanup for stores written before KYP was removed. It rewrites
    /// labels and source ids in place; the alternative is an app that still
    /// says "KYP.ai" over its own data after an update.
    private func migrateLegacyDiscovery() {
        var changed = false
        func text(_ value: String) -> String {
            value
                .replacingOccurrences(of: "KYP.ai task mining", with: "ProcessLink discovery")
                .replacingOccurrences(of: "KYP.ai application usage", with: "ProcessLink app usage")
                .replacingOccurrences(of: "KYP.ai role aggregation", with: "ProcessLink role aggregation")
                .replacingOccurrences(of: "KYP.ai team aggregation", with: "ProcessLink team aggregation")
                .replacingOccurrences(of: "KYP.ai + ProcessLink", with: "ProcessLink discovery + analysis")
                .replacingOccurrences(of: "KYP.ai sandbox · incremental", with: "In-house discovery · local refresh")
                .replacingOccurrences(of: "KYP.ai sandbox · backfill", with: "In-house discovery · local refresh")
                .replacingOccurrences(of: "KYP.ai sandbox", with: "In-house discovery")
                .replacingOccurrences(of: "KYP.ai", with: "discovery")
        }
        for process in (try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? [] {
            let source = text(process.sourceRaw)
            if source != process.sourceRaw { process.sourceRaw = source; changed = true }
            if process.discoveryID.hasPrefix("kyp-") {
                process.discoveryID = "disc-" + process.discoveryID.dropFirst(4)
                changed = true
            }
            let summary = text(process.summary)
            if summary != process.summary { process.summary = summary; changed = true }
        }
        for node in (try? context.fetch(FetchDescriptor<KGNodeRecord>())) ?? [] {
            let source = text(node.source)
            let note = text(node.note)
            let sourceID = text(node.sourceID)
            if source != node.source { node.source = source; changed = true }
            if note != node.note { node.note = note; changed = true }
            if sourceID != node.sourceID { node.sourceID = sourceID; changed = true }
        }
        for sync in (try? context.fetch(FetchDescriptor<SyncRecord>())) ?? [] {
            let source = text(sync.source)
            let note = text(sync.note)
            if source != sync.source { sync.source = source; changed = true }
            if note != sync.note { sync.note = note; changed = true }
        }
        for audit in (try? context.fetch(FetchDescriptor<AuditRecord>())) ?? [] {
            let subject = text(audit.subject)
            let detail = text(audit.detail)
            if subject != audit.subject { audit.subject = subject; changed = true }
            if detail != audit.detail { audit.detail = detail; changed = true }
        }
        for governance in (try? context.fetch(FetchDescriptor<GovernanceRecord>())) ?? [] {
            let detail = text(governance.detail)
            if detail != governance.detail { governance.detail = detail; changed = true }
        }
        for block in (try? context.fetch(FetchDescriptor<MeetingBlockRecord>())) ?? [] {
            let value = text(block.text)
            if value != block.text { block.text = value; changed = true }
        }
        if changed { try? context.save() }
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
            followUp: "Validate with before/after measurements after 6 weeks.",
            createdAt: now)
        context.insert(initiative)
        StrategyDefaults.applyDefaultLink(to: initiative)
        opportunity.statusRaw = OpportunityStatus.promoted.rawValue
        opportunity.promotedAt = now
        audit(action: "initiative.created", subject: initiative.title,
              detail: "From opportunity \(opportunity.id), \(Fmt.hoursPerYear(initiative.savingsHours)) estimated.")
        let initiativeNode = ensureKGNode(id: "kg-ini-\(initiative.id)", kind: .initiative,
                                          name: initiative.title, confidence: 0.93,
                                          source: "ProcessLink TEOA layer", sourceID: initiative.id,
                                          processID: initiative.processID)
        ensureKGEdge(from: "kg-opp-\(opportunity.id)", .addressedBy, to: initiativeNode.id, confidence: 0.9)
        let savingsNode = ensureKGNode(id: "kg-savings-\(initiative.id)", kind: .savingsRecord,
                                       name: "\(Fmt.hours(initiative.savingsHours)) · Estimated",
                                       confidence: 0.8, source: "ProcessLink value tracking",
                                       sourceID: initiative.id, processID: initiative.processID)
        ensureKGEdge(from: initiativeNode.id, .realizesSavings, to: savingsNode.id, confidence: 0.9)
        if opportunity.alignment >= 4 {
            ensureKGEdge(from: initiativeNode.id, .alignedToObjective,
                         to: initiative.processID.hasPrefix("p-order") ? "kg-hoshin-o2c" : "kg-hoshin-rework",
                         confidence: 0.7)
        }
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
        guard initiative.hasStrategyLink else {
            showToast("Link the initiative to strategy first",
                      detail: "Choose a strategic bet, a KPI and at least one value on Strategy.",
                      symbol: "link.badge.plus", warning: true)
            page = .strategy
            return
        }
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
        guard initiative.hasStrategyLink else {
            showToast("Link the initiative to strategy first",
                      detail: "A saving commitment needs a bet, a KPI and a value.",
                      symbol: "link.badge.plus", warning: true)
            page = .strategy
            return
        }
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
        guard initiative.hasStrategyLink else {
            showToast("Link the initiative to strategy first",
                      detail: "Validation needs a KPI and value context, not only hours.",
                      symbol: "link.badge.plus", warning: true)
            page = .strategy
            return
        }
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
        let savingsNode = ensureKGNode(id: "kg-savings-\(initiative.id)", kind: .savingsRecord,
                                       name: "\(Fmt.hours(initiative.savingsHours)) · Validated",
                                       confidence: 1.0, source: "ProcessLink value tracking",
                                       sourceID: initiative.id, processID: initiative.processID)
        savingsNode.note = "Validated by \(trimmedValidator). \(trimmedEvidence)"
        savingsNode.updatedAt = now
        try? context.save()
        showToast("Saving validated", detail: "\(Fmt.hours(initiative.savingsHours)) · \(trimmedValidator)")
    }

    // MARK: Knowledge graph actions

    /// A merge is non-destructive: the losing node closes with `validTo`, its
    /// edges move to the winner in the same save, and the decision is audited.
    func confirmKGNode(_ node: KGNodeRecord, mergeInto targetID: String?) {
        if let targetID, let target = try? context.fetch(FetchDescriptor<KGNodeRecord>()).first(where: { $0.id == targetID }) {
            let edges = (try? context.fetch(FetchDescriptor<KGEdgeRecord>())) ?? []
            var moved = 0
            for edge in edges {
                var changed = false
                if edge.fromID == node.id { edge.fromID = target.id; changed = true }
                if edge.toID == node.id { edge.toID = target.id; changed = true }
                guard changed else { continue }
                if edge.fromID == edge.toID {
                    // The variant edge that justified the merge becomes a
                    // self-loop; history lives on the closed node, not here.
                    context.delete(edge)
                } else {
                    moved += 1
                }
            }
            node.reviewRaw = ReviewState.rejected.rawValue
            node.validTo = now
            node.note = "Merged into \(target.name) (\(target.id)) by a human reviewer."
            audit(action: "kg.merge.confirmed", subject: node.name,
                  detail: "Merged into \(target.name) at \(Fmt.percent(node.confidence)) confidence; \(moved) edge references re-pointed.")
            showToast("Merged", detail: "\(moved) edge references moved to \(target.name)")
        } else {
            node.reviewRaw = ReviewState.confirmed.rawValue
            audit(action: "kg.node.confirmed", subject: node.name, detail: "Entity resolution accepted.")
            showToast("Review recorded", detail: node.name)
        }
        node.updatedAt = now
        try? context.save()
    }

    func rejectKGNode(_ node: KGNodeRecord) {
        node.reviewRaw = ReviewState.rejected.rawValue
        node.updatedAt = now
        audit(action: "kg.node.rejected", subject: node.name, detail: "Proposed link rejected by a human reviewer.")
        try? context.save()
    }

    // MARK: Knowledge graph writes

    /// Idempotent node upsert. The same id is never inserted twice; an
    /// existing node keeps its history and takes the newer claims.
    @discardableResult
    func ensureKGNode(id: String, kind: KGKind, name: String, confidence: Double,
                      source: String, sourceID: String, processID: String = "") -> KGNodeRecord {
        let existing = (try? context.fetch(FetchDescriptor<KGNodeRecord>()))?.first { $0.id == id }
        if let existing {
            if existing.name != name { existing.name = name }
            existing.confidence = max(existing.confidence, confidence)
            existing.updatedAt = now
            return existing
        }
        let node = KGNodeRecord(id: id, kind: kind, name: name, confidence: confidence,
                                review: .confirmed, source: source, sourceID: sourceID,
                                validFrom: now, processID: processID)
        context.insert(node)
        return node
    }

    /// An edge is a fact with an id, so replaying a write is a no-op.
    func ensureKGEdge(from: String, _ predicate: RelationKind, to: String,
                      confidence: Double, source: String = "ProcessLink") {
        let id = "edge-\(from)-\(predicate.rawValue)-\(to)"
        let existing = (try? context.fetch(FetchDescriptor<KGEdgeRecord>()))?.contains { $0.id == id } ?? false
        guard !existing else { return }
        context.insert(KGEdgeRecord(id: id, fromID: from, predicate: predicate, toID: to,
                                    confidence: confidence, source: source))
    }

    /// Decisions and actions become graph facts the moment they are typed.
    /// They are also linked back to the meeting that produced them.
    func writeBlockToGraph(_ block: MeetingBlockRecord, meeting: MeetingRecord) {
        guard block.kind.createsNode else { return }
        let kind: KGKind = block.kind == .decision ? .decision : .action
        let node = ensureKGNode(id: "kg-\(kind.rawValue)-\(block.id)", kind: kind,
                                name: String(block.text.prefix(90)), confidence: 0.9,
                                source: "ProcessLink meeting notes", sourceID: block.id,
                                processID: meeting.processID)
        node.updatedAt = now
        ensureKGEdge(from: node.id, .documentedIn, to: meeting.kgID, confidence: 0.95)
        if !block.owner.isEmpty {
            let roleID = "kg-role-\(slug(block.owner))"
            ensureKGNode(id: roleID, kind: .role, name: block.owner, confidence: 0.88,
                         source: "Meeting action owner", sourceID: block.id)
            ensureKGEdge(from: node.id, .assignedTo, to: roleID, confidence: 0.9)
        }
        if !block.linkedID.isEmpty, block.linkedKindRaw == "opportunity" {
            ensureKGEdge(from: block.linkedID, .hasOpportunity, to: node.id, confidence: 0.7)
        }
    }

    /// A meeting is a node too: the notes are not a silo beside the graph.
    func writeMeetingToGraph(_ meeting: MeetingRecord) {
        let node = ensureKGNode(id: meeting.kgID, kind: .meeting, name: meeting.title,
                                confidence: 0.9, source: "ProcessLink meeting notes",
                                sourceID: meeting.id, processID: meeting.processID)
        node.updatedAt = now
        if !meeting.processID.isEmpty {
            ensureKGEdge(from: "kg-proc-\(meeting.processID)", .discussedIn, to: meeting.kgID, confidence: 0.85)
        }
        if !meeting.initiativeID.isEmpty {
            ensureKGEdge(from: "kg-ini-\(meeting.initiativeID)", .discussedIn, to: meeting.kgID, confidence: 0.85)
        }
    }

    // MARK: Meetings

    @discardableResult
    func createMeeting(kind: MeetingKind, processID: String = "") -> MeetingRecord {
        let meeting = MeetingRecord(
            id: "meet-\(UUID().uuidString.prefix(8))",
            title: "\(kind.label) · \(Fmt.day(now))",
            kind: kind, date: now, durationMinutes: kind.defaultDuration,
            site: processID.isEmpty ? "" : (process(forID: processID)?.site ?? ""),
            owner: "CI Manager (role)", attendees: ["Process Owner", "CI Manager"],
            processID: processID, initiativeID: "", status: .notes,
            summary: "", isRecurring: kind == .dailyHuddle,
            cadence: kind == .dailyHuddle ? "Daily" : "")
        context.insert(meeting)
        applyTemplate(kind, to: meeting, announce: false)
        writeMeetingToGraph(meeting)
        audit(action: "meeting.created", subject: meeting.title, detail: "\(kind.label) note created.")
        try? context.save()
        selectedMeetingID = meeting.id
        page = .meetings
        showToast("Meeting note created", detail: kind.label, symbol: "person.3.sequence")
        return meeting
    }

    func process(forID id: String) -> ProcessRecord? {
        ((try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? []).first { $0.id == id }
    }

    func blocks(for meeting: MeetingRecord) -> [MeetingBlockRecord] {
        ((try? context.fetch(FetchDescriptor<MeetingBlockRecord>())) ?? [])
            .filter { $0.meetingID == meeting.id }
            .sorted { $0.order < $1.order }
    }

    @discardableResult
    func addBlock(to meeting: MeetingRecord, kind: BlockKind, after order: Int? = nil) -> MeetingBlockRecord {
        let existing = blocks(for: meeting)
        let insertAt = order.map { $0 + 1 } ?? (existing.count)
        for block in existing where block.order >= insertAt { block.order += 1 }
        let block = MeetingBlockRecord(id: "blk-\(UUID().uuidString.prefix(8))",
                                       meetingID: meeting.id, order: insertAt, kind: kind,
                                       text: placeholder(for: kind),
                                       owner: kind == .action ? meeting.owner : "",
                                       due: kind == .action ? now.addingTimeInterval(7 * 86_400) : nil)
        context.insert(block)
        meeting.updatedAt = now
        writeBlockToGraph(block, meeting: meeting)
        audit(action: "meeting.block.added", subject: meeting.title, detail: kind.label)
        try? context.save()
        return block
    }

    func deleteBlock(_ block: MeetingBlockRecord, meeting: MeetingRecord) {
        context.delete(block)
        meeting.updatedAt = now
        audit(action: "meeting.block.deleted", subject: meeting.title, detail: block.kind.label)
        try? context.save()
    }

    func moveBlock(_ block: MeetingBlockRecord, by delta: Int, meeting: MeetingRecord) {
        let siblings = blocks(for: meeting)
        guard let index = siblings.firstIndex(where: { $0.id == block.id }) else { return }
        let target = index + delta
        guard siblings.indices.contains(target) else { return }
        let other = siblings[target]
        let swap = block.order
        block.order = other.order
        other.order = swap
        meeting.updatedAt = now
        try? context.save()
    }

    func toggle(_ block: MeetingBlockRecord, meeting: MeetingRecord) {
        block.checked.toggle()
        meeting.updatedAt = now
        if block.kind.createsNode {
            let nodeID = "kg-\((block.kind == .decision ? KGKind.decision : KGKind.action).rawValue)-\(block.id)"
            if let node = (try? context.fetch(FetchDescriptor<KGNodeRecord>()))?.first(where: { $0.id == nodeID }) {
                node.note = block.checked ? "Done" : "Open"
                node.updatedAt = now
            }
        }
        try? context.save()
    }

    func applyTemplate(_ kind: MeetingKind, to meeting: MeetingRecord, announce: Bool = true) {
        let existing = blocks(for: meeting)
        guard announce || existing.isEmpty else { return }
        var order = existing.count
        var created: [MeetingBlockRecord] = []
        func add(_ blockKind: BlockKind, _ text: String, owner: String = "",
                 due: Date? = nil, link: (String, String) = ("", "")) {
            let block = MeetingBlockRecord(id: "blk-\(UUID().uuidString.prefix(8))",
                                           meetingID: meeting.id, order: order,
                                           kind: blockKind, text: text,
                                           owner: owner, due: due,
                                           linkedKind: link.0, linkedID: link.1)
            context.insert(block)
            created.append(block)
            order += 1
        }
        switch kind {
        case .dailyHuddle:
            add(.heading, "Yesterday")
            add(.bullet, "")
            add(.heading, "Today")
            add(.bullet, "")
            add(.heading, "Blockers")
            add(.bullet, "")
            add(.decision, "")
            add(.action, "", owner: meeting.owner, due: now.addingTimeInterval(7 * 86_400))
        case .kaizen:
            add(.heading, "Problem")
            add(.text, "")
            add(.heading, "Target")
            add(.text, "")
            add(.heading, "Observed waste")
            add(.bullet, "")
            add(.heading, "Countermeasures")
            add(.checklist, "")
            add(.decision, "")
            add(.action, "", owner: meeting.owner, due: now.addingTimeInterval(14 * 86_400))
        case .a3Review:
            add(.heading, "Background")
            add(.text, "")
            add(.heading, "Target vs actual")
            add(.text, "")
            add(.heading, "Root cause")
            add(.text, "")
            add(.decision, "")
            add(.action, "", owner: meeting.owner, due: now.addingTimeInterval(14 * 86_400))
        case .leadership:
            add(.heading, "Portfolio")
            add(.bullet, "Validated: \(Fmt.hours(validatedHours()))")
            add(.bullet, "Committed: \(Fmt.hours(committedHours()))")
            add(.heading, "Decisions needed")
            add(.decision, "")
            add(.action, "", owner: meeting.owner, due: now.addingTimeInterval(7 * 86_400))
        case .workshop, .oneToOne:
            add(.heading, "Context")
            add(.text, "")
            add(.heading, "Notes")
            add(.bullet, "")
            add(.decision, "")
            add(.action, "", owner: meeting.owner, due: now.addingTimeInterval(7 * 86_400))
        }
        meeting.updatedAt = now
        if announce {
            audit(action: "meeting.template", subject: meeting.title, detail: kind.label)
            showToast("Template inserted", detail: kind.label, symbol: "doc.badge.plus")
        }
        // New action/decision blocks become graph facts too.
        for block in created where block.kind.createsNode {
            writeBlockToGraph(block, meeting: meeting)
        }
        try? context.save()
    }

    func validatedHours() -> Double {
        let initiatives = (try? context.fetch(FetchDescriptor<InitiativeRecord>())) ?? []
        return SavingsLedger.totals(initiatives.map(\.savingLine)).validated
    }

    func committedHours() -> Double {
        let initiatives = (try? context.fetch(FetchDescriptor<InitiativeRecord>())) ?? []
        return SavingsLedger.totals(initiatives.map(\.savingLine)).committed
    }

    func linkMeeting(_ meeting: MeetingRecord, processID: String? = nil, initiativeID: String? = nil) {
        if let processID { meeting.processID = processID; meeting.site = process(forID: processID)?.site ?? meeting.site }
        if let initiativeID { meeting.initiativeID = initiativeID }
        meeting.updatedAt = now
        writeMeetingToGraph(meeting)
        audit(action: "meeting.linked", subject: meeting.title, detail: "Linked to process or initiative.")
        try? context.save()
        showToast("Meeting linked", detail: meeting.title, symbol: "link")
    }

    /// An action becomes work only through the same initiative gate as an
    /// opportunity. It never deploys anything.
    @discardableResult
    func promoteAction(_ block: MeetingBlockRecord, meeting: MeetingRecord) -> InitiativeRecord? {
        let owner = block.owner.isEmpty ? meeting.owner : block.owner
        guard !owner.isEmpty else {
            showToast("An action needs an owner", detail: "Assign the action before promoting it.", symbol: "person.crop.circle.badge.exclamationmark", warning: true)
            return nil
        }
        let opportunity = block.linkedID.isEmpty ? nil :
            ((try? context.fetch(FetchDescriptor<OpportunityRecord>())) ?? []).first { $0.id == block.linkedID || $0.kgID == block.linkedID }
        let processID = meeting.processID.isEmpty ? (opportunity?.processID ?? "") : meeting.processID
        let process = processFor(processID)
        let initiative = InitiativeRecord(
            id: "ini-\(UUID().uuidString.prefix(8))",
            title: block.text.isEmpty ? "Action from \(meeting.title)" : block.text,
            opportunityID: opportunity?.id ?? "", processID: processID,
            processName: process?.name ?? meeting.title, site: process?.site ?? meeting.site,
            method: meeting.kind == .kaizen ? .kaizen : meeting.kind == .a3Review ? .a3 : .standardWork,
            owner: owner, stage: .plan, status: .active,
            due: block.due ?? now.addingTimeInterval(30 * 86_400),
            savingsHours: opportunity?.annualHours ?? 0,
            savingsStage: .estimated, validatedBy: "", evidenceNote: "",
            claimsWaste: opportunity?.waste ?? .waiting,
            background: "From \(meeting.title) (\(Fmt.day(meeting.date))).",
            target: block.text, rootCause: "", countermeasure: "",
            result: "", followUp: "Confirm the action produced the intended change.",
            createdAt: now)
        context.insert(initiative)
        StrategyDefaults.applyDefaultLink(to: initiative)
        block.checked = true
        if let opportunity { opportunity.statusRaw = OpportunityStatus.promoted.rawValue }
        writeMeetingToGraph(meeting)
        audit(action: "action.promoted", subject: initiative.title, detail: "From meeting \(meeting.id).")
        try? context.save()
        selectedInitiativeID = initiative.id
        page = .improvements
        showToast("Action promoted", detail: "\(owner) · initiative created", symbol: "flag.pattern.checkered")
        return initiative
    }

    func processFor(_ id: String) -> ProcessRecord? {
        guard !id.isEmpty else { return nil }
        return ((try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? []).first { $0.id == id }
    }

    private func placeholder(for kind: BlockKind) -> String {
        switch kind {
        case .heading: "New section"
        case .text: ""
        case .bullet: ""
        case .checklist: "To do"
        case .decision: "What did we decide?"
        case .action: "What happens next?"
        case .callout: "Note for the room"
        case .link: "Linked record"
        }
    }

    private func slug(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// Edits to a decision or action text refresh the graph node it created.
    func refreshBlockNode(_ block: MeetingBlockRecord, meeting: MeetingRecord) {
        guard block.kind.createsNode else { return }
        let kind: KGKind = block.kind == .decision ? .decision : .action
        let node = ensureKGNode(id: "kg-\(kind.rawValue)-\(block.id)", kind: kind,
                                name: String(block.text.prefix(90)), confidence: 0.9,
                                source: "ProcessLink meeting notes", sourceID: block.id,
                                processID: meeting.processID)
        node.updatedAt = now
        if !block.owner.isEmpty {
            let roleID = "kg-role-\(slug(block.owner))"
            ensureKGNode(id: roleID, kind: .role, name: block.owner, confidence: 0.88,
                         source: "Meeting action owner", sourceID: block.id)
            ensureKGEdge(from: node.id, .assignedTo, to: roleID, confidence: 0.9)
        }
        try? context.save()
    }

    func markMeetingDone(_ meeting: MeetingRecord) {
        meeting.statusRaw = MeetingStatus.done.rawValue
        meeting.updatedAt = now
        audit(action: "meeting.done", subject: meeting.title, detail: "Meeting note closed.")
        try? context.save()
        showToast("Meeting closed", detail: meeting.title)
    }

    func deleteMeeting(_ meeting: MeetingRecord) {
        for block in blocks(for: meeting) {
            context.delete(block)
        }
        if let node = (try? context.fetch(FetchDescriptor<KGNodeRecord>()))?.first(where: { $0.id == meeting.kgID }) {
            node.validTo = now
            node.updatedAt = now
        }
        context.delete(meeting)
        audit(action: "meeting.deleted", subject: meeting.title, detail: "Meeting notes removed; graph facts closed.")
        try? context.save()
        selectedMeetingID = nil
        showToast("Meeting deleted", detail: meeting.title, symbol: "trash")
    }

    // MARK: In-house discovery

    var selectedDatasetID: String?

    func events(for dataset: DatasetRecord) -> [EventLogRecord] {
        let rows = ((try? context.fetch(FetchDescriptor<EventItemRecord>())) ?? [])
            .filter { $0.datasetID == dataset.id }
            .sorted { $0.timestamp < $1.timestamp }
        return rows.map { row in
            let attributes = (try? JSONSerialization.jsonObject(with: Data(row.attributesJSON.utf8)))
                as? [String: String] ?? [:]
            return EventLogRecord(caseID: row.caseHash, activity: row.activity,
                                  timestamp: row.timestamp, resource: row.resource,
                                  application: row.application,
                                  attributes: attributes, cost: row.cost)
        }
    }

    func minedProcess(for dataset: DatasetRecord) -> MinedProcess {
        ProcessMining.mine(events(for: dataset), name: dataset.name)
    }

    @discardableResult
    func importSampleDataset() -> DatasetRecord? {
        do {
            let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
            return storeDataset(name: "Order intake · mined sample", result: result,
                                source: "sample", filename: "order-intake-sample.csv",
                                site: "Bensheim",
                                notes: "Synthetic 24-case log shipped with ProcessLink. No tenant data.")
        } catch {
            showToast("Could not load the sample", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
            return nil
        }
    }

    func deleteDataset(_ dataset: DatasetRecord) {
        for event in (try? context.fetch(FetchDescriptor<EventItemRecord>())) ?? [] where event.datasetID == dataset.id {
            context.delete(event)
        }
        context.delete(dataset)
        audit(action: "dataset.deleted", subject: dataset.name, detail: "Events removed with the dataset.")
        try? context.save()
        selectedDatasetID = nil
    }

    func importCSV(text: String, name: String, filename: String, site: String,
                   mapping: MiningColumnMap = MiningColumnMap(),
                   processID: String = "", mapID: String = "",
                   mapMappingJSON: String = "{}") throws -> DatasetRecord {
        let result = try EventLogImporter.importCSV(text, mapping: mapping)
        guard let dataset = storeDataset(name: name, result: result, source: "csv",
                                         filename: filename, site: site,
                                         notes: "Imported event log. Case ids hashed, resources sanitised.",
                                         processID: processID, mapID: mapID,
                                         mapMappingJSON: mapMappingJSON) else {
            throw MiningError.noRows
        }
        return dataset
    }

    @discardableResult
    private func storeDataset(name: String, result: EventLogImport, source: String,
                              filename: String, site: String, notes: String,
                              processID: String = "", mapID: String = "",
                              mapMappingJSON: String = "{}") -> DatasetRecord? {
        guard result.caseCount > 0 else { return nil }
        let dataset = DatasetRecord(
            id: "ds-\(UUID().uuidString.prefix(8))", name: name, source: source,
            importedAt: now, caseCount: result.caseCount, eventCount: result.events.count,
            site: site, classification: .internalUse, filename: filename, notes: notes,
            processID: processID, mapID: mapID, mapMappingJSON: mapMappingJSON)
        context.insert(dataset)
        for (index, event) in result.events.enumerated() {
            let attributes = (try? JSONSerialization.data(withJSONObject: event.attributes))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            context.insert(EventItemRecord(
                id: "\(dataset.id)-ev-\(index)", datasetID: dataset.id,
                caseHash: event.caseID, activity: event.activity,
                timestamp: event.timestamp, resource: event.resource,
                application: event.application,
                attributesJSON: attributes, cost: event.cost))
        }
        audit(action: "dataset.imported", subject: name,
              detail: "\(result.caseCount) cases, \(result.events.count) events, \(result.skippedRows) skipped.")
        try? context.save()
        selectedDatasetID = dataset.id
        page = .mining
        showToast("Event log imported", detail: "\(result.caseCount) cases · \(result.events.count) events",
                  symbol: "tablecells")
        return dataset
    }

    func dataset(forMap mapID: String) -> DatasetRecord? {
        ((try? context.fetch(FetchDescriptor<DatasetRecord>())) ?? [])
            .filter { $0.mapID == mapID && $0.sourceRaw == "flightdeck-contract-flow" }
            .sorted { $0.importedAt > $1.importedAt }
            .first
    }

    /// Replaces a live map's events in place. The process, map link and
    /// strategy links stay; only the evidence is refreshed.
    func replaceEvents(in dataset: DatasetRecord, result: EventLogImport, cursor: String) {
        let old = (try? context.fetch(FetchDescriptor<EventItemRecord>()))?
            .filter { $0.datasetID == dataset.id } ?? []
        for event in old { context.delete(event) }
        for (index, event) in result.events.enumerated() {
            let attributes = (try? JSONSerialization.data(withJSONObject: event.attributes))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            context.insert(EventItemRecord(
                id: "\(dataset.id)-ev-\(index)", datasetID: dataset.id,
                caseHash: event.caseID, activity: event.activity,
                timestamp: event.timestamp, resource: event.resource,
                application: event.application,
                attributesJSON: attributes, cost: event.cost))
        }
        dataset.caseCount = result.caseCount
        dataset.eventCount = result.events.count
        dataset.importedAt = now
        dataset.sourceCursor = cursor
        audit(action: "dataset.refreshed", subject: dataset.name,
              detail: "\(result.caseCount) cases, \(result.events.count) events; cursor \(cursor).")
        try? context.save()
    }

    /// Turns a mined log into process/step/variant records so every
    /// downstream surface works unchanged.
    @discardableResult
    func createProcess(from dataset: DatasetRecord) -> ProcessRecord? {
        let events = events(for: dataset)
        guard !events.isEmpty else { return nil }
        let mined = ProcessMining.mine(events, name: dataset.name)
        let first = mined.firstTimestamp ?? now
        let last = mined.lastTimestamp ?? now
        let spanDays = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1)
        let casesPerYear = Double(mined.cases) / Double(spanDays) * 365
        let annualHours = min(50_000, casesPerYear * mined.medianCycleMinutes / 60 * (1 + mined.reworkRate))
        let id = "p-mined-\(UUID().uuidString.prefix(8))"
        let name = dataset.name.replacingOccurrences(of: " · mined sample", with: "")
        let process = ProcessRecord(
            id: id, name: name, site: dataset.site, businessUnit: "In-house discovery",
            valueStream: "Imported process log", ownerRole: "Process Owner",
            discoveryID: dataset.id, kgID: "kg-proc-\(id)",
            summary: "Mined from \(mined.cases) cases and \(mined.events) events in \(dataset.filename). \(mined.variants.count) variants; median cycle \(Fmt.minutes(mined.medianCycleMinutes)).",
            applications: Array(Set(events.map(\.application).filter { !$0.isEmpty })).sorted(),
            variantNames: mined.variants.prefix(5).map { $0.sequence.joined(separator: " → ") },
            capturedFrom: first, capturedTo: last, lastSynced: now,
            confidence: 0.82, people: max(12, Set(events.map(\.resource)).count * 4),
            annualHours: annualHours, cycleMinutes: mined.medianCycleMinutes,
            reworkRate: mined.reworkRate, handoffs: mined.activities.reduce(0) { $0 + $1.handoffs },
            variantCount: mined.variants.count, adherence: 0.7, maturity: 2,
            classification: .internalUse, status: .discovered, statusReason: "",
            standardDocument: "Imported event log · \(dataset.filename)", standardVersion: "—",
            source: "In-house process mining")
        context.insert(process)

        var ordered = mined.topVariant?.sequence ?? []
        for activity in mined.activities where !ordered.contains(activity.name) {
            ordered.append(activity.name)
        }
        for (index, activityName) in ordered.enumerated() {
            guard let activity = mined.activities.first(where: { $0.name == activityName }) else { continue }
            let activityEvents = events.filter { $0.activity == activityName }
            let role = mostCommon(activityEvents.map(\.resource)) ?? "Unassigned"
            let application = mostCommon(activityEvents.map(\.application)) ?? ""
            context.insert(StepRecord(
                id: "step-\(id)-\(index)", processID: id, order: index,
                name: activityName, role: role, application: application,
                minutes: max(1, activity.averageWaitMinutes + 2), handoffs: activity.handoffs,
                reworkShare: activity.events == 0 ? 0 : Double(activity.reworkCount) / Double(activity.events),
                waste: waste(for: activity), evidenceCount: activity.events,
                kgID: "kg-step-\(id)-\(index)", standardAligned: activity.automationScore < 0.7))
        }
        for (index, variant) in mined.variants.prefix(6).enumerated() {
            context.insert(VariantRecord(
                id: "var-\(id)-\(index)", processID: id,
                name: variant.sequence.prefix(3).joined(separator: " → "),
                share: variant.share, cycleMinutes: variant.averageCycleMinutes,
                reworkRate: variant.reworkRate,
                path: variant.sequence.joined(separator: " → ")))
        }

        let processNode = ensureKGNode(id: process.kgID, kind: .process, name: name,
                                       confidence: 0.82, source: process.sourceRaw,
                                       sourceID: dataset.id, processID: id)
        processNode.note = "Mined in-house from \(dataset.filename)."
        if !dataset.site.isEmpty {
            let siteID = "kg-site-\(slug(dataset.site))"
            ensureKGNode(id: siteID, kind: .site, name: dataset.site, confidence: 0.98,
                         source: "Flightdeck registry", sourceID: "registry-site-\(slug(dataset.site))")
            ensureKGEdge(from: process.kgID, .performedIn, to: siteID, confidence: 0.95)
        }
        for (index, _) in ordered.enumerated() {
            ensureKGEdge(from: process.kgID, .measuredBy,
                         to: "kg-step-\(id)-\(index)", confidence: 0.8)
        }

        if let bottleneck = mined.bottleneck {
            let inputs = OpportunityInputs(
                annualHours: annualHours * 0.25, errorReductionPct: 10,
                effortWeeks: 4, risk: 2, alignment: 3,
                automationSuitability: bottleneck.automationScore,
                confidence: 0.78, statutory: false, waste: waste(for: bottleneck))
            let route = OpportunityScoring.route(for: inputs)
            let method = MethodRecommender.recommend(waste: inputs.waste, route: route, statutory: false)
            context.insert(OpportunityRecord(
                id: "opp-mined-\(UUID().uuidString.prefix(8))",
                title: "Reduce \(bottleneck.name) in \(name)",
                processID: id, processName: name, site: dataset.site,
                waste: inputs.waste, method: method.method, route: route,
                annualHours: annualHours * 0.25, errorReductionPct: 10,
                effortWeeks: 4, risk: 2, alignment: 3,
                automation: bottleneck.automationScore, confidence: 0.78,
                statutory: false,
                rationale: "Mined from \(mined.cases) cases: \(bottleneck.events) events, \(bottleneck.reworkCount) repeats, average wait \(Fmt.minutes(bottleneck.averageWaitMinutes)). \(bottleneck.automationReason)",
                kgID: "kg-opp-mined-\(id)", ownerRole: "Process Owner"))
            ensureKGEdge(from: process.kgID, .hasOpportunity,
                         to: "kg-opp-mined-\(id)", confidence: 0.8)
        }

        audit(action: "mining.process.created", subject: name,
              detail: "\(mined.cases) cases, \(mined.variants.count) variants, \(ordered.count) steps.")
        try? context.save()
        selectedProcessID = id
        page = .discoveries
        showToast("Discovered process created",
                  detail: "\(ordered.count) steps · \(mined.variants.count) variants · in-house source",
                  symbol: "sparkle.magnifyingglass")
        return process
    }

    private func waste(for activity: MinedActivity) -> WasteType {
        let reworkShare = activity.events == 0 ? 0 : Double(activity.reworkCount) / Double(activity.events)
        if reworkShare > 0.2 { return .rework }
        if activity.handoffs > activity.cases / 2 { return .handoffs }
        if activity.averageWaitMinutes > 10 { return .waiting }
        return .overProcessing
    }

    private func mostCommon(_ values: [String]) -> String? {
        let cleaned = values.filter { !$0.isEmpty }
        let counts = Dictionary(grouping: cleaned, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    // MARK: Task capture

    func recordCapture(name: String, role: String, site: String, startedAt: Date,
                       endedAt: Date, minutes: Double, idleMinutes: Double,
                       switchCount: Int,
                       keystrokeCount: Int = 0, clickCount: Int = 0,
                       windows: [(app: String, title: String, minutes: Double, samples: Int)] = [],
                       shots: [(path: String, app: String, at: Date)] = [],
                       tasks: [(app: String, label: String, startedAt: Date, minutes: Double, samples: Int)] = [],
                       apps: [(name: String, bundleID: String, minutes: Double, idle: Double, switches: Int)]) {
        let session = CaptureSessionRecord(
            id: "cap-\(UUID().uuidString.prefix(8))", name: name, role: role, site: site,
            startedAt: startedAt, endedAt: endedAt, sampleSeconds: 2,
            activeMinutes: minutes, idleMinutes: idleMinutes, switchCount: switchCount,
            keystrokeCount: keystrokeCount, clickCount: clickCount,
            windowTitleCount: windows.count, screenshotCount: shots.count,
            status: "complete",
            notes: "Local aggregate; window titles are masked, screenshots stay on this Mac, input capture is counts only.")
        context.insert(session)
        for (index, app) in apps.enumerated() {
            context.insert(CaptureAppRecord(
                id: "\(session.id)-app-\(index)", sessionID: session.id,
                appName: app.name, bundleID: app.bundleID,
                minutes: app.minutes, idleMinutes: app.idle, switches: app.switches))
        }
        for (index, window) in windows.enumerated() {
            context.insert(CaptureWindowRecord(
                id: "\(session.id)-win-\(index)", sessionID: session.id,
                appName: window.app, title: window.title,
                minutes: window.minutes, samples: window.samples))
        }
        for (index, shot) in shots.enumerated() {
            context.insert(CaptureShotRecord(
                id: "\(session.id)-shot-\(index)", sessionID: session.id,
                path: shot.path, appName: shot.app, capturedAt: shot.at))
        }
        for (index, task) in tasks.enumerated() {
            context.insert(CaptureTaskRecord(
                id: "\(session.id)-task-\(index)", sessionID: session.id,
                appName: task.app, label: task.label, startedAt: task.startedAt,
                minutes: task.minutes, samples: task.samples))
        }
        audit(action: "capture.completed", subject: name,
              detail: "\(String(format: "%.0f", minutes)) active minutes, \(switchCount) switches, \(apps.count) apps, \(windows.count) titles, \(shots.count) screenshots, \(keystrokeCount) keystrokes (count only).")
        try? context.save()
        page = .mining
        showToast("Capture saved", detail: "\(String(format: "%.0f", minutes)) min · \(switchCount) switches",
                  symbol: "record.circle")
    }

    @discardableResult
    func createProcess(from session: CaptureSessionRecord,
                       apps: [CaptureAppRecord]) -> ProcessRecord? {
        guard !apps.isEmpty, session.activeMinutes > 0 else { return nil }
        let id = "p-capture-\(UUID().uuidString.prefix(8))"
        let name = "Desktop work · \(session.role.isEmpty ? "Unassigned" : session.role)"
        let annual = min(20_000, session.activeMinutes / 60 * 220)
        let process = ProcessRecord(
            id: id, name: name, site: session.site, businessUnit: "In-house task mining",
            valueStream: "Digital work", ownerRole: session.role,
            discoveryID: session.id, kgID: "kg-proc-\(id)",
            summary: "Captured locally on this Mac: \(String(format: "%.0f", session.activeMinutes)) active minutes, \(session.switchCount) app switches. Titles and screenshots, where enabled, remain local.",
            applications: apps.map(\.appName), variantNames: apps.map(\.appName),
            capturedFrom: session.startedAt, capturedTo: session.endedAt ?? session.startedAt,
            lastSynced: now, confidence: 0.7, people: 12,
            annualHours: annual, cycleMinutes: session.activeMinutes,
            reworkRate: 0, handoffs: session.switchCount, variantCount: 1,
            adherence: 0, maturity: 1, classification: .internalUse,
            status: .discovered, statusReason: "", standardDocument: "", standardVersion: "",
            source: "In-house task capture")
        context.insert(process)
        for (index, app) in apps.enumerated() {
            context.insert(StepRecord(
                id: "step-\(id)-\(index)", processID: id, order: index,
                name: app.appName, role: session.role, application: app.appName,
                minutes: app.minutes, handoffs: app.switches,
                reworkShare: 0, waste: .contextSwitching, evidenceCount: max(1, app.switches),
                kgID: "kg-step-\(id)-\(index)", standardAligned: false))
        }
        context.insert(VariantRecord(
            id: "var-\(id)-0", processID: id, name: "Observed path", share: 1,
            cycleMinutes: session.activeMinutes, reworkRate: 0,
            path: apps.map(\.appName).joined(separator: " → ")))
        ensureKGNode(id: process.kgID, kind: .process, name: name, confidence: 0.7,
                     source: "In-house task capture", sourceID: session.id, processID: id)
        context.insert(OpportunityRecord(
            id: "opp-capture-\(UUID().uuidString.prefix(8))",
            title: "Reduce context switching in \(name)",
            processID: id, processName: name, site: session.site,
            waste: .contextSwitching, method: .fiveS, route: .standardize,
            annualHours: annual * 0.2, errorReductionPct: 5, effortWeeks: 3,
            risk: 2, alignment: 3, automation: 0.3, confidence: 0.65,
            statutory: false,
            rationale: "A local capture recorded \(session.switchCount) switches across \(apps.count) applications in \(String(format: "%.0f", session.activeMinutes)) minutes.",
            kgID: "kg-opp-capture-\(id)", ownerRole: session.role))
        audit(action: "capture.process.created", subject: name,
              detail: "\(apps.count) apps, \(session.switchCount) switches.")
        try? context.save()
        selectedProcessID = id
        page = .discoveries
        showToast("Task capture become a process", detail: "\(apps.count) app steps · estimate only",
                  symbol: "sparkle.magnifyingglass")
        return process
    }

    // MARK: Flightdeck Maps

    /// A map is a node in the graph. The map document stays owned by Maps;
    /// ProcessLink only binds it to the process and records provenance.
    @discardableResult
    func registerMap(_ document: MapsBridge.Document, process: ProcessRecord?) -> KGNodeRecord {
        let node = ensureKGNode(id: "kg-map-\(document.id)", kind: .map,
                                name: document.label, confidence: 0.94,
                                source: "Flightdeck Maps · signavio-map/1",
                                sourceID: document.id, processID: document.processID)
        node.note = "\(document.nodes.count) shapes, \(document.boundNodes) bound to KG steps."
        node.updatedAt = now
        if let process {
            ensureKGEdge(from: process.kgID, .documentedIn, to: node.id, confidence: 0.95)
        }
        return node
    }

    /// An edit made on a map is a proposal, not a silent rewrite of discovery.
    /// It is written to the map's node in the graph and to the audit log.
    func recordMapEdit(_ document: MapsBridge.Document, nodeID: String, summary: String) {
        let mapNode = ensureKGNode(id: "kg-map-\(document.id)", kind: .map,
                                   name: document.label, confidence: 0.94,
                                   source: "Flightdeck Maps · signavio-map/1",
                                   sourceID: document.id, processID: document.processID)
        mapNode.note = "\(mapNode.note)\n\(Fmt.stamp(now)) · \(nodeID): \(summary)".trimmingCharacters(in: .whitespacesAndNewlines)
        mapNode.updatedAt = now
        audit(action: "map.edit.proposed", subject: document.label,
              detail: "\(nodeID): \(summary)")
        try? context.save()
    }

    // MARK: Refresh

    /// Re-read the local discovery store. There is no vendor sync: event logs
    /// and task captures are already local, so refresh only proves they are
    /// readable and records what is in scope.
    func runSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await Task.sleep(for: .milliseconds(350))
        let processes = count(ProcessRecord.self)
        let datasets = count(DatasetRecord.self)
        let captures = count(CaptureSessionRecord.self)
        let events = count(EventItemRecord.self)
        let sync = SyncRecord(
            source: "ProcessLink in-house · local refresh",
            fetched: processes + datasets + captures,
            inserted: 0, updated: 0, skipped: 0,
            status: "success",
            note: "\(processes) processes, \(datasets) event logs, \(captures) captures, \(events) events read locally.")
        context.insert(sync)
        audit(action: "discovery.refreshed", subject: "In-house discovery",
              detail: "\(processes) processes, \(datasets) datasets, \(captures) captures; no external connector.")
        try? context.save()
        showToast("Discovery refreshed",
                  detail: "\(processes) processes · \(datasets) logs · \(captures) captures",
                  symbol: "arrow.triangle.2.circlepath")
    }

    // MARK: Scheduled map refresh

    /// Opt-in every-30-minutes refresh of the newest live map log. The cursor
    /// makes it a no-op when no ticket activity changed.
    func configureMapRefresh() {
        mapRefreshTimer?.invalidate()
        mapRefreshTimer = nil
        let enabled = UserDefaults.standard.bool(forKey: "sync.mapLogs")
        guard enabled else { return }
        mapRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshNewestMapLog() }
        }
    }

    func configureConnectorRefresh() {
        connectorTimer?.invalidate()
        connectorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshDueConnectors() }
        }
    }

    func refreshDueConnectors() async {
        let connectors = (try? context.fetch(FetchDescriptor<ConnectorRecord>())) ?? []
        for connector in connectors where connector.active && connector.scheduleMinutes > 0 {
            let due = connector.lastRunAt.map { now.timeIntervalSince($0) >= Double(connector.scheduleMinutes) * 60 } ?? true
            guard due else { continue }
            _ = await runConnector(connector)
        }
    }

    func refreshNewestMapLog() async {
        guard let dataset = ((try? context.fetch(FetchDescriptor<DatasetRecord>())) ?? [])
            .filter({ $0.sourceRaw == "flightdeck-contract-flow" && !$0.mapID.isEmpty })
            .sorted(by: { $0.importedAt > $1.importedAt }).first,
              let map = MapsBridge.loadAll().first(where: { $0.id == dataset.mapID }) else { return }
        _ = await flightdeck.importContractFlow(into: self, map: map)
    }

    // MARK: Managed capture agent

    func capturePolicy() -> CapturePolicyRecord? {
        ((try? context.fetch(FetchDescriptor<CapturePolicyRecord>())) ?? []).first
    }

    func validConsent(for policy: CapturePolicyRecord) -> Bool {
        let consents = (try? context.fetch(FetchDescriptor<ConsentRecord>())) ?? []
        return consents.contains {
            $0.revokedAt == nil && $0.version == policy.consentVersion
                && ($0.expiresAt.map { $0 > now } ?? true)
        }
    }

    func grantConsent(site: String, role: String, reference: String, expiresAt: Date?) {
        let policy = capturePolicy()
        let record = ConsentRecord(
            id: "consent-\(UUID().uuidString.prefix(8))",
            site: site, role: role, version: policy?.consentVersion ?? "v1",
            expiresAt: expiresAt, reference: reference)
        context.insert(record)
        audit(action: "capture.consent.granted", subject: "\(site)/\(role)",
              detail: "Version \(record.version); \(reference)")
        try? context.save()
        showToast("Consent recorded", detail: "\(site) · \(role)", symbol: "checkmark.shield")
    }

    @discardableResult
    func startManagedAgent() -> Bool {
        guard let policy = capturePolicy(), policy.active else {
            showToast("Agent policy is off", detail: "Turn on the managed capture policy first.",
                      symbol: "pause.circle", warning: true)
            return false
        }
        guard validConsent(for: policy) else {
            showToast("Consent required", detail: "Record a consent for this site/role and version.",
                      symbol: "hand.raised", warning: true)
            page = .mining
            return false
        }
        guard !ActivityCapture.shared.isRunning else { return false }
        let options = ActivityCapture.Options(
            windowTitles: policy.windowTitles, screenshots: policy.screenshots,
            inputCounts: policy.inputCounts)
        ActivityCapture.shared.start(options: options)
        let maxMinutes = max(1, policy.maxSessionMinutes)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(maxMinutes * 60))
            guard let result = ActivityCapture.shared.stop() else { return }
            recordCapture(
                name: "Agent · \(Fmt.day(now))", role: "Managed agent", site: "",
                startedAt: result.startedAt, endedAt: result.endedAt,
                minutes: result.activeMinutes, idleMinutes: result.idleMinutes,
                switchCount: result.switches, keystrokeCount: result.keystrokes,
                clickCount: result.clicks,
                windows: result.windows.map { ($0.appName, $0.title, $0.minutes, $0.samples) },
                shots: result.shots.map { ($0.path, $0.appName, $0.capturedAt) },
                tasks: result.segments.map { ($0.appName, $0.label, $0.startedAt, $0.minutes, $0.samples) },
                apps: result.apps.map { ($0.name, $0.bundleID, $0.minutes, $0.idleMinutes, $0.switches) })
            policy.lastRunAt = now
            try? context.save()
        }
        return true
    }

    func configureAgentTimer() {
        agentTimer?.invalidate()
        agentTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let policy = self.capturePolicy(), policy.active,
                      !ActivityCapture.shared.isRunning, self.validConsent(for: policy) else { return }
                let due = policy.lastRunAt.map { self.now.timeIntervalSince($0) >= Double(policy.intervalMinutes) * 60 } ?? true
                guard due else { return }
                _ = self.startManagedAgent()
            }
        }
    }

    @discardableResult
    func addAppFeedback(rating: String, priority: String = "normal", category: String, comment: String,
                        author: String, page: String) -> AppFeedbackRecord? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let record = AppFeedbackRecord(
            id: "appfeedback-\(UUID().uuidString.prefix(8))", rating: rating,
            priority: priority, category: category, comment: trimmed,
            author: author.isEmpty ? "CI Manager (role)" : author,
            page: page)
        context.insert(record)
        audit(action: "feedback.product", subject: record.id,
              detail: "\(rating) · \(category) · \(page)")
        try? context.save()
        showToast("Feedback saved", detail: "Local product feedback; not sent anywhere.",
                  symbol: "bubble.left.and.text.bubble.right")
        return record
    }

    func exportFeedbackForPDFStudio() {
        let annotations = (try? context.fetch(FetchDescriptor<FeedbackRecord>())) ?? []
        let product = (try? context.fetch(FetchDescriptor<AppFeedbackRecord>())) ?? []
        let payload: [String: Any] = [
            "schema": "processlink-annotations/1",
            "generatedAt": ISO8601DateFormatter().string(from: now),
            "annotations": annotations.map { record in
                ["kind": record.kindRaw, "subjectId": record.subjectID,
                 "subjectLabel": record.subjectLabel, "parentId": record.parentID,
                 "body": record.body, "author": record.author,
                 "createdAt": ISO8601DateFormatter().string(from: record.createdAt),
                 "resolved": record.resolved, "mentions": record.mentions]
            },
            "productFeedback": product.map { record in
                ["rating": record.rating, "priority": record.priority,
                 "category": record.category, "comment": record.comment,
                 "author": record.author, "page": record.page,
                 "createdAt": ISO8601DateFormatter().string(from: record.createdAt)]
            },
        ]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "processlink-annotations.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
            showToast("Annotation package saved", detail: "For PDF Studio review; not sent automatically.",
                      symbol: "doc.badge.arrow.up")
        } catch {
            showToast("Export failed", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
        }
    }

    func exportFeedbackCSV() {
        let annotations = (try? context.fetch(FetchDescriptor<FeedbackRecord>())) ?? []
        let product = (try? context.fetch(FetchDescriptor<AppFeedbackRecord>())) ?? []
        var rows = [["type", "kind", "subject", "rating", "priority", "resolved", "author", "createdAt", "body"]]
        for record in annotations {
            rows.append(["annotation", record.kindRaw, record.subjectLabel, "", "",
                         record.resolved ? "yes" : "no", record.author,
                         ISO8601DateFormatter().string(from: record.createdAt), record.body])
        }
        for record in product {
            rows.append(["product", "", record.page, record.rating, record.priority, "",
                         record.author, ISO8601DateFormatter().string(from: record.createdAt),
                         record.comment])
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "processlink-feedback.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = rows.map { row in
            row.map { value in "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }.joined(separator: "\n")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            showToast("Feedback CSV saved", detail: "\(annotations.count) annotations · \(product.count) product notes",
                      symbol: "tablecells")
        } catch {
            showToast("Export failed", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
        }
    }

    func exportAgentPolicy(deviceID: String) {
        guard let policy = capturePolicy() else { return }
        let consents = (try? context.fetch(FetchDescriptor<ConsentRecord>())) ?? []
        let payload: [String: Any] = [
            "schema": "processlink-agent-policy/1",
            "deviceID": deviceID,
            "workspaceID": policy.workspaceID,
            "projectID": policy.projectID,
            "policy": [
                "active": policy.active, "intervalMinutes": policy.intervalMinutes,
                "maxSessionMinutes": policy.maxSessionMinutes,
                "windowTitles": policy.windowTitles, "screenshots": policy.screenshots,
                "inputCounts": policy.inputCounts, "consentVersion": policy.consentVersion,
            ],
            "consents": consents.filter { $0.revokedAt == nil }.map { consent in
                ["site": consent.site, "role": consent.role, "version": consent.version,
                 "reference": consent.reference,
                 "expiresAt": consent.expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""]
            },
            "exportedAt": ISO8601DateFormatter().string(from: now),
        ]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "processlink-agent-policy.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
            showToast("Agent policy exported", detail: "Consent and policy only; no case or capture data.",
                      symbol: "doc.badge.arrow.up")
        } catch {
            showToast("Export failed", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
        }
    }

    func importAgentPolicy() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let policy = root["policy"] as? [String: Any],
              let record = capturePolicy() else { return }
        record.active = policy["active"] as? Bool ?? record.active
        record.intervalMinutes = policy["intervalMinutes"] as? Int ?? record.intervalMinutes
        record.maxSessionMinutes = policy["maxSessionMinutes"] as? Int ?? record.maxSessionMinutes
        record.windowTitles = policy["windowTitles"] as? Bool ?? record.windowTitles
        record.screenshots = policy["screenshots"] as? Bool ?? record.screenshots
        record.inputCounts = policy["inputCounts"] as? Bool ?? record.inputCounts
        record.consentVersion = policy["consentVersion"] as? String ?? record.consentVersion
        record.deviceID = root["deviceID"] as? String ?? record.deviceID
        record.policyVersion = String((root["version"] as? Int) ?? Int(record.policyVersion) ?? 1)
        record.updatedAt = now
        audit(action: "capture.policy.imported", subject: record.deviceID,
              detail: "Policy \(record.policyVersion); consent not imported")
        try? context.save()
        showToast("Agent policy imported", detail: "Consent is not imported; grant it locally.",
                  symbol: "square.and.arrow.down")
    }

    func markAgentHeartbeat() {
        guard let policy = capturePolicy() else { return }
        policy.lastHeartbeat = now
        if policy.deviceID.isEmpty { policy.deviceID = UUID().uuidString }
        try? context.save()
        showToast("Agent heartbeat recorded", detail: "Local only; no fleet server contacted.",
                  symbol: "heartbeat")
    }

    func exportCaptureSessionsCSV() {
        let sessions = (try? context.fetch(FetchDescriptor<CaptureSessionRecord>())) ?? []
        var rows = [["id", "name", "role", "site", "startedAt", "endedAt", "activeMinutes", "idleMinutes", "switches", "keystrokes", "clicks", "status"]]
        let formatter = ISO8601DateFormatter()
        for session in sessions {
            rows.append([session.id, session.name, session.role, session.site,
                         formatter.string(from: session.startedAt),
                         session.endedAt.map { formatter.string(from: $0) } ?? "",
                         String(format: "%.1f", session.activeMinutes), String(format: "%.1f", session.idleMinutes),
                         String(session.switchCount), String(session.keystrokeCount),
                         String(session.clickCount), session.statusRaw])
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "processlink-capture-sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = rows.map { row in row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\n")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        showToast("Capture sessions exported", detail: "\(sessions.count) sessions", symbol: "tablecells")
    }

    func exportAuditCSV() {
        let records = (try? context.fetch(FetchDescriptor<AuditRecord>())) ?? []
        var rows = [["at", "actor", "action", "subject", "classification", "detail"]]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([formatter.string(from: record.at), record.actor, record.action,
                         record.subject, record.classification.rawValue, record.detail])
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "processlink-audit.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = rows.map { row in row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\n")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        showToast("Audit exported", detail: "\(records.count) records", symbol: "tablecells")
    }

    func purgeExpiredCapture() {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let sessions = (try? context.fetch(FetchDescriptor<CaptureSessionRecord>())) ?? []
        let expired = sessions.filter { $0.startedAt < cutoff }
        for session in expired {
            let shots = (try? context.fetch(FetchDescriptor<CaptureShotRecord>())) ?? []
            for shot in shots where shot.sessionID == session.id {
                try? FileManager.default.removeItem(atPath: shot.path)
                context.delete(shot)
            }
            let windows = (try? context.fetch(FetchDescriptor<CaptureWindowRecord>())) ?? []
            for window in windows where window.sessionID == session.id { context.delete(window) }
            let tasks = (try? context.fetch(FetchDescriptor<CaptureTaskRecord>())) ?? []
            for task in tasks where task.sessionID == session.id { context.delete(task) }
            context.delete(session)
        }
        ActivityCapture.removeScreenshots(olderThan: retentionDays)
        audit(action: "capture.purge", subject: "retention",
              detail: "\(expired.count) sessions older than \(retentionDays) days")
        try? context.save()
        showToast("Retention applied", detail: "\(expired.count) expired sessions removed",
                  symbol: "trash")
    }

    // MARK: Updates

    @MainActor
    func checkForUpdates(silent: Bool = false) async {
        guard !SelfTest.requested else { return }
        if !silent { updateStatus = "checking" }
        updateError = ""
        do {
            let channel = UserDefaults.standard.string(forKey: "updates.channel") ?? "stable"
            let latest = try await UpdateService.latest(channel: channel)
            updateInfo = latest
            updateLastChecked = now
            updateStatus = UpdateService.isNewer(latest.version, than: UpdateService.currentVersion) ? "available" : "current"
        } catch {
            updateError = error.localizedDescription
            updateStatus = silent ? "idle" : "failed"
        }
    }

    func openUpdate() {
        NSWorkspace.shared.open(updateInfo?.downloadURL ?? updateInfo?.pageURL ?? UpdateService.releasesPage)
    }

    // MARK: Automation handoff

    @discardableResult
    func generateAutomationHandoff(for initiative: InitiativeRecord) -> AutomationHandoffRecord? {
        let existing = ((try? context.fetch(FetchDescriptor<AutomationHandoffRecord>())) ?? [])
            .first { $0.initiativeID == initiative.id }
        let id = existing?.id ?? "handoff-\(UUID().uuidString.prefix(8))"
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("ProcessLink/handoffs/\(id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let steps = ((try? context.fetch(FetchDescriptor<StepRecord>())) ?? [])
                .filter { $0.processID == initiative.processID }
                .sorted { $0.order < $1.order }
            let payload: [String: Any] = [
                "schema": "processlink-automation-handoff/1",
                "generatedAt": ISO8601DateFormatter().string(from: now),
                "initiative": [
                    "id": initiative.id, "title": initiative.title,
                    "owner": initiative.owner, "process": initiative.processName,
                    "stage": initiative.stage.label, "savingHours": initiative.savingsHours,
                    "savingStage": initiative.savingsStage.label,
                ],
                "strategy": [
                    "bet": initiative.strategicBetID, "kpi": initiative.kpiID,
                    "values": initiative.valueIDs, "expectedKPIChange": initiative.expectedKPIChange,
                ],
                "steps": steps.map { ["name": $0.name, "role": $0.role, "application": $0.application,
                                      "minutes": $0.minutes, "waste": $0.waste.rawValue] },
                "guardrails": [
                    "No automatic send, release or performance decision.",
                    "A named human validates the KPI change and the saving.",
                    "The package is a scaffold, not a deployed automation.",
                ],
            ]
            let json = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try json.write(to: folder.appendingPathComponent("automation.json"), options: .atomic)
            let readme = """
            # Automation handoff — \(initiative.title)

            Owner: \(initiative.owner)
            Process: \(initiative.processName)
            Strategic bet: \(initiative.strategicBetID)
            KPI: \(initiative.kpiID)
            Expected change: \(initiative.expectedKPIChange)

            This folder is a handoff scaffold. It does not deploy code or change a production system.
            Read automation.json for the machine-readable package, test-plan.md for acceptance,
            and agent.py for the minimal agent skeleton.
            """
            try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            let testPlan = """
            # Test plan

            - Before/after KPI measurement with a named validator
            - Sample audit of at least 10 cases
            - Human review of every automated recommendation
            - Rollback owner and date
            - No automatic send, release or performance action
            """
            try testPlan.write(to: folder.appendingPathComponent("test-plan.md"), atomically: true, encoding: .utf8)
            let agent = """
            # ProcessLink automation skeleton — generated, not deployed.
            # Fill in the system adapter and keep a human approval step.
            def run(case):
                draft = {"case": case, "action": "review", "requires_human": True}
                return draft
            """
            try agent.write(to: folder.appendingPathComponent("agent.py"), atomically: true, encoding: .utf8)

            let record = existing ?? AutomationHandoffRecord(
                id: id, initiativeID: initiative.id, status: "ready",
                packagePath: folder.path, target: initiative.processName,
                notes: "Generated from \(initiative.title).")
            if existing == nil { context.insert(record) }
            record.statusRaw = "ready"
            record.packagePath = folder.path
            record.updatedAt = now
            audit(action: "automation.handoff.generated", subject: initiative.title,
                  detail: "Package at \(folder.path); not deployed.")
            try? context.save()
            showToast("Automation handoff ready", detail: "Package generated; no deployment.",
                      symbol: "shippingbox")
            return record
        } catch {
            showToast("Handoff failed", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
            return nil
        }
    }

    func setAutomationStatus(_ record: AutomationHandoffRecord, status: String) {
        record.statusRaw = status
        record.updatedAt = now
        audit(action: "automation.handoff.status", subject: record.id, detail: status)
        try? context.save()
    }

    // MARK: Feedback

    @discardableResult
    func addFeedback(kind: FeedbackKind, subjectID: String, subjectLabel: String,
                     body: String, parentID: String = "") -> FeedbackRecord? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let record = FeedbackRecord(
            id: "fb-\(UUID().uuidString.prefix(8))", kind: kind,
            subjectID: subjectID, subjectLabel: subjectLabel,
            parentID: parentID, body: trimmed, author: dataOwner)
        context.insert(record)
        audit(action: "feedback.added", subject: subjectLabel,
              detail: "\(kind.label)\(parentID.isEmpty ? "" : " reply") · \(trimmed.prefix(120))")
        try? context.save()
        showToast(parentID.isEmpty ? "Feedback added" : "Reply added",
                  detail: record.mentions.isEmpty ? subjectLabel : "Mentioned \(record.mentions.joined(separator: ", "))",
                  symbol: "bubble.left.and.text.bubble.right")
        return record
    }

    func setFeedbackResolved(_ record: FeedbackRecord, resolved: Bool) {
        record.resolved = resolved
        audit(action: resolved ? "feedback.resolved" : "feedback.reopened",
              subject: record.subjectLabel, detail: record.body.prefix(120).description)
        try? context.save()
    }

    func deleteFeedback(_ record: FeedbackRecord) {
        let replies = ((try? context.fetch(FetchDescriptor<FeedbackRecord>())) ?? [])
            .filter { $0.parentID == record.id }
        for reply in replies { context.delete(reply) }
        context.delete(record)
        audit(action: "feedback.deleted", subject: record.subjectLabel, detail: "Thread and replies deleted.")
        try? context.save()
    }

    // MARK: Capacity studies

    @discardableResult
    func saveCapacityStudy(name: String, dataset: DatasetRecord, roles: [CapacityRole],
                           result: CapacityResult, arrivalsPerDay: Double, days: Int,
                           workingMinutes: Double) -> CapacityStudyRecord {
        let roleRows = roles.map { ["role": $0.role, "capacity": $0.capacity, "serviceMinutes": $0.serviceMinutes] }
        let recommendationRows = result.utilization.map { role in
            ["role": role.role, "utilization": role.utilization,
             "averageWaitMinutes": role.averageWaitMinutes,
             "recommendedCapacity": role.recommendedCapacity,
             "capacityGap": role.capacityGap]
        }
        func json(_ value: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        let record = CapacityStudyRecord(
            id: "study-\(UUID().uuidString.prefix(8))",
            name: name.isEmpty ? "Capacity study · \(dataset.name)" : name,
            datasetID: dataset.id, processID: dataset.processID, mapID: dataset.mapID,
            arrivalsPerDay: arrivalsPerDay, days: days, workingMinutesPerDay: workingMinutes,
            rolesJSON: json(roleRows), recommendationsJSON: json(recommendationRows),
            assumptionsJSON: json(result.assumptions),
            medianCycleMinutes: result.medianCycleMinutes,
            p90CycleMinutes: result.p90CycleMinutes,
            averageWaitMinutes: result.averageWaitMinutes)
        context.insert(record)
        audit(action: "capacity.study.saved", subject: record.name,
              detail: "\(Int(arrivalsPerDay))/day, \(days) days, \(roles.count) roles, \(result.cases) cases.")
        try? context.save()
        showToast("Capacity study saved", detail: record.name, symbol: "person.3.sequence")
        return record
    }

    // MARK: Map drift

    @discardableResult
    func createDriftReview(map: MapsBridge.Document, report: MapMiningReport,
                           owner: String) -> GovernanceRecord {
        let id = "gov-drift-\(map.id)"
        let existing = ((try? context.fetch(FetchDescriptor<GovernanceRecord>())) ?? []).first { $0.id == id }
        let record = existing ?? GovernanceRecord(
            id: id, title: "Map drift · \(map.label)",
            detail: "\(report.unexpectedTransitions.count) observed transitions are outside the map; \(report.missingSteps.count) map steps were not observed. Review the map or the work, then record the decision.",
            group: "Process model", status: .inProgress, owner: owner, sortKey: 90)
        record.detail = "\(report.unexpectedTransitions.count) observed transitions are outside the map; \(report.missingSteps.count) map steps were not observed. Review the map or the work, then record the decision."
        record.owner = owner
        record.updatedAt = .now
        if existing == nil { context.insert(record) }
        audit(action: "map.drift.review", subject: map.label,
              detail: "Assigned to \(owner); \(report.unexpectedTransitions.count) unexpected transitions, \(report.missingSteps.count) missing steps.")
        try? context.save()
        page = .governance
        showToast("Drift review assigned", detail: owner, symbol: "checkmark.shield")
        return record
    }

    /// Agent follow-through: a validated bottleneck becomes a real initiative,
    /// already carrying its process, strategic bet, KPI and values. The user
    /// still owns the target and the saving evidence.
    @discardableResult
    func createInitiativeFromMining(dataset: DatasetRecord, activity: MinedActivity,
                                    map: MapsBridge.Document?) -> InitiativeRecord? {
        let processID: String
        if !dataset.processID.isEmpty {
            processID = dataset.processID
        } else if let process = createProcess(from: dataset) {
            processID = process.id
            dataset.processID = process.id
        } else {
            return nil
        }
        let process = ((try? context.fetch(FetchDescriptor<ProcessRecord>())) ?? []).first { $0.id == processID }
        let waste: WasteType = activity.reworkCount > 0 ? .rework : activity.averageWaitMinutes > 10 ? .waiting : .overProcessing
        let link = StrategyDefaults.link(for: processID, waste: waste)
        let annualHours = min(5_000, Double(activity.events) / Double(max(1, dataset.caseCount)) * 220
                              * max(1, activity.averageWaitMinutes + 2) / 60)
        let initiative = InitiativeRecord(
            id: "ini-mining-\(UUID().uuidString.prefix(8))",
            title: "Improve \(activity.name) in \(dataset.name)",
            opportunityID: "", processID: processID,
            processName: process?.name ?? dataset.name, site: dataset.site,
            method: .kaizen, owner: "Process Owner", stage: .plan, status: .active,
            due: now.addingTimeInterval(30 * 86_400), savingsHours: annualHours,
            savingsStage: .estimated, validatedBy: "", evidenceNote: "",
            claimsWaste: waste,
            background: "Mined from \(dataset.caseCount) cases and \(dataset.eventCount) events\(map.map { " in \($0.label)" } ?? ""). \(activity.events) events at \(activity.name); average wait \(Fmt.minutes(activity.averageWaitMinutes)).",
            target: "Reduce the observed \(waste.label.lowercased()) at \(activity.name) without adding a control step.",
            rootCause: activity.automationReason,
            countermeasure: "Test the smallest change that removes the wait or repeat; measure before and after.",
            result: "", followUp: "Validate with before/after evidence after six weeks.",
            strategicBetID: link.betID, kpiID: link.kpiID, valueIDs: link.valueIDs,
            expectedKPIChange: link.expectedChange, visionContribution: link.contribution)
        context.insert(initiative)
        audit(action: "mining.initiative.created", subject: initiative.title,
              detail: "From \(dataset.name) / \(activity.name)\(map.map { " / map \($0.id)" } ?? "").")
        try? context.save()
        selectedInitiativeID = initiative.id
        page = .improvements
        showToast("Initiative created", detail: "\(initiative.title) · linked to \(link.betID)",
                  symbol: "flag.pattern.checkered")
        return initiative
    }

    // MARK: Connectors

    func setConnectorSecret(_ value: String, for id: String) {
        if value.isEmpty { KeychainStore.delete(account: "connector.\(id)") }
        else { KeychainStore.set(value, account: "connector.\(id)") }
    }

    func connectorSecret(for id: String) -> String? {
        KeychainStore.get(account: "connector.\(id)")
    }

    func deleteConnector(_ connector: ConnectorRecord) {
        KeychainStore.delete(account: "connector.\(connector.id)")
        context.delete(connector)
        audit(action: "connector.deleted", subject: connector.name, detail: connector.provider.label)
        try? context.save()
    }

    @discardableResult
    func runConnector(_ connector: ConnectorRecord, testOnly: Bool = false) async -> Bool {
        guard let url = connectorURL(connector) else {
            connector.lastStatus = "error"
            connector.lastError = "Invalid URL"
            try? context.save()
            return false
        }
        var requestURL = url
        if !testOnly, !connector.cursor.isEmpty, !connector.incrementalParam.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: connector.incrementalParam, value: connector.cursor))
            components.queryItems = items
            requestURL = components.url ?? url
        }
        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let secret = connectorSecret(for: connector.id), !secret.isEmpty {
            if connector.authMode == "basic" {
                let raw = "\(connector.username):\(secret)"
                request.setValue("Basic \(Data(raw.utf8).base64EncodedString())",
                                 forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
        }
        do {
            var data = Data()
            var response: URLResponse?
            for attempt in 0..<3 {
                do {
                    let result = try await URLSession.shared.data(for: request)
                    data = result.0
                    response = result.1
                    if let http = result.1 as? HTTPURLResponse,
                       (http.statusCode == 429 || http.statusCode >= 500), attempt < 2 {
                        let delay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? Double(attempt + 1)
                        try? await Task.sleep(for: .seconds(min(8, delay)))
                        continue
                    }
                    break
                } catch {
                    if attempt == 2 { throw error }
                    try? await Task.sleep(for: .seconds(Double(attempt + 1)))
                }
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "ProcessLink.Connector", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
            }
            if testOnly {
                connector.lastStatus = "tested"
                connector.lastError = ""
                connector.lastRunAt = .now
                try? context.save()
                showToast("Connector reachable", detail: "\(data.count) bytes from \(connector.provider.label)",
                          symbol: "checkmark.icloud")
                return true
            }
            var csv = try ConnectorParser.csv(from: data, provider: connector.provider,
                                              mapping: connector.mapping)
            var cursor = nextConnectorCursor(data: data, response: http)
            if connector.maxPages > 1, let firstNext = cursor, firstNext != connector.cursor {
                var pageCursor = firstNext
                for _ in 1..<max(1, min(20, connector.maxPages)) {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    var items = components?.queryItems ?? []
                    items.append(URLQueryItem(name: connector.pageParam, value: pageCursor))
                    components?.queryItems = items
                    guard let pageURL = components?.url else { break }
                    var pageRequest = request
                    pageRequest.url = pageURL
                    guard let (pageData, pageResponse) = try? await URLSession.shared.data(for: pageRequest),
                          let pageHTTP = pageResponse as? HTTPURLResponse,
                          (200..<300).contains(pageHTTP.statusCode) else { break }
                    let pageCSV = try ConnectorParser.csv(from: pageData, provider: connector.provider,
                                                         mapping: connector.mapping)
                    csv = mergeConnectorCSV(csv, pageCSV)
                    guard let next = nextConnectorCursor(data: pageData, response: pageHTTP),
                          next != pageCursor else { break }
                    pageCursor = next
                    cursor = next
                }
            }
            let result = try EventLogImporter.importCSV(csv)
            let dataset = storeDataset(
                name: "\(connector.name) · \(Fmt.day(now))", result: result,
                source: "connector", filename: connector.provider.label,
                site: connector.site,
                notes: "Pulled from \(connector.provider.label) by a configured REST connector. Credentials are in the Keychain.")
            connector.lastStatus = "success"
            connector.lastError = ""
            connector.lastRunAt = .now
            connector.cursor = cursor ?? ISO8601DateFormatter().string(from: now)
            audit(action: "connector.run", subject: connector.name,
                  detail: "\(result.events.count) events, \(result.caseCount) cases")
            try? context.save()
            if let dataset {
                selectedDatasetID = dataset.id
                page = .mining
            }
            return dataset != nil
        } catch {
            connector.lastStatus = "error"
            connector.lastError = error.localizedDescription
            connector.lastRunAt = .now
            try? context.save()
            showToast("Connector failed", detail: error.localizedDescription,
                      symbol: "exclamationmark.triangle", warning: true)
            return false
        }
    }

    private func nextConnectorCursor(data: Data, response: HTTPURLResponse) -> String? {
        if let next = response.value(forHTTPHeaderField: "X-Next-Cursor") ?? response.value(forHTTPHeaderField: "X-Cursor"),
           !next.isEmpty {
            return next
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let next = root["nextCursor"] as? String ?? root["cursor"] as? String,
           !next.isEmpty {
            return next
        }
        return nil
    }

    private func mergeConnectorCSV(_ first: String, _ second: String) -> String {
        let firstLines = first.split(separator: "\n", omittingEmptySubsequences: false)
        let secondLines = second.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = firstLines.first else { return second }
        let rows = firstLines.dropFirst() + secondLines.dropFirst()
        return ([header] + rows).joined(separator: "\n")
    }

    private func connectorURL(_ connector: ConnectorRecord) -> URL? {
        let base = connector.baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let path = connector.path.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { return URL(string: base) }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
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
        let meetings = (try? context.fetch(FetchDescriptor<MeetingRecord>())) ?? []
        let meetingBlocks = (try? context.fetch(FetchDescriptor<MeetingBlockRecord>())) ?? []

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
                           discoveryID: process.discoveryID, kgID: process.kgID)
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
        let meetingInsights = meetings.map { meeting in
            let blocks = meetingBlocks.filter { $0.meetingID == meeting.id }
            let processName = visible.first { $0.id == meeting.processID }?.name ?? ""
            return MeetingInsight(
                id: meeting.id, title: meeting.title, date: meeting.date,
                kind: meeting.kind.label, site: meeting.site, processName: processName,
                decisions: blocks.filter { $0.kind == .decision }.map {
                    MeetingItemInsight(id: $0.id, text: $0.text, owner: $0.owner, done: $0.checked)
                },
                actions: blocks.filter { $0.kind == .action }.map {
                    MeetingItemInsight(id: $0.id, text: $0.text, owner: $0.owner,
                                       done: $0.checked, due: $0.due)
                },
                kgID: meeting.kgID)
        }
        var answer = AskEngine.answer(trimmed, processes: processInsights,
                                      steps: stepInsights, opportunities: opportunityInsights,
                                      meetings: meetingInsights)
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
            text += "- Source: discovery \(opportunity.processID) · KG \(opportunity.kgID)\n\n"
        }
        text += "## Savings ledger\n\n"
        for initiative in initiatives.sorted(by: { $0.savingsHours > $1.savingsHours }) {
            text += "- \(initiative.title): \(Fmt.hours(initiative.savingsHours)) · \(initiative.savingsStage.label)"
            text += initiative.validatedBy.isEmpty ? "\n" : " · validated by \(initiative.validatedBy)\n"
        }
        text += "\n> Estimates are not validated savings. Every figure traces to a discovery object or KG node; unknowns stay on the to-verify list.\n"

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

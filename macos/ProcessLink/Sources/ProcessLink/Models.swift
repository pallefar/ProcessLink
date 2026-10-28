import Foundation
import ProcessLinkKit
import SwiftData

// MARK: - Discovery

/// One discovered process. Aggregated only: no person, no
/// screenshot, no keystroke, no free text from a case.
@Model
final class ProcessRecord {
    var id: String = ""
    var name: String = ""
    var site: String = ""
    var businessUnit: String = ""
    var valueStream: String = ""
    var ownerRole: String = ""
    var discoveryID: String = ""
    var kgID: String = ""
    var summary: String = ""
    var applications: [String] = []
    var variantNames: [String] = []

    var capturedFrom: Date = Date.now
    var capturedTo: Date = Date.now
    var lastSynced: Date = Date.now

    var confidence: Double = 0.8
    var people: Int = 12
    var annualHours: Double = 0
    var cycleMinutes: Double = 0
    var reworkRate: Double = 0
    var handoffs: Int = 0
    var variantCount: Int = 1
    /// 0 ... 1 against the documented standard work.
    var adherence: Double = 0.7
    var maturity: Int = 2

    var classificationRaw: String = DataClass.internalUse.rawValue
    /// "discovered", "suppressed" or "blocked".
    var statusRaw: String = ProcessStatus.discovered.rawValue
    var statusReason: String = ""
    var standardDocument: String = ""
    var standardVersion: String = ""
    /// "ProcessLink task mining", "In-house process mining", "In-house task capture".
    var sourceRaw: String = "ProcessLink discovery"

    init(id: String, name: String, site: String, businessUnit: String, valueStream: String,
         ownerRole: String, discoveryID: String, kgID: String, summary: String,
         applications: [String], variantNames: [String], capturedFrom: Date, capturedTo: Date,
         lastSynced: Date, confidence: Double, people: Int, annualHours: Double,
         cycleMinutes: Double, reworkRate: Double, handoffs: Int, variantCount: Int,
         adherence: Double, maturity: Int, classification: DataClass,
         status: ProcessStatus, statusReason: String, standardDocument: String,
         standardVersion: String, source: String = "ProcessLink discovery") {
        self.id = id
        self.name = name
        self.site = site
        self.businessUnit = businessUnit
        self.valueStream = valueStream
        self.ownerRole = ownerRole
        self.discoveryID = discoveryID
        self.kgID = kgID
        self.summary = summary
        self.applications = applications
        self.variantNames = variantNames
        self.capturedFrom = capturedFrom
        self.capturedTo = capturedTo
        self.lastSynced = lastSynced
        self.confidence = confidence
        self.people = people
        self.annualHours = annualHours
        self.cycleMinutes = cycleMinutes
        self.reworkRate = reworkRate
        self.handoffs = handoffs
        self.variantCount = variantCount
        self.adherence = adherence
        self.maturity = maturity
        self.classificationRaw = classification.rawValue
        self.statusRaw = status.rawValue
        self.statusReason = statusReason
        self.standardDocument = standardDocument
        self.standardVersion = standardVersion
        self.sourceRaw = source
    }

    var classification: DataClass { DataClass(rawValue: classificationRaw) ?? .internalUse }
    var status: ProcessStatus { ProcessStatus(rawValue: statusRaw) ?? .discovered }
    var source: String { sourceRaw }
    var provenance: Provenance {
        Provenance(source: sourceRaw, sourceID: discoveryID,
                   capturedFrom: capturedFrom, capturedTo: capturedTo,
                   confidence: confidence, syncedAt: lastSynced)
    }
    var isStale: Bool { Drift.isStale(lastSynced: lastSynced) }
    var staleDays: Int { Drift.days(since: lastSynced) }
}

enum ProcessStatus: String, CaseIterable {
    case discovered
    case suppressed
    case blocked

    var label: String {
        switch self {
        case .discovered: "Discovered"
        case .suppressed: "Suppressed"
        case .blocked: "Blocked"
        }
    }

    /// Ordering for a list: workable records first, refusals last.
    var rank: Int {
        switch self {
        case .discovered: 0
        case .suppressed: 1
        case .blocked: 2
        }
    }
}

/// One mined step, with the role and application as discovery classified them.
@Model
final class StepRecord {
    var id: String = ""
    var processID: String = ""
    var order: Int = 0
    var name: String = ""
    var role: String = ""
    var application: String = ""
    var minutes: Double = 0
    var handoffs: Int = 0
    var reworkShare: Double = 0
    var wasteRaw: String = WasteType.waiting.rawValue
    var evidenceCount: Int = 0
    var kgID: String = ""
    var standardAligned: Bool = true

    init(id: String, processID: String, order: Int, name: String, role: String,
         application: String, minutes: Double, handoffs: Int, reworkShare: Double,
         waste: WasteType, evidenceCount: Int, kgID: String, standardAligned: Bool) {
        self.id = id
        self.processID = processID
        self.order = order
        self.name = name
        self.role = role
        self.application = application
        self.minutes = minutes
        self.handoffs = handoffs
        self.reworkShare = reworkShare
        self.wasteRaw = waste.rawValue
        self.evidenceCount = evidenceCount
        self.kgID = kgID
        self.standardAligned = standardAligned
    }

    var waste: WasteType { WasteType(rawValue: wasteRaw) ?? .waiting }

    var insight: (ProcessRecord) -> StepInsight {
        { process in
            StepInsight(id: self.id, processID: self.processID, processName: process.name,
                        site: process.site, name: self.name, role: self.role,
                        application: self.application, minutes: self.minutes,
                        handoffs: self.handoffs, reworkShare: self.reworkShare,
                        waste: self.waste, evidenceCount: self.evidenceCount, kgID: self.kgID)
        }
    }
}

/// One mined variant of a process.
@Model
final class VariantRecord {
    var id: String = ""
    var processID: String = ""
    var name: String = ""
    var share: Double = 0
    var cycleMinutes: Double = 0
    var reworkRate: Double = 0
    var path: String = ""

    init(id: String, processID: String, name: String, share: Double,
         cycleMinutes: Double, reworkRate: Double, path: String) {
        self.id = id
        self.processID = processID
        self.name = name
        self.share = share
        self.cycleMinutes = cycleMinutes
        self.reworkRate = reworkRate
        self.path = path
    }
}

// MARK: - Opportunity

@Model
final class OpportunityRecord {
    var id: String = ""
    var title: String = ""
    var processID: String = ""
    var processName: String = ""
    var site: String = ""
    var wasteRaw: String = WasteType.waiting.rawValue
    var methodRaw: String = TEOMethod.kaizen.rawValue
    var routeRaw: String = Route.simplify.rawValue
    var statusRaw: String = OpportunityStatus.new.rawValue
    var rationale: String = ""
    var kgID: String = ""
    var ownerRole: String = ""

    var annualHours: Double = 0
    var errorReductionPct: Double = 0
    var effortWeeks: Double = 4
    var risk: Int = 2
    var alignment: Int = 3
    var automation: Double = 0.3
    var confidence: Double = 0.8
    var statutory: Bool = false

    var createdAt: Date = Date.now
    var promotedAt: Date?

    init(id: String, title: String, processID: String, processName: String, site: String,
         waste: WasteType, method: TEOMethod, route: Route, annualHours: Double,
         errorReductionPct: Double, effortWeeks: Double, risk: Int, alignment: Int,
         automation: Double, confidence: Double, statutory: Bool, rationale: String,
         kgID: String, ownerRole: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.processID = processID
        self.processName = processName
        self.site = site
        self.wasteRaw = waste.rawValue
        self.methodRaw = method.rawValue
        self.routeRaw = route.rawValue
        self.annualHours = annualHours
        self.errorReductionPct = errorReductionPct
        self.effortWeeks = effortWeeks
        self.risk = risk
        self.alignment = alignment
        self.automation = automation
        self.confidence = confidence
        self.statutory = statutory
        self.rationale = rationale
        self.kgID = kgID
        self.ownerRole = ownerRole
        self.createdAt = createdAt
    }

    var waste: WasteType { WasteType(rawValue: wasteRaw) ?? .waiting }
    var method: TEOMethod { TEOMethod(rawValue: methodRaw) ?? .kaizen }
    var route: Route { Route(rawValue: routeRaw) ?? .simplify }
    var status: OpportunityStatus { OpportunityStatus(rawValue: statusRaw) ?? .new }

    var inputs: OpportunityInputs {
        OpportunityInputs(annualHours: annualHours, errorReductionPct: errorReductionPct,
                          effortWeeks: effortWeeks, risk: risk, alignment: alignment,
                          automationSuitability: automation, confidence: confidence,
                          statutory: statutory, waste: waste)
    }
    var score: OpportunityScore { OpportunityScoring.score(inputs) }
}

enum OpportunityStatus: String, CaseIterable {
    case new
    case qualified
    case promoted
    case deferred

    var label: String {
        switch self {
        case .new: "New"
        case .qualified: "Qualified"
        case .promoted: "In an initiative"
        case .deferred: "Deferred"
        }
    }
}

// MARK: - Initiative

@Model
final class InitiativeRecord {
    var id: String = ""
    var title: String = ""
    var opportunityID: String = ""
    var processID: String = ""
    var processName: String = ""
    var site: String = ""
    var methodRaw: String = TEOMethod.kaizen.rawValue
    var owner: String = ""
    /// plan, do, check, act
    var stageRaw: String = CycleStage.plan.rawValue
    var statusRaw: String = InitiativeStatus.active.rawValue
    var due: Date = Date.now
    var createdAt: Date = Date.now

    var savingsHours: Double = 0
    var savingsStageRaw: String = SavingsStage.estimated.rawValue
    var validatedBy: String = ""
    var evidenceNote: String = ""
    var claimsWasteRaw: String = WasteType.waiting.rawValue

    // A3 one-page content.
    var background: String = ""
    var target: String = ""
    var rootCause: String = ""
    var countermeasure: String = ""
    var result: String = ""
    var followUp: String = ""

    init(id: String, title: String, opportunityID: String, processID: String, processName: String,
         site: String, method: TEOMethod, owner: String, stage: CycleStage,
         status: InitiativeStatus, due: Date, savingsHours: Double, savingsStage: SavingsStage,
         validatedBy: String, evidenceNote: String, claimsWaste: WasteType,
         background: String, target: String, rootCause: String, countermeasure: String,
         result: String, followUp: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.opportunityID = opportunityID
        self.processID = processID
        self.processName = processName
        self.site = site
        self.methodRaw = method.rawValue
        self.owner = owner
        self.stageRaw = stage.rawValue
        self.statusRaw = status.rawValue
        self.due = due
        self.savingsHours = savingsHours
        self.savingsStageRaw = savingsStage.rawValue
        self.validatedBy = validatedBy
        self.evidenceNote = evidenceNote
        self.claimsWasteRaw = claimsWaste.rawValue
        self.background = background
        self.target = target
        self.rootCause = rootCause
        self.countermeasure = countermeasure
        self.result = result
        self.followUp = followUp
        self.createdAt = createdAt
    }

    var method: TEOMethod { TEOMethod(rawValue: methodRaw) ?? .kaizen }
    var stage: CycleStage { CycleStage(rawValue: stageRaw) ?? .plan }
    var status: InitiativeStatus { InitiativeStatus(rawValue: statusRaw) ?? .active }
    var savingsStage: SavingsStage { SavingsStage(rawValue: savingsStageRaw) ?? .estimated }
    var claimsWaste: WasteType { WasteType(rawValue: claimsWasteRaw) ?? .waiting }
}

/// Computed projections live outside the @Model body: the SwiftData macro
/// rewrites the class and does not carry every computed member through.
extension InitiativeRecord {
    var savingLine: SavingsLine {
        SavingsLine(id: id, initiativeID: id, initiativeTitle: title, processID: processID,
                    waste: claimsWaste, stage: savingsStage, hours: savingsHours,
                    validatedBy: validatedBy.isEmpty ? nil : validatedBy, note: evidenceNote)
    }
}

/// The A3/PDCA cycle stages the board already uses.
enum CycleStage: String, CaseIterable {
    case plan, `do`, check, act

    var label: String {
        switch self {
        case .plan: "Plan"
        case .do: "Do"
        case .check: "Check"
        case .act: "Act"
        }
    }

    var next: CycleStage {
        switch self {
        case .plan: .do
        case .do: .check
        case .check: .act
        case .act: .act
        }
    }
}

enum InitiativeStatus: String, CaseIterable {
    case active, onHold, complete

    var label: String {
        switch self {
        case .active: "Active"
        case .onHold: "On hold"
        case .complete: "Complete"
        }
    }
}

// MARK: - Knowledge graph

@Model
final class KGNodeRecord {
    var id: String = ""
    var kindRaw: String = KGKind.process.rawValue
    var name: String = ""
    var confidence: Double = 0.9
    /// confirmed, suggested, rejected
    var reviewRaw: String = ReviewState.confirmed.rawValue
    var source: String = ""
    var sourceID: String = ""
    var validFrom: Date = Date.now
    var validTo: Date?
    var processID: String = ""
    var note: String = ""
    var updatedAt: Date = Date.now
    var groupHint: String = ""

    init(id: String, kind: KGKind, name: String, confidence: Double, review: ReviewState,
         source: String, sourceID: String, validFrom: Date, validTo: Date? = nil,
         processID: String = "", note: String = "", groupHint: String = "") {
        self.id = id
        self.kindRaw = kind.rawValue
        self.name = name
        self.confidence = confidence
        self.reviewRaw = review.rawValue
        self.source = source
        self.sourceID = sourceID
        self.validFrom = validFrom
        self.validTo = validTo
        self.processID = processID
        self.note = note
        self.groupHint = groupHint
    }

    var kind: KGKind { KGKind(rawValue: kindRaw) ?? .process }
    var review: ReviewState { ReviewState(rawValue: reviewRaw) ?? .confirmed }
    var isOrphan: Bool { false }
}

enum ReviewState: String, CaseIterable {
    case confirmed, suggested, rejected

    var label: String {
        switch self {
        case .confirmed: "Confirmed"
        case .suggested: "Needs review"
        case .rejected: "Rejected"
        }
    }
}

@Model
final class KGEdgeRecord {
    var id: String = ""
    var fromID: String = ""
    var predicateRaw: String = RelationKind.performedIn.rawValue
    var toID: String = ""
    var confidence: Double = 0.9
    var source: String = ""

    init(id: String, fromID: String, predicate: RelationKind, toID: String,
         confidence: Double, source: String) {
        self.id = id
        self.fromID = fromID
        self.predicateRaw = predicate.rawValue
        self.toID = toID
        self.confidence = confidence
        self.source = source
    }

    var predicate: RelationKind { RelationKind(rawValue: predicateRaw) ?? .performedIn }
}

// MARK: - Governance and audit

@Model
final class GovernanceRecord {
    var id: String = ""
    var title: String = ""
    var detail: String = ""
    var group: String = ""
    var statusRaw: String = GovernanceStatus.notStarted.rawValue
    var owner: String = ""
    var updatedAt: Date = Date.now
    /// The checklist order an owner reads, independent of query order.
    var sortKey: Int = 0

    init(id: String, title: String, detail: String, group: String,
         status: GovernanceStatus, owner: String, sortKey: Int = 0) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.statusRaw = status.rawValue
        self.owner = owner
        self.sortKey = sortKey
    }

    var status: GovernanceStatus { GovernanceStatus(rawValue: statusRaw) ?? .notStarted }
}

enum GovernanceStatus: String, CaseIterable {
    case done, inProgress, blocked, notStarted

    var label: String {
        switch self {
        case .done: "Done"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .notStarted: "Not started"
        }
    }
}

@Model
final class AuditRecord {
    var id: String = ""
    var at: Date = Date.now
    var actor: String = ""
    var action: String = ""
    var subject: String = ""
    var detail: String = ""
    var classificationRaw: String = DataClass.internalUse.rawValue

    init(id: String = UUID().uuidString, at: Date = .now, actor: String, action: String,
         subject: String, detail: String, classification: DataClass = .internalUse) {
        self.id = id
        self.at = at
        self.actor = actor
        self.action = action
        self.subject = subject
        self.detail = detail
        self.classificationRaw = classification.rawValue
    }

    var classification: DataClass { DataClass(rawValue: classificationRaw) ?? .internalUse }
}

@Model
final class SyncRecord {
    var id: String = ""
    var at: Date = Date.now
    var source: String = ""
    var fetched: Int = 0
    var inserted: Int = 0
    var updated: Int = 0
    var skipped: Int = 0
    var statusRaw: String = "success"
    var note: String = ""

    init(id: String = UUID().uuidString, at: Date = .now, source: String, fetched: Int,
         inserted: Int, updated: Int, skipped: Int, status: String, note: String) {
        self.id = id
        self.at = at
        self.source = source
        self.fetched = fetched
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.statusRaw = status
        self.note = note
    }
}

// MARK: - Meetings

/// A meeting note is a page: typed blocks, decisions and actions, linked to
/// the process and initiative it is about.
@Model
final class MeetingRecord {
    var id: String = ""
    var title: String = ""
    var kindRaw: String = MeetingKind.dailyHuddle.rawValue
    var date: Date = Date.now
    var durationMinutes: Int = 30
    var site: String = ""
    var owner: String = ""
    /// Roles, never people. "Order Desk Lead", not a name.
    var attendees: [String] = []
    var processID: String = ""
    var initiativeID: String = ""
    /// planned, notes, done
    var statusRaw: String = MeetingStatus.planned.rawValue
    var summary: String = ""
    var isRecurring: Bool = false
    var cadence: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var kgID: String = ""

    init(id: String, title: String, kind: MeetingKind, date: Date, durationMinutes: Int,
         site: String, owner: String, attendees: [String], processID: String,
         initiativeID: String, status: MeetingStatus, summary: String,
         isRecurring: Bool, cadence: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.date = date
        self.durationMinutes = durationMinutes
        self.site = site
        self.owner = owner
        self.attendees = attendees
        self.processID = processID
        self.initiativeID = initiativeID
        self.statusRaw = status.rawValue
        self.summary = summary
        self.isRecurring = isRecurring
        self.cadence = cadence
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.kgID = "kg-meeting-\(id)"
    }

    var kind: MeetingKind { MeetingKind(rawValue: kindRaw) ?? .dailyHuddle }
    var status: MeetingStatus { MeetingStatus(rawValue: statusRaw) ?? .planned }
}

enum MeetingKind: String, CaseIterable, Identifiable {
    case dailyHuddle, kaizen, a3Review, leadership, workshop, oneToOne

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyHuddle: "Daily huddle"
        case .kaizen: "Kaizen event"
        case .a3Review: "A3 review"
        case .leadership: "Leadership review"
        case .workshop: "Workshop"
        case .oneToOne: "1:1"
        }
    }

    var symbol: String {
        switch self {
        case .dailyHuddle: "sunrise"
        case .kaizen: "bolt"
        case .a3Review: "doc.text"
        case .leadership: "person.3"
        case .workshop: "person.2.wave.2"
        case .oneToOne: "person.crop.circle"
        }
    }

    var defaultDuration: Int {
        switch self {
        case .dailyHuddle: 15
        case .kaizen: 480
        case .a3Review: 45
        case .leadership: 60
        case .workshop: 120
        case .oneToOne: 30
        }
    }
}

enum MeetingStatus: String, CaseIterable {
    case planned, notes, done

    var label: String {
        switch self {
        case .planned: "Planned"
        case .notes: "Notes"
        case .done: "Done"
        }
    }
}

/// One block on a meeting page. `order` is the reading order; blocks are
/// queried by meeting id so the meeting record stays small.
@Model
final class MeetingBlockRecord {
    var id: String = ""
    var meetingID: String = ""
    var order: Int = 0
    var kindRaw: String = BlockKind.text.rawValue
    var text: String = ""
    var checked: Bool = false
    var owner: String = ""
    var due: Date?
    /// process, opportunity, initiative, meeting, node
    var linkedKindRaw: String = ""
    var linkedID: String = ""
    var indent: Int = 0
    var createdAt: Date = Date.now

    init(id: String, meetingID: String, order: Int, kind: BlockKind, text: String,
         checked: Bool = false, owner: String = "", due: Date? = nil,
         linkedKind: String = "", linkedID: String = "", indent: Int = 0) {
        self.id = id
        self.meetingID = meetingID
        self.order = order
        self.kindRaw = kind.rawValue
        self.text = text
        self.checked = checked
        self.owner = owner
        self.due = due
        self.linkedKindRaw = linkedKind
        self.linkedID = linkedID
        self.indent = indent
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .text }
}

enum BlockKind: String, CaseIterable, Identifiable {
    case heading, text, bullet, checklist, decision, action, callout, link

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heading: "Heading"
        case .text: "Text"
        case .bullet: "Bullet"
        case .checklist: "To-do"
        case .decision: "Decision"
        case .action: "Action"
        case .callout: "Callout"
        case .link: "Link"
        }
    }

    var symbol: String {
        switch self {
        case .heading: "textformat.size"
        case .text: "text.alignleft"
        case .bullet: "list.bullet"
        case .checklist: "checklist"
        case .decision: "checkmark.bubble"
        case .action: "person.crop.circle.badge.checkmark"
        case .callout: "lightbulb"
        case .link: "link"
        }
    }

    /// The blocks that become KG nodes when they are created.
    var createsNode: Bool { self == .decision || self == .action }
}

extension MeetingRecord: HasStringID {}
extension MeetingBlockRecord: HasStringID {}


// MARK: - In-house discovery

/// An imported event log. The rows live in `EventItemRecord`; this row is the
/// dataset header a person sees and can delete.
@Model
final class DatasetRecord {
    var id: String = ""
    var name: String = ""
    /// csv, sample, task-capture
    var sourceRaw: String = "csv"
    var importedAt: Date = Date.now
    var caseCount: Int = 0
    var eventCount: Int = 0
    var site: String = ""
    var classificationRaw: String = DataClass.internalUse.rawValue
    var filename: String = ""
    var notes: String = ""

    init(id: String, name: String, source: String, importedAt: Date, caseCount: Int,
         eventCount: Int, site: String, classification: DataClass, filename: String, notes: String) {
        self.id = id
        self.name = name
        self.sourceRaw = source
        self.importedAt = importedAt
        self.caseCount = caseCount
        self.eventCount = eventCount
        self.site = site
        self.classificationRaw = classification.rawValue
        self.filename = filename
        self.notes = notes
    }

    var classification: DataClass { DataClass(rawValue: classificationRaw) ?? .internalUse }
}

@Model
final class EventItemRecord {
    var id: String = ""
    var datasetID: String = ""
    /// Already a hash at import time.
    var caseHash: String = ""
    var activity: String = ""
    var timestamp: Date = Date.now
    var resource: String = ""
    var application: String = ""
    /// JSON object of imported attribute columns.
    var attributesJSON: String = "{}"
    var cost: Double?

    init(id: String, datasetID: String, caseHash: String, activity: String,
         timestamp: Date, resource: String, application: String,
         attributesJSON: String = "{}", cost: Double? = nil) {
        self.id = id
        self.datasetID = datasetID
        self.caseHash = caseHash
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.application = application
        self.attributesJSON = attributesJSON
        self.cost = cost
    }
}

/// One opt-in task-capture session. Samples are aggregated per app; there are
/// no window titles, keystrokes, screenshots or person names.
@Model
final class CaptureSessionRecord {
    var id: String = ""
    var name: String = ""
    var role: String = ""
    var site: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    var sampleSeconds: Int = 5
    var activeMinutes: Double = 0
    var idleMinutes: Double = 0
    var switchCount: Int = 0
    var keystrokeCount: Int = 0
    var clickCount: Int = 0
    var windowTitleCount: Int = 0
    var screenshotCount: Int = 0
    /// capturing, complete
    var statusRaw: String = "complete"
    var notes: String = ""

    init(id: String, name: String, role: String, site: String, startedAt: Date,
         endedAt: Date?, sampleSeconds: Int, activeMinutes: Double, idleMinutes: Double,
         switchCount: Int, keystrokeCount: Int = 0, clickCount: Int = 0,
         windowTitleCount: Int = 0, screenshotCount: Int = 0,
         status: String, notes: String) {
        self.id = id
        self.name = name
        self.role = role
        self.site = site
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sampleSeconds = sampleSeconds
        self.activeMinutes = activeMinutes
        self.idleMinutes = idleMinutes
        self.switchCount = switchCount
        self.keystrokeCount = keystrokeCount
        self.clickCount = clickCount
        self.windowTitleCount = windowTitleCount
        self.screenshotCount = screenshotCount
        self.statusRaw = status
        self.notes = notes
    }

    var status: String { statusRaw }
}

@Model
final class CaptureAppRecord {
    var id: String = ""
    var sessionID: String = ""
    var appName: String = ""
    var bundleID: String = ""
    var minutes: Double = 0
    var idleMinutes: Double = 0
    var switches: Int = 0

    init(id: String, sessionID: String, appName: String, bundleID: String,
         minutes: Double, idleMinutes: Double, switches: Int) {
        self.id = id
        self.sessionID = sessionID
        self.appName = appName
        self.bundleID = bundleID
        self.minutes = minutes
        self.idleMinutes = idleMinutes
        self.switches = switches
    }
}

/// Aggregated window-title samples for a capture. Titles are masked at the
/// source (e-mail/phone patterns) and never leave the Mac.
@Model
final class CaptureWindowRecord {
    var id: String = ""
    var sessionID: String = ""
    var appName: String = ""
    var title: String = ""
    var minutes: Double = 0
    var samples: Int = 0

    init(id: String, sessionID: String, appName: String, title: String,
         minutes: Double, samples: Int) {
        self.id = id
        self.sessionID = sessionID
        self.appName = appName
        self.title = title
        self.minutes = minutes
        self.samples = samples
    }
}

/// A local screenshot thumbnail. The file path is inside Application Support
/// and the retention job removes both the row and the file.
@Model
final class CaptureShotRecord {
    var id: String = ""
    var sessionID: String = ""
    var path: String = ""
    var appName: String = ""
    var capturedAt: Date = Date.now

    init(id: String, sessionID: String, path: String, appName: String, capturedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.path = path
        self.appName = appName
        self.capturedAt = capturedAt
    }
}

extension DatasetRecord: HasStringID {}
extension CaptureSessionRecord: HasStringID {}

/// A configured REST connector. The secret is in the Keychain, keyed by id;
/// the model carries only the query shape and the field mapping.
@Model
final class ConnectorRecord {
    var id: String = ""
    var name: String = ""
    var providerRaw: String = ConnectorProvider.genericJSON.rawValue
    var baseURL: String = ""
    var path: String = ""
    var authMode: String = "bearer" // bearer, basic
    var username: String = ""
    var site: String = ""
    var caseField: String = "case_id"
    var activityField: String = "activity"
    var timestampField: String = "timestamp"
    var resourceField: String = "resource"
    var applicationField: String = "application"
    var costField: String = "cost"
    var active: Bool = true
    var lastRunAt: Date?
    var lastStatus: String = "never"
    var lastError: String = ""
    var createdAt: Date = Date.now

    init(id: String, name: String, provider: ConnectorProvider, baseURL: String,
         path: String, authMode: String, username: String, site: String,
         caseField: String, activityField: String, timestampField: String,
         resourceField: String, applicationField: String, costField: String) {
        self.id = id
        self.name = name
        self.providerRaw = provider.rawValue
        self.baseURL = baseURL
        self.path = path
        self.authMode = authMode
        self.username = username
        self.site = site
        self.caseField = caseField
        self.activityField = activityField
        self.timestampField = timestampField
        self.resourceField = resourceField
        self.applicationField = applicationField
        self.costField = costField
    }

    var provider: ConnectorProvider { ConnectorProvider(rawValue: providerRaw) ?? .genericJSON }
    var mapping: ConnectorMapping {
        ConnectorMapping(caseField: caseField, activityField: activityField,
                         timestampField: timestampField, resourceField: resourceField,
                         applicationField: applicationField, costField: costField)
    }
}

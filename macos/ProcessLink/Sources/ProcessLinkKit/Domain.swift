import Foundation

// MARK: - Data protection

/// The classification label carried by every discovered fact.
/// `restricted` is the hard stop: it never leaves the local store, not even
/// for a local report. Matches the four labels Flightdeck already uses.
public enum DataClass: String, CaseIterable, Sendable, Codable {
    case publicData = "public"
    case internalUse = "internal"
    case confidential = "confidential"
    case restricted = "restricted"

    public var label: String {
        switch self {
        case .publicData: "Public"
        case .internalUse: "Internal"
        case .confidential: "Confidential"
        case .restricted: "Restricted"
        }
    }

    public var detail: String {
        switch self {
        case .publicData: "Safe for any approved destination."
        case .internalUse: "Stays in the tenant or an approved AI gateway."
        case .confidential: "Needs named approval before it moves."
        case .restricted: "Never leaves the local store. Blocked by policy."
        }
    }

    /// Higher is more sensitive.
    public var rank: Int {
        switch self {
        case .publicData: 0
        case .internalUse: 1
        case .confidential: 2
        case .restricted: 3
        }
    }
}

/// Why data is being used. Process improvement is the only permitted purpose
/// in ProcessLink; `individualPerformance` exists so the guard can refuse it
/// by name rather than by omission.
public enum Purpose: String, CaseIterable, Sendable {
    case processImprovement
    case reporting
    case qualityReview
    case individualPerformance

    public var label: String {
        switch self {
        case .processImprovement: "Process improvement"
        case .reporting: "Aggregate reporting"
        case .qualityReview: "Quality review"
        case .individualPerformance: "Individual performance"
        }
    }
}

/// Where data is about to go. The guard's answers are per destination.
public enum Destination: String, CaseIterable, Sendable {
    case localView
    case aiGateway
    case knowledgeGraph
    case export
    case deck

    public var label: String {
        switch self {
        case .localView: "This Mac"
        case .aiGateway: "AI gateway"
        case .knowledgeGraph: "Knowledge graph"
        case .export: "Export"
        case .deck: "DeckForge deck"
        }
    }
}

// MARK: - TEOA

/// A TEOA method, as ProcessLink understands it.
///
/// ⚠ Draft catalog. The official TE Operating Advantage tool list was not in
/// the Flightdeck repository at build time (open question Q4 in
/// docs/PHASE-0-DISCOVERY.md). These ten are the common TEOA-family methods;
/// an admin must confirm names, definitions and validation rules before a
/// pilot, and the app labels the catalog "draft" wherever it is shown.
public enum TEOMethod: String, CaseIterable, Sendable, Codable, Identifiable {
    case fiveS
    case valueStreamMapping
    case standardWork
    case smed
    case kaizen
    case a3
    case hoshin
    case dailyManagement
    case tpm
    case errorProofing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fiveS: "5S workplace organization"
        case .valueStreamMapping: "Value stream mapping"
        case .standardWork: "Standard work"
        case .smed: "SMED / quick changeover"
        case .kaizen: "Kaizen event"
        case .a3: "A3 problem solving"
        case .hoshin: "Hoshin deployment"
        case .dailyManagement: "Daily management"
        case .tpm: "Total productive maintenance"
        case .errorProofing: "Error proofing (poka-yoke)"
        }
    }

    public var summary: String {
        switch self {
        case .fiveS: "Organize the workspace so the right information is where the work happens."
        case .valueStreamMapping: "Map the flow end to end, separate value from wait, and size the gap."
        case .standardWork: "Define the current best sequence, then measure adherence against it."
        case .smed: "Cut changeover and setup time between cases, products or queues."
        case .kaizen: "A focused, time-boxed team event that removes one known waste."
        case .a3: "Structure a problem on one page: background, target, cause, countermeasure, result."
        case .hoshin: "Connect improvement work to the few breakthrough objectives that matter this year."
        case .dailyManagement: "See today's performance against target, every day, at the point of work."
        case .tpm: "Keep the tools, systems and data pipelines that carry the work reliable."
        case .errorProofing: "Make the mistake hard to make instead of asking people to try harder."
        }
    }

    /// Which mined signal points at this method.
    public var signal: String {
        switch self {
        case .fiveS: "Search time, window switching, duplicate systems"
        case .valueStreamMapping: "Long waiting time between steps, many handoffs"
        case .standardWork: "Many variants, low adherence, best-practice path hidden"
        case .smed: "Setup or queue change between cases dominates cycle time"
        case .kaizen: "One hot spot with a clear owner and a short fix"
        case .a3: "A problem that needs a cause, not just a task"
        case .hoshin: "Improvement work that does not ladder to an objective"
        case .dailyManagement: "No daily read of cycle time, backlog or rework"
        case .tpm: "System failures, retries and data quality gaps"
        case .errorProofing: "Rework caused by missing or mistyped data"
        }
    }

    public var symbol: String {
        switch self {
        case .fiveS: "square.grid.2x2"
        case .valueStreamMapping: "point.topleft.down.to.point.bottomright.curvepath"
        case .standardWork: "list.number"
        case .smed: "timer"
        case .kaizen: "bolt"
        case .a3: "doc.text"
        case .hoshin: "scope"
        case .dailyManagement: "calendar.day.timeline.left"
        case .tpm: "wrench.and.screwdriver"
        case .errorProofing: "shield.lefthalf.filled.badge.checkmark"
        }
    }
}

/// The eight wastes, translated to digital and administrative work. The TE
/// names are kept where they exist; the digital reading is what a mined task
/// can actually show.
public enum WasteType: String, CaseIterable, Sendable, Codable, Identifiable {
    case waiting
    case rework
    case overProcessing
    case handoffs
    case contextSwitching
    case defects
    case unusedTalent
    case backlog

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .waiting: "Waiting"
        case .rework: "Rework"
        case .overProcessing: "Over-processing"
        case .handoffs: "Handoffs"
        case .contextSwitching: "Context switching"
        case .defects: "Defects"
        case .unusedTalent: "Unused talent"
        case .backlog: "Backlog / inventory"
        }
    }

    public var digital: String {
        switch self {
        case .waiting: "Queue time, approvals waiting in an inbox, batch waits"
        case .rework: "Re-opening a case, correcting a record, repeating a check"
        case .overProcessing: "Extra approvals, duplicate data entry, unnecessary checks"
        case .handoffs: "Work passed between teams, systems or tickets"
        case .contextSwitching: "Jumping between applications and windows to finish one task"
        case .defects: "Wrong data, failed validation, returned cases"
        case .unusedTalent: "Skilled people doing copy-paste, chasing or manual reconciliation"
        case .backlog: "Open cases growing faster than they close"
        }
    }

    public var symbol: String {
        switch self {
        case .waiting: "hourglass"
        case .rework: "arrow.triangle.2.circlepath"
        case .overProcessing: "square.stack.3d.up"
        case .handoffs: "arrow.left.arrow.right"
        case .contextSwitching: "rectangle.on.rectangle"
        case .defects: "exclamationmark.triangle"
        case .unusedTalent: "person.crop.circle.badge.questionmark"
        case .backlog: "tray.full"
        }
    }
}

/// The five ways to respond to an opportunity. The order is the TEOA order:
/// eliminate first, automate last.
public enum Route: String, CaseIterable, Sendable, Codable {
    case eliminate
    case simplify
    case standardize
    case automate
    case leave

    public var label: String {
        switch self {
        case .eliminate: "Eliminate"
        case .simplify: "Simplify"
        case .standardize: "Standardize"
        case .automate: "Automate"
        case .leave: "Leave as-is"
        }
    }

    public var detail: String {
        switch self {
        case .eliminate: "Stop doing the step at all; question the requirement first."
        case .simplify: "Keep the outcome, remove the extra checks and data entry."
        case .standardize: "Make the best path the only path, with a human control where required."
        case .automate: "Only after eliminate, simplify and standardize are done."
        case .leave: "Nothing worth changing; keep it visible and monitored."
        }
    }

    public var symbol: String {
        switch self {
        case .eliminate: "trash.slash"
        case .simplify: "scissors"
        case .standardize: "ruler"
        case .automate: "gearshape.2"
        case .leave: "pause.circle"
        }
    }
}

// MARK: - Savings lifecycle

/// TE's validation ladder: a saving is an estimate until a human commits it,
/// and committed until before/after evidence validates it.
public enum SavingsStage: String, CaseIterable, Sendable, Codable {
    case estimated
    case committed
    case validated

    public var label: String {
        switch self {
        case .estimated: "Estimated"
        case .committed: "Committed"
        case .validated: "Validated"
        }
    }

    public var detail: String {
        switch self {
        case .estimated: "Calculated from mined data. Not a claim."
        case .committed: "An owner and a target date have signed up."
        case .validated: "Before/after evidence checked by a named validator."
        }
    }

    public var rank: Int {
        switch self {
        case .estimated: 0
        case .committed: 1
        case .validated: 2
        }
    }
}

// MARK: - Knowledge graph vocabulary

/// The node types ProcessLink asks the KG to hold. This is the proposed
/// ontology in docs/KG-ONTOLOGY.md; the app only writes types it declares.
public enum KGKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case process
    case subprocess
    case task
    case step
    case variant
    case application
    case system
    case role
    case team
    case site
    case businessUnit
    case valueStream
    case document
    case control
    case risk
    case metric
    case painPoint
    case wasteInstance
    case opportunity
    case initiative
    case automation
    case savingsRecord
    case teoaMethod
    case maturityAssessment
    case hoshinObjective
    case meeting
    case decision
    case action
    case map

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .process: "Process"
        case .subprocess: "Subprocess"
        case .task: "Task"
        case .step: "Step"
        case .variant: "Variant"
        case .application: "Application"
        case .system: "System"
        case .role: "Role"
        case .team: "Team"
        case .site: "Site"
        case .businessUnit: "Business unit"
        case .valueStream: "Value stream"
        case .document: "Document / SOP"
        case .control: "Control"
        case .risk: "Risk"
        case .metric: "Metric"
        case .painPoint: "Pain point"
        case .wasteInstance: "Waste instance"
        case .opportunity: "Opportunity"
        case .initiative: "Initiative / Kaizen"
        case .automation: "Automation / agent"
        case .savingsRecord: "Savings record"
        case .teoaMethod: "TEOA method"
        case .maturityAssessment: "Maturity assessment"
        case .hoshinObjective: "Hoshin objective"
        case .meeting: "Meeting"
        case .decision: "Decision"
        case .action: "Action"
        case .map: "Map"
        }
    }

    public var symbol: String {
        switch self {
        case .process: "arrow.triangle.branch"
        case .subprocess: "arrow.triangle.branch"
        case .task: "checklist"
        case .step: "smallcircle.filled.circle"
        case .variant: "arrow.triangle.swap"
        case .application: "app"
        case .system: "server.rack"
        case .role: "person.badge.key"
        case .team: "person.3"
        case .site: "mappin.and.ellipse"
        case .businessUnit: "building.2"
        case .valueStream: "arrow.right.to.line.compact"
        case .document: "doc.text"
        case .control: "checkmark.shield"
        case .risk: "exclamationmark.shield"
        case .metric: "chart.bar"
        case .painPoint: "bandage"
        case .wasteInstance: "trash"
        case .opportunity: "lightbulb"
        case .initiative: "flag"
        case .automation: "gearshape.2"
        case .savingsRecord: "banknote"
        case .teoaMethod: "book.closed"
        case .maturityAssessment: "chart.line.uptrend.xyaxis"
        case .hoshinObjective: "scope"
        case .meeting: "person.3.sequence"
        case .decision: "checkmark.bubble"
        case .action: "checklist"
        case .map: "map"
        }
    }
}

/// The relation predicates in the proposed ontology.
public enum RelationKind: String, CaseIterable, Sendable, Codable {
    case performedIn
    case uses
    case handsOffTo
    case variantOf
    case deviatesFromStandard
    case ownedBy
    case measuredBy
    case causes
    case mitigatedBy
    case addressedBy
    case automatedBy
    case realizesSavings
    case alignedToObjective
    case documentedIn
    case hasOpportunity
    case discussedIn
    case assignedTo

    public var label: String {
        switch self {
        case .performedIn: "performed in"
        case .uses: "uses"
        case .handsOffTo: "hands off to"
        case .variantOf: "variant of"
        case .deviatesFromStandard: "deviates from standard"
        case .ownedBy: "owned by"
        case .measuredBy: "measured by"
        case .causes: "causes"
        case .mitigatedBy: "mitigated by"
        case .addressedBy: "addressed by"
        case .automatedBy: "automated by"
        case .realizesSavings: "realizes savings"
        case .alignedToObjective: "aligned to objective"
        case .documentedIn: "documented in"
        case .hasOpportunity: "has opportunity"
        case .discussedIn: "discussed in"
        case .assignedTo: "assigned to"
        }
    }
}

// MARK: - Provenance

/// Every fact ProcessLink shows carries where it came from and how sure we
/// are. `sourceID` is the discovery object id, never a person.
public struct Provenance: Sendable, Hashable, Codable {
    public var source: String
    public var sourceID: String
    public var capturedFrom: Date
    public var capturedTo: Date
    public var confidence: Double
    public var syncedAt: Date

    public init(source: String, sourceID: String, capturedFrom: Date, capturedTo: Date,
                confidence: Double, syncedAt: Date) {
        self.source = source
        self.sourceID = sourceID
        self.capturedFrom = capturedFrom
        self.capturedTo = capturedTo
        self.confidence = confidence
        self.syncedAt = syncedAt
    }

    /// 0...1, for a three-state confidence chip.
    public var band: ConfidenceBand {
        confidence >= 0.85 ? .high : confidence >= 0.65 ? .medium : .low
    }
}

public enum ConfidenceBand: String, Sendable, Codable {
    case high, medium, low

    public var label: String {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence — review"
        }
    }
}

/// A citation the assistant must show for every number it says out loud.
public struct Citation: Sendable, Hashable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable {
        case discovery
        case kgNode
        case initiative
        case policy
        case computed
        case meeting

        public var label: String {
            switch self {
            case .discovery: "Discovery"
            case .kgNode: "KG"
            case .initiative: "Initiative"
            case .policy: "Policy"
            case .computed: "Computed"
            case .meeting: "Meeting"
            }
        }
    }

    public var id: String { "\(kind.rawValue):\(ref)" }
    public var kind: Kind
    public var ref: String
    public var label: String

    public init(kind: Kind, ref: String, label: String) {
        self.kind = kind
        self.ref = ref
        self.label = label
    }
}

// MARK: - Cost model

/// One blended rate, held in one place. Hours are the source of truth; money
/// is derived so a rate change can never rewrite a validated saving. The
/// real rate comes from Finance (open question Q6).
public enum CostModel {
    public static let ratePerHour: Double = 52

    public static func euro(hours: Double) -> String {
        Fmt.euro(hours * ratePerHour)
    }
}

// MARK: - Formatting helpers shared by every surface

public enum Fmt {
    /// 1,240 h — no decimals on a year of effort.
    public static func hours(_ value: Double) -> String {
        let number = value.rounded()
        return "\(Int(number).formatted(.number.grouping(.automatic))) h"
    }

    /// 1,240 h/yr
    public static func hoursPerYear(_ value: Double) -> String {
        "\(hours(value))/yr"
    }

    /// €64,480 — whole euros, grouped.
    public static func euro(_ value: Double) -> String {
        "€\(Int(value.rounded()).formatted(.number.grouping(.automatic)))"
    }

    /// 64% — whole percent for a rate the user reads at a glance.
    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// 12 min
    public static func minutes(_ value: Double) -> String {
        value < 60 ? "\(Int(value.rounded())) min" : String(format: "%.1f h", value / 60)
    }

    /// 4 days ago / today
    public static func ago(_ date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// 14 Sep 2026
    public static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// 14 Sep 2026, 09:41
    public static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    /// 2026-Q3 — the period a citation can point at.
    public static func quarter(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let year = Calendar.current.component(.year, from: date)
        return "\(year)-Q\((month - 1) / 3 + 1)"
    }
}

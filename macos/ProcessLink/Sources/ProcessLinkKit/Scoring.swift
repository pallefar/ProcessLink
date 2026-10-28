import Foundation

/// What the opportunity engine needs to rank one opportunity. Everything is
/// a number a user can point at: mined hours, an effort estimate, two
/// judgement scores, and the statutory flag that must never be automated.
public struct OpportunityInputs: Sendable, Hashable {
    public var annualHours: Double
    public var errorReductionPct: Double
    public var effortWeeks: Double
    /// 1 (low) ... 5 (high), set by the reviewer.
    public var risk: Int
    /// 1 ... 5, how strongly this ladders to a Hoshin objective.
    public var alignment: Int
    /// 0 ... 1, from the automation-suitability rubric.
    public var automationSuitability: Double
    public var confidence: Double
    public var statutory: Bool
    public var waste: WasteType

    public init(annualHours: Double, errorReductionPct: Double, effortWeeks: Double, risk: Int,
                alignment: Int, automationSuitability: Double, confidence: Double,
                statutory: Bool, waste: WasteType) {
        self.annualHours = annualHours
        self.errorReductionPct = errorReductionPct
        self.effortWeeks = effortWeeks
        self.risk = risk
        self.alignment = alignment
        self.automationSuitability = automationSuitability
        self.confidence = confidence
        self.statutory = statutory
        self.waste = waste
    }
}

/// One opportunity's score, with every component kept so the UI can show the
/// arithmetic instead of a black-box number.
public struct OpportunityScore: Sendable, Hashable {
    /// 0 ... 100
    public var impact: Double
    /// 0 ... 100, higher is easier.
    public var ease: Double
    /// 0 ... 100
    public var alignment: Double
    /// 0 ... 100
    public var automation: Double
    /// Points subtracted, 0 ... 20.
    public var riskPenalty: Double
    /// 0 ... 100
    public var total: Double
    public var route: Route
    public var reasoning: [String]
}

public enum OpportunityScoring {
    /// Weighted, bounded, and deliberately easy to explain:
    ///   impact   = 70 × (hours / 1200, capped) + 30 × error-reduction rate
    ///   ease     = 100 − 6 per week of effort beyond the first (floor 10)
    ///   total    = 0.42·impact + 0.22·ease + 0.18·alignment
    ///              + 0.10·automation + 0.08·confidence − risk penalty
    ///
    /// The weights sum to 1.0, so a perfect opportunity is 100 before the
    /// penalty. `confidence` is scaled 0...100 before weighting.
    public static func score(_ input: OpportunityInputs) -> OpportunityScore {
        let hours = max(0, input.annualHours)
        let hourComponent = min(1, hours / 1_200) * 70
        let errorComponent = min(1, max(0, input.errorReductionPct / 100)) * 30
        let impact = min(100, hourComponent + errorComponent)

        let ease = min(100, max(10, 100 - max(0, input.effortWeeks - 1) * 6))
        let alignment = min(100, max(0, Double(min(5, max(1, input.alignment))) / 5 * 100))
        let automation = min(100, max(0, input.automationSuitability * 100))
        let riskPenalty = Double(min(5, max(1, input.risk)) - 1) * 5
        let confidence = min(100, max(0, input.confidence * 100))

        let raw = 0.42 * impact + 0.22 * ease + 0.18 * alignment + 0.10 * automation + 0.08 * confidence
        let total = min(100, max(0, raw - riskPenalty))

        var reasoning: [String] = []
        reasoning.append("\(Fmt.hours(hours))/yr of mined effort drives \(Int(hourComponent.rounded())) of the 100 impact points.")
        if input.errorReductionPct > 0 {
            reasoning.append("A \(Int(input.errorReductionPct.rounded())) percent error reduction adds \(Int(errorComponent.rounded())) points.")
        }
        reasoning.append("An estimated \(String(format: "%.0f", input.effortWeeks)) weeks of effort gives an ease score of \(Int(ease.rounded())).")
        reasoning.append("Alignment \(input.alignment)/5 contributes \(Int((0.18 * alignment).rounded())) weighted points.")
        if riskPenalty > 0 {
            reasoning.append("Risk \(input.risk)/5 subtracts \(Int(riskPenalty.rounded())) points.")
        }
        if input.confidence < 0.75 {
            reasoning.append("Confidence is \(Fmt.percent(input.confidence)); this needs a human check before it is committed.")
        }

        return OpportunityScore(impact: impact, ease: ease, alignment: alignment, automation: automation,
                                riskPenalty: riskPenalty, total: total,
                                route: route(for: input), reasoning: reasoning)
    }

    /// The TEOA order: eliminate, simplify, standardize, then automate. A
    /// statutory or human-only step is never an automation candidate — the
    /// guardrail is in the rule, not in the copy.
    public static func route(for input: OpportunityInputs) -> Route {
        if input.statutory { return .standardize }
        switch input.waste {
        case .handoffs, .waiting:
            return input.automationSuitability >= 0.55 && input.effortWeeks <= 10 ? .automate : .simplify
        case .overProcessing, .defects:
            return .simplify
        case .contextSwitching, .rework:
            return .standardize
        case .backlog:
            return .eliminate
        case .unusedTalent:
            return input.automationSuitability >= 0.5 ? .automate : .standardize
        }
    }
}

/// A method suggestion with the reason attached, so the coach can be
/// challenged rather than obeyed.
public struct MethodRecommendation: Sendable, Hashable {
    public var method: TEOMethod
    public var reason: String
}

public enum MethodRecommender {
    public static func recommend(waste: WasteType, route: Route, statutory: Bool) -> MethodRecommendation {
        if statutory {
            return MethodRecommendation(method: .a3,
                reason: "A statutory or human-only step keeps its human control. Use A3 to make the control explicit and measurable; automation is excluded by policy.")
        }
        if route == .automate {
            return MethodRecommendation(method: .kaizen,
                reason: "Automation follows a kaizen that proves the simplified path. Run the event first, then hand the stable path to automation.")
        }
        if route == .eliminate {
            return MethodRecommendation(method: .valueStreamMapping,
                reason: "Removing work starts with seeing the flow. Map the stream to find where the step waits before deleting it.")
        }
        switch waste {
        case .handoffs, .waiting:
            return MethodRecommendation(method: .valueStreamMapping,
                reason: "Handoffs and waiting are visible only end to end. The value stream map shows the queue between each pair of roles.")
        case .overProcessing:
            return MethodRecommendation(method: .standardWork,
                reason: "Duplicate checks and extra approvals disappear when the standard path is written down once and followed.")
        case .rework, .defects:
            return MethodRecommendation(method: .a3,
                reason: "Rework needs a cause before a countermeasure. A3 keeps the analysis honest and the result measurable.")
        case .contextSwitching:
            return MethodRecommendation(method: .fiveS,
                reason: "Switching between applications is a workplace-organisation problem: put the information where the work happens.")
        case .unusedTalent:
            return MethodRecommendation(method: .standardWork,
                reason: "Copy-paste and chasing are not the job. Write the standard so the skilled part stays with the person.")
        case .backlog:
            return MethodRecommendation(method: .dailyManagement,
                reason: "A backlog needs a daily read against target, not a one-off project. Put it on the management board.")
        }
    }
}

// MARK: - Savings ledger

/// One row of the savings ledger. Hours, not money, are the source of truth;
/// money is derived with one rate so a rate change never rewrites history.
public struct SavingsLine: Sendable, Identifiable, Hashable {
    public var id: String
    public var initiativeID: String
    public var initiativeTitle: String
    public var processID: String
    public var waste: WasteType
    public var stage: SavingsStage
    public var hours: Double
    public var validatedBy: String?
    public var note: String

    public init(id: String, initiativeID: String, initiativeTitle: String, processID: String,
                waste: WasteType, stage: SavingsStage, hours: Double, validatedBy: String?, note: String) {
        self.id = id
        self.initiativeID = initiativeID
        self.initiativeTitle = initiativeTitle
        self.processID = processID
        self.waste = waste
        self.stage = stage
        self.hours = hours
        self.validatedBy = validatedBy
        self.note = note
    }
}

public struct SavingsTotals: Sendable, Hashable {
    public var estimated: Double
    public var committed: Double
    public var validated: Double
}

/// A duplicate claim on the same process and waste type.
public struct SavingsConflict: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    public var processID: String
    public var waste: WasteType
    public var initiativeIDs: [String]
    public var hours: Double
}

public enum SavingsLedger {
    /// The key that prevents double counting: one process, one waste type.
    public static func key(processID: String, waste: WasteType) -> String {
        "\(processID):\(waste.rawValue)"
    }

    /// Credited hours at each stage. For each key only the most advanced line
    /// counts (a validated saving does not also count as committed), and ties
    /// at the same stage take the larger claim once, never the sum.
    public static func totals(_ lines: [SavingsLine]) -> SavingsTotals {
        var credited: [String: SavingsLine] = [:]
        for line in lines {
            let key = key(processID: line.processID, waste: line.waste)
            if let existing = credited[key] {
                if line.stage.rank > existing.stage.rank
                    || (line.stage.rank == existing.stage.rank && line.hours > existing.hours) {
                    credited[key] = line
                }
            } else {
                credited[key] = line
            }
        }
        var totals = SavingsTotals(estimated: 0, committed: 0, validated: 0)
        for line in credited.values {
            switch line.stage {
            case .estimated: totals.estimated += line.hours
            case .committed: totals.committed += line.hours
            case .validated: totals.validated += line.hours
            }
        }
        return totals
    }

    /// Keys claimed by more than one initiative at committed or beyond.
    public static func conflicts(_ lines: [SavingsLine]) -> [SavingsConflict] {
        var byKey: [String: [SavingsLine]] = [:]
        for line in lines where line.stage.rank >= SavingsStage.committed.rank {
            byKey[key(processID: line.processID, waste: line.waste), default: []].append(line)
        }
        return byKey.compactMap { key, group in
            let initiatives = Set(group.map(\.initiativeID))
            guard initiatives.count > 1 else { return nil }
            return SavingsConflict(key: key, processID: group[0].processID, waste: group[0].waste,
                                   initiativeIDs: Array(initiatives).sorted(),
                                   hours: group.map(\.hours).max() ?? 0)
        }
    }

    /// A validated line must name who validated it.
    public static func unvalidatedClaims(_ lines: [SavingsLine]) -> [SavingsLine] {
        lines.filter { $0.stage == .validated && ($0.validatedBy ?? "").isEmpty }
    }
}

// MARK: - Drift

public enum Drift {
    /// A map or a discovered process is stale after this many days without a
    /// successful sync. Configurable in production; fixed here so the demo
    /// cannot silently change its own threshold.
    public static let staleAfterDays = 14

    public static func days(since date: Date, now: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0)
    }

    public static func isStale(lastSynced: Date, now: Date = .now) -> Bool {
        days(since: lastSynced, now: now) > staleAfterDays
    }
}

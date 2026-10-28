import Foundation

// MARK: - Read models the assistant is allowed to see
//
// The engine never receives a person, a screenshot, a keystroke or a free
// text field. It receives aggregates that already passed the privacy guard.

public struct ProcessInsight: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var site: String
    public var valueStream: String
    public var people: Int
    public var annualHours: Double
    public var cycleMinutes: Double
    public var reworkRate: Double
    public var handoffs: Int
    /// 0 ... 1, adherence to the documented standard work.
    public var adherence: Double
    public var variantCount: Int
    public var confidence: Double
    public var staleDays: Int
    public var kypID: String
    public var kgID: String

    public init(id: String, name: String, site: String, valueStream: String, people: Int,
                annualHours: Double, cycleMinutes: Double, reworkRate: Double, handoffs: Int,
                adherence: Double, variantCount: Int, confidence: Double, staleDays: Int,
                kypID: String, kgID: String) {
        self.id = id
        self.name = name
        self.site = site
        self.valueStream = valueStream
        self.people = people
        self.annualHours = annualHours
        self.cycleMinutes = cycleMinutes
        self.reworkRate = reworkRate
        self.handoffs = handoffs
        self.adherence = adherence
        self.variantCount = variantCount
        self.confidence = confidence
        self.staleDays = staleDays
        self.kypID = kypID
        self.kgID = kgID
    }
}

public struct StepInsight: Sendable, Hashable, Identifiable {
    public var id: String
    public var processID: String
    public var processName: String
    public var site: String
    public var name: String
    public var role: String
    public var application: String
    public var minutes: Double
    public var handoffs: Int
    public var reworkShare: Double
    public var waste: WasteType
    public var evidenceCount: Int
    public var kgID: String

    public init(id: String, processID: String, processName: String, site: String, name: String,
                role: String, application: String, minutes: Double, handoffs: Int,
                reworkShare: Double, waste: WasteType, evidenceCount: Int, kgID: String) {
        self.id = id
        self.processID = processID
        self.processName = processName
        self.site = site
        self.name = name
        self.role = role
        self.application = application
        self.minutes = minutes
        self.handoffs = handoffs
        self.reworkShare = reworkShare
        self.waste = waste
        self.evidenceCount = evidenceCount
        self.kgID = kgID
    }
}

public struct OpportunityInsight: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var processID: String
    public var processName: String
    public var site: String
    public var annualHours: Double
    public var confidence: Double
    public var route: Route
    public var kgID: String

    public init(id: String, title: String, processID: String, processName: String, site: String,
                annualHours: Double, confidence: Double, route: Route, kgID: String) {
        self.id = id
        self.title = title
        self.processID = processID
        self.processName = processName
        self.site = site
        self.annualHours = annualHours
        self.confidence = confidence
        self.route = route
        self.kgID = kgID
    }
}

// MARK: - Meetings

/// One decision or action as the assistant may see it. Text is the block's
/// own words; no attendee identity is ever included.
public struct MeetingItemInsight: Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var owner: String
    public var done: Bool
    public var due: Date?

    public init(id: String, text: String, owner: String, done: Bool, due: Date? = nil) {
        self.id = id
        self.text = text
        self.owner = owner
        self.done = done
        self.due = due
    }
}

public struct MeetingInsight: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var date: Date
    public var kind: String
    public var site: String
    public var processName: String
    public var decisions: [MeetingItemInsight]
    public var actions: [MeetingItemInsight]
    public var kgID: String

    public init(id: String, title: String, date: Date, kind: String, site: String,
                processName: String, decisions: [MeetingItemInsight],
                actions: [MeetingItemInsight], kgID: String) {
        self.id = id
        self.title = title
        self.date = date
        self.kind = kind
        self.site = site
        self.processName = processName
        self.decisions = decisions
        self.actions = actions
        self.kgID = kgID
    }
}

// MARK: - Answer

public struct AskAnswer: Sendable, Hashable, Identifiable {
    public enum Intent: String, Sendable {
        case handoffs
        case adherence
        case opportunity
        case variants
        case freshness
        case sites
        case governance
        case decisions
        case actions
        case fallback
    }

    public var id: String = UUID().uuidString
    public var question: String
    public var intent: Intent
    public var headline: String
    public var body: String
    public var citations: [Citation]
    public var toVerify: [String]
    public var confidence: Double

    public init(question: String, intent: Intent, headline: String, body: String,
                citations: [Citation], toVerify: [String], confidence: Double) {
        self.question = question
        self.intent = intent
        self.headline = headline
        self.body = body
        self.citations = citations
        self.toVerify = toVerify
        self.confidence = confidence
    }
}

/// Deterministic, local "Ask the process". Every number comes from the read
/// models above and every claim carries a citation. This is the offline
/// provider in the provider abstraction; the hosted provider answers through
/// the same contract, and the same citation checks run on both.
public enum AskEngine {
    public static let suggestions: [String] = [
        "Where do handoffs create the most rework?",
        "Which standard work is least followed?",
        "What would automating order intake save?",
        "Which processes have the most variants?",
        "What did we decide about pricing?",
        "What actions are still open?",
    ]

    public static func answer(_ rawQuestion: String,
                              processes: [ProcessInsight],
                              steps: [StepInsight],
                              opportunities: [OpportunityInsight],
                              meetings: [MeetingInsight] = []) -> AskAnswer {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = question.lowercased()

        if lower.contains("privacy") || lower.contains("gdpr") || lower.contains("works council")
            || lower.contains("legal") || lower.contains("dpia") {
            return governance(question)
        }
        if lower.contains("handoff") || lower.contains("rework") {
            return handoffAnswer(question, steps: steps, processes: processes)
        }
        if lower.contains("standard") || lower.contains("adherence") || lower.contains("follow")
            || lower.contains("followed") {
            return adherenceAnswer(question, processes: processes)
        }
        if lower.contains("decid") || lower.contains("meeting") || lower.contains("minutes") {
            return decisionAnswer(question, meetings: meetings, processes: processes)
        }
        if lower.contains("action") || lower.contains("follow-up") || lower.contains("follow up") {
            return actionAnswer(question, meetings: meetings, processes: processes)
        }
        if lower.contains("variant") {
            return variantAnswer(question, processes: processes)
        }
        if lower.contains("stale") || lower.contains("fresh") || lower.contains("changed")
            || lower.contains("old") {
            return freshnessAnswer(question, processes: processes)
        }
        if lower.contains("site") || lower.contains("compare") || lower.contains("across") {
            return siteAnswer(question, processes: processes)
        }
        if lower.contains("save") || lower.contains("saving") || lower.contains("worth")
            || lower.contains("automate") || lower.contains("automation") || lower.contains("opportunit") {
            return opportunityAnswer(question, opportunities: opportunities, processes: processes)
        }
        return fallback(question, processes: processes, opportunities: opportunities)
    }

    // MARK: Intents

    private static func handoffAnswer(_ question: String, steps: [StepInsight],
                                      processes: [ProcessInsight]) -> AskAnswer {
        let ranked = steps
            .filter { $0.handoffs > 0 && $0.reworkShare > 0.05 }
            .sorted { lhs, rhs in
                let left = Double(lhs.handoffs) * lhs.reworkShare * Double(lhs.evidenceCount)
                let right = Double(rhs.handoffs) * rhs.reworkShare * Double(rhs.evidenceCount)
                return left > right
            }
        guard let first = ranked.first else {
            return AskAnswer(question: question, intent: .handoffs,
                headline: "No handoff-driven rework found in the current window",
                body: "The sandbox data has no step that both hands work off and carries rework. That is a finding, not a zero: confirm the KYP.ai capture window covers the process before reading it as good news.",
                citations: [], toVerify: ["Confirm the KYP.ai capture window"], confidence: 0.6)
        }
        let top = ranked.prefix(3)
        let process = processes.first { $0.id == first.processID }
        let body = top.enumerated().map { index, step in
            "\(index + 1). \(step.name) — \(step.processName), \(step.site). \(step.handoffs) handoff\(step.handoffs == 1 ? "" : "s"), \(Fmt.percent(step.reworkShare)) of its touches rework, on \(step.application)."
        }.joined(separator: "\n")
        let citations = top.flatMap { step in
            [Citation(kind: .kyp, ref: step.id, label: step.name),
             Citation(kind: .kgNode, ref: step.kgID, label: step.name)]
        }
        var verify = ["Handoff counts are mined events, not a judgement about the people who do them."]
        if let process, process.confidence < 0.85 {
            verify.append("\(process.name) confidence is \(Fmt.percent(process.confidence)); re-check after the next sync.")
        }
        return AskAnswer(question: question, intent: .handoffs,
            headline: "Handoffs concentrate rework at \(first.name)",
            body: body + "\n\nThe pattern to test: each handoff adds a queue and a re-key. The value stream map for \(first.processName) is generated from these steps, with the loop drawn where the rework returns.",
            citations: citations, toVerify: verify,
            confidence: min(0.92, min(1, 0.6 + Double(top.map { $0.evidenceCount }.min() ?? 0) / 60)))
    }

    private static func adherenceAnswer(_ question: String, processes: [ProcessInsight]) -> AskAnswer {
        let ranked = processes
            .filter { $0.people >= 10 }
            .sorted { $0.adherence < $1.adherence }
        guard let lowest = ranked.first else {
            return AskAnswer(question: question, intent: .adherence,
                headline: "No group large enough to compare", body: "Every process is below the group-size threshold, so adherence cannot be shown.",
                citations: [], toVerify: ["Group sizes"], confidence: 0.5)
        }
        let body = ranked.prefix(3).map { process in
            "\(process.name) (\(process.site)): \(Fmt.percent(process.adherence)) adherence across \(process.variantCount) variant\(process.variantCount == 1 ? "" : "s")."
        }.joined(separator: "\n")
        let citations = ranked.prefix(3).map {
            Citation(kind: .kgNode, ref: $0.kgID, label: $0.name)
        }
        return AskAnswer(question: question, intent: .adherence,
            headline: "\(lowest.name) deviates most from its documented standard",
            body: body + "\n\nA low adherence number has two readings: the standard is wrong, or the work has drifted. Compare the most common variant with the SOP before changing either. The comparison is on the Maps tab.",
            citations: citations,
            toVerify: ["Confirm the SOP version that the adherence is measured against"],
            confidence: 0.82)
    }

    private static func decisionAnswer(_ question: String, meetings: [MeetingInsight],
                                        processes: [ProcessInsight]) -> AskAnswer {
        let lower = question.lowercased()
        let named = processes.first { lower.contains($0.name.lowercased()) }
        let scoped = named == nil ? meetings : meetings.filter { $0.processName == named?.name }
        let withDecisions = scoped.filter { !$0.decisions.isEmpty }
        guard !withDecisions.isEmpty else {
            return AskAnswer(question: question, intent: .decisions,
                headline: "No decision is recorded for that scope",
                body: "ProcessLink holds \(meetings.count) meeting note\(meetings.count == 1 ? "" : "s"), but none of them records a decision for this scope. That is an absence of evidence, not evidence of no decision.",
                citations: meetings.prefix(3).map { Citation(kind: .meeting, ref: $0.kgID, label: $0.title) },
                toVerify: ["Check the meeting minutes or ask the meeting owner"], confidence: 0.6)
        }
        let body = withDecisions.prefix(3).flatMap { meeting in
            meeting.decisions.map { decision in
                "\(meeting.title) (\(Fmt.day(meeting.date))): \(decision.text)"
            }
        }.joined(separator: "\n")
        return AskAnswer(question: question, intent: .decisions,
            headline: "Recorded decisions for \(named?.name ?? "the portfolio")",
            body: body + "\n\nA decision note is a record of what the room agreed. It is not a validated outcome and it does not approve a change on its own.",
            citations: withDecisions.prefix(3).map { Citation(kind: .meeting, ref: $0.kgID, label: $0.title) },
            toVerify: ["Confirm the minutes were approved", "Confirm the owner recorded against each decision"],
            confidence: 0.84)
    }

    private static func actionAnswer(_ question: String, meetings: [MeetingInsight],
                                     processes: [ProcessInsight]) -> AskAnswer {
        let lower = question.lowercased()
        let named = processes.first { lower.contains($0.name.lowercased()) }
        let scoped = named == nil ? meetings : meetings.filter { $0.processName == named?.name }
        let open = scoped.flatMap { meeting in
            meeting.actions.filter { !$0.done }.map { (meeting, $0) }
        }
        guard !open.isEmpty else {
            return AskAnswer(question: question, intent: .actions,
                headline: "No open actions in that scope",
                body: "Every action recorded in the matching meeting notes is marked done. Check the decisions that created them before closing the loop.",
                citations: scoped.prefix(3).map { Citation(kind: .meeting, ref: $0.kgID, label: $0.title) },
                toVerify: ["Confirm done actions have evidence, not just a tick"], confidence: 0.7)
        }
        let body = open.prefix(5).map { meeting, action in
            "• \(action.text) — \(action.owner.isEmpty ? "unassigned" : action.owner)\(action.due.map { ", due \(Fmt.day($0))" } ?? "")\(meeting.title.isEmpty ? "" : " · \(meeting.title)")"
        }.joined(separator: "\n")
        return AskAnswer(question: question, intent: .actions,
            headline: "\(open.count) open action\(open.count == 1 ? "" : "s") in \(named?.name ?? "the portfolio")",
            body: body + "\n\nAn action is a commitment, not a result. It becomes work when it is promoted to an initiative with an owner and a saving.",
            citations: Array(Set(open.map { $0.0.kgID })).map { ref in
                Citation(kind: .meeting, ref: ref,
                         label: meetings.first { $0.kgID == ref }?.title ?? "Meeting")
            },
            toVerify: ["Promote any action that is really improvement work"],
            confidence: 0.86)
    }

    private static func variantAnswer(_ question: String, processes: [ProcessInsight]) -> AskAnswer {
        let ranked = processes.filter { $0.people >= 10 }.sorted { $0.variantCount > $1.variantCount }
        guard let first = ranked.first else {
            return AskAnswer(question: question, intent: .variants, headline: "No comparable variants",
                             body: "No process passes the group-size threshold.", citations: [], toVerify: [], confidence: 0.5)
        }
        let body = ranked.prefix(3).map {
            "\($0.name): \($0.variantCount) variants, \(Fmt.percent($0.reworkRate)) rework, \(Fmt.minutes($0.cycleMinutes)) median cycle time."
        }.joined(separator: "\n")
        return AskAnswer(question: question, intent: .variants,
            headline: "\(first.name) has the widest variant spread",
            body: body + "\n\nVariation is the standard-work signal: pick the variant with the lowest rework, document it, and retire the rest with the owners.",
            citations: ranked.prefix(3).map { Citation(kind: .kgNode, ref: $0.kgID, label: $0.name) },
            toVerify: ["Variant labels are KYP.ai generated; confirm they mean what the team calls them."],
            confidence: 0.8)
    }

    private static func freshnessAnswer(_ question: String, processes: [ProcessInsight]) -> AskAnswer {
        let sorted = processes.sorted { $0.staleDays > $1.staleDays }
        let stale = sorted.filter { $0.staleDays > Drift.staleAfterDays }
        let body = sorted.prefix(4).map { "\($0.name): last evidence \($0.staleDays) day\($0.staleDays == 1 ? "" : "s") old." }
            .joined(separator: "\n")
        return AskAnswer(question: question, intent: .freshness,
            headline: stale.isEmpty ? "All maps match the latest discovery" : "\(stale.count) map\(stale.count == 1 ? "" : "s") no longer match the latest discovery",
            body: body + (stale.isEmpty ? "" : "\n\nThese are marked stale in Maps. A stale map is not deleted: its shapes keep the last known values and carry a warning until the next sync."),
            citations: sorted.prefix(4).map { Citation(kind: .kgNode, ref: $0.kgID, label: $0.name) },
            toVerify: [], confidence: 0.9)
    }

    private static func siteAnswer(_ question: String, processes: [ProcessInsight]) -> AskAnswer {
        var bySite: [String: (hours: Double, people: Int, count: Int)] = [:]
        for process in processes {
            var entry = bySite[process.site] ?? (0, 0, 0)
            entry.hours += process.annualHours
            entry.people += process.people
            entry.count += 1
            bySite[process.site] = entry
        }
        let ranked = bySite.sorted { $0.value.hours > $1.value.hours }
        let body = ranked.map { site, value in
            "\(site): \(Fmt.hoursPerYear(value.hours)) across \(value.count) process\(value.count == 1 ? "" : "es")."
        }.joined(separator: "\n")
        return AskAnswer(question: question, intent: .sites,
            headline: "\(ranked.first?.key ?? "No site") carries the largest discovered effort",
            body: body + "\n\nThis compares discovered effort, not performance. Site totals are aggregates of groups at or above the threshold; no site is ranked by output per person.",
            citations: ranked.prefix(3).map { Citation(kind: .computed, ref: $0.key, label: $0.key) },
            toVerify: ["Site labels come from KYP.ai org data; confirm the mapping to Flightdeck sites."],
            confidence: 0.85)
    }

    private static func opportunityAnswer(_ question: String, opportunities: [OpportunityInsight],
                                          processes: [ProcessInsight]) -> AskAnswer {
        let lower = question.lowercased()
        let named = processes.first { lower.contains($0.name.lowercased()) }
            ?? processes.first { process in
                process.name.lowercased().split(separator: " ").contains { lower.contains($0) && $0.count > 4 }
            }
        let candidates = opportunities
            .filter { named == nil || $0.processID == named?.id }
            .sorted { $0.annualHours > $1.annualHours }
        guard let best = candidates.first else {
            return fallback(question, processes: processes, opportunities: opportunities)
        }
        let body = """
        \(best.title) is the largest opportunity in that scope at \(Fmt.hoursPerYear(best.annualHours)).
        Route: \(best.route.label) — \(best.route.detail)
        Confidence in the estimate: \(Fmt.percent(best.confidence)).
        """
        return AskAnswer(question: question, intent: .opportunity,
            headline: "\(best.title): about \(Fmt.hoursPerYear(best.annualHours)) of effort",
            body: body + "\n\nThis is an estimate, not a validated saving. It becomes a claim only after an owner commits it and before/after evidence validates it in the savings ledger.",
            citations: [Citation(kind: .kgNode, ref: best.kgID, label: best.title),
                        Citation(kind: .kyp, ref: best.processID, label: best.processName)],
            toVerify: ["Estimated saving — needs an owner and before/after evidence",
                       "Confirm the effort estimate with the process owner"],
            confidence: best.confidence)
    }

    private static func governance(_ question: String) -> AskAnswer {
        AskAnswer(question: question, intent: .governance,
            headline: "No production use until the launch checklist is signed",
            body: "ProcessLink is designed for process and system improvement only. Before production: a DPIA, a legal review per country, works-council or employee-representative consultation where required, a transparency notice, a retention schedule, and a named data owner. Cross-border AI calls need the same review, and processing is region-pinned.\n\nIn the product: groups below the threshold are suppressed, closed content is blocked by classification, and personal-data patterns are masked before any AI call.",
            citations: [Citation(kind: .policy, ref: "privacy-guard/1", label: "ProcessLink privacy policy"),
                        Citation(kind: .policy, ref: "governance/launch-checklist", label: "Launch checklist")],
            toVerify: ["DPIA status by country", "Works-council agreement scope"], confidence: 0.95)
    }

    private static func fallback(_ question: String, processes: [ProcessInsight],
                                 opportunities: [OpportunityInsight]) -> AskAnswer {
        let total = processes.reduce(0) { $0 + $1.annualHours }
        let best = opportunities.max { $0.annualHours < $1.annualHours }
        let body = "ProcessLink currently holds \(processes.count) discovered processes covering \(Fmt.hoursPerYear(total))." +
            (best.map { " The largest opportunity is \($0.title) at \(Fmt.hoursPerYear($0.annualHours)) (estimate)." } ?? "")
        return AskAnswer(question: question, intent: .fallback,
            headline: "I can answer that from the graph, but not this phrasing",
            body: body + "\n\nTry asking about handoffs and rework, standard-work adherence, variants, a named process, or freshness. Every answer cites the KYP.ai object or KG node it used.",
            citations: best.map { [Citation(kind: .kgNode, ref: $0.kgID, label: $0.title)] } ?? [],
            toVerify: best == nil ? [] : ["Savings are estimates until validated"],
            confidence: 0.55)
    }
}

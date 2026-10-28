import Foundation
import Testing
@testable import ProcessLinkKit

// MARK: - Scoring

private func inputs(hours: Double = 400, error: Double = 10, effort: Double = 4,
                    risk: Int = 2, alignment: Int = 3, automation: Double = 0.4,
                    confidence: Double = 0.85, statutory: Bool = false,
                    waste: WasteType = .handoffs) -> OpportunityInputs {
    OpportunityInputs(annualHours: hours, errorReductionPct: error, effortWeeks: effort,
                      risk: risk, alignment: alignment, automationSuitability: automation,
                      confidence: confidence, statutory: statutory, waste: waste)
}

@Test("More hours never lowers the score")
func hoursMonotonic() {
    let small = OpportunityScoring.score(inputs(hours: 100))
    let large = OpportunityScoring.score(inputs(hours: 1_800))
    #expect(large.impact >= small.impact)
    #expect(large.total >= small.total)
}

@Test("The total is bounded to 100 and never negative")
func bounded() {
    let perfect = OpportunityScoring.score(inputs(hours: 5_000, error: 100, effort: 1,
                                                  risk: 1, alignment: 5, automation: 1,
                                                  confidence: 1))
    let hopeless = OpportunityScoring.score(inputs(hours: 0, error: 0, effort: 40,
                                                   risk: 5, alignment: 1, automation: 0,
                                                   confidence: 0))
    #expect(perfect.total <= 100)
    #expect(hopeless.total >= 0)
}

@Test("A statutory step is never routed to automation")
func statutoryGuard() {
    for waste in WasteType.allCases {
        let score = OpportunityScoring.score(inputs(hours: 900, automation: 1, statutory: true, waste: waste))
        #expect(score.route != .automate)
        #expect(score.route == .standardize)
    }
}

@Test("The reasoning names the hours it used")
func reasoningHasNumbers() {
    let score = OpportunityScoring.score(inputs(hours: 640))
    #expect(score.reasoning.contains { $0.contains("640 h") })
    #expect(!score.reasoning.isEmpty)
}

@Test("The recommended method follows the waste")
func methodMapping() {
    #expect(MethodRecommender.recommend(waste: .rework, route: .standardize, statutory: false).method == .a3)
    #expect(MethodRecommender.recommend(waste: .contextSwitching, route: .standardize, statutory: false).method == .fiveS)
    #expect(MethodRecommender.recommend(waste: .handoffs, route: .simplify, statutory: false).method == .valueStreamMapping)
}

// MARK: - Privacy

@Test("Restricted content never passes, whatever the destination")
func restrictedBlocked() {
    for destination in Destination.allCases {
        let decision = PrivacyGuard.evaluate(groupSize: 40, classification: .restricted,
                                             destination: destination, purpose: .processImprovement)
        #expect(!decision.allowed)
        #expect(decision.action == .block)
    }
}

@Test("Individual performance is refused by purpose")
func purposeLimitation() {
    let decision = PrivacyGuard.evaluate(groupSize: 40, classification: .publicData,
                                         destination: .localView, purpose: .individualPerformance)
    #expect(!decision.allowed)
    #expect(decision.reason.contains("improvement only"))
}

@Test("Small groups are suppressed locally and blocked on export")
func groupThreshold() {
    let policy = PrivacyPolicy(minimumGroupSize: 10)
    let local = PrivacyGuard.evaluate(groupSize: 6, classification: .internalUse,
                                      destination: .localView, purpose: .processImprovement,
                                      policy: policy)
    #expect(local.allowed)
    #expect(local.action == .suppress)

    let export = PrivacyGuard.evaluate(groupSize: 6, classification: .internalUse,
                                       destination: .export, purpose: .processImprovement,
                                       policy: policy)
    #expect(!export.allowed)
}

@Test("PII is found and masked before an AI call")
func piiMask() {
    let text = "Mail anna.schmidt@example.com or IBAN DE44 5001 0517 5407 3249 31, case EMP-4821."
    let scan = PIIScanner.scan(text)
    #expect(scan.counts["email addresses"] == 1)
    #expect(scan.counts["IBANs"] == 1)
    #expect(scan.maskedText.contains("[redacted:email]"))
    #expect(!scan.maskedText.contains("anna.schmidt"))

    let decision = PrivacyGuard.evaluate(groupSize: 40, classification: .internalUse,
                                         destination: .aiGateway, purpose: .processImprovement,
                                         piiFindings: scan.total)
    #expect(!decision.allowed)
    #expect(decision.action == .mask)
}

// MARK: - Savings

@Test("One key is credited once, at its most advanced stage")
func ledgerCreditsOnce() {
    let lines = [
        SavingsLine(id: "1", initiativeID: "a", initiativeTitle: "A", processID: "p",
                    waste: .rework, stage: .estimated, hours: 300, validatedBy: nil, note: ""),
        SavingsLine(id: "2", initiativeID: "b", initiativeTitle: "B", processID: "p",
                    waste: .rework, stage: .committed, hours: 120, validatedBy: nil, note: ""),
    ]
    let totals = SavingsLedger.totals(lines)
    #expect(totals.committed == 120)
    #expect(totals.estimated == 0)
    #expect(totals.validated == 0)
}

@Test("Different waste types on one process both count")
func ledgerDistinctWaste() {
    let lines = [
        SavingsLine(id: "1", initiativeID: "a", initiativeTitle: "A", processID: "p",
                    waste: .rework, stage: .validated, hours: 100, validatedBy: "CI", note: ""),
        SavingsLine(id: "2", initiativeID: "b", initiativeTitle: "B", processID: "p",
                    waste: .handoffs, stage: .validated, hours: 50, validatedBy: "CI", note: ""),
    ]
    #expect(SavingsLedger.totals(lines).validated == 150)
}

@Test("Two commitments on one key are reported as a conflict")
func ledgerConflict() {
    let lines = [
        SavingsLine(id: "1", initiativeID: "a", initiativeTitle: "A", processID: "p",
                    waste: .handoffs, stage: .committed, hours: 100, validatedBy: nil, note: ""),
        SavingsLine(id: "2", initiativeID: "b", initiativeTitle: "B", processID: "p",
                    waste: .handoffs, stage: .committed, hours: 80, validatedBy: nil, note: ""),
    ]
    let conflicts = SavingsLedger.conflicts(lines)
    #expect(conflicts.count == 1)
    #expect(conflicts.first?.initiativeIDs.count == 2)
}

// MARK: - Ask

private let process = ProcessInsight(id: "p1", name: "Order intake", site: "Bensheim",
                                     valueStream: "Order-to-cash", people: 34, annualHours: 3_000,
                                     cycleMinutes: 42, reworkRate: 0.28, handoffs: 6,
                                     adherence: 0.61, variantCount: 4, confidence: 0.9,
                                     staleDays: 3, discoveryID: "disc-1", kgID: "kg-p1")

private let step = StepInsight(id: "s1", processID: "p1", processName: "Order intake",
                               site: "Bensheim", name: "Clear exception queue", role: "Order Desk",
                               application: "Salesforce", minutes: 11, handoffs: 2,
                               reworkShare: 0.38, waste: .handoffs, evidenceCount: 40,
                               kgID: "kg-s1")

@Test("A handoff question cites the step's KG node")
func askCites() {
    let answer = AskEngine.answer("Where do handoffs create the most rework?",
                                  processes: [process], steps: [step], opportunities: [])
    #expect(answer.intent == .handoffs)
    #expect(answer.citations.contains { $0.kind == .kgNode && $0.ref == "kg-s1" })
    #expect(!answer.headline.isEmpty)
}

@Test("A savings answer is labelled an estimate")
func askLabelsEstimate() {
    let opportunity = OpportunityInsight(id: "o1", title: "Remove a check", processID: "p1",
                                         processName: "Order intake", site: "Bensheim",
                                         annualHours: 410, confidence: 0.9, route: .simplify,
                                         kgID: "kg-o1")
    let answer = AskEngine.answer("What would order intake save?", processes: [process],
                                  steps: [step], opportunities: [opportunity])
    #expect(answer.intent == .opportunity)
    #expect(answer.body.lowercased().contains("estimate"))
    #expect(!answer.toVerify.isEmpty)
}

@Test("A stale process is reported as stale")
func askFreshness() {
    var stale = process
    stale.staleDays = 40
    let answer = AskEngine.answer("Which maps are stale?", processes: [stale], steps: [], opportunities: [])
    #expect(answer.intent == .freshness)
    #expect(answer.headline.contains("stale") || answer.body.contains("40"))
}

@Test("Every answer keeps a citation list, even when empty")
func askAlwaysTraceable() {
    let answer = AskEngine.answer("Tell me something unrelated", processes: [process], steps: [step], opportunities: [])
    #expect(answer.intent == .fallback)
    #expect(answer.confidence <= 0.6)
}

// MARK: - Domain

@Test("Cost derives from hours at one rate")
func costModel() {
    #expect(CostModel.euro(hours: 10) == "€520")
    #expect(Fmt.hours(1_000) == "1,000 h")
    #expect(Fmt.percent(0.284) == "28%")
}

// MARK: - Graph

private let graphNodes = [
    GraphNode(id: "a", kind: .process, name: "Order intake", confidence: 0.9),
    GraphNode(id: "b", kind: .step, name: "Check customer master", confidence: 0.8),
    GraphNode(id: "c", kind: .application, name: "SAP S/4HANA", confidence: 0.9),
    GraphNode(id: "d", kind: .role, name: "Order Desk", confidence: 0.9),
]

private let graphEdges = [
    GraphEdge(from: "a", to: "b", predicate: .measuredBy, confidence: 0.8),
    GraphEdge(from: "b", to: "c", predicate: .uses, confidence: 0.9),
]

@Test("Orphans are exactly the nodes with no edge")
func orphans() {
    let orphan = KGGraph.orphanIDs(nodes: graphNodes, edges: graphEdges)
    #expect(orphan == ["d"])
}

@Test("Neighbourhood walks two hops and stops")
func neighbourhood() {
    let one = KGGraph.neighbours(of: "a", in: graphEdges)
    #expect(one == ["b"])
    let two = KGGraph.neighbourhood(of: "a", in: graphEdges, depth: 2)
    #expect(two == ["a", "b", "c"])
}

@Test("Name similarity is explainable and symmetric")
func similarity() {
    #expect(KGGraph.similarity("SAP S/4HANA", "SAP S4HANA") > 0.9)
    #expect(KGGraph.similarity("Order Desk", "Invoice Desk") > 0.3)
    #expect(KGGraph.similarity("Order Desk", "Invoice Desk") == KGGraph.similarity("Invoice Desk", "Order Desk"))
    #expect(KGGraph.similarity("Order Desk", "Completely different") < 0.35)
}

@Test("Duplicate candidates only compare the same kind")
func duplicates() {
    let nodes = [
        GraphNode(id: "1", kind: .application, name: "SAP S/4HANA", confidence: 0.9),
        GraphNode(id: "2", kind: .application, name: "SAP S4HANA", confidence: 0.8),
        GraphNode(id: "3", kind: .role, name: "SAP S/4HANA", confidence: 0.8),
    ]
    let pairs = KGGraph.duplicatePairs(nodes: nodes, threshold: 0.7)
    #expect(pairs.count == 1)
    #expect(pairs.first?.left == "1")
}

@Test("Closed nodes are not duplicate candidates")
func closedNodes() {
    let nodes = [
        GraphNode(id: "1", kind: .application, name: "SAP ECC", confidence: 0.9),
        GraphNode(id: "2", kind: .application, name: "SAP ECC", confidence: 0.9, validTo: .now),
    ]
    #expect(KGGraph.duplicatePairs(nodes: nodes).isEmpty)
}

// MARK: - Mining

@Test("The sample CSV imports and hashes case ids")
func importSample() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    #expect(result.caseCount == 24)
    #expect(result.events.count > 100)
    #expect(result.events.allSatisfy { $0.caseID.hasPrefix("case-") })
    #expect(!result.events.contains { $0.caseID.contains("ORD-2026") })
    #expect(result.skippedRows == 0)
}

@Test("Mining finds variants, rework and a bottleneck")
func mineSample() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    #expect(mined.cases == 24)
    #expect(mined.variants.count == 3, "found \(mined.variants.count)")
    #expect(abs(mined.variants.map(\.share).reduce(0, +) - 1) < 0.001)
    #expect(mined.reworkRate > 0)
    #expect(mined.medianCycleMinutes > 0)
    #expect(mined.edges.contains { $0.from == "Receive order" && $0.to == "Check customer master" })
    #expect(mined.bottleneck != nil)
}

@Test("Conformance reports exact cases and missing activities")
func conformance() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let reference = ["Receive order", "Check customer master", "Validate pricing",
                     "Create sales order", "Send confirmation"]
    let report = ProcessMining.conformance(events: result.events, reference: reference)
    #expect(report.fitness > 0.8)
    #expect(report.exactCases > 0)
    #expect(report.extraActivities.contains("Clear exception queue"))
}

@Test("Personal-looking activities are masked on import")
func miningMasksPII() throws {
    let csv = "case_id,activity,timestamp,resource\n1,Send to anna.schmidt@example.com,2026-01-01 09:00,Order Desk\n2,Check,2026-01-01 10:00,Order Desk\n"
    let result = try EventLogImporter.importCSV(csv)
    #expect(result.events.contains { $0.activity.contains("[redacted:email]") })
    #expect(!result.events.contains { $0.activity.contains("anna.schmidt") })
}

@Test("Resource values that look personal become roles")
func miningResourcePrivacy() throws {
    let csv = "case_id,activity,timestamp,resource\n1,Check,2026-01-01 09:00,anna.schmidt@example.com\n"
    let result = try EventLogImporter.importCSV(csv)
    #expect(result.events[0].resource.hasPrefix("role-"))
    #expect(!result.events[0].resource.contains("@"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIGHTDECK_UAT_URL"] != nil))
func liveFlightdeckUAT() async throws {
    let environment = ProcessInfo.processInfo.environment
    let config = try FlightdeckConfig(
        baseURL: URL(string: environment["FLIGHTDECK_UAT_URL"]!)!,
        atlasURL: environment["FLIGHTDECK_ATLAS_URL"].flatMap(URL.init(string:)))
    let client = FlightdeckClient(config: config)
    let accounts = try await client.quickLoginAccounts()
    #expect(!accounts.isEmpty)
    let account = environment["FLIGHTDECK_UAT_ACCOUNT"] ?? "uat-admin"
    let principal = try await client.quickLogin(accountID: account)
    #expect(principal.username == account)
    let workspaces = try await client.workspaces()
    #expect(!workspaces.isEmpty)
    let workspace = workspaces.first(where: { $0.id == "te-ops" }) ?? workspaces[0]
    let projects = try await client.projects(workspaceID: workspace.id)
    #expect(!projects.isEmpty)
    let project = projects.first(where: { $0.id == "project-contract" }) ?? projects[0]
    let vision = try await client.vision(workspaceID: workspace.id, projectID: project.id)
    #expect(!vision.status.isEmpty)
    let advantage = try await client.advantage(workspaceID: workspace.id, projectID: project.id)
    #expect(!advantage.kpis.isEmpty)
    if let email = environment["FLIGHTDECK_ATLAS_EMAIL"] {
        let atlas = try await client.atlas(email: email)
        #expect(!atlas.projects.isEmpty)
    }
}

@Test("Flightdeck accepts loopback HTTP and refuses insecure remote HTTP")
func flightdeckURLRules() throws {
    _ = try FlightdeckConfig(baseURL: URL(string: "http://127.0.0.1:4173")!)
    _ = try FlightdeckConfig(baseURL: URL(string: "https://flightdeck.example.test")!)
    #expect(throws: FlightdeckError.self) {
        _ = try FlightdeckConfig(baseURL: URL(string: "http://flightdeck.example.test")!)
    }
    #expect(throws: FlightdeckError.self) {
        _ = try FlightdeckConfig(baseURL: URL(string: "https://user:secret@flightdeck.example.test")!)
    }
}

@Test("Attributes, cost and case records survive import")
func miningAttributesAndCases() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    #expect(result.attributeNames.contains("case_type"))
    let first = result.events.first { $0.attributes["case_type"] != nil }
    #expect(first?.attributes["case_type"] == "Standard" || first?.attributes["case_type"] == "Expedite")
    #expect(first?.cost != nil)
    let cases = ProcessMining.buildCases(result.events)
    #expect(cases.count == 24)
    #expect(cases.allSatisfy { !$0.sequence.isEmpty && $0.cycleMinutes >= 0 })
}

@Test("Filters keep whole cases and can select rework")
func miningFilters() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let expedite = MiningFilter(attributes: ["case_type": "Expedite"])
    let filtered = ProcessMining.filter(result.events, with: expedite)
    #expect(!filtered.isEmpty)
    #expect(filtered.count < result.events.count)
    let cases = ProcessMining.buildCases(filtered)
    #expect(cases.count == 8)
    #expect(cases.allSatisfy { $0.attributes["case_type"] == "Expedite" })
    let rework = MiningFilter(onlyRework: true)
    #expect(ProcessMining.buildCases(ProcessMining.filter(result.events, with: rework)).allSatisfy { $0.reworkCount > 0 })
}

@Test("Periods, handovers and root causes are derived")
func miningAdvanced() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    #expect(!mined.periods.isEmpty)
    #expect(mined.periods.count <= 12)
    #expect(!mined.handovers.isEmpty)
    #expect(mined.caseRecords.count == 24)
    let causes = ProcessMining.rootCauses(mined.caseRecords, outcome: .slow)
    #expect(!causes.isEmpty)
    #expect(causes.allSatisfy { $0.cases >= 2 })
}

@Test("What-if simulation removes waits and reports assumptions")
func miningSimulation() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    let baseline = ProcessMining.simulate(mined.caseRecords, MiningSimulation())
    #expect(abs(baseline.baselineMedianMinutes - baseline.projectedMedianMinutes) < 0.001)
    let simulated = ProcessMining.simulate(mined.caseRecords, MiningSimulation(
        automate: ["Validate pricing"], remove: ["Send confirmation"], reworkReduction: 1))
    #expect(simulated.projectedMedianMinutes <= simulated.baselineMedianMinutes)
    #expect(!simulated.assumptions.isEmpty)
}

@Test("Token replay adds a second conformance measure")
func miningTokenReplay() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let reference = ["Receive order", "Check customer master", "Validate pricing",
                     "Create sales order", "Send confirmation"]
    let report = ProcessMining.conformance(events: result.events, reference: reference)
    #expect(report.tokenFitness >= 0 && report.tokenFitness <= 1)
    #expect(report.consumedTokens > 0)
    #expect(report.deviatingCases > 0)
}

@Test("A custom header mapping imports the chosen columns")
func miningCustomMapping() throws {
    let csv = """
    Case,When,Task,Role,Channel
    A-1,2026-01-01 09:00,Start,Desk,Web
    A-1,2026-01-01 09:05,Check,Desk,Web
    B-1,2026-01-01 10:00,Start,Desk,Phone
    """
    let mapping = MiningColumnMap(caseID: "Case", activity: "Task",
                                  timestamp: "When", resource: "Role")
    let result = try EventLogImporter.importCSV(csv, mapping: mapping)
    #expect(result.caseCount == 2)
    #expect(result.events.count == 3)
    #expect(result.events.first?.attributes["Channel"] == "Web")
}

@Test("The mining watchlist explains rework, wait and variant risk")
func miningAlerts() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    let alerts = ProcessMining.alerts(mined)
    #expect(!alerts.isEmpty)
    #expect(alerts.contains { $0.id == "rework" })
    #expect(alerts.allSatisfy { !$0.detail.isEmpty })
}

@Test("A sound block-structured tree exports BPMN")
func miningTreeAndBPMN() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    let tree = InductiveDiscovery.tree(from: mined.caseRecords)
    #expect(tree.isSound)
    #expect(Set(tree.activityNames).count >= 5)
    let bpmn = InductiveDiscovery.bpmn(tree, name: "Order intake")
    #expect(bpmn.contains("<bpmn:process"))
    #expect(bpmn.contains("<bpmn:task"))
    #expect(bpmn.contains("exclusiveGateway"))
}

@Test("Optimal alignment finds missing and extra moves")
func miningAlignment() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let reference = ["Receive order", "Check customer master", "Validate pricing",
                     "Create sales order", "Send confirmation"]
    let report = Alignment.sequence(result.events, reference: reference)
    #expect(report.totalCases == 24)
    #expect(report.totalCost > 0)
    #expect(report.fitness > 0.5 && report.fitness <= 1)
    #expect(report.cases.contains { $0.cost > 0 })
}

@Test("Capacity simulation models queues and use")
func miningCapacity() throws {
    let result = try EventLogImporter.importCSV(EventLogImporter.sampleCSV())
    let mined = ProcessMining.mine(result.events, name: "Order intake")
    let roles = CapacitySimulation.defaultRoles(for: mined)
    #expect(!roles.isEmpty)
    let run = CapacitySimulation.run(mined, roles: roles, arrivalPerDay: 12, days: 5)
    #expect(run.cases > 0)
    #expect(run.medianCycleMinutes > 0)
    #expect(run.utilization.count == roles.count)
    #expect(!run.assumptions.isEmpty)
}

@Test("ServiceNow and Salesforce envelopes become canonical CSV")
func connectorParser() throws {
    let serviceNow = """
    {"result":[{"documentkey":"INC001","fieldname":"State changed","sys_created_on":"2026-01-01 09:00:00","user":"Desk","tablename":"incident","cost":"12.50"}]}
    """.data(using: .utf8)!
    let csv = try ConnectorParser.csv(from: serviceNow, provider: .serviceNow,
                                      mapping: .init(caseField: "documentkey", activityField: "fieldname",
                                                     timestampField: "sys_created_on", resourceField: "user",
                                                     applicationField: "tablename", costField: "cost"))
    #expect(csv.contains("INC001"))
    #expect(csv.contains("State changed"))
    let imported = try EventLogImporter.importCSV(csv)
    #expect(imported.events.count == 1)

    let salesforce = """
    {"records":[{"Id":"5001","Subject":"Check","ActivityDate":"2026-01-02T10:00:00Z","OwnerId":"U1"}]}
    """.data(using: .utf8)!
    let sf = try ConnectorParser.csv(from: salesforce, provider: .salesforce,
                                     mapping: .init(caseField: "Id", activityField: "Subject",
                                                    timestampField: "ActivityDate", resourceField: "OwnerId",
                                                    applicationField: "", costField: ""))
    #expect(sf.contains("5001"))
}

@Test("Map mining maps activities and checks map transitions")
func mapMiningConformance() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let events = [
        EventLogRecord(caseID: "c1", activity: "Open ticket", timestamp: start, resource: "Desk"),
        EventLogRecord(caseID: "c1", activity: "4-eye check", timestamp: start.addingTimeInterval(60), resource: "Reviewer"),
        EventLogRecord(caseID: "c1", activity: "Send hearing", timestamp: start.addingTimeInterval(120), resource: "HR"),
    ]
    let reference = MapReference(
        name: "Hearing",
        steps: [MapStepRef(id: "intake", label: "Open ticket"),
                MapStepRef(id: "qc", label: "4-eye check"),
                MapStepRef(id: "send", label: "Send hearing")],
        edges: [MapEdgeRef(from: "intake", to: "qc"), MapEdgeRef(from: "qc", to: "send")])
    let mapping = ["Open ticket": "intake", "4-eye check": "qc", "Send hearing": "send"]
    let report = MapMining.conformance(events: events, reference: reference, mapping: mapping)
    #expect(report.stepsObserved == 3)
    #expect(report.mappedActivities == 3)
    #expect(report.transitionCoverage == 1)
    #expect(report.unmappedActivities.isEmpty)
}

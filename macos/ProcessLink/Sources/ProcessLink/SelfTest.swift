import AppKit
import ProcessLinkKit
import SwiftData

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with 0 or 1.
///   APP_STORE=/tmp/ProcessLink-self.store ~/Applications/ProcessLink.app/Contents/MacOS/ProcessLink --selftest
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(0.3))
            let context = model.container.mainContext

            func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
                (try? context.fetch(FetchDescriptor<T>())) ?? []
            }

            if fetch(ProcessRecord.self).isEmpty { SeedData.seed(into: model) }

            let processes = fetch(ProcessRecord.self)
            let opportunities = fetch(OpportunityRecord.self)
            check("seed has the seven processes", processes.count == 7, "found \(processes.count)")
            check("seed has the opportunity pipeline", opportunities.count >= 12, "found \(opportunities.count)")

            // Strategy and mandatory links.
            let strategies = fetch(StrategyRecord.self)
            let bets = fetch(StrategicBetRecord.self)
            let kpis = fetch(KPIRecord.self)
            let values = fetch(ValueRecord.self)
            check("a function vision exists", strategies.count == 1)
            check("strategic bets, KPIs and values exist",
                  bets.count >= 4 && kpis.count >= 5 && values.count >= 4,
                  "bets \(bets.count), KPIs \(kpis.count), values \(values.count)")
            let seededInitiatives = fetch(InitiativeRecord.self)
            check("every seeded initiative has a bet, KPI and value",
                  !seededInitiatives.isEmpty && seededInitiatives.allSatisfy(\.hasStrategyLink),
                  "\(seededInitiatives.filter { $0.hasStrategyLink }.count) of \(seededInitiatives.count) linked")

            if let initiative = seededInitiatives.first {
                if let handoff = model.generateAutomationHandoff(for: initiative) {
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: handoff.packagePath)) ?? []
                    check("automation handoff writes the package",
                          files.contains("automation.json") && files.contains("agent.py"), "\(files)")
                    check("automation handoff starts un-deployed", handoff.statusRaw == "ready")
                    model.setAutomationStatus(handoff, status: "retired")
                    check("automation handoff status is tracked", handoff.statusRaw == "retired")
                } else {
                    check("automation handoff can be generated", false)
                }
            }

            // Feedback: anchored, threaded, mention-parsed and resolvable.
            if let note = model.addFeedback(kind: .process, subjectID: "p-order-intake",
                                            subjectLabel: "Order intake & validation",
                                            body: "Please review @Ops Excellence Lead") {
                check("feedback parses an @mention", note.mentions == ["@Ops"], "\(note.mentions)")
                let reply = model.addFeedback(kind: .process, subjectID: "p-order-intake",
                                              subjectLabel: "Order intake & validation",
                                              body: "Confirmed.", parentID: note.id)
                check("feedback replies attach to their thread", reply?.parentID == note.id)
                model.setFeedbackResolved(note, resolved: true)
                check("feedback can be resolved", note.resolved)
                model.deleteFeedback(note)
                check("deleting a thread removes its replies",
                      !((try? context.fetch(FetchDescriptor<FeedbackRecord>())) ?? []).contains { $0.id == reply?.id })
            } else {
                check("feedback can be added", false)
            }

            // Meetings and their graph facts.
            let meetings = fetch(MeetingRecord.self)
            let meetingBlocks = fetch(MeetingBlockRecord.self)
            check("seed has meeting pages", meetings.count == 5, "found \(meetings.count)")
            check("meeting pages have decisions", meetingBlocks.filter { $0.kind == .decision }.count >= 3)
            check("meeting pages have open actions", meetingBlocks.contains { $0.kind == .action && !$0.checked })
            if let huddle = meetings.first(where: { $0.id == "meet-huddle-triage" }) {
                check("a meeting is a graph node",
                      fetch(KGNodeRecord.self).contains { $0.id == huddle.kgID && $0.kind == .meeting })
                check("a meeting links to its process",
                      fetch(KGEdgeRecord.self).contains {
                          $0.fromID == "kg-proc-p-triage" && $0.predicate == .discussedIn && $0.toID == huddle.kgID
                      })
                check("a decision is documented in its meeting",
                      fetch(KGNodeRecord.self).contains { $0.kind == .decision && $0.processID == "p-triage" })
            }

            // Privacy guard.
            let restricted = PrivacyGuard.evaluate(groupSize: 14, classification: .restricted,
                                                   destination: .localView, purpose: .processImprovement)
            check("restricted data is blocked even locally", !restricted.allowed && restricted.action == .block)

            let smallGroup = PrivacyGuard.evaluate(groupSize: 4, classification: .internalUse,
                                                   destination: .export, purpose: .processImprovement,
                                                   policy: PrivacyPolicy(minimumGroupSize: 10))
            check("a group below the threshold cannot be exported", !smallGroup.allowed)

            let display = PrivacyGuard.canDisplay(groupSize: 4, classification: .internalUse,
                                                  policy: PrivacyPolicy(minimumGroupSize: 10))
            check("a small group is suppressed on screen", !display)

            let performance = PrivacyGuard.evaluate(groupSize: 30, classification: .internalUse,
                                                    destination: .aiGateway, purpose: .individualPerformance)
            check("individual performance use is refused by purpose", !performance.allowed)

            // PII.
            let scan = PIIScanner.scan("Contact anna.schmidt@example.com about case EMP-4821.")
            check("PII scan finds an e-mail and an employee id", scan.total >= 2, scan.summary)
            check("PII scan masks the e-mail", scan.maskedText.contains("[redacted:email]"), scan.maskedText)

            // Scoring.
            let base = OpportunityInputs(annualHours: 200, errorReductionPct: 5, effortWeeks: 4,
                                         risk: 2, alignment: 3, automationSuitability: 0.3,
                                         confidence: 0.8, statutory: false, waste: .handoffs)
            let larger = OpportunityInputs(annualHours: 900, errorReductionPct: 5, effortWeeks: 4,
                                           risk: 2, alignment: 3, automationSuitability: 0.3,
                                           confidence: 0.8, statutory: false, waste: .handoffs)
            check("more hours never lowers the score",
                  OpportunityScoring.score(larger).total >= OpportunityScoring.score(base).total)
            check("the score is bounded to 100", OpportunityScoring.score(larger).total <= 100)
            check("the score explains itself", !OpportunityScoring.score(larger).reasoning.isEmpty)

            var statutory = base
            statutory.statutory = true
            statutory.waste = .overProcessing
            check("a statutory step is never routed to automation",
                  OpportunityScoring.score(statutory).route != .automate)

            // Savings ledger.
            let lines = [
                SavingsLine(id: "a", initiativeID: "ini-a", initiativeTitle: "A", processID: "p1",
                            waste: .handoffs, stage: .estimated, hours: 100, validatedBy: nil, note: ""),
                SavingsLine(id: "b", initiativeID: "ini-b", initiativeTitle: "B", processID: "p1",
                            waste: .handoffs, stage: .committed, hours: 100, validatedBy: nil, note: ""),
            ]
            let totals = SavingsLedger.totals(lines)
            check("a key counts once at its most advanced stage",
                  totals.committed == 100 && totals.estimated == 0,
                  "committed \(totals.committed), estimated \(totals.estimated)")

            let conflicted = lines + [SavingsLine(id: "c", initiativeID: "ini-c", initiativeTitle: "C",
                                                  processID: "p1", waste: .handoffs, stage: .committed,
                                                  hours: 60, validatedBy: nil, note: "")]
            check("two initiatives on one key are a conflict", SavingsLedger.conflicts(conflicted).count == 1)

            // Ask.
            let handoff = AskEngine.answer("Where do handoffs create the most rework?",
                                           processes: processes.map { process in
                ProcessInsight(id: process.id, name: process.name, site: process.site,
                               valueStream: process.valueStream, people: process.people,
                               annualHours: process.annualHours, cycleMinutes: process.cycleMinutes,
                               reworkRate: process.reworkRate, handoffs: process.handoffs,
                               adherence: process.adherence, variantCount: process.variantCount,
                               confidence: process.confidence, staleDays: process.staleDays,
                               discoveryID: process.discoveryID, kgID: process.kgID)
            }, steps: fetch(StepRecord.self).map { step in
                StepInsight(id: step.id, processID: step.processID, processName: "",
                            site: "", name: step.name, role: step.role, application: step.application,
                            minutes: step.minutes, handoffs: step.handoffs,
                            reworkShare: step.reworkShare, waste: step.waste,
                            evidenceCount: step.evidenceCount, kgID: step.kgID)
            }, opportunities: [])
            check("the handoff answer cites a KG node",
                  handoff.citations.contains { $0.kind == .kgNode })

            // Promotion, savings lifecycle, and the blocked path.
            guard let pricing = opportunities.first(where: { $0.id == "opp-pricing-check" }),
                  let orderIntake = processes.first(where: { $0.id == "p-order-intake" }) else {
                check("the pricing opportunity exists", false)
                finish(code: 1)
                return
            }
            let initiative = model.promote(pricing, process: orderIntake)
            check("promotion creates an initiative", initiative != nil)
            check("promotion moves the opportunity out of the queue",
                  pricing.status == .promoted)
            if let initiative {
                check("promotion writes an initiative node",
                      fetch(KGNodeRecord.self).contains { $0.id == "kg-ini-\(initiative.id)" && $0.kind == .initiative })
                check("promotion writes the addressed_by edge",
                      fetch(KGEdgeRecord.self).contains {
                          $0.fromID == "kg-opp-opp-pricing-check" && $0.predicate == .addressedBy
                              && $0.toID == "kg-ini-\(initiative.id)"
                      })
                check("promotion writes a savings record",
                      fetch(KGNodeRecord.self).contains { $0.id == "kg-savings-\(initiative.id)" })
            }

            if let initiative {
                check("a new initiative inherits a strategy link", initiative.hasStrategyLink)
            check("a new saving starts as an estimate", initiative.savingsStage == .estimated)
                model.commitSavings(initiative)
                check("an owner can commit the saving", initiative.savingsStage == .committed)

                model.validateSavings(initiative, validator: "CI Manager", evidence: "too short")
                check("validation refuses evidence that is too thin", initiative.savingsStage == .committed)

                model.validateSavings(initiative, validator: "CI Manager",
                                      evidence: "Before 34% rework over 8 weeks; after 11% over 6 weeks; 410 h confirmed.")
                check("validation records the validator and the evidence",
                      initiative.savingsStage == .validated && initiative.validatedBy == "CI Manager")
            }

            if let blocked = opportunities.first(where: { $0.id == "opp-export-precheck" }),
               let export = processes.first(where: { $0.id == "p-export" }) {
                let refused = model.promote(blocked, process: export)
                check("a Restricted process cannot be promoted", refused == nil)
            }

            // Local discovery refresh (no external connector).
            let beforeSync = fetch(SyncRecord.self).count
            await model.runSync()
            let afterSync = fetch(SyncRecord.self).count
            check("a local refresh records its scope", afterSync > beforeSync,
                  "\(beforeSync) → \(afterSync)")
            let audits = fetch(AuditRecord.self)
            check("the refresh is audited", audits.contains { $0.action == "discovery.refreshed" })

            // Entity resolution needs a human.
            if let ecc = fetch(KGNodeRecord.self).first(where: { $0.id == "kg-app-sap-ecc" }),
               let target = fetch(KGNodeRecord.self).first(where: { $0.id == "kg-app-sap-s4hana" }) {
                model.confirmKGNode(ecc, mergeInto: target.id)
                check("a merge records the human decision",
                      ecc.review == .rejected && ecc.note.contains("Merged into"))
                check("a merge closes the losing node", ecc.validTo != nil)
                check("a merge moves or drops every edge",
                      !fetch(KGEdgeRecord.self).contains { $0.fromID == "kg-app-sap-ecc" || $0.toID == "kg-app-sap-ecc" })
            }

            // Access control: no blocked process may enter the ask context.
            let visibleForAsk = processes.filter {
                $0.status != .blocked && PrivacyGuard.canDisplay(groupSize: $0.people,
                                                                 classification: $0.classification,
                                                                 policy: model.policy)
            }
            check("the restricted process never enters the ask context",
                  !visibleForAsk.contains { $0.id == "p-export" })

            // Flightdeck Maps: documents, bindings, drift and persistence.
            MapsBridge.seedIfNeeded(processes: processes, steps: fetch(StepRecord.self))
            let maps = MapsBridge.loadAll()
            check("seeded Flightdeck maps", maps.count >= 2, "found \(maps.count)")
            if let order = maps.first(where: { $0.processID == "p-order-intake" }) {
                check("map shapes are bound to KG steps", order.boundNodes >= 5, "bound \(order.boundNodes)")
                check("map is a signavio-map/1 document", order.json["schema"] as? String == "signavio-map/1")
                let drifted = order.nodes.contains { node in
                    guard let link = node.link, let step = fetch(StepRecord.self).first(where: { $0.id == link.stepID }) else { return false }
                    return node.role != step.role
                }
                check("a human map edit is visible as drift", drifted)
                if let target = order.nodes.first(where: { $0.link != nil }) {
                    let edited = MapsBridge.updateNode(order, nodeID: target.id, label: target.label,
                                                       role: "Map Edited Role", system: target.system,
                                                       estimateMin: (target.estimateMin ?? 0) + 1)
                    try? MapsBridge.save(edited)
                    let reloaded = MapsBridge.loadAll().first { $0.id == order.id }
                    check("a map edit persists in the document",
                          reloaded?.nodes.first { $0.id == target.id }?.role == "Map Edited Role")
                }
                model.registerMap(order, process: processes.first { $0.id == order.processID })
                check("a map is a graph node",
                      fetch(KGNodeRecord.self).contains { $0.id == "kg-map-\(order.id)" && $0.kind == .map })
                check("the map is documented in the process",
                      fetch(KGEdgeRecord.self).contains {
                          $0.fromID == "kg-proc-p-order-intake" && $0.predicate == .documentedIn
                              && $0.toID == "kg-map-\(order.id)"
                      })
            }

            // Creating a meeting writes blocks and graph facts.
            let created = model.createMeeting(kind: .a3Review, processID: "p-invoice")
            check("a new meeting gets template blocks", model.blocks(for: created).count >= 6)
            check("a new meeting is a graph node",
                  fetch(KGNodeRecord.self).contains { $0.id == created.kgID })
            let decisionBlock = model.addBlock(to: created, kind: .decision)
            model.refreshBlockNode(decisionBlock, meeting: created)
            check("a decision block becomes a graph node",
                  fetch(KGNodeRecord.self).contains {
                      $0.id == "kg-decision-\(decisionBlock.id)" && $0.kind == .decision
                  })
            if let action = model.blocks(for: created).first(where: { $0.kind == .action }) {
                let beforeAction = fetch(InitiativeRecord.self).count
                let promoted = model.promoteAction(action, meeting: created)
                check("promoting a meeting action creates an initiative",
                      promoted != nil && fetch(InitiativeRecord.self).count == beforeAction + 1)
                check("the action is marked done", action.checked)
            }

            // Ask uses the meeting notes, not a separate store.
            let meetingInsights = meetings.map { meeting -> MeetingInsight in
                let meetingBlocks = fetch(MeetingBlockRecord.self).filter { $0.meetingID == meeting.id }
                let processName = processes.first { $0.id == meeting.processID }?.name ?? ""
                return MeetingInsight(
                    id: meeting.id, title: meeting.title, date: meeting.date,
                    kind: meeting.kind.label, site: meeting.site, processName: processName,
                    decisions: meetingBlocks.filter { $0.kind == .decision }.map {
                        MeetingItemInsight(id: $0.id, text: $0.text, owner: $0.owner, done: $0.checked)
                    },
                    actions: meetingBlocks.filter { $0.kind == .action }.map {
                        MeetingItemInsight(id: $0.id, text: $0.text, owner: $0.owner,
                                           done: $0.checked, due: $0.due)
                    },
                    kgID: meeting.kgID)
            }
            let decisionAnswer = AskEngine.answer("What did we decide about pricing?",
                                                  processes: [], steps: [], opportunities: [],
                                                  meetings: meetingInsights)
            check("a decision question is answered from meeting notes",
                  decisionAnswer.intent == .decisions)
            check("a decision answer cites a meeting",
                  decisionAnswer.citations.contains { $0.kind == .meeting })

            // In-house discovery: import, mine, create a process.
            let dataset = model.importSampleDataset()
            check("the sample event log imports", dataset != nil)
            if let dataset {
                check("case ids are hashed on import",
                      !fetch(EventItemRecord.self).contains { $0.caseHash.contains("ORD-2026") })
                let mined = model.minedProcess(for: dataset)
                check("imported attributes survive storage",
                      model.events(for: dataset).contains { $0.attributes["case_type"] != nil })
                check("mining exposes case records and periods",
                      mined.caseRecords.count == 24 && !mined.periods.isEmpty)
                let whatIf = ProcessMining.simulate(mined.caseRecords,
                                                    MiningSimulation(remove: ["Send confirmation"]))
                check("the what-if projection is bounded by the baseline",
                      whatIf.projectedMedianMinutes <= whatIf.baselineMedianMinutes)
                check("mining finds 24 cases", mined.cases == 24, "found \(mined.cases)")
                check("mining finds three variants", mined.variants.count == 3, "found \(mined.variants.count)")
                let discovered = model.createProcess(from: dataset)
                check("mining creates a process", discovered != nil)
                check("the process is labelled in-house",
                      discovered?.source == "In-house process mining")
                if let discovered {
                    let processSteps = fetch(StepRecord.self).filter { $0.processID == discovered.id }
                    check("the mined process has steps", processSteps.count >= 4, "found \(processSteps.count)")
                    check("the mined process has variants",
                          fetch(VariantRecord.self).contains { $0.processID == discovered.id })
                    check("the mined process has an opportunity",
                          fetch(OpportunityRecord.self).contains { $0.processID == discovered.id })
                    check("the mined process is a KG node",
                          fetch(KGNodeRecord.self).contains { $0.id == "kg-proc-\(discovered.id)" })
                }
            }

            // In-house task capture: aggregate, save, turn into a process.
            model.recordCapture(name: "Self-test capture", role: "Order Desk", site: "Bensheim",
                                startedAt: model.now, endedAt: model.now,
                                minutes: 30, idleMinutes: 4, switchCount: 12,
                                apps: [("Outlook", "com.microsoft.Outlook", 12, 1, 4),
                                       ("SAP S/4HANA", "com.sap.s4", 14, 2, 5)])
            if let session = fetch(CaptureSessionRecord.self).first(where: { $0.name == "Self-test capture" }) {
                let captureApps = fetch(CaptureAppRecord.self).filter { $0.sessionID == session.id }
                check("a capture session stores app aggregates", captureApps.count == 2)
                let captureProcess = model.createProcess(from: session, apps: captureApps)
                check("a capture becomes a process", captureProcess != nil)
                check("the capture process is labelled in-house",
                      captureProcess?.source == "In-house task capture")
            }

            check("the connection layer registers OS, Vision and Atlas",
                  model.flightdeck.health.count == 3)
            check("the connection layer defaults to the local UAT endpoint",
                  model.flightdeck.baseURLString == "http://127.0.0.1:4173")

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

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
                               kypID: process.kypID, kgID: process.kgID)
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

            // Sync.
            let beforeSync = fetch(OpportunityRecord.self).count
            await model.runSync()
            let afterSync = fetch(OpportunityRecord.self).count
            check("a sync adds the next sandbox batch", afterSync > beforeSync,
                  "\(beforeSync) → \(afterSync)")
            let audits = fetch(AuditRecord.self)
            check("the sync is audited", audits.contains { $0.action == "sync.completed" })

            // Entity resolution needs a human.
            if let ecc = fetch(KGNodeRecord.self).first(where: { $0.id == "kg-app-sap-ecc" }),
               let target = fetch(KGNodeRecord.self).first(where: { $0.id == "kg-app-sap-s4hana" }) {
                model.confirmKGNode(ecc, mergeInto: target.id)
                check("a merge records the human decision",
                      ecc.review == .rejected && ecc.note.contains("Merged into"))
            }

            // Access control: no blocked process may enter the ask context.
            let visibleForAsk = processes.filter {
                $0.status != .blocked && PrivacyGuard.canDisplay(groupSize: $0.people,
                                                                 classification: $0.classification,
                                                                 policy: model.policy)
            }
            check("the restricted process never enters the ask context",
                  !visibleForAsk.contains { $0.id == "p-export" })

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

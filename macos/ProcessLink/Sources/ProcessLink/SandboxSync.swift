import Foundation
import ProcessLinkKit

/// The offline stand-in for the `kyp-connector` sync worker. Each call returns
/// the next prepared incremental batch from the sandbox, in the same shape the
/// real connector will produce: aggregated opportunities, never raw capture.
enum SandboxSync {
    struct Batch {
        var fetched: Int
        var skipped: Int
        var note: String
        var opportunities: [OpportunityRecord]
    }

    static func nextBatch(after count: Int, now: Date = .now) -> Batch {
        switch count % 3 {
        case 0:
            return Batch(fetched: 341, skipped: 2,
                         note: "Incremental window 02:00–08:00. 2 groups below threshold skipped.",
                         opportunities: [
                            opportunity(id: "opp-sync-password", title: "Deflect password-reset cases to self-service",
                                        processID: "p-triage", processName: "Customer case triage", site: "Manila",
                                        waste: .unusedTalent, method: .kaizen, route: .automate,
                                        hours: 310, error: 6, effort: 6, risk: 3, alignment: 3,
                                        automation: 0.75, confidence: 0.81, statutory: false,
                                        rationale: "31% of portal cases are password resets. Each takes 11 minutes of resolver time and needs no judgement.\nA self-service flow removes the case before it is created.",
                                        owner: "Customer Care Lead", now: now),
                            opportunity(id: "opp-sync-bank", title: "Validate supplier bank details at intake",
                                        processID: "p-supplier", processName: "Supplier master data maintenance", site: "Guadalajara",
                                        waste: .defects, method: .errorProofing, route: .simplify,
                                        hours: 150, error: 24, effort: 2, risk: 4, alignment: 2,
                                        automation: 0.55, confidence: 0.77, statutory: false,
                                        rationale: "Bank-data corrections are found at payment time, after the supplier is live.\nAn IBAN checksum at intake moves the check before the cost.",
                                        owner: "Master Data Steward", now: now),
                         ])
        case 1:
            return Batch(fetched: 296, skipped: 3,
                         note: "Incremental window 08:00–14:00. 3 groups below threshold skipped.",
                         opportunities: [
                            opportunity(id: "opp-sync-preboarding", title: "Pre-boarding checklist before day one",
                                        processID: "p-onboarding", processName: "Employee onboarding administration", site: "Manila",
                                        waste: .waiting, method: .standardWork, route: .standardize,
                                        hours: 220, error: 9, effort: 3, risk: 2, alignment: 3,
                                        automation: 0.30, confidence: 0.79, statutory: false,
                                        rationale: "Documents requested on the first day add an average of four days to the admin lead time.\nA checklist sent with the offer removes the wait without changing any control.",
                                        owner: "HR Services Lead", now: now),
                         ])
        default:
            return Batch(fetched: 274, skipped: 1,
                         note: "Incremental window complete. No new opportunities.",
                         opportunities: [])
        }
    }

    private static func opportunity(id: String, title: String, processID: String, processName: String,
                                    site: String, waste: WasteType, method: TEOMethod, route: Route,
                                    hours: Double, error: Double, effort: Double, risk: Int,
                                    alignment: Int, automation: Double, confidence: Double,
                                    statutory: Bool, rationale: String, owner: String,
                                    now: Date) -> OpportunityRecord {
        OpportunityRecord(id: id, title: title, processID: processID, processName: processName,
                          site: site, waste: waste, method: method, route: route,
                          annualHours: hours, errorReductionPct: error, effortWeeks: effort,
                          risk: risk, alignment: alignment, automation: automation,
                          confidence: confidence, statutory: statutory, rationale: rationale,
                          kgID: "kg-opp-\(id)", ownerRole: owner, createdAt: now)
    }
}

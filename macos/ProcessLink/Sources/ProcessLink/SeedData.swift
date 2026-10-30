import Foundation
import ProcessLinkKit
import SwiftData

// MARK: - Seed data
//
// Sample data for snapshots and for the first run. Every value is invented
// for the demo and labelled "In-house discovery" in the UI. No person, no real
// tenant, no restricted content.

private struct StepSeed {
    var name: String
    var role: String
    var app: String
    var minutes: Double
    var handoffs: Int
    var rework: Double
    var waste: WasteType
    var evidence: Int
    var aligned: Bool = true
}

private struct VariantSeed {
    var name: String
    var share: Double
    var cycle: Double
    var rework: Double
    var path: String
}

private struct ProcessSeed {
    var id: String
    var name: String
    var site: String
    var businessUnit: String
    var valueStream: String
    var owner: String
    var summary: String
    var apps: [String]
    var people: Int
    var hours: Double
    var cycle: Double
    var rework: Double
    var handoffs: Int
    var adherence: Double
    var confidence: Double
    var maturity: Int
    var classification: DataClass
    var status: ProcessStatus
    var statusReason: String
    var standard: String
    var standardVersion: String
    var captureDays: Int
    var staleDays: Int
    var steps: [StepSeed]
    var variants: [VariantSeed]
}

@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<ProcessRecord>())) ?? 0) == 0 else { return }
        seed(into: model)
        if ((try? context.fetchCount(FetchDescriptor<DatasetRecord>())) ?? 0) == 0 {
            _ = model.importSampleDataset()
        }
    }

    static func seed(into model: AppModel) {
        let context = model.container.mainContext
        let now = Date.now
        let calendar = Calendar.current

        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }
        func daysAhead(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: now) ?? now
        }

        // MARK: Processes

        let processes: [ProcessSeed] = [
            ProcessSeed(
                id: "p-order-intake", name: "Order intake & validation", site: "Bensheim",
                businessUnit: "Customer Experience", valueStream: "Order-to-cash",
                owner: "Order Desk Lead",
                summary: "Orders arrive through e-mail, EDI and the web shop. The desk re-keys, checks the customer master, validates pricing and releases credit holds before a sales order exists.",
                apps: ["Outlook", "SAP S/4HANA", "Salesforce"],
                people: 34, hours: 3_180, cycle: 42, rework: 0.28, handoffs: 6,
                adherence: 0.61, confidence: 0.91, maturity: 2,
                classification: .internalUse, status: .discovered, statusReason: "",
                standard: "SOP O2C-04 Order intake", standardVersion: "v6.2",
                captureDays: 92, staleDays: 3,
                steps: [
                    StepSeed(name: "Receive order", role: "Order Desk", app: "Outlook", minutes: 6, handoffs: 0, rework: 0.05, waste: .waiting, evidence: 412),
                    StepSeed(name: "Check customer master", role: "Order Desk", app: "SAP S/4HANA", minutes: 9, handoffs: 1, rework: 0.18, waste: .rework, evidence: 398),
                    StepSeed(name: "Validate pricing", role: "Pricing Analyst", app: "Salesforce", minutes: 12, handoffs: 1, rework: 0.22, waste: .overProcessing, evidence: 366),
                    StepSeed(name: "Release credit hold", role: "Credit Manager", app: "SAP S/4HANA", minutes: 4, handoffs: 1, rework: 0.05, waste: .waiting, evidence: 121),
                    StepSeed(name: "Create sales order", role: "Order Desk", app: "SAP S/4HANA", minutes: 14, handoffs: 1, rework: 0.12, waste: .contextSwitching, evidence: 402),
                    StepSeed(name: "Send confirmation", role: "Order Desk", app: "Outlook", minutes: 3, handoffs: 0, rework: 0.04, waste: .rework, evidence: 389),
                    StepSeed(name: "Clear exception queue", role: "Order Desk", app: "Salesforce", minutes: 11, handoffs: 2, rework: 0.38, waste: .handoffs, evidence: 187),
                ],
                variants: [
                    VariantSeed(name: "EDI straight-through", share: 0.31, cycle: 18, rework: 0.07, path: "Receive → Master → Pricing → Create → Confirm"),
                    VariantSeed(name: "E-mail with manual pricing", share: 0.42, cycle: 47, rework: 0.31, path: "Receive → Master → Pricing → Credit → Create → Confirm"),
                    VariantSeed(name: "Exception re-key from portal", share: 0.19, cycle: 76, rework: 0.44, path: "Receive → Queue → Master → Pricing → Credit → Create → Queue → Confirm"),
                    VariantSeed(name: "Credit-hold escalation", share: 0.08, cycle: 121, rework: 0.36, path: "Receive → Master → Credit → Pricing → Create → Confirm"),
                ]),
            ProcessSeed(
                id: "p-invoice", name: "Invoice exception handling", site: "Wrocław",
                businessUnit: "Finance Operations", valueStream: "Procure-to-pay",
                owner: "AP Team Lead",
                summary: "Invoices that fail the three-way match land in an exception queue. Codes are free text, so the same defect is categorised differently by each specialist.",
                apps: ["SAP S/4HANA", "Outlook", "Coupa"],
                people: 22, hours: 2_410, cycle: 31, rework: 0.34, handoffs: 5,
                adherence: 0.58, confidence: 0.88, maturity: 2,
                classification: .internalUse, status: .discovered, statusReason: "",
                standard: "SOP P2P-11 Exception coding", standardVersion: "v3.0",
                captureDays: 84, staleDays: 9,
                steps: [
                    StepSeed(name: "Open exception queue", role: "AP Specialist", app: "SAP S/4HANA", minutes: 4, handoffs: 0, rework: 0.08, waste: .backlog, evidence: 512),
                    StepSeed(name: "Identify mismatch", role: "AP Specialist", app: "SAP S/4HANA", minutes: 11, handoffs: 0, rework: 0.29, waste: .rework, evidence: 498),
                    StepSeed(name: "Ask buyer to confirm", role: "AP Specialist", app: "Outlook", minutes: 7, handoffs: 1, rework: 0.21, waste: .handoffs, evidence: 441),
                    StepSeed(name: "Correct PO or invoice", role: "Buyer", app: "Coupa", minutes: 13, handoffs: 1, rework: 0.33, waste: .defects, evidence: 402),
                    StepSeed(name: "Post and close", role: "AP Specialist", app: "SAP S/4HANA", minutes: 5, handoffs: 0, rework: 0.11, waste: .overProcessing, evidence: 488),
                ],
                variants: [
                    VariantSeed(name: "Price mismatch", share: 0.44, cycle: 28, rework: 0.31, path: "Queue → Identify → Buyer → Correct → Post"),
                    VariantSeed(name: "Missing receipt", share: 0.33, cycle: 39, rework: 0.41, path: "Queue → Identify → Buyer → Correct → Post → Queue"),
                    VariantSeed(name: "Vendor master error", share: 0.23, cycle: 24, rework: 0.27, path: "Queue → Identify → Correct → Post"),
                ]),
            ProcessSeed(
                id: "p-onboarding", name: "Employee onboarding administration", site: "Manila",
                businessUnit: "HR Services", valueStream: "Hire-to-retire",
                owner: "HR Services Lead",
                summary: "New-hire documents arrive by e-mail, are checked against a checklist and re-keyed into Workday. Missing documents restart the loop with the recruiter.",
                apps: ["Workday", "Outlook", "DocuSign"],
                people: 41, hours: 1_890, cycle: 55, rework: 0.19, handoffs: 4,
                adherence: 0.64, confidence: 0.83, maturity: 3,
                classification: .internalUse, status: .discovered, statusReason: "",
                standard: "SOP H2R-02 Onboarding pack", standardVersion: "v4.1",
                captureDays: 76, staleDays: 21,
                steps: [
                    StepSeed(name: "Receive new-hire pack", role: "HR Coordinator", app: "Outlook", minutes: 5, handoffs: 0, rework: 0.09, waste: .waiting, evidence: 268),
                    StepSeed(name: "Check document checklist", role: "HR Coordinator", app: "Workday", minutes: 16, handoffs: 0, rework: 0.24, waste: .overProcessing, evidence: 261),
                    StepSeed(name: "Chase missing documents", role: "HR Coordinator", app: "Outlook", minutes: 9, handoffs: 1, rework: 0.31, waste: .handoffs, evidence: 174),
                    StepSeed(name: "Create Worker record", role: "HR Coordinator", app: "Workday", minutes: 18, handoffs: 1, rework: 0.13, waste: .rework, evidence: 255),
                    StepSeed(name: "Send for e-signature", role: "HR Coordinator", app: "DocuSign", minutes: 4, handoffs: 1, rework: 0.06, waste: .waiting, evidence: 247),
                ],
                variants: [
                    VariantSeed(name: "Complete pack first time", share: 0.52, cycle: 41, rework: 0.08, path: "Receive → Check → Record → Sign"),
                    VariantSeed(name: "One missing document", share: 0.31, cycle: 68, rework: 0.24, path: "Receive → Check → Chase → Record → Sign"),
                    VariantSeed(name: "Two or more missing", share: 0.17, cycle: 96, rework: 0.42, path: "Receive → Check → Chase → Chase → Record → Sign"),
                ]),
            ProcessSeed(
                id: "p-triage", name: "Customer case triage", site: "Manila",
                businessUnit: "Customer Experience", valueStream: "Issue-to-resolution",
                owner: "Customer Care Lead",
                summary: "Cases arrive from the portal, chat and e-mail. Triage classifies and routes them; resolvers summarise the history by hand before they can act.",
                apps: ["ServiceNow", "Outlook", "Salesforce"],
                people: 56, hours: 4_270, cycle: 18, rework: 0.22, handoffs: 3,
                adherence: 0.55, confidence: 0.90, maturity: 2,
                classification: .internalUse, status: .discovered, statusReason: "",
                standard: "SOP CX-07 Case triage", standardVersion: "v2.4",
                captureDays: 96, staleDays: 1,
                steps: [
                    StepSeed(name: "Intake from portal", role: "Customer Care", app: "ServiceNow", minutes: 3, handoffs: 0, rework: 0.03, waste: .waiting, evidence: 1_284),
                    StepSeed(name: "Classify and prioritise", role: "Triage Agent", app: "ServiceNow", minutes: 5, handoffs: 0, rework: 0.16, waste: .overProcessing, evidence: 1_201),
                    StepSeed(name: "Route to resolver group", role: "Triage Agent", app: "ServiceNow", minutes: 2, handoffs: 1, rework: 0.09, waste: .handoffs, evidence: 1_198),
                    StepSeed(name: "Summarise case history", role: "Resolver", app: "Salesforce", minutes: 18, handoffs: 0, rework: 0.14, waste: .unusedTalent, evidence: 976),
                    StepSeed(name: "Update the customer", role: "Resolver", app: "Outlook", minutes: 4, handoffs: 1, rework: 0.07, waste: .contextSwitching, evidence: 921),
                    StepSeed(name: "Close and survey", role: "Customer Care", app: "ServiceNow", minutes: 2, handoffs: 0, rework: 0.05, waste: .rework, evidence: 1_104),
                ],
                variants: [
                    VariantSeed(name: "Portal, standard", share: 0.46, cycle: 14, rework: 0.16, path: "Intake → Classify → Route → Resolve → Update → Close"),
                    VariantSeed(name: "E-mail with attachment", share: 0.28, cycle: 26, rework: 0.29, path: "Intake → Classify → Route → Resolve → Update → Update → Close"),
                    VariantSeed(name: "Escalated priority", share: 0.18, cycle: 34, rework: 0.24, path: "Intake → Classify → Route → Resolve → Escalate → Update → Close"),
                    VariantSeed(name: "Reopened case", share: 0.08, cycle: 51, rework: 0.46, path: "Intake → Classify → Route → Resolve → Close → Intake → Classify → Route"),
                ]),
            ProcessSeed(
                id: "p-supplier", name: "Supplier master data maintenance", site: "Guadalajara",
                businessUnit: "Procurement", valueStream: "Source-to-contract",
                owner: "Procurement Operations Lead",
                summary: "Supplier records are created per region with local conventions, then merged by hand when duplicates surface in payment runs.",
                apps: ["Coupa", "SAP S/4HANA", "Outlook"],
                people: 12, hours: 960, cycle: 26, rework: 0.31, handoffs: 2,
                adherence: 0.70, confidence: 0.76, maturity: 3,
                classification: .internalUse, status: .discovered, statusReason: "",
                standard: "SOP P2P-03 Supplier master", standardVersion: "v2.2",
                captureDays: 64, staleDays: 12,
                steps: [
                    StepSeed(name: "Receive supplier request", role: "Procurement Analyst", app: "Outlook", minutes: 6, handoffs: 0, rework: 0.07, waste: .waiting, evidence: 142),
                    StepSeed(name: "Search existing records", role: "Procurement Analyst", app: "Coupa", minutes: 12, handoffs: 0, rework: 0.34, waste: .rework, evidence: 139),
                    StepSeed(name: "Validate tax and bank data", role: "Procurement Analyst", app: "SAP S/4HANA", minutes: 17, handoffs: 1, rework: 0.28, waste: .defects, evidence: 131),
                    StepSeed(name: "Merge duplicates", role: "Master Data Steward", app: "SAP S/4HANA", minutes: 22, handoffs: 1, rework: 0.39, waste: .handoffs, evidence: 64),
                ],
                variants: [
                    VariantSeed(name: "New supplier", share: 0.61, cycle: 21, rework: 0.18, path: "Request → Search → Validate"),
                    VariantSeed(name: "Duplicate merged", share: 0.39, cycle: 58, rework: 0.51, path: "Request → Search → Validate → Merge → Validate"),
                ]),
            ProcessSeed(
                id: "p-contract", name: "Contract clause review", site: "Bensheim",
                businessUnit: "Legal Operations", valueStream: "Contract lifecycle",
                owner: "Legal Operations Lead",
                summary: "Standard clauses are reviewed against the playbook before signature. The group is small, so the aggregate is suppressed even locally.",
                apps: ["DocuSign", "Outlook", "Word"],
                people: 8, hours: 720, cycle: 74, rework: 0.12, handoffs: 3,
                adherence: 0.66, confidence: 0.82, maturity: 2,
                classification: .internalUse, status: .suppressed,
                statusReason: "Group of 8 is below the 10-person threshold. Only the existence of the process is shown.",
                standard: "Playbook CL-01 Clause review", standardVersion: "v1.9",
                captureDays: 70, staleDays: 6,
                steps: [
                    StepSeed(name: "Receive redline", role: "Legal Counsel", app: "Outlook", minutes: 8, handoffs: 0, rework: 0.06, waste: .waiting, evidence: 61),
                    StepSeed(name: "Compare to playbook", role: "Legal Counsel", app: "Word", minutes: 34, handoffs: 0, rework: 0.14, waste: .overProcessing, evidence: 58),
                    StepSeed(name: "Approve or escalate", role: "Legal Counsel", app: "DocuSign", minutes: 12, handoffs: 1, rework: 0.09, waste: .handoffs, evidence: 54),
                ],
                variants: []),
            ProcessSeed(
                id: "p-export", name: "Export control screening", site: "Bensheim",
                businessUnit: "Trade Compliance", valueStream: "Order-to-cash",
                owner: "Trade Compliance Lead",
                summary: "Orders are screened against restricted-party lists before release. The record is classified Restricted and never enters ProcessLink.",
                apps: ["SAP S/4HANA", "Outlook"],
                people: 14, hours: 640, cycle: 12, rework: 0.08, handoffs: 2,
                adherence: 0.88, confidence: 0.94, maturity: 4,
                classification: .restricted, status: .blocked,
                statusReason: "Classified Restricted. The aggregate is blocked and no AI call may see it.",
                standard: "SOP TC-02 Screening", standardVersion: "v5.0",
                captureDays: 88, staleDays: 2,
                steps: [],
                variants: []),
        ]

        var stepCounter = 0
        for seed in processes {
            let process = ProcessRecord(
                id: seed.id, name: seed.name, site: seed.site, businessUnit: seed.businessUnit,
                valueStream: seed.valueStream, ownerRole: seed.owner, discoveryID: "disc-proc-\(seed.id)",
                kgID: "kg-proc-\(seed.id)", summary: seed.summary, applications: seed.apps,
                variantNames: seed.variants.map(\.name),
                capturedFrom: daysAgo(seed.captureDays), capturedTo: daysAgo(1),
                lastSynced: daysAgo(seed.staleDays), confidence: seed.confidence,
                people: seed.people, annualHours: seed.hours, cycleMinutes: seed.cycle,
                reworkRate: seed.rework, handoffs: seed.handoffs,
                variantCount: seed.variants.count, adherence: seed.adherence,
                maturity: seed.maturity, classification: seed.classification,
                status: seed.status, statusReason: seed.statusReason,
                standardDocument: seed.standard, standardVersion: seed.standardVersion)
            context.insert(process)

            for (index, step) in seed.steps.enumerated() {
                stepCounter += 1
                context.insert(StepRecord(
                    id: "step-\(seed.id)-\(index)", processID: seed.id, order: index,
                    name: step.name, role: step.role, application: step.app,
                    minutes: step.minutes, handoffs: step.handoffs, reworkShare: step.rework,
                    waste: step.waste, evidenceCount: step.evidence,
                    kgID: "kg-step-\(seed.id)-\(index)", standardAligned: step.aligned))
            }
            for (index, variant) in seed.variants.enumerated() {
                context.insert(VariantRecord(id: "var-\(seed.id)-\(index)", processID: seed.id,
                                             name: variant.name, share: variant.share,
                                             cycleMinutes: variant.cycle, reworkRate: variant.rework,
                                             path: variant.path))
            }
        }
        _ = stepCounter

        // MARK: Opportunities

        struct OppSeed {
            var id: String
            var title: String
            var process: String
            var waste: WasteType
            var method: TEOMethod
            var route: Route
            var hours: Double
            var error: Double
            var effort: Double
            var risk: Int
            var alignment: Int
            var automation: Double
            var confidence: Double
            var statutory: Bool
            var owner: String
            var rationale: String
        }

        let opportunities: [OppSeed] = [
            OppSeed(id: "opp-pricing-check", title: "Remove the duplicate pricing check before order approval",
                    process: "p-order-intake", waste: .overProcessing, method: .standardWork, route: .simplify,
                    hours: 410, error: 18, effort: 3, risk: 2, alignment: 5, automation: 0.20, confidence: 0.90,
                    statutory: false, owner: "Order Desk Lead",
                    rationale: "Pricing is validated in Salesforce, then checked again in SAP by a second role. 18% of orders are re-opened because the two checks disagree.\nThe second check exists from a 2019 control that no longer applies."),
            OppSeed(id: "opp-exception-triage", title: "Automate the exception queue triage for order intake",
                    process: "p-order-intake", waste: .handoffs, method: .kaizen, route: .automate,
                    hours: 620, error: 22, effort: 6, risk: 3, alignment: 4, automation: 0.80, confidence: 0.86,
                    statutory: false, owner: "Order Desk Lead",
                    rationale: "19% of orders take the exception path, with two extra handoffs and 44% rework on that path.\nThe decisions are rule-based: missing PO reference, price mismatch or master-data conflict."),
            OppSeed(id: "opp-invoice-codes", title: "Standardize invoice exception codes across Wrocław",
                    process: "p-invoice", waste: .rework, method: .a3, route: .standardize,
                    hours: 540, error: 25, effort: 4, risk: 2, alignment: 4, automation: 0.30, confidence: 0.88,
                    statutory: false, owner: "AP Team Lead",
                    rationale: "Codes are free text. The same defect is labelled three ways, so the queue cannot be analysed and the buyer rework repeats.\nA fixed code list is a standard-work change, not an automation project."),
            OppSeed(id: "opp-onboarding-upload", title: "Self-service upload for onboarding documents",
                    process: "p-onboarding", waste: .handoffs, method: .kaizen, route: .automate,
                    hours: 390, error: 12, effort: 8, risk: 3, alignment: 3, automation: 0.60, confidence: 0.80,
                    statutory: false, owner: "HR Services Lead",
                    rationale: "48% of packs need at least one chase. Each chase is a handoff between HR, the recruiter and the new hire.\nA self-service upload removes the chase, not the check."),
            OppSeed(id: "opp-case-summary", title: "Agent assist for customer case summarization",
                    process: "p-triage", waste: .unusedTalent, method: .kaizen, route: .automate,
                    hours: 780, error: 8, effort: 7, risk: 4, alignment: 4, automation: 0.85, confidence: 0.78,
                    statutory: false, owner: "Customer Care CI",
                    rationale: "Resolvers spend 18 minutes per case reading and summarising history that already exists in the case record.\nThis is an agent candidate, not an autonomous agent: a human reviews every summary before it is used."),
            OppSeed(id: "opp-supplier-merge", title: "Merge duplicate supplier records at source",
                    process: "p-supplier", waste: .defects, method: .a3, route: .simplify,
                    hours: 210, error: 30, effort: 3, risk: 2, alignment: 2, automation: 0.50, confidence: 0.74,
                    statutory: false, owner: "Master Data Steward",
                    rationale: "39% of supplier requests are duplicates. Each merge costs 22 minutes and a buyer confirmation.\nThe root cause is the search step, not the merge step."),
            OppSeed(id: "opp-triage-board", title: "Daily management board for the triage backlog",
                    process: "p-triage", waste: .backlog, method: .dailyManagement, route: .simplify,
                    hours: 160, error: 5, effort: 2, risk: 1, alignment: 5, automation: 0.10, confidence: 0.90,
                    statutory: false, owner: "Customer Care Lead",
                    rationale: "The backlog grows every Monday and clears by Thursday. Nobody sees it until the queue breaches its SLA.\nA ten-minute daily read is cheaper than another tool."),
            OppSeed(id: "opp-paper-confirm", title: "Eliminate the printed confirmation in order intake",
                    process: "p-order-intake", waste: .waiting, method: .valueStreamMapping, route: .eliminate,
                    hours: 95, error: 4, effort: 1, risk: 1, alignment: 3, automation: 0.00, confidence: 0.93,
                    statutory: false, owner: "Order Desk Lead",
                    rationale: "The confirmation is printed, signed and scanned although the e-mail is the legal record. 3 minutes per order, 95 hours a year, and a queue."),
            OppSeed(id: "opp-credit-standard", title: "Standard work for credit-hold decisions",
                    process: "p-order-intake", waste: .overProcessing, method: .standardWork, route: .standardize,
                    hours: 130, error: 15, effort: 2, risk: 4, alignment: 4, automation: 0.00, confidence: 0.90,
                    statutory: true, owner: "Credit Manager",
                    rationale: "Credit release is a human control. Four people apply four different thresholds, and the reasoning is not recorded.\nAutomation is excluded by policy; the improvement is a written decision standard with a recorded rationale."),
            OppSeed(id: "opp-three-lookups", title: "Consolidate the three order-status lookups",
                    process: "p-order-intake", waste: .contextSwitching, method: .fiveS, route: .standardize,
                    hours: 240, error: 3, effort: 3, risk: 2, alignment: 3, automation: 0.60, confidence: 0.84,
                    statutory: false, owner: "Order Desk Lead",
                    rationale: "Order status is checked in Salesforce, SAP and a shared spreadsheet. 240 hours a year is spent moving between them."),
            OppSeed(id: "opp-contract-check", title: "Contract review checklist and clause library",
                    process: "p-contract", waste: .rework, method: .standardWork, route: .standardize,
                    hours: 120, error: 10, effort: 3, risk: 2, alignment: 3, automation: 0.20, confidence: 0.70,
                    statutory: false, owner: "Legal Operations Lead",
                    rationale: "Reviews restart when a clause is missing from the playbook. The group is below the display threshold, so this opportunity stays suppressed until the group grows."),
            OppSeed(id: "opp-export-precheck", title: "Pre-check export screening inside the order flow",
                    process: "p-export", waste: .defects, method: .errorProofing, route: .simplify,
                    hours: 180, error: 20, effort: 4, risk: 5, alignment: 5, automation: 0.40, confidence: 0.95,
                    statutory: false, owner: "Trade Compliance Lead",
                    rationale: "Screening happens after the order is built, so a blocked party stops an order that should never have been entered.\nThis record is Restricted. It is blocked from promotion and from any AI call by policy."),
        ]

        let processesByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0) })
        for seed in opportunities {
            guard let process = processesByID[seed.process] else { continue }
            context.insert(OpportunityRecord(
                id: seed.id, title: seed.title, processID: seed.process, processName: process.name,
                site: process.site, waste: seed.waste, method: seed.method, route: seed.route,
                annualHours: seed.hours, errorReductionPct: seed.error, effortWeeks: seed.effort,
                risk: seed.risk, alignment: seed.alignment, automation: seed.automation,
                confidence: seed.confidence, statutory: seed.statutory, rationale: seed.rationale,
                kgID: "kg-opp-\(seed.id)", ownerRole: seed.owner, createdAt: daysAgo(9)))
        }

        // MARK: Initiatives and the savings ledger

        struct InitSeed {
            var id: String
            var title: String
            var opportunity: String
            var process: String
            var method: TEOMethod
            var owner: String
            var stage: CycleStage
            var due: Date
            var hours: Double
            var savings: SavingsStage
            var validator: String
            var evidence: String
            var waste: WasteType
            var background: String
            var target: String
            var cause: String
            var counter: String
            var result: String
            var followUp: String
        }

        let initiatives: [InitSeed] = [
            InitSeed(id: "ini-invoice-codes", title: "A3: one exception-code list for invoice handling",
                     opportunity: "opp-invoice-codes", process: "p-invoice", method: .a3,
                     owner: "AP Team Lead", stage: .act, due: daysAhead(-12),
                     hours: 540, savings: .validated, validator: "CI Manager, Wrocław",
                     evidence: "Before: 34% rework and 11 codes in free text over 8 weeks. After: 11% rework and one code list over 6 weeks. 540 h confirmed against the AP time report.",
                     waste: .rework,
                     background: "The exception queue could not be analysed because the same defect carried three labels.",
                     target: "One code list, 90% of exceptions categorised in week one, rework below 15%.",
                     cause: "Free-text code field and no owner for the list.",
                     counter: "Fixed list, a 30-minute weekly review, and the buyer confirmation moved into the same screen.",
                     result: "Rework 34% → 11%. 540 hours a year returned to the team.",
                     followUp: "Re-measure after the SAP upgrade in Q1."),
            InitSeed(id: "ini-pricing", title: "Kaizen: cut the second pricing check",
                     opportunity: "opp-pricing-check", process: "p-order-intake", method: .kaizen,
                     owner: "Ops Excellence Lead", stage: .do, due: daysAhead(21),
                     hours: 410, savings: .committed, validator: "", evidence: "",
                     waste: .overProcessing,
                     background: "Two pricing checks disagree on 18% of orders and re-open them.",
                     target: "Remove the SAP re-check for orders above the price tolerance; keep a sampled audit.",
                     cause: "A 2019 control that no longer matches the pricing engine.",
                     counter: "Tolerance-based release plus a weekly 5% sample audit.",
                     result: "", followUp: "Compare rework before and after over 6 weeks."),
            InitSeed(id: "ini-case-agent", title: "Agent change package: case summarization assist",
                     opportunity: "opp-case-summary", process: "p-triage", method: .kaizen,
                     owner: "Customer Care CI", stage: .check, due: daysAhead(14),
                     hours: 780, savings: .estimated, validator: "", evidence: "",
                     waste: .unusedTalent,
                     background: "18 minutes per case is spent re-reading case history before acting.",
                     target: "A draft summary in under 2 minutes, reviewed by the resolver before use.",
                     cause: "Case history is spread across ServiceNow and Salesforce.",
                     counter: "A reviewed agent draft, a human approval step, and a no-auto-send rule.",
                     result: "", followUp: "Human review rate and summary acceptance rate."),
            InitSeed(id: "ini-5s-orderdesk", title: "5S: order desk workspace and status lookups",
                     opportunity: "opp-three-lookups", process: "p-order-intake", method: .fiveS,
                     owner: "Order Desk Lead", stage: .plan, due: daysAhead(38),
                     hours: 240, savings: .estimated, validator: "", evidence: "",
                     waste: .contextSwitching,
                     background: "Three systems and one spreadsheet hold order status.",
                     target: "One status view, two clicks maximum, no spreadsheet.",
                     cause: "No agreed single source for status.",
                     counter: "A Salesforce status tile backed by SAP, and a printed 5S standard at the desk.",
                     result: "", followUp: "Time a random sample of status checks."),
            InitSeed(id: "ini-credit", title: "Standard work: credit-hold decision record",
                     opportunity: "opp-credit-standard", process: "p-order-intake", method: .standardWork,
                     owner: "Credit Manager", stage: .do, due: daysAhead(27),
                     hours: 130, savings: .committed, validator: "", evidence: "",
                     waste: .overProcessing,
                     background: "Four reviewers apply four thresholds and record no rationale.",
                     target: "One threshold table, a mandatory rationale field, no automation.",
                     cause: "No written standard and no audit of the decision.",
                     counter: "A one-page standard and a monthly review of 10 decisions.",
                     result: "", followUp: "Check that every release has a recorded rationale."),
            InitSeed(id: "ini-rpa-legacy", title: "RPA pilot: order intake bot",
                     opportunity: "opp-exception-triage", process: "p-order-intake", method: .kaizen,
                     owner: "Automation CoE", stage: .do, due: daysAhead(45),
                     hours: 430, savings: .committed, validator: "", evidence: "",
                     waste: .handoffs,
                     background: "A pilot bot re-keys portal orders into SAP.",
                     target: "430 hours a year from the re-key path.",
                     cause: "Portal orders are not integrated.",
                     counter: "Bot built before the path was standardized.",
                     result: "", followUp: "This overlaps the exception-triage initiative; resolve the double count before validating either."),
        ]

        for seed in initiatives {
            let process = processesByID[seed.process]
            let link = StrategyDefaults.link(for: seed.process, waste: seed.waste)
            context.insert(InitiativeRecord(
                id: seed.id, title: seed.title, opportunityID: seed.opportunity,
                processID: seed.process, processName: process?.name ?? "",
                site: process?.site ?? "", method: seed.method, owner: seed.owner,
                stage: seed.stage, status: seed.stage == .act ? .complete : .active, due: seed.due,
                savingsHours: seed.hours, savingsStage: seed.savings,
                validatedBy: seed.validator, evidenceNote: seed.evidence, claimsWaste: seed.waste,
                background: seed.background, target: seed.target, rootCause: seed.cause,
                countermeasure: seed.counter, result: seed.result, followUp: seed.followUp,
                strategicBetID: link.betID, kpiID: link.kpiID,
                valueIDs: link.valueIDs, expectedKPIChange: link.expectedChange,
                visionContribution: link.contribution,
                createdAt: daysAgo(40)))
        }

        // MARK: Feedback
        if ((try? context.fetchCount(FetchDescriptor<FeedbackRecord>())) ?? 0) == 0 {
            context.insert(FeedbackRecord(
                id: "fb-seed-pricing", kind: .process, subjectID: "p-order-intake",
                subjectLabel: "Order intake & validation",
                body: "Should the second pricing check be sampled rather than removed? @Ops Excellence Lead",
                author: "CI Manager (role)", createdAt: daysAgo(2)))
            context.insert(FeedbackRecord(
                id: "fb-seed-map", kind: .map, subjectID: "map-p-triage-as-is",
                subjectLabel: "Customer case triage — as-is",
                body: "The resolver handoff looks longer than the standard. Can someone confirm on the next huddle?",
                author: "Order Desk Lead", createdAt: daysAgo(1)))
        }

        // MARK: Meeting pages

        struct BlockSeed {
            var kind: BlockKind
            var text: String
            var owner: String = ""
            var due: Date?
            var checked: Bool = false
            var linkedKind: String = ""
            var linkedID: String = ""
        }

        struct MeetingSeed {
            var id: String
            var title: String
            var kind: MeetingKind
            var date: Date
            var duration: Int
            var site: String
            var owner: String
            var attendees: [String]
            var process: String
            var initiative: String
            var status: MeetingStatus
            var summary: String
            var recurring: Bool
            var cadence: String
            var blocks: [BlockSeed]
        }

        let meetingSeeds: [MeetingSeed] = [
            MeetingSeed(
                id: "meet-huddle-triage", title: "Daily huddle · Customer Care", kind: .dailyHuddle,
                date: now.addingTimeInterval(-2 * 3_600), duration: 15, site: "Manila",
                owner: "Customer Care Lead",
                attendees: ["Customer Care Lead", "Triage Agent", "Resolver"],
                process: "p-triage", initiative: "", status: .notes,
                summary: "Backlog above target; add the queue to the daily board.",
                recurring: true, cadence: "Daily 08:30",
                blocks: [
                    BlockSeed(kind: .heading, text: "Yesterday"),
                    BlockSeed(kind: .bullet, text: "Backlog peaked at 84 cases; six SLA breaches."),
                    BlockSeed(kind: .bullet, text: "Two reopened cases came from a missing attachment."),
                    BlockSeed(kind: .heading, text: "Today"),
                    BlockSeed(kind: .bullet, text: "Clear the 12 oldest cases first."),
                    BlockSeed(kind: .decision, text: "Add the triage backlog to the daily management board, reviewed at 08:30."),
                    BlockSeed(kind: .action, text: "Create the daily board and review it for two weeks.", owner: "Customer Care Lead", due: daysAhead(14)),
                    BlockSeed(kind: .action, text: "Ask IT for a ServiceNow queue export at 07:00.", owner: "Triage Agent", due: daysAhead(7)),
                    BlockSeed(kind: .callout, text: "No individual volumes are discussed in the huddle; only the queue."),
                ]),
            MeetingSeed(
                id: "meet-kaizen-pricing", title: "Kaizen · pricing check in order intake", kind: .kaizen,
                date: daysAgo(3), duration: 480, site: "Bensheim", owner: "Ops Excellence Lead",
                attendees: ["Order Desk Lead", "Pricing Analyst", "Credit Manager", "Ops Excellence Lead"],
                process: "p-order", initiative: "ini-pricing", status: .notes,
                summary: "Remove the second pricing check above tolerance and audit by sample.",
                recurring: false, cadence: "",
                blocks: [
                    BlockSeed(kind: .heading, text: "Problem"),
                    BlockSeed(kind: .text, text: "Two pricing checks disagree on 18% of orders and re-open them."),
                    BlockSeed(kind: .heading, text: "Target"),
                    BlockSeed(kind: .text, text: "Remove the SAP re-check above the €5k tolerance; keep a 5% sample audit."),
                    BlockSeed(kind: .decision, text: "Drop the SAP re-check above the €5k tolerance from Monday."),
                    BlockSeed(kind: .action, text: "Update SOP O2C-04 to v6.3 and brief the desk.", owner: "Order Desk Lead", due: daysAhead(10)),
                    BlockSeed(kind: .action, text: "Run a weekly 5% sample audit for six weeks.", owner: "Ops Excellence Lead", due: daysAhead(21)),
                    BlockSeed(kind: .action, text: "Quantify rework before and after the change.", owner: "Ops Excellence Lead", due: daysAhead(42), linkedKind: "opportunity", linkedID: "opp-pricing"),
                ]),
            MeetingSeed(
                id: "meet-a3-invoice", title: "A3 review · invoice exception codes", kind: .a3Review,
                date: daysAgo(6), duration: 45, site: "Wrocław", owner: "AP Team Lead",
                attendees: ["AP Team Lead", "Buyer", "CI Manager"],
                process: "p-invoice", initiative: "ini-codes", status: .done,
                summary: "Rework 34% to 11%; adopt the single code list and close.",
                recurring: false, cadence: "",
                blocks: [
                    BlockSeed(kind: .heading, text: "Result"),
                    BlockSeed(kind: .text, text: "Rework 34% → 11% over six weeks; 540 hours confirmed against the AP time report."),
                    BlockSeed(kind: .decision, text: "Adopt the single code list across both AP teams."),
                    BlockSeed(kind: .action, text: "Share the list with the Manila AP team.", owner: "AP Team Lead", due: daysAhead(7)),
                    BlockSeed(kind: .callout, text: "Saving validated by CI Manager, Wrocław. Evidence is attached to the initiative."),
                ]),
            MeetingSeed(
                id: "meet-leadership", title: "Leadership review · Q4 pipeline", kind: .leadership,
                date: daysAgo(2), duration: 60, site: "", owner: "CI Manager",
                attendees: ["CI Manager", "Finance Business Partner", "Site CI Leads"],
                process: "", initiative: "", status: .done,
                summary: "Fund the agent change package subject to security review.",
                recurring: true, cadence: "Monthly",
                blocks: [
                    BlockSeed(kind: .heading, text: "Portfolio"),
                    BlockSeed(kind: .bullet, text: "Validated 540 h; committed 840 h; estimated 1,020 h."),
                    BlockSeed(kind: .bullet, text: "One conflict remains in order intake."),
                    BlockSeed(kind: .decision, text: "Fund the case-summarization agent change package, subject to security review."),
                    BlockSeed(kind: .action, text: "Request the security review for the agent change package.", owner: "Customer Care CI", due: daysAhead(5), linkedKind: "opportunity", linkedID: "opp-summary"),
                    BlockSeed(kind: .action, text: "Resolve the order-intake double count before the roll-up.", owner: "Ops Excellence Lead", due: daysAhead(9)),
                ]),
            MeetingSeed(
                id: "meet-works-council", title: "Works council prep · capture scope", kind: .workshop,
                date: daysAhead(5), duration: 120, site: "Bensheim", owner: "HR Business Partner",
                attendees: ["HR Business Partner", "Data Protection Office", "CI Manager"],
                process: "", initiative: "", status: .planned,
                summary: "Prepare the draft agreement for the Bensheim works council.",
                recurring: false, cadence: "",
                blocks: [
                    BlockSeed(kind: .heading, text: "Agenda"),
                    BlockSeed(kind: .bullet, text: "Capture scope and the minimum group size."),
                    BlockSeed(kind: .bullet, text: "Retention, transparency notice and the escalation path."),
                    BlockSeed(kind: .bullet, text: "Questions from employee representatives."),
                    BlockSeed(kind: .checklist, text: "Share the DPIA summary with the works council."),
                    BlockSeed(kind: .action, text: "Send the draft agreement and DPIA summary.", owner: "HR Business Partner", due: daysAhead(3)),
                ]),
        ]

        for seed in meetingSeeds {
            let meeting = MeetingRecord(
                id: seed.id, title: seed.title, kind: seed.kind, date: seed.date,
                durationMinutes: seed.duration, site: seed.site, owner: seed.owner,
                attendees: seed.attendees, processID: seed.process, initiativeID: seed.initiative,
                status: seed.status, summary: seed.summary, isRecurring: seed.recurring,
                cadence: seed.cadence, createdAt: daysAgo(10))
            context.insert(meeting)
            var inserted: [MeetingBlockRecord] = []
            for (index, blockSeed) in seed.blocks.enumerated() {
                let block = MeetingBlockRecord(
                    id: "blk-\(seed.id)-\(index)", meetingID: meeting.id, order: index,
                    kind: blockSeed.kind, text: blockSeed.text, checked: blockSeed.checked,
                    owner: blockSeed.owner, due: blockSeed.due,
                    linkedKind: blockSeed.linkedKind, linkedID: blockSeed.linkedID)
                context.insert(block)
                inserted.append(block)
            }
            model.writeMeetingToGraph(meeting)
            for block in inserted {
                model.writeBlockToGraph(block, meeting: meeting)
            }
        }

        // MARK: Knowledge graph

        var nodes: [(String, KGKind, String, Double, ReviewState, String, String)] = []
        var edges: [(String, RelationKind, String, Double)] = []

        let sites = Array(Set(processes.map(\.site))).sorted()
        for site in sites {
            nodes.append(("kg-site-\(slug(site))", .site, site, 0.98, .confirmed, "Flightdeck registry", "registry-site-\(slug(site))"))
        }
        for bu in Array(Set(processes.map(\.businessUnit))).sorted() {
            nodes.append(("kg-bu-\(slug(bu))", .businessUnit, bu, 0.97, .confirmed, "Flightdeck registry", "registry-bu-\(slug(bu))"))
        }
        for vs in Array(Set(processes.map(\.valueStream))).sorted() {
            nodes.append(("kg-vs-\(slug(vs))", .valueStream, vs, 0.96, .confirmed, "Flightdeck catalog", "catalog-vs-\(slug(vs))"))
        }

        let applicationNames = Array(Set(processes.flatMap(\.apps))).sorted()
        for app in applicationNames {
            nodes.append(("kg-app-\(slug(app))", .application, app, 0.93, .confirmed, "ProcessLink app usage", "disc-app-\(slug(app))"))
        }

        let roleNames = Array(Set(processes.flatMap { $0.steps.map(\.role) })).sorted()
        for role in roleNames {
            nodes.append(("kg-role-\(slug(role))", .role, role, 0.9, .confirmed, "ProcessLink role aggregation", "disc-role-\(slug(role))"))
        }

        for seed in processes {
            nodes.append(("kg-proc-\(seed.id)", .process, seed.name, seed.confidence, .confirmed,
                          "ProcessLink discovery", "disc-proc-\(seed.id)"))
            edges.append(("kg-proc-\(seed.id)", .performedIn, "kg-site-\(slug(seed.site))", 0.99))
            edges.append(("kg-proc-\(seed.id)", .ownedBy, "kg-role-\(slug(seed.owner))", 0.85))
            edges.append(("kg-proc-\(seed.id)", .alignedToObjective, "kg-vs-\(slug(seed.valueStream))", 0.8))
            for app in seed.apps {
                edges.append(("kg-proc-\(seed.id)", .uses, "kg-app-\(slug(app))", 0.9))
            }
            for (index, _) in seed.steps.enumerated() where index < seed.steps.count - 1 {
                edges.append(("kg-step-\(seed.id)-\(index)", .handsOffTo, "kg-step-\(seed.id)-\(index + 1)", 0.88))
            }
            for (index, step) in seed.steps.enumerated() {
                nodes.append(("kg-step-\(seed.id)-\(index)", .step, step.name, 0.87, .confirmed,
                              "ProcessLink discovery", "disc-step-\(seed.id)-\(index)"))
            }
        }

        let objectives: [(String, String)] = [
            ("kg-hoshin-o2c", "Cut order-to-cash lead time by 25%"),
            ("kg-hoshin-rework", "Halve administrative rework in finance"),
            ("kg-hoshin-adherence", "Lift standard-work adherence above 85%"),
        ]
        for (id, name) in objectives {
            nodes.append((id, .hoshinObjective, name, 0.95, .confirmed, "Hoshin deployment 2026", id))
        }

        let documents: [(String, String)] = [
            ("kg-doc-o2c", "SOP O2C-04 Order intake v6.2"),
            ("kg-doc-p2p", "SOP P2P-11 Exception coding v3.0"),
        ]
        for (id, name) in documents {
            nodes.append((id, .document, name, 0.92, .confirmed, "Knowledge Guardian", id))
        }
        edges.append(("kg-proc-p-order-intake", .documentedIn, "kg-doc-o2c", 0.9))
        edges.append(("kg-proc-p-invoice", .documentedIn, "kg-doc-p2p", 0.9))

        for seed in opportunities where seed.process != "p-export" {
            nodes.append(("kg-opp-\(seed.id)", .opportunity, seed.title, min(0.95, seed.confidence + 0.02),
                          .confirmed, "ProcessLink opportunity engine", seed.id))
            edges.append(("kg-proc-\(seed.process)", .hasOpportunity, "kg-opp-\(seed.id)", 0.9))
            if seed.process == "p-invoice" || seed.process == "p-order-intake" {
                edges.append(("kg-opp-\(seed.id)", .alignedToObjective, "kg-hoshin-rework", 0.7))
            }
            if seed.process == "p-order-intake" {
                edges.append(("kg-opp-\(seed.id)", .alignedToObjective, "kg-hoshin-o2c", 0.8))
            }
        }
        for seed in initiatives {
            nodes.append(("kg-ini-\(seed.id)", .initiative, seed.title, 0.93, .confirmed,
                          "ProcessLink TEOA layer", seed.id))
            edges.append(("kg-opp-\(seed.opportunity)", .addressedBy, "kg-ini-\(seed.id)", 0.9))
            edges.append(("kg-ini-\(seed.id)", .realizesSavings, "kg-savings-\(seed.id)", 0.9))
            nodes.append(("kg-savings-\(seed.id)", .savingsRecord,
                          "\(Int(seed.hours)) h · \(seed.savings.label)", 0.9, .confirmed,
                          "ProcessLink value tracking", seed.id))
            if seed.process == "p-order-intake" {
                edges.append(("kg-ini-\(seed.id)", .alignedToObjective, "kg-hoshin-o2c", 0.75))
            }
        }

        // Two deliberately uncertain matches for the human review queue.
        nodes.append(("kg-app-sap-ecc", .application, "SAP ECC", 0.61, .suggested,
                      "ProcessLink app usage", "disc-app-ecc"))
        nodes.append(("kg-team-sales-support", .team, "Sales Support", 0.72, .suggested,
                      "ProcessLink team aggregation", "disc-team-sales-support"))
        edges.append(("kg-app-sap-ecc", .variantOf, "kg-app-\(slug("SAP S/4HANA"))", 0.61))
        edges.append(("kg-team-sales-support", .variantOf, "kg-role-order-desk", 0.72))

        for (id, kind, name, confidence, review, source, sourceID) in nodes {
            guard !exists(context, KGNodeRecord.self, id) else { continue }
            let node = KGNodeRecord(id: id, kind: kind, name: name, confidence: confidence,
                                    review: review, source: source, sourceID: sourceID,
                                    validFrom: daysAgo(120),
                                    processID: name.lowercased().contains("order") ? "p-order-intake" : "",
                                    note: review == .suggested ? "Entity resolution found a likely duplicate. A human must confirm or reject the merge." : "")
            node.updatedAt = daysAgo(120)
            context.insert(node)
        }
        for (index, edge) in edges.enumerated() {
            context.insert(KGEdgeRecord(id: "edge-\(index)", fromID: edge.0, predicate: edge.1,
                                        toID: edge.2, confidence: edge.3,
                                        source: "ProcessLink discovery + analysis"))
        }

        // MARK: Governance

        let governance: [(String, String, String, String, GovernanceStatus, String)] = [
            ("gov-dpia", "Data protection impact assessment", "Completed for the pilot in DE and PL; the PH and MX assessments are in review.", "Data protection", .inProgress, "Data Protection Office"),
            ("gov-legal", "Legal review per country", "DE and PL approved for process improvement only. PH and MX pending.", "Data protection", .inProgress, "Legal"),
            ("gov-works-council", "Works council consultation (DE)", "The Bensheim works council has the draft agreement. No capture expansion before sign-off.", "People", .blocked, "HR Business Partner"),
            ("gov-notice", "Employee transparency notice", "Published in the intranet and linked from the discovery capture page.", "People", .done, "Internal Communications"),
            ("gov-retention", "Retention schedule", "Aggregated process facts 400 days; raw capture stays in the local capture store and is not copied.", "Data protection", .done, "Data Owner"),
            ("gov-owner", "Named data owner", "CI Manager (role) is accountable for every use of discovery data in ProcessLink.", "Accountability", .done, "CI Manager"),
            ("gov-scope", "Capture scope confirmed", "Sites: Bensheim, Wrocław, Manila, Guadalajara. No personal devices, no off-network capture.", "People", .done, "Discovery administrator"),
            ("gov-ai", "AI provider and region approval", "Local provider approved. The hosted provider is approved for EU processing only, classification-gated.", "AI & security", .inProgress, "Security"),
            ("gov-dpia-prod", "DPIA for production rollout", "Pilot DPIA is not a production DPIA. Required before any site beyond the pilot.", "Data protection", .notStarted, "Data Protection Office"),
        ]
        for (index, item) in governance.enumerated() {
            context.insert(GovernanceRecord(id: item.0, title: item.1, detail: item.2,
                                            group: item.3, status: item.4, owner: item.5,
                                            sortKey: index))
        }

        // MARK: Audit trail

        let audits: [(String, String, String, String, Int)] = [
            ("governance.reviewed", "Launch checklist", "DPIA reviewed with the Data Protection Office.", "internal", 12),
            ("discovery.refreshed", "In-house discovery", "7 processes, 144 events and 5 captures read locally.", "internal", 3),
            ("initiative.created", "Kaizen: cut the second pricing check", "From opportunity opp-pricing-check.", "internal", 9),
            ("savings.validated", "A3: one exception-code list", "540 h validated by CI Manager, Wrocław.", "internal", 6),
            ("ai.answer", "Ask the process", "Question answered locally with 6 citations.", "internal", 2),
            ("kg.node.rejected", "SAP ECC", "Suggested merge rejected: the ECC instance is still live in Guadalajara.", "internal", 5),
        ]
        for (action, subject, detail, classification, days) in audits {
            let dataClass = DataClass(rawValue: classification) ?? .internalUse
            context.insert(AuditRecord(at: daysAgo(days), actor: "CI Manager (role)", action: action,
                                       subject: subject, detail: detail, classification: dataClass))
        }

        // MARK: Sync history

        context.insert(SyncRecord(at: daysAgo(3), source: "In-house discovery · local refresh",
                                  fetched: 7, inserted: 0, updated: 0, skipped: 0,
                                  status: "success", note: "7 processes, 5 captures and 144 events read locally."))
        context.insert(SyncRecord(at: daysAgo(10), source: "In-house discovery · local refresh",
                                  fetched: 7, inserted: 0, updated: 0, skipped: 0,
                                  status: "success", note: "7 processes, 5 captures and 144 events read locally."))
        context.insert(SyncRecord(at: daysAgo(31), source: "In-house discovery · local refresh",
                                  fetched: 7, inserted: 0, updated: 0, skipped: 0,
                                  status: "success", note: "Local discovery store created."))

        // Local task capture: aggregates only, seeded so the tab is not empty.
        let captureSessions: [(String, String, String, String, Int, Int, Int, [(String, String, Double, Int)])] = [
            ("cap-demo-order", "Order desk · morning", "Order Desk", "Bensheim", 34, 6, 23,
             [("Outlook", "com.microsoft.Outlook", 9, 6),
              ("SAP S/4HANA", "com.sap.s4", 14, 9),
              ("Salesforce", "com.salesforce.desktop", 8, 5),
              ("Microsoft Teams", "com.microsoft.teams2", 3, 3)]),
            ("cap-demo-triage", "Case triage · afternoon", "Triage Agent", "Manila", 41, 9, 31,
             [("ServiceNow", "com.servicenow.agent", 18, 12),
              ("Salesforce", "com.salesforce.desktop", 11, 8),
              ("Outlook", "com.microsoft.Outlook", 7, 7),
              ("Microsoft Teams", "com.microsoft.teams2", 5, 4)]),
        ]
        for (index, seed) in captureSessions.enumerated() {
            let session = CaptureSessionRecord(
                id: seed.0, name: seed.1, role: seed.2, site: seed.3,
                startedAt: daysAgo(index + 1), endedAt: daysAgo(index + 1).addingTimeInterval(45 * 60),
                sampleSeconds: 5, activeMinutes: Double(seed.4), idleMinutes: Double(seed.5),
                switchCount: seed.6, status: "complete",
                notes: "Aggregates only: app name, minutes and switches.")
            context.insert(session)
            for (appIndex, app) in seed.7.enumerated() {
                context.insert(CaptureAppRecord(
                    id: "\(seed.0)-app-\(appIndex)", sessionID: seed.0,
                    appName: app.0, bundleID: app.1, minutes: app.2,
                    idleMinutes: 0, switches: app.3))
            }
        }

        try? context.save()
    }

    private static func slug(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    private static func exists<T: PersistentModel & HasStringID>(_ context: ModelContext,
                                                                _ type: T.Type, _ id: String) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.contains { $0.id == id }
    }
}

import Foundation
import ProcessLinkKit
import SwiftData

/// The default function strategy and the linking rules that keep every
/// initiative traceable. These are editable records, not constants in a view.
@MainActor
enum StrategyDefaults {
    static let visionID = "function-strategy"
    static let betO2C = "bet-o2c"
    static let betFinance = "bet-frictionless-finance"
    static let betDigital = "bet-digital-operations"
    static let betStandard = "bet-standard-work"

    static let kpiO2C = "kpi-o2c-lead-time"
    static let kpiInvoice = "kpi-invoice-rework"
    static let kpiManual = "kpi-manual-touches"
    static let kpiCase = "kpi-case-handling"
    static let kpiAdherence = "kpi-adherence"

    static let valCustomer = "val-customer-first"
    static let valRight = "val-right-first-time"
    static let valSimplify = "val-simplify-before-automate"
    static let valPeople = "val-people-in-loop"

    struct Link {
        var betID: String
        var kpiID: String
        var valueIDs: [String]
        var expectedChange: String
        var contribution: String
    }

    // MARK: Install

    static func installIfNeeded(in context: ModelContext) {
        let strategies = (try? context.fetch(FetchDescriptor<StrategyRecord>())) ?? []
        if strategies.isEmpty {
            context.insert(StrategyRecord(
                id: visionID, functionName: "Operations",
                visionTitle: "Right first time, end to end",
                visionStatement: "Make every order and invoice flow right the first time — designed around the customer, simplified before it is automated, and measured end to end.",
                horizon: "FY2026", owner: "COO"))
        }

        let values = (try? context.fetch(FetchDescriptor<ValueRecord>())) ?? []
        if values.isEmpty {
            let seeds = [
                ValueRecord(id: valCustomer, name: "Customer first",
                            statement: "Start with the customer's wait, not our queue.",
                            behaviour: "Every improvement states whose wait it removes.", order: 0),
                ValueRecord(id: valRight, name: "Right first time",
                            statement: "Fix the cause, not the exception.",
                            behaviour: "Countermeasures remove a defect source, not a symptom.", order: 1),
                ValueRecord(id: valSimplify, name: "Simplify before automate",
                            statement: "Remove work before buying a robot.",
                            behaviour: "An automation case must show the simpler path was tested.", order: 2),
                ValueRecord(id: valPeople, name: "People in the loop",
                            statement: "Automation drafts; a named human decides.",
                            behaviour: "No automatic send, release or performance decision.", order: 3),
            ]
            for value in seeds { context.insert(value) }
        }

        let kpis = (try? context.fetch(FetchDescriptor<KPIRecord>())) ?? []
        if kpis.isEmpty {
            let seeds = [
                KPIRecord(id: kpiO2C, name: "Order-to-cash lead time",
                          definition: "Working days from order received to cash posted, measured end to end.",
                          unit: "days", baseline: 12, current: 11, target: 9, direction: "lower",
                          cadence: "Weekly", source: "Discovery timestamps + SAP", strategicBetID: betO2C),
                KPIRecord(id: kpiInvoice, name: "Invoice exception rework",
                          definition: "Share of invoice lines that return to the exception queue.",
                          unit: "%", baseline: 34, current: 9, target: 10, direction: "lower",
                          cadence: "Weekly", source: "SAP exception log", strategicBetID: betFinance),
                KPIRecord(id: kpiManual, name: "Manual touches per order",
                          definition: "Clicks, re-keys and handoffs required to create one sales order.",
                          unit: "touches", baseline: 7, current: 6, target: 4, direction: "lower",
                          cadence: "Monthly", source: "Task capture + event log", strategicBetID: betDigital),
                KPIRecord(id: kpiCase, name: "Case handling minutes",
                          definition: "Median minutes from case open to first substantive action.",
                          unit: "min", baseline: 38, current: 34, target: 26, direction: "lower",
                          cadence: "Weekly", source: "ServiceNow + Salesforce", strategicBetID: betDigital),
                KPIRecord(id: kpiAdherence, name: "Standard-work adherence",
                          definition: "Share of sampled cases following the current standard work.",
                          unit: "%", baseline: 68, current: 78, target: 85, direction: "higher",
                          cadence: "Monthly", source: "Audit sample", strategicBetID: betStandard),
            ]
            for kpi in seeds { context.insert(kpi) }
        }

        let bets = (try? context.fetch(FetchDescriptor<StrategicBetRecord>())) ?? []
        if bets.isEmpty {
            let seeds = [
                StrategicBetRecord(id: betO2C, title: "Order-to-cash velocity",
                                   detail: "Remove duplicate checks and handoffs between order intake and cash.",
                                   owner: "COO", horizon: "FY2026", status: "active",
                                   primaryKPIID: kpiO2C, valueIDs: [valCustomer, valRight], order: 0),
                StrategicBetRecord(id: betFinance, title: "Frictionless finance",
                                   detail: "One exception language, a clean close, and no rework loop.",
                                   owner: "Finance Director", horizon: "FY2026", status: "active",
                                   primaryKPIID: kpiInvoice, valueIDs: [valRight, valCustomer], order: 1),
                StrategicBetRecord(id: betDigital, title: "Digital operations at the desk",
                                   detail: "Give people one status view and remove re-keying before adding agents.",
                                   owner: "CI Manager", horizon: "FY2026", status: "active",
                                   primaryKPIID: kpiManual, valueIDs: [valSimplify, valPeople], order: 2),
                StrategicBetRecord(id: betStandard, title: "Standard work that sticks",
                                   detail: "Make the best known way the default, with a named owner and an audit.",
                                   owner: "Ops Excellence Lead", horizon: "FY2026", status: "active",
                                   primaryKPIID: kpiAdherence, valueIDs: [valRight, valPeople], order: 3),
            ]
            for bet in seeds { context.insert(bet) }
        }

        try? context.save()
    }

    // MARK: Linking

    static func link(for processID: String, waste: WasteType) -> Link {
        switch processID {
        case "p-invoice":
            return Link(betID: betFinance, kpiID: kpiInvoice,
                        valueIDs: [valRight, valCustomer],
                        expectedChange: "Exception rework moves toward the 10% target.",
                        contribution: "Reduces rework in the invoice exception path.")
        case "p-triage":
            return Link(betID: betDigital, kpiID: kpiCase,
                        valueIDs: [valPeople, valSimplify],
                        expectedChange: "Case handling minutes move toward 26.",
                        contribution: "Gives resolvers a faster, reviewed start.")
        case "p-order-intake" where waste == .contextSwitching || waste == .handoffs:
            return Link(betID: betDigital, kpiID: kpiManual,
                        valueIDs: [valSimplify, valPeople],
                        expectedChange: "Manual touches move from 6 toward 4.",
                        contribution: "Removes re-keying and status hunting at the desk.")
        case "p-order-intake":
            return Link(betID: betO2C, kpiID: kpiO2C,
                        valueIDs: [valSimplify, valRight],
                        expectedChange: "Order-to-cash lead time moves toward 9 days.",
                        contribution: "Removes a duplicate check that reopens orders.")
        default:
            return Link(betID: betStandard, kpiID: kpiAdherence,
                        valueIDs: [valRight, valPeople],
                        expectedChange: "Adherence moves toward the 85% target.",
                        contribution: "Makes the standard the default and auditable.")
        }
    }

    /// Fills only empty fields. An explicit human link is never overwritten.
    static func applyLink(_ link: Link, to initiative: InitiativeRecord) {
        if initiative.strategicBetID.isEmpty { initiative.strategicBetID = link.betID }
        if initiative.kpiID.isEmpty { initiative.kpiID = link.kpiID }
        if initiative.valueIDs.isEmpty { initiative.valueIDsRaw = link.valueIDs.joined(separator: ",") }
        if initiative.expectedKPIChange.isEmpty { initiative.expectedKPIChange = link.expectedChange }
        if initiative.visionContribution.isEmpty { initiative.visionContribution = link.contribution }
    }

    static func applyDefaultLink(to initiative: InitiativeRecord) {
        let waste = initiative.claimsWaste
        let link = link(for: initiative.processID, waste: waste)
        applyLink(link, to: initiative)
    }

    static func repairAllLinks(in context: ModelContext) {
        let initiatives = (try? context.fetch(FetchDescriptor<InitiativeRecord>())) ?? []
        for initiative in initiatives where !initiative.hasStrategyLink {
            applyDefaultLink(to: initiative)
        }
        try? context.save()
    }

    static func bet(for id: String, in context: ModelContext) -> StrategicBetRecord? {
        ((try? context.fetch(FetchDescriptor<StrategicBetRecord>())) ?? []).first { $0.id == id }
    }

    static func kpi(for id: String, in context: ModelContext) -> KPIRecord? {
        ((try? context.fetch(FetchDescriptor<KPIRecord>())) ?? []).first { $0.id == id }
    }

    static func valueNames(for ids: [String], in context: ModelContext) -> [String] {
        let values = (try? context.fetch(FetchDescriptor<ValueRecord>())) ?? []
        return ids.compactMap { id in values.first { $0.id == id }?.name }
    }
}

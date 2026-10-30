import Foundation

public struct OCELObject: Sendable, Identifiable, Hashable {
    public var id: String
    public var type: String
    public var label: String
}

public struct OCELEvent: Sendable, Identifiable, Hashable {
    public var id: String
    public var activity: String
    public var timestamp: Date
    public var objectIDs: [String]
}

public struct OCELInteraction: Sendable, Identifiable, Hashable {
    public var id: String { "\(from)|\(to)" }
    public var from: String
    public var to: String
    public var events: Int
}

public struct OCELModel: Sendable {
    public var objects: [OCELObject]
    public var events: [OCELEvent]
    public var objectTypes: [(type: String, count: Int)]
    public var interactions: [OCELInteraction]
    public var eventsWithMultipleObjects: Int
}

/// Object-centric event log. Multiple object notions (case, order, customer,
/// invoice, employee, …) are derived from imported attributes; no person-level
/// identity is invented. Object links come only from columns the log supplies.
public enum OCEL {
    public static func build(events: [EventLogRecord], objectKeys: [String]) -> OCELModel {
        var objects: [String: OCELObject] = [:]
        var ocelEvents: [OCELEvent] = []
        var interactions: [String: (from: String, to: String, count: Int)] = [:]
        var multiple = 0

        for event in events {
            var ids: [String] = ["case:\(event.caseID)"]
            objects["case:\(event.caseID)"] = OCELObject(id: "case:\(event.caseID)", type: "case", label: event.caseID)
            for key in objectKeys {
                guard let value = event.attributes[key], !value.isEmpty else { continue }
                let type = key.lowercased().replacingOccurrences(of: " ", with: "_")
                let id = "\(type):\(value)"
                objects[id] = OCELObject(id: id, type: type, label: value)
                ids.append(id)
            }
            if ids.count > 2 { multiple += 1 }
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let a = ids[i], b = ids[j]
                    let key = a < b ? "\(a)|\(b)" : "\(b)|\(a)"
                    let pair = interactions[key] ?? (from: a, to: b, count: 0)
                    interactions[key] = (from: pair.from, to: pair.to, count: pair.count + 1)
                }
            }
            ocelEvents.append(OCELEvent(id: event.caseID + "|" + event.activity + "|" + event.timestamp.ISO8601Format(),
                                        activity: event.activity, timestamp: event.timestamp, objectIDs: ids))
        }
        let typeCounts = Dictionary(grouping: objects.values, by: \.type).map { ($0.key, $0.value.count) }
            .sorted { $0.0 < $1.0 }
        return OCELModel(
            objects: objects.values.sorted { $0.id < $1.id },
            events: ocelEvents,
            objectTypes: typeCounts.map { (type: $0.0, count: $0.1) },
            interactions: interactions.values.map { OCELInteraction(from: $0.from, to: $0.to, events: $0.count) }
                .sorted { $0.events > $1.events },
            eventsWithMultipleObjects: multiple)
    }
}

// MARK: - Peer benchmark library

public struct PeerBenchmark: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var cohort: String
    public var medianCycleMinutes: Double
    public var p90CycleMinutes: Double
    public var reworkRate: Double
    public var automationRatio: Double
    public var sampleCases: Int
    public var note: String
}

public enum PeerBenchmarks {
    /// Illustrative, synthetic reference values shipped for comparison only.
    /// They are not a vendor benchmark and must be labelled as illustrative.
    public static let library: [PeerBenchmark] = [
        PeerBenchmark(id: "finance-eu-mid", label: "Finance · EU mid-size", cohort: "AP / invoice",
                      medianCycleMinutes: 1_080, p90CycleMinutes: 3_600, reworkRate: 0.22,
                      automationRatio: 0.35, sampleCases: 420,
                      note: "Illustrative cohort. Replace with a governed benchmark feed before use."),
        PeerBenchmark(id: "order-de-mid", label: "Order desk · DE mid-size", cohort: "Order-to-cash",
                      medianCycleMinutes: 2_520, p90CycleMinutes: 7_200, reworkRate: 0.18,
                      automationRatio: 0.42, sampleCases: 610,
                      note: "Illustrative cohort. Replace with a governed benchmark feed before use."),
        PeerBenchmark(id: "service-eu-mid", label: "Customer service · EU mid-size", cohort: "Case triage",
                      medianCycleMinutes: 1_920, p90CycleMinutes: 5_400, reworkRate: 0.14,
                      automationRatio: 0.38, sampleCases: 880,
                      note: "Illustrative cohort. Replace with a governed benchmark feed before use."),
    ]

    public static func closest(to mined: MinedProcess) -> PeerBenchmark {
        library.min { a, b in
            abs(a.medianCycleMinutes - mined.medianCycleMinutes) < abs(b.medianCycleMinutes - mined.medianCycleMinutes)
        } ?? library[0]
    }
}

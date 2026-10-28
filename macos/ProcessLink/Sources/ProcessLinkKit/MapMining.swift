import Foundation

public struct MapStepRef: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var role: String
    public var system: String

    public init(id: String, label: String, role: String = "", system: String = "") {
        self.id = id
        self.label = label
        self.role = role
        self.system = system
    }
}

public struct MapEdgeRef: Sendable, Hashable {
    public var from: String
    public var to: String
    public init(from: String, to: String) { self.from = from; self.to = to }
}

public struct MapReference: Sendable {
    public var name: String
    public var steps: [MapStepRef]
    public var edges: [MapEdgeRef]
    public init(name: String, steps: [MapStepRef], edges: [MapEdgeRef]) {
        self.name = name
        self.steps = steps
        self.edges = edges
    }
}

public struct MapMiningReport: Sendable {
    public var stepsObserved: Int
    public var stepsTotal: Int
    public var mappedActivities: Int
    public var unmappedActivities: [String]
    public var expectedTransitions: Int
    public var observedTransitions: Int
    public var unexpectedTransitions: [String]
    public var missingSteps: [String]

    public var stepCoverage: Double {
        stepsTotal == 0 ? 0 : Double(stepsObserved) / Double(stepsTotal)
    }
    public var transitionCoverage: Double {
        expectedTransitions == 0 ? 0 : min(1, Double(observedTransitions) / Double(expectedTransitions))
    }
}

/// Map-native conformance: the event log does not have to use the map's exact
/// labels. A mapping from observed activity to map step id is applied first;
/// then step coverage and whether each observed transition exists in the map
/// graph are reported. Unmapped activities are named rather than hidden.
public enum MapMining {
    public static func autoMap(activities: [String], reference: MapReference) -> [String: String] {
        var result: [String: String] = [:]
        for activity in activities {
            let normalized = normalize(activity)
            if let exact = reference.steps.first(where: {
                normalize($0.label) == normalized || normalize($0.id) == normalized
            }) {
                result[activity] = exact.id
                continue
            }
            let tokens = Set(normalized.split(separator: " ").map(String.init))
            let scored = reference.steps.map { step -> (MapStepRef, Double) in
                let stepTokens = Set(normalize(step.label).split(separator: " ").map(String.init))
                let overlap = tokens.intersection(stepTokens).count
                return (step, stepTokens.isEmpty ? 0 : Double(overlap) / Double(stepTokens.count))
            }.sorted { $0.1 > $1.1 }
            if let best = scored.first, best.1 >= 0.5 {
                result[activity] = best.0.id
            }
        }
        return result
    }

    public static func conformance(events: [EventLogRecord], reference: MapReference,
                                   mapping: [String: String]) -> MapMiningReport {
        let lookup = Dictionary(uniqueKeysWithValues: mapping.map { ($0.key.lowercased(), $0.value) })
        let cases = Dictionary(grouping: events, by: \.caseID).values
        var observedSteps = Set<String>()
        var observedTransitions = Set<String>()
        var activities = Set<String>()
        for events in cases {
            let ordered = events.sorted { $0.timestamp < $1.timestamp }
            var previous: String?
            for event in ordered {
                activities.insert(event.activity)
                if let step = lookup[event.activity.lowercased()] {
                    observedSteps.insert(step)
                    if let previous, previous != step {
                        observedTransitions.insert("\(previous)|\(step)")
                    }
                    previous = step
                }
            }
        }
        let stepIDs = Set(reference.steps.map(\.id))
        let expected = Set(reference.edges.compactMap { edge -> String? in
            guard stepIDs.contains(edge.from), stepIDs.contains(edge.to) else { return nil }
            return "\(edge.from)|\(edge.to)"
        })
        let mappedActivities = activities.filter { lookup[$0.lowercased()] != nil }
        let unmapped = activities.filter { lookup[$0.lowercased()] == nil }.sorted()
        let unexpected = observedTransitions.filter { !expected.contains($0) }.sorted()
        let missing = reference.steps.filter { !observedSteps.contains($0.id) }.map(\.label)
        return MapMiningReport(
            stepsObserved: observedSteps.count, stepsTotal: reference.steps.count,
            mappedActivities: mappedActivities.count, unmappedActivities: unmapped,
            expectedTransitions: expected.count,
            observedTransitions: observedTransitions.intersection(expected).count,
            unexpectedTransitions: unexpected, missingSteps: missing)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

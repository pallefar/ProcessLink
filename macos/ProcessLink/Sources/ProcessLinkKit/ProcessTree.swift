import Foundation

/// A block-structured process tree. The discovery below builds it from the
/// observed case variants as a prefix tree: every branch is an XOR, every
/// common prefix is a sequence, and every leaf is an activity. The result is
/// sound by construction (no deadlocks or unhandled tokens), but it recognises
/// the observed language rather than inventing unobserved behaviour.
public indirect enum ProcessTree: Sendable, Equatable {
    case activity(String)
    case sequence([ProcessTree])
    case xor([ProcessTree])
    case tau

    public var activityNames: [String] {
        switch self {
        case .activity(let name): [name]
        case .sequence(let children), .xor(let children): children.flatMap(\.activityNames)
        case .tau: []
        }
    }

    public var isSound: Bool {
        switch self {
        case .activity, .tau: true
        case .sequence(let children), .xor(let children):
            !children.isEmpty && children.allSatisfy(\.isSound)
        }
    }

    public func outline(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .activity(let name): return "\(pad)• \(name)"
        case .tau: return "\(pad)• τ"
        case .sequence(let children):
            return ([ "\(pad)Sequence" ] + children.map { $0.outline(indent: indent + 1) }).joined(separator: "\n")
        case .xor(let children):
            return ([ "\(pad)Choice" ] + children.map { $0.outline(indent: indent + 1) }).joined(separator: "\n")
        }
    }
}

public enum InductiveDiscovery {
    /// Discover a block-structured tree from case variants. The prefix-tree
    /// construction is deliberately explainable: every observed path becomes a
    /// branch, and common prefixes are factored into sequences.
    public static func tree(from cases: [MinedCase]) -> ProcessTree {
        final class Node {
            var children: [String: Node] = [:]
            var terminal = false
        }
        let root = Node()
        for record in cases {
            var node = root
            for activity in record.sequence {
                if node.children[activity] == nil { node.children[activity] = Node() }
                node = node.children[activity]!
            }
            node.terminal = true
        }
        func build(_ node: Node) -> ProcessTree {
            if node.children.isEmpty { return .tau }
            if node.children.count == 1, let (activity, child) = node.children.first {
                let rest = build(child)
                return .sequence([.activity(activity), rest])
            }
            let branches = node.children.keys.sorted().map { activity -> ProcessTree in
                .sequence([.activity(activity), build(node.children[activity]!)])
            }
            return .xor(branches)
        }
        return build(root)
    }

    /// BPMN 2.0 XML for the tree. The tree is block-structured, so the emitted
    /// gateways are paired split/merge gateways and the model is sound.
    public static func bpmn(_ tree: ProcessTree, name: String, id: String = "ProcessLink") -> String {
        final class Emitter {
            var counter = 0
            var elements: [String] = []
            var flows: [String] = []
            func next(_ prefix: String) -> String {
                counter += 1
                return "\(prefix)_\(counter)"
            }
            func flow(_ from: String, _ to: String) {
                flows.append("""
                <bpmn:sequenceFlow id="\(next("Flow"))" sourceRef="\(from)" targetRef="\(to)"/>
                """)
            }
            func emit(_ tree: ProcessTree, from: String, to: String) {
                switch tree {
                case .tau:
                    flow(from, to)
                case .activity(let activity):
                    let task = next("Task")
                    elements.append("""
                    <bpmn:task id="\(task)" name="\(InductiveDiscovery.xml(activity))"/>
                    """)
                    flow(from, task)
                    flow(task, to)
                case .sequence(let children):
                    var previous = from
                    for (index, child) in children.enumerated() {
                        let next = index == children.count - 1 ? to : next("Gateway")
                        if next.hasPrefix("Gateway") {
                            elements.append("""
                            <bpmn:exclusiveGateway id="\(next)" name=""/>
                            """)
                        }
                        emit(child, from: previous, to: next)
                        previous = next
                    }
                case .xor(let children):
                    let split = next("Gateway")
                    let merge = next("Gateway")
                    elements.append("""
                    <bpmn:exclusiveGateway id="\(split)" name=""/>
                    """)
                    elements.append("""
                    <bpmn:exclusiveGateway id="\(merge)" name=""/>
                    """)
                    flow(from, split)
                    for child in children { emit(child, from: split, to: merge) }
                    flow(merge, to)
                }
            }
        }
        let emitter = Emitter()
        emitter.elements.append("""
        <bpmn:startEvent id="Start"/>
        """)
        emitter.elements.append("""
        <bpmn:endEvent id="End"/>
        """)
        emitter.emit(tree, from: "Start", to: "End")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
                          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                          targetNamespace="https://processlink.local/bpmn">
          <bpmn:process id="\(InductiveDiscovery.xml(id))" name="\(InductiveDiscovery.xml(name))" isExecutable="false">
        \(emitter.elements.joined(separator: "\n"))
        \(emitter.flows.joined(separator: "\n"))
          </bpmn:process>
        </bpmn:definitions>
        """
    }

    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Optimal alignment (sequence model)

public struct AlignmentMove: Sendable, Hashable {
    public var kind: String   // sync, log, model
    public var activity: String
}

public struct CaseAlignment: Sendable, Identifiable {
    public var id: String { caseID }
    public var caseID: String
    public var cost: Int
    public var fitness: Double
    public var moves: [AlignmentMove]
}

public struct AlignmentReport: Sendable {
    public var fitness: Double
    public var totalCost: Int
    public var perfectCases: Int
    public var totalCases: Int
    public var cases: [CaseAlignment]
}

public enum Alignment {
    /// Optimal alignment against a sequence model: synchronous moves cost 0,
    /// log-only and model-only moves cost 1. Dynamic programming gives the
    /// minimum edit path (and the moves for the case explorer).
    public static func sequence(_ events: [EventLogRecord], reference: [String]) -> AlignmentReport {
        let grouped = Dictionary(grouping: events, by: \.caseID)
        guard !reference.isEmpty else {
            return AlignmentReport(fitness: 0, totalCost: 0, perfectCases: 0,
                                   totalCases: grouped.count, cases: [])
        }
        var results: [CaseAlignment] = []
        var totalCost = 0
        var perfect = 0
        for (caseID, caseEvents) in grouped {
            let sequence = caseEvents.sorted { $0.timestamp < $1.timestamp }.map(\.activity)
            let result = align(sequence, reference)
            totalCost += result.cost
            if result.cost == 0 { perfect += 1 }
            results.append(CaseAlignment(caseID: caseID, cost: result.cost,
                                         fitness: result.fitness, moves: result.moves))
        }
        let logLength = grouped.values.reduce(0) { $0 + $1.count }
        let denominator = max(1, logLength + reference.count * grouped.count)
        return AlignmentReport(
            fitness: max(0, 1 - Double(totalCost) / Double(denominator)),
            totalCost: totalCost, perfectCases: perfect, totalCases: results.count,
            cases: results.sorted { $0.cost > $1.cost })
    }

    private static func align(_ log: [String], _ model: [String]) -> (cost: Int, fitness: Double, moves: [AlignmentMove]) {
        let n = log.count, m = model.count
        var dp = Array(repeating: Array(repeating: Int.max / 2, count: m + 1), count: n + 1)
        dp[0][0] = 0
        for i in 1...n { dp[i][0] = i }
        for j in 1...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sync = log[i - 1] == model[j - 1] ? dp[i - 1][j - 1] : Int.max / 2
                    dp[i][j] = min(sync, dp[i - 1][j] + 1, dp[i][j - 1] + 1)
                }
            }
        }
        var moves: [AlignmentMove] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, log[i - 1] == model[j - 1], dp[i][j] == dp[i - 1][j - 1] {
                moves.append(AlignmentMove(kind: "sync", activity: log[i - 1])); i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                moves.append(AlignmentMove(kind: "log", activity: log[i - 1])); i -= 1
            } else if j > 0, dp[i][j] == dp[i][j - 1] + 1 {
                moves.append(AlignmentMove(kind: "model", activity: model[j - 1])); j -= 1
            } else {
                break
            }
        }
        let cost = dp[n][m]
        let denominator = max(1, n + m)
        return (cost, max(0, 1 - Double(cost) / Double(denominator)), moves.reversed())
    }
}

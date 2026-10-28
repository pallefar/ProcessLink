import Foundation

/// The graph algorithms the UI needs, kept pure so they are testable without
/// SwiftData or a view. The app maps its records into these lite values.
public struct GraphNode: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: KGKind
    public var name: String
    public var confidence: Double
    public var validTo: Date?

    public init(id: String, kind: KGKind, name: String, confidence: Double, validTo: Date? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.confidence = confidence
        self.validTo = validTo
    }
}

public struct GraphEdge: Sendable, Hashable {
    public var from: String
    public var to: String
    public var predicate: RelationKind
    public var confidence: Double

    public init(from: String, to: String, predicate: RelationKind, confidence: Double) {
        self.from = from
        self.to = to
        self.predicate = predicate
        self.confidence = confidence
    }
}

public struct DuplicatePair: Sendable, Hashable, Identifiable {
    public var id: String { "\(left)|\(right)" }
    public var left: String
    public var right: String
    public var similarity: Double
}

public enum KGGraph {
    public static func orphanIDs(nodes: [GraphNode], edges: [GraphEdge]) -> Set<String> {
        let connected = Set(edges.flatMap { [$0.from, $0.to] })
        return Set(nodes.filter { !connected.contains($0.id) }.map(\.id))
    }

    public static func neighbours(of id: String, in edges: [GraphEdge]) -> Set<String> {
        var result: Set<String> = []
        for edge in edges {
            if edge.from == id { result.insert(edge.to) }
            if edge.to == id { result.insert(edge.from) }
        }
        return result
    }

    /// Two hops out, excluding the origin. Used by the radial graph view.
    public static func neighbourhood(of id: String, in edges: [GraphEdge], depth: Int = 2) -> Set<String> {
        var visited: Set<String> = [id]
        var frontier: Set<String> = [id]
        for _ in 0..<max(1, depth) {
            var next: Set<String> = []
            for node in frontier {
                next.formUnion(neighbours(of: node, in: edges))
            }
            next.subtract(visited)
            visited.formUnion(next)
            frontier = next
            if frontier.isEmpty { break }
        }
        return visited
    }

    /// Token + trigram similarity, 0...1. Deliberately explainable rather than
    /// a model: a reviewer can see why two names were proposed.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let left = normalise(a)
        let right = normalise(b)
        if left == right { return 1 }
        if left.isEmpty || right.isEmpty { return 0 }
        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let tokenUnion = leftTokens.union(rightTokens)
        let tokenScore = tokenUnion.isEmpty ? 0 : Double(leftTokens.intersection(rightTokens).count) / Double(tokenUnion.count)

        let leftTrigrams = trigrams(left)
        let rightTrigrams = trigrams(right)
        let triUnion = leftTrigrams.union(rightTrigrams)
        let triScore = triUnion.isEmpty ? 0 : Double(leftTrigrams.intersection(rightTrigrams).count) / Double(triUnion.count)
        let combined = 0.45 * tokenScore + 0.55 * triScore

        // "SAP S/4HANA" and "SAP S4HANA" are the same product written two
        // ways; collapsing separators before the bigram comparison catches it.
        let compactDice = bigramDice(left.replacingOccurrences(of: " ", with: ""),
                                     right.replacingOccurrences(of: " ", with: ""))
        return max(combined, compactDice)
    }

    private static func bigramDice(_ a: String, _ b: String) -> Double {
        let left = Array(a)
        let right = Array(b)
        guard left.count > 1, right.count > 1 else { return a == b ? 1 : 0 }
        var counts: [String: Int] = [:]
        for index in 0..<(left.count - 1) {
            counts[String(left[index...index + 1]), default: 0] += 1
        }
        var common = 0
        for index in 0..<(right.count - 1) {
            let gram = String(right[index...index + 1])
            if let count = counts[gram], count > 0 {
                common += 1
                counts[gram] = count - 1
            }
        }
        return 2 * Double(common) / Double((left.count - 1) + (right.count - 1))
    }

    public static func duplicatePairs(nodes: [GraphNode], threshold: Double = 0.72) -> [DuplicatePair] {
        var pairs: [DuplicatePair] = []
        let active = nodes.filter { $0.validTo == nil }
        // Only kinds where a human merge makes sense. Two savings records that
        // share a template ("130 h · Committed") are not duplicates.
        let mergeable: Set<KGKind> = [
            .process, .subprocess, .application, .system, .role, .team,
            .site, .businessUnit, .valueStream, .document, .control, .risk,
        ]
        for index in active.indices {
            for other in active.indices where other > index {
                let a = active[index]
                let b = active[other]
                guard a.kind == b.kind, mergeable.contains(a.kind) else { continue }
                let score = similarity(a.name, b.name)
                if score >= threshold {
                    pairs.append(DuplicatePair(left: a.id, right: b.id, similarity: score))
                }
            }
        }
        return pairs.sorted { $0.similarity > $1.similarity }
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trigrams(_ text: String) -> Set<String> {
        let padded = "  \(text) "
        let characters = Array(padded)
        guard characters.count >= 3 else { return [padded] }
        var result: Set<String> = []
        for index in 0...(characters.count - 3) {
            result.insert(String(characters[index...index + 2]))
        }
        return result
    }
}

import CryptoKit
import Foundation

// MARK: - Event log

/// One event in a process log. `caseID` is always a hash by the time it
/// reaches here; `resource` is a role, never a person.
public struct EventLogRecord: Sendable, Hashable {
    public var caseID: String
    public var activity: String
    public var timestamp: Date
    public var resource: String
    public var application: String

    public init(caseID: String, activity: String, timestamp: Date,
                resource: String, application: String = "") {
        self.caseID = caseID
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.application = application
    }
}

public struct MiningColumnMap: Sendable, Hashable {
    public var caseID: String
    public var activity: String
    public var timestamp: String
    public var resource: String
    public var application: String?

    public init(caseID: String = "case_id", activity: String = "activity",
                timestamp: String = "timestamp", resource: String = "resource",
                application: String? = nil) {
        self.caseID = caseID
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.application = application
    }
}

public enum MiningError: Error, LocalizedError, Equatable {
    case empty
    case missingColumn(String)
    case noRows
    case unreadableTimestamp(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "The file is empty."
        case .missingColumn(let name): "The file has no '\(name)' column."
        case .noRows: "No complete rows were found."
        case .unreadableTimestamp(let value): "Could not read the timestamp '\(value)'."
        }
    }
}

public struct EventLogImport: Sendable {
    public var events: [EventLogRecord]
    public var rowCount: Int
    public var skippedRows: Int
    public var caseCount: Int
    public var firstTimestamp: Date?
    public var lastTimestamp: Date?
    public var detectedDelimiter: Character
}

/// A small, explainable CSV importer. It does not try to understand a
/// customer's schema: the sheet maps columns, this maps rows.
public enum EventLogImporter {
    public static func headers(in text: String, delimiter: Character? = nil) -> [String] {
        guard let first = text.split(whereSeparator: \.isNewline).first else { return [] }
        let resolved = delimiter ?? detectDelimiter(String(first))
        return parseLine(String(first), delimiter: resolved).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func detectDelimiter(_ line: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        let scored = candidates.map { candidate in
            (candidate, line.filter { $0 == candidate }.count)
        }
        return scored.max { $0.1 < $1.1 }?.0 ?? ","
    }

    public static func importCSV(_ text: String, mapping: MiningColumnMap = MiningColumnMap(),
                                 delimiter explicit: Character? = nil,
                                 anonymizeCaseIDs: Bool = true) throws -> EventLogImport {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw MiningError.empty }
        let delimiter = explicit ?? detectDelimiter(lines[0])
        let header = parseLine(lines[0], delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(_ name: String?) throws -> Int? {
            guard let name else { return nil }
            guard let index = header.firstIndex(of: name.lowercased()) else {
                throw MiningError.missingColumn(name)
            }
            return index
        }
        let caseIndex = try index(mapping.caseID)
        let activityIndex = try index(mapping.activity)
        let timestampIndex = try index(mapping.timestamp)
        let resourceIndex = try index(mapping.resource)
        let applicationIndex = try index(mapping.application)
        guard let caseIndex, let activityIndex, let timestampIndex, let resourceIndex else {
            throw MiningError.empty
        }

        var events: [EventLogRecord] = []
        var skipped = 0
        for line in lines.dropFirst() {
            let cells = parseLine(line, delimiter: delimiter)
            func cell(_ index: Int?) -> String {
                guard let index, cells.indices.contains(index) else { return "" }
                return cells[index].trimmingCharacters(in: .whitespaces)
            }
            let rawCase = cell(caseIndex)
            let rawActivity = cell(activityIndex)
            let rawTimestamp = cell(timestampIndex)
            let rawResource = cell(resourceIndex)
            guard !rawCase.isEmpty, !rawActivity.isEmpty, !rawTimestamp.isEmpty else {
                skipped += 1
                continue
            }
            guard let timestamp = parseTimestamp(rawTimestamp) else {
                skipped += 1
                continue
            }
            // Text fields are untrusted: mask anything that looks personal.
            let activity = PIIScanner.scan(rawActivity).maskedText
            let resource = sanitiseResource(rawResource)
            let application = sanitiseResource(cell(applicationIndex))
            events.append(EventLogRecord(
                caseID: anonymizeCaseIDs ? hashed(rawCase) : rawCase,
                activity: activity,
                timestamp: timestamp,
                resource: resource,
                application: application))
        }
        guard !events.isEmpty else { throw MiningError.noRows }
        events.sort { $0.timestamp < $1.timestamp }
        let cases = Set(events.map(\.caseID))
        return EventLogImport(events: events, rowCount: lines.count - 1,
                              skippedRows: skipped, caseCount: cases.count,
                              firstTimestamp: events.first?.timestamp,
                              lastTimestamp: events.last?.timestamp,
                              detectedDelimiter: delimiter)
    }

    /// Header names the demo file uses, for the import preview.
    public static let sampleHeader = "case_id,activity,timestamp,resource,application"

    /// 24 synthetic orders across three variants. No real tenant data.
    public static func sampleCSV() -> String {
        var lines = [sampleHeader]
        let base = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for index in 0..<24 {
            let caseID = String(format: "ORD-2026-%04d", index + 1)
            var time = base.addingTimeInterval(Double(index % 12) * 86_400 + Double(index) * 1_800)
            let variant = index % 3
            func add(_ activity: String, _ minutes: Double, _ role: String, _ app: String) {
                lines.append("\(caseID),\(activity),\(formatter.string(from: time)),\(role),\(app)")
                time = time.addingTimeInterval(minutes * 60)
            }
            add("Receive order", 6, "Order Desk", "Outlook")
            add("Check customer master", 9, "Order Desk", "SAP S/4HANA")
            if variant == 2 {
                add("Clear exception queue", 11 + Double(index % 4), "Order Desk", "Salesforce")
            }
            add("Validate pricing", 12, index % 2 == 0 ? "Pricing Analyst" : "Order Desk", "Salesforce")
            if variant == 1 {
                add("Release credit hold", 4 + Double(index % 3), "Credit Manager", "SAP S/4HANA")
            }
            add("Create sales order", 14, "Order Desk", "SAP S/4HANA")
            if variant == 2 {
                add("Clear exception queue", 8, "Order Desk", "Salesforce")
            }
            add("Send confirmation", 3, "Order Desk", "Outlook")
        }
        return lines.joined(separator: "\n")
    }

    private static func hashed(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "case-" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitiseResource(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Unassigned" }
        let lower = trimmed.lowercased()
        if lower.contains("@") || trimmed.filter(\.isNumber).count > 4 {
            return "role-" + String(hashed(trimmed).suffix(4))
        }
        return trimmed
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
                       "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm",
                       "MM/dd/yyyy HH:mm:ss", "yyyy-MM-dd HH:mm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                if quoted, line.index(after: index) < line.endIndex, line[line.index(after: index)] == "\"" {
                    current.append("\"")
                    index = line.index(index, offsetBy: 2)
                    continue
                }
                quoted.toggle()
            } else if character == delimiter && !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        cells.append(current)
        return cells
    }
}

// MARK: - Mining

public struct MinedActivity: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var events: Int
    public var cases: Int
    public var averageWaitMinutes: Double
    public var reworkCount: Int
    public var handoffs: Int
    public var resources: [String]
    public var automationScore: Double
    public var automationReason: String
}

public struct MinedEdge: Sendable, Hashable, Identifiable {
    public var id: String { "\(from)→\(to)" }
    public var from: String
    public var to: String
    public var count: Int
    public var averageWaitMinutes: Double
}

public struct MinedVariant: Sendable, Hashable, Identifiable {
    public var id: String { sequence.joined(separator: "→") }
    public var sequence: [String]
    public var cases: Int
    public var share: Double
    public var averageCycleMinutes: Double
    public var reworkRate: Double
    public var hasRework: Bool
}

public struct MinedProcess: Sendable {
    public var name: String
    public var events: Int
    public var cases: Int
    public var activities: [MinedActivity]
    public var edges: [MinedEdge]
    public var variants: [MinedVariant]
    public var medianCycleMinutes: Double
    public var p90CycleMinutes: Double
    public var reworkRate: Double
    public var handoffRate: Double
    public var startActivities: [String]
    public var endActivities: [String]
    public var firstTimestamp: Date?
    public var lastTimestamp: Date?

    public var topVariant: MinedVariant? { variants.first }
    public var bottleneck: MinedActivity? {
        activities.max { $0.averageWaitMinutes + Double($0.reworkCount) * 2 < $1.averageWaitMinutes + Double($1.reworkCount) * 2 }
    }
    public var automationCandidates: [MinedActivity] {
        activities.filter { $0.automationScore >= 0.55 }.sorted { $0.automationScore > $1.automationScore }
    }
}

public struct ConformanceReport: Sendable, Hashable {
    public var fitness: Double
    public var exactCases: Int
    public var totalCases: Int
    public var missingActivities: [String]
    public var extraActivities: [String]
}

public enum ProcessMining {
    public static func mine(_ events: [EventLogRecord], name: String) -> MinedProcess {
        let grouped = Dictionary(grouping: events, by: \.caseID)
        var sequences: [[String]] = []
        var caseSequences: [([String], Double)] = []
        var cycles: [Double] = []
        var repeated = 0
        var totalEvents = 0
        var handoffs = 0
        var activityEvents: [String: Int] = [:]
        var activityCases: [String: Set<String>] = [:]
        var activityWaits: [String: [Double]] = [:]
        var activityRework: [String: Int] = [:]
        var activityHandoffs: [String: Int] = [:]
        var activityResources: [String: Set<String>] = [:]
        var edgeCounts: [String: Int] = [:]
        var edgeWaits: [String: [Double]] = [:]
        var starts: [String: Int] = [:]
        var ends: [String: Int] = [:]

        for (caseID, caseEvents) in grouped {
            let ordered = caseEvents.sorted { $0.timestamp < $1.timestamp }
            guard !ordered.isEmpty else { continue }
            let sequence = ordered.map(\.activity)
            sequences.append(sequence)
            if let first = ordered.first, let last = ordered.last {
                let cycle = last.timestamp.timeIntervalSince(first.timestamp) / 60
                cycles.append(cycle)
                caseSequences.append((sequence, cycle))
            }
            if let first = ordered.first { starts[first.activity, default: 0] += 1 }
            if let last = ordered.last { ends[last.activity, default: 0] += 1 }
            var seen: Set<String> = []
            var previous: EventLogRecord?
            for event in ordered {
                totalEvents += 1
                activityEvents[event.activity, default: 0] += 1
                activityCases[event.activity, default: []].insert(caseID)
                activityResources[event.activity, default: []].insert(event.resource)
                if seen.contains(event.activity) {
                    repeated += 1
                    activityRework[event.activity, default: 0] += 1
                }
                seen.insert(event.activity)
                if let previous {
                    let wait = event.timestamp.timeIntervalSince(previous.timestamp) / 60
                    activityWaits[event.activity, default: []].append(max(0, wait))
                    let key = "\(previous.activity)→\(event.activity)"
                    edgeCounts[key, default: 0] += 1
                    edgeWaits[key, default: []].append(max(0, wait))
                    if previous.resource != event.resource {
                        handoffs += 1
                        activityHandoffs[event.activity, default: 0] += 1
                    }
                }
                previous = event
            }
        }

        let caseCount = grouped.count
        let activities = activityEvents.map { name, count -> MinedActivity in
            let waits = activityWaits[name] ?? []
            let averageWait = waits.isEmpty ? 0 : waits.reduce(0, +) / Double(waits.count)
            let resources = Array(activityResources[name] ?? []).sorted()
            let rework = activityRework[name] ?? 0
            let score = automationScore(events: count, cases: activityCases[name]?.count ?? 0,
                                         averageWait: averageWait, resources: resources.count,
                                         rework: rework)
            return MinedActivity(
                name: name, events: count, cases: activityCases[name]?.count ?? 0,
                averageWaitMinutes: averageWait, reworkCount: rework,
                handoffs: activityHandoffs[name] ?? 0, resources: resources,
                automationScore: score.score, automationReason: score.reason)
        }.sorted { $0.events > $1.events }

        let edges = edgeCounts.map { key, count -> MinedEdge in
            let parts = key.components(separatedBy: "→")
            let waits = edgeWaits[key] ?? []
            return MinedEdge(from: parts.first ?? "", to: parts.last ?? "", count: count,
                             averageWaitMinutes: waits.isEmpty ? 0 : waits.reduce(0, +) / Double(waits.count))
        }.sorted { $0.count > $1.count }

        var variantCounts: [String: (cases: Int, cycles: [Double], rework: Int, events: Int)] = [:]
        for (sequence, cycle) in caseSequences {
            let key = sequence.joined(separator: " → ")
            var entry = variantCounts[key] ?? (0, [], 0, 0)
            entry.cases += 1
            entry.events += sequence.count
            entry.rework += sequence.count - Set(sequence).count
            entry.cycles.append(cycle)
            variantCounts[key] = entry
        }
        let variants = variantCounts.map { key, value -> MinedVariant in
            let sequence = key.components(separatedBy: " → ")
            return MinedVariant(
                sequence: sequence, cases: value.cases,
                share: caseCount == 0 ? 0 : Double(value.cases) / Double(caseCount),
                averageCycleMinutes: value.cycles.isEmpty ? 0 : value.cycles.reduce(0, +) / Double(value.cycles.count),
                reworkRate: value.events == 0 ? 0 : Double(value.rework) / Double(value.events),
                hasRework: value.rework > 0)
        }.sorted { $0.cases > $1.cases }

        cycles.sort()
        return MinedProcess(
            name: name, events: events.count, cases: caseCount,
            activities: activities, edges: edges, variants: variants,
            medianCycleMinutes: percentile(cycles, 0.5),
            p90CycleMinutes: percentile(cycles, 0.9),
            reworkRate: totalEvents == 0 ? 0 : Double(repeated) / Double(totalEvents),
            handoffRate: totalEvents == 0 ? 0 : Double(handoffs) / Double(max(1, totalEvents - caseCount)),
            startActivities: starts.sorted { $0.value > $1.value }.map(\.key),
            endActivities: ends.sorted { $0.value > $1.value }.map(\.key),
            firstTimestamp: events.map(\.timestamp).min(),
            lastTimestamp: events.map(\.timestamp).max())
    }

    /// Reference-sequence conformance: exact-match share plus average LCS
    /// coverage. Deliberately simple enough to explain in a review.
    public static func conformance(events: [EventLogRecord], reference: [String]) -> ConformanceReport {
        let grouped = Dictionary(grouping: events, by: \.caseID)
        guard !reference.isEmpty, !grouped.isEmpty else {
            return ConformanceReport(fitness: 0, exactCases: 0, totalCases: grouped.count,
                                     missingActivities: reference, extraActivities: [])
        }
        var exact = 0
        var fitnessTotal = 0.0
        var missing: Set<String> = []
        var extra: Set<String> = []
        for (_, caseEvents) in grouped {
            let sequence = caseEvents.sorted { $0.timestamp < $1.timestamp }.map(\.activity)
            if sequence == reference { exact += 1 }
            let lcs = longestCommonSubsequence(sequence, reference).count
            fitnessTotal += Double(lcs) / Double(reference.count)
            missing.formUnion(reference.filter { !sequence.contains($0) })
            extra.formUnion(sequence.filter { !reference.contains($0) })
        }
        return ConformanceReport(
            fitness: min(1, fitnessTotal / Double(grouped.count)),
            exactCases: exact, totalCases: grouped.count,
            missingActivities: missing.sorted(), extraActivities: extra.sorted())
    }

    private static func automationScore(events: Int, cases: Int, averageWait: Double,
                                        resources: Int, rework: Int) -> (score: Double, reason: String) {
        let volume = min(1, Double(events) / 100)
        let repetition = min(1, Double(rework) / Double(max(1, events)))
        let roleSpread = resources <= 1 ? 1.0 : resources == 2 ? 0.7 : 0.4
        let score = 0.45 * volume + 0.3 * repetition + 0.25 * roleSpread
        let reason: String
        if score >= 0.7 {
            reason = "High volume, repeated work and a narrow role set."
        } else if score >= 0.55 {
            reason = "Enough volume and repetition to test a standard or a bot."
        } else {
            reason = "Needs more volume or repetition before automation is credible."
        }
        return (score, reason)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                table[i][j] = a[i - 1] == b[j - 1]
                    ? table[i - 1][j - 1] + 1
                    : max(table[i - 1][j], table[i][j - 1])
            }
        }
        var result: [String] = []
        var i = a.count, j = b.count
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] { result.append(a[i - 1]); i -= 1; j -= 1 }
            else if table[i - 1][j] >= table[i][j - 1] { i -= 1 }
            else { j -= 1 }
        }
        return result.reversed()
    }
}

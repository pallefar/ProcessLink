import CryptoKit
import Foundation

// MARK: - Event log

/// One event in a process log. `caseID` is always a hash by the time it
/// reaches here; `resource` is a role, never a person.
public struct EventLogRecord: Sendable {
    public var caseID: String
    public var activity: String
    public var timestamp: Date
    public var resource: String
    public var application: String
    /// Additional dimensions kept for filtering and root-cause analysis.
    /// Values are masked/sanitised at import time, exactly like activity.
    public var attributes: [String: String]
    public var cost: Double?

    public init(caseID: String, activity: String, timestamp: Date,
                resource: String, application: String = "",
                attributes: [String: String] = [:], cost: Double? = nil) {
        self.caseID = caseID
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.application = application
        self.attributes = attributes
        self.cost = cost
    }
}

public struct MiningColumnMap: Sendable, Hashable {
    public var caseID: String
    public var activity: String
    public var timestamp: String
    public var resource: String
    public var application: String?
    /// Extra columns to import as case/event attributes. Empty means "all
    /// columns not used by the core mapping", which is the useful default.
    public var attributes: [String]
    public var cost: String?

    public init(caseID: String = "case_id", activity: String = "activity",
                timestamp: String = "timestamp", resource: String = "resource",
                application: String? = nil, attributes: [String] = [],
                cost: String? = nil) {
        self.caseID = caseID
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.application = application
        self.attributes = attributes
        self.cost = cost
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
    public var attributeNames: [String]
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
        let originalHeader = parseLine(lines[0], delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let header = originalHeader.map { $0.lowercased() }
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
        let applicationIndex = try index(mapping.application) ?? header.firstIndex(of: "application")
        let costIndex = try index(mapping.cost) ?? header.firstIndex(of: "cost")
        guard let caseIndex, let activityIndex, let timestampIndex, let resourceIndex else {
            throw MiningError.empty
        }
        let core = Set([caseIndex, activityIndex, timestampIndex, resourceIndex,
                        applicationIndex, costIndex].compactMap { $0 })
        let requested = Set(mapping.attributes.map { $0.lowercased() })
        let attributeColumns: [(Int, String)] = originalHeader.enumerated().compactMap { index, name in
            guard !core.contains(index), !name.isEmpty else { return nil }
            if !requested.isEmpty && !requested.contains(name.lowercased()) { return nil }
            return (index, name)
        }.prefix(16).map { $0 }
        let attributeNames = attributeColumns.map(\.1)

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
            var attributes: [String: String] = [:]
            for (index, name) in attributeColumns {
                let raw = cell(index)
                guard !raw.isEmpty else { continue }
                attributes[name] = PIIScanner.scan(raw).maskedText
            }
            let rawCost = cell(costIndex).replacingOccurrences(of: ",", with: ".")
            events.append(EventLogRecord(
                caseID: anonymizeCaseIDs ? hashed(rawCase) : rawCase,
                activity: activity,
                timestamp: timestamp,
                resource: resource,
                application: application,
                attributes: attributes,
                cost: Double(rawCost)))
        }
        guard !events.isEmpty else { throw MiningError.noRows }
        events.sort { $0.timestamp < $1.timestamp }
        let cases = Set(events.map(\.caseID))
        return EventLogImport(events: events, rowCount: lines.count - 1,
                              skippedRows: skipped, caseCount: cases.count,
                              firstTimestamp: events.first?.timestamp,
                              lastTimestamp: events.last?.timestamp,
                              detectedDelimiter: delimiter,
                              attributeNames: attributeNames)
    }

    /// Header names the demo file uses, for the import preview.
    public static let sampleHeader = "case_id,activity,timestamp,resource,application,case_type,region,cost"

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
            let caseType = variant == 2 ? "Expedite" : "Standard"
            let region = index % 2 == 0 ? "DE" : "PL"
            let caseCost = variant == 2 ? 180.0 : 120.0
            func add(_ activity: String, _ minutes: Double, _ role: String, _ app: String) {
                let cost = caseCost / 5
                lines.append("\(caseID),\(activity),\(formatter.string(from: time)),\(role),\(app),\(caseType),\(region),\(String(format: "%.2f", cost))")
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
    public var meanCycleMinutes: Double
    public var maxCycleMinutes: Double
    public var reworkRate: Double
    public var handoffRate: Double
    public var startActivities: [String]
    public var endActivities: [String]
    public var firstTimestamp: Date?
    public var lastTimestamp: Date?
    public var periods: [MiningPeriod]
    public var handovers: [MiningHandover]
    public var caseRecords: [MinedCase]
    public var totalCost: Double
    public var costPerCase: Double
    public var casesWithRework: Int

    public var topVariant: MinedVariant? { variants.first }
    public var bottleneck: MinedActivity? {
        activities.max { $0.averageWaitMinutes + Double($0.reworkCount) * 2 < $1.averageWaitMinutes + Double($1.reworkCount) * 2 }
    }
    public var automationCandidates: [MinedActivity] {
        activities.filter { $0.automationScore >= 0.55 }.sorted { $0.automationScore > $1.automationScore }
    }
}

// MARK: - Filters, cases and advanced mining

public struct MiningFilter: Sendable, Equatable {
    public var from: Date?
    public var to: Date?
    public var activities: Set<String> = []
    public var resources: Set<String> = []
    public var variants: Set<String> = []
    public var attributes: [String: String] = [:]
    public var onlyRework = false
    public var minCycleMinutes: Double?
    public var maxCycleMinutes: Double?

    public init(from: Date? = nil, to: Date? = nil, activities: Set<String> = [],
                resources: Set<String> = [], variants: Set<String> = [],
                attributes: [String: String] = [:], onlyRework: Bool = false,
                minCycleMinutes: Double? = nil, maxCycleMinutes: Double? = nil) {
        self.from = from
        self.to = to
        self.activities = activities
        self.resources = resources
        self.variants = variants
        self.attributes = attributes
        self.onlyRework = onlyRework
        self.minCycleMinutes = minCycleMinutes
        self.maxCycleMinutes = maxCycleMinutes
    }

    public var isActive: Bool {
        from != nil || to != nil || !activities.isEmpty || !resources.isEmpty
            || !variants.isEmpty || !attributes.isEmpty || onlyRework
            || minCycleMinutes != nil || maxCycleMinutes != nil
    }
}

public struct MinedCase: Sendable, Identifiable {
    public var id: String { caseID }
    public var caseID: String
    public var events: [EventLogRecord]
    public var sequence: [String]
    public var start: Date
    public var end: Date
    public var cycleMinutes: Double
    public var waitingMinutes: Double
    public var reworkCount: Int
    public var handoffs: Int
    public var resources: [String]
    public var attributes: [String: String]
    public var cost: Double
    public var variant: String { sequence.joined(separator: " → ") }
}

public struct MiningPeriod: Sendable, Identifiable, Hashable {
    public var id: String { label }
    public var label: String
    public var start: Date
    public var cases: Int
    public var medianCycleMinutes: Double
    public var reworkRate: Double
}

public struct MiningHandover: Sendable, Identifiable, Hashable {
    public var id: String { "\(from)→\(to)" }
    public var from: String
    public var to: String
    public var count: Int
    public var averageWaitMinutes: Double
}

public enum MiningOutcome: String, Sendable, CaseIterable, Identifiable {
    case rework
    case slow

    public var id: String { rawValue }
    public var label: String { self == .rework ? "Rework" : "Slow cases" }
}

public struct MiningRootCause: Sendable, Identifiable, Hashable {
    public var id: String { "\(dimension)=\(value)" }
    public var dimension: String
    public var value: String
    public var cases: Int
    public var averageCycleMinutes: Double
    public var reworkRate: Double
    public var impact: Double
    public var impactLabel: String
}

public struct MiningSimulation: Sendable, Equatable {
    public var automate: Set<String> = []
    public var remove: Set<String> = []
    public var reworkReduction: Double = 0
    public var waitReduction: Double = 0
    public init(automate: Set<String> = [], remove: Set<String> = [],
                reworkReduction: Double = 0, waitReduction: Double = 0) {
        self.automate = automate
        self.remove = remove
        self.reworkReduction = reworkReduction
        self.waitReduction = waitReduction
    }
}

public struct MiningSimulationResult: Sendable {
    public var baselineMedianMinutes: Double
    public var projectedMedianMinutes: Double
    public var savedMedianMinutes: Double
    public var savedHoursPer1000: Double
    public var casesAffected: Int
    public var assumptions: [String]
}

public struct ConformanceReport: Sendable, Hashable {
    public var fitness: Double
    public var exactCases: Int
    public var totalCases: Int
    public var missingActivities: [String]
    public var extraActivities: [String]
    public var tokenFitness: Double = 0
    public var missingTokens: Int = 0
    public var remainingTokens: Int = 0
    public var consumedTokens: Int = 0
    public var producedTokens: Int = 0
    public var deviatingCases: Int = 0
}

public enum ProcessMining {
    public static func buildCases(_ events: [EventLogRecord]) -> [MinedCase] {
        Dictionary(grouping: events, by: \.caseID).compactMap { caseID, caseEvents -> MinedCase? in
            let ordered = caseEvents.sorted { $0.timestamp < $1.timestamp }
            guard let first = ordered.first, let last = ordered.last else { return nil }
            let sequence = ordered.map(\.activity)
            var waiting = 0.0
            var handoffs = 0
            var previous: EventLogRecord?
            for event in ordered {
                if let previous { waiting += max(0, event.timestamp.timeIntervalSince(previous.timestamp) / 60) }
                if let previous, previous.resource != event.resource { handoffs += 1 }
                previous = event
            }
            var attributes: [String: String] = [:]
            for event in ordered {
                for (key, value) in event.attributes where attributes[key] == nil { attributes[key] = value }
            }
            return MinedCase(
                caseID: caseID, events: ordered, sequence: sequence,
                start: first.timestamp, end: last.timestamp,
                cycleMinutes: max(0, last.timestamp.timeIntervalSince(first.timestamp) / 60),
                waitingMinutes: waiting,
                reworkCount: sequence.count - Set(sequence).count,
                handoffs: handoffs,
                resources: Array(Set(ordered.map(\.resource))).sorted(),
                attributes: attributes,
                cost: ordered.compactMap(\.cost).reduce(0, +))
        }.sorted { $0.start < $1.start }
    }

    /// Event-level filters first, then case-level filters (variant, cycle,
    /// rework). Filtering at the case level keeps a case's timeline intact.
    public static func filter(_ events: [EventLogRecord], with filter: MiningFilter) -> [EventLogRecord] {
        guard filter.isActive else { return events }
        var scoped = events.filter { event in
            if let from = filter.from, event.timestamp < from { return false }
            if let to = filter.to, event.timestamp > to { return false }
            if !filter.activities.isEmpty && !filter.activities.contains(event.activity) { return false }
            if !filter.resources.isEmpty && !filter.resources.contains(event.resource) { return false }
            for (key, value) in filter.attributes where event.attributes[key] != value { return false }
            return true
        }
        let records = buildCases(scoped)
        let allowed = records.filter { record in
            if !filter.variants.isEmpty && !filter.variants.contains(record.variant) { return false }
            if filter.onlyRework && record.reworkCount == 0 { return false }
            if let min = filter.minCycleMinutes, record.cycleMinutes < min { return false }
            if let max = filter.maxCycleMinutes, record.cycleMinutes > max { return false }
            return true
        }.map(\.caseID)
        let allowedSet = Set(allowed)
        scoped = scoped.filter { allowedSet.contains($0.caseID) }
        return scoped.sorted { $0.timestamp < $1.timestamp }
    }

    public static func periods(_ cases: [MinedCase]) -> [MiningPeriod] {
        let calendar = Calendar(identifier: .iso8601)
        var grouped: [String: (Date, [MinedCase])] = [:]
        for record in cases {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.start)
            guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else { continue }
            let key = String(format: "%04d-W%02d", year, week)
            let weekStart = calendar.date(from: components) ?? record.start
            var entry = grouped[key] ?? (weekStart, [])
            entry.1.append(record)
            grouped[key] = entry
        }
        return grouped.map { key, value in
            let cycles = value.1.map(\.cycleMinutes).sorted()
            let rework = value.1.reduce(0) { $0 + $1.reworkCount }
            let events = value.1.reduce(0) { $0 + $1.events.count }
            return MiningPeriod(label: key, start: value.0, cases: value.1.count,
                                medianCycleMinutes: percentile(cycles, 0.5),
                                reworkRate: events == 0 ? 0 : Double(rework) / Double(events))
        }.sorted { $0.start < $1.start }.suffix(12).map { $0 }
    }

    public static func handovers(_ events: [EventLogRecord]) -> [MiningHandover] {
        var counts: [String: Int] = [:]
        var waits: [String: [Double]] = [:]
        for (_, caseEvents) in Dictionary(grouping: events, by: \.caseID) {
            let ordered = caseEvents.sorted { $0.timestamp < $1.timestamp }
            for (previous, next) in zip(ordered, ordered.dropFirst()) where previous.resource != next.resource {
                let key = "\(previous.resource)→\(next.resource)"
                counts[key, default: 0] += 1
                waits[key, default: []].append(max(0, next.timestamp.timeIntervalSince(previous.timestamp) / 60))
            }
        }
        return counts.map { key, count in
            let parts = key.components(separatedBy: "→")
            let values = waits[key] ?? []
            return MiningHandover(from: parts.first ?? "", to: parts.last ?? "", count: count,
                                  averageWaitMinutes: values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
        }.sorted { $0.count > $1.count }
    }

    /// Compare cases that had rework / ran slow against the whole population,
    /// one attribute value at a time. The impact is an hours estimate, not a
    /// causal claim.
    public static func rootCauses(_ cases: [MinedCase], outcome: MiningOutcome) -> [MiningRootCause] {
        guard !cases.isEmpty else { return [] }
        let overallCycle = cases.map(\.cycleMinutes).reduce(0, +) / Double(cases.count)
        let overallRework = Double(cases.filter { $0.reworkCount > 0 }.count) / Double(cases.count)
        var dimensions: [String: [String: [MinedCase]]] = [:]
        for record in cases {
            for (key, value) in record.attributes where !value.isEmpty {
                dimensions[key, default: [:]][value, default: []].append(record)
            }
        }
        var results: [MiningRootCause] = []
        for (dimension, values) in dimensions {
            for (value, group) in values where group.count >= max(2, cases.count / 12) {
                let cycle = group.map(\.cycleMinutes).reduce(0, +) / Double(group.count)
                let rework = Double(group.filter { $0.reworkCount > 0 }.count) / Double(group.count)
                let impact: Double
                let label: String
                switch outcome {
                case .slow:
                    impact = (cycle - overallCycle) * Double(group.count) / 60
                    let delta = cycle - overallCycle
                    label = "\(abs(delta).formatted(.number.precision(.fractionLength(0)))) min \(delta >= 0 ? "slower" : "faster") · \(group.count) cases"
                case .rework:
                    impact = (rework - overallRework) * Double(group.count)
                    label = "\(Int((rework * 100).rounded()))% rework · \(group.count) cases"
                }
                results.append(MiningRootCause(
                    dimension: dimension, value: value, cases: group.count,
                    averageCycleMinutes: cycle, reworkRate: rework, impact: impact, impactLabel: label))
            }
        }
        return results.sorted { abs($0.impact) > abs($1.impact) }.prefix(12).map { $0 }
    }

    /// What-if arithmetic on the observed case timelines. It models the wait
    /// before each event, so a removed step removes that wait, an automated
    /// step keeps 20% of it, and rework reduction removes a share of repeat
    /// waits. It is an estimate with stated assumptions, not a simulator.
    public static func simulate(_ cases: [MinedCase], _ input: MiningSimulation) -> MiningSimulationResult {
        guard !cases.isEmpty else {
            return MiningSimulationResult(baselineMedianMinutes: 0, projectedMedianMinutes: 0,
                                          savedMedianMinutes: 0, savedHoursPer1000: 0,
                                          casesAffected: 0, assumptions: [])
        }
        var baseline: [Double] = []
        var projected: [Double] = []
        var affected = 0
        for record in cases {
            var seen: Set<String> = []
            var saved = 0.0
            var previous: EventLogRecord?
            var touched = false
            for event in record.events {
                if let previous {
                    let wait = max(0, event.timestamp.timeIntervalSince(previous.timestamp) / 60)
                    if input.remove.contains(event.activity) {
                        saved += wait
                        touched = true
                    } else if input.automate.contains(event.activity) {
                        saved += wait * 0.8
                        touched = true
                    }
                    if seen.contains(event.activity), input.reworkReduction > 0 {
                        saved += wait * min(1, max(0, input.reworkReduction))
                        touched = true
                    }
                }
                seen.insert(event.activity)
                previous = event
            }
            let afterRework = max(0, record.cycleMinutes - saved)
            let remainingWait = max(0, record.waitingMinutes - saved)
            let waitReduction = remainingWait * min(1, max(0, input.waitReduction))
            baseline.append(record.cycleMinutes)
            projected.append(max(0, afterRework - waitReduction))
            if touched || input.waitReduction > 0 { affected += 1 }
        }
        baseline.sort()
        projected.sort()
        let baselineMedian = percentile(baseline, 0.5)
        let projectedMedian = percentile(projected, 0.5)
        let saved = max(0, baselineMedian - projectedMedian)
        return MiningSimulationResult(
            baselineMedianMinutes: baselineMedian,
            projectedMedianMinutes: projectedMedian,
            savedMedianMinutes: saved,
            savedHoursPer1000: saved * 1000 / 60,
            casesAffected: affected,
            assumptions: [
                "Each removed activity removes the wait before it.",
                "An automated activity keeps 20% of its wait.",
                "Rework reduction removes that share of repeat-step waits.",
                "Median cycle across \(cases.count) observed cases; not a financial promise.",
            ])
    }
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
        let records = buildCases(events)
        let totalCost = records.reduce(0) { $0 + $1.cost }
        return MinedProcess(
            name: name, events: events.count, cases: caseCount,
            activities: activities, edges: edges, variants: variants,
            medianCycleMinutes: percentile(cycles, 0.5),
            p90CycleMinutes: percentile(cycles, 0.9),
            meanCycleMinutes: cycles.isEmpty ? 0 : cycles.reduce(0, +) / Double(cycles.count),
            maxCycleMinutes: cycles.last ?? 0,
            reworkRate: totalEvents == 0 ? 0 : Double(repeated) / Double(totalEvents),
            handoffRate: totalEvents == 0 ? 0 : Double(handoffs) / Double(max(1, totalEvents - caseCount)),
            startActivities: starts.sorted { $0.value > $1.value }.map(\.key),
            endActivities: ends.sorted { $0.value > $1.value }.map(\.key),
            firstTimestamp: events.map(\.timestamp).min(),
            lastTimestamp: events.map(\.timestamp).max(),
            periods: periods(records),
            handovers: handovers(events),
            caseRecords: records,
            totalCost: totalCost,
            costPerCase: records.isEmpty ? 0 : totalCost / Double(records.count),
            casesWithRework: records.filter { $0.reworkCount > 0 }.count)
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
        var missingTokens = 0
        var remainingTokens = 0
        var consumedTokens = 0
        var producedTokens = 0
        var deviatingCases = 0
        for (_, caseEvents) in grouped {
            let sequence = caseEvents.sorted { $0.timestamp < $1.timestamp }.map(\.activity)
            if sequence == reference { exact += 1 } else { deviatingCases += 1 }
            let lcs = longestCommonSubsequence(sequence, reference).count
            fitnessTotal += Double(lcs) / Double(reference.count)
            missing.formUnion(reference.filter { !sequence.contains($0) })
            extra.formUnion(sequence.filter { !reference.contains($0) })

            // Place-based token replay against the reference sequence. A
            // missing step consumes nothing; leftover tokens at the end are
            // reported separately, so the UI can explain the number.
            var next = 0
            for activity in sequence {
                if next < reference.count, activity == reference[next] {
                    consumedTokens += 1
                    producedTokens += 1
                    next += 1
                } else if next < reference.count, reference[next...].contains(activity) {
                    missingTokens += 1
                    while next < reference.count, reference[next] != activity { next += 1 }
                    next += 1
                } else {
                    consumedTokens += 1
                }
            }
            remainingTokens += max(0, reference.count - next)
        }
        let tokenDenominator = max(1, consumedTokens + producedTokens + missingTokens + remainingTokens)
        let tokenFitness = max(0, min(1, 1 - Double(missingTokens + remainingTokens) / Double(tokenDenominator)))
        return ConformanceReport(
            fitness: min(1, fitnessTotal / Double(grouped.count)),
            exactCases: exact, totalCases: grouped.count,
            missingActivities: missing.sorted(), extraActivities: extra.sorted(),
            tokenFitness: tokenFitness, missingTokens: missingTokens,
            remainingTokens: remainingTokens, consumedTokens: consumedTokens,
            producedTokens: producedTokens, deviatingCases: deviatingCases)
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

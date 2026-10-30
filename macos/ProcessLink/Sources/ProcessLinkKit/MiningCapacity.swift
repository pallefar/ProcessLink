import Foundation

public struct CapacityRole: Sendable, Identifiable, Hashable {
    public var id: String { role }
    public var role: String
    public var capacity: Int
    public var serviceMinutes: Double

    public init(role: String, capacity: Int, serviceMinutes: Double) {
        self.role = role
        self.capacity = max(1, capacity)
        self.serviceMinutes = max(0.5, serviceMinutes)
    }
}

public struct RoleUtilization: Sendable, Identifiable, Hashable {
    public var id: String { role }
    public var role: String
    public var utilization: Double
    public var averageWaitMinutes: Double
    public var demandMinutes: Double
    public var availableMinutes: Double
    /// Staffing needed to keep this role at or below 85% utilisation.
    public var recommendedCapacity: Int
    public var capacityGap: Int
}

public struct CapacityResult: Sendable {
    public var cases: Int
    public var medianCycleMinutes: Double
    public var p90CycleMinutes: Double
    public var averageWaitMinutes: Double
    public var utilization: [RoleUtilization]
    public var assumptions: [String]
}

/// A small deterministic discrete-event simulation: cases arrive at a rate,
/// follow observed variant paths, queue for a role with finite capacity, and
/// occupy that role for a service time. It is intentionally transparent and
/// uses a fixed seed, so the same inputs produce the same picture.
public enum CapacitySimulation {
    public static func defaultRoles(for mined: MinedProcess) -> [CapacityRole] {
        var seen = Set<String>()
        var result: [CapacityRole] = []
        for activity in mined.activities {
            let role = activity.resources.first ?? "Unassigned"
            guard !seen.contains(role) else { continue }
            seen.insert(role)
            // Observed wait is the only timing signal in a plain event log.
            // The service time is deliberately labelled as an assumption.
            result.append(CapacityRole(role: role, capacity: 1,
                                       serviceMinutes: max(1, activity.averageWaitMinutes)))
        }
        return result.sorted { $0.role < $1.role }.prefix(8).map { $0 }
    }

    public static func run(_ mined: MinedProcess,
                           roles: [CapacityRole],
                           arrivalPerDay: Double,
                           days: Int,
                           workingMinutesPerDay: Double = 480,
                           breakMinutesPerDay: Double = 0,
                           workingWeekdays: Set<Int> = [2, 3, 4, 5, 6],
                           holidays: [Date] = [],
                           seed: UInt64 = 7) -> CapacityResult {
        guard !mined.caseRecords.isEmpty, !roles.isEmpty, arrivalPerDay > 0, days > 0 else {
            return CapacityResult(cases: 0, medianCycleMinutes: 0, p90CycleMinutes: 0,
                                  averageWaitMinutes: 0, utilization: [],
                                  assumptions: ["No cases or roles in the current view."])
        }
        var rng = LCG(seed: seed)
        let count = max(10, Int((arrivalPerDay * Double(days)).rounded()))
        let workingMinutes = max(60, min(1_440, workingMinutesPerDay))
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let holidayDays = Set(holidays.map { calendar.startOfDay(for: $0) })
        var workingDayOffsets: [Int] = []
        var cursor = 0
        while workingDayOffsets.count < days, cursor < days * 4 {
            if let date = calendar.date(byAdding: .day, value: cursor, to: today),
               workingWeekdays.contains(calendar.component(.weekday, from: date)),
               !holidayDays.contains(calendar.startOfDay(for: date)) {
                workingDayOffsets.append(cursor)
            }
            cursor += 1
        }
        let effectiveDays = max(1, workingDayOffsets.count)
        let breakMinutes = max(0, min(workingMinutes - 30, breakMinutesPerDay))
        let productiveMinutes = max(30, workingMinutes - breakMinutes)
        let gap = productiveMinutes / max(1, arrivalPerDay)
        let roleByName = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, $0) })
        var available = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, 0.0) })
        var busy = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, 0.0) })
        var waits = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, [Double]()) })
        var arrivals: [Double] = []
        var cycles: [Double] = []
        var totalWait = 0.0
        var horizon = 0.0

        let variants = mined.variants.isEmpty
            ? [MinedVariant(sequence: mined.activities.map(\.name), cases: mined.cases,
                            share: 1, averageCycleMinutes: mined.medianCycleMinutes,
                            reworkRate: mined.reworkRate, hasRework: mined.reworkRate > 0)]
            : mined.variants
        let activityByName = Dictionary(uniqueKeysWithValues: mined.activities.map { ($0.name, $0) })

        for index in 0..<count {
            let jitter = (rng.nextUnit() - 0.5) * gap * 0.4
            let daySlot = min(max(0, workingDayOffsets.count - 1), index / max(1, Int(arrivalPerDay)))
            let dayOffset = workingDayOffsets.isEmpty ? 0 : workingDayOffsets[daySlot]
            let arrival = Double(dayOffset) * 1_440 + 480
                + Double(index % max(1, Int(arrivalPerDay))) * gap + jitter
            arrivals.append(arrival)
            let selected = pick(variants, rng: &rng)
            var caseEnd = arrival
            for activityName in selected.sequence {
                let activity = activityByName[activityName]
                let roleName = activity?.resources.first ?? "Unassigned"
                guard let role = roleByName[roleName] else { continue }
                let start = max(caseEnd, available[roleName] ?? 0)
                let wait = max(0, start - caseEnd)
                totalWait += wait
                waits[roleName, default: []].append(wait)
                let finish = start + role.serviceMinutes
                busy[roleName, default: 0] += role.serviceMinutes
                available[roleName] = finish
                caseEnd = finish
            }
            cycles.append(max(0, caseEnd - arrival))
            horizon = max(horizon, caseEnd)
        }
        cycles.sort()
        let utilizations = roles.map { role -> RoleUtilization in
            let values = waits[role.role] ?? []
            return RoleUtilization(
                role: role.role,
                utilization: horizon <= 0 ? 0 : min(1, (busy[role.role] ?? 0) / max(1, productiveMinutes * Double(effectiveDays) * Double(role.capacity))),
                averageWaitMinutes: values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count),
                demandMinutes: busy[role.role] ?? 0,
                availableMinutes: productiveMinutes * Double(effectiveDays) * Double(role.capacity),
                recommendedCapacity: horizon <= 0 ? role.capacity
                    : max(1, Int(ceil((busy[role.role] ?? 0) / max(1, productiveMinutes * Double(effectiveDays) * 0.85)))),
                capacityGap: horizon <= 0 ? 0
                    : max(1, Int(ceil((busy[role.role] ?? 0) / max(1, productiveMinutes * Double(effectiveDays) * 0.85)))) - role.capacity)
        }
        return CapacityResult(
            cases: count,
            medianCycleMinutes: percentile(cycles, 0.5),
            p90CycleMinutes: percentile(cycles, 0.9),
            averageWaitMinutes: totalWait / Double(max(1, count)),
            utilization: utilizations,
            assumptions: [
                "Service time starts from the observed average wait per activity; replace it with a measured touch time before a business case.",
                "Cases follow the observed variant shares; the seed is fixed.",
                "Each role is a FIFO queue with the capacity shown.",
                "The staffing recommendation keeps each role at or below 85% utilisation over the simulated horizon; it is a starting point, not a roster.",
                "Arrivals are spread across a \(Int(productiveMinutes))-minute productive day (\(Int(workingMinutes)) shift minus \(Int(breakMinutes)) break); weekends and holidays are not modelled.",
            ])
    }

    private static func pick(_ variants: [MinedVariant], rng: inout LCG) -> MinedVariant {
        let value = rng.nextUnit()
        var cumulative = 0.0
        for variant in variants {
            cumulative += max(0, variant.share)
            if value <= cumulative { return variant }
        }
        return variants.last ?? variants[0]
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }

    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 1 : seed }
        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
    }
}

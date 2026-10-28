import Foundation

public enum ConnectorProvider: String, CaseIterable, Sendable, Identifiable {
    case serviceNow
    case salesforce
    case sap
    case genericJSON

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .serviceNow: "ServiceNow"
        case .salesforce: "Salesforce"
        case .sap: "SAP"
        case .genericJSON: "Generic REST / JSON"
        }
    }

    public var defaultPath: String {
        switch self {
        case .serviceNow: "/api/now/table/sys_audit?sysparm_limit=1000"
        case .salesforce: "/services/data/v60.0/query?q=SELECT+Id,Subject,ActivityDate,OwnerId+FROM+Task"
        case .sap: "/sap/opu/odata/sap/Z_PROCESS_SRV/Events"
        case .genericJSON: ""
        }
    }

    public var defaultMapping: ConnectorMapping {
        switch self {
        case .serviceNow:
            ConnectorMapping(caseField: "documentkey", activityField: "fieldname",
                             timestampField: "sys_created_on", resourceField: "user",
                             applicationField: "tablename", costField: "cost")
        case .salesforce:
            ConnectorMapping(caseField: "Id", activityField: "Subject",
                             timestampField: "ActivityDate", resourceField: "OwnerId",
                             applicationField: "Application", costField: "Cost")
        case .sap:
            ConnectorMapping(caseField: "CaseId", activityField: "Activity",
                             timestampField: "Timestamp", resourceField: "Role",
                             applicationField: "Application", costField: "Cost")
        case .genericJSON:
            ConnectorMapping(caseField: "case_id", activityField: "activity",
                             timestampField: "timestamp", resourceField: "resource",
                             applicationField: "application", costField: "cost")
        }
    }
}

public struct ConnectorMapping: Sendable, Hashable {
    public var caseField: String
    public var activityField: String
    public var timestampField: String
    public var resourceField: String
    public var applicationField: String
    public var costField: String

    public init(caseField: String, activityField: String, timestampField: String,
                resourceField: String, applicationField: String, costField: String) {
        self.caseField = caseField
        self.activityField = activityField
        self.timestampField = timestampField
        self.resourceField = resourceField
        self.applicationField = applicationField
        self.costField = costField
    }
}

public enum ConnectorError: Error, LocalizedError, Equatable {
    case emptyPayload
    case noRows(String)
    case invalidRow(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPayload: "The connector returned no data."
        case .noRows(let where_): "No rows found at \(where_)."
        case .invalidRow(let message): "A connector row could not be mapped: \(message)"
        }
    }
}

/// A connector is a mapping, not a hard-coded vendor client: the endpoint
/// returns JSON, the rows are located at the provider's envelope, and the
/// configured fields become the same canonical CSV the importer already
/// guards. This keeps privacy rules in one place.
public enum ConnectorParser {
    public static func csv(from data: Data, provider: ConnectorProvider,
                           mapping: ConnectorMapping) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let rows = try extractRows(object, provider: provider)
        guard !rows.isEmpty else { throw ConnectorError.noRows(provider.label) }
        var lines = ["case_id,activity,timestamp,resource,application,cost"]
        for row in rows {
            let caseID = text(row, mapping.caseField)
            let activity = text(row, mapping.activityField)
            let timestamp = timestamp(row, mapping.timestampField)
            guard !caseID.isEmpty, !activity.isEmpty, !timestamp.isEmpty else { continue }
            lines.append([
                caseID, activity, timestamp,
                text(row, mapping.resourceField),
                text(row, mapping.applicationField),
                text(row, mapping.costField),
            ].map(csv).joined(separator: ","))
        }
        guard lines.count > 1 else { throw ConnectorError.noRows(provider.label) }
        return lines.joined(separator: "\n")
    }

    private static func extractRows(_ object: Any, provider: ConnectorProvider) throws -> [[String: Any]] {
        if let array = object as? [[String: Any]] { return array }
        guard let root = object as? [String: Any] else { throw ConnectorError.emptyPayload }
        let paths: [String]
        switch provider {
        case .serviceNow: paths = ["result", "data.result"]
        case .salesforce: paths = ["records", "data.records"]
        case .sap: paths = ["d.results", "value", "data"]
        case .genericJSON: paths = ["data", "rows", "items", "value", "results"]
        }
        for path in paths {
            if let value = value(root, path), let rows = value as? [[String: Any]] { return rows }
        }
        throw ConnectorError.noRows(provider.label)
    }

    private static func text(_ row: [String: Any], _ key: String) -> String {
        guard !key.isEmpty, let value = value(row, key) else { return "" }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func timestamp(_ row: [String: Any], _ key: String) -> String {
        guard let value = value(row, key) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber, number.doubleValue > 1_000_000_000 {
            let date = Date(timeIntervalSince1970: number.doubleValue > 10_000_000_000 ? number.doubleValue / 1000 : number.doubleValue)
            return ISO8601DateFormatter().string(from: date)
        }
        return ""
    }

    private static func value(_ object: Any, _ path: String) -> Any? {
        var current: Any = object
        for part in path.split(separator: ".").map(String.init) {
            guard let dictionary = current as? [String: Any], let next = dictionary[part] else { return nil }
            current = next
        }
        return current
    }

    private static func csv(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

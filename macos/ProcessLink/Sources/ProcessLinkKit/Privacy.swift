import Foundation

/// The policy the guard enforces. Values are deliberately shown in the UI:
/// a threshold nobody can see is a threshold nobody can trust.
public struct PrivacyPolicy: Sendable, Hashable {
    /// Groups smaller than this are never displayed or exported, even as an
    /// aggregate. Ten is the default in this build; the real number is a
    /// works-council decision, not a developer choice.
    public var minimumGroupSize: Int
    public var retentionDays: Int
    public var approvedAIProviders: [String]
    public var approvedRegions: [String]
    public var purpose: Purpose
    public var dataOwner: String

    public init(minimumGroupSize: Int = 10, retentionDays: Int = 400,
                approvedAIProviders: [String] = ["Local (on device)", "Anthropic Claude · EU"],
                approvedRegions: [String] = ["EU"], purpose: Purpose = .processImprovement,
                dataOwner: String = "CI Manager (role)") {
        self.minimumGroupSize = minimumGroupSize
        self.retentionDays = retentionDays
        self.approvedAIProviders = approvedAIProviders
        self.approvedRegions = approvedRegions
        self.purpose = purpose
        self.dataOwner = dataOwner
    }

    public static let standard = PrivacyPolicy()
}

public struct PrivacyDecision: Sendable, Hashable {
    public enum Action: String, Sendable, Hashable {
        case allow
        case mask
        case suppress
        case block

        public var label: String {
            switch self {
            case .allow: "Allowed"
            case .mask: "Masked"
            case .suppress: "Suppressed"
            case .block: "Blocked"
            }
        }
    }

    public var allowed: Bool
    public var action: Action
    public var reason: String
    /// The rule that decided, so an audit entry can name it.
    public var rule: String

    public init(allowed: Bool, action: Action, reason: String, rule: String) {
        self.allowed = allowed
        self.action = action
        self.reason = reason
        self.rule = rule
    }
}

/// One place for every "may this move?" decision. The order of the checks is
/// the order of the policy: purpose, classification, group size, then
/// destination-specific conditions.
public enum PrivacyGuard {
    public static func evaluate(groupSize: Int,
                                classification: DataClass,
                                destination: Destination,
                                purpose: Purpose,
                                piiFindings: Int = 0,
                                policy: PrivacyPolicy = .standard) -> PrivacyDecision {
        if purpose == .individualPerformance {
            return PrivacyDecision(allowed: false, action: .block,
                reason: "ProcessLink is for process and system improvement only. Individual performance, monitoring or HR use is out of purpose.",
                rule: "privacy-guard/1 · purpose limitation")
        }
        if classification == .restricted {
            return PrivacyDecision(allowed: false, action: .block,
                reason: "This record is classified Restricted. Restricted content never enters ProcessLink, not even for a local report.",
                rule: "privacy-guard/1 · classification gate")
        }
        if groupSize < policy.minimumGroupSize {
            let allowed = destination == .localView && groupSize > 0
            return PrivacyDecision(allowed: allowed,
                action: allowed ? .suppress : .block,
                reason: allowed
                    ? "A group of \(groupSize) is below the \(policy.minimumGroupSize)-person threshold. The aggregate is hidden; only the fact that it exists is shown."
                    : "A group of \(groupSize) cannot be sent to \(destination.label). The minimum group size is \(policy.minimumGroupSize).",
                rule: "privacy-guard/1 · minimum group size")
        }
        if classification == .confidential,
           destination == .aiGateway || destination == .export || destination == .deck || destination == .knowledgeGraph {
            return PrivacyDecision(allowed: false, action: .block,
                reason: "Confidential data needs a named approval before it goes to \(destination.label). Ask the data owner to approve this specific transfer.",
                rule: "privacy-guard/1 · confidential transfer")
        }
        if destination == .aiGateway && piiFindings > 0 {
            return PrivacyDecision(allowed: false, action: .mask,
                reason: "\(piiFindings) possible personal-data item\(piiFindings == 1 ? "" : "s") found. Mask them, or remove them, before any AI call.",
                rule: "privacy-guard/1 · PII before API")
        }
        if destination == .aiGateway && !policy.approvedRegions.contains("EU") {
            return PrivacyDecision(allowed: false, action: .block,
                reason: "No approved processing region is configured. A cross-border AI call needs legal review.",
                rule: "privacy-guard/1 · region pin")
        }
        return PrivacyDecision(allowed: true, action: .allow,
            reason: "\(classification.label) data may go to \(destination.label) for \(purpose.label.lowercased()) under the current policy.",
            rule: "privacy-guard/1 · default allow")
    }

    /// Convenience for the common case: an aggregate view on this Mac.
    public static func canDisplay(groupSize: Int, classification: DataClass,
                                  policy: PrivacyPolicy = .standard) -> Bool {
        let decision = evaluate(groupSize: groupSize, classification: classification,
                                destination: .localView, purpose: policy.purpose, policy: policy)
        return decision.allowed && decision.action == .allow
    }
}

// MARK: - PII scan

/// A deliberately small, explainable detector. It runs before any AI call and
/// before an export; it is not a substitute for a real DLP product.
public struct PIIScan: Sendable, Hashable {
    public var counts: [String: Int]
    public var maskedText: String

    public var total: Int { counts.values.reduce(0, +) }

    public var summary: String {
        guard total > 0 else { return "No personal data patterns found." }
        let parts = counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        return "\(total) possible personal-data item\(total == 1 ? "" : "s"): " + parts.joined(separator: ", ")
    }
}

public enum PIIScanner {
    /// Patterns are ordered; each has one mask token.
    private static let patterns: [(name: String, token: String, regex: String)] = [
        ("email addresses", "email", #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        ("IBANs", "iban", #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{2,4}){4,8}\b"#),
        ("employee ids", "employee-id", #"\bEMP[- ]?\d{4,}\b"#),
        ("phone numbers", "phone", #"(?<!\d)\+?\d[\d\s().-]{8,}\d(?!\d)"#),
        ("long identifier numbers", "identifier", #"(?<!\d)\d{9,}(?!\d)"#),
    ]

    public static func scan(_ text: String) -> PIIScan {
        var masked = text
        var counts: [String: Int] = [:]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: (masked as NSString).length)
            let matches = regex.numberOfMatches(in: masked, range: range)
            guard matches > 0 else { continue }
            counts[pattern.name, default: 0] += matches
            masked = regex.stringByReplacingMatches(in: masked, range: range,
                                                   withTemplate: "[redacted:\(pattern.token)]")
        }
        return PIIScan(counts: counts, maskedText: masked)
    }
}

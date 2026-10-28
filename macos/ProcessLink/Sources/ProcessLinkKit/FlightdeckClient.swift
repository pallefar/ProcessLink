import Foundation

// MARK: - Configuration and errors

public struct FlightdeckConfig: Sendable, Hashable {
    public var baseURL: URL
    public var atlasURL: URL?

    public init(baseURL: URL, atlasURL: URL? = nil) throws {
        try Self.validate(baseURL)
        if let atlasURL { try Self.validate(atlasURL) }
        self.baseURL = baseURL
        self.atlasURL = atlasURL
    }

    /// HTTPS everywhere except loopback. A UAT URL with credentials embedded
    /// is refused rather than turned into a request header.
    public static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw FlightdeckError.invalidURL("Only http or https URLs are accepted.")
        }
        guard url.user == nil, url.password == nil else {
            throw FlightdeckError.invalidURL("Do not put credentials in the URL.")
        }
        guard url.query == nil, url.fragment == nil else {
            throw FlightdeckError.invalidURL("Use a base URL without a query or fragment.")
        }
        if scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            guard host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]" else {
                throw FlightdeckError.insecureURL("Plain HTTP is only allowed on this Mac (localhost or 127.0.0.1).")
            }
        }
    }
}

public enum FlightdeckError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case insecureURL(String)
    case notConfigured(String)
    case unreachable(String)
    case unauthorized
    case forbidden(String)
    case http(Int, String)
    case decoding(String)
    case quickLoginDisabled
    case atlasIdentityRequired

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let message): message
        case .insecureURL(let message): message
        case .notConfigured(let message): message
        case .unreachable(let message): "Flightdeck is unreachable: \(message)"
        case .unauthorized: "The Flightdeck session expired. Sign in again."
        case .forbidden(let message): "This account may not read that source: \(message)"
        case .http(let status, let message): "Flightdeck returned \(status). \(message)"
        case .decoding(let message): "Unexpected Flightdeck response: \(message)"
        case .quickLoginDisabled: "Quick login is disabled on this Flightdeck. Use a username and password, or enable UAT quick login."
        case .atlasIdentityRequired: "Atlas needs a local UAT identity e-mail (or a hosted sign-in token)."
        }
    }
}

// MARK: - Read models

public struct QuickLoginAccount: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var label: String
    public var username: String
}

public struct FlightdeckPrincipal: Sendable, Hashable, Codable {
    public var username: String
    public var displayName: String
    public var role: String
}

public struct WorkspaceSummary: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var enabled: Bool
}

public struct ProjectSummary: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var enabled: Bool
    public var isDefault: Bool
    public var owners: [String]
}

public struct VisionItem: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var status: String
}

public struct VisionSnapshot: Sendable {
    public var status: String
    public var enrolled: Bool
    public var approvedGoals: [String]
    public var requiredActions: [String]
    public var strategyTitle: String
    public var goals: [String]
    public var roadmap: [VisionItem]
    public var portfolio: [VisionItem]
    public var benefits: [VisionItem]
    public var decisionCount: Int
    public var ownerView: Bool
}

public struct KPIValue: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var unit: String
    public var state: String
    public var value: Double?
    public var sample: Int
    public var period: String
}

public struct AdvantageOpportunity: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kind: String
    public var rank: Int
    public var severity: String
    public var effort: String?
}

public struct AdvantageSnapshot: Sendable {
    public var asOf: String
    public var kpis: [KPIValue]
    public var opportunities: [AdvantageOpportunity]
}

public struct ContractFlowSummary: Sendable, Identifiable, Hashable {
    public var id: String
    public var updatedAt: String
    public var latestRunID: String

    public init(id: String, updatedAt: String, latestRunID: String) {
        self.id = id
        self.updatedAt = updatedAt
        self.latestRunID = latestRunID
    }
}

public struct FlightdeckMapSummary: Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var steps: Int
    public var approved: Bool
}

public struct AtlasProject: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var status: String
}

public struct AtlasSnapshot: Sendable {
    public var workspaceID: String
    public var workspaceName: String
    public var projects: [AtlasProject]
    public var localIdentity: String
}

// MARK: - Client

/// Read-only client for the Flightdeck OS HTTP API, the Vision projection and
/// Atlas. The session is a `flightdeck_session` cookie captured from a UAT
/// quick-login (or password login) and held by the caller; the client itself
/// never persists a secret.
public actor FlightdeckClient {
    public private(set) var baseURL: URL
    public private(set) var atlasURL: URL?
    public private(set) var principal: FlightdeckPrincipal?
    public private(set) var sessionCookie: String?

    private let session: URLSession

    public init(config: FlightdeckConfig, cookie: String? = nil) {
        self.baseURL = config.baseURL
        self.atlasURL = config.atlasURL
        self.sessionCookie = cookie
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func setCookie(_ cookie: String?) { sessionCookie = cookie }
    public func cookieHeader() -> String? { sessionCookie }

    // MARK: Auth

    public func quickLoginAccounts() async throws -> [QuickLoginAccount] {
        let data = try await get("/api/auth/quick-login")
        let object = try jsonObject(data)
        guard object["enabled"] as? Bool == true else { throw FlightdeckError.quickLoginDisabled }
        return (object["accounts"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let username = item["username"] as? String else { return nil }
            return QuickLoginAccount(id: id, label: item["label"] as? String ?? username, username: username)
        }
    }

    @discardableResult
    public func quickLogin(accountID: String) async throws -> FlightdeckPrincipal {
        let data = try await post("/api/auth/quick-login", body: ["id": accountID], authenticated: false)
        let object = try jsonObject(data)
        guard let principalObject = object["principal"] as? [String: Any],
              let principal = principal(from: principalObject) else {
            throw FlightdeckError.decoding("The login answer did not include a principal.")
        }
        self.principal = principal
        return principal
    }

    @discardableResult
    public func login(username: String, password: String) async throws -> FlightdeckPrincipal {
        let data = try await post("/api/auth/login", body: ["username": username, "password": password], authenticated: false)
        let object = try jsonObject(data)
        guard let principalObject = object["principal"] as? [String: Any],
              let principal = principal(from: principalObject) else {
            throw FlightdeckError.decoding("The login answer did not include a principal.")
        }
        self.principal = principal
        return principal
    }

    @discardableResult
    public func me() async throws -> FlightdeckPrincipal {
        let data = try await get("/api/auth/me")
        let object = try jsonObject(data)
        guard let principalObject = object["principal"] as? [String: Any],
              let principal = principal(from: principalObject) else {
            throw FlightdeckError.unauthorized
        }
        self.principal = principal
        return principal
    }

    // MARK: OS context

    public func workspaces() async throws -> [WorkspaceSummary] {
        let data = try await get("/api/workspaces")
        let object = try jsonObject(data)
        return (object["workspaces"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return WorkspaceSummary(id: id, label: item["label"] as? String ?? id,
                                    enabled: item["enabled"] as? Bool ?? true)
        }
    }

    public func projects(workspaceID: String) async throws -> [ProjectSummary] {
        let data = try await get("/api/projects", workspace: workspaceID)
        let object = try jsonObject(data)
        return (object["projects"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return ProjectSummary(
                id: id, label: item["label"] as? String ?? id,
                enabled: item["enabled"] as? Bool ?? true,
                isDefault: item["isDefault"] as? Bool ?? false,
                owners: item["owners"] as? [String] ?? [])
        }
    }

    // MARK: Vision

    public func vision(workspaceID: String, projectID: String) async throws -> VisionSnapshot {
        let data = try await get("/api/project-vision", workspace: workspaceID, project: projectID)
        let object = try jsonObject(data)
        let projection = (object["project"] as? [String: Any])
            ?? (object["workspace"] as? [String: Any]) ?? [:]
        var snapshot = VisionSnapshot(
            status: projection["status"] as? String ?? "unknown",
            enrolled: projection["enrolled"] as? Bool ?? false,
            approvedGoals: projection["approvedGoals"] as? [String] ?? [],
            requiredActions: projection["requiredActions"] as? [String] ?? [],
            strategyTitle: "", goals: [], roadmap: [], portfolio: [], benefits: [],
            decisionCount: 0, ownerView: false)

        // The owner view is optional: a normal member gets the projection and
        // a 403 here must not fail the whole connection.
        if let bootstrap = try? await get("/api/vision/bootstrap", workspace: workspaceID, project: projectID),
           let root = try? jsonObject(bootstrap) {
            snapshot.ownerView = true
            if let strategy = root["strategy"] as? [String: Any],
               let body = strategy["body"] as? [String: Any] {
                snapshot.strategyTitle = body["title"] as? String ?? ""
                snapshot.goals = body["goals"] as? [String] ?? []
            }
            snapshot.roadmap = items(root["roadmap"])
            snapshot.portfolio = items(root["portfolio"])
            snapshot.benefits = items(root["benefits"])
            snapshot.decisionCount = (root["decisions"] as? [Any])?.count ?? 0
        }
        return snapshot
    }

    // MARK: Advantage

    public func advantage(workspaceID: String, projectID: String) async throws -> AdvantageSnapshot {
        let kpiData = try await get("/api/apps/advantage/process-kpis", workspace: workspaceID, project: projectID)
        let kpiRoot = try jsonObject(kpiData)
        let kpis = (kpiRoot["kpis"] as? [[String: Any]] ?? []).compactMap { item -> KPIValue? in
            guard let id = item["id"] as? String else { return nil }
            let latest = item["latest"] as? [String: Any] ?? [:]
            let number = latest["value"] as? Double ?? (latest["value"] as? NSNumber)?.doubleValue
            return KPIValue(
                id: id, label: localized(item["label"]) ?? id,
                unit: item["unit"] as? String ?? "",
                state: item["state"] as? String ?? "unknown",
                value: number,
                sample: latest["n"] as? Int ?? 0,
                period: latest["period"] as? String ?? "")
        }

        let opportunityData = try await get("/api/apps/advantage/opportunities", workspace: workspaceID, project: projectID)
        let opportunityRoot = try jsonObject(opportunityData)
        let opportunities = (opportunityRoot["opportunities"] as? [[String: Any]] ?? []).compactMap { item -> AdvantageOpportunity? in
            guard let id = item["id"] as? String else { return nil }
            let rank = item["rank"] as? Int ?? (item["rank"] as? NSNumber)?.intValue ?? 0
            return AdvantageOpportunity(
                id: id,
                title: localized(item["title"]) ?? (item["title"] as? String ?? "Opportunity"),
                kind: item["kind"] as? String ?? "process",
                rank: rank,
                severity: item["severity"] as? String ?? "",
                effort: item["effort"] as? String)
        }
        return AdvantageSnapshot(asOf: kpiRoot["asOf"] as? String ?? "",
                                 kpis: kpis, opportunities: opportunities)
    }

    // MARK: Flightdeck Maps

    public func maps(workspaceID: String, projectID: String) async throws -> [FlightdeckMapSummary] {
        let data = try await get("/api/apps/maps/maps", workspace: workspaceID, project: projectID)
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] {
            rows = array
        } else if let root = object as? [String: Any], let array = root["maps"] as? [[String: Any]] {
            rows = array
        } else {
            throw FlightdeckError.decoding("Expected a map list.")
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return FlightdeckMapSummary(
                id: id,
                label: row["label"] as? String ?? id,
                steps: row["steps"] as? Int ?? (row["steps"] as? NSNumber)?.intValue ?? 0,
                approved: row["approved"] as? Bool ?? false)
        }
    }

    public func mapCI(id: String, workspaceID: String, projectID: String) async throws -> Data {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/api/apps/maps/maps/\(encoded)/ci", workspace: workspaceID, project: projectID)
    }

    public func mapCISettings(workspaceID: String, projectID: String) async throws -> Data {
        try await get("/api/apps/maps/settings/ci", workspace: workspaceID, project: projectID)
    }

    public func mapDocument(id: String, workspaceID: String, projectID: String) async throws -> Data {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/api/apps/maps/maps/\(encoded)", workspace: workspaceID, project: projectID)
    }

    // MARK: Contract-flow execution history

    /// Contract-flow tickets are real process cases: runs, checks, PDFs,
    /// works-council steps and signatures. This is the operational event log
    /// behind a contract map, not a synthetic map walk.
    public func contractFlowSummaries(workspaceID: String, projectID: String) async throws -> [ContractFlowSummary] {
        let data = try await get("/api/contract-flow/tickets", workspace: workspaceID, project: projectID)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["tickets"] as? [[String: Any]] else {
            throw FlightdeckError.decoding("Expected a contract-flow ticket list.")
        }
        return rows.compactMap { row in
            guard let id = row["ticket"] as? String else { return nil }
            let run = row["latestRun"] as? [String: Any]
            return ContractFlowSummary(
                id: id,
                updatedAt: row["updatedAt"] as? String ?? "",
                latestRunID: run?["runId"] as? String ?? "")
        }
    }

    public func contractFlowTicketIDs(workspaceID: String, projectID: String) async throws -> [String] {
        let data = try await get("/api/contract-flow/tickets", workspace: workspaceID, project: projectID)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["tickets"] as? [[String: Any]] else {
            throw FlightdeckError.decoding("Expected a contract-flow ticket list.")
        }
        return rows.compactMap { $0["ticket"] as? String }
    }

    public func contractFlowTicket(id: String, workspaceID: String, projectID: String) async throws -> Data {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/api/contract-flow/tickets/\(encoded)",
                             workspace: workspaceID, project: projectID)
    }

    // MARK: Atlas

    /// Atlas's UAT/local development identity is supplied by its hosting
    /// dispatcher as `oai-authenticated-user-*` headers. This method is for a
    /// loopback Atlas with that local identity; hosted Atlas needs its own
    /// sign-in token and is reported as unavailable rather than guessed.
    public func atlas(email: String, token: String? = nil) async throws -> AtlasSnapshot {
        guard let atlasURL else { throw FlightdeckError.notConfigured("Set an Atlas URL first.") }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty && (token?.isEmpty ?? true) && !isLoopback(atlasURL) {
            throw FlightdeckError.atlasIdentityRequired
        }
        var headers = ["Accept": "application/json"]
        // Atlas's local/UAT sign-in is a development cookie, not a password.
        // A hosted Atlas supplies a token instead; a bare loopback request
        // without either is refused explicitly.
        if let token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        } else if isLoopback(atlasURL) {
            headers["Cookie"] = "__sites_local_auth=1"
        } else {
            throw FlightdeckError.atlasIdentityRequired
        }
        let data = try await requestThis(url: atlasURL.appendingPathComponent("api/projects"),
                                         headers: headers, atlas: true)
        let root = try jsonObject(data)
        let access = root["access"] as? [String: Any] ?? [:]
        let projects = (root["projects"] as? [[String: Any]] ?? []).compactMap { item -> AtlasProject? in
            guard let id = item["id"] as? String else { return nil }
            return AtlasProject(id: id,
                                title: item["title"] as? String ?? item["name"] as? String ?? id,
                                status: item["status"] as? String ?? "active")
        }
        return AtlasSnapshot(workspaceID: "", workspaceName: "Atlas", projects: projects,
                             localIdentity: access["email"] as? String ?? trimmedEmail)
    }

    // MARK: HTTP

    private func get(_ path: String, workspace: String? = nil, project: String? = nil) async throws -> Data {
        var headers = ["Accept": "application/json"]
        if let cookie = sessionCookie { headers["Cookie"] = cookie }
        if let workspace { headers["X-Workspace-Id"] = workspace }
        if let project { headers["X-Project-Id"] = project }
        return try await requestThis(url: baseURL.appendingPathComponent(String(path.dropFirst())),
                                     headers: headers, atlas: false)
    }

    private func post(_ path: String, body: [String: any Sendable], authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let cookie = sessionCookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try check(response, data: data)
        captureCookie(response)
        return data
    }

    private func requestThis(url: URL, headers: [String: String], atlas: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (data, response) = try await session.data(for: request)
            try check(response, data: data, atlas: atlas)
            captureCookie(response)
            return data
        } catch let error as FlightdeckError {
            throw error
        } catch {
            throw FlightdeckError.unreachable(error.localizedDescription)
        }
    }

    private func check(_ response: URLResponse, data: Data, atlas: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FlightdeckError.decoding("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? ""
            if http.statusCode == 401 {
                throw atlas ? FlightdeckError.atlasIdentityRequired : FlightdeckError.unauthorized
            }
            if http.statusCode == 403 {
                throw FlightdeckError.forbidden(snippet.isEmpty ? "forbidden" : snippet)
            }
            throw FlightdeckError.http(http.statusCode, snippet)
        }
    }

    private func captureCookie(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "Set-Cookie") else { return }
        for part in raw.split(separator: ",") {
            let candidate = part.trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix("flightdeck_session=") else { continue }
            sessionCookie = String(candidate.split(separator: ";").first ?? candidate[...])
            return
        }
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlightdeckError.decoding("Expected a JSON object.")
        }
        return object
    }

    private func principal(from object: [String: Any]) -> FlightdeckPrincipal? {
        guard let username = object["username"] as? String else { return nil }
        return FlightdeckPrincipal(username: username,
                                   displayName: object["displayName"] as? String ?? username,
                                   role: object["role"] as? String ?? "")
    }

    private func isLoopback(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    private func localized(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let map = value as? [String: Any] {
            return map["en"] as? String ?? map["de"] as? String
        }
        return nil
    }

    private func items(_ value: Any?) -> [VisionItem] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let body = item["body"] as? [String: Any] ?? [:]
            let title = body["title"] as? String ?? item["title"] as? String ?? id
            return VisionItem(id: id, title: title, status: item["status"] as? String ?? "draft")
        }
    }
}

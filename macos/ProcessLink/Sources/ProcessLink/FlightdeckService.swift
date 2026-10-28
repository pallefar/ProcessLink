import Foundation
import Observation
import ProcessLinkKit

enum ConnectionState: String {
    case notConfigured
    case connected
    case partial
    case error
    case busy
}

struct SourceHealth: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var state: ConnectionState
    var detail: String
    var count: Int = 0
    var updatedAt: Date?
}

/// Holds the UAT connection and turns live OS/Vision/Atlas reads into graph
/// facts. It is deliberately read-only: no OS, Atlas or Vision write is made
/// by this service.
@MainActor
@Observable
final class FlightdeckService {
    static let defaults = UserDefaults.standard
    private static let cookieAccount = "session-cookie"
    private static let atlasTokenAccount = "atlas-token"

    var baseURLString: String {
        didSet { Self.defaults.set(baseURLString, forKey: "fd.baseURL"); client = nil }
    }
    var atlasURLString: String {
        didSet { Self.defaults.set(atlasURLString, forKey: "fd.atlasURL"); client = nil }
    }
    var atlasEmail: String {
        didSet { Self.defaults.set(atlasEmail, forKey: "fd.atlasEmail") }
    }
    var workspaceID: String {
        didSet { Self.defaults.set(workspaceID, forKey: "fd.workspace") }
    }
    var projectID: String {
        didSet { Self.defaults.set(projectID, forKey: "fd.project") }
    }

    private(set) var principal: FlightdeckPrincipal?
    private(set) var quickAccounts: [QuickLoginAccount] = []
    private(set) var workspaces: [WorkspaceSummary] = []
    private(set) var projects: [ProjectSummary] = []
    private(set) var health: [String: SourceHealth] = [:]
    private(set) var lastSync: Date?
    private(set) var lastVision: VisionSnapshot?
    private(set) var lastAdvantage: AdvantageSnapshot?
    private(set) var lastAtlas: AtlasSnapshot?
    private(set) var busy = false
    private(set) var quickLoginAvailable = true
    var selectedAccountID: String = ""
    var errorMessage: String?

    private var client: FlightdeckClient?
    private var atlasToken: String?

    init() {
        baseURLString = Self.defaults.string(forKey: "fd.baseURL") ?? "http://127.0.0.1:4173"
        atlasURLString = Self.defaults.string(forKey: "fd.atlasURL") ?? "http://localhost:5173"
        atlasEmail = Self.defaults.string(forKey: "fd.atlasEmail") ?? ""
        workspaceID = Self.defaults.string(forKey: "fd.workspace") ?? ""
        projectID = Self.defaults.string(forKey: "fd.project") ?? ""
        lastSync = Self.defaults.object(forKey: "fd.lastSync") as? Date
        atlasToken = KeychainStore.get(account: Self.atlasTokenAccount)
        health = [
            "os": SourceHealth(id: "os", title: "Flightdeck OS", symbol: "cloud", state: .notConfigured,
                               detail: "Sign in with a UAT account", count: 0, updatedAt: nil),
            "vision": SourceHealth(id: "vision", title: "Vision", symbol: "scope", state: .notConfigured,
                                   detail: "Read through the OS session", count: 0, updatedAt: nil),
            "atlas": SourceHealth(id: "atlas", title: "Atlas", symbol: "square.stack.3d.up", state: .notConfigured,
                                  detail: "Set the Atlas UAT URL and identity", count: 0, updatedAt: nil),
        ]
    }

    var isSignedIn: Bool { principal != nil }
    var accountLabel: String { principal?.displayName ?? "Not signed in" }
    var selectedWorkspace: WorkspaceSummary? { workspaces.first { $0.id == workspaceID } }
    var selectedProject: ProjectSummary? { projects.first { $0.id == projectID } }

    func setAtlasToken(_ token: String) {
        atlasToken = token.isEmpty ? nil : token
        if !token.isEmpty {
            KeychainStore.set(token, account: Self.atlasTokenAccount)
        } else {
            KeychainStore.delete(account: Self.atlasTokenAccount)
        }
    }

    // MARK: Session

    func discoverAccounts() async {
        errorMessage = nil
        do {
            let value = try makeClient()
            quickAccounts = try await value.quickLoginAccounts()
            quickLoginAvailable = true
            if selectedAccountID.isEmpty {
                selectedAccountID = quickAccounts.first(where: { $0.id == "uat-admin" })?.id
                    ?? quickAccounts.first?.id ?? ""
            }
            updateHealth("os", state: .partial,
                         detail: quickAccounts.isEmpty ? "Quick login is on but has no accounts" : "Choose a UAT account",
                         count: quickAccounts.count)
        } catch FlightdeckError.quickLoginDisabled {
            quickLoginAvailable = false
            updateHealth("os", state: .partial, detail: "Quick login is off; use username/password", count: 0)
        } catch FlightdeckError.http(let status, _) where status == 404 {
            quickLoginAvailable = false
            updateHealth("os", state: .partial, detail: "Quick login is not enabled; use username/password", count: 0)
        } catch {
            errorMessage = error.localizedDescription
            updateHealth("os", state: .error, detail: error.localizedDescription, count: 0)
        }
    }

    func signInWithUAT(accountID: String) async {
        guard !accountID.isEmpty else { return }
        await perform {
            let value = try self.makeClient()
            self.principal = try await value.quickLogin(accountID: accountID)
            if let cookie = await value.cookieHeader() {
                KeychainStore.set(cookie, account: Self.cookieAccount)
            }
            await self.refreshContext()
        }
    }

    func signIn(username: String, password: String) async {
        await perform {
            let value = try self.makeClient()
            self.principal = try await value.login(username: username, password: password)
            if let cookie = await value.cookieHeader() {
                KeychainStore.set(cookie, account: Self.cookieAccount)
            }
            await self.refreshContext()
        }
    }

    func restoreSession() async {
        guard principal == nil else { return }
        guard !baseURLString.isEmpty else { return }
        guard let cookie = KeychainStore.get(account: Self.cookieAccount) else { return }
        await perform {
            let value = try self.makeClient()
            await value.setCookie(cookie)
            self.principal = try await value.me()
            await self.refreshContext()
        }
    }

    func signOut() {
        KeychainStore.delete(account: Self.cookieAccount)
        client = nil
        principal = nil
        workspaces = []
        projects = []
        quickAccounts = []
        lastSync = nil
        lastVision = nil
        lastAdvantage = nil
        lastAtlas = nil
        health["os"] = SourceHealth(id: "os", title: "Flightdeck OS", symbol: "cloud",
                                    state: .notConfigured, detail: "Signed out", count: 0, updatedAt: nil)
        health["vision"] = SourceHealth(id: "vision", title: "Vision", symbol: "scope",
                                        state: .notConfigured, detail: "Read through the OS session", count: 0, updatedAt: nil)
        health["atlas"] = SourceHealth(id: "atlas", title: "Atlas", symbol: "square.stack.3d.up",
                                       state: .notConfigured, detail: "Set the Atlas UAT URL and identity", count: 0, updatedAt: nil)
    }

    // MARK: Context

    func refreshContext() async {
        guard principal != nil else { return }
        do {
            let value = try makeClient()
            workspaces = try await value.workspaces()
            if workspaceID.isEmpty || !workspaces.contains(where: { $0.id == workspaceID }) {
                workspaceID = workspaces.first(where: { $0.id == "te-ops" })?.id ?? workspaces.first?.id ?? ""
            }
            projects = try await value.projects(workspaceID: workspaceID)
            if projectID.isEmpty || !projects.contains(where: { $0.id == projectID }) {
                projectID = projects.first(where: { $0.id == "project-contract" })?.id
                    ?? projects.first(where: \.isDefault)?.id
                    ?? projects.first?.id ?? ""
            }
            updateHealth("os", state: .connected,
                         detail: "\(principal?.displayName ?? "Signed in") · \(principal?.role ?? "") · \(projects.count) projects",
                         count: projects.count)
            updateHealth("vision", state: .partial, detail: "Ready to sync", count: 0)
        } catch {
            errorMessage = error.localizedDescription
            updateHealth("os", state: .error, detail: error.localizedDescription, count: 0)
        }
    }

    func testAtlas() async {
        guard !atlasEmail.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = FlightdeckError.atlasIdentityRequired.localizedDescription
            updateHealth("atlas", state: .error, detail: "Set the Atlas UAT identity e-mail", count: 0)
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let value = try makeClient()
            let atlas = try await value.atlas(email: atlasEmail, token: atlasToken)
            lastAtlas = atlas
            updateHealth("atlas", state: .connected,
                         detail: "\(atlas.projects.count) projects · \(atlas.localIdentity)",
                         count: atlas.projects.count)
        } catch {
            errorMessage = error.localizedDescription
            updateHealth("atlas", state: .error, detail: error.localizedDescription, count: 0)
        }
    }

    // MARK: Sync

    func sync(into model: AppModel) async {
        guard principal != nil else {
            errorMessage = "Sign in to Flightdeck first."
            return
        }
        if workspaceID.isEmpty || projectID.isEmpty { await refreshContext() }
        await perform {
            let value = try self.makeClient()
            let vision = try? await value.vision(workspaceID: self.workspaceID, projectID: self.projectID)
            let advantage = try? await value.advantage(workspaceID: self.workspaceID, projectID: self.projectID)
            if let vision {
                self.lastVision = vision
                self.ingest(vision: vision, into: model)
                self.updateHealth("vision", state: .connected,
                                  detail: "\(vision.status) · \(vision.approvedGoals.count) goals · \(vision.requiredActions.count) actions",
                                  count: vision.approvedGoals.count + vision.requiredActions.count + vision.roadmap.count)
            } else {
                self.updateHealth("vision", state: .error, detail: "Vision projection could not be read", count: 0)
            }
            if let advantage {
                self.lastAdvantage = advantage
                self.ingest(advantage: advantage, into: model)
                self.updateHealth("os", state: .connected,
                                  detail: "\(self.principal?.displayName ?? "Signed in") · \(advantage.kpis.count) KPIs · \(advantage.opportunities.count) opportunities",
                                  count: advantage.kpis.count + advantage.opportunities.count)
            }

            if !self.atlasEmail.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    let atlas = try await value.atlas(email: self.atlasEmail, token: self.atlasToken)
                    self.lastAtlas = atlas
                    self.ingest(atlas: atlas, into: model)
                    self.updateHealth("atlas", state: .connected,
                                      detail: "\(atlas.projects.count) Atlas projects · \(atlas.localIdentity)",
                                      count: atlas.projects.count)
                } catch {
                    self.updateHealth("atlas", state: .error, detail: error.localizedDescription, count: 0)
                }
            }
            self.workspaceNodes(into: model)
            _ = await self.importFlightdeckMaps(into: model)
            self.lastSync = .now
            Self.defaults.set(self.lastSync, forKey: "fd.lastSync")
            model.audit(action: "connection.sync", subject: "Flightdeck UAT",
                        detail: "OS/\(self.workspaceID)/\(self.projectID), Vision and Atlas read-only sync.")
            try? model.context.save()
            model.showToast("Flightdeck synced", detail: "OS, Vision and Atlas context refreshed", symbol: "arrow.triangle.2.circlepath")
        }
    }

    /// Imports every map in every enabled project from Flightdeck Maps. A
    /// local file with the same id is kept (it may carry approved edits);
    /// the remote copy is still registered in the graph.
    @discardableResult
    func importFlightdeckMaps(into model: AppModel) async -> (imported: Int, failed: Int) {
        guard principal != nil else { return (0, 0) }
        if projects.isEmpty { await refreshContext() }
        guard !workspaceID.isEmpty else { return (0, 0) }
        var imported = 0
        var failed = 0
        var existing = Set(MapsBridge.loadAll().map(\.id))
        var seen = Set<String>()
        do {
            let value = try makeClient()
            for project in projects where project.enabled {
                let summaries: [FlightdeckMapSummary]
                do {
                    summaries = try await value.maps(workspaceID: workspaceID, projectID: project.id)
                } catch {
                    failed += 1
                    continue
                }
                for summary in summaries where !seen.contains(summary.id) {
                    seen.insert(summary.id)
                    do {
                        let data = try await value.mapDocument(id: summary.id,
                                                              workspaceID: workspaceID,
                                                              projectID: project.id)
                        let document = try MapsBridge.importRemote(data, existing: existing.contains(summary.id))
                        existing.insert(summary.id)
                        model.registerMap(document, process: nil)
                        imported += 1
                    } catch {
                        failed += 1
                    }
                }
            }
        } catch {
            return (imported, failed + 1)
        }
        if imported > 0 {
            lastSync = .now
            try? model.context.save()
        }
        return (imported, failed)
    }

    // MARK: Graph write-through

    private func workspaceNodes(into model: AppModel) {
        guard let workspace = selectedWorkspace, let project = selectedProject else { return }
        let workspaceID = "kg-os-workspace-\(workspace.id)"
        let workspaceNode = model.ensureKGNode(
            id: workspaceID, kind: .businessUnit, name: workspace.label, confidence: 0.98,
            source: "Flightdeck OS", sourceID: "workspace:\(workspace.id)")
        workspaceNode.note = "Live UAT workspace"
        workspaceNode.updatedAt = .now

        let projectKG = "kg-os-project-\(workspace.id)-\(project.id)"
        let projectNode = model.ensureKGNode(
            id: projectKG, kind: .valueStream, name: project.label, confidence: 0.96,
            source: "Flightdeck OS", sourceID: "project:\(project.id)")
        projectNode.note = "Flightdeck project \(project.id), \(project.owners.count) owners"
        projectNode.updatedAt = .now
        model.ensureKGEdge(from: projectKG, .ownedBy, to: workspaceID, confidence: 0.96)
    }

    private func ingest(vision: VisionSnapshot, into model: AppModel) {
        guard let project = selectedProject else { return }
        let projectKG = "kg-os-project-\(workspaceID)-\(project.id)"
        for goal in vision.goals + vision.approvedGoals {
            let id = "kg-vision-goal-\(slug(goal))"
            let node = model.ensureKGNode(
                id: id, kind: .hoshinObjective, name: goal, confidence: 0.95,
                source: "Flightdeck Vision", sourceID: "goal:\(slug(goal))")
            node.note = "Vision strategy: \(vision.strategyTitle.isEmpty ? "untitled" : vision.strategyTitle)"
            node.updatedAt = .now
            model.ensureKGEdge(from: projectKG, .alignedToObjective, to: id, confidence: 0.9)
        }
        for action in vision.requiredActions {
            let id = "kg-vision-action-\(slug(action))"
            let node = model.ensureKGNode(
                id: id, kind: .action, name: action, confidence: 0.92,
                source: "Flightdeck Vision", sourceID: "required-action:\(slug(action))")
            node.note = "Required action from the Vision assessment"
            node.updatedAt = .now
            model.ensureKGEdge(from: projectKG, .addressedBy, to: id, confidence: 0.85)
        }
        for milestone in vision.roadmap {
            let id = "kg-vision-roadmap-\(milestone.id)"
            let node = model.ensureKGNode(
                id: id, kind: .hoshinObjective, name: milestone.title, confidence: 0.88,
                source: "Flightdeck Vision", sourceID: "roadmap:\(milestone.id)")
            node.note = "Vision roadmap · \(milestone.status)"
            node.updatedAt = .now
            model.ensureKGEdge(from: projectKG, .alignedToObjective, to: id, confidence: 0.85)
        }
        for benefit in vision.benefits {
            let id = "kg-vision-benefit-\(benefit.id)"
            let node = model.ensureKGNode(
                id: id, kind: .savingsRecord, name: benefit.title, confidence: 0.9,
                source: "Flightdeck Vision", sourceID: "benefit:\(benefit.id)")
            node.note = "Vision benefit · \(benefit.status)"
            node.updatedAt = .now
        }
    }

    private func ingest(advantage: AdvantageSnapshot, into model: AppModel) {
        guard let project = selectedProject else { return }
        let projectKG = "kg-os-project-\(workspaceID)-\(project.id)"
        for kpi in advantage.kpis {
            let id = "kg-os-kpi-\(project.id)-\(kpi.id)"
            let node = model.ensureKGNode(
                id: id, kind: .metric, name: kpi.label, confidence: 0.9,
                source: "Flightdeck Advantage", sourceID: "kpi:\(kpi.id)")
            node.note = "\(kpi.state) · \(kpi.period) · n=\(kpi.sample)"
            node.updatedAt = .now
            model.ensureKGEdge(from: projectKG, .measuredBy, to: id, confidence: 0.9)
        }
        for opportunity in advantage.opportunities {
            let id = "kg-os-opp-\(project.id)-\(opportunity.id)"
            let node = model.ensureKGNode(
                id: id, kind: .opportunity, name: opportunity.title, confidence: 0.86,
                source: "Flightdeck Advantage", sourceID: "opportunity:\(opportunity.id)")
            node.note = "\(opportunity.kind) · rank \(opportunity.rank) · \(opportunity.severity)"
            node.updatedAt = .now
            model.ensureKGEdge(from: projectKG, .hasOpportunity, to: id, confidence: 0.86)
        }
    }

    private func ingest(atlas: AtlasSnapshot, into model: AppModel) {
        let workspaceKG = "kg-atlas-workspace"
        let workspace = model.ensureKGNode(
            id: workspaceKG, kind: .businessUnit, name: "Atlas workspace",
            confidence: 0.85, source: "Flightdeck Atlas", sourceID: "atlas:workspace")
        workspace.note = "Atlas UAT connection; projects are read-only. The signed-in e-mail is not stored in the graph."
        workspace.updatedAt = .now
        for project in atlas.projects.prefix(60) {
            let id = "kg-atlas-project-\(project.id)"
            let node = model.ensureKGNode(
                id: id, kind: .initiative, name: project.title, confidence: 0.82,
                source: "Flightdeck Atlas", sourceID: "atlas-project:\(project.id)")
            node.note = "Atlas project · \(project.status)"
            node.updatedAt = .now
            model.ensureKGEdge(from: id, .ownedBy, to: workspaceKG, confidence: 0.82)
        }
    }

    // MARK: Helpers

    private func makeClient() throws -> FlightdeckClient {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              !baseURLString.isEmpty else {
            throw FlightdeckError.invalidURL("Enter the Flightdeck UAT URL.")
        }
        let atlas = URL(string: atlasURLString.trimmingCharacters(in: .whitespaces)).flatMap { url in
            atlasURLString.isEmpty ? nil : url
        }
        let config = try FlightdeckConfig(baseURL: url, atlasURL: atlas)
        if let client { return client }
        let value = FlightdeckClient(config: config,
                                     cookie: KeychainStore.get(account: Self.cookieAccount))
        client = value
        return value
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
            updateHealth("os", state: .error, detail: error.localizedDescription, count: 0)
        }
    }

    private func updateHealth(_ id: String, state: ConnectionState, detail: String, count: Int) {
        guard var item = health[id] else { return }
        item.state = state
        item.detail = detail
        item.count = count
        item.updatedAt = .now
        health[id] = item
    }

    private func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(allowed).split(separator: "-").joined(separator: "-").prefix(80).description
    }
}

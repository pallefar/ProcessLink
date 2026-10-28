import Foundation
import Observation
import ProcessLinkKit
import SwiftData

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
        // A self-test must not block on a Keychain prompt from an ad-hoc
        // build. Normal launches still restore the Atlas token.
        if !SelfTest.requested {
            atlasToken = KeychainStore.get(account: Self.atlasTokenAccount)
        }
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

    /// Pulls the Maps CI goals, derived benefits and manual KPIs into Strategy.
    /// The map remains the owner of the definition; ProcessLink keeps the link
    /// and the current value, not a second independent copy of the process.
    @discardableResult
    func syncMapKPIs(into model: AppModel) async -> Int {
        guard principal != nil else { return 0 }
        if projects.isEmpty { await refreshContext() }
        guard !workspaceID.isEmpty else { return 0 }
        let maps = MapsBridge.loadAll().filter { !$0.id.hasPrefix("map-") }
        guard !maps.isEmpty else {
            model.showToast("No Flightdeck maps", detail: "Import a map before syncing its KPIs.",
                            symbol: "map", warning: true)
            return 0
        }
        var imported = 0
        do {
            let value = try makeClient()
            let context = model.context
            let settingsData = try await value.mapCISettings(workspaceID: workspaceID, projectID: projectID)
            let settings = (try? JSONSerialization.jsonObject(with: settingsData)) as? [String: Any] ?? [:]
            let goals = settings["goals"] as? [[String: Any]] ?? []
            var bets = (try? context.fetch(FetchDescriptor<StrategicBetRecord>())) ?? []
            var kpis = (try? context.fetch(FetchDescriptor<KPIRecord>())) ?? []
            let strategy = ((try? context.fetch(FetchDescriptor<StrategyRecord>())) ?? []).first
            let existingInitiatives = (try? context.fetch(FetchDescriptor<InitiativeRecord>())) ?? []

            for map in maps {
                let ciData = try await value.mapCI(id: map.id, workspaceID: workspaceID, projectID: projectID)
                let ci = (try? JSONSerialization.jsonObject(with: ciData)) as? [String: Any] ?? [:]
                let benefits = ci["benefits"] as? [[String: Any]] ?? []
                let manual = ((map.json["meta"] as? [String: Any])?["ci"] as? [String: Any])?["kpis"] as? [[String: Any]] ?? []
                let mapGoals = Dictionary(uniqueKeysWithValues: goals.compactMap { goal -> (String, String)? in
                    guard let id = goal["id"] as? String else { return nil }
                    return (id, goal["label"] as? String ?? id)
                })

                func betID(_ goalID: String, _ goalLabel: String) -> String {
                    let id = "bet-map-\(goalID.isEmpty ? "default" : goalID)"
                    if let existing = bets.first(where: { $0.id == id }) { return existing.id }
                    let bet = StrategicBetRecord(
                        id: id, title: goalLabel,
                        detail: "Imported from Flightdeck Maps continuous-improvement goals.",
                        owner: "Process Owner", horizon: strategy?.horizon ?? "Current",
                        status: "active", primaryKPIID: "", valueIDs: [StrategyDefaults.valRight, StrategyDefaults.valSimplify],
                        order: bets.count)
                    context.insert(bet)
                    bets.append(bet)
                    return id
                }

                func upsertKPI(id: String, name: String, definition: String, unit: String,
                               baseline: Double, current: Double, target: Double,
                               direction: String, source: String, bet: String, cadence: String) {
                    let kpi: KPIRecord
                    if let existing = kpis.first(where: { $0.id == id }) {
                        kpi = existing
                    } else {
                        kpi = KPIRecord(id: id, name: name, definition: definition, unit: unit,
                                        baseline: baseline, current: current, target: target,
                                        direction: direction, cadence: cadence, source: source,
                                        strategicBetID: bet)
                        context.insert(kpi)
                        kpis.append(kpi)
                    }
                    kpi.name = name
                    kpi.definition = definition
                    kpi.unit = unit
                    kpi.baseline = baseline
                    kpi.current = current
                    kpi.target = target
                    kpi.directionRaw = direction
                    kpi.cadence = cadence
                    kpi.source = source
                    kpi.strategicBetID = bet
                    kpi.updatedAt = .now
                    if let index = bets.firstIndex(where: { $0.id == bet }), bets[index].primaryKPIID.isEmpty {
                        bets[index].primaryKPIID = id
                    }
                    imported += 1
                }

                for benefit in benefits {
                    guard let key = benefit["key"] as? String,
                          let label = benefit["label"] as? String else { continue }
                    let goalID = benefit["goalId"] as? String ?? "default"
                    let goalLabel = benefit["goalLabel"] as? String ?? mapGoals[goalID] ?? "Process improvement"
                    let bet = betID(goalID, goalLabel)
                    let rawUnit = benefit["unit"] as? String ?? ""
                    let unit = rawUnit == "ms" ? "min" : rawUnit
                    let scale = rawUnit == "ms" ? 1.0 / 60_000.0 : 1.0
                    let baseline = (benefit["baseline"] as? Double).map { $0 * scale } ?? 0
                    let current = (benefit["current"] as? Double).map { $0 * scale } ?? 0
                    upsertKPI(id: "kpi-map-\(map.id)-\(key)",
                              name: "\(label) · \(map.label)",
                              definition: benefit["summary"] as? String ?? "Derived by Flightdeck Maps.",
                              unit: unit, baseline: baseline, current: current,
                              target: current, direction: benefit["betterWhen"] as? String ?? "lower",
                              source: "Flightdeck Maps", bet: bet, cadence: "On demand")
                }

                for item in manual {
                    guard let key = item["id"] as? String,
                          let label = item["label"] as? String else { continue }
                    let goalID = item["goalId"] as? String ?? "default"
                    let goalLabel = mapGoals[goalID] ?? "Process improvement"
                    let bet = betID(goalID, goalLabel)
                    let baseline = (item["baseline"] as? Double) ?? (item["current"] as? Double) ?? 0
                    let current = (item["current"] as? Double) ?? baseline
                    let target = (item["target"] as? Double) ?? current
                    upsertKPI(id: "kpi-map-\(map.id)-\(key)",
                              name: "\(label) · \(map.label)",
                              definition: "Manual KPI owned by \(map.label).",
                              unit: item["unit"] as? String ?? "", baseline: baseline,
                              current: current, target: target,
                              direction: item["betterWhen"] as? String ?? "lower",
                              source: "Flightdeck Maps", bet: bet, cadence: "Manual")
                }

                // Auto-link an initiative to the map's KPI only when the link
                // is empty; a human choice always wins.
                for initiative in existingInitiatives where initiative.processID == map.processID {
                    if initiative.kpiID.isEmpty, let bet = bets.first(where: { $0.id == initiative.strategicBetID }) {
                        initiative.kpiID = bet.primaryKPIID
                    }
                }
            }
            try? context.save()
            model.showToast("Maps KPIs synced",
                            detail: "\(imported) KPI readings · \(maps.count) maps",
                            symbol: "chart.line.uptrend.xyaxis")
            return imported
        } catch {
            model.showToast("Maps KPI sync failed", detail: error.localizedDescription,
                            symbol: "exclamationmark.triangle", warning: true)
            return 0
        }
    }

    /// Pulls the real contract-flow execution history behind a Flightdeck map:
    /// one case per ticket, with run, four-eye check, PDF, works council and
    /// signature events. It is the operational event log, not a map walk.
    @discardableResult
    func importContractFlow(into model: AppModel, map: MapsBridge.Document) async -> DatasetRecord? {
        guard principal != nil else { return nil }
        if projects.isEmpty { await refreshContext() }
        guard !workspaceID.isEmpty else { return nil }
        do {
            let value = try makeClient()
            let summaries = try await value.contractFlowSummaries(workspaceID: workspaceID, projectID: projectID)
            let ids = summaries.map(\.id)
            let cursor = summaries.map { "\($0.updatedAt)|\($0.latestRunID)" }.max() ?? ""
            if let existing = model.dataset(forMap: map.id), !cursor.isEmpty,
               existing.sourceCursor == cursor {
                model.selectedDatasetID = existing.id
                model.page = .mining
                model.showToast("Map log is current", detail: "\(existing.caseCount) cases · no new ticket activity",
                                symbol: "checkmark.circle")
                return existing
            }
            guard !ids.isEmpty else {
                model.showToast("No execution history", detail: "This project has no contract-flow tickets yet.",
                                symbol: "tray", warning: true)
                return nil
            }
            let header = "case_id,activity,timestamp,resource,application,outcome,project,stage,source,checks"
            var lines = [header]
            var cases = 0
            for id in ids.prefix(500) {
                guard let data = try? await value.contractFlowTicket(id: id, workspaceID: workspaceID,
                                                                     projectID: projectID),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let ticket = root["ticket"] as? String ?? id
                let project = root["project"] as? String ?? ""
                let stage = root["stage"] as? String ?? ""
                let runs = root["runs"] as? [[String: Any]] ?? []
                let latest = runs.first
                let history = root["history"] as? [[String: Any]] ?? []
                let updatedAt = root["updatedAt"] as? String ?? ""
                let stepRows = root["steps"] as? [[String: Any]] ?? []
                let run = latest
                let outcome = run?["outcome"] as? String ?? ""
                let checks = run?["checks"] as? [String: Any]
                let checkText = checks.map { "\($0["passed"] as? Int ?? 0) passed" } ?? ""
                let runSource = run?["source"] as? String ?? "flightdeck"
                let startAt = run?["startedAt"] as? String ?? ""
                let finishAt = run?["finishedAt"] as? String ?? ""
                let checkAt = (run?["check"] as? [String: Any])?["at"] as? String
                let pdfAt = (run?["pdf"] as? [String: Any])?["at"] as? String
                let signatureAt = (run?["signature"] as? [String: Any])?["at"] as? String
                var historyAt: [String: String] = [:]
                for entry in history {
                    if let key = entry["stage"] as? String, let at = entry["at"] as? String {
                        historyAt[key] = at
                    }
                }
                let stepLabels: [String: (String, String)] = [
                    "intake": ("Open ticket", "HR Services"),
                    "recognition": ("Check documents", "Engine"),
                    "wc": ("Works council", "Works council"),
                    "draft": ("Prepare contract", "Preparer"),
                    "signature": ("Sign contract", "Signatory"),
                    "done": ("Close ticket", "HR Services"),
                ]
                let stepTime: [String: String] = [
                    "intake": startAt,
                    "recognition": finishAt,
                    "wc": historyAt["wc-sent"] ?? historyAt["wc-approved"] ?? historyAt["wc-rejected"] ?? updatedAt,
                    "draft": checkAt ?? pdfAt ?? finishAt,
                    "signature": signatureAt ?? updatedAt,
                    "done": historyAt["done"] ?? updatedAt,
                ]
                var stepEvents: [(String, String, String, String, String)] = []
                for step in stepRows {
                    guard let id = step["id"] as? String,
                          let state = step["state"] as? String, state != "todo",
                          let label = stepLabels[id],
                          let at = stepTime[id], !at.isEmpty else { continue }
                    let source = (state == "done" && at != updatedAt) ? runSource : "step-state"
                    stepEvents.append((label.0, at, label.1, outcome, source))
                }
                // A ticket with a run but no step state still yields one honest
                // event; never invent a step that the OS did not report.
                if stepEvents.isEmpty, let at = startAt.isEmpty ? nil : startAt {
                    stepEvents.append(("Open ticket", at, "HR Services", outcome, runSource))
                }
                for event in stepEvents {
                    lines.append(csvLine([ticket, event.0, event.1, event.2, "Flightdeck Maps",
                                          event.3, project, stage, event.4, checkText]))
                }
                let exceptions = ["refused": ("Refused", "Engine"), "checks-failed": ("Checks failed", "Engine")]
                for (key, value) in exceptions {
                    if let at = historyAt[key] {
                        lines.append(csvLine([ticket, value.0, at, value.1, "Flightdeck Maps",
                                              stage, project, key, "history-exception", ""]))
                    }
                }
                cases += 1
            }
            guard lines.count > 1 else {
                model.showToast("No execution events", detail: "The tickets have no run or history timestamps.",
                                symbol: "tray", warning: true)
                return nil
            }
            let csv = lines.joined(separator: "\n")
            let result = try EventLogImporter.importCSV(csv)
            let dataset: DatasetRecord
            if let existing = model.dataset(forMap: map.id) {
                model.replaceEvents(in: existing, result: result, cursor: cursor)
                dataset = existing
            } else {
                dataset = try model.importCSV(
                    text: csv, name: "Contract flow · \(map.label)",
                    filename: "flightdeck-contract-flow.csv", site: "",
                    mapID: map.id,
                    mapMappingJSON: mappingJSON(for: map))
            }
            let existingProcess = ((try? model.context.fetch(FetchDescriptor<ProcessRecord>())) ?? [])
                .first { $0.id == dataset.processID }
            let process: ProcessRecord
            if let existingProcess {
                process = existingProcess
            } else if let created = model.createProcess(from: dataset) {
                process = created
            } else {
                return dataset
            }
            dataset.processID = process.id
            dataset.mapID = map.id
            dataset.sourceRaw = "flightdeck-contract-flow"
            dataset.sourceCursor = cursor
            dataset.notes = "Live contract-flow execution history from Flightdeck Maps: \(cases) tickets."
            let processSteps = ((try? model.context.fetch(FetchDescriptor<StepRecord>())) ?? [])
                .filter { $0.processID == process.id }
                .sorted { $0.order < $1.order }
            let updated = try MapsBridge.attachProcess(map, process: process, steps: processSteps)
            model.registerMap(updated, process: process)
            model.selectedDatasetID = dataset.id
            model.selectedProcessID = process.id
            model.page = .mining
            try? model.context.save()
            model.showToast("Contract flow mined",
                            detail: "\(dataset.caseCount) cases · \(dataset.eventCount) events · \(ids.count) tickets",
                            symbol: "point.topleft.down.to.point.bottomright.curvepath")
            return dataset
        } catch {
            model.showToast("Contract-flow import failed", detail: error.localizedDescription,
                            symbol: "exclamationmark.triangle", warning: true)
            return nil
        }
    }

    private func mappingJSON(for map: MapsBridge.Document) -> String {
        let steps = map.nodes.compactMap { node -> MapStepRef? in
            guard node.type != "start" && node.type != "end" else { return nil }
            let stepID = node.link?.stepID ?? (node.stepID.isEmpty ? node.id : node.stepID)
            return MapStepRef(id: stepID, label: node.label,
                              role: node.role, system: node.system)
        }
        let aliases: [String: String] = [
            "Open ticket": "intake_received",
            "Check documents": "check_documents",
            "Prepare contract": "prepare_documents",
            "Works council": "send_to_wc",
            "Sign contract": "hrss_signature",
            "Close ticket": "complete",
            "Refused": "request_info",
            "Checks failed": "qc_four_eye",
        ]
        var mapping: [String: String] = [:]
        let stepIDs = Dictionary(uniqueKeysWithValues: map.nodes.map { node in
            (node.id, node.link?.stepID ?? (node.stepID.isEmpty ? node.id : node.stepID))
        })
        let reference = MapReference(name: map.label, steps: steps,
                                     edges: map.edges.compactMap { edge in
                                         guard let from = stepIDs[edge.source], let to = stepIDs[edge.target] else { return nil }
                                         return MapEdgeRef(from: from, to: to)
                                     })
        for (activity, step) in aliases where steps.contains(where: { $0.id == step }) {
            mapping[activity] = step
        }
        for (activity, step) in MapMining.autoMap(activities: Array(Set(mapping.keys)).sorted(), reference: reference) {
            if mapping[activity] == nil { mapping[activity] = step }
        }
        let data = (try? JSONSerialization.data(withJSONObject: mapping, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func csvLine(_ values: [String]) -> String {
        values.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
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

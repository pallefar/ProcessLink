import AppKit
import Foundation

/// The Flightdeck Maps bridge.
///
/// Maps are real `signavio-map/1` documents, not a ProcessLink-only drawing.
/// This build keeps them in a folder that Flightdeck Maps can point at
/// (`APP_MAPS_DIR`, defaulting to Application Support); the same documents
/// travel through `GET/PUT /api/apps/maps/maps/:id` in the host.
///
/// A map may carry two additive ProcessLink fields:
///   node.data.processLink  — the binding from a shape to a KG step
///   meta.processLink       — the map-level process/initiative context
/// Both are optional, so every existing map is valid and unchanged.
@MainActor
enum MapsBridge {
    struct Link {
        var processID: String
        var stepID: String
        var kgNodeID: String
        var kgProcessID: String
        var syncedAt: String
    }

    struct Node: Identifiable {
        var id: String
        var type: String
        var label: String
        var stepID: String
        var x: Double
        var y: Double
        var role: String
        var system: String
        var estimateMin: Double?
        var link: Link?
    }

    struct Edge: Identifiable {
        var id: String
        var source: String
        var target: String
        var label: String
    }

    struct Document: Identifiable {
        var id: String
        var label: String
        var fileURL: URL
        var json: [String: Any]
        var nodes: [Node]
        var edges: [Edge]
        var processID: String
        var kgProcessID: String
        var generatedAt: Date?
        var updatedAt: Date
        var approved: Bool
        var boundNodes: Int { nodes.filter { $0.link != nil }.count }

        var processLinkGeneratedAt: Date? {
            guard let meta = json["meta"] as? [String: Any],
                  let link = meta["processLink"] as? [String: Any],
                  let value = link["generatedAt"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: value)
        }
    }

    static var folderURL: URL {
        if let path = ProcessInfo.processInfo.environment["APP_MAPS_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ProcessLink/maps", isDirectory: true)
    }

    static func loadAll() -> [Document] {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Document? in
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let json = object as? [String: Any],
                      json["schema"] as? String == "signavio-map/1" else { return nil }
                return document(from: json, at: url)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private static func document(from json: [String: Any], at url: URL) -> Document {
        let nodes = (json["nodes"] as? [[String: Any]] ?? []).compactMap { raw -> Node? in
            guard let id = raw["id"] as? String else { return nil }
            let data = raw["data"] as? [String: Any] ?? [:]
            let position = raw["position"] as? [String: Any] ?? [:]
            let timing = data["timing"] as? [String: Any] ?? [:]
            let linkRaw = data["processLink"] as? [String: Any]
            let link = linkRaw.flatMap { value -> Link? in
                guard let processID = value["processId"] as? String,
                      let stepID = value["stepId"] as? String,
                      let kgNodeID = value["kgNodeId"] as? String,
                      let kgProcessID = value["kgProcessId"] as? String else { return nil }
                return Link(processID: processID, stepID: stepID, kgNodeID: kgNodeID,
                            kgProcessID: kgProcessID, syncedAt: value["syncedAt"] as? String ?? "")
            }
            return Node(id: id, type: raw["type"] as? String ?? "step",
                        label: raw["label"] as? String ?? "",
                        stepID: data["stepId"] as? String ?? "",
                        x: position["x"] as? Double ?? 0, y: position["y"] as? Double ?? 0,
                        role: data["role"] as? String ?? "",
                        system: data["systemUsed"] as? String ?? "",
                        estimateMin: timing["estimateMin"] as? Double,
                        link: link)
        }
        let edges = (json["edges"] as? [[String: Any]] ?? []).compactMap { raw -> Edge? in
            guard let id = raw["id"] as? String,
                  let source = raw["source"] as? String,
                  let target = raw["target"] as? String else { return nil }
            return Edge(id: id, source: source, target: target, label: raw["label"] as? String ?? "")
        }
        let meta = json["meta"] as? [String: Any] ?? [:]
        let link = meta["processLink"] as? [String: Any] ?? [:]
        let generated = (link["generatedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return Document(id: json["id"] as? String ?? url.deletingPathExtension().lastPathComponent,
                        label: json["label"] as? String ?? url.lastPathComponent,
                        fileURL: url, json: json, nodes: nodes, edges: edges,
                        processID: link["processId"] as? String ?? meta["sourceProcessId"] as? String ?? "",
                        kgProcessID: link["kgProcessId"] as? String ?? "",
                        generatedAt: generated, updatedAt: modified,
                        approved: meta["approved"] as? Bool ?? false)
    }

    /// Links a local map to the process mined from its execution log. Labels
    /// that match a mined step get the normal ProcessLink binding; unmatched
    /// map steps stay visible as unexercised work.
    static func attachProcess(_ document: Document, process: ProcessRecord,
                              steps: [StepRecord]) throws -> Document {
        var json = document.json
        var meta = json["meta"] as? [String: Any] ?? [:]
        meta["sourceProcessId"] = process.id
        meta["processLink"] = [
            "processId": process.id,
            "kgProcessId": process.kgID,
            "generatedAt": ISO8601DateFormatter().string(from: .now),
            "source": "ProcessLink Mining",
        ]
        json["meta"] = meta
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        for index in nodes.indices {
            var node = nodes[index]
            guard let label = node["label"] as? String else { continue }
            let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let step = steps.first(where: {
                $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }) else { continue }
            var data = node["data"] as? [String: Any] ?? [:]
            data["processLink"] = [
                "processId": process.id,
                "stepId": step.id,
                "kgNodeId": step.kgID,
                "kgProcessId": process.kgID,
                "syncedAt": ISO8601DateFormatter().string(from: .now),
            ]
            node["data"] = data
            nodes[index] = node
        }
        json["nodes"] = nodes
        let updated = documentFromEditedJSON(json, at: document.fileURL)
        try save(updated)
        return updated
    }

    /// Imports a map document returned by Flightdeck Maps    /// Imports a map document returned by Flightdeck Maps without touching a
    /// local edit that already exists. The file is written only when absent;
    /// the returned Document is still registered in the graph.
    static func importRemote(_ data: Data, existing: Bool) throws -> Document {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? String == "signavio-map/1",
              let id = object["id"] as? String, !id.isEmpty else {
            throw NSError(domain: "ProcessLink.Maps", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a signavio-map/1 document"])
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let url = folderURL.appendingPathComponent(id).appendingPathExtension("json")
        if !existing {
            let pretty = try JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try pretty.write(to: url, options: .atomic)
        }
        return document(from: object, at: url)
    }

    static func save(_ document: Document) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: document.json,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: document.fileURL, options: .atomic)
    }

    /// Regenerates the `processLink` block of one shape after an edit, without
    /// touching the human-authored label/role/system fields.
    static func updateNode(_ document: Document, nodeID: String,
                           label: String?, role: String?, system: String?, estimateMin: Double?) -> Document {
        var json = document.json
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        guard let index = nodes.firstIndex(where: { $0["id"] as? String == nodeID }) else { return document }
        var node = nodes[index]
        if let label { node["label"] = label }
        var data = node["data"] as? [String: Any] ?? [:]
        if let role { data["role"] = role.isEmpty ? nil : role }
        if let system { data["systemUsed"] = system.isEmpty ? nil : system }
        if let estimateMin {
            var timing = data["timing"] as? [String: Any] ?? [:]
            timing["estimateMin"] = estimateMin
            data["timing"] = timing
        }
        node["data"] = data
        nodes[index] = node
        json["nodes"] = nodes
        var meta = json["meta"] as? [String: Any] ?? [:]
        meta["approved"] = false
        json["meta"] = meta
        var updated = document
        updated.json = json
        updated.nodes = (MapsBridge.document(from: json, at: document.fileURL)).nodes
        updated.edges = document.edges
        updated.updatedAt = .now
        return updated
    }

    /// Binds one shape to a mined step without touching the human fields.
    static func bindNode(_ document: Document, nodeID: String,
                         step: StepRecord, process: ProcessRecord) -> Document {
        var json = document.json
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        guard let index = nodes.firstIndex(where: { $0["id"] as? String == nodeID }) else { return document }
        var node = nodes[index]
        var data = node["data"] as? [String: Any] ?? [:]
        data["processLink"] = [
            "processId": process.id,
            "stepId": step.id,
            "kgNodeId": step.kgID,
            "kgProcessId": process.kgID,
            "syncedAt": ISO8601DateFormatter().string(from: .now),
        ]
        node["data"] = data
        nodes[index] = node
        json["nodes"] = nodes
        var meta = json["meta"] as? [String: Any] ?? [:]
        meta["approved"] = false
        json["meta"] = meta
        return documentFromEditedJSON(json, at: document.fileURL)
    }

    /// Builds a map document from mined steps. This is the ProcessLink → Maps
    /// direction: the map is a real Flightdeck document with bindings, not a
    /// screenshot or a private drawing.
    static func makeMap(process: ProcessRecord, steps: [StepRecord], initiativeID: String? = nil) -> Document {
        let id = "map-\(process.id)-as-is"
        let lanes = unique(steps.map(\.role))
        var nodes: [[String: Any]] = []
        var edges: [[String: Any]] = []
        for (index, step) in steps.enumerated() {
            let lane = max(0, lanes.firstIndex(of: step.role) ?? 0)
            let data: [String: Any] = [
                "role": step.role,
                "systemUsed": step.application,
                "timing": ["estimateMin": step.minutes],
                "processLink": [
                    "processId": process.id,
                    "stepId": step.id,
                    "kgNodeId": step.kgID,
                    "kgProcessId": process.kgID,
                    "syncedAt": ISO8601DateFormatter().string(from: .now),
                ],
            ]
            nodes.append([
                "id": "n-\(step.id)",
                "type": index == 0 ? "start" : (index == steps.count - 1 ? "end" : "step"),
                "label": step.name,
                "position": ["x": 150 + Double(index) * 185, "y": 50 + Double(lane) * 100],
                "data": data,
            ])
            if index > 0 {
                edges.append([
                    "id": "e-\(index)",
                    "source": "n-\(steps[index - 1].id)",
                    "target": "n-\(step.id)",
                ])
            }
        }
        var meta: [String: Any] = [
            "createdBy": "ai-draft",
            "approved": false,
            "sourceProcessId": process.id,
            "lanes": lanes,
            "processLink": [
                "processId": process.id,
                "kgProcessId": process.kgID,
                "generatedAt": ISO8601DateFormatter().string(from: .now),
                "generatedBy": "ProcessLink",
                "source": process.sourceRaw,
                "version": "processlink-maps/1",
            ],
        ]
        if let initiativeID { meta["initiativeId"] = initiativeID }
        let json: [String: Any] = [
            "schema": "signavio-map/1",
            "id": id,
            "label": "\(process.name) — as-is",
            "nodes": nodes,
            "edges": edges,
            "meta": meta,
        ]
        let url = folderURL.appendingPathComponent("\(id).json")
        var document = document(from: json, at: url)
        document.updatedAt = .now
        return document
    }

    /// Seeds two readable maps on first run so the integration can be seen
    /// without a live Flightdeck. One shape deliberately disagrees with the
    /// mined role, to show drift in both directions.
    static func seedIfNeeded(processes: [ProcessRecord], steps: [StepRecord]) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let existingIDs = Set(loadAll().map(\.id))
        for process in processes where ["p-order-intake", "p-triage"].contains(process.id) {
            let expectedID = "map-\(process.id)-as-is"
            guard !existingIDs.contains(expectedID) else { continue }
            let processSteps = steps.filter { $0.processID == process.id }.sorted { $0.order < $1.order }
            guard !processSteps.isEmpty else { continue }
            var document = makeMap(process: process, steps: processSteps)
            if process.id == "p-order-intake", let index = document.nodes.firstIndex(where: { $0.label == "Check customer master" }) {
                var json = document.json
                var nodes = json["nodes"] as? [[String: Any]] ?? []
                var node = nodes[index]
                var data = node["data"] as? [String: Any] ?? [:]
                data["role"] = "Master Data"
                var timing = data["timing"] as? [String: Any] ?? [:]
                timing["estimateMin"] = 12
                data["timing"] = timing
                node["data"] = data
                nodes[index] = node
                json["nodes"] = nodes
                document.json = json
                document = documentFromEditedJSON(json, at: document.fileURL)
            }
            try? save(document)
        }
    }

    private static func documentFromEditedJSON(_ json: [String: Any], at url: URL) -> Document {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? json
        return MapsBridge.document(from: decoded, at: url)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: [String] = []
        for value in values where !seen.contains(value) { seen.append(value) }
        return seen
    }
}

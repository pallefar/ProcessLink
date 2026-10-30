import AppKit
import ProcessLinkKit
import SwiftData
import SwiftUI

/// Flightdeck Maps, read and written as `signavio-map/1` documents.
///
/// Two-way: the shape inspector shows the mined step, opportunity and saving
/// from ProcessLink; edits made on the map are saved to the document and
/// proposed to the graph instead of overwriting discovery.
struct MapsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \StepRecord.order) private var steps: [StepRecord]
    @Query private var opportunities: [OpportunityRecord]
    @Query private var initiatives: [InitiativeRecord]
    @Query private var datasets: [DatasetRecord]
    @Query private var feedback: [FeedbackRecord]

    @State private var documents: [MapsBridge.Document] = []
    @State private var selectedMapID: String?
    @State private var selectedNodeID: String?
    @State private var overlay: MapOverlay = .cycleTime
    @State private var search = ""
    @State private var didImportMaps = false
    @State private var importingMaps = false
    @State private var mapImportStatus: String?
    @State private var miningMap: MapsBridge.Document?
    @State private var feedbackSubject: FeedbackSubject?

    private var filtered: [MapsBridge.Document] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return documents }
        return documents.filter { $0.label.lowercased().contains(query) || $0.processID.lowercased().contains(query) }
    }

    private var current: MapsBridge.Document? {
        documents.first { $0.id == selectedMapID } ?? filtered.first ?? documents.first
    }

    private var process: ProcessRecord? {
        processes.first { $0.id == current?.processID }
    }

    private var selectedNode: MapsBridge.Node? {
        current?.nodes.first { $0.id == selectedNodeID }
    }

    private var stepsByID: [String: StepRecord] {
        Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
    }

    private func step(for node: MapsBridge.Node) -> StepRecord? {
        guard let link = node.link else { return nil }
        return stepsByID[link.stepID]
    }

    private var driftIDs: Set<String> {
        guard let document = current else { return [] }
        return Set(document.nodes.compactMap { node in
            guard let mined = step(for: node) else { return nil }
            let systemMismatch = !node.system.isEmpty && node.system != mined.application
            let timingMismatch = node.estimateMin.map { abs($0 - mined.minutes) > 0.5 } ?? false
            return node.role != mined.role || systemMismatch || timingMismatch ? node.id : nil
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.6)
            if let document = current {
                GeometryReader { _ in
                    FlightdeckMapCanvas(document: document, selectedID: selectedNodeID,
                                        overlay: overlay, driftIDs: driftIDs,
                                        stepsByID: stepsByID) { id in
                        selectedNodeID = id
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if document.nodes.count > 5 {
                        Chip(text: "Scroll to see all \(document.nodes.count) shapes",
                             symbol: "arrow.right", tint: .secondary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                ContentUnavailableView("No maps yet", systemImage: "map",
                                       description: Text("Create one from a discovered process."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().opacity(0.6)
            inspectorBar
                .frame(height: 312)
        }
        .navigationTitle("Maps")
        .onAppear {
            load()
            Task { await importMapsIfNeeded() }
        }
        .sheet(item: $feedbackSubject) { subject in
            FeedbackSheet(subject: subject)
        }
        .sheet(item: $miningMap) { document in
            MapMiningSheet(document: document,
                           dataset: datasets.first { $0.mapID == document.id })
        }
    }

    private func load() {
        MapsBridge.seedIfNeeded(processes: processes, steps: steps)
        documents = MapsBridge.loadAll()
        for document in documents {
            model.registerMap(document, process: processes.first { $0.id == document.processID })
        }
        if selectedMapID == nil || !documents.contains(where: { $0.id == selectedMapID }) {
            selectedMapID = documents.first?.id
            selectedNodeID = documents.first?.nodes.first(where: { $0.link != nil })?.id
        }
    }

    // MARK: List

    private var mapList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Text("\(filtered.count) maps")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    if let current { mineMap(current) }
                } label: {
                    Label("Mine", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(current == nil)
                .help("Mine the execution history of the current process map")
                .accessibilityLabel("Mine this process map")

                Menu {
                    ForEach(processes.filter { process in
                        !steps.filter { $0.processID == process.id }.isEmpty
                    }) { process in
                        Button {
                            newMap(for: process)
                        } label: {
                            Label(process.name, systemImage: "plus.rectangle.on.folder")
                        }
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Create a Flightdeck map from a discovered process")
                .accessibilityLabel("New map from process")
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.md)

            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search maps", text: $search)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)

            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { document in
                        Button {
                            selectedMapID = document.id
                            selectedNodeID = nil
                        } label: {
                            SelectableRow(selected: current?.id == document.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: Space.xs) {
                                        Image(systemName: "map")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(document.label)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Text(processes.first { $0.id == document.processID }?.name ?? "No linked process")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: Space.xs) {
                                        Chip(text: "\(document.nodes.count) shapes", symbol: "square.on.square", tint: .secondary)
                                        if !driftIDs.isEmpty {
                                            Chip(text: "\(driftIDs.count) drifted", symbol: "exclamationmark.triangle", tint: .orange)
                                        }
                                        if document.approved {
                                            Chip(text: "Approved", symbol: "checkmark.seal", tint: .green)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Toolbar and inspector

    private var toolbar: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Menu {
                    ForEach(documents) { document in
                        Button(document.label) {
                            selectedMapID = document.id
                            selectedNodeID = nil
                        }
                    }
                } label: {
                    Label(current?.label ?? "No map", systemImage: "map")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 260, alignment: .leading)
                .accessibilityLabel("Choose a map")

                if !driftIDs.isEmpty {
                    Chip(text: "\(driftIDs.count) differ", symbol: "exclamationmark.triangle", tint: .orange)
                }
                Spacer(minLength: Space.sm)

                Button {
                    if let current { mineMap(current) }
                } label: {
                    Label("Mine", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(current == nil)
                .help("Mine the execution history of the current process map")
                .accessibilityLabel("Mine this process map")

                Menu {
                    ForEach(processes.filter { process in
                        !steps.filter { $0.processID == process.id }.isEmpty
                    }) { process in
                        Button {
                            newMap(for: process)
                        } label: {
                            Label(process.name, systemImage: "plus.rectangle.on.folder")
                        }
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Publish a discovered process as a Flightdeck map")
                .accessibilityLabel("New map from process")

                Button {
                    Task { await importMapsFromFlightdeck() }
                } label: {
                    if importingMaps {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Import Maps", systemImage: "arrow.down.doc")
                    }
                }
                .disabled(importingMaps || !model.flightdeck.isSignedIn)
                .help("Import every map from the connected Flightdeck Maps projects")
                .accessibilityLabel("Import maps from Flightdeck")

                Button {
                    load()
                    model.showToast("Maps reloaded", detail: "Pulled the latest signavio-map/1 documents.",
                                    symbol: "arrow.down.doc")
                } label: {
                    Label("Pull", systemImage: "arrow.down.doc")
                }
                .help("Pull the latest documents from Flightdeck Maps")

                Button {
                    guard let current else { return }
                    feedbackSubject = FeedbackSubject(kind: .map, subjectID: current.id,
                                                      label: current.label)
                } label: {
                    Label(feedbackBadge, systemImage: "bubble.left.and.text.bubble.right")
                }
                .disabled(current == nil)
                .help("Comment on this map")
                .accessibilityLabel("Map feedback")

                Menu {
                    Button("Open document folder") { NSWorkspace.shared.open(MapsBridge.folderURL) }
                    Button("Reveal current file") {
                        if let document = current {
                            NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Flightdeck map actions")
                .accessibilityLabel("Map actions")
            }

            HStack(spacing: Space.sm) {
                if let process {
                    Text("\(process.name) · \(process.site)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 320, alignment: .leading)
                }
                Spacer(minLength: Space.sm)
                Picker("Overlay", selection: $overlay) {
                    ForEach(MapOverlay.allCases) { item in
                        Label(item.label, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 152)
                .accessibilityLabel("Map overlay")
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(.bar)
    }

    @ViewBuilder
    private var inspectorBar: some View {
        if let document = current, let node = selectedNode {
            MapShapeInspector(
                document: document,
                node: node,
                process: process,
                step: step(for: node),
                opportunities: opportunities.filter { $0.processID == document.processID },
                initiatives: initiatives.filter { $0.processID == document.processID },
                drifted: driftIDs.contains(node.id),
                horizontal: true,
                onSave: { label, role, system, estimate in
                    save(document: document, node: node, label: label, role: role,
                         system: system, estimate: estimate)
                },
                onRestore: {
                    guard let mined = step(for: node) else { return }
                    let json = MapsBridge.updateNode(document, nodeID: node.id,
                                                     label: mined.name, role: mined.role,
                                                     system: mined.application,
                                                     estimateMin: mined.minutes)
                    persist(json, summary: "Restored \(node.id) from discovery")
                },
                onBind: { mined in
                    let updated = MapsBridge.bindNode(document, nodeID: node.id,
                                                      step: mined, process: process ?? processes[0])
                    persist(updated, summary: "Bound \(node.id) to \(mined.name)")
                },
                onOpenProcess: {
                    model.selectedProcessID = document.processID
                    model.page = .discoveries
                },
                onOpenOpportunity: { id in
                    model.selectedOpportunityID = id
                    model.page = .opportunities
                },
                onOpenKG: {
                    model.selectedKGID = node.link?.kgNodeID ?? "kg-map-\(document.id)"
                    model.page = .graph
                },
                onFeedback: {
                    feedbackSubject = FeedbackSubject(
                        kind: .mapShape, subjectID: "\(document.id)#\(node.id)",
                        label: "\(document.label) · \(node.label)")
                }
            )
            .id(node.id)
        } else if let document = current {
            MapDocumentSummary(document: document, process: process,
                               opportunities: opportunities.filter { $0.processID == document.processID },
                               initiatives: initiatives.filter { $0.processID == document.processID },
                               driftCount: driftIDs.count,
                               onOpenFolder: { NSWorkspace.shared.open(MapsBridge.folderURL) },
                               onOpenKG: {
                                   model.selectedKGID = "kg-map-\(document.id)"
                                   model.page = .graph
                               },
                               onRegenerate: { regenerate(document) },
                               onFeedback: {
                                   feedbackSubject = FeedbackSubject(kind: .map, subjectID: document.id,
                                                                     label: document.label)
                               })
        } else {
            ContentUnavailableView("Select a map", systemImage: "map")
        }
    }

    private func importMapsIfNeeded() async {
        guard !didImportMaps else { return }
        didImportMaps = true
        guard model.flightdeck.isSignedIn || KeychainStore.get(account: "session-cookie") != nil else { return }
        if !model.flightdeck.isSignedIn { await model.flightdeck.restoreSession() }
        guard model.flightdeck.isSignedIn else { return }
        await importMapsFromFlightdeck()
    }

    private func importMapsFromFlightdeck() async {
        guard !importingMaps else { return }
        importingMaps = true
        defer { importingMaps = false }
        if !model.flightdeck.isSignedIn { await model.flightdeck.restoreSession() }
        guard model.flightdeck.isSignedIn else {
            mapImportStatus = "Connect Flightdeck first"
            return
        }
        let result = await model.flightdeck.importFlightdeckMaps(into: model)
        load()
        if result.imported > 0 {
            mapImportStatus = "\(result.imported) from Flightdeck Maps"
            model.showToast("Maps imported",
                            detail: "\(result.imported) from Flightdeck Maps\(result.failed > 0 ? " · \(result.failed) unavailable" : "")",
                            symbol: "arrow.down.doc")
        } else if result.failed > 0 {
            mapImportStatus = "Maps unavailable"
            model.showToast("Maps not available",
                            detail: "Flightdeck Maps did not return a readable map.",
                            symbol: "exclamationmark.triangle", warning: true)
        } else {
            mapImportStatus = "Maps up to date"
        }
    }

    private var feedbackBadge: String {
        guard let current else { return "Feedback" }
        let count = feedback.filter {
            $0.subjectID == current.id || $0.subjectID.hasPrefix(current.id + "#")
        }.filter { !$0.resolved && $0.parentID.isEmpty }.count
        return count == 0 ? "Feedback" : "Feedback \(count)"
    }

    private func mineMap(_ document: MapsBridge.Document) {
        if let dataset = datasets.first(where: { $0.mapID == document.id }) {
            model.selectedDatasetID = dataset.id
            if !dataset.processID.isEmpty { model.selectedProcessID = dataset.processID }
            model.page = .mining
        } else {
            miningMap = document
        }
    }

    private func newMap(for process: ProcessRecord) {
        let processSteps = steps.filter { $0.processID == process.id }.sorted { $0.order < $1.order }
        guard !processSteps.isEmpty else { return }
        var document = MapsBridge.makeMap(process: process, steps: processSteps)
        if documents.contains(where: { $0.id == document.id }) {
            document.json["id"] = "\(document.id)-\(Int(Date().timeIntervalSince1970))"
            document.id = document.json["id"] as? String ?? document.id
            document.fileURL = MapsBridge.folderURL.appendingPathComponent("\(document.id).json")
        }
        try? MapsBridge.save(document)
        documents = MapsBridge.loadAll()
        selectedMapID = document.id
        selectedNodeID = nil
        model.registerMap(document, process: process)
        model.showToast("Map published", detail: "\(document.nodes.count) shapes · signavio-map/1",
                        symbol: "map")
    }

    private func regenerate(_ document: MapsBridge.Document) {
        guard let process else { return }
        let processSteps = steps.filter { $0.processID == process.id }.sorted { $0.order < $1.order }
        let fresh = MapsBridge.makeMap(process: process, steps: processSteps)
        var updated = document
        updated.json["nodes"] = fresh.json["nodes"]
        updated.json["edges"] = fresh.json["edges"]
        updated.nodes = fresh.nodes
        updated.edges = fresh.edges
        persist(updated, summary: "Regenerated from discovery")
    }

    private func save(document: MapsBridge.Document, node: MapsBridge.Node,
                      label: String, role: String, system: String, estimate: Double?) {
        let updated = MapsBridge.updateNode(document, nodeID: node.id, label: label,
                                            role: role, system: system, estimateMin: estimate)
        var changes: [String] = []
        if label != node.label { changes.append("label '\(node.label)' → '\(label)'") }
        if role != node.role { changes.append("role '\(node.role)' → '\(role)'") }
        if system != node.system { changes.append("system '\(node.system)' → '\(system)'") }
        if let estimate, let old = node.estimateMin, abs(estimate - old) > 0.01 {
            changes.append("time \(Int(old)) → \(Int(estimate)) min")
        }
        persist(updated, summary: changes.isEmpty ? "Saved without a semantic change" : changes.joined(separator: "; "))
    }

    private func persist(_ document: MapsBridge.Document, summary: String) {
        try? MapsBridge.save(document)
        documents = documents.map { $0.id == document.id ? document : $0 }
        model.registerMap(document, process: processes.first { $0.id == document.processID })
        model.recordMapEdit(document, nodeID: selectedNodeID ?? "map", summary: summary)
        model.showToast("Map saved", detail: summary, symbol: "square.and.arrow.down")
    }
}

// MARK: - Canvas

/// Draws the document exactly as Maps stores it: absolute positions, lane
/// bands by role, arrows between shapes. Shape size is fixed so labels stay
/// readable; long processes scroll rather than shrink.
private struct FlightdeckMapCanvas: View {
    var document: MapsBridge.Document
    var selectedID: String?
    var overlay: MapOverlay
    var driftIDs: Set<String>
    var stepsByID: [String: StepRecord]
    var onSelect: (String) -> Void

    private let nodeWidth: CGFloat = 176
    private let nodeHeight: CGFloat = 70

    private var lanes: [(role: String, y: CGFloat)] {
        var result: [(String, CGFloat)] = []
        for node in document.nodes where !result.contains(where: { $0.0 == (node.role.isEmpty ? "Unassigned" : node.role) }) {
            result.append((node.role.isEmpty ? "Unassigned" : node.role, CGFloat(node.y)))
        }
        return result.sorted { $0.1 < $1.1 }
    }

    private var canvasSize: CGSize {
        let maxX = document.nodes.map(\.x).max() ?? 0
        let maxY = document.nodes.map(\.y).max() ?? 0
        return CGSize(width: max(920, CGFloat(maxX) + nodeWidth + 180),
                      height: max(420, CGFloat(maxY) + nodeHeight + 80))
    }

    private func point(_ node: MapsBridge.Node) -> CGPoint {
        CGPoint(x: CGFloat(node.x) + 120 + nodeWidth / 2,
                y: CGFloat(node.y) + nodeHeight / 2)
    }

    private func overlayValue(_ node: MapsBridge.Node) -> Double {
        guard let step = node.link.flatMap({ stepsByID[$0.stepID] }) else { return 0 }
        switch overlay {
        case .cycleTime: return step.minutes / 20
        case .handoffs: return Double(step.handoffs) / 2
        case .rework: return step.reworkShare / 0.4
        case .automation:
            switch step.waste {
            case .unusedTalent: return 0.9
            case .overProcessing: return 0.8
            case .rework: return 0.65
            case .handoffs: return 0.6
            case .contextSwitching: return 0.5
            case .defects: return 0.45
            case .waiting: return 0.35
            case .backlog: return 0.25
            }
        }
    }

    private func overlayText(_ node: MapsBridge.Node) -> String {
        guard let step = node.link.flatMap({ stepsByID[$0.stepID] }) else { return "Not bound" }
        switch overlay {
        case .cycleTime: return Fmt.minutes(step.minutes)
        case .handoffs: return "\(step.handoffs) handoffs"
        case .rework: return "\(Fmt.percent(step.reworkShare)) rework"
        case .automation: return "\(step.waste.label) · \(Fmt.percent(step.reworkShare)) rework"
        }
    }

    private func tint(_ value: Double) -> Color {
        let t = min(1, max(0, value))
        return t < 0.5 ? Color.green.mix(with: .orange, by: t * 2) : Color.orange.mix(with: .red, by: (t - 0.5) * 2)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(lanes, id: \.role) { lane in
                    let y = lane.y
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        .frame(width: canvasSize.width, height: nodeHeight + 48)
                        .offset(y: y + 12) // grid: ok map document coordinate
                    Text(lane.role)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 108, alignment: .leading)
                        .offset(x: 10, y: y + 34) // grid: ok map document coordinate
                }

                Canvas { context, _ in
                    for edge in document.edges {
                        guard let source = document.nodes.first(where: { $0.id == edge.source }),
                              let target = document.nodes.first(where: { $0.id == edge.target }) else { continue }
                        let start = CGPoint(x: point(source).x + nodeWidth / 2, y: point(source).y)
                        let end = CGPoint(x: point(target).x - nodeWidth / 2, y: point(target).y)
                        var path = Path()
                        path.move(to: start)
                        if abs(start.y - end.y) < 2 {
                            path.addLine(to: end)
                        } else {
                            let mid = (start.x + end.x) / 2
                            path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y),
                                          control2: CGPoint(x: mid, y: end.y))
                        }
                        context.stroke(path, with: .color(Color.secondary.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)

                ForEach(document.nodes) { node in
                    let step = node.link.flatMap { stepsByID[$0.stepID] }
                    let drifted = driftIDs.contains(node.id)
                    MapShapeCard(node: node, step: step, overlayText: overlayText(node),
                                 heat: tint(overlayValue(node)), drifted: drifted,
                                 selected: selectedID == node.id, width: nodeWidth)
                        .frame(width: nodeWidth, height: nodeHeight)
                        .position(point(node)) // grid: ok map document coordinate
                        .onTapGesture { onSelect(node.id) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(node.label), \(node.role.isEmpty ? "unassigned" : node.role), \(overlayText(node))")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MapShapeCard: View {
    var node: MapsBridge.Node
    var step: StepRecord?
    var overlayText: String
    var heat: Color
    var drifted: Bool
    var selected: Bool
    var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(node.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if drifted {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("This shape differs from the mined step")
                } else if node.link != nil {
                    Image(systemName: "hexagon")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                        .help("Bound to \(node.link?.kgNodeID ?? "")")
                }
            }
            Text(node.system.isEmpty ? node.role : node.system)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(overlayText)
                    .font(.caption2.weight(.medium).monospacedDigit())
                Spacer(minLength: 0)
                if let step {
                    Text(step.waste.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(heat.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Palette.accent : Color(nsColor: .separatorColor),
                              lineWidth: selected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Inspector

private struct MapShapeInspector: View {
    @Environment(AppModel.self) private var model
    var document: MapsBridge.Document
    var node: MapsBridge.Node
    var process: ProcessRecord?
    var step: StepRecord?
    var opportunities: [OpportunityRecord]
    var initiatives: [InitiativeRecord]
    var drifted: Bool
    var horizontal = false
    var onSave: (String, String, String, Double?) -> Void
    var onRestore: () -> Void
    var onBind: (StepRecord) -> Void
    var onOpenProcess: () -> Void
    var onOpenOpportunity: (String) -> Void
    var onOpenKG: () -> Void
    var onFeedback: () -> Void

    @State private var label: String
    @State private var role: String
    @State private var system: String
    @State private var estimate: String

    init(document: MapsBridge.Document, node: MapsBridge.Node, process: ProcessRecord?,
         step: StepRecord?, opportunities: [OpportunityRecord], initiatives: [InitiativeRecord],
         drifted: Bool, horizontal: Bool = false,
         onSave: @escaping (String, String, String, Double?) -> Void,
         onRestore: @escaping () -> Void, onBind: @escaping (StepRecord) -> Void,
         onOpenProcess: @escaping () -> Void, onOpenOpportunity: @escaping (String) -> Void,
         onOpenKG: @escaping () -> Void, onFeedback: @escaping () -> Void) {
        self.document = document
        self.node = node
        self.process = process
        self.step = step
        self.opportunities = opportunities
        self.initiatives = initiatives
        self.drifted = drifted
        self.horizontal = horizontal
        self.onSave = onSave
        self.onRestore = onRestore
        self.onBind = onBind
        self.onOpenProcess = onOpenProcess
        self.onOpenOpportunity = onOpenOpportunity
        self.onOpenKG = onOpenKG
        self.onFeedback = onFeedback
        _label = State(initialValue: node.label)
        _role = State(initialValue: node.role)
        _system = State(initialValue: node.system)
        _estimate = State(initialValue: node.estimateMin.map { String(Int($0)) } ?? "")
    }

    private var topOpportunity: OpportunityRecord? {
        opportunities.max { $0.score.total < $1.score.total }
    }

    private var validated: Double {
        SavingsLedger.totals(initiatives.map(\.savingLine)).validated
    }

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: Space.lg) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.md) {
                            header
                            mapFields
                            actions
                        }
                        .padding(Space.md)
                    }
                    .frame(width: 392)

                    ScrollView {
                        Group {
                            if let step { processLinkCard(step) } else { unboundCard }
                        }
                        .padding(Space.md)
                    }
                    .frame(maxWidth: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.md) {
                            if drifted, let step { driftCard(step) }
                            GuardrailNote(text: "Saving records a map change proposal. The mined step is not overwritten.")
                        }
                        .padding(Space.md)
                    }
                    .frame(width: 280)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        header
                        mapFields
                        if let step { processLinkCard(step) } else { unboundCard }
                        if drifted, let step { driftCard(step) }
                        actions
                    }
                    .padding(Space.lg)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.type.capitalized)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(node.label)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.xs) {
                if node.link != nil {
                    Chip(text: "KG bound", symbol: "hexagon", tint: .teal)
                } else {
                    Chip(text: "Not bound", symbol: "link.badge.plus", tint: .orange)
                }
                if drifted {
                    Chip(text: "Map proposal", symbol: "pencil", tint: .orange)
                }
            }
        }
    }

    private var mapFields: some View {
        Card("Map fields", subtitle: "Owned by Flightdeck Maps. Saving writes the document.", symbol: "map") {
            VStack(alignment: .leading, spacing: Space.sm) {
                TextField("Label", text: $label)
                    .textFieldStyle(.roundedBorder)
                TextField("Role / lane", text: $role)
                    .textFieldStyle(.roundedBorder)
                TextField("Application / system", text: $system)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: Space.sm) {
                    TextField("Minutes", text: $estimate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Text("estimate").font(.caption).foregroundStyle(.tertiary)
                }
                HStack(spacing: Space.sm) {
                    Button("Save to map") {
                        onSave(label, role, system, Double(estimate))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Restore") { onRestore() }
                        .disabled(step == nil)
                        .help("Restore this shape from the mined step")
                }
            }
        }
    }

    private func processLinkCard(_ step: StepRecord) -> some View {
        Card("ProcessLink", subtitle: "Live mined facts for this shape.", symbol: "hexagon") {
            VStack(alignment: .leading, spacing: Space.sm) {
                DetailRow(label: "Process", value: process?.name ?? "Unknown")
                DetailRow(label: "Step", value: step.name)
                DetailRow(label: "Time", value: Fmt.minutes(step.minutes))
                DetailRow(label: "Handoffs", value: "\(step.handoffs)")
                DetailRow(label: "Rework", value: Fmt.percent(step.reworkShare))
                DetailRow(label: "Waste", value: step.waste.label)
                DetailRow(label: "KG node", value: step.kgID, mono: true)
                DetailRow(label: "Mined events", value: "\(step.evidenceCount)")

                if let topOpportunity {
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(opportunities.count) opportunit\(opportunities.count == 1 ? "y" : "ies") on this process")
                            .font(.caption.weight(.semibold))
                        Text(topOpportunity.title)
                            .font(.caption)
                            .lineLimit(2)
                        HStack(spacing: Space.xs) {
                            Chip(text: Fmt.hoursPerYear(topOpportunity.annualHours), tint: .orange)
                            Button("Open") { onOpenOpportunity(topOpportunity.id) }
                                .controlSize(.mini)
                        }
                    }
                }
                if validated > 0 {
                    Divider().opacity(0.6)
                    HStack(spacing: Space.xs) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("\(Fmt.hours(validated)) validated on this process")
                            .font(.caption)
                    }
                }
                HStack(spacing: Space.md) {
                    Button("Open process") { onOpenProcess() }
                        .controlSize(.small)
                    Button("Open KG node") { onOpenKG() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var unboundCard: some View {
        Card("Not in ProcessLink yet", subtitle: "Bind this shape to a mined step to see live metrics.", symbol: "link.badge.plus") {
            if let process {
                let candidates = (try? model.context.fetch(FetchDescriptor<StepRecord>()))?
                    .filter { $0.processID == process.id }
                    .sorted { $0.order < $1.order } ?? []
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("This shape was added or renamed on the map. A binding makes it part of the graph; it does not overwrite the map.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu("Bind to a step") {
                        ForEach(candidates) { candidate in
                            Button(candidate.name) { onBind(candidate) }
                        }
                    }
                    .fixedSize()
                }
            } else {
                Text("Link the map to a process first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func driftCard(_ step: StepRecord) -> some View {
        Card("Map differs from discovery", subtitle: "A proposal, not a silent overwrite.", symbol: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: Space.xs) {
                if node.role != step.role {
                    Text("Role: map '\(node.role)' · mined '\(step.role)'")
                        .font(.caption)
                }
                if !node.system.isEmpty && node.system != step.application {
                    Text("System: map '\(node.system)' · mined '\(step.application)'")
                        .font(.caption)
                }
                if let estimate = node.estimateMin, abs(estimate - step.minutes) > 0.5 {
                    Text("Time: map \(Int(estimate)) min · mined \(Int(step.minutes)) min")
                        .font(.caption)
                }
                GuardrailNote(text: "Saving records a map change proposal against \(step.kgID). A human decides whether to update standard work or the map.")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.sm) {
            Text(document.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button("Feedback") { onFeedback() }
                .controlSize(.small)
            Button("Reveal file") {
                NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
            }
            .controlSize(.small)
        }
    }
}

private struct MapDocumentSummary: View {
    var document: MapsBridge.Document
    var process: ProcessRecord?
    var opportunities: [OpportunityRecord]
    var initiatives: [InitiativeRecord]
    var driftCount: Int
    var onOpenFolder: () -> Void
    var onOpenKG: () -> Void
    var onRegenerate: () -> Void
    var onFeedback: () -> Void

    private var validated: Double {
        SavingsLedger.totals(initiatives.map(\.savingLine)).validated
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Space.lg) {
                Card("Document", subtitle: "signavio-map/1, owned by Flightdeck Maps.", symbol: "doc") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Map id", value: document.id, mono: true)
                        DetailRow(label: "Label", value: document.label)
                        DetailRow(label: "Process", value: process?.name ?? "Not linked")
                        DetailRow(label: "Shapes", value: "\(document.nodes.count) · \(document.boundNodes) bound")
                        DetailRow(label: "Generated", value: document.generatedAt.map { Fmt.day($0) } ?? "—")
                    }
                }
                .frame(width: 392)

                Card("ProcessLink", subtitle: "What the map is about.", symbol: "hexagon") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Annual effort", value: process.map { Fmt.hoursPerYear($0.annualHours) } ?? "—")
                        DetailRow(label: "Rework", value: process.map { Fmt.percent($0.reworkRate) } ?? "—")
                        DetailRow(label: "Opportunities", value: "\(opportunities.count)")
                        DetailRow(label: "Validated", value: Fmt.hours(validated))
                        if driftCount > 0 {
                            DetailRow(label: "Drifted shapes", value: "\(driftCount)")
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Space.md) {
                    Button("Open folder") { onOpenFolder() }
                    Button("KG node") { onOpenKG() }
                    Button("Feedback") { onFeedback() }
                    Button("Regenerate from discovery") { onRegenerate() }
                        .disabled(process == nil)
                    GuardrailNote(text: "Select a shape to see its ProcessLink facts and map fields.")
                }
                .controlSize(.small)
                .frame(width: 260, alignment: .leading)
            }
            .padding(Space.md)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct MapDocumentInspector: View {
    var document: MapsBridge.Document
    var process: ProcessRecord?
    var opportunities: [OpportunityRecord]
    var initiatives: [InitiativeRecord]
    var driftCount: Int
    var onOpenFolder: () -> Void
    var onOpenKG: () -> Void
    var onRegenerate: () -> Void
    var onFeedback: () -> Void

    private var validated: Double {
        SavingsLedger.totals(initiatives.map(\.savingLine)).validated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Map").font(.caption).foregroundStyle(.tertiary)
                    Text(document.label).font(.headline)
                    HStack(spacing: Space.xs) {
                        Chip(text: document.approved ? "Approved" : "Draft",
                             tint: document.approved ? .green : .orange)
                        if driftCount > 0 {
                            Chip(text: "\(driftCount) drifted", symbol: "exclamationmark.triangle", tint: .orange)
                        }
                    }
                }

                Card("Document", subtitle: "signavio-map/1, owned by Flightdeck Maps.", symbol: "doc") {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        DetailRow(label: "Map id", value: document.id, mono: true)
                        DetailRow(label: "Process", value: process?.name ?? "Not linked")
                        DetailRow(label: "KG process", value: document.kgProcessID.isEmpty ? "—" : document.kgProcessID, mono: true)
                        DetailRow(label: "Shapes", value: "\(document.nodes.count) · \(document.boundNodes) bound")
                        DetailRow(label: "Generated", value: document.generatedAt.map { Fmt.day($0) } ?? "—")
                        DetailRow(label: "Updated", value: Fmt.stamp(document.updatedAt))
                    }
                }

                if let process {
                    Card("ProcessLink", subtitle: "What the map is about.", symbol: "hexagon") {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            DetailRow(label: "Annual effort", value: Fmt.hoursPerYear(process.annualHours))
                            DetailRow(label: "Rework", value: Fmt.percent(process.reworkRate))
                            DetailRow(label: "Opportunities", value: "\(opportunities.count)")
                            DetailRow(label: "Validated", value: Fmt.hours(validated))
                        }
                    }
                }

                HStack(spacing: Space.sm) {
                    Button("Open folder") { onOpenFolder() }
                    Button("KG node") { onOpenKG() }
                    Button("Regenerate") { onRegenerate() }
                        .disabled(process == nil)
                }
                .controlSize(.small)

                GuardrailNote(text: "ProcessLink reads and writes the same map document as Flightdeck Maps. Shape edits create proposals; they never overwrite discovery.")
            }
            .padding(Space.lg)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}


private struct MapMiningSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let document: MapsBridge.Document
    let dataset: DatasetRecord?

    @State private var busy = false
    @State private var error: String?
    @State private var showingCSV = false

    private var mapSteps: [MapsBridge.Node] {
        document.nodes.filter { $0.type != "start" && $0.type != "end" }
    }

    /// Local as-is maps have no Flightdeck execution history. Contract-flow
    /// tickets belong to maps imported from the OS.
    private var canPullLive: Bool {
        !document.id.hasPrefix("map-")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mine this process").font(.title3.weight(.semibold))
                    Text(document.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Close") { dismiss() }
            }

            HStack(spacing: Space.md) {
                MetricTile(title: "Map steps", value: "\(mapSteps.count)", detail: "The reference model",
                           symbol: "square.on.square", tint: .blue)
                MetricTile(title: "Edges", value: "\(document.edges.count)", detail: "Expected flow",
                           symbol: "arrow.triangle.branch", tint: .purple)
                MetricTile(title: "Linked process", value: document.processID.isEmpty ? "None" : "Yes",
                           detail: document.processID.isEmpty ? "The log will create one" : document.processID,
                           symbol: "link", tint: .teal)
            }

            if let dataset {
                Card("Existing execution log", subtitle: "\(dataset.name)", symbol: "tablecells") {
                    HStack {
                        Text("\(dataset.caseCount) cases · \(dataset.eventCount) events")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open mining") {
                            model.selectedDatasetID = dataset.id
                            model.page = .mining
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Card("Get the execution log", subtitle: "A map is the model; mining needs what actually happened.", symbol: "sparkle.magnifyingglass") {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if canPullLive {
                            HStack(alignment: .top, spacing: Space.sm) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    .foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pull live contract-flow history").font(.subheadline.weight(.medium))
                                    Text("Tickets, runs, four-eye checks, PDFs, works-council steps and signatures from Flightdeck OS.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    pullLive()
                                } label: {
                                    if busy { ProgressView().controlSize(.small) }
                                    else { Text("Pull live") }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy || !model.flightdeck.isSignedIn)
                            }
                            RowDivider()
                        } else {
                            Text("This local as-is map has no Flightdeck execution log. Import a CSV, or select an OS map to pull contract-flow history.")
                                .font(.caption).foregroundStyle(.secondary)
                            RowDivider()
                        }
                        HStack(alignment: .top, spacing: Space.sm) {
                            Image(systemName: "tablecells").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import a CSV for this map").font(.subheadline.weight(.medium))
                                Text("For a system export or a log from another execution engine. Columns are mapped on the next screen.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Choose CSV…") { showingCSV = true }
                                .disabled(busy)
                        }
                        if !model.flightdeck.isSignedIn {
                            Text("Connect Flightdeck first for the live contract-flow path.")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            GuardrailNote(text: "A map step is a model fact. The event log is evidence. Mining never treats the map as proof that a step happened, and an unmapped activity is shown rather than silently dropped.")
        }
        .padding(Space.lg)
        .frame(width: 620, height: 600)
        .fileImporter(isPresented: $showingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): importCSV(url)
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }

    private func pullLive() {
        busy = true
        error = nil
        Task {
            let result = await model.flightdeck.importContractFlow(into: model, map: document)
            busy = false
            if result != nil { dismiss() }
        }
    }

    private func importCSV(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let dataset = try model.importCSV(
                text: text, name: url.deletingPathExtension().lastPathComponent,
                filename: url.lastPathComponent, site: "", mapID: document.id)
            guard let process = model.createProcess(from: dataset) else {
                self.error = "The log imported, but no process could be created."
                return
            }
            dataset.processID = process.id
            let processSteps = (try? model.context.fetch(FetchDescriptor<StepRecord>())) ?? []
            let mapped = try MapsBridge.attachProcess(document, process: process,
                                                      steps: processSteps.filter { $0.processID == process.id })
            model.registerMap(mapped, process: process)
            model.selectedDatasetID = dataset.id
            model.selectedProcessID = process.id
            model.page = .mining
            try? model.context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

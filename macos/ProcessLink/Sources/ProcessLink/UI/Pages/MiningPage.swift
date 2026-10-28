import ProcessLinkKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// In-house discovery: mine an event log or capture desktop task activity,
/// then turn the result into the same process/step/variant records KYP.ai
/// produces. No tenant dependency; no screenshots or keystrokes.
struct MiningPage: View {
    enum Mode: String, CaseIterable, Identifiable {
        case logs, capture
        var id: String { rawValue }
        var label: String { self == .logs ? "Process logs" : "Task capture" }
        var symbol: String { self == .logs ? "tablecells" : "record.circle" }
    }

    @Environment(AppModel.self) private var model
    @Query(sort: \DatasetRecord.importedAt, order: .reverse) private var datasets: [DatasetRecord]
    @Query(sort: \CaptureSessionRecord.startedAt, order: .reverse) private var sessions: [CaptureSessionRecord]
    @Query private var captureApps: [CaptureAppRecord]
    @Query(sort: \ProcessRecord.name) private var processes: [ProcessRecord]
    @Query(sort: \StepRecord.order) private var steps: [StepRecord]

    @State private var mode: Mode = .logs
    @State private var selectedDatasetID: String?
    @State private var importing = false
    @State private var importError: String?
    @State private var pendingCSV: PendingCSV?
    @State private var referenceProcessID: String?
    @State private var capture = ActivityCapture.shared
    @State private var captureRole = "Order Desk"
    @State private var captureSite = "Bensheim"
    @State private var captureName = "Desktop work"

    private var selectedDataset: DatasetRecord? {
        datasets.first { $0.id == selectedDatasetID } ?? datasets.first
    }

    private var mined: MinedProcess? {
        selectedDataset.map { model.minedProcess(for: $0) }
    }

    private var referenceSteps: [String] {
        let id = referenceProcessID ?? processes.first(where: { process in
            !steps.filter { $0.processID == process.id }.isEmpty
        })?.id
        guard let id else { return [] }
        return steps.filter { $0.processID == id }.sorted { $0.order < $1.order }.map(\.name)
    }

    private var conformance: ConformanceReport? {
        guard let dataset = selectedDataset, !referenceSteps.isEmpty else { return nil }
        return ProcessMining.conformance(events: model.events(for: dataset), reference: referenceSteps)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            switch mode {
            case .logs: logsView
            case .capture: captureView
            }
        }
        .navigationTitle("Mining")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            handleImport(result)
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_MINING"] == "capture" {
                mode = .capture
            }
            if selectedDatasetID == nil { selectedDatasetID = datasets.first?.id }
        }
        .sheet(item: $pendingCSV) { file in
            MiningImportSheet(file: file)
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.label, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)

            Spacer()

            if mode == .logs {
                Button {
                    _ = model.importSampleDataset()
                } label: {
                    Label("Sample log", systemImage: "sparkles")
                }
                .help("Load the 24-case synthetic order log")

                Button {
                    importing = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .help("case_id, activity, timestamp, resource, application")
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(.bar)
    }

    // MARK: Process logs

    @ViewBuilder
    private var logsView: some View {
        if datasets.isEmpty {
            ContentUnavailableView {
                Label("Mine your first process", systemImage: "sparkle.magnifyingglass")
            } description: {
                Text("Import an event log (CSV) or load the sample. Case ids are hashed, resources are sanitised, and activity text is masked before it is stored.")
            } actions: {
                Button("Load the sample log") { _ = model.importSampleDataset() }
                    .buttonStyle(.borderedProminent)
                Button("Import CSV…") { importing = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                datasetList
                    .frame(width: 260)
                Divider()
                datasetDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var datasetList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(datasets.count) datasets").font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    importing = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Import a CSV event log")
                .accessibilityLabel("Import a CSV event log")
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(datasets) { dataset in
                        Button {
                            selectedDatasetID = dataset.id
                        } label: {
                            SelectableRow(selected: selectedDataset?.id == dataset.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dataset.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: Space.xs) {
                                        Chip(text: dataset.sourceRaw == "sample" ? "Sample" : "CSV",
                                             symbol: "tablecells", tint: .secondary)
                                        if !dataset.site.isEmpty {
                                            Chip(text: dataset.site, tint: .secondary)
                                        }
                                    }
                                    Text("\(dataset.caseCount) cases · \(dataset.eventCount) events")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Create discovered process") {
                                if let dataset = selectedDataset { model.createProcess(from: dataset) }
                            }
                            Button("Delete dataset", role: .destructive) {
                                model.deleteDataset(dataset)
                            }
                        }
                    }
                }
                .padding(Space.sm)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var datasetDetail: some View {
        if let dataset = selectedDataset {
            MiningWorkbench(dataset: dataset, processes: processes, steps: steps)
        } else {
            ContentUnavailableView("Select a dataset", systemImage: "tablecells")
        }
    }

    private func datasetHeader(_ dataset: DatasetRecord, mined: MinedProcess) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(dataset.name).font(.title2.weight(.semibold))
                Spacer()
                Button("Delete", role: .destructive) {
                    model.deleteDataset(dataset)
                }
                .controlSize(.small)
            }
            HStack(spacing: Space.xs) {
                Chip(text: dataset.sourceRaw == "sample" ? "In-house sample" : "CSV import",
                     symbol: "sparkles", tint: .blue)
                Chip(text: dataset.classification.label, symbol: "lock", tint: .secondary)
                if !dataset.site.isEmpty { Chip(text: dataset.site, symbol: "mappin.and.ellipse", tint: .secondary) }
                Chip(text: "\(mined.cases) cases", symbol: "shippingbox", tint: .secondary)
                Chip(text: "\(mined.events) events", symbol: "list.bullet", tint: .secondary)
                if let first = mined.firstTimestamp, let last = mined.lastTimestamp {
                    Chip(text: "\(Fmt.day(first)) – \(Fmt.day(last))", symbol: "calendar", tint: .secondary)
                }
            }
            Text(dataset.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metrics(_ mined: MinedProcess) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            MetricTile(title: "Median cycle", value: Fmt.minutes(mined.medianCycleMinutes),
                       detail: "P90 \(Fmt.minutes(mined.p90CycleMinutes))", symbol: "timer", tint: .blue)
            MetricTile(title: "Variants", value: "\(mined.variants.count)",
                       detail: "Top path \(Fmt.percent(mined.topVariant?.share ?? 0))",
                       symbol: "arrow.triangle.swap", tint: .purple)
            MetricTile(title: "Rework", value: Fmt.percent(mined.reworkRate),
                       detail: "Repeated activities", symbol: "arrow.triangle.2.circlepath", tint: .orange)
            MetricTile(title: "Handoffs", value: Fmt.percent(mined.handoffRate),
                       detail: "Role changes between events", symbol: "arrow.left.arrow.right", tint: .teal)
            MetricTile(title: "Automation candidates", value: "\(mined.automationCandidates.count)",
                       detail: "Score ≥ 0.55", symbol: "gearshape.2", tint: .green)
        }
    }

    private func variantsCard(_ mined: MinedProcess) -> some View {
        Card("Variants", subtitle: "The paths that actually ran, by case count.", symbol: "arrow.triangle.swap") {
            VStack(spacing: Space.md) {
                ForEach(mined.variants.prefix(5)) { variant in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Space.sm) {
                            Text(variant.sequence.prefix(4).joined(separator: " → "))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Spacer(minLength: Space.sm)
                            Text(Fmt.percent(variant.share))
                                .font(.subheadline.monospacedDigit())
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(variant.hasRework ? Color.orange : Palette.accent)
                                    .frame(width: max(4, proxy.size.width * variant.share))
                            }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                        Text("\(variant.cases) cases · \(Fmt.minutes(variant.averageCycleMinutes)) avg · \(Fmt.percent(variant.reworkRate)) rework")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bottlenecksCard(_ mined: MinedProcess) -> some View {
        Card("Bottlenecks", subtitle: "Wait, rework and handoffs by activity.", symbol: "chart.bar.xaxis") {
            VStack(spacing: 0) {
                HStack(spacing: Space.sm) {
                    Text("Activity").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Wait").frame(width: 56, alignment: .trailing)
                    Text("Rework").frame(width: 56, alignment: .trailing)
                    Text("Fit").frame(width: 44, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xs)

                ForEach(Array(mined.activities.sorted { $0.averageWaitMinutes > $1.averageWaitMinutes }.prefix(7))) { activity in
                    HStack(spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.name).font(.subheadline).lineLimit(1)
                            Text(activity.resources.prefix(2).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.minutes(activity.averageWaitMinutes))
                            .font(.caption.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                        Text("\(activity.reworkCount)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                        Text(Fmt.percent(activity.automationScore))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(activity.automationScore >= 0.55 ? .green : .secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    if activity.id != mined.activities.sorted(by: { $0.averageWaitMinutes > $1.averageWaitMinutes }).prefix(7).last?.id {
                        RowDivider()
                    }
                }
            }
        }
        .frame(width: 420)
    }

    private func conformanceCard(_ dataset: DatasetRecord) -> some View {
        Card("Conformance", subtitle: "Compare the log with a documented standard path.", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Text("Reference").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        ForEach(processes.filter { process in
                            !steps.filter { $0.processID == process.id }.isEmpty
                        }) { process in
                            Button(process.name) { referenceProcessID = process.id }
                        }
                    } label: {
                        Text(processes.first { $0.id == referenceProcessID }?.name ?? "Choose a process")
                            .font(.subheadline)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    if let conformance {
                        Chip(text: "\(Fmt.percent(conformance.fitness)) fit",
                             symbol: "checkmark.seal",
                             tint: conformance.fitness > 0.85 ? .green : .orange)
                    }
                }

                if let conformance {
                    Meter(label: "Sequence coverage", value: conformance.fitness * 100,
                          tint: conformance.fitness > 0.85 ? .green : .orange)
                    Text("\(conformance.exactCases) of \(conformance.totalCases) cases follow the reference exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !conformance.missingActivities.isEmpty {
                        HStack(spacing: Space.xs) {
                            Text("Missing").font(.caption).foregroundStyle(.secondary)
                            ForEach(conformance.missingActivities.prefix(4), id: \.self) { activity in
                                Chip(text: activity, tint: .red)
                            }
                        }
                    }
                    if !conformance.extraActivities.isEmpty {
                        HStack(spacing: Space.xs) {
                            Text("Extra").font(.caption).foregroundStyle(.secondary)
                            ForEach(conformance.extraActivities.prefix(4), id: \.self) { activity in
                                Chip(text: activity, tint: .orange)
                            }
                        }
                    }
                } else {
                    Text("Choose a process with steps to compare.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GuardrailNote(text: "Fitness is sequence coverage, not a quality score. A deviation can be a local improvement; a human decides.")
            }
        }
    }

    // MARK: Task capture

    @ViewBuilder
    private var captureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                captureHeader
                if capture.isRunning {
                    liveCapture
                } else {
                    startCapture
                }
                sessionHistory
            }
            .padding(Space.margin)
            .frame(maxWidth: 940, alignment: .leading)
        }
    }

    private var captureHeader: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Task capture").font(.title2.weight(.semibold))
                Spacer()
                Chip(text: "Local only", symbol: "lock.shield", tint: .green)
            }
            Text("Samples the frontmost app every two seconds and aggregates minutes and switches. No window titles, keystrokes, clipboard, screenshots or names. Stop at any time; nothing leaves this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startCapture: some View {
        Card("Start a capture", subtitle: "Use it on your own Mac, for a task you choose.", symbol: "record.circle") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.md) {
                    TextField("Session name", text: $captureName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    TextField("Role", text: $captureRole)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    TextField("Site", text: $captureSite)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }
                HStack(spacing: Space.md) {
                    Button {
                        capture.start()
                    } label: {
                        Label("Start capture", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("The app must be frontmost to keep sampling. It records only the app name, never what is in it.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var liveCapture: some View {
        Card("Capturing", subtitle: "No content is recorded — only app name, minutes and switches.", symbol: "record.circle") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.md) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(since: capture.startedAt, now: context.date))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    Spacer()
                    Text("\(capture.switches) switches · \(String(format: "%.0f", capture.activeMinutes)) active min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Stop and save") {
                        stopCapture()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider().opacity(0.6)
                ForEach(capture.apps.values.sorted { $0.minutes > $1.minutes }) { app in
                    HStack(spacing: Space.sm) {
                        Image(systemName: "app").foregroundStyle(.secondary)
                        Text(app.name).font(.subheadline)
                        Spacer()
                        Text("\(String(format: "%.1f", app.minutes)) min")
                            .font(.caption.monospacedDigit())
                        Text("\(app.switches) switches")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                if capture.apps.isEmpty {
                    Text("Waiting for the first sample…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sessionHistory: some View {
        Card("Capture sessions", subtitle: "Aggregates from this Mac; use one as a task-mining process.", symbol: "clock.arrow.circlepath") {
            if sessions.isEmpty {
                Text("No capture yet. Start one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(6)) { session in
                        let apps = captureApps.filter { $0.sessionID == session.id }.sorted { $0.minutes > $1.minutes }
                        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.subheadline.weight(.medium))
                                Text("\(Fmt.day(session.startedAt)) · \(String(format: "%.0f", session.activeMinutes)) min · \(session.switchCount) switches · \(apps.count) apps")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Create process") {
                                model.createProcess(from: session, apps: apps)
                            }
                            .controlSize(.small)
                            .disabled(apps.isEmpty)
                        }
                        .padding(.vertical, Space.sm)
                        if session.id != sessions.prefix(6).last?.id { RowDivider() }
                    }
                }
            }
        }
    }

    private func stopCapture() {
        guard let result = capture.stop() else { return }
        model.recordCapture(name: captureName.isEmpty ? "Desktop work" : captureName,
                            role: captureRole, site: captureSite,
                            startedAt: result.startedAt, endedAt: result.endedAt,
                            minutes: result.activeMinutes, idleMinutes: result.idleMinutes,
                            switchCount: result.switches,
                            apps: result.apps.map { ($0.name, $0.bundleID, $0.minutes, $0.idleMinutes, $0.switches) })
        capture.reset()
    }

    private func elapsed(since start: Date?, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start ?? now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                pendingCSV = PendingCSV(
                    name: url.deletingPathExtension().lastPathComponent,
                    filename: url.lastPathComponent,
                    text: text)
            } catch {
                importError = error.localizedDescription
                model.showToast("Import failed", detail: error.localizedDescription,
                                symbol: "exclamationmark.triangle", warning: true)
            }
        }
    }
}


struct PendingCSV: Identifiable {
    let id = UUID()
    var name: String
    var filename: String
    var text: String
}

private struct MiningImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var file: PendingCSV

    @State private var name: String
    @State private var site = ""
    @State private var caseColumn: String
    @State private var activityColumn: String
    @State private var timestampColumn: String
    @State private var resourceColumn: String
    @State private var applicationColumn: String
    @State private var error: String?

    private let headers: [String]
    private let preview: [String]

    init(file: PendingCSV) {
        self.file = file
        let headers = EventLogImporter.headers(in: file.text)
        self.headers = headers
        self.preview = file.text.split(whereSeparator: \.isNewline).prefix(4).map(String.init)
        func find(_ names: [String], fallback: String) -> String {
            for name in names {
                if let match = headers.first(where: { $0.lowercased() == name }) { return match }
            }
            return headers.first(where: { $0.lowercased().contains(names[0]) }) ?? fallback
        }
        _name = State(initialValue: file.name)
        _caseColumn = State(initialValue: find(["case_id", "case", "caseid"], fallback: headers.first ?? ""))
        _activityColumn = State(initialValue: find(["activity", "task", "step"], fallback: headers.dropFirst().first ?? ""))
        _timestampColumn = State(initialValue: find(["timestamp", "time", "datetime"], fallback: headers.dropFirst(2).first ?? ""))
        _resourceColumn = State(initialValue: find(["resource", "role", "user"], fallback: headers.dropFirst(3).first ?? ""))
        _applicationColumn = State(initialValue: find(["application", "app", "system"], fallback: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map the event log").font(.title3.weight(.semibold))
                    Text("\(headers.count) columns · \(file.filename)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
                row("Name", TextField("Dataset name", text: $name).textFieldStyle(.roundedBorder))
                row("Site", TextField("Optional site", text: $site).textFieldStyle(.roundedBorder))
                row("Case id", picker($caseColumn))
                row("Activity", picker($activityColumn))
                row("Timestamp", picker($timestampColumn))
                row("Resource", picker($resourceColumn))
                row("Application", picker($applicationColumn, optional: true))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(preview.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(Space.sm)
                }
                .frame(height: 72)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            GuardrailNote(text: "Case ids are hashed, role values are sanitised, activity and attribute text is PII-masked. Extra columns become filterable dimensions; a cost column is parsed as a number.")

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Import \(file.name)") {
                    let mapping = MiningColumnMap(
                        caseID: caseColumn, activity: activityColumn,
                        timestamp: timestampColumn, resource: resourceColumn,
                        application: applicationColumn.isEmpty ? nil : applicationColumn)
                    do {
                        _ = try model.importCSV(text: file.text, name: name, filename: file.filename,
                                                site: site, mapping: mapping)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || caseColumn.isEmpty || activityColumn.isEmpty
                          || timestampColumn.isEmpty || resourceColumn.isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 680, height: 560)
    }

    private func row<Content: View>(_ label: String, _ content: Content) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
        }
    }

    private func picker(_ selection: Binding<String>, optional: Bool = false) -> some View {
        Picker("", selection: selection) {
            if optional { Text("None").tag("") }
            ForEach(headers, id: \.self) { header in Text(header).tag(header) }
        }
        .labelsHidden()
    }
}

import AppKit
import Carbon.HIToolbox
import ProcessLinkKit
import SwiftUI

// MARK: - Global shortcut

extension Notification.Name {
    nonisolated static let processLinkHotKey = Notification.Name("processLinkHotKey")
}

/// Option-Command-P from anywhere, no permission required (Carbon hot key,
/// the same API Spotlight-style utilities use).
@MainActor
enum GlobalHotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?

    static func install() {
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052_4C4B), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), processLinkHotKeyHandler,
                            1, &spec, nil, &handlerRef)
    }
}

/// A C callback: it may only post. The notification is observed on the main
/// actor by ContentView, which opens the panel.
private nonisolated func processLinkHotKeyHandler(_ call: EventHandlerCallRef?,
                                                  _ event: EventRef?,
                                                  _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: .processLinkHotKey, object: nil)
    return noErr
}

// MARK: - Quick ask panel

/// A non-activating panel: Option-Command-P from another app and you can type
/// without switching Spaces or losing the window you were in.
@MainActor
final class QuickAskController {
    static let shared = QuickAskController()

    private var panel: NSPanel?

    func toggle(model: AppModel) {
        if let panel, panel.isVisible {
            close()
        } else {
            show(model: model)
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func show(model: AppModel) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 220),
                                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.contentView = NSHostingView(rootView: QuickAskView(model: model))
            self.panel = panel
        }
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }
}

/// One input, one answer, Escape closes. This is the app's quick-capture
/// entry point, so focusing the field on open is deliberate.
struct QuickAskView: View {
    var model: AppModel
    @State private var query = ""
    @State private var answer: AskAnswer?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Palette.accentText)
                    .accessibilityHidden(true)
                Text("Ask ProcessLink")
                    .font(.headline)
                Spacer()
                Chip(text: "Local", symbol: "cpu", tint: .green)
                Button {
                    QuickAskController.shared.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close (Escape)")
                .accessibilityLabel("Close")
            }

            HStack(spacing: Space.sm) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Where does rework concentrate?", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(run)
                Button(action: run) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Ask")
            }
            .padding(Space.md)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }

            if let answer {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(answer.headline).font(.subheadline.weight(.semibold))
                    Text(answer.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.xs) {
                        ForEach(answer.citations.prefix(3)) { citation in
                            Chip(text: citation.label, symbol: "link", tint: .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Answers cite discovery objects and KG nodes. Press Return to ask · Escape to close.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .frame(width: 540, height: 220, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { focused = true }
        .onExitCommand { QuickAskController.shared.close() }
    }

    private func run() {
        guard let result = model.quickAnswer(query) else { return }
        answer = result
        query = ""
    }
}

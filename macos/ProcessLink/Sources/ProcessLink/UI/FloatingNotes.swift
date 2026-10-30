import ProcessLinkKit
import SwiftData
import SwiftUI

struct FloatingNotes: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \PageNoteRecord.createdAt, order: .reverse) private var notes: [PageNoteRecord]
    @State private var showing = false

    private var current: [PageNoteRecord] {
        notes.filter { $0.pageRaw == (model.page?.rawValue ?? "unknown") }
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                if !current.isEmpty {
                    Text("\(current.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 4, y: -4) // grid: ok badge
                }
            }
        }
        .buttonStyle(.plain)
        .help("Notes on this page (local)")
        .sheet(isPresented: $showing) { NoteSheet() }
    }
}

private struct NoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PageNoteRecord.createdAt, order: .reverse) private var notes: [PageNoteRecord]
    @State private var draft = ""

    private var page: String { model.page?.rawValue ?? "unknown" }
    private var current: [PageNoteRecord] { notes.filter { $0.pageRaw == page } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Notes · \(page)").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Local only. Notes stay in the ProcessLink store.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if current.isEmpty {
                        Text("No notes on this page.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(current) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.body).font(.caption)
                            HStack {
                                Text("\(note.author) · \(Fmt.ago(note.createdAt))").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                Button("Delete") {
                                    model.context.delete(note)
                                    try? model.context.save()
                                }
                                .controlSize(.mini)
                            }
                        }
                        .padding(Space.sm)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 120)
            TextField("Write a note for this page…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button("Save note") {
                    let note = PageNoteRecord(id: "note-\(UUID().uuidString.prefix(8))",
                                              page: page, body: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                                              author: "CI Manager (role)")
                    model.context.insert(note)
                    try? model.context.save()
                    draft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 420, height: 420)
    }
}

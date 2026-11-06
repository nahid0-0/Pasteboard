import Foundation
import Combine

class NoteManager: ObservableObject {
    @Published var notes: [Note] = []

    private let saveURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Pasteboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("notes.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    // MARK: - CRUD

    /// Auto-number new notes as "Note 1", "Note 2", etc.
    private func nextAutoTitle(for type: NoteContent) -> String {
        let prefix = type.typeName + " Note"
        var idx = 1
        let existing = Set(notes.map { $0.title })
        while existing.contains("\(prefix) \(idx)") { idx += 1 }
        return "\(prefix) \(idx)"
    }

    func addNote(title: String = "", type: NoteContent) {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nextAutoTitle(for: type)
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note(title: finalTitle, content: type)
        notes.insert(note, at: 0)
        save()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Pin / unpin a note (pinned notes are listed first). Doesn't bump modifiedAt.
    func togglePin(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isPinned.toggle()
        save()
    }

    func updateContent(id: UUID, content: NoteContent) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].content = content
        notes[idx].modifiedAt = Date()
        save()
    }

    func updateTitle(id: UUID, title: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
        notes[idx].modifiedAt = Date()
        save()
    }

    // MARK: - Form helpers

    func addFormItem(to noteID: UUID, value: String = "", label: String = "", imageData: Data? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              case .form(var items) = notes[idx].content else { return }
        items.append(FormItem(value: value, label: label, imageData: imageData))
        notes[idx].content = .form(items)
        notes[idx].modifiedAt = Date()
        save()
    }

    func deleteFormItem(from noteID: UUID, itemID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              case .form(var items) = notes[idx].content else { return }
        items.removeAll { $0.id == itemID }
        notes[idx].content = .form(items)
        notes[idx].modifiedAt = Date()
        save()
    }

    func updateFormItem(in noteID: UUID, itemID: UUID, value: String, label: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              case .form(var items) = notes[idx].content,
              let itemIdx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[itemIdx].value = value
        items[itemIdx].label = label
        notes[idx].content = .form(items)
        notes[idx].modifiedAt = Date()
        save()
    }

    func updateFormItemImage(in noteID: UUID, itemID: UUID, imageData: Data?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              case .form(var items) = notes[idx].content,
              let itemIdx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[itemIdx].imageData = imageData
        notes[idx].content = .form(items)
        notes[idx].modifiedAt = Date()
        save()
    }
}

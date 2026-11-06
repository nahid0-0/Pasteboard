import Foundation

// MARK: - Form Item

struct FormItem: Identifiable, Codable, Equatable {
    var id: UUID
    var value: String        // The text that gets copied (e.g. "John Doe") — unused when imageData is set
    var label: String        // Optional display label (e.g. "Full Name") — may be empty
    var imageData: Data?     // When present, this field holds an image instead of text

    init(id: UUID = UUID(), value: String, label: String = "", imageData: Data? = nil) {
        self.id = id
        self.value = value
        self.label = label
        self.imageData = imageData
    }
}

// MARK: - Note Content

enum NoteContent: Codable, Equatable {
    case plainText(String)
    case form([FormItem])
    case image(Data)

    // Custom Codable because Swift enums with associated values need it
    private enum CodingKeys: String, CodingKey {
        case type, text, items, imageData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plainText(let text):
            try container.encode("plainText", forKey: .type)
            try container.encode(text, forKey: .text)
        case .form(let items):
            try container.encode("form", forKey: .type)
            try container.encode(items, forKey: .items)
        case .image(let data):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .imageData)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "form":
            let items = try container.decode([FormItem].self, forKey: .items)
            self = .form(items)
        case "image":
            let data = try container.decodeIfPresent(Data.self, forKey: .imageData) ?? Data()
            self = .image(data)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .plainText(text)
        }
    }

    var typeName: String {
        switch self {
        case .plainText: return "Text"
        case .form:      return "Form"
        case .image:     return "Image"
        }
    }

    var typeIcon: String {
        switch self {
        case .plainText: return "doc.text"
        case .form:      return "list.bullet.clipboard"
        case .image:     return "photo"
        }
    }
}

// MARK: - Note

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: NoteContent
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool

    init(id: UUID = UUID(),
         title: String,
         content: NoteContent,
         createdAt: Date = Date(),
         modifiedAt: Date = Date(),
         isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
    }

    // Custom decoding so notes saved before `isPinned` existed still load
    private enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt, modifiedAt, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(NoteContent.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// A brief one-line preview string shown in the card
    var preview: String {
        switch content {
        case .plainText(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                       .components(separatedBy: .newlines).first ?? ""
        case .form(let items):
            return items.map { $0.imageData != nil ? "🖼 Image" : $0.value }.joined(separator: " · ")
        case .image:
            return "Image"
        }
    }
}

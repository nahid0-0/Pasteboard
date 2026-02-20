import Foundation
import AppKit
import UniformTypeIdentifiers

// Data type classification
enum ClipDataType: String {
    case plainText = "Plain Text"
    case url = "URL"
    case image = "Image"
    case file = "File"
}

// Static cache for app icons to avoid repeated filesystem lookups
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]
    
    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        cache[bundleID] = icon
        return icon
    }
}

// Static cache for file type icons
final class FileIconCache {
    static let shared = FileIconCache()
    private var cache: [String: NSImage] = [:]
    
    func icon(for fileExtension: String) -> NSImage {
        if let cached = cache[fileExtension] {
            return cached
        }
        let icon: NSImage
        if let utType = UTType(filenameExtension: fileExtension) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        cache[fileExtension] = icon
        return icon
    }
}

// Protocol for all clip types
protocol ClipItem: Identifiable, Equatable {
    var id: UUID { get }
    var createdAt: Date { get }
    var isPinned: Bool { get set }
    var sourceAppName: String? { get }
    var sourceAppBundleID: String? { get }
}

// Text clip model
struct TextClip: ClipItem {
    let id: UUID
    let createdAt: Date
    var isPinned: Bool
    let text: String
    let sourceAppName: String?
    let sourceAppBundleID: String?
    
    var isURL: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    init(text: String, sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.text = text
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
    }
    
    static func == (lhs: TextClip, rhs: TextClip) -> Bool {
        lhs.id == rhs.id
    }
}

// Image clip model
struct ImageClip: ClipItem {
    let id: UUID
    let createdAt: Date
    var isPinned: Bool
    let imageData: Data
    let width: Int
    let height: Int
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let originalFileName: String?
    
    // Cached at creation time
    let cachedThumbnail: NSImage?
    private var _cachedFullImage: NSImage?
    
    init?(imageData: Data, maxSize: Int = 10_000_000, sourceAppName: String? = nil, sourceAppBundleID: String? = nil, originalFileName: String? = nil) {
        guard imageData.count <= maxSize else { return nil }
        
        guard let nsImage = NSImage(data: imageData) else { return nil }
        guard let representation = nsImage.representations.first else { return nil }
        
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.imageData = imageData
        self.width = representation.pixelsWide
        self.height = representation.pixelsHigh
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.originalFileName = originalFileName
        
        self.cachedThumbnail = ImageClip.generateThumbnail(from: nsImage, size: CGSize(width: 64, height: 64))
        self._cachedFullImage = nsImage
    }
    
    /// Display name: filename if available, otherwise dimensions
    var displayName: String {
        if let name = originalFileName {
            return name
        }
        return "\(width) x \(height)"
    }
    
    private static func generateThumbnail(from original: NSImage, size: CGSize) -> NSImage? {
        let originalSize = original.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }
        let aspectRatio = originalSize.width / originalSize.height
        
        let targetSize: CGSize
        if aspectRatio > 1 {
            targetSize = CGSize(width: size.width, height: size.width / aspectRatio)
        } else {
            targetSize = CGSize(width: size.height * aspectRatio, height: size.height)
        }
        
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: targetSize),
                     from: NSRect(origin: .zero, size: originalSize),
                     operation: .copy,
                     fraction: 1.0)
        thumbnail.unlockFocus()
        
        return thumbnail
    }
    
    func thumbnail() -> NSImage? {
        return cachedThumbnail
    }
    
    func fullImage() -> NSImage? {
        return _cachedFullImage ?? NSImage(data: imageData)
    }
    
    static func == (lhs: ImageClip, rhs: ImageClip) -> Bool {
        lhs.id == rhs.id
    }
}

// File clip model - stores reference to file, not contents
struct FileClip: ClipItem {
    let id: UUID
    let createdAt: Date
    var isPinned: Bool
    let filePath: String
    let fileName: String
    let fileExtension: String
    let fileSize: Int64
    let sourceAppName: String?
    let sourceAppBundleID: String?
    
    // Cached file icon
    let cachedFileIcon: NSImage
    
    init?(url: URL, sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.filePath = url.path
        self.fileName = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.fileSize = (attributes?[.size] as? Int64) ?? 0
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.cachedFileIcon = FileIconCache.shared.icon(for: url.pathExtension)
    }
    
    static func == (lhs: FileClip, rhs: FileClip) -> Bool {
        lhs.id == rhs.id
    }
}

// Unified container for all types
enum ClipType: Identifiable, Equatable {
    case text(TextClip)
    case image(ImageClip)
    case file(FileClip)
    
    var id: UUID {
        switch self {
        case .text(let clip): return clip.id
        case .image(let clip): return clip.id
        case .file(let clip): return clip.id
        }
    }
    
    var createdAt: Date {
        switch self {
        case .text(let clip): return clip.createdAt
        case .image(let clip): return clip.createdAt
        case .file(let clip): return clip.createdAt
        }
    }
    
    var isPinned: Bool {
        get {
            switch self {
            case .text(let clip): return clip.isPinned
            case .image(let clip): return clip.isPinned
            case .file(let clip): return clip.isPinned
            }
        }
        set {
            switch self {
            case .text(var clip):
                clip.isPinned = newValue
                self = .text(clip)
            case .image(var clip):
                clip.isPinned = newValue
                self = .image(clip)
            case .file(var clip):
                clip.isPinned = newValue
                self = .file(clip)
            }
        }
    }
    
    var sourceAppName: String? {
        switch self {
        case .text(let clip): return clip.sourceAppName
        case .image(let clip): return clip.sourceAppName
        case .file(let clip): return clip.sourceAppName
        }
    }
    
    var sourceAppBundleID: String? {
        switch self {
        case .text(let clip): return clip.sourceAppBundleID
        case .image(let clip): return clip.sourceAppBundleID
        case .file(let clip): return clip.sourceAppBundleID
        }
    }
    
    var dataType: ClipDataType {
        switch self {
        case .text(let clip):
            return clip.isURL ? .url : .plainText
        case .image:
            return .image
        case .file:
            return .file
        }
    }
    
    var dataSize: Int {
        switch self {
        case .text(let clip): return clip.text.utf8.count
        case .image(let clip): return clip.imageData.count
        case .file(let clip): return Int(clip.fileSize)
        }
    }
    
    var sourceAppIcon: NSImage? {
        guard let bundleID = sourceAppBundleID else { return nil }
        return AppIconCache.shared.icon(for: bundleID)
    }
    
    static func == (lhs: ClipType, rhs: ClipType) -> Bool {
        lhs.id == rhs.id
    }
}

import Foundation
import AppKit
import UniformTypeIdentifiers

// Data type classification
enum ClipDataType: String {
    case plainText = "Plain Text"
    case url = "URL"
    case image = "Image"
    case file = "File"
    case stack = "Stack"
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
    
    /// Display name: filename if available, source app name if from web, otherwise dimensions
    var displayName: String {
        if let name = originalFileName {
            return name
        }
        if let appName = sourceAppName {
            return appName
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

// File clip model - stores reference to file(s), not contents
struct FileClip: ClipItem {
    let id: UUID
    let createdAt: Date
    var isPinned: Bool
    let filePaths: [String]
    let fileNames: [String]
    let fileExtensions: [String]
    let totalFileSize: Int64
    let sourceAppName: String?
    let sourceAppBundleID: String?
    
    // Cached file icons (one per file)
    let cachedFileIcons: [NSImage]
    
    // Convenience: number of files
    var fileCount: Int { filePaths.count }
    var isSingleFile: Bool { filePaths.count == 1 }
    
    // Backward-compatible convenience properties
    var fileName: String {
        if isSingleFile { return fileNames.first ?? "Unknown" }
        return "\(fileCount) files"
    }
    var filePath: String { filePaths.first ?? "" }
    var fileExtension: String { fileExtensions.first ?? "" }
    var cachedFileIcon: NSImage { cachedFileIcons.first ?? NSWorkspace.shared.icon(for: .data) }
    
    // Single-file init (backward compatible)
    init?(url: URL, sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.filePaths = [url.path]
        self.fileNames = [url.lastPathComponent]
        self.fileExtensions = [url.pathExtension.lowercased()]
        self.totalFileSize = (attributes?[.size] as? Int64) ?? 0
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.cachedFileIcons = [FileIconCache.shared.icon(for: url.pathExtension)]
    }
    
    // Multi-file init
    init?(urls: [URL], sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else { return nil }
        
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.filePaths = validURLs.map { $0.path }
        self.fileNames = validURLs.map { $0.lastPathComponent }
        self.fileExtensions = validURLs.map { $0.pathExtension.lowercased() }
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.cachedFileIcons = validURLs.map { FileIconCache.shared.icon(for: $0.pathExtension) }
        
        var total: Int64 = 0
        for url in validURLs {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            total += (attrs?[.size] as? Int64) ?? 0
        }
        self.totalFileSize = total
    }
    
    static func == (lhs: FileClip, rhs: FileClip) -> Bool {
        lhs.id == rhs.id
    }
}

// Stack set model — groups multiple clips into a single item
struct StackSet: ClipItem {
    let id: UUID
    let createdAt: Date
    var isPinned: Bool
    var items: [ClipType]
    var isAccepting: Bool  // true = actively stacking, false = finalized
    
    var sourceAppName: String? {
        items.first?.sourceAppName
    }
    var sourceAppBundleID: String? {
        items.first?.sourceAppBundleID
    }
    
    init(items: [ClipType] = [], isAccepting: Bool = true) {
        self.id = UUID()
        self.createdAt = Date()
        self.isPinned = false
        self.items = items
        self.isAccepting = isAccepting
    }
    
    var itemCount: Int { items.count }
    
    /// Combined text of all text items, joined by newlines
    var combinedText: String {
        items.compactMap { item -> String? in
            if case .text(let t) = item { return t.text }
            return nil
        }.joined(separator: "\n")
    }
    
    /// All file paths from file items
    var allFilePaths: [String] {
        items.flatMap { item -> [String] in
            if case .file(let f) = item { return f.filePaths }
            return []
        }
    }
    
    /// First image clip if any
    var firstImageClip: ImageClip? {
        for item in items {
            if case .image(let img) = item { return img }
        }
        return nil
    }
    
    static func == (lhs: StackSet, rhs: StackSet) -> Bool {
        lhs.id == rhs.id
    }
}

// Unified container for all types
enum ClipType: Identifiable, Equatable {
    case text(TextClip)
    case image(ImageClip)
    case file(FileClip)
    case stack(StackSet)
    
    var id: UUID {
        switch self {
        case .text(let clip): return clip.id
        case .image(let clip): return clip.id
        case .file(let clip): return clip.id
        case .stack(let set): return set.id
        }
    }
    
    var createdAt: Date {
        switch self {
        case .text(let clip): return clip.createdAt
        case .image(let clip): return clip.createdAt
        case .file(let clip): return clip.createdAt
        case .stack(let set): return set.createdAt
        }
    }
    
    var isPinned: Bool {
        get {
            switch self {
            case .text(let clip): return clip.isPinned
            case .image(let clip): return clip.isPinned
            case .file(let clip): return clip.isPinned
            case .stack(let set): return set.isPinned
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
            case .stack(var set):
                set.isPinned = newValue
                self = .stack(set)
            }
        }
    }
    
    var sourceAppName: String? {
        switch self {
        case .text(let clip): return clip.sourceAppName
        case .image(let clip): return clip.sourceAppName
        case .file(let clip): return clip.sourceAppName
        case .stack(let set): return set.sourceAppName
        }
    }
    
    var sourceAppBundleID: String? {
        switch self {
        case .text(let clip): return clip.sourceAppBundleID
        case .image(let clip): return clip.sourceAppBundleID
        case .file(let clip): return clip.sourceAppBundleID
        case .stack(let set): return set.sourceAppBundleID
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
        case .stack:
            return .stack
        }
    }
    
    var dataSize: Int {
        switch self {
        case .text(let clip): return clip.text.utf8.count
        case .image(let clip): return clip.imageData.count
        case .file(let clip): return Int(clip.totalFileSize)
        case .stack(let set): return set.items.reduce(0) { $0 + $1.dataSize }
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

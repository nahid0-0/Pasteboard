import Foundation
import AppKit
import Combine

class ClipboardManager: ObservableObject {
    @Published var clips: [ClipType] = []
    
    private var lastChangeCount: Int
    private var timer: Timer?
    private var lastCapturedText: String?
    private var lastCapturedImageData: Data?
    private var screenshotWatcher: ScreenshotWatcher?
    private var settingsObserver: AnyCancellable?
    private var ignoreNextClipboardChange: Bool = false
    
    // Get the frontmost app info at capture time
    private var frontmostAppInfo: (name: String?, bundleID: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }
    
    // Configuration
    private let maxTotalItems = 55
    private let maxUnpinnedItems = 50
    private let maxPinnedItems = 5
    private let pollInterval: TimeInterval = 0.5
    
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // Start clipboard monitoring
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        screenshotWatcher?.stopWatching()
    }
    
    // Start/stop screenshot watching based on settings
    func configureScreenshotWatcher(enabled: Bool) {
        if enabled {
            if screenshotWatcher == nil {
                screenshotWatcher = ScreenshotWatcher()
                screenshotWatcher?.startWatching { [weak self] imageData in
                    self?.captureScreenshot(imageData)
                }
            }
        } else {
            screenshotWatcher?.stopWatching()
            screenshotWatcher = nil
        }
    }
    
    // Capture screenshot from file
    private func captureScreenshot(_ imageData: Data) {
        // Avoid duplicates - check if same image data recently captured
        guard imageData != lastCapturedImageData else { return }
        lastCapturedImageData = imageData
        lastCapturedText = nil
        
        // Ignore the next clipboard change since we're about to copy the screenshot
        ignoreNextClipboardChange = true
        
        let appInfo = frontmostAppInfo
        guard let imageClip = ImageClip(imageData: imageData, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID) else {
            print("Failed to create image clip from screenshot")
            return
        }
        
        DispatchQueue.main.async {
            self.clips.insert(.image(imageClip), at: 0)
            self.enforceCapacity()
        }
    }
    
    // Check for clipboard changes
    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Skip if this change was triggered by screenshot watcher
        if ignoreNextClipboardChange {
            ignoreNextClipboardChange = false
            return
        }
        
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp", "heic"]
        
        // Check for file URLs first — read ALL pasteboard items
        if types.contains(.fileURL) {
            let items = pasteboard.pasteboardItems ?? []
            var fileURLs: [URL] = []
            for item in items {
                if let urlString = item.string(forType: .fileURL),
                   let url = URL(string: urlString) {
                    fileURLs.append(url)
                }
            }
            
            if fileURLs.count == 1, let url = fileURLs.first {
                // Single file — existing behavior (check if image)
                let ext = url.pathExtension.lowercased()
                if imageExtensions.contains(ext),
                   let imageData = try? Data(contentsOf: url) {
                    captureImage(imageData, originalFileName: url.lastPathComponent)
                    return
                } else {
                    captureFile(url: url)
                    return
                }
            } else if fileURLs.count > 1 {
                // Multiple files — capture as grouped clip
                captureFiles(urls: fileURLs)
                return
            }
        }
        
        // Try to capture image data (e.g. copied from apps, no file URL)
        if types.contains(.tiff) || types.contains(.png) {
            if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
                captureImage(imageData)
                return
            }
        }
        
        // Fall back to text
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            captureText(string)
            return
        }
    }
    
    // Capture text clip
    private func captureText(_ text: String) {
        // Deduplicate consecutive identical text
        guard text != lastCapturedText else { return }
        lastCapturedText = text
        lastCapturedImageData = nil
        
        let appInfo = frontmostAppInfo
        let newClip = TextClip(text: text, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID)
        
        DispatchQueue.main.async {
            self.clips.insert(.text(newClip), at: 0)
            self.enforceCapacity()
        }
    }
    
    // Capture image clip
    private func captureImage(_ imageData: Data, originalFileName: String? = nil) {
        // Deduplicate consecutive identical images (basic comparison)
        guard imageData != lastCapturedImageData else { return }
        lastCapturedImageData = imageData
        lastCapturedText = nil
        
        let appInfo = frontmostAppInfo
        guard let imageClip = ImageClip(imageData: imageData, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID, originalFileName: originalFileName) else {
            print("Failed to create image clip or image too large")
            return
        }
        
        DispatchQueue.main.async {
            self.clips.insert(.image(imageClip), at: 0)
            self.enforceCapacity()
        }
    }
    
    // Capture file clip (non-image files like .dmg, .zip, .pdf, etc.)
    private func captureFile(url: URL) {
        // Deduplicate by path
        let path = url.path
        guard lastCapturedText != path else { return }
        lastCapturedText = path
        lastCapturedImageData = nil
        
        let appInfo = frontmostAppInfo
        guard let fileClip = FileClip(url: url, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID) else {
            print("Failed to create file clip for: \(url.lastPathComponent)")
            return
        }
        
        DispatchQueue.main.async {
            self.clips.insert(.file(fileClip), at: 0)
            self.enforceCapacity()
        }
    }
    
    // Capture multiple files as a single grouped clip
    private func captureFiles(urls: [URL]) {
        // Deduplicate by sorted paths
        let sortedPaths = urls.map { $0.path }.sorted().joined(separator: "\n")
        guard lastCapturedText != sortedPaths else { return }
        lastCapturedText = sortedPaths
        lastCapturedImageData = nil
        
        let appInfo = frontmostAppInfo
        guard let fileClip = FileClip(urls: urls, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID) else {
            print("Failed to create multi-file clip")
            return
        }
        
        DispatchQueue.main.async {
            self.clips.insert(.file(fileClip), at: 0)
            self.enforceCapacity()
        }
    }
    
    // Enforce capacity limits (ring buffer with pin protection)
    private func enforceCapacity() {
        let pinnedCount = clips.filter { $0.isPinned }.count
        let unpinnedCount = clips.count - pinnedCount
        
        // Remove oldest unpinned items if over limit
        // Newest items are at index 0, oldest at the end — remove from the end
        if unpinnedCount > maxUnpinnedItems {
            let itemsToRemove = unpinnedCount - maxUnpinnedItems
            var removed = 0
            var indicesToRemove: [Int] = []
            
            // Iterate from the end (oldest) to find unpinned items to evict
            for i in stride(from: clips.count - 1, through: 0, by: -1) {
                if removed >= itemsToRemove { break }
                if !clips[i].isPinned {
                    indicesToRemove.append(i)
                    removed += 1
                }
            }
            
            // Remove in reverse-sorted order to keep indices valid
            for index in indicesToRemove.sorted().reversed() {
                clips.remove(at: index)
            }
        }
        
        // Hard cap on total items
        if clips.count > maxTotalItems {
            clips = Array(clips.prefix(maxTotalItems))
        }
        
        // Safeguard: limit pinned items
        if pinnedCount > maxPinnedItems {
            print("Warning: Too many pinned items (\(pinnedCount))")
        }
    }
    
    // Toggle pin status
    func togglePin(for clipID: UUID) {
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            clips[index].isPinned.toggle()
            
            // Move pinned items to top
            if clips[index].isPinned {
                let clip = clips.remove(at: index)
                let firstUnpinnedIndex = clips.firstIndex(where: { !$0.isPinned }) ?? 0
                clips.insert(clip, at: firstUnpinnedIndex)
            }
        }
    }
    
    // Delete specific clip
    func delete(clipID: UUID) {
        clips.removeAll { $0.id == clipID }
    }
    
    // Clear unpinned clips
    func clearUnpinned() {
        clips.removeAll { !$0.isPinned }
    }
    
    // Clear all clips
    func clearAll() {
        clips.removeAll()
    }
    
    // Copy clip back to clipboard
    func copyToClipboard(_ clip: ClipType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch clip {
        case .text(let textClip):
            pasteboard.setString(textClip.text, forType: .string)
            lastCapturedText = textClip.text
            lastChangeCount = pasteboard.changeCount
            
        case .image(let imageClip):
            if let image = imageClip.fullImage() {
                pasteboard.writeObjects([image])
                lastCapturedImageData = imageClip.imageData
                lastChangeCount = pasteboard.changeCount
            }
            
        case .file(let fileClip):
            let fileURLs = fileClip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(fileURLs)
            lastCapturedText = fileClip.filePaths.sorted().joined(separator: "\n")
            lastChangeCount = pasteboard.changeCount
        }
    }
    
    // Get sorted clips (pinned first)
    var sortedClips: [ClipType] {
        let pinned = clips.filter { $0.isPinned }
        let unpinned = clips.filter { !$0.isPinned }
        return pinned + unpinned
    }
}


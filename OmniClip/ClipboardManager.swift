import Foundation
import AppKit
import Combine

class ClipboardManager: ObservableObject {
    @Published var clips: [ClipType] = [] {
        didSet { _cachedSortedClips = nil }
    }
    
    // Stack mode state
    @Published var isStackMode: Bool = false
    private var activeStackID: UUID?
    
    // Cached sorted clips — invalidated when clips changes
    private var _cachedSortedClips: [ClipType]?
    
    private var lastChangeCount: Int
    private var pollTimer: DispatchSourceTimer?
    private var lastCapturedText: String?
    private var lastCapturedImageData: Data?
    private var screenshotWatcher: ScreenshotWatcher?
    private var settingsObserver: AnyCancellable?
    private var ignoreNextClipboardChange: Bool = false
    private let pollQueue = DispatchQueue(label: "com.omniclip.clipboard-poll", qos: .userInitiated)
    
    // Get the frontmost app info at capture time
    private var frontmostAppInfo: (name: String?, bundleID: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }
    
    // Configuration
    private let maxTotalItems = 55
    private let maxUnpinnedItems = 50
    private let maxPinnedItems = 5
    private let pollInterval: Double = 0.5
    
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // Start clipboard monitoring on a background queue
    func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.checkClipboard()
        }
        pollTimer = timer
        timer.resume()
    }
    
    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
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
    
    // Check for clipboard changes (runs on background pollQueue)
    private func checkClipboard() {
        // changeCount is thread-safe
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Skip if this change was triggered by screenshot watcher
        if ignoreNextClipboardChange {
            ignoreNextClipboardChange = false
            return
        }
        
        // Read pasteboard on the current background thread
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
        let clipType = ClipType.text(newClip)
        
        DispatchQueue.main.async {
            if self.appendToActiveStackIfNeeded(clipType) { return }
            self.clips.insert(clipType, at: 0)
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
        let clipType = ClipType.image(imageClip)
        
        DispatchQueue.main.async {
            if self.appendToActiveStackIfNeeded(clipType) { return }
            self.clips.insert(clipType, at: 0)
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
        let clipType = ClipType.file(fileClip)
        
        DispatchQueue.main.async {
            if self.appendToActiveStackIfNeeded(clipType) { return }
            self.clips.insert(clipType, at: 0)
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
        let clipType = ClipType.file(fileClip)
        
        DispatchQueue.main.async {
            if self.appendToActiveStackIfNeeded(clipType) { return }
            self.clips.insert(clipType, at: 0)
            self.enforceCapacity()
        }
    }
    
    // MARK: - Stack Mode
    
    /// Append a clip to the active stack set. Returns true if handled.
    private func appendToActiveStackIfNeeded(_ clip: ClipType) -> Bool {
        guard isStackMode, let stackID = activeStackID,
              let index = clips.firstIndex(where: { $0.id == stackID }),
              case .stack(var set) = clips[index], set.isAccepting else {
            return false
        }
        set.items.append(clip)
        clips[index] = .stack(set)
        return true
    }
    
    /// Toggle stack mode on/off
    func toggleStackMode() {
        if isStackMode {
            // Turn OFF — finalize the active stack
            if let stackID = activeStackID,
               let index = clips.firstIndex(where: { $0.id == stackID }),
               case .stack(var set) = clips[index] {
                set.isAccepting = false
                clips[index] = .stack(set)
            }
            activeStackID = nil
            isStackMode = false
        } else {
            // Turn ON — create a new stack set
            let newSet = StackSet()
            clips.insert(.stack(newSet), at: 0)
            activeStackID = newSet.id
            isStackMode = true
        }
    }
    
    /// Resume stacking into an existing finalized set
    func resumeStacking(setID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == setID }),
              case .stack(var set) = clips[index] else { return }
        
        // Finalize any currently active stack first
        if let currentID = activeStackID,
           let currentIndex = clips.firstIndex(where: { $0.id == currentID }),
           case .stack(var currentSet) = clips[currentIndex] {
            currentSet.isAccepting = false
            clips[currentIndex] = .stack(currentSet)
        }
        
        set.isAccepting = true
        clips[index] = .stack(set)
        activeStackID = setID
        isStackMode = true
    }
    
    // Enforce capacity limits (single-pass filter)
    private func enforceCapacity() {
        // Separate pinned and unpinned in one pass
        let pinned = clips.filter { $0.isPinned }
        var unpinned = clips.filter { !$0.isPinned }
        
        // Trim oldest unpinned (newest are at front, oldest at end)
        if unpinned.count > maxUnpinnedItems {
            unpinned = Array(unpinned.prefix(maxUnpinnedItems))
        }
        
        clips = pinned + unpinned
        
        // Hard cap
        if clips.count > maxTotalItems {
            clips = Array(clips.prefix(maxTotalItems))
        }
        
        if pinned.count > maxPinnedItems {
            print("Warning: Too many pinned items (\(pinned.count))")
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
            
        case .stack(let set):
            // Combine all items: texts joined by newline, files as URLs, images as first image
            var objects: [NSPasteboardWriting] = []
            let combinedText = set.combinedText
            if !combinedText.isEmpty {
                objects.append(combinedText as NSString)
            }
            let filePaths = set.allFilePaths
            if !filePaths.isEmpty {
                let fileURLs = filePaths.map { URL(fileURLWithPath: $0) as NSURL }
                objects.append(contentsOf: fileURLs)
            }
            if combinedText.isEmpty && filePaths.isEmpty, let imgClip = set.firstImageClip, let img = imgClip.fullImage() {
                objects.append(img)
            }
            if !objects.isEmpty {
                pasteboard.writeObjects(objects)
            }
            lastCapturedText = combinedText
            lastChangeCount = pasteboard.changeCount
        }
    }
    
    // Get sorted clips (pinned first) — cached, invalidated on clips change
    var sortedClips: [ClipType] {
        if let cached = _cachedSortedClips { return cached }
        let pinned = clips.filter { $0.isPinned }
        let unpinned = clips.filter { !$0.isPinned }
        let result = pinned + unpinned
        _cachedSortedClips = result
        return result
    }
}


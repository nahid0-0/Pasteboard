import Foundation
import AppKit
import Combine
import ApplicationServices

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
        ImageClip.purgePasteFiles()
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
                screenshotWatcher?.startWatching { [weak self] imageData, fileURL in
                    self?.captureScreenshot(imageData, fileURL: fileURL)
                }
            }
        } else {
            screenshotWatcher?.stopWatching()
            screenshotWatcher = nil
        }
    }
    
    // Capture screenshot from file (called on main thread)
    private func captureScreenshot(_ imageData: Data, fileURL: URL) {
        // Avoid duplicates - check if same image data recently captured
        guard imageData != lastCapturedImageData else { return }
        
        let appInfo = frontmostAppInfo
        guard let imageClip = ImageClip(imageData: imageData, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID, sourceFileURL: fileURL) else {
            print("Failed to create image clip from screenshot")
            return
        }
        let clipType = ClipType.image(imageClip)
        
        // In stack mode this also writes the whole stack to the pasteboard
        if appendToActiveStackIfNeeded(clipType) { return }
        
        clips.insert(clipType, at: 0)
        enforceCapacity()
        // Put the screenshot on the system clipboard (image data + file URL)
        copyToClipboard(clipType)
    }
    
    // Check for clipboard changes (runs on background pollQueue)
    private func checkClipboard() {
        // changeCount is thread-safe
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
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
                    captureImage(imageData, sourceFileURL: url)
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
    private func captureImage(_ imageData: Data, sourceFileURL: URL? = nil) {
        // Deduplicate consecutive identical images (basic comparison)
        guard imageData != lastCapturedImageData else { return }
        lastCapturedImageData = imageData
        lastCapturedText = nil
        
        let appInfo = frontmostAppInfo
        guard let imageClip = ImageClip(imageData: imageData, sourceAppName: appInfo.name, sourceAppBundleID: appInfo.bundleID, sourceFileURL: sourceFileURL) else {
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
        // Write the combined stack to the system pasteboard so Cmd+V pastes the full stack
        copyToClipboard(.stack(set))
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
                // Write the finalized stack to the system pasteboard so Cmd+V pastes it
                copyToClipboard(.stack(set))
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

    // Manually insert a plain-text clip (from the Add button)
    func insertManual(title: String, text: String) {
        let effectiveTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        let clip = TextClip(text: text, sourceAppName: effectiveTitle, sourceAppBundleID: nil)
        DispatchQueue.main.async {
            self.clips.insert(.text(clip), at: 0)
            self.enforceCapacity()
        }
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
        // Build everything up front (image encoding / temp-file writes can be slow)
        var objects: [NSPasteboardWriting] = []
        var capturedText: String?
        var capturedImageData: Data?
        
        switch clip {
        case .text(let textClip):
            objects = [textClip.text as NSString]
            capturedText = textClip.text
            
        case .image(let imageClip):
            // Image data + file URL: pastes as an image in apps, as a file in Finder
            objects = [imageClip.pasteboardItem()]
            capturedImageData = imageClip.imageData
            
        case .file(let fileClip):
            objects = fileClip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            capturedText = fileClip.filePaths.sorted().joined(separator: "\n")
            
        case .stack(let set):
            // Text-only / image-only stacks: texts joined by newline, then files as URLs, then
            // every image (data + file URL, so the whole stack pastes into Finder too)
            let combinedText = set.combinedText
            let images = set.allImageClips
            if !combinedText.isEmpty && !images.isEmpty {
                // Mixed stack: a single rich item (RTFD + HTML + plain text) with text and images
                // inline, in stack order. No separate file-URL items: when file URLs are present,
                // most apps (chat apps, browsers, editors) paste only the files and drop the text.
                objects.append(Self.richStackItem(for: set, plainText: combinedText))
            } else {
                if !combinedText.isEmpty {
                    objects.append(combinedText as NSString)
                }
                objects.append(contentsOf: set.allFilePaths.map { URL(fileURLWithPath: $0) as NSURL })
                objects.append(contentsOf: images.map { $0.pasteboardItem() })
            }
            capturedText = combinedText
            capturedImageData = set.allImageClips.last?.imageData
        }
        
        // Write + record changeCount on the poll queue so the poller never sees our own write
        let changeCount: Int = pollQueue.sync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !objects.isEmpty {
                pasteboard.writeObjects(objects)
            }
            if let text = capturedText { lastCapturedText = text }
            if let data = capturedImageData { lastCapturedImageData = data }
            lastChangeCount = pasteboard.changeCount
            return lastChangeCount
        }
        
        // Mixed stacks: many apps paste either the text or the images from one clipboard, never
        // both. Arm the stack paster so Cmd+V pastes each piece in turn instead.
        if case .stack(let set) = clip, !set.combinedText.isEmpty, !set.allImageClips.isEmpty {
            StackPaster.shared.arm(
                segments: Self.stackSegments(for: set),
                changeCount: changeCount,
                write: { [weak self] objects in self?.writeRaw(objects) },
                restore: { [weak self] in self?.copyToClipboard(.stack(set)) }
            )
        } else {
            StackPaster.shared.disarm()
        }
    }
    
    /// Write objects to the pasteboard without capturing them as a new clip
    private func writeRaw(_ objects: [NSPasteboardWriting]) {
        pollQueue.sync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(objects)
            lastChangeCount = pasteboard.changeCount
        }
    }
    
    /// The stack split into pasteable pieces, in order: consecutive texts joined, each image alone,
    /// files together. Builders, because a pasteboard item can only be written once.
    private static func stackSegments(for set: StackSet) -> [() -> [NSPasteboardWriting]] {
        var segments: [() -> [NSPasteboardWriting]] = []
        var pendingText: [String] = []
        func flushText() {
            guard !pendingText.isEmpty else { return }
            let text = pendingText.joined(separator: "\n")
            segments.append { [text as NSString] }
            pendingText = []
        }
        for item in set.items {
            switch item {
            case .text(let t):
                pendingText.append(t.text)
            case .image(let img):
                flushText()
                segments.append { [img.pasteboardItem()] }
            case .file(let f):
                flushText()
                let paths = f.filePaths
                segments.append { paths.map { URL(fileURLWithPath: $0) as NSURL } }
            default:
                break
            }
        }
        flushText()
        return segments
    }
    
    /// Rich text (RTFD + HTML) with the stack's text and images interleaved in order, plus plain text fallback
    private static func richStackItem(for set: StackSet, plainText: String) -> NSPasteboardItem {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var html = "<html><head><meta charset=\"utf-8\"></head><body>"
        var imageIndex = 0
        func escapeHTML(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        for item in set.items {
            switch item {
            case .text(let t):
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(NSAttributedString(string: t.text, attributes: [.font: font]))
                html.append("<div>\(escapeHTML(t.text).replacingOccurrences(of: "\n", with: "<br>"))</div>")
            case .image(let img):
                guard let png = img.pngData() else { continue }
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                imageIndex += 1
                let wrapper = FileWrapper(regularFileWithContents: png)
                wrapper.preferredFilename = "image\(imageIndex).png"
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                if let image = img.fullImage() { attachment.image = image }
                result.append(NSAttributedString(attachment: attachment))
                html.append("<div><img src=\"data:image/png;base64,\(png.base64EncodedString())\"></div>")
            default:
                break
            }
        }
        html.append("</body></html>")
        let pbItem = NSPasteboardItem()
        let range = NSRange(location: 0, length: result.length)
        if let rtfd = result.rtfd(from: range, documentAttributes: [:]) {
            pbItem.setData(rtfd, forType: .rtfd)
        }
        pbItem.setString(html, forType: .html)
        pbItem.setString(plainText, forType: .string)
        return pbItem
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



// MARK: - Stack Paster

/// Pastes a mixed (text + image) stack piece by piece. While such a stack is on the clipboard, a
/// Cmd+V in another app is intercepted and replaced by: put piece 1 on the clipboard, Cmd+V,
/// piece 2, Cmd+V, ... then the full stack is put back. Needs Accessibility permission; without
/// it, Cmd+V pastes the single rich-text item instead.
final class StackPaster {
    static let shared = StackPaster()
    
    private let lock = NSLock()
    private var armedChangeCount: Int?
    private var segments: [() -> [NSPasteboardWriting]] = []
    private var write: (([NSPasteboardWriting]) -> Void)?
    private var restore: (() -> Void)?
    
    private var tap: CFMachPort?
    private var isPasting = false        // main thread only
    private var promptedForAccess = false
    /// Marks Cmd+V events we post ourselves so the tap lets them through
    private static let marker: Int64 = 0x5053_5450
    private static let vKeyCode: Int64 = 9
    
    func arm(segments: [() -> [NSPasteboardWriting]], changeCount: Int,
             write: @escaping ([NSPasteboardWriting]) -> Void, restore: @escaping () -> Void) {
        lock.lock()
        armedChangeCount = changeCount
        self.segments = segments
        self.write = write
        self.restore = restore
        lock.unlock()
        DispatchQueue.main.async { self.installTapIfPossible() }
    }
    
    func disarm() {
        lock.lock()
        armedChangeCount = nil
        segments = []
        write = nil
        restore = nil
        lock.unlock()
    }
    
    private func installTapIfPossible() {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !promptedForAccess] as CFDictionary
        promptedForAccess = true
        guard AXIsProcessTrustedWithOptions(options) else { return }
        
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let paster = Unmanaged<StackPaster>.fromOpaque(refcon).takeUnretainedValue()
                return paster.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }
    
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != Self.marker,
              event.getIntegerValueField(.keyboardEventKeycode) == Self.vKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard flags == .maskCommand else { return Unmanaged.passUnretained(event) }
        
        // Swallow extra Cmd+V presses while a sequence is running
        if isPasting { return nil }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }
        
        lock.lock()
        let armed = armedChangeCount
        let segs = segments
        let write = self.write
        let restore = self.restore
        lock.unlock()
        
        guard let armed, armed == NSPasteboard.general.changeCount,
              segs.count > 1, let write, let restore,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return Unmanaged.passUnretained(event) }
        
        isPasting = true
        pasteSegment(at: 0, segs, write: write, restore: restore)
        return nil
    }
    
    private func pasteSegment(at index: Int, _ segs: [() -> [NSPasteboardWriting]],
                              write: @escaping ([NSPasteboardWriting]) -> Void, restore: @escaping () -> Void) {
        guard index < segs.count else {
            // Put the whole stack back so the next Cmd+V pastes it again
            restore()
            isPasting = false
            return
        }
        write(segs[index]())
        postCommandV()
        // Give the target app time to read the clipboard before it changes (apps read it async)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.pasteSegment(at: index + 1, segs, write: write, restore: restore)
        }
    }
    
    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(Self.vKeyCode), keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

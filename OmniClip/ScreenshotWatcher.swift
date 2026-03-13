import Foundation
import AppKit

class ScreenshotWatcher {
    private var onScreenshot: ((Data) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var watchedDirectory: String = ""
    private var knownFiles: Set<String> = []
    private var isStarted = false
    
    init() {}
    
    func startWatching(onScreenshot: @escaping (Data) -> Void) {
        guard !isStarted else { return }
        self.onScreenshot = onScreenshot
        
        // Determine screenshot directory
        watchedDirectory = screenshotDirectory()
        print("[ScreenshotWatcher] Watching directory: \(watchedDirectory)")
        
        // Snapshot current files so we only react to NEW ones
        knownFiles = currentScreenshotFiles()
        print("[ScreenshotWatcher] Found \(knownFiles.count) existing screenshots, will ignore them")
        
        // Open directory file descriptor for monitoring
        let fd = open(watchedDirectory, O_EVTONLY)
        guard fd >= 0 else {
            print("[ScreenshotWatcher] Failed to open directory for monitoring: \(watchedDirectory)")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        
        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        self.source = source
        isStarted = true
        source.resume()
        print("[ScreenshotWatcher] File system monitoring active")
    }
    
    func stopWatching() {
        source?.cancel()
        source = nil
        isStarted = false
    }
    
    // MARK: - Private
    
    /// Returns the macOS screenshot save directory (reads user preference, falls back to ~/Desktop)
    private func screenshotDirectory() -> String {
        // Check user-configured screenshot location
        if let plist = UserDefaults(suiteName: "com.apple.screencapture"),
           let location = plist.string(forKey: "location") {
            let expanded = NSString(string: location).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return NSHomeDirectory() + "/Desktop"
    }
    
    /// Returns the set of screenshot-like PNG filenames currently in the watched directory
    private func currentScreenshotFiles() -> Set<String> {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: watchedDirectory) else { return [] }
        return Set(entries.filter { isScreenshotFilename($0) })
    }
    
    /// Heuristic: macOS names screenshots "Screenshot YYYY-MM-DD at H.MM.SS (AM|PM)..."
    private func isScreenshotFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("screenshot") && (lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg"))
    }
    
    /// Called when the directory contents change
    private func handleDirectoryChange() {
        let currentFiles = currentScreenshotFiles()
        let newFiles = currentFiles.subtracting(knownFiles)
        
        guard !newFiles.isEmpty else { return }
        
        // Update known set
        knownFiles = currentFiles
        
        // Find the newest file by modification date
        var newestFile: String?
        var newestDate: Date = .distantPast
        let fm = FileManager.default
        
        for fileName in newFiles {
            let fullPath = (watchedDirectory as NSString).appendingPathComponent(fileName)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let modDate = attrs[.modificationDate] as? Date,
               modDate > newestDate {
                newestDate = modDate
                newestFile = fullPath
            }
        }
        
        guard let path = newestFile else { return }
        print("[ScreenshotWatcher] New screenshot detected: \(path)")
        
        // Small delay to ensure the file is fully written
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let url = URL(fileURLWithPath: path)
            if let imageData = try? Data(contentsOf: url),
               let image = NSImage(data: imageData) {
                print("[ScreenshotWatcher] Successfully loaded screenshot (\(imageData.count) bytes)")
                DispatchQueue.main.async {
                    // Copy to system clipboard immediately
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    
                    // Also add to our clipboard history
                    self?.onScreenshot?(imageData)
                }
            } else {
                print("[ScreenshotWatcher] Failed to read screenshot file at: \(path)")
            }
        }
    }
    
    deinit {
        stopWatching()
    }
}

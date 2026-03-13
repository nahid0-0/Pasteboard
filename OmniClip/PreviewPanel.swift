import SwiftUI
import AppKit

// MARK: - Line Number Ruler View

private class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let sv = scrollView else { return }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
        rect.fill()

        // Right-edge separator line
        (isDark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.80, alpha: 1)).setFill()
        NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let fgColor = isDark ? NSColor(white: 0.38, alpha: 1) : NSColor(white: 0.58, alpha: 1)
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fgColor]

        let inset = textView.textContainerInset.height
        let visibleRect = sv.documentVisibleRect
        let content = textView.string as NSString
        let totalGlyphs = layoutManager.numberOfGlyphs
        guard totalGlyphs > 0 else { return }

        var lineNumber = 1
        var glyphIndex = 0

        while glyphIndex < totalGlyphs {
            var effectiveRange = NSRange(location: glyphIndex, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let charRange = layoutManager.characterRange(forGlyphRange: effectiveRange, actualGlyphRange: nil)

            // Only draw a number for hard line starts (first line, or line after \n)
            let isHardStart = charRange.location == 0 ||
                (charRange.location > 0 && content.character(at: charRange.location - 1) == 10)

            if isHardStart {
                let yInRuler = inset + lineRect.origin.y - visibleRect.origin.y
                if yInRuler > rect.maxY { break }

                if yInRuler + lineRect.height > rect.minY {
                    let label = "\(lineNumber)" as NSString
                    let labelSize = label.size(withAttributes: attrs)
                    let x = ruleThickness - labelSize.width - 5
                    let y = yInRuler + (lineRect.height - labelSize.height) / 2
                    label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                }
                lineNumber += 1
            }

            if effectiveRange.length == 0 { break }
            glyphIndex = NSMaxRange(effectiveRange)
        }
    }
}

// MARK: - Scrollable Text View

// Virtualized text view with optional syntax highlighting
private struct ScrollableTextView: NSViewRepresentable {
    let text: String
    let syntaxHighlighting: Bool
    let showLineNumbers: Bool
    
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var scrollObserver: NSObjectProtocol?
        deinit {
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        // Set up line number ruler
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers && looksLikeCode(text)

        // Redraw ruler whenever the user scrolls
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak ruler] _ in
            ruler?.needsDisplay = true
        }
        
        applyText(to: textView)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView {
            if textView.string != text {
                applyText(to: textView)
                textView.scrollToBeginningOfDocument(nil)
            }
        }
        let shouldShow = showLineNumbers && looksLikeCode(text)
        if scrollView.rulersVisible != shouldShow {
            scrollView.rulersVisible = shouldShow
        }
        scrollView.verticalRulerView?.needsDisplay = true
    }
    
    private func applyText(to textView: NSTextView) {
        if syntaxHighlighting && looksLikeCode(text) {
            let attributed = SyntaxHighlighter.highlight(text)
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = text
            textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = NSColor.labelColor
        }
    }
    
    private func looksLikeCode(_ text: String) -> Bool {
        let codeIndicators = [
            "func ", "class ", "struct ", "enum ", "import ",   // Swift
            "def ", "if __name__", "print(",                     // Python
            "function ", "const ", "let ", "var ",               // JS/TS
            "public ", "private ", "static ", "void ",           // Java/C#
            "#include", "#define", "#import",                    // C/C++/ObjC
            "return ", "for ", "while ", "switch ",              // Common
            "=> ", "->", "{ }", "();", "});",                   // Syntax
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchCount = codeIndicators.filter { trimmed.contains($0) }.count
        return matchCount >= 2
    }
}

// Basic syntax highlighter using NSAttributedString
struct SyntaxHighlighter {
    static func highlight(_ code: String) -> NSAttributedString {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseColor = NSColor.labelColor
        
        let attributed = NSMutableAttributedString(string: code, attributes: [
            .font: baseFont,
            .foregroundColor: baseColor
        ])
        
        let keywords = [
            "func", "class", "struct", "enum", "protocol", "extension", "import",
            "var", "let", "const", "def", "return", "if", "else", "for", "while",
            "switch", "case", "break", "continue", "do", "try", "catch", "throw",
            "public", "private", "static", "final", "override", "self", "super",
            "true", "false", "nil", "null", "None", "undefined",
            "async", "await", "function", "void", "int", "string", "bool",
            "guard", "where", "in", "as", "is", "typealias", "init", "deinit",
        ]
        
        let keywordColor = isDark
            ? NSColor(red: 0.78, green: 0.46, blue: 0.87, alpha: 1.0)
            : NSColor(red: 0.61, green: 0.20, blue: 0.69, alpha: 1.0)
        
        let stringColor = isDark
            ? NSColor(red: 0.89, green: 0.55, blue: 0.40, alpha: 1.0)
            : NSColor(red: 0.77, green: 0.25, blue: 0.18, alpha: 1.0)
        
        let commentColor = isDark
            ? NSColor(red: 0.45, green: 0.55, blue: 0.45, alpha: 1.0)
            : NSColor(red: 0.30, green: 0.50, blue: 0.30, alpha: 1.0)
        
        let numberColor = isDark
            ? NSColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0)
            : NSColor(red: 0.11, green: 0.43, blue: 0.69, alpha: 1.0)
        
        let nsString = code as NSString
        
        highlightPattern("\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", in: attributed, with: stringColor, range: NSRange(location: 0, length: nsString.length))
        highlightPattern("'[^'\\\\]*(\\\\.[^'\\\\]*)*'", in: attributed, with: stringColor, range: NSRange(location: 0, length: nsString.length))
        highlightPattern("//.*$", in: attributed, with: commentColor, range: NSRange(location: 0, length: nsString.length))
        highlightPattern("#(?!include|define|import).*$", in: attributed, with: commentColor, range: NSRange(location: 0, length: nsString.length))
        
        for keyword in keywords {
            highlightPattern("\\b\(keyword)\\b", in: attributed, with: keywordColor, range: NSRange(location: 0, length: nsString.length))
        }
        
        highlightPattern("\\b\\d+(\\.\\d+)?\\b", in: attributed, with: numberColor, range: NSRange(location: 0, length: nsString.length))
        
        return attributed
    }
    
    private static func highlightPattern(_ pattern: String, in attributed: NSMutableAttributedString, with color: NSColor, range: NSRange) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

struct PreviewPanel: View {
    let clip: ClipType
    let clipboardManager: ClipboardManager
    let appSettings: AppSettings
    let onClose: () -> Void
    @State private var isFullScreen: Bool = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            Divider()
            detailsSection
            Divider()
            actionBar
        }
        .onAppear {
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 8) {
            if let icon = clip.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.sourceAppName ?? "Unknown App")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(clip.dataType.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if clip.isPinned {
                HStack(spacing: 2) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                    Text("Pinned")
                        .font(.system(size: 10))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Content Area
    
    @ViewBuilder
    private var contentArea: some View {
        switch clip {
        case .text(let textClip):
            if textClip.isURL {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text("URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    if appSettings.openURLsInBrowser {
                        Button(action: {
                            let trimmed = textClip.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let url = URL(string: trimmed) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text(textClip.text)
                                .font(.system(size: 13))
                                .foregroundColor(.accentColor)
                                .underline()
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        Text(textClip.text)
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer()
                }
            } else {
                ScrollableTextView(text: textClip.text, syntaxHighlighting: appSettings.syntaxHighlighting, showLineNumbers: false)
                    .cornerRadius(6)
                    .padding(12)
            }
            
        case .image(let imageClip):
            ScrollView {
                VStack(spacing: 12) {
                    if let fullImage = imageClip.fullImage() {
                        Image(nsImage: fullImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 350)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    } else {
                        Text("Unable to display image")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            
        case .file(let fileClip):
            if fileClip.isSingleFile {
                VStack(spacing: 16) {
                    Image(nsImage: fileClip.cachedFileIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                    
                    Text(fileClip.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                    
                    Text(fileClip.filePath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text("\(fileClip.fileCount) files")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(zip(fileClip.fileNames.indices, fileClip.fileNames)), id: \.0) { index, name in
                                HStack(spacing: 8) {
                                    Image(nsImage: fileClip.cachedFileIcons[index])
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(fileClip.filePaths[index])
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }
    
    // MARK: - Details Section (type-specific metadata not on cards)
    
    private var detailsSection: some View {
        VStack(spacing: 0) {
            // Full date (cards only show relative time)
            detailRow(label: "Copied", value: dateFormatter.string(from: clip.createdAt))
            
            // Source app
            if let appName = clip.sourceAppName {
                Divider().padding(.leading, 12)
                detailRow(label: "Source", value: appName)
            }
            
            // Type-specific details
            if case .text(let textClip) = clip {
                Divider().padding(.leading, 12)
                let charCount = textClip.text.count
                let wordCount = textClip.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                let lineCount = textClip.text.components(separatedBy: .newlines).count
                detailRow(label: "Content", value: "\(charCount) chars · \(wordCount) words · \(lineCount) lines")
            }
            
            if case .image(let imageClip) = clip {
                Divider().padding(.leading, 12)
                detailRow(label: "Dimensions", value: "\(imageClip.width) × \(imageClip.height) px")
            }
            
            if case .file(let fileClip) = clip {
                if !fileClip.isSingleFile {
                    Divider().padding(.leading, 12)
                    detailRow(label: "Files", value: "\(fileClip.fileCount) items")
                }
                if fileClip.isSingleFile {
                    Divider().padding(.leading, 12)
                    detailRow(label: "Extension", value: fileClip.fileExtension.uppercased())
                }
                Divider().padding(.leading, 12)
                if fileClip.isSingleFile {
                    detailRow(label: "Path", value: fileClip.filePath)
                } else {
                    detailRow(label: "Location", value: URL(fileURLWithPath: fileClip.filePaths.first ?? "").deletingLastPathComponent().path)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(width: 72, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()
            
            Button(action: {
                clipboardManager.togglePin(for: clip.id)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: clip.isPinned ? "pin.slash.fill" : "pin")
                        .font(.system(size: 10))
                    Text(clip.isPinned ? "Unpin" : "Pin")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(5)
            
            Button(action: {
                clipboardManager.copyToClipboard(clip)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                    Text("Copy")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(5)
            
            Button(action: {
                clipboardManager.delete(clipID: clip.id)
                onClose()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Delete")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.08))
            .cornerRadius(5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

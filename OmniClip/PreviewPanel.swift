import SwiftUI
import AppKit

// Virtualized text view with optional syntax highlighting
private struct ScrollableTextView: NSViewRepresentable {
    let text: String
    let syntaxHighlighting: Bool
    
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
            ? NSColor(red: 0.78, green: 0.46, blue: 0.87, alpha: 1.0)    // purple
            : NSColor(red: 0.61, green: 0.20, blue: 0.69, alpha: 1.0)
        
        let stringColor = isDark
            ? NSColor(red: 0.89, green: 0.55, blue: 0.40, alpha: 1.0)    // orange
            : NSColor(red: 0.77, green: 0.25, blue: 0.18, alpha: 1.0)
        
        let commentColor = isDark
            ? NSColor(red: 0.45, green: 0.55, blue: 0.45, alpha: 1.0)    // green-gray
            : NSColor(red: 0.30, green: 0.50, blue: 0.30, alpha: 1.0)
        
        let numberColor = isDark
            ? NSColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0)    // yellow
            : NSColor(red: 0.11, green: 0.43, blue: 0.69, alpha: 1.0)
        
        let nsString = code as NSString
        
        // Highlight strings (double-quoted)
        highlightPattern("\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", in: attributed, with: stringColor, range: NSRange(location: 0, length: nsString.length))
        
        // Highlight strings (single-quoted)
        highlightPattern("'[^'\\\\]*(\\\\.[^'\\\\]*)*'", in: attributed, with: stringColor, range: NSRange(location: 0, length: nsString.length))
        
        // Highlight single-line comments
        highlightPattern("//.*$", in: attributed, with: commentColor, range: NSRange(location: 0, length: nsString.length))
        
        // Highlight # comments (Python/Ruby)
        highlightPattern("#(?!include|define|import).*$", in: attributed, with: commentColor, range: NSRange(location: 0, length: nsString.length))
        
        // Highlight keywords (word boundaries)
        for keyword in keywords {
            highlightPattern("\\b\(keyword)\\b", in: attributed, with: keywordColor, range: NSRange(location: 0, length: nsString.length))
        }
        
        // Highlight numbers
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
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
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
            metadataSection
            Divider()
            actionBar
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
            
            Text(relativeDateFormatter.localizedString(for: clip.createdAt, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
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
                ScrollableTextView(text: textClip.text, syntaxHighlighting: appSettings.syntaxHighlighting)
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
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(spacing: 0) {
            metadataRow(label: "Type", value: clip.dataType.rawValue)
            
            Divider().padding(.leading, 12)
            
            metadataRow(label: "Size", value: formatBytes(clip.dataSize))
            
            Divider().padding(.leading, 12)
            
            metadataRow(label: "Copied", value: dateFormatter.string(from: clip.createdAt))
            
            if case .text(let textClip) = clip {
                Divider().padding(.leading, 12)
                
                let charCount = textClip.text.count
                let wordCount = textClip.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                let lineCount = textClip.text.components(separatedBy: .newlines).count
                metadataRow(label: "Content", value: "\(charCount) chars, \(wordCount) words, \(lineCount) lines")
            }
            
            if case .image(let imageClip) = clip {
                Divider().padding(.leading, 12)
                metadataRow(label: "Dimensions", value: "\(imageClip.width) x \(imageClip.height)")
            }
            
            if case .file(let fileClip) = clip {
                Divider().padding(.leading, 12)
                metadataRow(label: "Extension", value: fileClip.fileExtension.uppercased())
                Divider().padding(.leading, 12)
                metadataRow(label: "Path", value: fileClip.filePath)
            }
            
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
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

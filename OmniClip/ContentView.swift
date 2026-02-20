import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var keyboardActions: KeyboardActionPublisher
    @State private var selectedClipID: UUID?
    @State private var searchText = ""
    @State private var searchFieldFocused = false
    
    var selectedClip: ClipType? {
        guard let id = selectedClipID else { return nil }
        return clipboardManager.clips.first { $0.id == id }
    }
    
    var filteredClips: [ClipType] {
        let clips = clipboardManager.sortedClips
        
        if searchText.isEmpty {
            return clips
        }
        
        return clips.filter { clip in
            switch clip {
            case .text(let textClip):
                return textClip.text.localizedCaseInsensitiveContains(searchText)
            case .image:
                return false
            case .file(let fileClip):
                return fileClip.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: List of clips
            VStack(spacing: 0) {
                // Search bar
                SearchField(text: $searchText, isFocused: $searchFieldFocused)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Clips list
                if filteredClips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No clips yet" : "No matching clips")
                            .foregroundColor(.secondary)
                        if searchText.isEmpty {
                            Text("Copy something to get started")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredClips) { clip in
                                    EquatableView(content: ClipItemRow(
                                        clip: clip,
                                        isSelected: selectedClipID == clip.id,
                                        onSelect: {
                                            selectedClipID = clip.id
                                            if appSettings.copyOnClick {
                                                clipboardManager.copyToClipboard(clip)
                                            }
                                        },
                                        onCopy: {
                                            clipboardManager.copyToClipboard(clip)
                                        }
                                    ))
                                    .id(clip.id)
                                    Divider()
                                }
                            }
                        }
                        .scrollIndicators(.never)
                        .onChange(of: selectedClipID) { newID in
                            if let id = newID {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Bottom toolbar
                HStack(spacing: 12) {
                    Text("\(filteredClips.count) clips")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Shift+\u{2191}\u{2193}  Enter")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)
                    
                    Menu {
                        Button("Clear Unpinned") {
                            clipboardManager.clearUnpinned()
                            selectedClipID = nil
                        }
                        Button("Clear All") {
                            clipboardManager.clearAll()
                            selectedClipID = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24, height: 24)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 380)
            
            Divider()
            
            // Right side: Preview panel
            if let clip = selectedClip {
                PreviewPanel(
                    clip: clip,
                    clipboardManager: clipboardManager,
                    appSettings: appSettings,
                    onClose: { self.selectedClipID = nil }
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: appSettings.copyOnClick ? "hand.tap" : "arrow.left")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(appSettings.copyOnClick ? "Click any clip to copy" : "Select a clip to preview")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(width: 900, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if selectedClipID == nil, let firstClip = filteredClips.first {
                selectedClipID = firstClip.id
            }
        }
        // React to keyboard actions from AppDelegate
        .onChange(of: keyboardActions.actionCounter) { _ in
            handleKeyboardAction(keyboardActions.lastAction)
        }
    }
    
    // MARK: - Keyboard Action Handler
    
    private func handleKeyboardAction(_ action: String) {
        switch action {
        case "up":
            moveSelection(by: -1)
        case "down":
            moveSelection(by: 1)
        case "enter":
            copySelectedAndDismiss()
        case "search":
            searchFieldFocused = true
        default:
            break
        }
    }
    
    private func moveSelection(by offset: Int) {
        let clips = filteredClips
        guard !clips.isEmpty else { return }
        
        // Resign search field so typing doesn't go there
        NSApp.keyWindow?.makeFirstResponder(nil)
        
        if let currentID = selectedClipID,
           let currentIndex = clips.firstIndex(where: { $0.id == currentID }) {
            let newIndex = max(0, min(clips.count - 1, currentIndex + offset))
            selectedClipID = clips[newIndex].id
        } else {
            selectedClipID = clips[0].id
        }
    }
    
    private func copySelectedAndDismiss() {
        guard let clip = selectedClip else { return }
        clipboardManager.copyToClipboard(clip)
        NotificationCenter.default.post(name: .dismissOmniClip, object: nil)
    }
}

// Notification for dismissing
extension Notification.Name {
    static let dismissOmniClip = Notification.Name("dismissOmniClip")
}

// NSViewRepresentable search field with focus control
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search clips..."
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        return field
    }
    
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                self.isFocused = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                text = field.stringValue
            }
        }
    }
}

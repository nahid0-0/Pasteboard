import SwiftUI
import AppKit

// Shared state for toolbar — used by both titlebar accessory and ContentView
class ToolbarState: ObservableObject {
    @Published var searchText: String = ""
    @Published var typeFilter: String = "All"
    @Published var searchFieldFocused: Bool = false
    @Published var clipCount: Int = 0
    @Published var isPopoverMode: Bool = false
    
    let typeFilterOptions = ["All", "Text", "Image", "URL", "File", "Stack"]
}

struct ContentView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var keyboardActions: KeyboardActionPublisher
    @ObservedObject var toolbarState: ToolbarState
    @State private var selectedClipID: UUID?
    @State private var scrollOnNextSelection = false
    @State private var leftPanelWidth: CGFloat = 380
    @State private var dragStartWidth: CGFloat = 380
    
    // O(1) lookup for selected clip
    private var clipsByID: [UUID: ClipType] {
        Dictionary(uniqueKeysWithValues: clipboardManager.clips.map { ($0.id, $0) })
    }
    
    var selectedClip: ClipType? {
        guard let id = selectedClipID else { return nil }
        return clipsByID[id]
    }
    
    var filteredClips: [ClipType] {
        let clips = clipboardManager.sortedClips
        
        // Apply type filter
        let typeFiltered: [ClipType]
        switch toolbarState.typeFilter {
        case "Text":
            typeFiltered = clips.filter { $0.dataType == .plainText }
        case "Image":
            typeFiltered = clips.filter { $0.dataType == .image }
        case "URL":
            typeFiltered = clips.filter { $0.dataType == .url }
        case "File":
            typeFiltered = clips.filter { $0.dataType == .file }
        case "Stack":
            typeFiltered = clips.filter { $0.dataType == .stack }
        default:
            typeFiltered = clips
        }
        
        // Apply search filter
        if toolbarState.searchText.isEmpty {
            return typeFiltered
        }
        
        return typeFiltered.filter { clip in
            switch clip {
            case .text(let textClip):
                return textClip.text.localizedCaseInsensitiveContains(toolbarState.searchText)
            case .image:
                return false
            case .file(let fileClip):
                return fileClip.fileName.localizedCaseInsensitiveContains(toolbarState.searchText)
            case .stack(let set):
                return set.items.contains { item in
                    if case .text(let t) = item {
                        return t.text.localizedCaseInsensitiveContains(toolbarState.searchText)
                    }
                    return false
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Show inline toolbar in popover mode (no titlebar accessory)
            if toolbarState.isPopoverMode {
                TitlebarToolbarView(toolbarState: toolbarState, clipboardManager: clipboardManager)
                    .padding(.horizontal, 6)
                    .frame(height: 36)
                    .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }
            
            HStack(spacing: 0) {
            // Left side: List of clips
            VStack(spacing: 0) {
                if filteredClips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(toolbarState.searchText.isEmpty ? "No clips yet" : "No matching clips")
                            .foregroundColor(.secondary)
                        if toolbarState.searchText.isEmpty {
                            Text("Copy something to get started")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
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
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: selectedClipID) { newID in
                            if let id = newID, scrollOnNextSelection {
                                scrollOnNextSelection = false
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Bottom status bar
                HStack(spacing: 12) {
                    Text("\(filteredClips.count) clips")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(appSettings.navUpDisplay)\(appSettings.navDownDisplay)  Enter")
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
            .frame(width: leftPanelWidth)
            
            // Draggable resize handle
            ZStack {
                Color(NSColor.separatorColor)
                    .frame(width: 1)
                NonDraggableArea()
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let newWidth = dragStartWidth + value.translation.width
                                leftPanelWidth = max(220, min(650, newWidth))
                            }
                            .onEnded { _ in
                                dragStartWidth = leftPanelWidth
                            }
                    )
            }
            .frame(width: 8)
            
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
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 400, idealHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if selectedClipID == nil, let firstClip = filteredClips.first {
                selectedClipID = firstClip.id
            }
        }
        .onChange(of: keyboardActions.actionCounter) { _ in
            handleKeyboardAction(keyboardActions.lastAction)
        }
        .onChange(of: filteredClips.count) { newCount in
            toolbarState.clipCount = newCount
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
            toolbarState.searchFieldFocused = true
        default:
            break
        }
    }
    
    private func moveSelection(by offset: Int) {
        let clips = filteredClips
        guard !clips.isEmpty else { return }
        
        NSApp.keyWindow?.makeFirstResponder(nil)
        
        if let currentID = selectedClipID,
           let currentIndex = clips.firstIndex(where: { $0.id == currentID }) {
            let newIndex = max(0, min(clips.count - 1, currentIndex + offset))
            scrollOnNextSelection = true
            selectedClipID = clips[newIndex].id
        } else {
            scrollOnNextSelection = true
            selectedClipID = clips[0].id
        }
    }
    
    private func copySelectedAndDismiss() {
        guard let clip = selectedClip else { return }
        clipboardManager.copyToClipboard(clip)
        NotificationCenter.default.post(name: .dismissOmniClip, object: nil)
    }
}

// Notifications
extension Notification.Name {
    static let dismissOmniClip = Notification.Name("dismissOmniClip")
    static let openOmniClipSettings = Notification.Name("openOmniClipSettings")
}

// MARK: - Titlebar Toolbar View (embedded in titlebar accessory)

struct TitlebarToolbarView: View {
    @ObservedObject var toolbarState: ToolbarState
    @ObservedObject var clipboardManager: ClipboardManager
    
    var body: some View {
        HStack(spacing: 6) {
            // Search field
            SearchField(text: $toolbarState.searchText, isFocused: $toolbarState.searchFieldFocused)
                .frame(maxWidth: .infinity)
            
            // Stack toggle button
            Button(action: { clipboardManager.toggleStackMode() }) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13))
                    .foregroundColor(clipboardManager.isStackMode ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(clipboardManager.isStackMode ? "Stop Stacking" : "Start Stacking")
            
            // Filter pills
            ForEach(toolbarState.typeFilterOptions, id: \.self) { option in
                Button(action: { toolbarState.typeFilter = option }) {
                    Text(option)
                        .font(.system(size: 10, weight: toolbarState.typeFilter == option ? .semibold : .regular))
                        .foregroundColor(toolbarState.typeFilter == option ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(toolbarState.typeFilter == option ? Color.secondary.opacity(0.2) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Clip count
            Text("\(toolbarState.clipCount) clips")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize()
            
            // Settings button
            Button(action: {
                NotificationCenter.default.post(name: .openOmniClipSettings, object: nil)
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 28)
    }
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
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: 11)
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

// MARK: - Non-Draggable Area (prevents isMovableByWindowBackground from intercepting drags)

private class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

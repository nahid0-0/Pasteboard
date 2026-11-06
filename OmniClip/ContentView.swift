import SwiftUI
import AppKit

// Shared state for toolbar — used by both titlebar accessory and ContentView
class ToolbarState: ObservableObject {
    @Published var searchText: String = ""
    @Published var typeFilter: String = "All"
    @Published var notesFilter: String = "All"   // Notes page: All / Text / Form / Image
    @Published var searchFieldFocused: Bool = false
    @Published var clipCount: Int = 0
    @Published var isPopoverMode: Bool = false
    
    let typeFilterOptions = ["All", "Text", "Image", "URL", "File"]
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
    @State private var showAddPanel: Bool = false
    
    // Linear scan over ≤55 clips — cheaper than rebuilding a dictionary on every render
    var selectedClip: ClipType? {
        guard let id = selectedClipID else { return nil }
        return clipboardManager.clips.first { $0.id == id }
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
        // Filter once per render (was recomputed ~6× per render)
        let visibleClips = filteredClips
        VStack(spacing: 0) {
            HStack(spacing: 0) {
            // Left side: List of clips
            VStack(spacing: 0) {
                if visibleClips.isEmpty {
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
                                ForEach(visibleClips) { clip in
                                    EquatableView(content: ClipItemRow(
                                        clip: clip,
                                        isSelected: selectedClipID == clip.id,
                                        theme: appSettings.theme,
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
                        .clipped()
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
                    Text("\(visibleClips.count) clips")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
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
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                }
                .padding(8)
                .background(appSettings.theme.panelBg)
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
            
            // Right side: Add form or Preview panel
            if showAddPanel {
                AddClipView(
                    clipboardManager: clipboardManager,
                    appSettings: appSettings,
                    onDismiss: { showAddPanel = false }
                )
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            } else if let clip = selectedClip {
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
                .background(appSettings.theme.emptyBg, ignoresSafeAreaEdges: [])  // don't bleed into the titlebar
            }
            }
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 400, idealHeight: 600)
        .background(appSettings.theme.mainBg)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .showAddClipPanel)) { _ in
            showAddPanel = true
            selectedClipID = nil
        }
        .onAppear {
            if selectedClipID == nil, let firstClip = visibleClips.first {
                selectedClipID = firstClip.id
            }
        }
        .onChange(of: keyboardActions.actionCounter) { _ in
            handleKeyboardAction(keyboardActions.lastAction)
        }
        .onChange(of: visibleClips.count) { newCount in
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
    static let showAddClipPanel = Notification.Name("showAddClipPanel")
    static let addPlainNote = Notification.Name("addPlainNote")
    static let addFormNote = Notification.Name("addFormNote")
    static let addImageNote = Notification.Name("addImageNote")
}

// MARK: - Titlebar Toolbar View (embedded in titlebar accessory)

struct TitlebarToolbarView: View {
    @ObservedObject var toolbarState: ToolbarState
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var appSettings: AppSettings
    @EnvironmentObject var navigation: NavigationState

    var body: some View {
        HStack(spacing: 6) {
            switch navigation.currentPage {

            // ── Clipboard page toolbar ──────────────────────────────
            case .clipboard:
                // Search field
                SearchField(text: $toolbarState.searchText, isFocused: $toolbarState.searchFieldFocused)
                    .frame(maxWidth: .infinity)

                // Stack toggle — 1st position
                Button(action: { clipboardManager.toggleStackMode() }) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13))
                        .foregroundColor(clipboardManager.isStackMode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(clipboardManager.isStackMode ? "Stop Stacking" : "Start Stacking")

                // "All" pill — 2nd position
                Button(action: { toolbarState.typeFilter = "All" }) {
                    Text("All")
                        .font(.system(size: 10, weight: toolbarState.typeFilter == "All" ? .semibold : .regular))
                        .foregroundColor(toolbarState.typeFilter == "All" ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(toolbarState.typeFilter == "All" ? Color.secondary.opacity(0.2) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                // Type filter pills
                ForEach(["Text", "Image", "URL", "File"], id: \.self) { option in
                    Button(action: { toolbarState.typeFilter = option }) {
                        Text(option)
                            .font(.system(size: 10, weight: toolbarState.typeFilter == option ? .semibold : .regular))
                            .foregroundColor(toolbarState.typeFilter == option ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(toolbarState.typeFilter == option ? Color.secondary.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Note button
                Button(action: { navigation.openNotes() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                        Text("Note")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Open Notes")

                // Add button
                Button(action: {
                    NotificationCenter.default.post(name: .showAddClipPanel, object: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Manually add a clip")

            // ── Notes page toolbar ──────────────────────────────────
            case .notes:
                // Back button
                Button(action: { navigation.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.trailing, 4)

                // Type filter pills (same style as the clipboard page)
                ForEach(["All", "Text", "Form", "Image"], id: \.self) { option in
                    Button(action: { toolbarState.notesFilter = option }) {
                        Text(option)
                            .font(.system(size: 10, weight: toolbarState.notesFilter == option ? .semibold : .regular))
                            .foregroundColor(toolbarState.notesFilter == option ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(toolbarState.notesFilter == option ? Color.secondary.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // New note menu (stays in toolbar for notes page)
                Menu {
                    Button(action: {
                        NotificationCenter.default.post(name: .addPlainNote, object: nil)
                    }) {
                        Label("Plain Text Note", systemImage: "doc.text")
                    }
                    Button(action: {
                        NotificationCenter.default.post(name: .addFormNote, object: nil)
                    }) {
                        Label("Form Note", systemImage: "list.bullet.clipboard")
                    }
                    Button(action: {
                        NotificationCenter.default.post(name: .addImageNote, object: nil)
                    }) {
                        Label("Image Note", systemImage: "photo")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor)
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 52, height: 22)

            // ── Settings page toolbar ───────────────────────────────
            case .settings:
                Button(action: { navigation.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // ── Always-visible: Pin + Gear ──────────────────────────
            Button(action: { appSettings.isFloating.toggle() }) {
                Image(systemName: appSettings.isFloating ? "pin.circle.fill" : "pin.circle")
                    .font(.system(size: 14))
                    .foregroundColor(appSettings.isFloating ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(appSettings.isFloating ? "Stop floating" : "Keep window floating above other apps")

            Button(action: { navigation.openSettings() }) {
                Image(systemName: "gear")
                    .font(.system(size: 13))
                    .foregroundColor(navigation.currentPage == .settings ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 28)
        .background(appSettings.theme.mainBg)
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

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

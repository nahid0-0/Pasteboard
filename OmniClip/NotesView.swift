import SwiftUI
import AppKit
import ImageIO

// MARK: - Note image cache
// Notes store raw image Data; decoding it on every SwiftUI redraw (hover, selection,
// typing) is expensive. These caches decode each image once.

final class NoteImageCache {
    static let shared = NoteImageCache()

    private let fullImages = NSCache<NSData, NSImage>()
    private let thumbnails = NSCache<NSData, NSImage>()
    private let sizes = NSCache<NSData, NSValue>()

    private init() {
        fullImages.countLimit = 20
        thumbnails.countLimit = 300
        sizes.countLimit = 500
    }

    /// Full image (decoded once)
    func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = fullImages.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        fullImages.setObject(image, forKey: key)
        return image
    }

    /// Small thumbnail decoded straight to `maxPixel` (no full-size decode)
    func thumbnail(for data: Data, maxPixel: Int) -> NSImage? {
        let key = data as NSData
        if let cached = thumbnails.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        let thumb: NSImage?
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            thumb = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else {
            thumb = image(for: data)
        }
        if let thumb = thumb { thumbnails.setObject(thumb, forKey: key) }
        return thumb
    }

    /// Pixel dimensions read from the image header (no decode)
    func pixelSize(for data: Data) -> (width: Int, height: Int)? {
        let key = data as NSData
        if let cached = sizes.object(forKey: key) {
            let s = cached.sizeValue
            return (Int(s.width), Int(s.height))
        }
        var result: (Int, Int)?
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            result = (w, h)
        } else if let rep = NSImage(data: data)?.representations.first {
            result = (rep.pixelsWide, rep.pixelsHigh)
        }
        if let r = result {
            sizes.setObject(NSValue(size: NSSize(width: r.0, height: r.1)), forKey: key)
        }
        return result
    }
}

// MARK: - Scroll edge glow suppression (macOS 26 draws a soft glass gradient
// at scroll edges by default; we want flat, minimal panels instead)

extension View {
    @ViewBuilder
    func noScrollEdgeGlow() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

// MARK: - Notes Root View (in-app page)
// Layout mirrors the clipboard page: card list on the left (same row style, width and
// status bar), detail pane on the right (header / content / details / action bar).

struct NotesView: View {
    @ObservedObject var noteManager: NoteManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var toolbarState: ToolbarState

    @State private var selectedNoteID: UUID?
    @State private var leftPanelWidth: CGFloat = 380
    @State private var dragStartWidth: CGFloat = 380

    /// Notes matching the toolbar filter, pinned first (order otherwise preserved)
    var filteredNotes: [Note] {
        let typed: [Note]
        switch toolbarState.notesFilter {
        case "Text": typed = noteManager.notes.filter {
            if case .plainText = $0.content { return true }; return false
        }
        case "Form": typed = noteManager.notes.filter {
            if case .form = $0.content { return true }; return false
        }
        case "Image": typed = noteManager.notes.filter {
            if case .image = $0.content { return true }; return false
        }
        default: typed = noteManager.notes
        }
        return typed.filter { $0.isPinned } + typed.filter { !$0.isPinned }
    }

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteManager.notes.first { $0.id == id }
    }

    var body: some View {
        let visibleNotes = filteredNotes
        HStack(spacing: 0) {
            // ── LEFT PANEL ──────────────────────────────────────────
            VStack(spacing: 0) {
                if visibleNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(noteManager.notes.isEmpty ? "No notes yet" : "No \(toolbarState.notesFilter.lowercased()) notes")
                            .foregroundColor(.secondary)
                        Text("Use the New button to create one")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(visibleNotes) { note in
                                NoteItemRow(
                                    note: note,
                                    isSelected: selectedNoteID == note.id,
                                    theme: appSettings.theme,
                                    onSelect: { selectedNoteID = note.id },
                                    onDelete: {
                                        noteManager.deleteNote(id: note.id)
                                        if selectedNoteID == note.id {
                                            selectedNoteID = visibleNotes.first(where: { $0.id != note.id })?.id
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                    .noScrollEdgeGlow()
                    .clipped()
                }

                Divider()

                // Bottom status bar
                HStack(spacing: 12) {
                    Text("\(visibleNotes.count) note\(visibleNotes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 24)
                .padding(8)
                .background(appSettings.theme.panelBg)
            }
            .frame(width: leftPanelWidth)

            // Draggable resize handle (same as clipboard page)
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
                                leftPanelWidth = max(220, min(650, dragStartWidth + value.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = leftPanelWidth }
                    )
            }
            .frame(width: 8)

            // ── RIGHT PANEL ─────────────────────────────────────────
            if let note = selectedNote {
                NoteEditorView(
                    note: note,
                    noteManager: noteManager,
                    appSettings: appSettings
                )
                // Force SwiftUI to destroy & recreate this view (and all its @State)
                // when the selected note changes. Without this, editingTitle persists
                // from the previous note and looks like a shared "app bar" title.
                .id(note.id)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select a note to view it")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appSettings.theme.emptyBg, ignoresSafeAreaEdges: [])  // don't bleed into the titlebar
            }
        }
        .background(appSettings.theme.mainBg)
        .onAppear {
            if selectedNoteID == nil { selectedNoteID = visibleNotes.first?.id }
        }
        // Listen for New Note notifications from toolbar menu
        .onReceive(NotificationCenter.default.publisher(for: .addPlainNote)) { _ in
            addNote(type: .plainText(""))
        }
        .onReceive(NotificationCenter.default.publisher(for: .addFormNote)) { _ in
            addNote(type: .form([]))
        }
        .onReceive(NotificationCenter.default.publisher(for: .addImageNote)) { _ in
            addNote(type: .image(Data()))
        }
    }

    private func addNote(type: NoteContent) {
        noteManager.addNote(type: type)
        selectedNoteID = noteManager.notes.first?.id
    }
}

// MARK: - Note Item Row — same look as the clipboard's ClipItemRow

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

struct NoteItemRow: View {
    let note: Note
    let isSelected: Bool
    let theme: AppTheme
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// One-line content preview (only looks at the start of long notes)
    private var previewText: String {
        switch note.content {
        case .plainText(let t):
            let head = t.prefix(400).trimmingCharacters(in: .whitespacesAndNewlines)
            return head.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first.map(String.init) ?? ""
        case .form(let items):
            return items.prefix(6)
                .map { $0.imageData != nil ? "Image" : ($0.label.isEmpty ? $0.value : "\($0.label): \($0.value)") }
                .joined(separator: " · ")
        case .image:
            return ""
        }
    }

    private var countChip: (icon: String, text: String) {
        switch note.content {
        case .plainText(let t):
            return ("textformat", "\(t.count) chars")
        case .form(let items):
            return ("list.bullet", "\(items.count) field\(items.count == 1 ? "" : "s")")
        case .image(let data):
            if !data.isEmpty, let size = NoteImageCache.shared.pixelSize(for: data) {
                return ("aspectratio", "\(size.width) × \(size.height)")
            }
            return ("aspectratio", "No image")
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Top: leading icon/thumbnail + title & preview
                HStack(alignment: .center, spacing: 8) {
                    leadingIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !previewText.isEmpty {
                            Text(previewText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 4)

                    if isHovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete note")
                    }

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor)
                    }
                }

                // Bottom: metadata chips (same as clip rows)
                HStack(spacing: 6) {
                    metadataChip(icon: "clock",
                                 text: relativeFormatter.localizedString(for: note.modifiedAt, relativeTo: Date()))
                    metadataChip(icon: note.content.typeIcon, text: note.content.typeName)
                    metadataChip(icon: countChip.icon, text: countChip.text)
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? theme.cardBgSelected : (isHovering ? theme.cardBgHover : theme.cardBgNormal))
                    if isSelected {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if case .image(let data) = note.content, !data.isEmpty,
           let thumb = NoteImageCache.shared.thumbnail(for: data, maxPixel: 128) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .cornerRadius(4)
                .clipped()
        } else {
            Image(systemName: note.content.typeIcon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 20, height: 20)
        }
    }

    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundColor(.secondary)
    }
}

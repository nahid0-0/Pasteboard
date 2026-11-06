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

struct NotesView: View {
    @ObservedObject var noteManager: NoteManager
    @ObservedObject var appSettings: AppSettings

    @State private var selectedNoteID: UUID?
    @State private var filterType: String = "All"   // All / Text / Form / Image
    @State private var leftPanelWidth: CGFloat = 260
    @State private var dragStartWidth: CGFloat = 260

    private let filterOptions = ["All", "Text", "Form", "Image"]

    var filteredNotes: [Note] {
        switch filterType {
        case "Text": return noteManager.notes.filter {
            if case .plainText = $0.content { return true }; return false
        }
        case "Form": return noteManager.notes.filter {
            if case .form = $0.content { return true }; return false
        }
        case "Image": return noteManager.notes.filter {
            if case .image = $0.content { return true }; return false
        }
        default: return noteManager.notes
        }
    }

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteManager.notes.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
            // ── LEFT PANEL ──────────────────────────────────────────
            VStack(spacing: 0) {
                // Filter strip
                HStack(spacing: 4) {
                    ForEach(filterOptions, id: \.self) { option in
                        Button(action: { filterType = option }) {
                            Text(option)
                                .font(.system(size: 10, weight: filterType == option ? .semibold : .regular))
                                .foregroundColor(filterType == option ? .primary : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(filterType == option ? Color.secondary.opacity(0.2) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(appSettings.theme.mainBg)

                Divider()

                // Note list
                if filteredNotes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No notes yet")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        Text("Use the New button to create one")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredNotes) { note in
                                NoteItemRow(
                                    note: note,
                                    isSelected: selectedNoteID == note.id,
                                    theme: appSettings.theme,
                                    onSelect: { selectedNoteID = note.id },
                                    onDelete: {
                                        noteManager.deleteNote(id: note.id)
                                        if selectedNoteID == note.id { selectedNoteID = filteredNotes.first(where: { $0.id != note.id })?.id }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                    .noScrollEdgeGlow()
                }

                Divider()

                // Bottom count
                HStack {
                    Text("\(filteredNotes.count) note\(filteredNotes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(appSettings.theme.panelBg)
            }
            .frame(width: leftPanelWidth)
            .background(appSettings.theme.mainBg)

            // Resize handle
            ZStack {
                Color(NSColor.separatorColor).frame(width: 1)
                Color.clear.frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { h in h ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in leftPanelWidth = max(180, min(420, dragStartWidth + v.translation.width)) }
                            .onEnded { _ in dragStartWidth = leftPanelWidth }
                    )
            }
            .frame(width: 8)

            // ── RIGHT PANEL ─────────────────────────────────────────
            Group {
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
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.25))
                        Text("Select a note to view it")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appSettings.theme.mainBg)
                }
            }
            }
            .background(appSettings.theme.mainBg)
            .onAppear {
                if selectedNoteID == nil { selectedNoteID = filteredNotes.first?.id }
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
    }

    private func addNote(type: NoteContent) {
        noteManager.addNote(type: type)
        selectedNoteID = noteManager.notes.first?.id
    }
}

// MARK: - Note Item Row — title + detail strip

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

    private var detailCount: String {
        switch note.content {
        case .plainText(let t):
            let chars = t.count
            return "\(chars) chars"
        case .form(let items):
            return "\(items.count) field\(items.count == 1 ? "" : "s")"
        case .image(let data):
            if !data.isEmpty, let size = NoteImageCache.shared.pixelSize(for: data) {
                return "\(size.width) × \(size.height)"
            }
            return "No image"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Type icon
                Image(systemName: note.content.typeIcon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    // Title
                    Text(note.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Detail strip: time · type · count
                    HStack(spacing: 6) {
                        // Relative time
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                            Text(relativeFormatter.localizedString(for: note.modifiedAt, relativeTo: Date()))
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary.opacity(0.7))

                        Text("·")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.4))

                        // Type badge
                        HStack(spacing: 2) {
                            Image(systemName: note.content.typeIcon)
                                .font(.system(size: 8))
                            Text(note.content.typeName)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary.opacity(0.7))

                        Text("·")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.4))

                        // Count
                        Text(detailCount)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

                Spacer(minLength: 4)

                // Hover delete
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? theme.cardBgSelected : (isHovering ? theme.cardBgHover : theme.cardBgNormal))
                    if isSelected {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

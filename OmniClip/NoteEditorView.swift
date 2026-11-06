import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Note Editor (right panel)

struct NoteEditorView: View {
    let note: Note
    @ObservedObject var noteManager: NoteManager
    @ObservedObject var appSettings: AppSettings

    @State private var editingTitle: String = ""
    @State private var plainText: String = ""
    @State private var newFieldValue: String = ""
    @State private var newFieldLabel: String = ""
    @State private var newFieldIsImage: Bool = false   // add-field bar: text or image field
    @State private var editingItemID: UUID? = nil
    @State private var justCopiedText: Bool = false
    @State private var justCopiedImage: Bool = false
    @State private var isDropTargeted: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        // Same structure as the clipboard PreviewPanel:
        // header / content / details / action bar
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                titleField
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentCard(appSettings.theme, top: 4)   // lines up with the first note card
            footerBar
        }
        .onAppear { syncState() }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch note.content {
        case .plainText:
            plainTextBody
        case .form(let items):
            formBody(items: items)
        case .image(let data):
            imageBody(data: data)
        }
    }

    private func syncState() {
        editingTitle = note.title
        if case .plainText(let t) = note.content { plainText = t }
        newFieldValue = ""
        newFieldLabel = ""
        editingItemID = nil
    }

    // MARK: - Title (always editable)

    private var titleField: some View {
        HStack(alignment: .top, spacing: 10) {
            titleBlock
            pinButton
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Pin / unpin — a plain icon next to the title (outline = unpinned, filled = pinned)
    private var pinButton: some View {
        Button(action: { noteManager.togglePin(id: note.id) }) {
            Image(systemName: note.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13))
                .foregroundColor(note.isPinned ? .accentColor : Color.secondary.opacity(0.7))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(note.isPinned ? "Unpin note" : "Pin note to the top of the list")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleTextField
            // Stats line: form notes only — text/image notes show stats in the footer,
            // like the clipboard preview (form notes' footer is the add-field form)
            if case .form = note.content {
            HStack(spacing: 4) {
                Text(contentDetailValue)
                Text("·")
                Text(relativeTimeString(note.modifiedAt))
            }
            .font(.system(size: 10))
            .foregroundColor(Color.white.opacity(0.35))   // dimmed: secondary to the title
            .lineLimit(1)
            .help("Modified \(Self.dateFormatter.string(from: note.modifiedAt))")
            }
        }
    }

    private var titleTextField: some View {
        // Updates the left panel in real time on every keystroke. note.id is always the
        // current note here: the view is recreated via .id(note.id) when selection changes.
        TextField("Untitled", text: $editingTitle, onCommit: {
            saveTitle()
        })
        .textFieldStyle(.plain)
        .font(.system(size: 21, weight: .bold))
        .foregroundColor(.primary)
        .onChange(of: editingTitle) { newVal in
            let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            noteManager.updateTitle(id: note.id, title: trimmed)
        }
    }

    // MARK: - Details (same style as clipboard preview)

    private var contentDetailIcon: String {
        switch note.content {
        case .plainText: return "doc.text"
        case .form: return "list.bullet.clipboard"
        case .image: return "photo"
        }
    }

    private var contentDetailValue: String {
        switch note.content {
        case .plainText(let t):
            let chars = t.count
            let words = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = t.isEmpty ? 0 : t.components(separatedBy: .newlines).count
            return "\(chars) chars · \(words) words · \(lines) lines"
        case .form(let items):
            let images = items.filter { $0.imageData != nil }.count
            let base = "\(items.count) field\(items.count == 1 ? "" : "s")"
            return images > 0 ? "\(base) · \(images) image\(images == 1 ? "" : "s")" : base
        case .image(let data):
            if !data.isEmpty, let size = NoteImageCache.shared.pixelSize(for: data) {
                return "\(size.width) × \(size.height) px"
            }
            return "No image"
        }
    }


    // MARK: - Footer (details + actions in one compact bar)

    private var canCopy: Bool {
        switch note.content {
        case .plainText: return true
        case .image(let data): return !data.isEmpty
        case .form: return false   // form fields are copied individually
        }
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            if case .form = note.content {
                // Form notes: the footer IS the "new field" form
                addFieldControls
            } else {
                // Stats on the left — same as the clipboard preview's bar
                HStack(spacing: 4) {
                    Image(systemName: contentDetailIcon)
                        .font(.system(size: 9))
                    Text(contentDetailValue)
                    Text("·")
                    Text(relativeTimeString(note.modifiedAt))
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help("Modified \(Self.dateFormatter.string(from: note.modifiedAt))")

                Spacer(minLength: 8)

                // Image notes: replace actions
                if case .image(let data) = note.content, !data.isEmpty {
                    iconButton(icon: "doc.on.clipboard", help: "Replace with Clipboard", action: pasteImageFromClipboard)
                    iconButton(icon: "folder", help: "Choose File…", action: chooseImageFile)
                }

                // Delete — icon only, kept apart from Copy (same as clipboard)
                Button(action: { noteManager.deleteNote(id: note.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 20)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Delete note")
                .padding(.trailing, 4)
            }

            if canCopy {
                let copied = justCopiedText || justCopiedImage
                Button(action: {
                    if case .image = note.content { copyImage() } else { copyPlainText() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(copied ? Color.green.opacity(0.8) : Color.accentColor)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: copied)
            }
        }
        .barCard(appSettings.theme)
    }

    private func iconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 20)
                .background(Color.white.opacity(0.07))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func saveTitle() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            noteManager.updateTitle(id: note.id, title: trimmed)
        } else {
            // Restore stored title if field was cleared
            editingTitle = note.title
        }
    }

    private func copyPlainText() {
        let text: String
        if case .plainText(let t) = note.content { text = t } else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        justCopiedText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justCopiedText = false }
    }

    private func copyImage() {
        guard case .image(let data) = note.content, let nsImage = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        justCopiedImage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justCopiedImage = false }
    }

    // MARK: - Plain Text Body

    private var plainTextBody: some View {
        NoteTextEditor(text: $plainText, theme: appSettings.theme)
            .onChange(of: plainText) { newVal in
                noteManager.updateContent(id: note.id, content: .plainText(newVal))
            }
            .noScrollEdgeGlow()
    }

    // MARK: - Image Body

    private func imageBody(data: Data) -> some View {
        Group {
            if let nsImage = NoteImageCache.shared.image(for: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: nsImage.size.width, maxHeight: nsImage.size.height)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                imageDropZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BarCardMetrics.cornerRadius, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            isDropTargeted
                ? RoundedRectangle(cornerRadius: BarCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                : nil
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted, perform: handleImageDrop)
    }

    private var imageDropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.35))
            Text("No image yet")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Paste (⌘V), drag an image here, or choose a file")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(action: pasteImageFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .cornerRadius(5)

                Button(action: chooseImageFile) {
                    Label("Choose File…", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .cornerRadius(5)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setImage(data: Data) {
        noteManager.updateContent(id: note.id, content: .image(data))
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let tiffData = pb.data(forType: .tiff), let nsImage = NSImage(data: tiffData), let png = pngData(from: nsImage) {
            setImage(data: png)
        } else if let pngData = pb.data(forType: .png) {
            setImage(data: pngData)
        }
    }

    private func replaceFormItemImageFromClipboard(itemID: UUID) {
        let pb = NSPasteboard.general
        let png: Data?
        if let tiffData = pb.data(forType: .tiff), let nsImage = NSImage(data: tiffData) {
            png = pngData(from: nsImage)
        } else {
            png = pb.data(forType: .png)
        }
        guard let png else { return }
        noteManager.updateFormItemImage(in: note.id, itemID: itemID, imageData: png)
    }

    private func replaceFormItemImageFromFile(itemID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let nsImage = NSImage(data: data),
              let png = pngData(from: nsImage) else { return }
        noteManager.updateFormItemImage(in: note.id, itemID: itemID, imageData: png)
    }

    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let nsImage = NSImage(data: data),
           let png = pngData(from: nsImage) {
            setImage(data: png)
        }
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let nsImage = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if let png = pngData(from: nsImage) { setImage(data: png) }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                      let fileData = try? Data(contentsOf: url),
                      let nsImage = NSImage(data: fileData) else { return }
                DispatchQueue.main.async {
                    if let png = pngData(from: nsImage) { setImage(data: png) }
                }
            }
            return true
        }

        return false
    }

    // MARK: - Form Body

    private func formBody(items: [FormItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    FormItemRow(
                        item: item,
                        isEditing: editingItemID == item.id,
                        theme: appSettings.theme,
                        onCopy: {
                            NSPasteboard.general.clearContents()
                            if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                                NSPasteboard.general.writeObjects([nsImage])
                            } else {
                                NSPasteboard.general.setString(item.value, forType: .string)
                            }
                        },
                        onEdit: { editingItemID = item.id },
                        onSave: { value, label in
                            noteManager.updateFormItem(in: note.id, itemID: item.id,
                                                       value: value, label: label)
                            editingItemID = nil
                        },
                        onDelete: {
                            noteManager.deleteFormItem(from: note.id, itemID: item.id)
                            if editingItemID == item.id { editingItemID = nil }
                        },
                        onReplaceImageFromClipboard: {
                            replaceFormItemImageFromClipboard(itemID: item.id)
                        },
                        onReplaceImageFromFile: {
                            replaceFormItemImageFromFile(itemID: item.id)
                        },
                        onRemoveImage: {
                            noteManager.updateFormItemImage(in: note.id, itemID: item.id, imageData: nil)
                        }
                    )
                }

            }
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
        .noScrollEdgeGlow()
    }

    /// "New field" form shown in the footer of form notes. Pick the field type first:
    ///   Aa (text):  [Label] [Value — press Return to add]
    ///   🖼 (image): [Label] [Paste Image] [Choose File…]
    private var addFieldControls: some View {
        HStack(spacing: 6) {
            fieldKindPicker

            TextField("Label", text: $newFieldLabel)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(appSettings.theme.mainBg)
                )
                .frame(width: 110)
                .onSubmit { if !newFieldIsImage { addField() } }

            if newFieldIsImage {
                plateButton(icon: "doc.on.clipboard", title: "Paste Image",
                            help: "Add the image on the clipboard as a field",
                            action: addImageFieldFromClipboard)
                plateButton(icon: "folder", title: "Choose File…",
                            help: "Pick an image file to add as a field",
                            action: addImageFieldFromFile)
                Spacer(minLength: 0)
            } else {
                TextField("Value — press Return to add", text: $newFieldValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(appSettings.theme.mainBg)
                    )
                    .frame(maxWidth: .infinity)
                    .onSubmit(addField)
            }
        }
    }

    /// Two-segment toggle: text field or image field
    private var fieldKindPicker: some View {
        HStack(spacing: 2) {
            kindSegment(icon: "textformat", selected: !newFieldIsImage, help: "Text field") {
                newFieldIsImage = false
            }
            kindSegment(icon: "photo", selected: newFieldIsImage, help: "Image field") {
                newFieldIsImage = true
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(appSettings.theme.mainBg)
        )
    }

    private func kindSegment(icon: String, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(selected ? .primary : .secondary)
                .frame(width: 24, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func plateButton(icon: String, title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func addField() {
        let val = newFieldValue.trimmingCharacters(in: .whitespaces)
        guard !val.isEmpty else { return }
        noteManager.addFormItem(to: note.id, value: val, label: newFieldLabel.trimmingCharacters(in: .whitespaces))
        newFieldValue = ""
        newFieldLabel = ""
    }

    private func addImageFieldFromClipboard() {
        let pb = NSPasteboard.general
        let png: Data?
        if let tiffData = pb.data(forType: .tiff), let nsImage = NSImage(data: tiffData) {
            png = pngData(from: nsImage)
        } else {
            png = pb.data(forType: .png)
        }
        guard let png else { return }
        noteManager.addFormItem(to: note.id, value: "", label: newFieldLabel.trimmingCharacters(in: .whitespaces), imageData: png)
        newFieldLabel = ""
    }

    private func addImageFieldFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let nsImage = NSImage(data: data),
              let png = pngData(from: nsImage) else { return }
        noteManager.addFormItem(to: note.id, value: "", label: newFieldLabel.trimmingCharacters(in: .whitespaces), imageData: png)
        newFieldLabel = ""
    }
}

// MARK: - Hairline separator between form rows

struct FormHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

// MARK: - Form Item Row (click anywhere to copy)

struct FormItemRow: View {
    let item: FormItem
    let isEditing: Bool
    let theme: AppTheme
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onReplaceImageFromClipboard: () -> Void
    let onReplaceImageFromFile: () -> Void
    let onRemoveImage: () -> Void

    @State private var editValue: String = ""
    @State private var editLabel: String = ""
    @State private var isHovering: Bool = false
    @State private var justCopied: Bool = false
    @State private var showFullImage: Bool = false

    var body: some View {
        Group {
            if isEditing {
                editRow
            } else {
                displayRow
            }
        }
        .onAppear {
            editValue = item.value
            editLabel = item.label
        }
    }

    private var imageSizeText: String? {
        guard let data = item.imageData, let size = NoteImageCache.shared.pixelSize(for: data) else { return nil }
        return "\(size.width) × \(size.height)"
    }

    private var displayRow: some View {
        Button(action: {
            // Click anywhere on the row to copy
            onCopy()
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
        }) {
            HStack(spacing: 10) {
                // Image fields: thumbnail. Text fields: no icon — just the text.
                if let imageData = item.imageData,
                   let thumb = NoteImageCache.shared.thumbnail(for: imageData, maxPixel: 256) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    if !item.label.isEmpty {
                        Text(item.label)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.secondary.opacity(0.8))
                    }
                    if item.imageData != nil {
                        Text(item.label.isEmpty ? "Image" : (imageSizeText ?? "Image"))
                            .font(.system(size: 13))
                            .foregroundColor(item.label.isEmpty ? .primary : .secondary)
                            .lineLimit(1)
                    } else {
                        Text(item.value)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                // Right side: "Copied" feedback, or quiet actions on hover
                if justCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Copied")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.green)
                    .transition(.opacity)
                } else if isHovering {
                    HStack(spacing: 12) {
                        if item.imageData != nil {
                            rowAction("eye", help: "View full size") { showFullImage = true }
                        }
                        rowAction("pencil", help: "Edit") {
                            editValue = item.value
                            editLabel = item.label
                            onEdit()
                        }
                        rowAction("trash", help: "Delete", action: onDelete)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .help("Click to copy")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.white.opacity(0.025) : Color.clear)
            .overlay(alignment: .bottom) { FormHairline() }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.2), value: justCopied)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $showFullImage) {
            if let imageData = item.imageData, let nsImage = NoteImageCache.shared.image(for: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, maxHeight: 420)
                    .padding(12)
            }
        }
    }

    private func rowAction(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var editRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Label (optional)", text: $editLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(3)

                if item.imageData != nil {
                    HStack(spacing: 6) {
                        Menu {
                            Button(action: onReplaceImageFromClipboard) {
                                Label("Paste Image", systemImage: "doc.on.clipboard")
                            }
                            Button(action: onReplaceImageFromFile) {
                                Label("Choose File…", systemImage: "folder")
                            }
                        } label: {
                            Text("Replace Image")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(3)

                        Button(action: onRemoveImage) {
                            Text("Remove Image")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    TextField("Value", text: $editValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                }
            }

            VStack(spacing: 4) {
                Button(action: { onSave(editValue, editLabel) }) {
                    Text("Save")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: { onSave(item.value, item.label) }) {
                    Text("Cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) { FormHairline() }
    }
}

// MARK: - Plain text NSTextView for notes

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let theme: AppTheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 11, height: 4)   // 11 + 5pt line padding = title's 16pt
        tv.drawsBackground = true
        applyTheme(tv)
        tv.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tv = scrollView.documentView as! NSTextView
        applyTheme(tv)
        // Only replace the text when the note changes externally (e.g. note selection changed),
        // NOT when the user is actively typing (which would clobber the cursor position).
        guard !context.coordinator.isEditing else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    private func applyTheme(_ tv: NSTextView) {
        let bg = NSColor(theme.cardBgNormal)
        tv.backgroundColor = bg
        tv.enclosingScrollView?.backgroundColor = bg
        tv.textColor = .labelColor
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        /// True while the user is actively editing — prevents updateNSView from resetting text.
        var isEditing: Bool = false

        init(_ p: NoteTextEditor) { parent = p }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            isEditing = true
            parent.text = tv.string
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }
    }
}

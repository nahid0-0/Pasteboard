import SwiftUI
import AppKit

struct ClipItemRow: View, Equatable {
    let clip: ClipType
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    
    @State private var isHovering = false
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    
    static func == (lhs: ClipItemRow, rhs: ClipItemRow) -> Bool {
        lhs.clip.id == rhs.clip.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.clip.isPinned == rhs.clip.isPinned
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Top: source icon + content preview
                HStack(alignment: .center, spacing: 8) {
                    if let icon = clip.sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    
                    contentPreview
                    
                    Spacer(minLength: 4)
                    
                    if isHovering {
                        Button(action: { onCopy() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                    
                    if clip.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Bottom: metadata chips
                HStack(spacing: 6) {
                    // Time chip
                    metadataChip(
                        icon: "clock",
                        text: Self.relativeDateFormatter.localizedString(for: clip.createdAt, relativeTo: Date())
                    )
                    
                    // Type chip
                    metadataChip(
                        icon: typeIcon,
                        text: clip.dataType.rawValue
                    )
                    
                    // Size chip
                    metadataChip(
                        icon: "internaldrive",
                        text: formatBytes(clip.dataSize)
                    )
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.secondary.opacity(0.18) : (isHovering ? Color.secondary.opacity(0.06) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Type icon
    
    private var typeIcon: String {
        switch clip.dataType {
        case .plainText: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .stack: return "square.stack.3d.up.fill"
        }
    }
    
    // MARK: - Metadata Chip
    
    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundColor(.secondary)
    }
    
    // MARK: - Content Preview
    
    @ViewBuilder
    private var contentPreview: some View {
        switch clip {
        case .text(let textClip):
            Text(String(textClip.text.prefix(200)))
                .lineLimit(2)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
        case .image(let imageClip):
            HStack(spacing: 6) {
                if let thumbnail = imageClip.thumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .cornerRadius(4)
                        .clipped()
                }
                Text(imageClip.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
        case .file(let fileClip):
            HStack(spacing: 6) {
                if fileClip.isSingleFile {
                    Image(nsImage: fileClip.cachedFileIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                Text(fileClip.fileName)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
        case .stack(let set):
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 16))
                        .foregroundColor(set.isAccepting ? .accentColor : .secondary)
                        .frame(width: 24, height: 24)
                    if set.isAccepting {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 10, y: -10)
                    }
                }
                Text("Stack (\(set.itemCount) items)")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        Self.byteFormatter.string(fromByteCount: Int64(bytes))
    }
}

import SwiftUI
import AppKit

struct ClipItemRow: View, Equatable {
    let clip: ClipType
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    
    @State private var isHovering = false
    
    static func == (lhs: ClipItemRow, rhs: ClipItemRow) -> Bool {
        lhs.clip.id == rhs.clip.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.clip.isPinned == rhs.clip.isPinned
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                // Source app icon
                if let icon = clip.sourceAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                
                // Content preview
                contentPreview
                
                Spacer()
                
                // Data type badge
                Text(clip.dataType.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
                
                // Copy button (appears on hover)
                if isHovering {
                    Button(action: {
                        onCopy()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
                
                // Pin indicator
                if clip.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        switch clip {
        case .text(let textClip):
            Text(String(textClip.text.prefix(200)))
                .lineLimit(2)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
        case .image(let imageClip):
            HStack(spacing: 8) {
                if let thumbnail = imageClip.thumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                
                Text(imageClip.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
        case .file(let fileClip):
            HStack(spacing: 8) {
                Image(nsImage: fileClip.cachedFileIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(fileClip.fileName)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(formatBytes(Int(fileClip.fileSize)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

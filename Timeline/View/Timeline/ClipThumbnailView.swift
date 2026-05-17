import SwiftUI
import AppKit

enum ClickKind {
    case normal
    case toggle    // ⌘
    case extend    // ⇧
}

struct ClipThumbnailView: View {
    let clip: MediaClip
    let tint: Color
    var size: CGFloat = 56
    var isSelected: Bool = false
    var isFavorite: Bool = false
    var onClick: ((ClickKind) -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil

    @State private var cgImage: CGImage?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var sizeBucket: Int {
        if size <= 72 { return 256 }
        if size <= 160 { return 512 }
        return 1024
    }

    var body: some View {
        VStack(spacing: 3) {
            thumbBox
            Text(Self.timeFormatter.string(from: clip.captureDate))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? tint : .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .help(tooltip)
        .contentShape(Rectangle())
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            let kind: ClickKind
            if mods.contains(.command) { kind = .toggle }
            else if mods.contains(.shift) { kind = .extend }
            else { kind = .normal }
            onClick?(kind)
        }
        .contextMenu {
            Button(isFavorite ? "取消红心" : "加红心", systemImage: isFavorite ? "heart.slash" : "heart") {
                onToggleFavorite?()
            }
            Divider()
            Button("在 Finder 中显示", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.activateFileViewerSelecting(clip.urls)
            }
        }
        .task(id: clip.id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.18))

            if let cgImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: clip.kind.isPair ? "photo.stack" : "photo")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isSelected ? tint : tint.opacity(0.55),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        .overlay(alignment: .topLeading) {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(3)
                    .background(.thinMaterial, in: Circle())
                    .offset(x: -4, y: -4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if clip.kind.isPair {
                Text("RAW+JPG")
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: 4, y: -4)
            }
        }
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .shadow(color: isSelected ? tint.opacity(0.35) : .clear, radius: 4)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private func loadThumbnail() async {
        let image = await ThumbnailLoader.shared.thumbnail(for: clip.displayURL, sizeBucket: sizeBucket)
        if !Task.isCancelled {
            cgImage = image
        }
    }

    private var tooltip: String {
        var lines: [String] = [clip.displayName]
        lines.append(clip.captureDate.formatted(date: .abbreviated, time: .standard))
        if let f = clip.metadata.focalLengthDisplay { lines.append(f) }
        var settings: [String] = []
        if let a = clip.metadata.apertureDisplay { settings.append(a) }
        if let s = clip.metadata.shutterDisplay { settings.append(s) }
        if let i = clip.metadata.isoDisplay { settings.append(i) }
        if !settings.isEmpty { lines.append(settings.joined(separator: " · ")) }
        if let cam = clip.metadata.cameraModel { lines.append(cam) }
        return lines.joined(separator: "\n")
    }
}

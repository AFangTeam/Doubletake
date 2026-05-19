import SwiftUI

/// 浮在预览图左上角的半透明 EXIF 信息卡。
/// AB 对比时显示在每张图各自的左上角，方便一眼看清差异。
/// 字段由 `PreviewOverlaySettings` 控制开关。
///
/// `scale`：在 ImageRenderer 高分输出（7680px PNG）下整体放大字号 / 圆角 / 阴影。
/// `diffWith`：另一侧 clip 的 metadata。**不为 nil 时**，每个 EXIF 字段会
/// 跟另一侧逐项比较，不同的字段染黄色 + 微 glow，一致的保持白色。AB 实时预览
/// 和保存的对比图都用这个，让"哪些参数不同"一秒锁定。
struct ExifOverlayBadge: View {
    let clip: MediaClip
    let settings: PreviewOverlaySettings
    var sideLabel: String? = nil
    var sideTint: Color = .accentColor
    var scale: CGFloat = 1.0
    /// 另一侧 metadata；nil = 不做 diff
    var diffWith: ExifMetadata? = nil

    var body: some View {
        if !settings.enabled || isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 8 * scale) {
                if let sideLabel {
                    Text(sideLabel)
                        .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(sideTint.opacity(0.78), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5 * scale))
                        .shadow(color: .black.opacity(0.35), radius: 4 * scale, y: 1 * scale)
                }

                VStack(alignment: .leading, spacing: 3 * scale) {
                    if let chunks = topLineChunks() {
                        chunkLine(chunks, kind: .secondary)
                    }
                    if let chunks = primaryChunks() {
                        chunkLine(chunks, kind: .primary)
                    }
                    if settings.showCaptureDate {
                        Text(clip.captureDate.formatted(date: .abbreviated, time: .standard))
                            .font(LineKind.secondary.font(scale: scale))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if settings.showFilename {
                        Text(clip.displayName)
                            .font(LineKind.secondary.font(scale: scale))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 2 * scale, y: 1 * scale)
            }
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 7 * scale)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                        .fill(.black.opacity(0.32))
                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5 * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8 * scale, y: 3 * scale)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("EXIF 信息"))
        }
    }

    // MARK: - 行渲染

    @ViewBuilder
    private func chunkLine(_ chunks: [Chunk], kind: LineKind) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { idx, chunk in
                if idx > 0 {
                    Text("  ·  ")
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(chunk.text)
                    .foregroundStyle(chunk.highlighted ? Color.yellow : .white)
                    .shadow(
                        color: chunk.highlighted ? .yellow.opacity(0.6) : .clear,
                        radius: 3 * scale
                    )
            }
        }
        .font(kind.font(scale: scale))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    // MARK: - 分块构造

    private var isEmpty: Bool {
        topLineChunks() == nil
            && primaryChunks() == nil
            && !settings.showCaptureDate
            && !settings.showFilename
    }

    private func topLineChunks() -> [Chunk]? {
        guard settings.showCamera || settings.showLens else { return nil }
        var out: [Chunk] = []
        if settings.showCamera, let cam = clip.metadata.cameraModel {
            let other = diffWith?.cameraModel
            out.append(Chunk(text: cam, highlighted: diffSet(cam, other)))
        }
        if settings.showLens, let lens = clip.metadata.lensModel {
            let other = diffWith?.lensModel
            out.append(Chunk(text: lens, highlighted: diffSet(lens, other)))
        }
        return out.isEmpty ? nil : out
    }

    private func primaryChunks() -> [Chunk]? {
        var out: [Chunk] = []
        if settings.showFocalLength, let v = clip.metadata.focalLengthDisplay {
            out.append(Chunk(text: v, highlighted: diffSet(v, diffWith?.focalLengthDisplay)))
        }
        if settings.showAperture, let v = clip.metadata.apertureDisplay {
            out.append(Chunk(text: v, highlighted: diffSet(v, diffWith?.apertureDisplay)))
        }
        if settings.showShutter, let v = clip.metadata.shutterDisplay {
            out.append(Chunk(text: v, highlighted: diffSet(v, diffWith?.shutterDisplay)))
        }
        if settings.showISO, let v = clip.metadata.isoDisplay {
            out.append(Chunk(text: v, highlighted: diffSet(v, diffWith?.isoDisplay)))
        }
        return out.isEmpty ? nil : out
    }

    /// 是否要把这个 chunk 高亮为"差异"。
    /// - 没启用 diff（diffWith == nil）→ 永远 false
    /// - 另一侧没有该字段 → 不算差异（只一侧拍到的元数据不能算"不同"）
    /// - 都有但不相等 → 算差异
    private func diffSet(_ mine: String?, _ other: String?) -> Bool {
        guard diffWith != nil else { return false }
        guard let mine, let other else { return false }
        return mine != other
    }

    // MARK: - 类型

    private struct Chunk {
        let text: String
        let highlighted: Bool
    }

    private enum LineKind {
        case primary, secondary
        func font(scale: CGFloat) -> Font {
            switch self {
            case .primary:
                return .system(size: 12.5 * scale, weight: .semibold, design: .monospaced)
            case .secondary:
                return .system(size: 11 * scale, weight: .regular, design: .default)
            }
        }
    }
}

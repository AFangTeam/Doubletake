import SwiftUI

/// 浮在预览图左上角的半透明 EXIF 信息卡。
/// AB 对比时显示在每张图各自的左上角，方便一眼看清差异。
/// 字段由 `PreviewOverlaySettings` 控制开关。
/// `scale` 用于在 ImageRenderer 高分输出（7680px PNG）下整体放大字号 / 圆角 / 阴影。
struct ExifOverlayBadge: View {
    let clip: MediaClip
    let settings: PreviewOverlaySettings
    /// AB 对比时显示侧别角标（"A" / "B"），单图预览传 nil。
    var sideLabel: String? = nil
    /// 角标底色（A 蓝、B 橙）
    var sideTint: Color = .accentColor
    /// 整体视觉缩放倍数：屏幕上传 1.0，截图 PNG 里传 2.5 让字号、圆角、阴影一起放大。
    var scale: CGFloat = 1.0

    private var lines: [LineSpec] {
        var out: [LineSpec] = []
        // 顶部第一行：相机+镜头摘要（合并显示，最显眼）
        if settings.showCamera || settings.showLens {
            var seg: [String] = []
            if settings.showCamera, let cam = clip.metadata.cameraModel { seg.append(cam) }
            if settings.showLens, let lens = clip.metadata.lensModel { seg.append(lens) }
            if !seg.isEmpty {
                out.append(.init(text: seg.joined(separator: " · "), kind: .secondary))
            }
        }

        // 主参数（焦段 · 光圈 · 快门 · ISO）合并成一行 monospaced，最常对比
        var primary: [String] = []
        if settings.showFocalLength, let f = clip.metadata.focalLengthDisplay {
            primary.append(f)
        }
        if settings.showAperture, let a = clip.metadata.apertureDisplay {
            primary.append(a)
        }
        if settings.showShutter, let s = clip.metadata.shutterDisplay {
            primary.append(s)
        }
        if settings.showISO, let iso = clip.metadata.isoDisplay {
            primary.append(iso)
        }
        if !primary.isEmpty {
            out.append(.init(text: primary.joined(separator: "  ·  "), kind: .primary))
        }

        if settings.showCaptureDate {
            out.append(.init(
                text: clip.captureDate.formatted(date: .abbreviated, time: .standard),
                kind: .secondary
            ))
        }
        if settings.showFilename {
            out.append(.init(text: clip.displayName, kind: .secondary))
        }
        return out
    }

    var body: some View {
        if !settings.enabled || lines.isEmpty {
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
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(line.kind.font(scale: scale))
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

    private struct LineSpec {
        var text: String
        var kind: Kind

        enum Kind {
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
}

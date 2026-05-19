import SwiftUI

/// 把 ExifOverlayBadge 已经定型的"玻璃 + 软阴影 + 微描边"封装成 ViewModifier。
/// 顶 / 底栏 / 角标 / handle 全部走这个，杜绝散落不一致的半透明实现。
///
/// 默认尺度（scale=1）适合屏幕预览的常规 UI 元素；要在 8K 截图里放大整套视觉时
/// 传 scale > 1（比如 snapShot 里传 10），所有圆角 / 描边 / 阴影一起放大。
struct GlassBackgroundModifier: ViewModifier {
    /// 圆角半径基准；最终圆角 = cornerRadius × scale
    var cornerRadius: CGFloat = 10
    /// 整体视觉缩放（描边宽度、阴影半径同步放大）
    var scale: CGFloat = 1.0
    /// 黑色不透明度底层
    var baseOpacity: Double = 0.32
    /// ultraThinMaterial 的混合透明度
    var materialOpacity: Double = 0.55

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                        .fill(.black.opacity(baseOpacity))
                    RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(materialOpacity)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5 * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8 * scale, y: 3 * scale)
    }
}

/// 同上但走 Capsule 形（用于 chip / 徽标 / 手柄）
struct GlassCapsuleModifier: ViewModifier {
    var scale: CGFloat = 1.0
    var baseOpacity: Double = 0.32
    var materialOpacity: Double = 0.55

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(baseOpacity))
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(materialOpacity)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6 * scale)
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8 * scale, y: 3 * scale)
    }
}

extension View {
    /// 玻璃质感圆角矩形背景（房子风格）
    func glassBackground(cornerRadius: CGFloat = 10, scale: CGFloat = 1.0) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, scale: scale))
    }

    /// 玻璃质感胶囊背景
    func glassCapsule(scale: CGFloat = 1.0) -> some View {
        modifier(GlassCapsuleModifier(scale: scale))
    }
}

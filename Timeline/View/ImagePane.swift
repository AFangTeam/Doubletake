import SwiftUI

/// 单图显示面板。
/// - 第一阶段：用 ThumbnailLoader 的 2048 px 缩略图秒出图（即便 RAW 也很快）。
/// - 第二阶段：后台用 FullImageLoader 直接 ImageIO 解码出 6144 px 高分版本，
///   覆盖第一阶段缩略图。这样放大 / pixel-peep 时看到的不是被拉伸的缩略图，
///   而是来自原图的真实像素，不再发糊。
/// - zoom / pan 统一作用在最终显示的 CGImage 上，SwiftUI Image 高质量插值。
struct ImagePane: View {
    let url: URL
    let zoom: Double
    let pan: CGSize
    var background: Color = .black
    /// 第一阶段缩略图的尺寸桶。默认 2048。
    var thumbnailBucket: Int = 2048
    /// 高分图的最长边像素，默认 6144（够 2-3x 放大依然锐利）。
    var fullMaxPixel: Int = 6144

    @State private var thumbImage: CGImage?
    @State private var fullImage: CGImage?
    @State private var loadingURL: URL?

    /// 优先 full，其次 thumb。
    private var displayImage: CGImage? { fullImage ?? thumbImage }

    var body: some View {
        ZStack {
            background

            if let img = displayImage {
                // pan 是调用方算好的"点(pt)"位移；ABCompareView / SinglePreviewView
                // 负责把"fraction of pane size"转换成 pt 再传进来。
                // 这样不管 live 还是 ImageRenderer 的高分快照，pan 都按对应 pane 尺寸
                // 重新算 pt 偏移，跨尺寸不会失真。
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(pan)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .clipped()
        .task(id: url) {
            await loadBoth(url: url)
        }
    }

    private func loadBoth(url: URL) async {
        loadingURL = url
        thumbImage = nil
        fullImage = nil

        // 阶段 1：缩略图先出图（已被 ThumbnailLoader 用磁盘缓存，瞬时返回）
        let thumb = await ThumbnailLoader.shared.thumbnail(for: url, sizeBucket: thumbnailBucket)
        guard !Task.isCancelled, loadingURL == url else { return }
        if fullImage == nil {
            thumbImage = thumb
        }

        // 阶段 2：后台直接 ImageIO 解码高分图，避免缩略图二次压缩造成的模糊
        let full = await FullImageLoader.shared.image(for: url, maxPixel: fullMaxPixel)
        guard !Task.isCancelled, loadingURL == url else { return }
        if let full {
            fullImage = full
        }
    }
}

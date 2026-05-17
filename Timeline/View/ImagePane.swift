import SwiftUI

/// 单图显示面板：通过 ThumbnailLoader (QuickLook) 取一个 2048px 预览，
/// 应用统一的 zoom/pan 变换。RAW 也走 QuickLook，所以即便是 ARW/CR3 也很快。
struct ImagePane: View {
    let url: URL
    let zoom: Double
    let pan: CGSize
    var background: Color = .black
    /// 预览尺寸桶。默认 2048 px，足以撑到 ~3x 缩放仍清晰。
    var sizeBucket: Int = 2048

    @State private var cgImage: CGImage?
    @State private var loadingURL: URL?

    var body: some View {
        ZStack {
            background

            if let img = cgImage {
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
            await load(url: url)
        }
    }

    private func load(url: URL) async {
        loadingURL = url
        let img = await ThumbnailLoader.shared.thumbnail(for: url, sizeBucket: sizeBucket)
        if !Task.isCancelled, loadingURL == url {
            cgImage = img
        }
    }
}

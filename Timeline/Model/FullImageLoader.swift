import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 预览/AB 对比专用的"高分图加载器"。
///
/// 与 `ThumbnailLoader` 的区别：
/// - ThumbnailLoader 出 2048px 的 JPEG-压缩缩略图，速度快但放大后会糊。
/// - FullImageLoader 直接用 ImageIO `kCGImageSourceCreateThumbnailFromImageAlways`
///   按用户要求的 maxPixel 解码原始图像（JPG 走原文件，RAW 走 ImageIO 的 RAW 引擎），
///   不二次 JPEG 压缩、不落盘，只在内存里 LRU 缓存少数几张。
/// - 用 6144 px 这一档足够 2-3 倍放大依然锐利；继续放大也是原始解码出来的结果，
///   不再是 2048 拉伸而来的模糊像素。
actor FullImageLoader {
    static let shared = FullImageLoader()

    private struct Key: Hashable {
        let urlString: String
        let maxPixel: Int
    }

    private var cache: [(key: Key, image: CGImage)] = []
    private var inflight: [Key: Task<CGImage?, Never>] = [:]
    /// 只缓存最近的几张 —— 高分图很占内存（一张 6144x4096 8-bit 大约 100 MB）
    private let cacheLimit = 4

    /// 加载该 URL 的高分图。`maxPixel` 是较长边的最大像素数，默认 6144。
    /// 同一 url+maxPixel 的并发请求会合并。
    func image(for url: URL, maxPixel: Int = 6144) async -> CGImage? {
        let key = Key(urlString: url.absoluteString, maxPixel: maxPixel)

        if let hit = cache.first(where: { $0.key == key }) {
            // LRU 触发：移到末尾
            cache.removeAll { $0.key == key }
            cache.append(hit)
            return hit.image
        }
        if let task = inflight[key] { return await task.value }

        let task = Task<CGImage?, Never>.detached(priority: .userInitiated) {
            Self.decode(url: url, maxPixel: maxPixel)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil

        if let img = result {
            cache.append((key, img))
            while cache.count > cacheLimit {
                cache.removeFirst()
            }
        }
        return result
    }

    func purge() {
        cache.removeAll(keepingCapacity: false)
    }

    /// 解码到原图**完整**分辨率，**并应用 EXIF 方向标签**。
    /// 仅用于"保存对比"等一次性高质量出图。
    ///
    /// 走 thumbnail API（而不是 `CGImageSourceCreateImageAtIndex`），因为只有
    /// thumbnail 这一路支持 `kCGImageSourceCreateThumbnailWithTransform`。
    /// 竖拍照片在文件里其实是横向像素 + EXIF Orientation = 6/8，没这个标志会被
    /// 当横图画出来。
    /// maxPixel 设到 32768 —— 实际上等于"无 cap"，现实里没相机突破这个数。
    func fullResolutionImage(for url: URL) async -> CGImage? {
        let result = await Task<CGImage?, Never>.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 32768
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
        return result
    }

    private static func decode(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

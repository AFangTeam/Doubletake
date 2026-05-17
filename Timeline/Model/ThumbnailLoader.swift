import Foundation
import CoreGraphics
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// 缩略图加载器：内存缓存 + 磁盘缓存 + QLThumbnailGenerator 即时生成
/// - 调用方传 `sizeBucket`（推荐 256 / 512 / 1024），同一 url+bucket 多次请求合并
/// - 返回 CGImage，调用方用 `Image(decorative:scale:)` 包成 SwiftUI Image 显示
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private struct Key: Hashable {
        let urlString: String
        let sizeBucket: Int
    }

    private var memCache: [Key: CGImage] = [:]
    private var inflight: [Key: Task<CGImage?, Never>] = [:]

    private let diskCacheDir: URL
    private let memCacheLimit = 600

    init() {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "Timeline"
        let dir = base.appendingPathComponent(bundleID).appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskCacheDir = dir
    }

    func thumbnail(for url: URL, sizeBucket: Int) async -> CGImage? {
        let key = Key(urlString: url.absoluteString, sizeBucket: sizeBucket)
        if let cached = memCache[key] { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<CGImage?, Never> { [diskCacheDir] in
            // 1. 试读磁盘缓存
            let diskURL = ThumbnailLoader.diskPath(for: key, in: diskCacheDir)
            if FileManager.default.fileExists(atPath: diskURL.path) {
                if let cg = ThumbnailLoader.loadCGImage(from: diskURL) {
                    return cg
                }
            }
            // 2. QuickLook 生成
            let pixelSize = CGSize(width: sizeBucket, height: sizeBucket)
            let req = QLThumbnailGenerator.Request(
                fileAt: url,
                size: pixelSize,
                scale: 1.0,
                representationTypes: .thumbnail
            )
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
                let cg = rep.cgImage
                // 3. 落盘
                ThumbnailLoader.writeJPEG(cg, to: diskURL)
                return cg
            } catch {
                // 兜底：直接用 ImageIO 缩放原图
                return ThumbnailLoader.downsampleViaImageIO(url: url, maxPixel: sizeBucket)
            }
        }

        inflight[key] = task
        let result = await task.value
        inflight[key] = nil

        if let cg = result {
            if memCache.count >= memCacheLimit {
                memCache.removeAll(keepingCapacity: true)
            }
            memCache[key] = cg
        }
        return result
    }

    /// 清空内存缓存（不动磁盘）
    func purgeMemory() {
        memCache.removeAll(keepingCapacity: false)
    }

    // MARK: - 静态辅助（不持有 actor 状态）

    private static func diskPath(for key: Key, in dir: URL) -> URL {
        let hash = stableHash(key.urlString)
        return dir.appendingPathComponent("\(hash)_\(key.sizeBucket).jpg")
    }

    private static func stableHash(_ s: String) -> String {
        // 16 进制 64-bit FNV-1a，足够用作缓存键，不需要密码学强度
        var hash: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16, uppercase: false)
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    private static func downsampleViaImageIO(url: URL, maxPixel: Int) -> CGImage? {
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

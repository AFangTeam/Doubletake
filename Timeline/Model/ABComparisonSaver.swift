import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 一次 AB 对比导出的结果。
struct ABComparisonResult: Sendable {
    var outputFolder: URL
    var copiedFiles: Int
    var wroteComparisonImage: Bool
    var wroteOriginalComparisonImage: Bool
    var errors: [String]
}

/// 把一次 AB 对比（两张原图 + 当前画面对比截图 + 未调整状态的对比截图）写到
/// 一个用户命名的文件夹。
/// - `comparison.png`：用户当下看到的画面（带 zoom、⌘+拖动的位移）
/// - `original_comparison.png`：两张图未经任何调整，平摆左右（zoom=1，无位移）
enum ABComparisonSaver {
    nonisolated static func save(
        name rawName: String,
        parentFolder: URL,
        clipA: MediaClip,
        clipB: MediaClip,
        comparisonImage: CGImage?,
        originalComparisonImage: CGImage?,
        infoJSON: Data?
    ) throws -> ABComparisonResult {
        let fm = FileManager.default
        let sanitized = sanitizeFolderName(rawName)
        let outDir = uniqueFolder(in: parentFolder, baseName: sanitized)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        var copied = 0
        var errors: [String] = []
        var wroteImage = false
        var wroteOriginal = false

        copyClip(clipA, prefix: "A", into: outDir, fm: fm, copied: &copied, errors: &errors)
        copyClip(clipB, prefix: "B", into: outDir, fm: fm, copied: &copied, errors: &errors)

        if let cg = comparisonImage {
            let pngURL = outDir.appendingPathComponent("comparison.png")
            if writePNG(cg, to: pngURL) {
                wroteImage = true
            } else {
                errors.append("comparison.png 写盘失败")
            }
        }

        if let cg = originalComparisonImage {
            let pngURL = outDir.appendingPathComponent("original_comparison.png")
            if writePNG(cg, to: pngURL) {
                wroteOriginal = true
            } else {
                errors.append("original_comparison.png 写盘失败")
            }
        }

        if let json = infoJSON {
            let jsonURL = outDir.appendingPathComponent("comparison-info.json")
            do {
                try json.write(to: jsonURL)
            } catch {
                errors.append("comparison-info.json: \(error.localizedDescription)")
            }
        }

        return ABComparisonResult(
            outputFolder: outDir,
            copiedFiles: copied,
            wroteComparisonImage: wroteImage,
            wroteOriginalComparisonImage: wroteOriginal,
            errors: errors
        )
    }

    nonisolated private static func copyClip(
        _ clip: MediaClip,
        prefix: String,
        into dir: URL,
        fm: FileManager,
        copied: inout Int,
        errors: inout [String]
    ) {
        for url in clip.urls {
            let base = url.lastPathComponent
            let dest = dir.appendingPathComponent("\(prefix)_\(base)")
            if fm.fileExists(atPath: dest.path) {
                continue
            }
            do {
                try fm.copyItem(at: url, to: dest)
                copied += 1
            } catch {
                errors.append("\(prefix)_\(base): \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    nonisolated private static func sanitizeFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 替换文件系统不友好字符
        let bad = CharacterSet(charactersIn: "/\\:?\"<>|\0")
        let cleaned = trimmed.unicodeScalars
            .map { bad.contains($0) ? "-" : Character($0) }
            .map { String($0) }
            .joined()
        let fallback = cleaned.isEmpty ? defaultName() : cleaned
        // 限长
        return String(fallback.prefix(100))
    }

    nonisolated private static func defaultName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "AB-对比-\(f.string(from: Date()))"
    }

    nonisolated private static func uniqueFolder(in parent: URL, baseName: String) -> URL {
        let fm = FileManager.default
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var idx = 2
        while idx < 1000 {
            candidate = parent.appendingPathComponent("\(baseName) (\(idx))", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            idx += 1
        }
        return candidate
    }
}

/// 一份给 `comparison-info.json` 的最小结构 —— 记录对比当下的视图参数和两张 EXIF 摘要，
/// 后续若想复刻这一画面可以读它。
struct ABComparisonInfo: Codable, Sendable {
    var savedAtEpoch: Double
    var mode: String                 // "split" / "curtain"
    var zoom: Double
    var panAX: Double
    var panAY: Double
    var panBX: Double
    var panBY: Double
    var curtainSplit: Double
    var sourceA: String              // "JPG" / "RAW"
    var sourceB: String
    var clipASummary: ClipSummary
    var clipBSummary: ClipSummary

    struct ClipSummary: Codable, Sendable {
        var fileName: String
        var captureDateISO: String?
        var focalLength: String?
        var aperture: String?
        var shutter: String?
        var iso: String?
        var camera: String?
        var lens: String?

        static func from(_ clip: MediaClip) -> ClipSummary {
            let iso = clip.metadata.captureDate.map {
                ISO8601DateFormatter().string(from: $0)
            }
            return ClipSummary(
                fileName: clip.displayName,
                captureDateISO: iso,
                focalLength: clip.metadata.focalLengthDisplay,
                aperture: clip.metadata.apertureDisplay,
                shutter: clip.metadata.shutterDisplay,
                iso: clip.metadata.isoDisplay,
                camera: clip.metadata.cameraModel,
                lens: clip.metadata.lensModel
            )
        }
    }
}

import Foundation

struct FavoritesExportResult: Sendable {
    var destinationFolder: URL
    var copiedFiles: Int
    var skipped: Int
    var errors: [String]
}

enum FavoritesExporter {
    /// 把收藏夹 clips 的所有 URL 拷贝到目标文件夹（扁平结构，文件名前缀 A_/B_）。
    /// 调用方负责保证目标文件夹存在且可写（已 startAccessing security scope）。
    nonisolated static func export(
        clips: [MediaClip],
        to destination: URL
    ) throws -> FavoritesExportResult {
        let fm = FileManager.default
        let dirName = "Timeline-Favorites-\(timestampString())"
        let outDir = destination.appendingPathComponent(dirName, isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        var copied = 0
        var skipped = 0
        var errors: [String] = []

        for clip in clips {
            let prefix = clip.track == .a ? "A" : "B"
            for url in clip.urls {
                let base = url.lastPathComponent
                let destName = "\(prefix)_\(base)"
                let destURL = outDir.appendingPathComponent(destName)
                if fm.fileExists(atPath: destURL.path) {
                    skipped += 1
                    continue
                }
                do {
                    try fm.copyItem(at: url, to: destURL)
                    copied += 1
                } catch {
                    errors.append("\(base): \(error.localizedDescription)")
                }
            }
        }

        return FavoritesExportResult(
            destinationFolder: outDir,
            copiedFiles: copied,
            skipped: skipped,
            errors: errors
        )
    }

    nonisolated private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

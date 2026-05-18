import Foundation

nonisolated struct MediaClip: Identifiable, Hashable, Sendable {
    let id: ClipID
    let track: Track
    let urls: [URL]
    let displayURL: URL
    let captureDate: Date
    let kind: ClipKind
    let metadata: ExifMetadata
    let totalBytes: Int64

    var displayName: String { displayURL.lastPathComponent }

    var allExtensions: String {
        urls.map { $0.pathExtension.uppercased() }.joined(separator: "+")
    }

    var jpgURL: URL? {
        switch kind {
        case .pair(let jpg, _): return jpg
        case .single(let fmt): return fmt.isJPGFamily ? urls.first : nil
        }
    }

    var rawURL: URL? {
        switch kind {
        case .pair(_, let raw): return raw
        case .single(let fmt): return fmt.isRAW ? urls.first : nil
        }
    }

    var hasBothSources: Bool { jpgURL != nil && rawURL != nil }

    func url(for source: ImageSource) -> URL {
        switch source {
        case .jpg: return jpgURL ?? rawURL ?? displayURL
        case .raw: return rawURL ?? jpgURL ?? displayURL
        }
    }

    /// 单图预览默认用哪个源：优先 JPG（解码快、色彩贴近相机出片）
    var defaultSource: ImageSource {
        jpgURL != nil ? .jpg : .raw
    }

    /// AB 对比默认用哪个源：优先 RAW（要 pixel-peep 细节、判断画质差异）
    var abDefaultSource: ImageSource {
        rawURL != nil ? .raw : .jpg
    }
}

nonisolated enum ImageSource: String, CaseIterable, Sendable, Hashable {
    case jpg = "JPG"
    case raw = "RAW"
}

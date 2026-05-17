import Foundation

nonisolated struct ClipID: Hashable, Sendable, CustomStringConvertible {
    let track: Track
    let stableKey: String

    var description: String { "\(track.rawValue):\(stableKey)" }

    /// 序列化为字符串，用于 Codable 持久化（如收藏列表）
    var serialized: String { "\(track.rawValue):\(stableKey)" }

    init(track: Track, stableKey: String) {
        self.track = track
        self.stableKey = stableKey
    }

    init?(serialized s: String) {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let rawTrack = String(s[s.startIndex..<colon])
        let key = String(s[s.index(after: colon)..<s.endIndex])
        guard let track = Track(rawValue: rawTrack) else { return nil }
        self.track = track
        self.stableKey = key
    }
}

nonisolated enum ClipKind: Hashable, Sendable {
    case single(format: PhotoFormat)
    case pair(jpgURL: URL, rawURL: URL)

    var isPair: Bool {
        if case .pair = self { return true }
        return false
    }
}

nonisolated enum PhotoFormat: String, Hashable, Sendable {
    case jpg
    case heic
    case png
    case tiff
    case raw

    static func detect(extension ext: String) -> PhotoFormat? {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpg
        case "heic", "heif": return .heic
        case "png": return .png
        case "tif", "tiff": return .tiff
        case "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "dng", "orf", "pef", "srw", "rwl", "srf":
            return .raw
        default: return nil
        }
    }

    var isJPGFamily: Bool {
        switch self {
        case .jpg, .heic: true
        default: false
        }
    }

    var isRAW: Bool { self == .raw }
}

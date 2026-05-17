import Foundation

enum BookmarkError: Error, LocalizedError {
    case resolutionFailed
    case stale

    var errorDescription: String? {
        switch self {
        case .resolutionFailed: "无法访问之前保存的文件夹（书签已失效）"
        case .stale: "文件夹位置已变更，请重新选择"
        }
    }
}

struct ResolvedFolder {
    let url: URL
    let isStale: Bool
}

enum BookmarkStore {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> ResolvedFolder {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedFolder(url: url, isStale: isStale)
    }
}

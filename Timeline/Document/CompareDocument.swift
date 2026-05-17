import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let timelineCompare = UTType(exportedAs: "com.ericfang.timeline.compare")
}

struct CompareDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.timelineCompare]
    static let writableContentTypes: [UTType] = [.timelineCompare]

    var payload: CompareDocumentPayload
    var bookmarkA: Data?
    var bookmarkB: Data?

    init() {
        self.payload = .empty
        self.bookmarkA = nil
        self.bookmarkB = nil
    }

    init(configuration: ReadConfiguration) throws {
        guard let root = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if let jsonWrapper = root["compare.json"], let data = jsonWrapper.regularFileContents {
            self.payload = try JSONDecoder().decode(CompareDocumentPayload.self, from: data)
        } else {
            self.payload = .empty
        }

        let bookmarks = root["bookmarks"]?.fileWrappers
        self.bookmarkA = bookmarks?["A.bookmark"]?.regularFileContents
        self.bookmarkB = bookmarks?["B.bookmark"]?.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(payload)
        let jsonWrapper = FileWrapper(regularFileWithContents: jsonData)
        jsonWrapper.preferredFilename = "compare.json"

        var bookmarkWrappers: [String: FileWrapper] = [:]
        if let a = bookmarkA {
            let w = FileWrapper(regularFileWithContents: a)
            w.preferredFilename = "A.bookmark"
            bookmarkWrappers["A.bookmark"] = w
        }
        if let b = bookmarkB {
            let w = FileWrapper(regularFileWithContents: b)
            w.preferredFilename = "B.bookmark"
            bookmarkWrappers["B.bookmark"] = w
        }

        var rootWrappers: [String: FileWrapper] = ["compare.json": jsonWrapper]
        if !bookmarkWrappers.isEmpty {
            let bookmarksDir = FileWrapper(directoryWithFileWrappers: bookmarkWrappers)
            bookmarksDir.preferredFilename = "bookmarks"
            rootWrappers["bookmarks"] = bookmarksDir
        }

        return FileWrapper(directoryWithFileWrappers: rootWrappers)
    }

    func bookmark(for track: Track) -> Data? {
        switch track {
        case .a: bookmarkA
        case .b: bookmarkB
        }
    }

    mutating func setBookmark(_ data: Data?, for track: Track) {
        switch track {
        case .a: bookmarkA = data
        case .b: bookmarkB = data
        }
    }

    func config(for track: Track) -> TrackConfig {
        switch track {
        case .a: payload.trackA
        case .b: payload.trackB
        }
    }

    mutating func setConfig(_ config: TrackConfig, for track: Track) {
        switch track {
        case .a: payload.trackA = config
        case .b: payload.trackB = config
        }
    }
}

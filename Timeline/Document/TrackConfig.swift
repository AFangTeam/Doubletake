import Foundation

nonisolated enum Track: String, Codable, CaseIterable, Hashable, Sendable {
    case a
    case b

    var displayLabel: String {
        switch self {
        case .a: "A"
        case .b: "B"
        }
    }
}

nonisolated struct TrackConfig: Codable, Hashable, Sendable {
    var displayName: String
    var timeOffsetSeconds: Double
    var folderBookmarkRelativePath: String?

    static func empty(track: Track) -> TrackConfig {
        TrackConfig(
            displayName: "机型 \(track.displayLabel)",
            timeOffsetSeconds: 0,
            folderBookmarkRelativePath: nil
        )
    }
}

nonisolated struct ViewStateSnapshot: Codable, Hashable, Sendable {
    var pxPerSecond: Double
    var scrollAnchorEpoch: Double?

    static let initial = ViewStateSnapshot(pxPerSecond: 5.0, scrollAnchorEpoch: nil)
}

nonisolated struct CompareDocumentPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var trackA: TrackConfig
    var trackB: TrackConfig
    var clipNotes: [String: String]
    var favoriteClipIDs: [String]
    var viewState: ViewStateSnapshot

    static let currentSchemaVersion = 1

    static let empty = CompareDocumentPayload(
        schemaVersion: currentSchemaVersion,
        trackA: .empty(track: .a),
        trackB: .empty(track: .b),
        clipNotes: [:],
        favoriteClipIDs: [],
        viewState: .initial
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion, trackA, trackB, clipNotes, favoriteClipIDs, viewState
    }

    init(
        schemaVersion: Int,
        trackA: TrackConfig,
        trackB: TrackConfig,
        clipNotes: [String: String],
        favoriteClipIDs: [String],
        viewState: ViewStateSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.trackA = trackA
        self.trackB = trackB
        self.clipNotes = clipNotes
        self.favoriteClipIDs = favoriteClipIDs
        self.viewState = viewState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.trackA = try c.decode(TrackConfig.self, forKey: .trackA)
        self.trackB = try c.decode(TrackConfig.self, forKey: .trackB)
        self.clipNotes = try c.decodeIfPresent([String: String].self, forKey: .clipNotes) ?? [:]
        self.favoriteClipIDs = try c.decodeIfPresent([String].self, forKey: .favoriteClipIDs) ?? []
        self.viewState = try c.decodeIfPresent(ViewStateSnapshot.self, forKey: .viewState) ?? .initial
    }
}

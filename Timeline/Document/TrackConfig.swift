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
    /// 用户是否手动改过 displayName（true → 自动 EXIF 命名不再覆盖）
    var userRenamedDisplayName: Bool

    static func empty(track: Track) -> TrackConfig {
        TrackConfig(
            displayName: "机型 \(track.displayLabel)",
            timeOffsetSeconds: 0,
            folderBookmarkRelativePath: nil,
            userRenamedDisplayName: false
        )
    }

    /// 是否仍是默认值（"机型 A" / "机型 B"），用于判定能不能自动 EXIF 命名
    var hasDefaultDisplayName: Bool {
        displayName == "机型 A" || displayName == "机型 B"
    }

    enum CodingKeys: String, CodingKey {
        case displayName, timeOffsetSeconds, folderBookmarkRelativePath, userRenamedDisplayName
    }

    init(
        displayName: String,
        timeOffsetSeconds: Double,
        folderBookmarkRelativePath: String?,
        userRenamedDisplayName: Bool = false
    ) {
        self.displayName = displayName
        self.timeOffsetSeconds = timeOffsetSeconds
        self.folderBookmarkRelativePath = folderBookmarkRelativePath
        self.userRenamedDisplayName = userRenamedDisplayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.timeOffsetSeconds = try c.decode(Double.self, forKey: .timeOffsetSeconds)
        self.folderBookmarkRelativePath = try c.decodeIfPresent(String.self, forKey: .folderBookmarkRelativePath)
        self.userRenamedDisplayName = try c.decodeIfPresent(Bool.self, forKey: .userRenamedDisplayName) ?? false
    }
}

nonisolated struct ViewStateSnapshot: Codable, Hashable, Sendable {
    var pxPerSecond: Double
    var scrollAnchorEpoch: Double?
    /// 折叠空白时段：把相邻照片间隔 > emptyGapThresholdMinutes 的"空白"压成窄缝。
    /// 默认开启，让 timeline 默认就好用；用户可在 Inspector 关掉回到线性视图。
    var compactEmptyTime: Bool
    var emptyGapThresholdMinutes: Double

    static let initial = ViewStateSnapshot(
        pxPerSecond: 5.0,
        scrollAnchorEpoch: nil,
        compactEmptyTime: true,
        emptyGapThresholdMinutes: 10
    )

    enum CodingKeys: String, CodingKey {
        case pxPerSecond, scrollAnchorEpoch, compactEmptyTime, emptyGapThresholdMinutes
    }

    init(
        pxPerSecond: Double,
        scrollAnchorEpoch: Double?,
        compactEmptyTime: Bool = true,
        emptyGapThresholdMinutes: Double = 10
    ) {
        self.pxPerSecond = pxPerSecond
        self.scrollAnchorEpoch = scrollAnchorEpoch
        self.compactEmptyTime = compactEmptyTime
        self.emptyGapThresholdMinutes = emptyGapThresholdMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pxPerSecond = try c.decode(Double.self, forKey: .pxPerSecond)
        self.scrollAnchorEpoch = try c.decodeIfPresent(Double.self, forKey: .scrollAnchorEpoch)
        self.compactEmptyTime = try c.decodeIfPresent(Bool.self, forKey: .compactEmptyTime) ?? true
        self.emptyGapThresholdMinutes = try c.decodeIfPresent(Double.self, forKey: .emptyGapThresholdMinutes) ?? 10
    }
}

/// 预览/AB 对比时，浮在图片左上角的半透明信息卡设置。
/// 用户在 Inspector 里勾选要看哪些字段。
nonisolated struct PreviewOverlaySettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var showFilename: Bool
    var showCaptureDate: Bool
    var showFocalLength: Bool
    var showAperture: Bool
    var showShutter: Bool
    var showISO: Bool
    var showCamera: Bool
    var showLens: Bool

    static let initial = PreviewOverlaySettings(
        enabled: true,
        showFilename: false,
        showCaptureDate: false,
        showFocalLength: true,
        showAperture: true,
        showShutter: true,
        showISO: true,
        showCamera: false,
        showLens: false
    )
}

nonisolated struct CompareDocumentPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var trackA: TrackConfig
    var trackB: TrackConfig
    var clipNotes: [String: String]
    var favoriteClipIDs: [String]
    var viewState: ViewStateSnapshot
    var overlaySettings: PreviewOverlaySettings
    var savedComparisons: [SavedComparison]

    static let currentSchemaVersion = 1

    static let empty = CompareDocumentPayload(
        schemaVersion: currentSchemaVersion,
        trackA: .empty(track: .a),
        trackB: .empty(track: .b),
        clipNotes: [:],
        favoriteClipIDs: [],
        viewState: .initial,
        overlaySettings: .initial,
        savedComparisons: []
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion, trackA, trackB, clipNotes, favoriteClipIDs, viewState, overlaySettings, savedComparisons
    }

    init(
        schemaVersion: Int,
        trackA: TrackConfig,
        trackB: TrackConfig,
        clipNotes: [String: String],
        favoriteClipIDs: [String],
        viewState: ViewStateSnapshot,
        overlaySettings: PreviewOverlaySettings,
        savedComparisons: [SavedComparison]
    ) {
        self.schemaVersion = schemaVersion
        self.trackA = trackA
        self.trackB = trackB
        self.clipNotes = clipNotes
        self.favoriteClipIDs = favoriteClipIDs
        self.viewState = viewState
        self.overlaySettings = overlaySettings
        self.savedComparisons = savedComparisons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.trackA = try c.decode(TrackConfig.self, forKey: .trackA)
        self.trackB = try c.decode(TrackConfig.self, forKey: .trackB)
        self.clipNotes = try c.decodeIfPresent([String: String].self, forKey: .clipNotes) ?? [:]
        self.favoriteClipIDs = try c.decodeIfPresent([String].self, forKey: .favoriteClipIDs) ?? []
        self.viewState = try c.decodeIfPresent(ViewStateSnapshot.self, forKey: .viewState) ?? .initial
        self.overlaySettings = try c.decodeIfPresent(PreviewOverlaySettings.self, forKey: .overlaySettings) ?? .initial
        self.savedComparisons = try c.decodeIfPresent([SavedComparison].self, forKey: .savedComparisons) ?? []
    }
}

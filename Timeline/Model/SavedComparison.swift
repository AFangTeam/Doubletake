import Foundation

/// 一次"保存过的 AB 对比"在文档里的记录。
/// 用户点 chip 能回到这两张图、自动起 AB 对比。
nonisolated struct SavedComparison: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// 通过 ClipID.serialized 引用两张图，原文件被删后只是跳不到了，记录本身不丢
    var clipAIDSerialized: String
    var clipBIDSerialized: String
    var createdAtEpoch: Double
    /// 保存当时的 EXIF 短摘要（焦段、机身镜头等），用于 chip 显示。
    /// 即便 clip 被删，chip 也能展示"这次对比拍的是什么"
    var summaryA: String
    var summaryB: String

    init(
        id: UUID = UUID(),
        name: String,
        clipAIDSerialized: String,
        clipBIDSerialized: String,
        createdAtEpoch: Double = Date().timeIntervalSince1970,
        summaryA: String,
        summaryB: String
    ) {
        self.id = id
        self.name = name
        self.clipAIDSerialized = clipAIDSerialized
        self.clipBIDSerialized = clipBIDSerialized
        self.createdAtEpoch = createdAtEpoch
        self.summaryA = summaryA
        self.summaryB = summaryB
    }
}

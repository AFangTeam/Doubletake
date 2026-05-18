import Foundation
import Observation
import SwiftUI

/// 跨文档共享的全局偏好。原本在 Inspector 里的"时间线显示"、"预览叠加信息"、
/// "预览默认源"都迁过来 —— 只调一次就长期有效，不再每个文档窗各调一份。
/// 走 UserDefaults，App 重启保留。
@MainActor
@Observable
final class PreferencesStore {
    // MARK: - 时间线显示
    var compactEmptyTime: Bool {
        didSet { Self.defaults.set(compactEmptyTime, forKey: Keys.compactEmptyTime) }
    }
    var emptyGapThresholdMinutes: Double {
        didSet { Self.defaults.set(emptyGapThresholdMinutes, forKey: Keys.emptyGapThresholdMinutes) }
    }

    // MARK: - 预览叠加信息
    var overlay: PreviewOverlaySettings {
        didSet { Self.persistOverlay(overlay) }
    }

    // MARK: - 预览默认源
    var singlePreviewPrefersRAW: Bool {
        didSet { Self.defaults.set(singlePreviewPrefersRAW, forKey: Keys.singlePrefersRAW) }
    }
    var abComparePrefersRAW: Bool {
        didSet { Self.defaults.set(abComparePrefersRAW, forKey: Keys.abPrefersRAW) }
    }

    init() {
        let d = Self.defaults
        self.compactEmptyTime = d.object(forKey: Keys.compactEmptyTime) as? Bool ?? true
        let storedThreshold = d.double(forKey: Keys.emptyGapThresholdMinutes)
        self.emptyGapThresholdMinutes = storedThreshold > 0 ? storedThreshold : 10
        self.overlay = Self.loadOverlay()
        // 单图默认 JPG（false=JPG），AB 默认 RAW（true=RAW）—— 与之前的行为一致
        self.singlePreviewPrefersRAW = d.object(forKey: Keys.singlePrefersRAW) as? Bool ?? false
        self.abComparePrefersRAW = d.object(forKey: Keys.abPrefersRAW) as? Bool ?? true
    }

    /// 单图预览时该用哪个 source（结合 clip 实际可用的源回退）
    func defaultSource(forSingle clip: MediaClip) -> ImageSource {
        if singlePreviewPrefersRAW {
            return clip.rawURL != nil ? .raw : .jpg
        }
        return clip.jpgURL != nil ? .jpg : .raw
    }

    /// AB 对比时该用哪个 source
    func defaultSource(forAB clip: MediaClip) -> ImageSource {
        if abComparePrefersRAW {
            return clip.rawURL != nil ? .raw : .jpg
        }
        return clip.jpgURL != nil ? .jpg : .raw
    }

    // MARK: - Persistence helpers

    private enum Keys {
        static let compactEmptyTime = "prefs.compactEmptyTime"
        static let emptyGapThresholdMinutes = "prefs.emptyGapThresholdMinutes"
        static let overlay = "prefs.overlaySettings"
        static let singlePrefersRAW = "prefs.singlePrefersRAW"
        static let abPrefersRAW = "prefs.abPrefersRAW"
    }

    private static let defaults = UserDefaults.standard

    private static func loadOverlay() -> PreviewOverlaySettings {
        if let data = defaults.data(forKey: Keys.overlay),
           let decoded = try? JSONDecoder().decode(PreviewOverlaySettings.self, from: data) {
            return decoded
        }
        return .initial
    }

    private static func persistOverlay(_ s: PreviewOverlaySettings) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Keys.overlay)
        }
    }
}

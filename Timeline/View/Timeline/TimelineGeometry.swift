import Foundation

/// 把 timeline 上的"时间"和"x 像素"互转的几何工具。
///
/// 支持两种模式：
/// - **uniform**：经典线性映射，`x = leftPadding + (date - timelineStart) * pxPerSecond`
/// - **compacted**：把照片之间的空白时段（间隔 > threshold）压成统一窄缝，
///   每个"拍摄团"内部仍然线性。映射通过一张 segments 表二分。
///
/// 外部代码（TimelineView / TrackLane / TimeRulerView）一律只调 `x(at:)`、`date(at:)`，
/// 不需要感知是哪种模式。
struct TimelineGeometry: Equatable {
    let timelineStart: Date
    let timelineEnd: Date
    let pxPerSecond: Double
    let leftPadding: Double
    let rightPadding: Double

    /// 折叠模式下的 segment 表。uniform 模式下为 nil。
    let segments: [Segment]?
    /// 折叠模式下单个空白被压缩到多少"虚拟秒"。
    let compactedGapSeconds: TimeInterval

    /// 一个 cluster：内部时间线性映射；cluster 之间的空白被压成 compactedGapSeconds。
    struct Segment: Equatable {
        let realStart: Date
        let realEnd: Date
        /// 这个 cluster 在虚拟时间里的起始偏移（从 timelineStart 起算的秒）
        let virtualStart: TimeInterval

        var realDuration: TimeInterval {
            realEnd.timeIntervalSince(realStart)
        }
    }

    // MARK: - Init

    /// 经典均匀线性几何。
    init(
        timelineStart: Date,
        timelineEnd: Date,
        pxPerSecond: Double,
        leftPadding: Double = 24,
        rightPadding: Double = 24
    ) {
        self.timelineStart = timelineStart
        self.timelineEnd = timelineEnd
        self.pxPerSecond = pxPerSecond
        self.leftPadding = leftPadding
        self.rightPadding = rightPadding
        self.segments = nil
        self.compactedGapSeconds = 0
    }

    /// 折叠空白时段的非均匀几何。
    /// - parameter captureDates: 所有 effectiveDate（含 time offset），调用方传升序
    /// - parameter gapThresholdSeconds: 相邻照片间隔大于这个值就算"空白"
    /// - parameter compactedGapSeconds: 压缩后空白等效秒数（virtual 空间里固定宽度）
    /// - parameter clusterPaddingSeconds: 每个 cluster 头尾的实际时间内 padding
    init(
        timelineStart: Date,
        timelineEnd: Date,
        pxPerSecond: Double,
        leftPadding: Double = 24,
        rightPadding: Double = 24,
        captureDatesSorted: [Date],
        gapThresholdSeconds: TimeInterval,
        compactedGapSeconds: TimeInterval = 60,
        clusterPaddingSeconds: TimeInterval = 30
    ) {
        self.timelineStart = timelineStart
        self.timelineEnd = timelineEnd
        self.pxPerSecond = pxPerSecond
        self.leftPadding = leftPadding
        self.rightPadding = rightPadding
        self.compactedGapSeconds = compactedGapSeconds

        // 没有任何照片 → 退化到均匀模式
        guard !captureDatesSorted.isEmpty else {
            self.segments = nil
            return
        }

        // 切 cluster：找出 gap > threshold 的相邻点
        var clusterStarts: [Int] = [0]
        for i in 1..<captureDatesSorted.count {
            let delta = captureDatesSorted[i].timeIntervalSince(captureDatesSorted[i - 1])
            if delta > gapThresholdSeconds {
                clusterStarts.append(i)
            }
        }
        clusterStarts.append(captureDatesSorted.count)

        // 构建 segments，每个 cluster 头尾各加 clusterPaddingSeconds
        var segs: [Segment] = []
        var virtualCursor: TimeInterval = 0
        for k in 0..<(clusterStarts.count - 1) {
            let firstIdx = clusterStarts[k]
            let lastIdx = clusterStarts[k + 1] - 1
            let firstDate = captureDatesSorted[firstIdx]
            let lastDate = captureDatesSorted[lastIdx]
            // 第一个 cluster 的左 padding：用 timelineStart 和 firstDate-clusterPad 中更早的那个
            let segStart: Date = {
                let padded = firstDate.addingTimeInterval(-clusterPaddingSeconds)
                return k == 0 ? min(timelineStart, padded) : padded
            }()
            let segEnd: Date = {
                let padded = lastDate.addingTimeInterval(clusterPaddingSeconds)
                return (k == clusterStarts.count - 2) ? max(timelineEnd, padded) : padded
            }()
            segs.append(Segment(
                realStart: segStart,
                realEnd: segEnd,
                virtualStart: virtualCursor
            ))
            virtualCursor += segEnd.timeIntervalSince(segStart)
            // cluster 之间留压缩缝
            if k < clusterStarts.count - 2 {
                virtualCursor += compactedGapSeconds
            }
        }
        self.segments = segs
    }

    // MARK: - Derived

    var totalDuration: TimeInterval {
        if let segments, let last = segments.last {
            // 最后一个 segment 的 virtualStart + 该 segment 实长 = 总虚拟时长
            return last.virtualStart + last.realDuration
        }
        return max(0, timelineEnd.timeIntervalSince(timelineStart))
    }

    var contentWidth: Double {
        totalDuration * pxPerSecond + leftPadding + rightPadding
    }

    var isCompacted: Bool { segments != nil }

    // MARK: - 坐标转换

    func x(at date: Date) -> Double {
        guard let segments else {
            return leftPadding + date.timeIntervalSince(timelineStart) * pxPerSecond
        }
        // 折叠模式：找到包含 date 的 segment
        for seg in segments {
            if date >= seg.realStart && date <= seg.realEnd {
                let offsetIn = date.timeIntervalSince(seg.realStart)
                return leftPadding + (seg.virtualStart + offsetIn) * pxPerSecond
            }
            if date < seg.realStart {
                // date 落在前一个 gap 里：吸到这个 segment 起点
                return leftPadding + seg.virtualStart * pxPerSecond
            }
        }
        // date 在最后一个 segment 之后
        if let last = segments.last {
            return leftPadding + (last.virtualStart + last.realDuration) * pxPerSecond
        }
        return leftPadding
    }

    func date(at x: Double) -> Date {
        guard let segments else {
            let seconds = (x - leftPadding) / pxPerSecond
            return timelineStart.addingTimeInterval(seconds)
        }
        let virtualSec = (x - leftPadding) / pxPerSecond
        for seg in segments {
            let segEnd = seg.virtualStart + seg.realDuration
            if virtualSec < seg.virtualStart {
                // 落在 gap 里 → 吸到 segment 起点
                return seg.realStart
            }
            if virtualSec <= segEnd {
                let offsetIn = virtualSec - seg.virtualStart
                return seg.realStart.addingTimeInterval(offsetIn)
            }
        }
        return segments.last?.realEnd ?? timelineEnd
    }

    /// 给定可见 x 区间，返回对应的时间区间，用于视口剔除
    func visibleDateRange(forVisibleX range: ClosedRange<Double>) -> ClosedRange<Date> {
        let lower = date(at: range.lowerBound)
        let upper = date(at: range.upperBound)
        return lower...upper
    }

    /// 折叠点的 x 坐标 + 对应的折叠时长（用于 ruler 上画虚线 + "⋯"）。
    /// uniform 模式返回空。
    var compactedGapMarkers: [(x: Double, foldedSeconds: TimeInterval)] {
        guard let segments, segments.count > 1 else { return [] }
        var out: [(Double, TimeInterval)] = []
        for i in 1..<segments.count {
            let prev = segments[i - 1]
            let cur = segments[i]
            // gap 中心在虚拟空间里
            let midVirtual = (prev.virtualStart + prev.realDuration + cur.virtualStart) / 2
            let xMid = leftPadding + midVirtual * pxPerSecond
            let folded = cur.realStart.timeIntervalSince(prev.realEnd)
            out.append((xMid, folded))
        }
        return out
    }
}

extension TimelineGeometry {
    /// 选一个合适的 tick 间隔（秒）使得每个 tick 之间约为 targetPx 像素。
    static func suggestedTickIntervalSeconds(pxPerSecond: Double, targetPx: Double = 60) -> TimeInterval {
        let secondsPerTarget = targetPx / pxPerSecond
        let candidates: [TimeInterval] = [
            1, 2, 5, 10, 15, 30,
            60, 120, 300, 600, 900, 1800,
            3600, 7200, 10800, 21600, 43200,
            86400, 172800, 604800
        ]
        for v in candidates where v >= secondsPerTarget {
            return v
        }
        return 604800
    }
}

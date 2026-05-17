import Foundation

/// 把 timeline 上的"时间"和"x 像素"互转的几何工具。
struct TimelineGeometry: Equatable {
    let timelineStart: Date
    let timelineEnd: Date
    let pxPerSecond: Double
    let leftPadding: Double
    let rightPadding: Double

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
    }

    var totalDuration: TimeInterval {
        max(0, timelineEnd.timeIntervalSince(timelineStart))
    }

    var contentWidth: Double {
        totalDuration * pxPerSecond + leftPadding + rightPadding
    }

    func x(at date: Date) -> Double {
        leftPadding + date.timeIntervalSince(timelineStart) * pxPerSecond
    }

    func date(at x: Double) -> Date {
        let seconds = (x - leftPadding) / pxPerSecond
        return timelineStart.addingTimeInterval(seconds)
    }

    /// 给定可见 x 区间，返回对应的时间区间，用于视口剔除
    func visibleDateRange(forVisibleX range: ClosedRange<Double>) -> ClosedRange<Date> {
        let lower = date(at: range.lowerBound)
        let upper = date(at: range.upperBound)
        return lower...upper
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

import SwiftUI

/// 横向时间轴刻度。基于 Canvas 绘制，根据 pxPerSecond 自适应 tick 密度。
/// 折叠模式下：每个 cluster segment 内独立画刻度，cluster 之间的折叠点画虚线 + "⋯"。
struct TimeRulerView: View {
    let geometry: TimelineGeometry

    var body: some View {
        Canvas { ctx, size in
            let tickSeconds = TimelineGeometry.suggestedTickIntervalSeconds(
                pxPerSecond: geometry.pxPerSecond,
                targetPx: 70
            )
            let majorEvery: Int = 5
            let labelInterval = tickSeconds * Double(majorEvery)
            let fmt = ruleDateFormatter(for: tickSeconds)
            let tickColor = Color.secondary.opacity(0.45)
            let majorColor = Color.secondary.opacity(0.85)

            // 在指定时间区间内画 tick
            func drawTicks(_ realStart: Date, _ realEnd: Date) {
                let startEpoch = realStart.timeIntervalSince1970
                let endEpoch = realEnd.timeIntervalSince1970
                var t = floor(startEpoch / tickSeconds) * tickSeconds
                while t <= endEpoch + tickSeconds {
                    let date = Date(timeIntervalSince1970: t)
                    if date >= realStart && date <= realEnd {
                        let x = geometry.x(at: date)
                        if x >= -1 && x <= size.width + 1 {
                            let mod = abs(t.truncatingRemainder(dividingBy: labelInterval))
                            let isMajor = mod < 0.001 || abs(mod - labelInterval) < 0.001

                            var path = Path()
                            if isMajor {
                                path.move(to: CGPoint(x: x, y: size.height * 0.45))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            } else {
                                path.move(to: CGPoint(x: x, y: size.height * 0.7))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            }
                            ctx.stroke(path, with: .color(isMajor ? majorColor : tickColor), lineWidth: 0.5)

                            if isMajor {
                                let text = Text(fmt.string(from: date))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                ctx.draw(text, at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                            }
                        }
                    }
                    t += tickSeconds
                }
            }

            if let segments = geometry.segments {
                for seg in segments {
                    drawTicks(seg.realStart, seg.realEnd)
                }
                // 折叠点：竖虚线 + "⋯" 提示折叠了多少时长
                let dashColor = Color.secondary.opacity(0.55)
                for marker in geometry.compactedGapMarkers {
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: marker.x, y: size.height * 0.2))
                    dashPath.addLine(to: CGPoint(x: marker.x, y: size.height))
                    ctx.stroke(
                        dashPath,
                        with: .color(dashColor),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                    )
                    let foldedLabel = compactGapLabel(seconds: marker.foldedSeconds)
                    let text = Text("⋯ \(foldedLabel)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    ctx.draw(text, at: CGPoint(x: marker.x, y: 2), anchor: .top)
                }
            } else {
                drawTicks(geometry.timelineStart, geometry.timelineEnd)
            }

            // 底边线
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
        }
    }

    private func compactGapLabel(seconds: TimeInterval) -> String {
        if seconds < 3600 {
            return String(format: "%.0f 分钟", seconds / 60)
        }
        if seconds < 86400 {
            return String(format: "%.1f 小时", seconds / 3600)
        }
        return String(format: "%.1f 天", seconds / 86400)
    }

    private func ruleDateFormatter(for tickSeconds: TimeInterval) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        switch tickSeconds {
        case ..<60:
            f.dateFormat = "HH:mm:ss"
        case 60..<3600:
            f.dateFormat = "HH:mm"
        case 3600..<86400:
            f.dateFormat = "M/d HH:mm"
        default:
            f.dateFormat = "yyyy/M/d"
        }
        return f
    }
}

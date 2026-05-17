import SwiftUI

/// 横向时间轴刻度。基于 Canvas 绘制，根据 pxPerSecond 自适应 tick 密度。
struct TimeRulerView: View {
    let geometry: TimelineGeometry

    var body: some View {
        Canvas { ctx, size in
            let tickSeconds = TimelineGeometry.suggestedTickIntervalSeconds(
                pxPerSecond: geometry.pxPerSecond,
                targetPx: 70
            )
            let majorEvery: Int = 5  // 每 5 个 tick 显示一次标签
            let labelInterval = tickSeconds * Double(majorEvery)

            let startEpoch = geometry.timelineStart.timeIntervalSince1970
            let endEpoch = geometry.timelineEnd.timeIntervalSince1970

            // 把起始时刻对齐到 tick 边界
            var t = (floor(startEpoch / tickSeconds)) * tickSeconds

            let fmt = ruleDateFormatter(for: tickSeconds)
            let tickColor = Color.secondary.opacity(0.45)
            let majorColor = Color.secondary.opacity(0.85)

            while t <= endEpoch + tickSeconds {
                let date = Date(timeIntervalSince1970: t)
                let x = geometry.x(at: date)

                if x >= -1 && x <= size.width + 1 {
                    let isMajor = abs(t.truncatingRemainder(dividingBy: labelInterval)) < 0.001
                        || abs(t.truncatingRemainder(dividingBy: labelInterval) - labelInterval) < 0.001

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

                t += tickSeconds
            }

            // 底边线
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
        }
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

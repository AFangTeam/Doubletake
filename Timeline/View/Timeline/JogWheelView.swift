import SwiftUI
import AppKit

/// 横向"滚轮"控件：拖动以微调时间偏移。
/// 视觉是一条带刻度的水平条带，刻度随数值变化滚动，正中央有固定光标。
/// 修饰键：Shift = 精细（10x 慢）；Option = 粗调（10x 快）。
/// 跨越整秒时播一次轻量触觉反馈。
struct JogWheelView: View {
    @Binding var offsetSeconds: TimeInterval
    var tint: Color = .accentColor
    /// 默认拖多少像素 = 1 秒
    var basePixelsPerSecond: Double = 80
    var height: CGFloat = 56

    @State private var dragStartOffset: TimeInterval?
    @State private var lastWholeSecond: Int = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                    )

                ticks(size: proxy.size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // 中央指示器：上三角 + 一条垂直线
                VStack(spacing: 0) {
                    Triangle()
                        .fill(tint)
                        .frame(width: 12, height: 7)
                    Rectangle()
                        .fill(tint)
                        .frame(width: 1.5)
                }
                .frame(maxHeight: .infinity)

                // 数值胶囊
                Text(formatBig(offsetSeconds))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint, in: Capsule())
                    .shadow(color: tint.opacity(0.4), radius: 4, y: 1)
                    .offset(y: -(proxy.size.height / 2) - 10)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: height)
        .padding(.top, 14)  // 给数值胶囊留位置
        .accessibilityLabel("时间偏移调整轮")
        .accessibilityValue("\(formatBig(offsetSeconds))")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = offsetSeconds
                    lastWholeSecond = Int(offsetSeconds.rounded(.towardZero))
                }
                let mods = NSEvent.modifierFlags
                let scale: Double
                if mods.contains(.shift) { scale = 0.1 }       // 精细
                else if mods.contains(.option) { scale = 10 }  // 粗调
                else { scale = 1.0 }
                let secondsDelta = Double(value.translation.width) / basePixelsPerSecond * scale
                let newOffset = (dragStartOffset ?? 0) + secondsDelta
                offsetSeconds = newOffset

                // 整秒边界触觉反馈
                let cur = Int(newOffset.rounded(.towardZero))
                if cur != lastWholeSecond {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    lastWholeSecond = cur
                }
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    @ViewBuilder
    private func ticks(size: CGSize) -> some View {
        Canvas { ctx, sz in
            let centerX = sz.width / 2
            let visibleSecondsHalf = (sz.width / 2) / basePixelsPerSecond + 1

            // Step is 0.2s; major ticks every 1s
            let minorStep = 0.2
            let firstTick = ((offsetSeconds - visibleSecondsHalf) / minorStep).rounded(.down) * minorStep
            let lastTick = ((offsetSeconds + visibleSecondsHalf) / minorStep).rounded(.up) * minorStep

            var t = firstTick
            while t <= lastTick + 1e-6 {
                let x = centerX + (t - offsetSeconds) * basePixelsPerSecond
                let nearest = (t).rounded()
                let isMajor = abs(t - nearest) < 0.01
                let isSubmajor = !isMajor && abs((t * 5).rounded() - (t * 5)) < 0.01  // every 0.2

                var path = Path()
                if isMajor {
                    path.move(to: CGPoint(x: x, y: sz.height * 0.22))
                    path.addLine(to: CGPoint(x: x, y: sz.height * 0.78))
                    ctx.stroke(path, with: .color(.primary.opacity(0.55)), lineWidth: 0.8)
                    // major label
                    let label = formatTickLabel(t)
                    ctx.draw(
                        Text(label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary),
                        at: CGPoint(x: x, y: sz.height - 2),
                        anchor: .bottom
                    )
                } else if isSubmajor {
                    path.move(to: CGPoint(x: x, y: sz.height * 0.38))
                    path.addLine(to: CGPoint(x: x, y: sz.height * 0.62))
                    ctx.stroke(path, with: .color(.primary.opacity(0.22)), lineWidth: 0.5)
                }
                t += minorStep
            }
        }
    }

    private func formatTickLabel(_ s: Double) -> String {
        let rounded = s.rounded()
        if abs(rounded) < 0.01 { return "0" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(Int(abs(rounded)))"
    }

    private func formatBig(_ s: Double) -> String {
        if abs(s) < 0.005 { return "+0.00s" }
        let sign = s > 0 ? "+" : "−"
        let abs = Swift.abs(s)
        if abs >= 60 {
            let m = Int(abs) / 60
            let secs = abs.truncatingRemainder(dividingBy: 60)
            return String(format: "%@%dm %.2fs", sign, m, secs)
        }
        return String(format: "%@%.2fs", sign, abs)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

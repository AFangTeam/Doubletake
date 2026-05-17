import SwiftUI

struct TrackHeaderView: View {
    let track: Track
    let label: String
    let tint: Color
    let offsetSeconds: TimeInterval
    let count: Int
    let isFocused: Bool
    let pxPerSecond: Double

    var onFocus: () -> Void
    var onOffsetDelta: (TimeInterval) -> Void
    var onOffsetReset: () -> Void

    @State private var dragLastTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            Text("\(count) 张")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(formatOffset(offsetSeconds))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(offsetSeconds == 0 ? .secondary : tint)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9))
                Text("拖动")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isFocused ? tint.opacity(0.12) : .clear)
                .padding(4)
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
        .contextMenu {
            Button("重置时间偏移", systemImage: "arrow.counterclockwise") {
                onOffsetReset()
            }
            .disabled(offsetSeconds == 0)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    onFocus()
                    let delta = value.translation.width - dragLastTranslation
                    dragLastTranslation = value.translation.width
                    let secondsDelta = delta / pxPerSecond
                    if secondsDelta != 0 {
                        onOffsetDelta(secondsDelta)
                    }
                }
                .onEnded { _ in
                    dragLastTranslation = 0
                }
        )
        .help("点击聚焦本轨；横向拖动整体移动；右键可重置")
    }

    private func formatOffset(_ s: TimeInterval) -> String {
        if s == 0 { return "偏移 0" }
        let sign = s > 0 ? "+" : "−"
        let abs = Swift.abs(s)
        if abs >= 3600 {
            return String(format: "偏移 %@%.2fh", sign, abs / 3600)
        } else if abs >= 60 {
            return String(format: "偏移 %@%.2fm", sign, abs / 60)
        } else {
            return String(format: "偏移 %@%.1fs", sign, abs)
        }
    }
}

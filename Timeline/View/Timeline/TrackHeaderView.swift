import SwiftUI
import UniformTypeIdentifiers

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
    /// 从 Finder 拖一个文件夹到本轨道时调用
    var onDropFolder: (URL) -> Void = { _ in }

    @State private var dragLastTranslation: CGFloat = 0
    @State private var isDropTargeted: Bool = false

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
        // 拖文件夹进来时高亮反馈
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.18))
                    )
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
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
        .help("点击聚焦本轨；横向拖动整体移动；从 Finder 拖文件夹来直接换源；右键可重置偏移")
        // Finder 拖文件夹到 track header → 等价于点 inspector 选择文件夹
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists, isDir.boolValue else { return }
                DispatchQueue.main.async {
                    onDropFolder(url)
                }
            }
            return true
        }
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

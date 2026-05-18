import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @Binding var document: CompareDocument
    let vm: CompareViewModel
    /// 点击对比集列表项时跳转：选中两张图 + 滚 timeline + 起 AB 预览
    var onJumpToComparison: (SavedComparison) -> Void

    var body: some View {
        Form {
            if vm.selection.count == 1, let clip = vm.selectedClips().first {
                Section("选中的素材") {
                    SingleClipDetailView(
                        clip: clip,
                        isFavorite: vm.isFavorite(clip.id, in: document),
                        onToggleFavorite: { vm.toggleFavorite(clip.id, in: &document) }
                    )
                }
            } else if vm.selection.count > 1 {
                Section("选中") {
                    MultiSelectionSummary(
                        vm: vm,
                        document: $document
                    )
                }
            }

            Section("A 轨（机型 1）") {
                TrackInspectorRow(document: $document, vm: vm, track: .a)
            }
            Section("B 轨（机型 2）") {
                TrackInspectorRow(document: $document, vm: vm, track: .b)
            }

            if !document.payload.savedComparisons.isEmpty {
                Section("对比集 (\(document.payload.savedComparisons.count))") {
                    SavedComparisonsList(
                        comparisons: document.payload.savedComparisons,
                        onJump: { onJumpToComparison($0) },
                        onDelete: { c in
                            document.payload.savedComparisons.removeAll { $0.id == c.id }
                        },
                        onRename: { c, newName in
                            if let idx = document.payload.savedComparisons.firstIndex(where: { $0.id == c.id }) {
                                document.payload.savedComparisons[idx].name = newName
                            }
                        }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 对比集列表

private struct SavedComparisonsList: View {
    let comparisons: [SavedComparison]
    let onJump: (SavedComparison) -> Void
    let onDelete: (SavedComparison) -> Void
    let onRename: (SavedComparison, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(comparisons.enumerated()), id: \.element.id) { idx, c in
                ComparisonRow(
                    comparison: c,
                    onJump: { onJump(c) },
                    onDelete: { onDelete(c) },
                    onRename: { newName in onRename(c, newName) }
                )
                if idx < comparisons.count - 1 {
                    Divider().padding(.leading, 28)
                }
            }
        }
    }
}

private struct ComparisonRow: View {
    let comparison: SavedComparison
    let onJump: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var renamePopover = false
    @State private var renameDraft = ""

    var body: some View {
        Button(action: onJump) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(.tint)
                    .font(.caption)
                    .frame(width: 18)
                Text(comparison.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(relativeTime(from: comparison.createdAtEpoch))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("跳转到这次对比")
        .contextMenu {
            Button("重命名…") {
                renameDraft = comparison.name
                renamePopover = true
            }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
        .popover(isPresented: $renamePopover) {
            renameForm
        }
    }

    @ViewBuilder
    private var renameForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("重命名对比")
                .font(.headline)
            TextField("名字", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("取消") { renamePopover = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func commit() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        renamePopover = false
    }

    private func relativeTime(from epoch: Double) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.dateTimeStyle = .named
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 单选详情

private struct SingleClipDetailView: View {
    let clip: MediaClip
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: clip.kind.isPair ? "photo.stack" : "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(clip.track == .a ? .blue : .orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.displayName)
                        .font(.system(.callout, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(clip.track == .a ? "A 轨" : "B 轨")
                        .font(.caption)
                        .foregroundStyle(clip.track == .a ? .blue : .orange)
                }
                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isFavorite ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help(isFavorite ? "取消红心收藏 (F)" : "加红心收藏 (F)")
            }

            VStack(alignment: .leading, spacing: 6) {
                detailRow("拍摄时间", value: clip.captureDate.formatted(date: .long, time: .standard))
                if let f = clip.metadata.focalLengthDisplay {
                    detailRow("焦段", value: f)
                }
                if let camStr = cameraDisplay(metadata: clip.metadata) {
                    detailRow("机身", value: camStr)
                }
                if let lens = clip.metadata.lensModel {
                    detailRow("镜头", value: lens)
                }
                let parts: [String] = [
                    clip.metadata.apertureDisplay,
                    clip.metadata.shutterDisplay,
                    clip.metadata.isoDisplay
                ].compactMap { $0 }
                if !parts.isEmpty {
                    detailRow("曝光", value: parts.joined(separator: "  ·  "))
                }
                if let size = clip.metadata.pixelSizeDisplay {
                    detailRow("尺寸", value: size)
                }
                detailRow("文件大小", value: formatBytes(clip.totalBytes))
                detailRow("格式", value: clip.allExtensions)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("文件路径")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(clip.urls, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(url.lastPathComponent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中显示")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .default))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func cameraDisplay(metadata: ExifMetadata) -> String? {
        guard let cam = metadata.cameraModel else { return nil }
        if let make = metadata.cameraMake, !cam.contains(make) {
            return "\(make) \(cam)"
        }
        return cam
    }
}

// MARK: - 多选摘要

private struct MultiSelectionSummary: View {
    let vm: CompareViewModel
    @Binding var document: CompareDocument

    private var clips: [MediaClip] { vm.selectedClips() }
    private var countA: Int { clips.filter { $0.track == .a }.count }
    private var countB: Int { clips.filter { $0.track == .b }.count }

    private var allFavorited: Bool {
        clips.allSatisfy { vm.isFavorite($0.id, in: document) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("已选 \(clips.count) 张")
                    .font(.callout)
                Spacer()
                Button {
                    let target = !allFavorited
                    for c in clips {
                        vm.setFavorite(c.id, to: target, in: &document)
                    }
                } label: {
                    Image(systemName: allFavorited ? "heart.fill" : "heart")
                        .foregroundStyle(allFavorited ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help(allFavorited ? "全部取消红心 (F)" : "全部加红心 (F)")
                Button("清除") { vm.clearSelection() }
                    .controlSize(.small)
            }
            HStack(spacing: 16) {
                Label("A \(countA)", systemImage: "circle.fill")
                    .foregroundStyle(.blue)
                Label("B \(countB)", systemImage: "circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption)

            if countA == 1 && countB == 1 {
                Text("准备 AB 对比 — 按 Space 进入")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else if let span = timeSpan() {
                Text("时间跨度 \(span)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeSpan() -> String? {
        guard let minDate = clips.map(\.captureDate).min(),
              let maxDate = clips.map(\.captureDate).max() else { return nil }
        let dur = maxDate.timeIntervalSince(minDate)
        if dur < 60 { return String(format: "%.0fs", dur) }
        if dur < 3600 { return String(format: "%.1fm", dur / 60) }
        return String(format: "%.1fh", dur / 3600)
    }
}

// MARK: - 轨道节

private struct TrackInspectorRow: View {
    @Binding var document: CompareDocument
    let vm: CompareViewModel
    let track: Track
    @State private var importerPresented = false

    private var config: TrackConfig {
        document.config(for: track)
    }

    private var state: CompareViewModel.TrackState {
        vm.state(for: track)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("显示名称", text: Binding(
                get: { config.displayName },
                set: {
                    var c = config
                    c.displayName = $0
                    document.setConfig(c, for: track)
                }
            ))

            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                if let url = state.folderURL {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path(percentEncoded: false))
                } else {
                    Text("未选择文件夹")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button {
                    importerPresented = true
                } label: {
                    Label(state.folderURL == nil ? "选择文件夹" : "更换", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)

                if state.folderURL != nil {
                    Button(role: .destructive) {
                        document.setBookmark(nil, for: track)
                    } label: {
                        Label("清除", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                }

                Spacer()

                if state.isScanning {
                    ProgressView().controlSize(.small)
                } else if !state.clips.isEmpty {
                    Text("\(state.clips.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("时间偏移")
                        .font(.caption)
                    Spacer()
                    TextField(
                        "0",
                        value: Binding(
                            get: { config.timeOffsetSeconds },
                            set: {
                                var c = config
                                c.timeOffsetSeconds = $0
                                document.setConfig(c, for: track)
                            }
                        ),
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .font(.system(.caption, design: .monospaced))
                    Text("s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        var c = config
                        c.timeOffsetSeconds = 0
                        document.setConfig(c, for: track)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                    .disabled(config.timeOffsetSeconds == 0)
                    .help("重置为 0")
                }

                JogWheelView(
                    offsetSeconds: Binding(
                        get: { config.timeOffsetSeconds },
                        set: {
                            var c = config
                            c.timeOffsetSeconds = $0
                            document.setConfig(c, for: track)
                        }
                    ),
                    tint: track == .a ? .blue : .orange
                )

                Text("拖动调节：默认精度 80px=1s；按住 ⇧ 更精细，⌥ 更粗放")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try BookmarkStore.makeBookmark(for: url)
                document.setBookmark(bookmark, for: track)
            } catch {
                vm.updateState({
                    $0.error = "无法保存文件夹书签：\(error.localizedDescription)"
                }, for: track)
            }
        case .failure:
            break
        }
    }
}

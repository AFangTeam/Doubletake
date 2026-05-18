import SwiftUI
import UniformTypeIdentifiers

struct CompareDocumentView: View {
    @Binding var document: CompareDocument
    @Environment(PreferencesStore.self) private var prefs
    @State private var vm = CompareViewModel()
    @State private var inspectorPresented: Bool = true

    /// 预览状态：互斥的三种
    /// - .single(ClipID)：单图预览
    /// - .ab(aID, bID)：AB 对比
    /// - nil：无预览
    @State private var preview: PreviewState?

    enum PreviewState: Equatable {
        case single(ClipID)
        case ab(ClipID, ClipID)
    }

    // 独立预览窗口控制器 —— 用 AppKit NSWindow 装预览/对比视图，
    // 这样全屏、置顶（.floating）都是真正的 macOS 窗口行为，互不干扰主文档窗。
    @State private var previewCtrl = PreviewWindowController()
    @State private var previewFloating: Bool = false

    @State private var jumpPopoverPresented: Bool = false
    @State private var exportFolderImporter: Bool = false
    @State private var exportResult: FavoritesExportResult?
    @State private var exportError: String?

    // AB 对比的保存：用户先点 "保存对比" → 在 ABCompareView 里填名字 + 拿到截图 →
    // 我们再起 fileImporter 让用户选父文件夹 → 写盘。
    @State private var pendingABSave: PendingABSave?
    @State private var abSaveFolderImporter: Bool = false
    @State private var abSaveResult: ABComparisonResult?
    @State private var abSaveError: String?

    private struct PendingABSave: Equatable {
        let name: String
        let clipAID: ClipID
        let clipBID: ClipID
        let comparisonImage: CGImageBox
        let originalComparisonImage: CGImageBox
        let info: ABComparisonInfo

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name && lhs.clipAID == rhs.clipAID && lhs.clipBID == rhs.clipBID
        }
    }

    /// CGImage 不是 Equatable —— 包一层让 PendingABSave 能合成 Equatable
    private final class CGImageBox: @unchecked Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    private var favoriteCount: Int { vm.favoriteCount(in: document) }

    var body: some View {
        timelineArea
            .frame(minWidth: 880, minHeight: 520)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(
                    document: $document,
                    vm: vm,
                    onJumpToComparison: { jumpToSavedComparison($0) }
                )
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { jumpToDateButton }
                ToolbarItem(placement: .primaryAction) { exportFavoritesButton }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        requestPreview()
                    } label: {
                        Label(previewToolbarLabel, systemImage: previewToolbarIcon)
                    }
                    .disabled(!canPreview)
                    .help(canPreview ? "Space" : "选 1 张图单看，或选 1A+1B 做 AB 对比")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        inspectorPresented.toggle()
                    } label: {
                        Label("信息", systemImage: "sidebar.right")
                    }
                }
            }
            .task(id: document.bookmarkA) {
                await vm.applyBookmark(document.bookmarkA, for: .a)
            }
            .task(id: document.bookmarkB) {
                await vm.applyBookmark(document.bookmarkB, for: .b)
            }
            .onAppear {
                previewCtrl.onClose = { preview = nil }
            }
            .onDisappear {
                vm.releaseAllScopes()
                previewCtrl.dismiss()
            }
            .onChange(of: preview) { _, newValue in
                syncPreviewWindow(state: newValue)
            }
            .onChange(of: previewFloating) { _, _ in
                previewCtrl.setFloating(previewFloating)
            }
            .onChange(of: vm.selection) { _, _ in
                // 选区变化导致当前 preview 不再有效则自动关闭
                if let p = preview, !isPreviewStillValid(p) {
                    preview = nil
                }
            }
            // 切片 / 翻图 / Inspector 跳转触发预览窗内容更新
            .onChange(of: document.payload.overlaySettings) { _, _ in pushPreviewRefresh() }
            // 红心收藏变了 —— 预览窗右上角的心形需要从"空心"变"红色实心"
            .onChange(of: document.payload.favoriteClipIDs) { _, _ in pushPreviewRefresh() }
            // PreferencesStore 里的叠加信息开关变了，预览窗也要重渲染
            .onChange(of: prefs.overlay) { _, _ in pushPreviewRefresh() }
            .fileImporter(
                isPresented: $exportFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleExportFolder(result)
            }
            .fileImporter(
                isPresented: $abSaveFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleABSaveFolder(result)
            }
            .modifier(AlertsModifier(
                exportResult: $exportResult,
                exportError: $exportError,
                abSaveResult: $abSaveResult,
                abSaveError: $abSaveError
            ))
            .background { shortcutButtons }
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.zoomIn) } label: { EmptyView() }
                .keyboardShortcut("=", modifiers: .command)
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.zoomIn) } label: { EmptyView() }
                .keyboardShortcut("+", modifiers: .command)
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.zoomOut) } label: { EmptyView() }
                .keyboardShortcut("-", modifiers: .command)
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.fitAll) } label: { EmptyView() }
                .keyboardShortcut("0", modifiers: .command)
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.scrollToStart) } label: { EmptyView() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button { vm.pendingTimelineAction = CompareViewModel.TimelineActionRequest(.scrollToEnd) } label: { EmptyView() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button { jumpPopoverPresented = true } label: { EmptyView() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(vm.dateRange(in: document) == nil)
            Button { exportFolderImporter = true } label: { EmptyView() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(favoriteCount == 0)
            Button { requestPreview() } label: { EmptyView() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canPreview)
            Button { inspectorPresented.toggle() } label: { EmptyView() }
                .keyboardShortcut("i", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    @ViewBuilder
    private var timelineArea: some View {
        VStack(spacing: 0) {
            // 顶部按日期 chip 切片 —— 跨日素材时才显示
            DateChipStrip(
                days: availableDays,
                currentVisibleDay: currentVisibleDay,
                onSelect: { day in
                    vm.pendingScrollDate = day
                }
            )

            if vm.trackA.clips.isEmpty && vm.trackB.clips.isEmpty {
                emptyOrLoadingState
            } else {
                TimelineView(
                    document: $document,
                    vm: vm,
                    onRequestPreview: { requestPreview() }
                )
            }
        }
    }

    // MARK: - 日期 chip 数据

    private var availableDays: [Date] {
        let cal = Calendar.current
        let offsetA = document.payload.trackA.timeOffsetSeconds
        let offsetB = document.payload.trackB.timeOffsetSeconds
        let allDates = vm.trackA.clips.map { $0.captureDate.addingTimeInterval(offsetA) }
                     + vm.trackB.clips.map { $0.captureDate.addingTimeInterval(offsetB) }
        var seen = Set<Date>()
        for d in allDates { seen.insert(cal.startOfDay(for: d)) }
        return seen.sorted()
    }

    /// 当前 timeline 视口中心对应的"那一天"，用于 chip 高亮
    private var currentVisibleDay: Date? {
        guard let anchorEpoch = document.payload.viewState.scrollAnchorEpoch else { return nil }
        return Calendar.current.startOfDay(for: Date(timeIntervalSince1970: anchorEpoch))
    }

    private func jumpToSavedComparison(_ c: SavedComparison) {
        // 只滚动 + 选中两张，不直接弹预览 —— 用户可以再按 Space / 工具栏的 AB 按钮
        // 进入对比。这样列表跳转更轻量、可控
        guard vm.jumpToComparison(c, in: document) != nil else {
            abSaveError = "原始素材已不存在，无法跳转到这次对比。"
            return
        }
    }

    /// 给保存的对比一行紧凑摘要，列表项里附带显示
    private func shortSummary(of clip: MediaClip) -> String {
        var parts: [String] = []
        if let lens = clip.metadata.lensModel { parts.append(lens) }
        if let f = clip.metadata.focalLengthDisplay { parts.append(f) }
        if let a = clip.metadata.apertureDisplay { parts.append(a) }
        if parts.isEmpty, let cam = clip.metadata.cameraModel { parts.append(cam) }
        if parts.isEmpty { parts.append(clip.displayName) }
        return parts.joined(separator: " ")
    }

    // MARK: - 预览触发

    private var canPreview: Bool {
        vm.selection.count == 1 || vm.abPair != nil
    }

    private var previewToolbarLabel: String {
        vm.abPair != nil ? "AB 对比" : "预览"
    }

    private var previewToolbarIcon: String {
        vm.abPair != nil ? "rectangle.split.2x1" : "eye"
    }

    private func requestPreview() {
        if let pair = vm.abPair {
            preview = .ab(pair.a.id, pair.b.id)
        } else if vm.selection.count == 1, let id = vm.selection.first {
            preview = .single(id)
        }
    }

    private func isPreviewStillValid(_ p: PreviewState) -> Bool {
        switch p {
        case .single(let id): return vm.clip(for: id) != nil
        case .ab(let a, let b): return vm.clip(for: a) != nil && vm.clip(for: b) != nil
        }
    }

    // MARK: - 独立预览窗口

    private func syncPreviewWindow(state: PreviewState?) {
        guard let state else {
            previewCtrl.dismiss()
            return
        }
        let title = previewTitle(for: state)
        let view = previewContent(for: state)
        previewCtrl.present(view, title: title)
        previewCtrl.setFloating(previewFloating)
    }

    private func pushPreviewRefresh() {
        guard let state = preview else { return }
        syncPreviewWindow(state: state)
    }

    private func previewTitle(for state: PreviewState) -> String {
        switch state {
        case .single(let id):
            return vm.clip(for: id)?.displayName ?? "预览"
        case .ab(let a, let b):
            let na = vm.clip(for: a)?.displayName ?? "A"
            let nb = vm.clip(for: b)?.displayName ?? "B"
            return "\(na)  vs  \(nb)"
        }
    }

    @ViewBuilder
    private func previewContent(for state: PreviewState) -> some View {
        switch state {
        case .single(let id):
            if let clip = vm.clip(for: id) {
                SinglePreviewView(
                    clip: clip,
                    isFavorite: vm.isFavorite(id, in: document),
                    overlaySettings: prefs.overlay,
                    initialSource: prefs.defaultSource(forSingle: clip),
                    isFloating: previewFloating,
                    onDismiss: { preview = nil },
                    onNavigate: { direction in
                        if let next = vm.neighbor(of: id, direction: direction) {
                            preview = .single(next.id)
                            vm.selectOnly(next.id)
                            // 主文档 timeline 同步滚到这张图，关掉预览后那张就在中心
                            vm.requestedScrollClipID = next.id
                        }
                    },
                    onCrossTrack: {
                        if let other = vm.crossTrackNeighbor(of: id, in: document) {
                            preview = .single(other.id)
                            vm.selectOnly(other.id)
                            vm.requestedScrollClipID = other.id
                        }
                    },
                    onTrash: { trashFromPreview(currentID: id) },
                    onToggleFavorite: { vm.toggleFavorite(id, in: &document) },
                    onToggleFullScreen: { previewCtrl.toggleFullScreen() },
                    onToggleFloating: { previewFloating.toggle() }
                )
            } else {
                EmptyView()
            }
        case .ab(let aID, let bID):
            if let a = vm.clip(for: aID), let b = vm.clip(for: bID) {
                ABCompareView(
                    clipA: a,
                    clipB: b,
                    overlaySettings: prefs.overlay,
                    initialSourceA: prefs.defaultSource(forAB: a),
                    initialSourceB: prefs.defaultSource(forAB: b),
                    isFloating: previewFloating,
                    onDismiss: { preview = nil },
                    onNavigate: { direction in
                        let nextA = vm.neighbor(of: aID, direction: direction) ?? a
                        let nextB = vm.neighbor(of: bID, direction: direction) ?? b
                        preview = .ab(nextA.id, nextB.id)
                        vm.selection = [nextA.id, nextB.id]
                        vm.selectionAnchor = nextA.id
                        vm.requestedScrollClipID = nextA.id
                    },
                    onSaveComparison: { name, image, originalImage, info in
                        pendingABSave = PendingABSave(
                            name: name,
                            clipAID: aID,
                            clipBID: bID,
                            comparisonImage: CGImageBox(image),
                            originalComparisonImage: CGImageBox(originalImage),
                            info: info
                        )
                        abSaveFolderImporter = true
                    },
                    onToggleFullScreen: { previewCtrl.toggleFullScreen() },
                    onToggleFloating: { previewFloating.toggle() }
                )
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - 工具栏其他按钮

    @ViewBuilder
    private var jumpToDateButton: some View {
        Button {
            jumpPopoverPresented = true
        } label: {
            Label("跳转日期", systemImage: "calendar")
        }
        .disabled(vm.dateRange(in: document) == nil)
        .help("跳转到指定的拍摄日期 / 时间")
        .popover(isPresented: $jumpPopoverPresented, arrowEdge: .top) {
            if let range = vm.dateRange(in: document) {
                JumpToDateView(range: range, initial: vm.pendingScrollDate) { date in
                    vm.pendingScrollDate = date
                    jumpPopoverPresented = false
                }
            }
        }
    }

    @ViewBuilder
    private var exportFavoritesButton: some View {
        Button {
            exportFolderImporter = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("导出 \(favoriteCount)")
            }
        }
        .disabled(favoriteCount == 0)
        .help(favoriteCount == 0 ? "尚无红心标记的素材" : "把红心素材导出到一个文件夹")
    }

    private func trashFromPreview(currentID: ClipID) {
        guard let clip = vm.clip(for: currentID) else { return }
        let next = vm.neighbor(of: currentID, direction: .next)
            ?? vm.neighbor(of: currentID, direction: .prev)
        if let next {
            preview = .single(next.id)
            vm.selectOnly(next.id)
            // 删完后让背后 timeline 也滚到 next，关掉预览看到的就是 next，而不是被删
            // 的那张原先位置（"从头"感）
            vm.requestedScrollClipID = next.id
        } else {
            preview = nil
            vm.clearSelection()
        }
        _ = vm.trash([clip], in: &document)
    }

    private func handleExportFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            let started = folder.startAccessingSecurityScopedResource()
            defer { if started { folder.stopAccessingSecurityScopedResource() } }
            let favs = vm.favoriteClips(in: document)
            do {
                let res = try FavoritesExporter.export(clips: favs, to: folder)
                exportResult = res
            } catch {
                exportError = error.localizedDescription
            }
        case .failure(let error):
            exportError = error.localizedDescription
        }
    }

    private func handleABSaveFolder(_ result: Result<[URL], Error>) {
        defer { pendingABSave = nil }
        guard let pending = pendingABSave else { return }
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            guard let clipA = vm.clip(for: pending.clipAID),
                  let clipB = vm.clip(for: pending.clipBID) else {
                abSaveError = "选中的 AB 素材已不存在"
                return
            }
            let started = folder.startAccessingSecurityScopedResource()
            defer { if started { folder.stopAccessingSecurityScopedResource() } }

            let infoData: Data? = {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try? encoder.encode(pending.info)
            }()

            do {
                let res = try ABComparisonSaver.save(
                    name: pending.name,
                    parentFolder: folder,
                    clipA: clipA,
                    clipB: clipB,
                    comparisonImage: pending.comparisonImage.image,
                    originalComparisonImage: pending.originalComparisonImage.image,
                    infoJSON: infoData
                )
                abSaveResult = res
                let entry = SavedComparison(
                    name: pending.name,
                    clipAIDSerialized: pending.clipAID.serialized,
                    clipBIDSerialized: pending.clipBID.serialized,
                    summaryA: shortSummary(of: clipA),
                    summaryB: shortSummary(of: clipB)
                )
                document.payload.savedComparisons.append(entry)
            } catch {
                abSaveError = error.localizedDescription
            }
        case .failure(let error):
            abSaveError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var emptyOrLoadingState: some View {
        if vm.trackA.isScanning || vm.trackB.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在扫描照片…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.trackA.error ?? vm.trackB.error {
            ContentUnavailableView {
                Label("出错了", systemImage: "exclamationmark.triangle")
            } description: {
                Text(err)
            }
        } else {
            ContentUnavailableView {
                Label("双轨照片对比", systemImage: "rectangle.split.2x1")
            } description: {
                Text("在右侧 Inspector 为 A、B 两轨各选择一个文件夹，开始按拍摄时间对比照片。")
            }
        }
    }
}

/// 一组顶层 alert 拆出来当 ViewModifier，否则 CompareDocumentView.body 太长，
/// Swift 编译器会报"unable to type-check this expression in reasonable time"。
private struct AlertsModifier: ViewModifier {
    @Binding var exportResult: FavoritesExportResult?
    @Binding var exportError: String?
    @Binding var abSaveResult: ABComparisonResult?
    @Binding var abSaveError: String?

    func body(content: Content) -> some View {
        content
            .alert("导出完成", isPresented: Binding(
                get: { exportResult != nil },
                set: { if !$0 { exportResult = nil } }
            )) {
                Button("在 Finder 中显示") {
                    if let url = exportResult?.destinationFolder {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    exportResult = nil
                }
                Button("好") { exportResult = nil }
            } message: {
                if let r = exportResult {
                    Text("拷贝了 \(r.copiedFiles) 个文件，跳过 \(r.skipped) 个，错误 \(r.errors.count) 个。")
                }
            }
            .alert("导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("好") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .alert("AB 对比已保存", isPresented: Binding(
                get: { abSaveResult != nil },
                set: { if !$0 { abSaveResult = nil } }
            )) {
                Button("在 Finder 中显示") {
                    if let url = abSaveResult?.outputFolder {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    abSaveResult = nil
                }
                Button("好") { abSaveResult = nil }
            } message: {
                if let r = abSaveResult {
                    let count = (r.wroteComparisonImage ? 1 : 0) + (r.wroteOriginalComparisonImage ? 1 : 0)
                    Text("写入 \(count) 张对比截图，拷贝 \(r.copiedFiles) 个原文件，错误 \(r.errors.count) 个。")
                }
            }
            .alert("AB 对比保存失败", isPresented: Binding(
                get: { abSaveError != nil },
                set: { if !$0 { abSaveError = nil } }
            )) {
                Button("好") { abSaveError = nil }
            } message: {
                Text(abSaveError ?? "")
            }
    }
}

#Preview {
    CompareDocumentView(document: .constant(CompareDocument()))
        .environment(PreferencesStore())
}

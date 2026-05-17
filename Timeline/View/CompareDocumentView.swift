import SwiftUI
import UniformTypeIdentifiers

struct CompareDocumentView: View {
    @Binding var document: CompareDocument
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

    @State private var jumpPopoverPresented: Bool = false
    @State private var exportFolderImporter: Bool = false
    @State private var exportResult: FavoritesExportResult?
    @State private var exportError: String?

    private var favoriteCount: Int { vm.favoriteCount(in: document) }

    var body: some View {
        timelineArea
            .frame(minWidth: 880, minHeight: 520)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(document: $document, vm: vm)
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    jumpToDateButton
                }
                ToolbarItem(placement: .primaryAction) {
                    exportFavoritesButton
                }
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
            .onDisappear {
                vm.releaseAllScopes()
            }
            .sheet(isPresented: Binding(
                get: { preview != nil },
                set: { if !$0 { preview = nil } }
            )) {
                previewSheet
            }
            .onChange(of: vm.selection) { _, _ in
                // 选区变化导致当前 preview 不再有效则自动关闭
                if let p = preview, !isPreviewStillValid(p) {
                    preview = nil
                }
            }
            .fileImporter(
                isPresented: $exportFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleExportFolder(result)
            }
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
    }

    @ViewBuilder
    private var timelineArea: some View {
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

    @ViewBuilder
    private var previewSheet: some View {
        switch preview {
        case .single(let id):
            if let clip = vm.clip(for: id) {
                SinglePreviewView(
                    clip: clip,
                    isFavorite: vm.isFavorite(id, in: document),
                    onDismiss: { preview = nil },
                    onNavigate: { direction in
                        if let next = vm.neighbor(of: id, direction: direction) {
                            preview = .single(next.id)
                            vm.selectOnly(next.id)
                        }
                    },
                    onCrossTrack: {
                        if let other = vm.crossTrackNeighbor(of: id, in: document) {
                            preview = .single(other.id)
                            vm.selectOnly(other.id)
                        }
                    },
                    onTrash: { trashFromPreview(currentID: id) },
                    onToggleFavorite: { vm.toggleFavorite(id, in: &document) }
                )
            }
        case .ab(let aID, let bID):
            if let a = vm.clip(for: aID), let b = vm.clip(for: bID) {
                ABCompareView(
                    clipA: a,
                    clipB: b,
                    onDismiss: { preview = nil },
                    onNavigate: { direction in
                        let nextA = vm.neighbor(of: aID, direction: direction) ?? a
                        let nextB = vm.neighbor(of: bID, direction: direction) ?? b
                        preview = .ab(nextA.id, nextB.id)
                        vm.selection = [nextA.id, nextB.id]
                        vm.selectionAnchor = nextA.id
                    }
                )
            }
        case .none:
            EmptyView()
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
        // 决定删除后跳到哪张：先看下一张，没有就看上一张，再没有就关闭预览
        let next = vm.neighbor(of: currentID, direction: .next)
            ?? vm.neighbor(of: currentID, direction: .prev)
        _ = vm.trash([clip], in: &document)
        if let next {
            preview = .single(next.id)
            vm.selectOnly(next.id)
        } else {
            preview = nil
        }
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

#Preview {
    CompareDocumentView(document: .constant(CompareDocument()))
}

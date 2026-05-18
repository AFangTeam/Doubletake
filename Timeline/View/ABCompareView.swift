import SwiftUI
import AppKit

struct ABCompareView: View {
    let clipA: MediaClip
    let clipB: MediaClip
    let overlaySettings: PreviewOverlaySettings
    let initialSourceA: ImageSource
    let initialSourceB: ImageSource
    let isFloating: Bool
    var onDismiss: () -> Void
    var onNavigate: (CompareViewModel.NavDirection) -> Void = { _ in }
    /// 用户点了"保存对比"并填好名字之后：把名字、当前对比截图、原始（未调整）对比截图、视图参数一起回调出去。
    /// CompareDocumentView 负责弹 fileImporter 选父文件夹 + 写盘。
    var onSaveComparison: (String, CGImage?, CGImage?, ABComparisonInfo) -> Void = { _, _, _, _ in }
    var onToggleFullScreen: () -> Void = {}
    var onToggleFloating: () -> Void = {}

    enum Mode: String, CaseIterable {
        case split = "分屏"
        case curtain = "幕帘"
    }

    @State private var mode: Mode = .split
    @State private var zoom: Double = 1.0
    /// AB 的 pan 独立。默认拖动会同步两边；按住 ⌘ 起手拖只动起手那一侧。
    @State private var panA: CGSize = .zero
    @State private var panB: CGSize = .zero
    @State private var pinchBaseZoom: Double?
    @State private var dragBasePanA: CGSize?
    @State private var dragBasePanB: CGSize?
    @State private var dragSide: DragSide?
    @State private var dragIndependent: Bool = false
    @State private var curtainSplit: Double = 0.5

    @State private var sourceA: ImageSource
    @State private var sourceB: ImageSource
    @State private var stageSize: CGSize = .zero
    @FocusState private var focused: Bool

    // MARK: - 保存对比 UI
    @State private var savePopoverPresented: Bool = false
    @State private var saveNameDraft: String = ""

    private enum DragSide { case a, b }

    private let minZoom: Double = 0.2
    private let maxZoom: Double = 12.0

    init(
        clipA: MediaClip,
        clipB: MediaClip,
        overlaySettings: PreviewOverlaySettings,
        initialSourceA: ImageSource,
        initialSourceB: ImageSource,
        isFloating: Bool,
        onDismiss: @escaping () -> Void,
        onNavigate: @escaping (CompareViewModel.NavDirection) -> Void = { _ in },
        onSaveComparison: @escaping (String, CGImage?, CGImage?, ABComparisonInfo) -> Void = { _, _, _, _ in },
        onToggleFullScreen: @escaping () -> Void = {},
        onToggleFloating: @escaping () -> Void = {}
    ) {
        self.clipA = clipA
        self.clipB = clipB
        self.overlaySettings = overlaySettings
        self.initialSourceA = initialSourceA
        self.initialSourceB = initialSourceB
        self.isFloating = isFloating
        self.onDismiss = onDismiss
        self.onNavigate = onNavigate
        self.onSaveComparison = onSaveComparison
        self.onToggleFullScreen = onToggleFullScreen
        self.onToggleFloating = onToggleFloating
        self._sourceA = State(initialValue: initialSourceA)
        self._sourceB = State(initialValue: initialSourceB)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            GeometryReader { proxy in
                imageStage(in: proxy.size)
                    .onAppear { stageSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in stageSize = newSize }
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 980, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onChange(of: pinchBaseZoom) { _, _ in focused = true }
        .onChange(of: clipA.id) { _, _ in syncSourcesAndResetZoom() }
        .onChange(of: clipB.id) { _, _ in syncSourcesAndResetZoom() }
        .task(id: clipA.id) {
            await prefetchSources(for: clipA)
        }
        .task(id: clipB.id) {
            await prefetchSources(for: clipB)
        }
        // popover 输入框打开时让出键盘 —— 否则 Esc / Space / 方向键会被预览视图抢走，
        // 用户改名字想退到行首/行尾时会被这里劫持。
        .onKeyPress(.escape) {
            if savePopoverPresented { return .ignored }
            onDismiss(); return .handled
        }
        .onKeyPress(.space) {
            if savePopoverPresented { return .ignored }
            onDismiss(); return .handled
        }
        .onKeyPress(.leftArrow) {
            if savePopoverPresented { return .ignored }
            onNavigate(.prev); return .handled
        }
        .onKeyPress(.rightArrow) {
            if savePopoverPresented { return .ignored }
            onNavigate(.next); return .handled
        }
        .background {
            // 同窗口子视图 + keyboardShortcut，键盘事件路由稳定。
            // 行业惯例：弹出输入框（popover/dialog）展示时，**无修饰键**的字符快捷键全部禁用，
            // 否则用户输入 "j" / "0" / "=" / "F" 这些字符会触发预览功能而不是进文本框。
            // 只保留带 ⌘ 修饰符的快捷键 —— 它们和 macOS 文本框的编辑键不冲突。
            Group {
                if !savePopoverPresented {
                    // —— 无修饰键 / 仅 shift / 仅 ⌃⌘ 的快捷键，弹输入框时全部熄火 ——
                    Button { switchBothTo(.jpg) } label: { EmptyView() }
                        .keyboardShortcut("j", modifiers: [])
                    Button { switchBothTo(.jpg) } label: { EmptyView() }
                        .keyboardShortcut("J", modifiers: [])
                    Button { switchBothTo(.raw) } label: { EmptyView() }
                        .keyboardShortcut("r", modifiers: [])
                    Button { switchBothTo(.raw) } label: { EmptyView() }
                        .keyboardShortcut("R", modifiers: [])
                    Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                        .keyboardShortcut("=", modifiers: [])
                    Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                        .keyboardShortcut("+", modifiers: [])
                    Button { zoom = clamp(zoom * 0.8) } label: { EmptyView() }
                        .keyboardShortcut("-", modifiers: [])
                    Button { resetView() } label: { EmptyView() }
                        .keyboardShortcut("0", modifiers: [])
                    Button { onToggleFullScreen() } label: { EmptyView() }
                        .keyboardShortcut("F", modifiers: .shift)
                    Button { onToggleFullScreen() } label: { EmptyView() }
                        .keyboardShortcut("\\", modifiers: [])
                }
                // —— 带 ⌘ 的快捷键，文本输入时也保持可用 ——
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("=", modifiers: .command)
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("+", modifiers: .command)
                Button { zoom = clamp(zoom * 0.8) } label: { EmptyView() }
                    .keyboardShortcut("-", modifiers: .command)
                Button { resetView() } label: { EmptyView() }
                    .keyboardShortcut("0", modifiers: .command)
                Button { onToggleFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                Button { openSavePopover() } label: { EmptyView() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(savePopoverPresented)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    private func switchBothTo(_ target: ImageSource) {
        switch target {
        case .jpg:
            if clipA.jpgURL != nil { sourceA = .jpg }
            if clipB.jpgURL != nil { sourceB = .jpg }
        case .raw:
            if clipA.rawURL != nil { sourceA = .raw }
            if clipB.rawURL != nil { sourceB = .raw }
        }
        focused = true
    }

    private func resetView() {
        zoom = 1.0
        panA = .zero
        panB = .zero
    }

    /// "fraction of pane size"形式的 pan 转成实际渲染用的 pt 偏移
    private func panToPt(_ frac: CGSize, paneSize: CGSize, zoom: Double) -> CGSize {
        CGSize(
            width: frac.width * paneSize.width * zoom,
            height: frac.height * paneSize.height * zoom
        )
    }

    private func syncSourcesAndResetZoom() {
        if sourceA == .raw && clipA.rawURL == nil { sourceA = .jpg }
        if sourceA == .jpg && clipA.jpgURL == nil { sourceA = .raw }
        if sourceB == .raw && clipB.rawURL == nil { sourceB = .jpg }
        if sourceB == .jpg && clipB.jpgURL == nil { sourceB = .raw }
        resetView()
        focused = true
    }

    // MARK: - 顶栏（双侧 EXIF）

    @ViewBuilder
    private var topBar: some View {
        HStack(alignment: .top, spacing: 0) {
            ExifSummaryLine(clip: clipA, side: "A", tint: .blue, source: $sourceA)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 36).overlay(.white.opacity(0.2))
            ExifSummaryLine(clip: clipB, side: "B", tint: .orange, source: $sourceB)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - 图像区

    @ViewBuilder
    private func imageStage(in size: CGSize) -> some View {
        // 把"fraction of pane size"形式的 pan 当下算成实际 pt 偏移 ——
        // 同一份 pan 数据，live 和 snapshot 各自用自己的 pane 尺寸算 pt，跨尺寸不失真
        let paneSize: CGSize = {
            switch mode {
            case .split: return CGSize(width: size.width / 2, height: size.height)
            case .curtain: return size
            }
        }()
        let panAPt = panToPt(panA, paneSize: paneSize, zoom: zoom)
        let panBPt = panToPt(panB, paneSize: paneSize, zoom: zoom)

        switch mode {
        case .split:
            HStack(spacing: 1) {
                ZStack(alignment: .topLeading) {
                    ImagePane(url: clipA.url(for: sourceA), zoom: zoom, pan: panAPt)
                        .frame(width: size.width / 2, height: size.height)
                    ExifOverlayBadge(
                        clip: clipA,
                        settings: overlaySettings,
                        sideLabel: "A",
                        sideTint: .blue
                    )
                    .padding(14)
                    .allowsHitTesting(false)
                }
                .frame(width: size.width / 2, height: size.height)

                Rectangle().fill(.white.opacity(0.18)).frame(width: 1)

                ZStack(alignment: .topLeading) {
                    ImagePane(url: clipB.url(for: sourceB), zoom: zoom, pan: panBPt)
                        .frame(width: size.width / 2, height: size.height)
                    ExifOverlayBadge(
                        clip: clipB,
                        settings: overlaySettings,
                        sideLabel: "B",
                        sideTint: .orange
                    )
                    .padding(14)
                    .allowsHitTesting(false)
                }
                .frame(width: size.width / 2, height: size.height)
            }
            .contentShape(Rectangle())
            .gesture(panGesture(stageSize: size))
            .gesture(magnifyGesture)

        case .curtain:
            ZStack(alignment: .topLeading) {
                ImagePane(url: clipB.url(for: sourceB), zoom: zoom, pan: panBPt)
                    .frame(width: size.width, height: size.height)
                ImagePane(url: clipA.url(for: sourceA), zoom: zoom, pan: panAPt)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * curtainSplit)
                    }
                ExifOverlayBadge(
                    clip: clipA,
                    settings: overlaySettings,
                    sideLabel: "A",
                    sideTint: .blue
                )
                .padding(14)
                .allowsHitTesting(false)
                .opacity(curtainSplit > 0.12 ? 1 : 0)
                ExifOverlayBadge(
                    clip: clipB,
                    settings: overlaySettings,
                    sideLabel: "B",
                    sideTint: .orange
                )
                .padding(14)
                .padding(.leading, size.width * curtainSplit)
                .allowsHitTesting(false)
                .opacity(curtainSplit < 0.88 ? 1 : 0)

                CurtainHandle()
                    .position(x: size.width * curtainSplit, y: size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                curtainSplit = clampRatio(v.location.x / size.width)
                            }
                    )
            }
            .contentShape(Rectangle())
            .gesture(panGesture(stageSize: size))
            .gesture(magnifyGesture)
        }
    }

    private func panGesture(stageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                if dragBasePanA == nil {
                    // 起手判定：哪一侧 + 是否独立（看 ⌘ 修饰键）
                    let onA: Bool = {
                        switch mode {
                        case .split:
                            return value.startLocation.x < stageSize.width / 2
                        case .curtain:
                            return value.startLocation.x < stageSize.width * curtainSplit
                        }
                    }()
                    dragSide = onA ? .a : .b
                    dragIndependent = NSEvent.modifierFlags.contains(.command)
                    dragBasePanA = panA
                    dragBasePanB = panB
                }
                // 鼠标拖 dx pt → 累加到"fraction of pane"形式的 pan：
                //   pan += delta / (pane_size * zoom)
                // 这样无论之后 zoom 怎么变、pane 尺寸怎么变（live vs 截图），
                // 都能按各自的 pane 尺寸算出正确的 pt 偏移，保持图像内容对齐
                let paneW: CGFloat = {
                    switch mode {
                    case .split: return max(stageSize.width / 2, 1)
                    case .curtain: return max(stageSize.width, 1)
                    }
                }()
                let paneH = max(stageSize.height, 1)
                let invZoom = 1.0 / max(zoom, 0.01)
                let dx = value.translation.width * invZoom / paneW
                let dy = value.translation.height * invZoom / paneH
                let baseA = dragBasePanA ?? .zero
                let baseB = dragBasePanB ?? .zero

                if dragIndependent {
                    switch dragSide {
                    case .a:
                        panA = CGSize(width: baseA.width + dx, height: baseA.height + dy)
                    case .b:
                        panB = CGSize(width: baseB.width + dx, height: baseB.height + dy)
                    case .none:
                        break
                    }
                } else {
                    panA = CGSize(width: baseA.width + dx, height: baseA.height + dy)
                    panB = CGSize(width: baseB.width + dx, height: baseB.height + dy)
                }
            }
            .onEnded { _ in
                dragBasePanA = nil
                dragBasePanB = nil
                dragSide = nil
                dragIndependent = false
                focused = true
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchBaseZoom == nil { pinchBaseZoom = zoom }
                let base = pinchBaseZoom ?? zoom
                zoom = clamp(base * value.magnification)
            }
            .onEnded { _ in
                pinchBaseZoom = nil
                focused = true
            }
    }

    // MARK: - 底栏

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            Spacer()

            HStack(spacing: 6) {
                Button { onNavigate(.prev) } label: { Image(systemName: "chevron.left") }
                    .help("两轨同时上一张 (←)")
                Button { onNavigate(.next) } label: { Image(systemName: "chevron.right") }
                    .help("两轨同时下一张 (→)")
                Divider().frame(height: 18)
                Button { zoom = clamp(zoom * 0.8) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 56)
                Button { zoom = clamp(zoom * 1.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button("适配") {
                    resetView()
                }
                .controlSize(.small)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)

            Spacer()

            saveComparisonButton

            Button { onToggleFloating() } label: {
                Image(systemName: isFloating ? "pin.fill" : "pin")
                    .foregroundStyle(isFloating ? Color.accentColor : .white)
            }
            .help(isFloating ? "取消置顶" : "置顶（让对比窗浮在文档窗之上）")

            Button { onToggleFullScreen() } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("全屏（\\ 或 ⇧F 或 ⌃⌘F）")

            Button("退出对比") {
                onDismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var saveComparisonButton: some View {
        Button {
            openSavePopover()
        } label: {
            Label("保存对比", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help("把当前 AB 对比导出到一个文件夹：A、B 原文件 + 对比截图（⌘S）")
        .popover(isPresented: $savePopoverPresented, arrowEdge: .top) {
            SaveComparisonPopover(
                name: $saveNameDraft,
                onCommit: {
                    let name = saveNameDraft
                    savePopoverPresented = false
                    // ImageRenderer 是同步的，跑不动 ImagePane 的 .task 异步加载。
                    // 必须先把两张图的 CGImage 显式拿到，再喂给一个只用 CGImage 的快照视图。
                    // 这里专门走 8192 长边的"保存级"高分图（而不是预览用的 6144），
                    // 让最终 PNG 在 100% 看不糊。
                    Task { @MainActor in
                        let urlA = clipA.url(for: sourceA)
                        let urlB = clipB.url(for: sourceB)
                        async let aImg = FullImageLoader.shared.image(for: urlA, maxPixel: 8192)
                        async let bImg = FullImageLoader.shared.image(for: urlB, maxPixel: 8192)
                        let imgA = await aImg
                        let imgB = await bImg
                        // 第一张：用户当前看到的对比（带 zoom / 拖动校正），底部带"N×"角标
                        let png = renderComparisonImage(
                            cgImageA: imgA, cgImageB: imgB,
                            mode: mode, zoom: zoom,
                            panA: panA, panB: panB, curtainSplit: curtainSplit,
                            showZoomBadge: true
                        )
                        // 第二张：原始未调整的对比（zoom=1，无位移，强制分屏左右摆），不带角标
                        let originalPng = renderComparisonImage(
                            cgImageA: imgA, cgImageB: imgB,
                            mode: .split, zoom: 1.0,
                            panA: .zero, panB: .zero, curtainSplit: 0.5,
                            showZoomBadge: false
                        )
                        let info = buildInfo(name: name)
                        onSaveComparison(name, png, originalPng, info)
                    }
                },
                onCancel: { savePopoverPresented = false }
            )
        }
    }

    private func openSavePopover() {
        saveNameDraft = defaultSaveName()
        savePopoverPresented = true
        focused = false
    }

    private func defaultSaveName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "AB-对比 \(f.string(from: Date()))"
    }

    private func buildInfo(name: String) -> ABComparisonInfo {
        ABComparisonInfo(
            savedAtEpoch: Date().timeIntervalSince1970,
            mode: mode == .split ? "split" : "curtain",
            zoom: zoom,
            panAX: Double(panA.width),
            panAY: Double(panA.height),
            panBX: Double(panB.width),
            panBY: Double(panB.height),
            curtainSplit: curtainSplit,
            sourceA: sourceA.rawValue,
            sourceB: sourceB.rawValue,
            clipASummary: .from(clipA),
            clipBSummary: .from(clipB)
        )
    }

    /// 用 ImageRenderer 重渲染 stage（不带工具栏 / EXIF 顶栏），输出高分 PNG。
    /// 关键：传进来的是已经异步加载完的 CGImage，快照视图同步出图，不依赖 .task。
    /// mode/zoom/pan/curtain 由调用方指定 —— 这样 "当前对比" 和 "原始未调整对比"
    /// 可以共用同一份渲染管线
    @MainActor
    private func renderComparisonImage(
        cgImageA: CGImage?,
        cgImageB: CGImage?,
        mode: Mode,
        zoom: Double,
        panA: CGSize,
        panB: CGSize,
        curtainSplit: Double,
        showZoomBadge: Bool
    ) -> CGImage? {
        let renderSize = computedRenderSize(forMode: mode)
        let view = ABStageSnapshotView(
            clipA: clipA,
            clipB: clipB,
            cgImageA: cgImageA,
            cgImageB: cgImageB,
            mode: mode,
            zoom: zoom,
            panA: panA,
            panB: panB,
            curtainSplit: curtainSplit,
            overlaySettings: overlaySettings,
            renderSize: renderSize,
            showZoomBadge: showZoomBadge
        )
        let renderer = ImageRenderer(content: view)
        // scale = 1：renderSize 本身就是目标像素数（不再 ×2），
        // 这样 SwiftUI Image 内部走的也是源 CGImage → 输出像素的 1:1 高质量插值，
        // 不会先把图缩成小尺寸视图再拉伸。
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: renderSize.width, height: renderSize.height)
        return renderer.cgImage
    }

    /// 输出像素尺寸：保持 stage 比例，长边足够大。
    /// - split 模式长边 7680（左右各 3840px pane —— 比绝大多数显示器的物理像素都大）
    /// - curtain 长边 4096
    /// stageSize 没拿到则给个 16:9 兜底。
    private func computedRenderSize(forMode mode: Mode) -> CGSize {
        let fallback = CGSize(width: 1920, height: 1080)
        let s = stageSize.width > 0 && stageSize.height > 0 ? stageSize : fallback
        let aspect = s.width / s.height
        let longEdge: CGFloat = mode == .split ? 7680 : 4096
        var w: CGFloat
        var h: CGFloat
        if aspect >= 1 {
            w = longEdge
            h = longEdge / aspect
        } else {
            h = longEdge
            w = longEdge * aspect
        }
        // 双保险：单边不超过 8192 防爆内存（ImageRenderer 在极大尺寸可能挂）
        let cap: CGFloat = 8192
        let m = max(w, h)
        if m > cap {
            let k = cap / m
            w *= k
            h *= k
        }
        return CGSize(width: w, height: h)
    }

    private func clamp(_ z: Double) -> Double {
        Swift.min(Swift.max(z, minZoom), maxZoom)
    }
    private func clampRatio(_ r: Double) -> Double {
        Swift.min(Swift.max(r, 0.02), 0.98)
    }

    private func prefetchSources(for clip: MediaClip) async {
        await withTaskGroup(of: Void.self) { group in
            if let jpg = clip.jpgURL {
                group.addTask {
                    _ = await ThumbnailLoader.shared.thumbnail(for: jpg, sizeBucket: 2048)
                }
                group.addTask {
                    _ = await FullImageLoader.shared.image(for: jpg)
                }
            }
            if let raw = clip.rawURL {
                group.addTask {
                    _ = await ThumbnailLoader.shared.thumbnail(for: raw, sizeBucket: 2048)
                }
                group.addTask {
                    _ = await FullImageLoader.shared.image(for: raw)
                }
            }
        }
    }
}

// MARK: - 保存对比 popover

private struct SaveComparisonPopover: View {
    @Binding var name: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("保存这一次 AB 对比")
                .font(.headline)
            Text("给这次对比起个名字。会在你选的文件夹下建一个同名子文件夹，写入 A、B 两边的原文件和当前画面的对比截图 PNG。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("名字", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { onCommit() }
                .frame(minWidth: 320)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("下一步：选文件夹…") { onCommit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { nameFocused = true }
    }
}

// MARK: - Curtain handle

private struct CurtainHandle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(width: 2)
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                }
                .shadow(radius: 4)
        }
        .frame(width: 28, height: 220)
        .contentShape(Rectangle())
    }
}

// MARK: - EXIF top-bar line

private struct ExifSummaryLine: View {
    let clip: MediaClip
    let side: String
    let tint: Color
    @Binding var source: ImageSource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(side)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.4), in: Capsule())
                Text(clip.displayName)
                    .font(.system(.callout, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if clip.hasBothSources {
                    Picker("", selection: $source) {
                        Text("JPG").tag(ImageSource.jpg)
                        Text("RAW").tag(ImageSource.raw)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                }
            }
            HStack(spacing: 10) {
                Text(clip.captureDate.formatted(date: .abbreviated, time: .standard))
                    .font(.system(.caption, design: .monospaced))
                if let f = clip.metadata.focalLengthDisplay {
                    Label(f, systemImage: "camera.aperture")
                        .font(.caption)
                }
                if let a = clip.metadata.apertureDisplay {
                    Text(a).font(.system(.caption, design: .monospaced))
                }
                if let s = clip.metadata.shutterDisplay {
                    Text(s).font(.system(.caption, design: .monospaced))
                }
                if let i = clip.metadata.isoDisplay {
                    Text(i).font(.system(.caption, design: .monospaced))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 6) {
                if let cam = clip.metadata.cameraModel {
                    Text(cam)
                }
                if clip.metadata.cameraModel != nil, clip.metadata.lensModel != nil {
                    Text("·")
                }
                if let lens = clip.metadata.lensModel {
                    Label(lens, systemImage: "camera.metering.matrix")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
    }
}

// MARK: - 对比截图重渲染视图

/// 与 `ABCompareView.imageStage` 视觉一致，但内部用同步的 CGImage 出图（不是异步 ImagePane），
/// 这样 ImageRenderer 一次性把当前画面定格到 PNG。
struct ABStageSnapshotView: View {
    let clipA: MediaClip
    let clipB: MediaClip
    let cgImageA: CGImage?
    let cgImageB: CGImage?
    let mode: ABCompareView.Mode
    let zoom: Double
    let panA: CGSize
    let panB: CGSize
    let curtainSplit: Double
    let overlaySettings: PreviewOverlaySettings
    let renderSize: CGSize
    /// 是否在底部画"放大 N×"的角标。原始未调整对比图不画（永远 1×，意义不大）
    var showZoomBadge: Bool = false

    /// 截图渲染时的视觉缩放倍数（角标、外圈 padding 一起放大），让 7680×4320 的大画布里也看得清。
    private let snapScale: CGFloat = 10.0

    var body: some View {
        // panA/panB 是"fraction of pane size"，用快照自己的 pane 尺寸算出 pt 偏移
        let paneSize: CGSize = {
            switch mode {
            case .split: return CGSize(width: renderSize.width / 2, height: renderSize.height)
            case .curtain: return renderSize
            }
        }()
        let panAPt = CGSize(width: panA.width * paneSize.width * zoom, height: panA.height * paneSize.height * zoom)
        let panBPt = CGSize(width: panB.width * paneSize.width * zoom, height: panB.height * paneSize.height * zoom)

        ZStack {
            Color.black
            switch mode {
            case .split:
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        SyncCGImagePane(image: cgImageA, zoom: zoom, pan: panAPt)
                            .frame(width: renderSize.width / 2, height: renderSize.height)
                        ExifOverlayBadge(
                            clip: clipA,
                            settings: overlaySettings,
                            sideLabel: "A",
                            sideTint: .blue,
                            scale: snapScale
                        )
                        .padding(14 * snapScale)
                    }
                    .frame(width: renderSize.width / 2, height: renderSize.height)
                    .clipped()

                    // 分屏分界线在 7680 宽的 PNG 里加粗到 6 px、对比度提到 0.75，
                    // 既清晰又不抢图
                    Rectangle().fill(.white.opacity(0.75)).frame(width: 6)

                    ZStack(alignment: .topLeading) {
                        SyncCGImagePane(image: cgImageB, zoom: zoom, pan: panBPt)
                            .frame(width: renderSize.width / 2, height: renderSize.height)
                        ExifOverlayBadge(
                            clip: clipB,
                            settings: overlaySettings,
                            sideLabel: "B",
                            sideTint: .orange,
                            scale: snapScale
                        )
                        .padding(14 * snapScale)
                    }
                    .frame(width: renderSize.width / 2, height: renderSize.height)
                    .clipped()
                }
            case .curtain:
                ZStack(alignment: .topLeading) {
                    SyncCGImagePane(image: cgImageB, zoom: zoom, pan: panBPt)
                        .frame(width: renderSize.width, height: renderSize.height)
                    SyncCGImagePane(image: cgImageA, zoom: zoom, pan: panAPt)
                        .frame(width: renderSize.width, height: renderSize.height)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: renderSize.width * curtainSplit)
                        }
                    // 幕帘模式下也画一条分割线（截图里看得清楚两侧边界）
                    Rectangle()
                        .fill(.white.opacity(0.75))
                        .frame(width: 6, height: renderSize.height)
                        .offset(x: renderSize.width * curtainSplit - 3)
                    ExifOverlayBadge(
                        clip: clipA,
                        settings: overlaySettings,
                        sideLabel: "A",
                        sideTint: .blue,
                        scale: snapScale
                    )
                    .padding(14 * snapScale)
                    .opacity(curtainSplit > 0.12 ? 1 : 0)
                    ExifOverlayBadge(
                        clip: clipB,
                        settings: overlaySettings,
                        sideLabel: "B",
                        sideTint: .orange,
                        scale: snapScale
                    )
                    .padding(14 * snapScale)
                    .padding(.leading, renderSize.width * curtainSplit)
                    .opacity(curtainSplit < 0.88 ? 1 : 0)
                }
                .clipped()
            }

            if showZoomBadge {
                // 底部居中、留 ~12% 字幕安全区。设计语言和左上 A/B 角标一致：
                // 黑色透明底 + ultraThinMaterial 提亮 + 白色半透明描边 + 软阴影
                VStack {
                    Spacer()
                    ZoomLevelBadge(zoom: zoom, scale: snapScale)
                    Spacer().frame(height: renderSize.height * 0.12)
                }
                .frame(width: renderSize.width, height: renderSize.height)
                .allowsHitTesting(false)
            }
        }
        .frame(width: renderSize.width, height: renderSize.height)
    }
}

/// 同步版的 ImagePane：CGImage 已经在外面加载好，这里只负责按 zoom/pan 摆位。
/// ImageRenderer 跑这种纯同步视图能即时出图。
private struct SyncCGImagePane: View {
    let image: CGImage?
    let zoom: Double
    let pan: CGSize

    var body: some View {
        ZStack {
            Color.black
            if let img = image {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(zoom)
                    // pan 是上游算好的 pt 偏移，直接用
                    .offset(pan)
            }
        }
    }
}

/// 底部"放大 N×"角标 —— 沿用 ExifOverlayBadge 的设计语言（黑底 + ultraThinMaterial
/// 提亮 + 白色半透描边 + 软阴影），但形态是水平横条形 + 居中放置。
private struct ZoomLevelBadge: View {
    let zoom: Double
    let scale: CGFloat

    private var label: String {
        // 1.0 显示 "1×"，2.5 显示 "2.5×"，10 显示 "10×"
        if abs(zoom - zoom.rounded()) < 0.05 {
            return String(format: "%.0f×", zoom)
        }
        return String(format: "%.1f×", zoom)
    }

    var body: some View {
        Text(label)
            .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18 * scale)
            .padding(.vertical, 9 * scale)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.32))
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6 * scale)
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 9 * scale, y: 3 * scale)
    }
}

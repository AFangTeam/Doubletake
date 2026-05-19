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
    /// 用户在 NSSavePanel 里选好"位置 + 名字"之后：把名字、父文件夹、对比截图、
    /// 原始（未调整）对比截图、视图参数一起回调出去。CompareDocumentView 写盘。
    /// 走原生 NSSavePanel 比"命名 popover → 文件夹 picker → alert"三步链顺得多。
    var onSaveComparison: (String, URL, CGImage?, CGImage?, ABComparisonInfo) -> Void = { _, _, _, _, _ in }
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
        onSaveComparison: @escaping (String, URL, CGImage?, CGImage?, ABComparisonInfo) -> Void = { _, _, _, _, _ in },
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
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.space) { onDismiss(); return .handled }
        .onKeyPress(.leftArrow) { onNavigate(.prev); return .handled }
        .onKeyPress(.rightArrow) { onNavigate(.next); return .handled }
        .background {
            // 同窗口子视图 + keyboardShortcut，键盘事件路由稳定。NSSavePanel 接管
            // 文本输入时是独立窗口，不会和这里的字符快捷键打架，安全。
            Group {
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
                Button { openSavePanel() } label: { EmptyView() }
                    .keyboardShortcut("s", modifiers: .command)
                Button { onDismiss() } label: { EmptyView() }
                    .keyboardShortcut("w", modifiers: .command)
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
        .background(.ultraThinMaterial)
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
                        sideTint: .blue,
                        diffWith: clipB.metadata
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
                        sideTint: .orange,
                        diffWith: clipA.metadata
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
                    sideTint: .blue,
                    diffWith: clipB.metadata
                )
                .padding(14)
                .allowsHitTesting(false)
                .opacity(curtainSplit > 0.12 ? 1 : 0)
                ExifOverlayBadge(
                    clip: clipB,
                    settings: overlaySettings,
                    sideLabel: "B",
                    sideTint: .orange,
                    diffWith: clipA.metadata
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
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var saveComparisonButton: some View {
        Button {
            openSavePanel()
        } label: {
            Label("保存对比", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help("把当前 AB 对比导出到一个文件夹：A、B 原文件 + 对比截图（⌘S）")
    }

    /// 走原生 NSSavePanel —— 名字 + 父文件夹一并选好，少一次操作。
    private func openSavePanel() {
        let panel = NSSavePanel()
        panel.title = "保存 AB 对比"
        panel.message = "选择对比集要保存到哪个文件夹"
        panel.prompt = "保存"
        panel.nameFieldLabel = "对比集名称："
        panel.nameFieldStringValue = defaultSaveName()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = true

        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            Task { @MainActor in
                await performSaveComparison(destination: destURL)
            }
        }
    }

    /// destination 是 NSSavePanel 返回的"父文件夹 / 名字"完整路径。
    /// 我们拆出 name + parentFolder 交给上游写盘。
    @MainActor
    private func performSaveComparison(destination: URL) async {
        let name = destination.lastPathComponent
        let parent = destination.deletingLastPathComponent()

        let urlA = clipA.url(for: sourceA)
        let urlB = clipB.url(for: sourceB)
        // 全分辨率源解码（含 EXIF 方向），高 zoom 时尽可能拿到源像素
        async let aImg = FullImageLoader.shared.fullResolutionImage(for: urlA)
        async let bImg = FullImageLoader.shared.fullResolutionImage(for: urlB)
        let imgA = await aImg
        let imgB = await bImg
        if let imgA, let imgB {
            print("[Comparison] sourceA: \(imgA.width)×\(imgA.height), sourceB: \(imgB.width)×\(imgB.height)")
        }
        // 第一张：当前视角（zoom / pan 已应用），带 "N×" 缩放徽标
        let png = renderComparisonImage(
            cgImageA: imgA, cgImageB: imgB,
            mode: mode, zoom: zoom,
            panA: panA, panB: panB, curtainSplit: curtainSplit,
            showZoomBadge: true
        )
        // 第二张：未调整的对照（zoom=1，无位移，强制分屏），不带缩放徽标
        let originalPng = renderComparisonImage(
            cgImageA: imgA, cgImageB: imgB,
            mode: .split, zoom: 1.0,
            panA: .zero, panB: .zero, curtainSplit: 0.5,
            showZoomBadge: false
        )
        let info = buildInfo(name: name)
        onSaveComparison(name, parent, png, originalPng, info)
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

    /// **混合渲染管线**：
    /// - 照片内容走 **CGContext 直接画**（pixel-perfect，无 SwiftUI/Metal cap、无半分辨率 bug）
    /// - 角标 / 分界线 / 缩放徽标走 **SwiftUI ImageRenderer**（透明背景，只画 overlay）
    /// - 二者用 CGContext 合成
    ///
    /// 这是用户提出的"先裁切后压缩"的彻底实现 —— 源 CGImage（全分辨率）被直接
    /// 喂给 CGContext.draw(image, in:)，按 zoom/pan 计算 dstRect，CGContext 用
    /// kCGInterpolationHigh 做必要的上下采样，最后只在落盘时做一次 JPEG 压缩。
    /// SwiftUI ImageRenderer 在 macOS 26 上对 8K 输出有 ½ 分辨率 bug，全权绕开。
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
        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        guard w > 0, h > 0 else { return nil }

        // —— Step 1: CGContext 画照片层（全分辨率源 → 裁切到 pane）——
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let photoCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        photoCtx.interpolationQuality = .high
        // 翻成"top-left Y-down"，和 SwiftUI 同坐标系，公式好写
        photoCtx.translateBy(x: 0, y: CGFloat(h))
        photoCtx.scaleBy(x: 1, y: -1)

        photoCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        photoCtx.fill(CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))

        let paneW: CGFloat = mode == .split ? renderSize.width / 2 : renderSize.width
        let paneH = renderSize.height

        switch mode {
        case .split:
            let paneARect = CGRect(x: 0, y: 0, width: paneW, height: paneH)
            let paneBRect = CGRect(x: paneW, y: 0, width: paneW, height: paneH)
            drawPhotoCrop(in: photoCtx, image: cgImageA, paneRect: paneARect, zoom: zoom, panFraction: panA)
            drawPhotoCrop(in: photoCtx, image: cgImageB, paneRect: paneBRect, zoom: zoom, panFraction: panB)
            // 6 px 白线分界，opacity 0.75
            photoCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
            photoCtx.fill(CGRect(x: paneW - 3, y: 0, width: 6, height: paneH))
        case .curtain:
            let fullPane = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
            drawPhotoCrop(in: photoCtx, image: cgImageB, paneRect: fullPane, zoom: zoom, panFraction: panB)
            photoCtx.saveGState()
            photoCtx.clip(to: CGRect(x: 0, y: 0, width: renderSize.width * curtainSplit, height: renderSize.height))
            drawPhotoCrop(in: photoCtx, image: cgImageA, paneRect: fullPane, zoom: zoom, panFraction: panA)
            photoCtx.restoreGState()
            let dividerX = renderSize.width * curtainSplit - 3
            photoCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
            photoCtx.fill(CGRect(x: dividerX, y: 0, width: 6, height: renderSize.height))
        }

        guard let photoCanvas = photoCtx.makeImage() else { return nil }

        // —— Step 2: SwiftUI overlay 层（透明背景，只有角标 + 缩放徽标）——
        let overlay = ABStageOverlayView(
            clipA: clipA, clipB: clipB,
            mode: mode, zoom: zoom,
            curtainSplit: curtainSplit,
            overlaySettings: overlaySettings,
            renderSize: renderSize,
            showZoomBadge: showZoomBadge
        )
        let renderer = ImageRenderer(content: overlay)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        renderer.proposedSize = ProposedViewSize(width: renderSize.width, height: renderSize.height)
        let overlayCG = renderer.cgImage

        // —— Step 3: 合成 ——
        guard let composeCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return photoCanvas }
        composeCtx.interpolationQuality = .high
        let fullRect = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        composeCtx.draw(photoCanvas, in: fullRect)
        if let overlayCG {
            composeCtx.draw(overlayCG, in: fullRect)
        }
        let finalCG = composeCtx.makeImage()
        if let cg = finalCG {
            print("[Comparison] requested \(w)×\(h) → output \(cg.width)×\(cg.height) (overlay \(overlayCG?.width ?? 0)×\(overlayCG?.height ?? 0))")
        }
        return finalCG
    }

    /// 在 CGContext 里画一张照片的"按 zoom/pan 裁切版"。
    /// 参数全部按 SwiftUI 的 top-left Y-down 坐标，配合 photoCtx 已经做的翻转。
    @MainActor
    private func drawPhotoCrop(
        in ctx: CGContext,
        image: CGImage?,
        paneRect: CGRect,
        zoom: Double,
        panFraction: CGSize
    ) {
        guard let image else { return }
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        // 复刻 SwiftUI 的 .scaledToFit().scaleEffect(zoom).offset(panInPt)：
        let fitScale = min(paneRect.width / srcW, paneRect.height / srcH)
        let displayW = srcW * fitScale * zoom
        let displayH = srcH * fitScale * zoom
        let panX = panFraction.width * paneRect.width * zoom
        let panY = panFraction.height * paneRect.height * zoom
        let dstX = paneRect.midX - displayW / 2 + panX
        let dstY = paneRect.midY - displayH / 2 + panY
        let dstRect = CGRect(x: dstX, y: dstY, width: displayW, height: displayH)

        ctx.saveGState()
        ctx.clip(to: paneRect)
        // 在翻转后的 Y-down ctx 里把 image 画正：本地再翻一次
        ctx.translateBy(x: dstRect.minX, y: dstRect.minY + dstRect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: dstRect.width, height: dstRect.height))
        ctx.restoreGState()
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

// MARK: - Curtain handle

private struct CurtainHandle: View {
    var body: some View {
        ZStack {
            // 中央竖线（保持纤细可见，但用半透明白匹配玻璃质感）
            Rectangle()
                .fill(.white.opacity(0.65))
                .frame(width: 1.5)

            // 把手胶囊：复用全局玻璃质感
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassCapsule()
        }
        .frame(width: 32, height: 220)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
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

// MARK: - 对比截图 SwiftUI overlay 层

/// 给 `renderComparisonImage` 用的"透明 overlay 层"：只画角标 + 缩放徽标，
/// 照片区域是 Color.clear。CGContext 合成时 透明区域显示底下的照片画布。
/// 分界线由 CGContext 画，本视图不画。
struct ABStageOverlayView: View {
    let clipA: MediaClip
    let clipB: MediaClip
    let mode: ABCompareView.Mode
    let zoom: Double
    let curtainSplit: Double
    let overlaySettings: PreviewOverlaySettings
    let renderSize: CGSize
    let showZoomBadge: Bool

    private let snapScale: CGFloat = 10.0

    var body: some View {
        ZStack {
            Color.clear

            switch mode {
            case .split:
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: renderSize.width / 2, height: renderSize.height)
                        ExifOverlayBadge(
                            clip: clipA,
                            settings: overlaySettings,
                            sideLabel: "A",
                            sideTint: .blue,
                            scale: snapScale,
                            diffWith: clipB.metadata
                        )
                        .padding(14 * snapScale)
                    }
                    .frame(width: renderSize.width / 2, height: renderSize.height)
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: renderSize.width / 2, height: renderSize.height)
                        ExifOverlayBadge(
                            clip: clipB,
                            settings: overlaySettings,
                            sideLabel: "B",
                            sideTint: .orange,
                            scale: snapScale,
                            diffWith: clipA.metadata
                        )
                        .padding(14 * snapScale)
                    }
                    .frame(width: renderSize.width / 2, height: renderSize.height)
                }
            case .curtain:
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: renderSize.width, height: renderSize.height)
                    ExifOverlayBadge(
                        clip: clipA,
                        settings: overlaySettings,
                        sideLabel: "A",
                        sideTint: .blue,
                        scale: snapScale,
                        diffWith: clipB.metadata
                    )
                    .padding(14 * snapScale)
                    .opacity(curtainSplit > 0.12 ? 1 : 0)
                    ExifOverlayBadge(
                        clip: clipB,
                        settings: overlaySettings,
                        sideLabel: "B",
                        sideTint: .orange,
                        scale: snapScale,
                        diffWith: clipA.metadata
                    )
                    .padding(14 * snapScale)
                    .padding(.leading, renderSize.width * curtainSplit)
                    .opacity(curtainSplit < 0.88 ? 1 : 0)
                }
            }

            if showZoomBadge {
                VStack {
                    Spacer()
                    ZoomLevelBadge(zoom: zoom, scale: snapScale)
                    Spacer().frame(height: renderSize.height * 0.12)
                }
                .frame(width: renderSize.width, height: renderSize.height)
            }
        }
        .frame(width: renderSize.width, height: renderSize.height)
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

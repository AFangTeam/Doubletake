import SwiftUI
import AppKit

struct SinglePreviewView: View {
    let clip: MediaClip
    let isFavorite: Bool
    let overlaySettings: PreviewOverlaySettings
    let initialSource: ImageSource
    let isFloating: Bool
    var onDismiss: () -> Void
    var onNavigate: (CompareViewModel.NavDirection) -> Void
    var onCrossTrack: () -> Void
    var onTrash: () -> Void
    var onToggleFavorite: () -> Void
    var onToggleFullScreen: () -> Void
    var onToggleFloating: () -> Void

    @State private var zoom: Double = 1.0
    /// "fraction of pane size" 形式存储 —— 渲染端 × pane_size × zoom 还原成 pt 偏移
    @State private var pan: CGSize = .zero
    @State private var pinchBase: Double?
    @State private var dragBase: CGSize?
    @State private var paneSize: CGSize = .zero
    @State private var source: ImageSource
    @FocusState private var focused: Bool

    private let minZoom: Double = 0.2
    private let maxZoom: Double = 8.0

    init(
        clip: MediaClip,
        isFavorite: Bool,
        overlaySettings: PreviewOverlaySettings,
        initialSource: ImageSource,
        isFloating: Bool,
        onDismiss: @escaping () -> Void,
        onNavigate: @escaping (CompareViewModel.NavDirection) -> Void,
        onCrossTrack: @escaping () -> Void,
        onTrash: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onToggleFullScreen: @escaping () -> Void,
        onToggleFloating: @escaping () -> Void
    ) {
        self.clip = clip
        self.isFavorite = isFavorite
        self.overlaySettings = overlaySettings
        self.initialSource = initialSource
        self.isFloating = isFloating
        self.onDismiss = onDismiss
        self.onNavigate = onNavigate
        self.onCrossTrack = onCrossTrack
        self.onTrash = onTrash
        self.onToggleFavorite = onToggleFavorite
        self.onToggleFullScreen = onToggleFullScreen
        self.onToggleFloating = onToggleFloating
        self._source = State(initialValue: initialSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack(alignment: .topLeading) {
                GeometryReader { proxy in
                    ImagePane(
                        url: clip.url(for: source),
                        zoom: zoom,
                        pan: CGSize(
                            width: pan.width * proxy.size.width * zoom,
                            height: pan.height * proxy.size.height * zoom
                        )
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .onAppear { paneSize = proxy.size }
                    .onChange(of: proxy.size) { _, new in paneSize = new }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(panGesture)
                .gesture(magnifyGesture)

                ExifOverlayBadge(
                    clip: clip,
                    settings: overlaySettings,
                    sideLabel: nil
                )
                .padding(.top, 14)
                .padding(.leading, 14)
                .allowsHitTesting(false)

                sourceBadge
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        // gesture 结束后强制把焦点拉回来，保证 J/R/方向键等 onKeyPress 持续响应
        .onChange(of: pinchBase) { _, _ in focused = true }
        .onChange(of: dragBase) { _, _ in focused = true }
        .onChange(of: clip.id) { _, _ in
            zoom = 1.0
            pan = .zero
            // 新 clip 不支持当前 source 时回退
            if source == .raw && clip.rawURL == nil { source = .jpg }
            if source == .jpg && clip.jpgURL == nil { source = .raw }
            focused = true
        }
        .task(id: clip.id) {
            // 进入时同时预取两个源到磁盘缓存，切换瞬间出图
            await prefetchBothSources()
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.space) { onDismiss(); return .handled }
        .onKeyPress(.leftArrow) { onNavigate(.prev); return .handled }
        .onKeyPress(.rightArrow) { onNavigate(.next); return .handled }
        .onKeyPress(.upArrow) { onCrossTrack(); return .handled }
        .onKeyPress(.downArrow) { onCrossTrack(); return .handled }
        .background {
            // 这些"隐藏按钮 + keyboardShortcut"在 sheet 内是窗口级响应，
            // 不依赖具体哪个 SwiftUI 视图持有焦点 —— 解决放大/拖动之后
            // J/R 等 onKeyPress 失灵的问题。
            Group {
                Button { if clip.jpgURL != nil { source = .jpg } } label: { EmptyView() }
                    .keyboardShortcut("j", modifiers: [])
                Button { if clip.jpgURL != nil { source = .jpg } } label: { EmptyView() }
                    .keyboardShortcut("J", modifiers: [])
                Button { if clip.rawURL != nil { source = .raw } } label: { EmptyView() }
                    .keyboardShortcut("r", modifiers: [])
                Button { if clip.rawURL != nil { source = .raw } } label: { EmptyView() }
                    .keyboardShortcut("R", modifiers: [])
                Button { onToggleFavorite() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: [])
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("=", modifiers: [])
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("+", modifiers: [])
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("=", modifiers: .command)
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("+", modifiers: .command)
                Button { zoom = clamp(zoom * 0.8) } label: { EmptyView() }
                    .keyboardShortcut("-", modifiers: [])
                Button { zoom = clamp(zoom * 0.8) } label: { EmptyView() }
                    .keyboardShortcut("-", modifiers: .command)
                Button { zoom = 1.0; pan = .zero } label: { EmptyView() }
                    .keyboardShortcut("0", modifiers: [])
                Button { zoom = 1.0; pan = .zero } label: { EmptyView() }
                    .keyboardShortcut("0", modifiers: .command)
                Button { onTrash() } label: { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button { onToggleFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                // 更顺手的全屏快捷键：⇧F、反斜杠
                Button { onToggleFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("F", modifiers: .shift)
                Button { onToggleFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("\\", modifiers: [])
                // ⌘W 关闭预览窗（标准 macOS 行为）
                Button { onDismiss() } label: { EmptyView() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - 图区角标（可点切换源）

    @ViewBuilder
    private var sourceBadge: some View {
        let canToggle = clip.hasBothSources
        Button {
            if canToggle {
                source = (source == .jpg) ? .raw : .jpg
                focused = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(source.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                if canToggle {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassCapsule()
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(canToggle ? "点击切换 JPG ↔ RAW（快捷键 J / R）" : "本张图只有 \(source.rawValue) 一种源")
    }

    // MARK: - 顶栏

    @ViewBuilder
    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(clip.track == .a ? "A" : "B")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((clip.track == .a ? Color.blue : .orange).opacity(0.45), in: Capsule())
                .foregroundStyle(.white)

            Text(clip.displayName)
                .font(.system(.callout, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)

            Text(clip.captureDate.formatted(date: .abbreviated, time: .standard))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 10) {
                if let f = clip.metadata.focalLengthDisplay {
                    Label(f, systemImage: "camera.aperture").font(.caption)
                }
                if let a = clip.metadata.apertureDisplay { Text(a).font(.system(.caption, design: .monospaced)) }
                if let s = clip.metadata.shutterDisplay { Text(s).font(.system(.caption, design: .monospaced)) }
                if let i = clip.metadata.isoDisplay { Text(i).font(.system(.caption, design: .monospaced)) }
                if let lens = clip.metadata.lensModel {
                    Text("·").foregroundStyle(.tertiary)
                    Label(lens, systemImage: "camera.metering.matrix")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }
            .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFavorite ? .red : .white)
                    .padding(.horizontal, 6)
                    // 切换收藏时心形弹一下：1.0 → 1.35 → 0.95 → 1.0
                    .symbolEffect(.bounce, value: isFavorite)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "取消红心 (F)" : "加红心 (F)")

            if clip.hasBothSources {
                Picker("", selection: $source) {
                    Text("JPG").tag(ImageSource.jpg)
                    Text("RAW").tag(ImageSource.raw)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - 底栏

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { onNavigate(.prev) } label: {
                Image(systemName: "chevron.left")
            }
            .help("上一张 (←)")

            Button { onNavigate(.next) } label: {
                Image(systemName: "chevron.right")
            }
            .help("下一张 (→)")

            Spacer()

            HStack(spacing: 6) {
                Button { zoom = clamp(zoom * 0.8) } label: { Image(systemName: "minus.magnifyingglass") }
                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 56)
                Button { zoom = clamp(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                Button("适配") { zoom = 1.0; pan = .zero }
                    .controlSize(.small)
            }

            Spacer()

            Button { onToggleFloating() } label: {
                Image(systemName: isFloating ? "pin.fill" : "pin")
                    .foregroundStyle(isFloating ? Color.accentColor : .white)
            }
            .help(isFloating ? "取消置顶" : "置顶（让预览窗浮在文档窗之上）")

            Button { onToggleFullScreen() } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("全屏（\\ 或 ⇧F 或 ⌃⌘F）")

            Button(role: .destructive) { onTrash() } label: {
                Label("放入废纸篓", systemImage: "trash")
            }
            .help("⌘⌫")

            Button("退出 (Space)") { onDismiss() }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - 手势

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                if dragBase == nil { dragBase = pan }
                let base = dragBase ?? .zero
                // pan 存"fraction of pane"，所以鼠标 delta 要除以 (pane * zoom)
                let paneW = max(paneSize.width, 1)
                let paneH = max(paneSize.height, 1)
                let invZoom = 1.0 / max(zoom, 0.01)
                pan = CGSize(
                    width: base.width + value.translation.width * invZoom / paneW,
                    height: base.height + value.translation.height * invZoom / paneH
                )
            }
            .onEnded { _ in
                dragBase = nil
                focused = true
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchBase == nil { pinchBase = zoom }
                let base = pinchBase ?? zoom
                zoom = clamp(base * value.magnification)
            }
            .onEnded { _ in
                pinchBase = nil
                focused = true
            }
    }

    private func clamp(_ z: Double) -> Double {
        Swift.min(Swift.max(z, minZoom), maxZoom)
    }

    private func prefetchBothSources() async {
        // 缩略图（瞬时切源） + 高分图（J/R 切到的源放大不糊）
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

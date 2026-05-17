import SwiftUI
import AppKit

struct SinglePreviewView: View {
    let clip: MediaClip
    let isFavorite: Bool
    var onDismiss: () -> Void
    var onNavigate: (CompareViewModel.NavDirection) -> Void
    var onCrossTrack: () -> Void
    var onTrash: () -> Void
    var onToggleFavorite: () -> Void

    @State private var zoom: Double = 1.0
    @State private var pan: CGSize = .zero
    @State private var pinchBase: Double?
    @State private var dragBase: CGSize?
    @State private var source: ImageSource

    private let minZoom: Double = 0.2
    private let maxZoom: Double = 8.0

    init(
        clip: MediaClip,
        isFavorite: Bool,
        onDismiss: @escaping () -> Void,
        onNavigate: @escaping (CompareViewModel.NavDirection) -> Void,
        onCrossTrack: @escaping () -> Void,
        onTrash: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.clip = clip
        self.isFavorite = isFavorite
        self.onDismiss = onDismiss
        self.onNavigate = onNavigate
        self.onCrossTrack = onCrossTrack
        self.onTrash = onTrash
        self.onToggleFavorite = onToggleFavorite
        self._source = State(initialValue: clip.defaultSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack(alignment: .topTrailing) {
                ImagePane(
                    url: clip.url(for: source),
                    zoom: zoom,
                    pan: pan
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(panGesture)
                .gesture(magnifyGesture)

                sourceBadge
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .focusable()
        .focusEffectDisabled()
        .onChange(of: clip.id) { _, _ in
            zoom = 1.0
            pan = .zero
            // 新 clip 不支持当前 source 时回退
            if source == .raw && clip.rawURL == nil { source = .jpg }
            if source == .jpg && clip.jpgURL == nil { source = .raw }
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
        .onKeyPress(keys: ["j", "J"]) { _ in
            if clip.jpgURL != nil { source = .jpg }
            return .handled
        }
        .onKeyPress(keys: ["r", "R"]) { _ in
            if clip.rawURL != nil { source = .raw }
            return .handled
        }
        .onKeyPress(keys: ["f", "F"]) { _ in
            onToggleFavorite()
            return .handled
        }
        .onKeyPress(keys: ["="]) { _ in zoom = clamp(zoom * 1.25); return .handled }
        .onKeyPress(keys: ["-"]) { _ in zoom = clamp(zoom * 0.8); return .handled }
        .onKeyPress(keys: ["0"]) { _ in zoom = 1.0; pan = .zero; return .handled }
        .background {
            Group {
                Button { zoom = clamp(zoom * 1.25) } label: { EmptyView() }
                    .keyboardShortcut("=", modifiers: .command)
                Button { zoom = clamp(zoom * 0.8) } label: { EmptyView() }
                    .keyboardShortcut("-", modifiers: .command)
                Button { zoom = 1.0; pan = .zero } label: { EmptyView() }
                    .keyboardShortcut("0", modifiers: .command)
                Button { onTrash() } label: { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button { toggleHostFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
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
        .background(.regularMaterial)
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

            Button { toggleHostFullScreen() } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("全屏（⌃⌘F）")

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
        .background(.regularMaterial)
    }

    // MARK: - 手势

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                if dragBase == nil { dragBase = pan }
                let base = dragBase ?? .zero
                pan = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in dragBase = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchBase == nil { pinchBase = zoom }
                let base = pinchBase ?? zoom
                zoom = clamp(base * value.magnification)
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func clamp(_ z: Double) -> Double {
        Swift.min(Swift.max(z, minZoom), maxZoom)
    }

    private func prefetchBothSources() async {
        if let jpg = clip.jpgURL {
            _ = await ThumbnailLoader.shared.thumbnail(for: jpg, sizeBucket: 2048)
        }
        if let raw = clip.rawURL {
            _ = await ThumbnailLoader.shared.thumbnail(for: raw, sizeBucket: 2048)
        }
    }

    /// 让承载本 sheet 的宿主文档窗口进入/退出 macOS 全屏。
    private func toggleHostFullScreen() {
        var win = NSApp.keyWindow
        while let parent = win?.parent { win = parent }
        win?.toggleFullScreen(nil)
    }
}

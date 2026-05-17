import SwiftUI
import AppKit

struct ABCompareView: View {
    let clipA: MediaClip
    let clipB: MediaClip
    var onDismiss: () -> Void
    var onNavigate: (CompareViewModel.NavDirection) -> Void = { _ in }

    enum Mode: String, CaseIterable {
        case split = "分屏"
        case curtain = "幕帘"
    }

    @State private var mode: Mode = .split
    @State private var zoom: Double = 1.0
    @State private var pan: CGSize = .zero
    @State private var pinchBaseZoom: Double?
    @State private var dragBasePan: CGSize?
    @State private var curtainSplit: Double = 0.5

    @State private var sourceA: ImageSource
    @State private var sourceB: ImageSource

    private let minZoom: Double = 0.2
    private let maxZoom: Double = 8.0

    init(
        clipA: MediaClip,
        clipB: MediaClip,
        onDismiss: @escaping () -> Void,
        onNavigate: @escaping (CompareViewModel.NavDirection) -> Void = { _ in }
    ) {
        self.clipA = clipA
        self.clipB = clipB
        self.onDismiss = onDismiss
        self.onNavigate = onNavigate
        self._sourceA = State(initialValue: clipA.defaultSource)
        self._sourceB = State(initialValue: clipB.defaultSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            GeometryReader { proxy in
                imageStage(in: proxy.size)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 980, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .focusable()
        .focusEffectDisabled()
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
        .onKeyPress(keys: ["j", "J"]) { _ in
            if clipA.jpgURL != nil { sourceA = .jpg }
            if clipB.jpgURL != nil { sourceB = .jpg }
            return .handled
        }
        .onKeyPress(keys: ["r", "R"]) { _ in
            if clipA.rawURL != nil { sourceA = .raw }
            if clipB.rawURL != nil { sourceB = .raw }
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
                Button { toggleHostFullScreen() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    /// 让承载本 sheet 的宿主文档窗口进入/退出 macOS 全屏。
    private func toggleHostFullScreen() {
        var win = NSApp.keyWindow
        while let parent = win?.parent { win = parent }
        win?.toggleFullScreen(nil)
    }

    private func syncSourcesAndResetZoom() {
        if sourceA == .raw && clipA.rawURL == nil { sourceA = .jpg }
        if sourceA == .jpg && clipA.jpgURL == nil { sourceA = .raw }
        if sourceB == .raw && clipB.rawURL == nil { sourceB = .jpg }
        if sourceB == .jpg && clipB.jpgURL == nil { sourceB = .raw }
        zoom = 1.0
        pan = .zero
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
        switch mode {
        case .split:
            HStack(spacing: 1) {
                ImagePane(url: clipA.url(for: sourceA), zoom: zoom, pan: pan)
                    .frame(width: size.width / 2, height: size.height)
                Rectangle().fill(.white.opacity(0.18)).frame(width: 1)
                ImagePane(url: clipB.url(for: sourceB), zoom: zoom, pan: pan)
                    .frame(width: size.width / 2, height: size.height)
            }
            .gesture(panGesture)
            .gesture(magnifyGesture)

        case .curtain:
            ZStack {
                ImagePane(url: clipB.url(for: sourceB), zoom: zoom, pan: pan)
                    .frame(width: size.width, height: size.height)
                ImagePane(url: clipA.url(for: sourceA), zoom: zoom, pan: pan)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * curtainSplit)
                    }
                CurtainHandle()
                    .position(x: size.width * curtainSplit, y: size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                curtainSplit = clampRatio(v.location.x / size.width)
                            }
                    )
            }
            .gesture(magnifyGesture)
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                if dragBasePan == nil { dragBasePan = pan }
                let base = dragBasePan ?? .zero
                pan = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in dragBasePan = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchBaseZoom == nil { pinchBaseZoom = zoom }
                let base = pinchBaseZoom ?? zoom
                zoom = clamp(base * value.magnification)
            }
            .onEnded { _ in pinchBaseZoom = nil }
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
                    zoom = 1.0
                    pan = .zero
                }
                .controlSize(.small)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)

            Spacer()

            Button { toggleHostFullScreen() } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("全屏（⌃⌘F）")

            Button("退出对比") {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func clamp(_ z: Double) -> Double {
        Swift.min(Swift.max(z, minZoom), maxZoom)
    }
    private func clampRatio(_ r: Double) -> Double {
        Swift.min(Swift.max(r, 0.02), 0.98)
    }

    private func prefetchSources(for clip: MediaClip) async {
        if let jpg = clip.jpgURL {
            _ = await ThumbnailLoader.shared.thumbnail(for: jpg, sizeBucket: 2048)
        }
        if let raw = clip.rawURL {
            _ = await ThumbnailLoader.shared.thumbnail(for: raw, sizeBucket: 2048)
        }
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

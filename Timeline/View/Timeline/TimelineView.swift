import SwiftUI

struct TimelineView: View {
    @Binding var document: CompareDocument
    let vm: CompareViewModel
    var onRequestPreview: () -> Void = {}

    private let rulerHeight: Double = 32
    private let trackHeight: Double = 110
    private let trackHeaderWidth: Double = 96
    private let minPxPerSecond: Double = 0.02
    private let maxPxPerSecond: Double = 120.0
    private let clipHitHalfSize: Double = 32

    @State private var pxPerSecond: Double = 5.0
    @State private var scrollPosition: ScrollPosition = ScrollPosition()
    @State private var scrollX: Double = 0
    @State private var viewportWidth: Double = 0
    @State private var visibleXRange: ClosedRange<Double> = -.infinity ... .infinity

    @State private var pinchBaseline: PinchBaseline?
    @State private var focusedTrack: Track = .a

    @State private var marquee: MarqueeState?

    @State private var didApplyInitialViewState = false

    @FocusState private var focused: Bool

    private var clipsA: [MediaClip] { vm.trackA.clips }
    private var clipsB: [MediaClip] { vm.trackB.clips }

    private var clipsLoadedKey: String { "\(clipsA.count):\(clipsB.count)" }

    private var favoriteSet: Set<String> { Set(document.payload.favoriteClipIDs) }

    var body: some View {
        if let geometry = makeGeometry() {
            content(geometry: geometry)
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onAppear { focused = true }
                .background {
                    Group {
                        Button { zoom(factor: 1.25, geometry: geometry) } label: { EmptyView() }
                            .keyboardShortcut("=", modifiers: .command)
                        Button { zoom(factor: 0.8, geometry: geometry) } label: { EmptyView() }
                            .keyboardShortcut("-", modifiers: .command)
                        Button { fitAll(geometry: geometry) } label: { EmptyView() }
                            .keyboardShortcut("0", modifiers: .command)
                        Button { vm.selectAll() } label: { EmptyView() }
                            .keyboardShortcut("a", modifiers: .command)
                        Button { toggleFavoritesForSelection() } label: { EmptyView() }
                            .keyboardShortcut("f", modifiers: [])
                        Button { trashSelection() } label: { EmptyView() }
                            .keyboardShortcut(.delete, modifiers: .command)
                    }
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
                .onKeyPress(.leftArrow) { navigateClip(.prev, geometry: geometry); return .handled }
                .onKeyPress(.rightArrow) { navigateClip(.next, geometry: geometry); return .handled }
                .onKeyPress(.upArrow) { jumpToOtherTrack(geometry: geometry); return .handled }
                .onKeyPress(.downArrow) { jumpToOtherTrack(geometry: geometry); return .handled }
                .onKeyPress(keys: [.home]) { _ in scrollTo(x: 0); return .handled }
                .onKeyPress(keys: [.end]) { _ in scrollTo(x: geometry.contentWidth); return .handled }
                .onKeyPress(.escape) { vm.clearSelection(); return .handled }
                .onKeyPress(.space) {
                    // 选了 1 张 → 单图预览；选了 1A+1B → AB 对比；其他 → 忽略
                    if vm.abPair != nil || vm.selection.count == 1 {
                        onRequestPreview()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(keys: ["[", "]", "{", "}"]) { press in
                    handleOffsetKey(press)
                    return .handled
                }
                .task(id: clipsLoadedKey) {
                    applyInitialViewStateIfNeeded(geometry: geometry)
                }
                .onChange(of: pxPerSecond) { _, new in
                    document.payload.viewState.pxPerSecond = new
                }
                .onChange(of: scrollX) { _, new in
                    guard didApplyInitialViewState else { return }
                    let date = geometry.date(at: new + max(viewportWidth, 1) / 2)
                    document.payload.viewState.scrollAnchorEpoch = date.timeIntervalSince1970
                }
                .onChange(of: vm.pendingScrollDate) { _, newValue in
                    guard let date = newValue else { return }
                    scrollToDate(date, geometry: geometry)
                    vm.pendingScrollDate = nil
                }
        } else {
            ContentUnavailableView {
                Label("尚无可显示的素材", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("请先在右侧 Inspector 为 A、B 两轨各选择一个含照片的文件夹")
            }
        }
    }

    @ViewBuilder
    private func content(geometry: TimelineGeometry) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: rulerHeight)
                TrackHeaderView(
                    track: .a,
                    label: document.payload.trackA.displayName,
                    tint: .blue,
                    offsetSeconds: document.payload.trackA.timeOffsetSeconds,
                    count: clipsA.count,
                    isFocused: focusedTrack == .a,
                    pxPerSecond: pxPerSecond,
                    onFocus: { focusedTrack = .a },
                    onOffsetDelta: { delta in mutateOffset(track: .a) { $0 += delta } },
                    onOffsetReset: { mutateOffset(track: .a) { $0 = 0 } }
                )
                .frame(height: trackHeight)
                Divider()
                TrackHeaderView(
                    track: .b,
                    label: document.payload.trackB.displayName,
                    tint: .orange,
                    offsetSeconds: document.payload.trackB.timeOffsetSeconds,
                    count: clipsB.count,
                    isFocused: focusedTrack == .b,
                    pxPerSecond: pxPerSecond,
                    onFocus: { focusedTrack = .b },
                    onOffsetDelta: { delta in mutateOffset(track: .b) { $0 += delta } },
                    onOffsetReset: { mutateOffset(track: .b) { $0 = 0 } }
                )
                .frame(height: trackHeight)
            }
            .frame(width: trackHeaderWidth)
            .background(.background.secondary)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.separator).frame(width: 0.5)
            }

            rightPane(geometry: geometry)
        }
    }

    @ViewBuilder
    private func rightPane(geometry: TimelineGeometry) -> some View {
        ScrollView([.horizontal], showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TimeRulerView(geometry: geometry)
                        .frame(width: geometry.contentWidth, height: rulerHeight)

                    TrackLane(
                        tint: .blue,
                        clips: clipsA,
                        offsetSeconds: document.payload.trackA.timeOffsetSeconds,
                        geometry: geometry,
                        height: trackHeight,
                        visibleXRange: visibleXRange,
                        selection: vm.selection,
                        favoriteIDSet: favoriteSet,
                        onClipClick: { clip, kind in handleClipClick(clip: clip, kind: kind) },
                        onToggleFavorite: { clip in vm.toggleFavorite(clip.id, in: &document) }
                    )

                    Divider()

                    TrackLane(
                        tint: .orange,
                        clips: clipsB,
                        offsetSeconds: document.payload.trackB.timeOffsetSeconds,
                        geometry: geometry,
                        height: trackHeight,
                        visibleXRange: visibleXRange,
                        selection: vm.selection,
                        favoriteIDSet: favoriteSet,
                        onClipClick: { clip, kind in handleClipClick(clip: clip, kind: kind) },
                        onToggleFavorite: { clip in vm.toggleFavorite(clip.id, in: &document) }
                    )
                }
                .contentShape(Rectangle())
                .gesture(magnifyGesture(geometry: geometry))
                .gesture(marqueeGesture(geometry: geometry))

                if let m = marquee {
                    let rect = m.normalizedRect
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: rect.width, height: rect.height)
                        .overlay(
                            Rectangle()
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(.background)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollSnapshot.self) { proxy in
            ScrollSnapshot(
                offsetX: proxy.contentOffset.x,
                width: proxy.containerSize.width
            )
        } action: { _, newValue in
            scrollX = newValue.offsetX
            viewportWidth = newValue.width
            visibleXRange = newValue.offsetX ... max(newValue.offsetX + 1, newValue.offsetX + newValue.width)
        }
    }

    // MARK: - 几何

    private func makeGeometry() -> TimelineGeometry? {
        let offsetA = document.payload.trackA.timeOffsetSeconds
        let offsetB = document.payload.trackB.timeOffsetSeconds
        let effA = clipsA.map { $0.captureDate.addingTimeInterval(offsetA) }
        let effB = clipsB.map { $0.captureDate.addingTimeInterval(offsetB) }
        let all = effA + effB
        guard let minD = all.min(), let maxD = all.max() else { return nil }

        let rawSpan = maxD.timeIntervalSince(minD)
        let span = max(rawSpan, 60)
        let pad = max(span * 0.08, 30)
        let realEnd = (rawSpan < 60) ? minD.addingTimeInterval(60) : maxD

        return TimelineGeometry(
            timelineStart: minD.addingTimeInterval(-pad),
            timelineEnd: realEnd.addingTimeInterval(pad),
            pxPerSecond: pxPerSecond
        )
    }

    private var trackAYRange: ClosedRange<Double> { rulerHeight ... (rulerHeight + trackHeight) }
    private var trackBYRange: ClosedRange<Double> {
        let start = rulerHeight + trackHeight + 1
        return start ... (start + trackHeight)
    }

    private func clipUnder(point: CGPoint, geometry: TimelineGeometry) -> MediaClip? {
        func test(clips: [MediaClip], offset: TimeInterval, yRange: ClosedRange<Double>) -> MediaClip? {
            guard yRange.contains(point.y) else { return nil }
            let centerY = (yRange.lowerBound + yRange.upperBound) / 2
            for clip in clips {
                let x = geometry.x(at: clip.captureDate.addingTimeInterval(offset))
                if abs(x - point.x) <= clipHitHalfSize && abs(point.y - centerY) <= clipHitHalfSize {
                    return clip
                }
            }
            return nil
        }
        return test(clips: clipsA, offset: document.payload.trackA.timeOffsetSeconds, yRange: trackAYRange)
            ?? test(clips: clipsB, offset: document.payload.trackB.timeOffsetSeconds, yRange: trackBYRange)
    }

    private func clipsIntersecting(rect: CGRect, geometry: TimelineGeometry) -> [ClipID] {
        func collect(clips: [MediaClip], offset: TimeInterval, yRange: ClosedRange<Double>) -> [ClipID] {
            let centerY = (yRange.lowerBound + yRange.upperBound) / 2
            let half = clipHitHalfSize
            return clips.compactMap { clip in
                let x = geometry.x(at: clip.captureDate.addingTimeInterval(offset))
                let clipRect = CGRect(x: x - half, y: centerY - half, width: half * 2, height: half * 2)
                return rect.intersects(clipRect) ? clip.id : nil
            }
        }
        var out: [ClipID] = []
        if rect.intersects(CGRect(x: 0, y: trackAYRange.lowerBound, width: .infinity, height: trackHeight)) {
            out += collect(clips: clipsA, offset: document.payload.trackA.timeOffsetSeconds, yRange: trackAYRange)
        }
        if rect.intersects(CGRect(x: 0, y: trackBYRange.lowerBound, width: .infinity, height: trackHeight)) {
            out += collect(clips: clipsB, offset: document.payload.trackB.timeOffsetSeconds, yRange: trackBYRange)
        }
        return out
    }

    // MARK: - 收藏

    private func trashSelection() {
        let toDelete = vm.selectedClips()
        guard !toDelete.isEmpty else { return }
        _ = vm.trash(toDelete, in: &document)
    }

    private func toggleFavoritesForSelection() {
        guard !vm.selection.isEmpty else { return }
        // 全选中已收藏 → 全部取消；否则全部加红心
        let allFav = vm.selection.allSatisfy { vm.isFavorite($0, in: document) }
        for id in vm.selection {
            vm.setFavorite(id, to: !allFav, in: &document)
        }
    }

    // MARK: - Marquee

    private struct MarqueeState: Equatable {
        var start: CGPoint
        var current: CGPoint
        var additive: Bool

        var normalizedRect: CGRect {
            let x = min(start.x, current.x)
            let y = min(start.y, current.y)
            let w = abs(current.x - start.x)
            let h = abs(current.y - start.y)
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    private func marqueeGesture(geometry: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if marquee == nil {
                    if clipUnder(point: value.startLocation, geometry: geometry) != nil {
                        return
                    }
                    let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
                    marquee = MarqueeState(
                        start: value.startLocation,
                        current: value.location,
                        additive: additive
                    )
                } else {
                    marquee?.current = value.location
                }
            }
            .onEnded { _ in
                guard let m = marquee else { return }
                let hits = clipsIntersecting(rect: m.normalizedRect, geometry: geometry)
                if m.additive {
                    vm.selection.formUnion(hits)
                } else {
                    vm.selection = Set(hits)
                }
                vm.selectionAnchor = hits.last
                marquee = nil
            }
    }

    // MARK: - 点击

    private func handleClipClick(clip: MediaClip, kind: ClickKind) {
        focusedTrack = clip.track
        switch kind {
        case .normal: vm.selectOnly(clip.id)
        case .toggle: vm.toggle(clip.id)
        case .extend: vm.extendSelection(to: clip.id)
        }
    }

    // MARK: - 偏移

    private func mutateOffset(track: Track, _ body: (inout TimeInterval) -> Void) {
        var c = document.config(for: track)
        body(&c.timeOffsetSeconds)
        document.setConfig(c, for: track)
    }

    private func handleOffsetKey(_ press: KeyPress) {
        let ch = press.key.character
        let big = press.modifiers.contains(.shift) || ch == "{" || ch == "}"
        let amount: TimeInterval = big ? 10 : 1
        let sign: TimeInterval = (ch == "[" || ch == "{") ? -1 : 1
        mutateOffset(track: focusedTrack) { $0 += sign * amount }
    }

    // MARK: - 缩放

    private struct PinchBaseline: Equatable {
        var pxPerSecond: Double
        var anchorDate: Date
        var anchorViewportX: Double
    }

    private func magnifyGesture(geometry: TimelineGeometry) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchBaseline == nil {
                    let contentX = value.startLocation.x
                    let viewportX = contentX - scrollX
                    pinchBaseline = PinchBaseline(
                        pxPerSecond: pxPerSecond,
                        anchorDate: geometry.date(at: contentX),
                        anchorViewportX: viewportX
                    )
                }
                guard let baseline = pinchBaseline else { return }
                let target = clamp(baseline.pxPerSecond * value.magnification, minPxPerSecond, maxPxPerSecond)
                applyZoom(
                    targetPxPerSecond: target,
                    anchorDate: baseline.anchorDate,
                    anchorViewportX: baseline.anchorViewportX,
                    currentGeometry: geometry
                )
            }
            .onEnded { _ in
                pinchBaseline = nil
            }
    }

    private func zoom(factor: Double, geometry: TimelineGeometry) {
        let target = clamp(pxPerSecond * factor, minPxPerSecond, maxPxPerSecond)
        let viewportX = max(viewportWidth / 2, 1)
        let contentX = scrollX + viewportX
        let anchorDate = geometry.date(at: contentX)
        applyZoom(
            targetPxPerSecond: target,
            anchorDate: anchorDate,
            anchorViewportX: viewportX,
            currentGeometry: geometry
        )
    }

    private func applyZoom(
        targetPxPerSecond: Double,
        anchorDate: Date,
        anchorViewportX: Double,
        currentGeometry: TimelineGeometry
    ) {
        let newGeo = TimelineGeometry(
            timelineStart: currentGeometry.timelineStart,
            timelineEnd: currentGeometry.timelineEnd,
            pxPerSecond: targetPxPerSecond,
            leftPadding: currentGeometry.leftPadding,
            rightPadding: currentGeometry.rightPadding
        )
        let newContentX = newGeo.x(at: anchorDate)
        let newScrollX = newContentX - anchorViewportX
        pxPerSecond = targetPxPerSecond
        scrollPosition.scrollTo(x: max(0, newScrollX))
    }

    private func fitAll(geometry: TimelineGeometry) {
        let usableWidth = max(viewportWidth - 16, 100)
        let span = geometry.totalDuration
        let needed = usableWidth / max(span, 1)
        pxPerSecond = clamp(needed, minPxPerSecond, maxPxPerSecond)
        scrollPosition.scrollTo(x: 0)
    }

    // MARK: - 平移 & 按 clip 跳

    private func arrowStep(shift: Bool) -> Double {
        shift ? max(viewportWidth * 0.6, 400) : 120
    }

    private func scrollBy(_ delta: Double) {
        let newX = max(0, scrollX + delta)
        scrollTo(x: newX)
    }

    /// 左右方向键：按时间序在当前轨道的 clip 之间跳。
    /// 没有选区时，选中聚焦轨道的第一张。
    private func navigateClip(_ direction: CompareViewModel.NavDirection, geometry: TimelineGeometry) {
        let anchor: ClipID
        if let s = vm.selectionAnchor, vm.clip(for: s) != nil {
            anchor = s
        } else if let first = vm.selection.first, vm.clip(for: first) != nil {
            anchor = first
        } else {
            // 无选区：选当前聚焦轨道的第一张
            let list = focusedTrack == .a ? clipsA : clipsB
            guard let firstClip = list.first else { return }
            vm.selectOnly(firstClip.id)
            focusedTrack = firstClip.track
            scrollClipIntoViewIfNeeded(firstClip, geometry: geometry)
            return
        }
        guard let next = vm.neighbor(of: anchor, direction: direction) else { return }
        vm.selectOnly(next.id)
        focusedTrack = next.track
        scrollClipIntoViewIfNeeded(next, geometry: geometry)
    }

    /// 上/下方向键：跳到另一条轨上时间最接近的那张
    private func jumpToOtherTrack(geometry: TimelineGeometry) {
        let anchor: ClipID
        if let s = vm.selectionAnchor, vm.clip(for: s) != nil {
            anchor = s
        } else if let first = vm.selection.first, vm.clip(for: first) != nil {
            anchor = first
        } else {
            // 没选区：选当前聚焦轨第一张
            let list = focusedTrack == .a ? clipsA : clipsB
            guard let firstClip = list.first else { return }
            vm.selectOnly(firstClip.id)
            scrollClipIntoViewIfNeeded(firstClip, geometry: geometry)
            return
        }
        guard let other = vm.crossTrackNeighbor(of: anchor, in: document) else { return }
        vm.selectOnly(other.id)
        focusedTrack = other.track
        scrollClipIntoViewIfNeeded(other, geometry: geometry)
    }

    private func scrollClipIntoViewIfNeeded(_ clip: MediaClip, geometry: TimelineGeometry) {
        let offset = document.config(for: clip.track).timeOffsetSeconds
        let x = geometry.x(at: clip.captureDate.addingTimeInterval(offset))
        let margin: Double = 80
        let leftEdge = scrollX + margin
        let rightEdge = scrollX + viewportWidth - margin
        guard viewportWidth > 0 else { return }
        if x < leftEdge || x > rightEdge {
            let target = max(0, x - max(viewportWidth, 1) / 2)
            scrollPosition.scrollTo(x: target)
        }
    }

    private func scrollTo(x: Double) {
        scrollPosition.scrollTo(x: x)
    }

    private func scrollToDate(_ date: Date, geometry: TimelineGeometry) {
        let target = geometry.x(at: date) - max(viewportWidth, 1) / 2
        scrollPosition.scrollTo(x: max(0, target))
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(v, lo), hi)
    }

    // MARK: - 视图状态初始恢复

    private func applyInitialViewStateIfNeeded(geometry: TimelineGeometry) {
        guard !didApplyInitialViewState else { return }
        guard !clipsA.isEmpty || !clipsB.isEmpty else { return }

        let saved = document.payload.viewState
        let savedZoom = clamp(saved.pxPerSecond, minPxPerSecond, maxPxPerSecond)
        if savedZoom != pxPerSecond {
            pxPerSecond = savedZoom
        }

        if let anchorEpoch = saved.scrollAnchorEpoch {
            let date = Date(timeIntervalSince1970: anchorEpoch)
            let g = TimelineGeometry(
                timelineStart: geometry.timelineStart,
                timelineEnd: geometry.timelineEnd,
                pxPerSecond: savedZoom,
                leftPadding: geometry.leftPadding,
                rightPadding: geometry.rightPadding
            )
            let centerX = g.x(at: date)
            let target = max(0, centerX - max(viewportWidth, 1) / 2)
            scrollPosition.scrollTo(x: target)
        }

        didApplyInitialViewState = true
    }
}

private struct ScrollSnapshot: Equatable {
    var offsetX: Double
    var width: Double
}

private struct TrackLane: View {
    let tint: Color
    let clips: [MediaClip]
    let offsetSeconds: TimeInterval
    let geometry: TimelineGeometry
    let height: Double
    let visibleXRange: ClosedRange<Double>
    let selection: Set<ClipID>
    let favoriteIDSet: Set<String>
    let onClipClick: (MediaClip, ClickKind) -> Void
    let onToggleFavorite: (MediaClip) -> Void

    private static let prefetchBuffer: Double = 600

    private var visibleClips: [MediaClip] {
        let lower = visibleXRange.lowerBound - Self.prefetchBuffer
        let upper = visibleXRange.upperBound + Self.prefetchBuffer
        return clips.filter { clip in
            let x = geometry.x(at: clip.captureDate.addingTimeInterval(offsetSeconds))
            return x >= lower && x <= upper
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(0.05))
                .frame(width: geometry.contentWidth, height: height)

            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(width: geometry.contentWidth, height: 1)
                .offset(y: height / 2)

            ForEach(visibleClips) { clip in
                let date = clip.captureDate.addingTimeInterval(offsetSeconds)
                let x = geometry.x(at: date)
                ClipThumbnailView(
                    clip: clip,
                    tint: tint,
                    isSelected: selection.contains(clip.id),
                    isFavorite: favoriteIDSet.contains(clip.id.serialized),
                    onClick: { kind in onClipClick(clip, kind) },
                    onToggleFavorite: { onToggleFavorite(clip) }
                )
                .position(x: x, y: height / 2)
            }
        }
        .frame(width: geometry.contentWidth, height: height, alignment: .topLeading)
        .clipped()
    }
}

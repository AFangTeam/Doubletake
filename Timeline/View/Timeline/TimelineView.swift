import SwiftUI
import AppKit

struct TimelineView: View {
    @Binding var document: CompareDocument
    @Environment(PreferencesStore.self) private var prefs
    let vm: CompareViewModel
    var onRequestPreview: () -> Void = {}

    /// AppKit scroll-wheel monitor token，用于 ⌘+滚轮 缩放
    @State private var scrollWheelMonitor: Any?
    /// timeline rightPane 在窗口坐标系里的 frame，用于把鼠标点定位到 content x
    @State private var rightPaneFrameInWindow: CGRect = .zero
    /// 文档窗口本身的引用 —— global event monitor 会收到任意窗口的 scroll/magnify，
    /// 不过滤就会把预览窗的事件错算到 timeline 的坐标里
    @State private var hostWindow: NSWindow?

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
                .onChange(of: vm.pendingTimelineAction) { _, newValue in
                    guard let req = newValue else { return }
                    switch req.action {
                    case .zoomIn:        zoom(factor: 1.25, geometry: geometry)
                    case .zoomOut:       zoom(factor: 0.8, geometry: geometry)
                    case .fitAll:        fitAll(geometry: geometry)
                    case .scrollToStart: scrollTo(x: 0)
                    case .scrollToEnd:   scrollTo(x: geometry.contentWidth)
                    }
                    vm.pendingTimelineAction = nil
                }
                .onChange(of: vm.requestedScrollClipID) { _, newID in
                    guard let id = newID, let clip = vm.clip(for: id) else { return }
                    scrollClipIntoCenter(clip, geometry: geometry)
                    vm.requestedScrollClipID = nil
                }
                .onAppear { installScrollWheelMonitor(geometryProvider: { makeGeometry() }) }
                .onDisappear { removeScrollWheelMonitor() }
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
                // 注意：捏合缩放走 NSEvent .magnify monitor（在 installScrollWheelMonitor 里），
                // 因为 SwiftUI MagnifyGesture 的 startLocation 在 macOS trackpad 上不可靠 ——
                // 经常报错误位置导致缩放飞到末端
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
        // 捕获 rightPane 在窗口里的 frame —— ⌘+滚轮 需要知道鼠标是否在 timeline 上
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: RightPaneFrameKey.self, value: proxy.frame(in: .global))
            }
        )
        .onPreferenceChange(RightPaneFrameKey.self) { newValue in
            rightPaneFrameInWindow = newValue
        }
        // 捕获本视图所在的 NSWindow，过滤掉来自其它窗口（比如预览窗）的 scroll/magnify
        .background(
            HostWindowFinder { hostWindow = $0 }
        )
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
        let start = minD.addingTimeInterval(-pad)
        let end = realEnd.addingTimeInterval(pad)

        // 折叠模式：把照片间隔 > threshold 的"空白"压成窄缝
        // （Preferences 控制，不再绑文档）
        if prefs.compactEmptyTime {
            let thresholdSec = prefs.emptyGapThresholdMinutes * 60
            let sorted = (effA + effB).sorted()
            return TimelineGeometry(
                timelineStart: start,
                timelineEnd: end,
                pxPerSecond: pxPerSecond,
                captureDatesSorted: sorted,
                gapThresholdSeconds: thresholdSec
            )
        }

        return TimelineGeometry(
            timelineStart: start,
            timelineEnd: end,
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
        // ⌘= / ⌘- / ⌘0 这种"键盘缩放"也尽量以鼠标位置为锚点 —— 跟触控板捏合 +
        // ⌘+滚轮 行为一致；鼠标不在 timeline 上时回退到视口中心
        let viewportX = mouseViewportXIfInsideTimeline() ?? max(viewportWidth / 2, 1)
        let contentX = scrollX + viewportX
        let anchorDate = geometry.date(at: contentX)
        applyZoom(
            targetPxPerSecond: target,
            anchorDate: anchorDate,
            anchorViewportX: viewportX,
            currentGeometry: geometry
        )
    }

    /// 返回当前鼠标在 timeline 视口（rightPane）里的 x 坐标，鼠标不在时返回 nil。
    /// 用 NSEvent.mouseLocation（屏幕坐标）→ window 坐标 → 减去 rightPane 在窗口里的 minX。
    private func mouseViewportXIfInsideTimeline() -> Double? {
        guard let window = hostWindow else { return nil }
        // mouseLocation 是 screen 坐标（左下原点）；convertPoint(fromScreen:) 转到窗口坐标
        let screenPt = NSEvent.mouseLocation
        let windowPt = window.convertPoint(fromScreen: screenPt)
        // 翻 Y：rightPaneFrameInWindow 来自 SwiftUI .global（左上原点）
        let contentHeight = window.contentView?.bounds.height ?? 0
        let mouseX = windowPt.x
        let mouseY = contentHeight - windowPt.y
        let frame = rightPaneFrameInWindow
        guard frame.contains(CGPoint(x: mouseX, y: mouseY)) else { return nil }
        return mouseX - frame.minX
    }

    private func applyZoom(
        targetPxPerSecond: Double,
        anchorDate: Date,
        anchorViewportX: Double,
        currentGeometry: TimelineGeometry
    ) {
        // 关键修复：不要重建 TimelineGeometry —— 那个 init 不带 segments，
        // 在折叠空白时段模式下会把 anchorDate 的 x 算错（按"未折叠"位置算），
        // 结果 scrollX 跳到时间线末端附近。
        //
        // 不管 uniform 还是 compacted，都有 x = leftPadding + virtualSec(date) * pxPerSecond，
        // 其中 virtualSec(date) 与 pxPerSecond 无关。所以缩放后 x 沿 pxPerSecond 线性放缩：
        //   newX = leftPadding + (oldX - leftPadding) × (newPx / oldPx)
        let oldContentX = currentGeometry.x(at: anchorDate)
        let scale = targetPxPerSecond / max(currentGeometry.pxPerSecond, 0.0001)
        let newContentX = currentGeometry.leftPadding
            + (oldContentX - currentGeometry.leftPadding) * scale
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

    /// 强制把 clip 滚到视口中心（不管现在在不在视口里）—— 给"预览翻图同步 timeline"用
    private func scrollClipIntoCenter(_ clip: MediaClip, geometry: TimelineGeometry) {
        let offset = document.config(for: clip.track).timeOffsetSeconds
        let x = geometry.x(at: clip.captureDate.addingTimeInterval(offset))
        let target = max(0, x - max(viewportWidth, 1) / 2)
        animatedScrollTo(target)
    }

    private func scrollTo(x: Double) {
        scrollPosition.scrollTo(x: x)
    }

    private func scrollToDate(_ date: Date, geometry: TimelineGeometry) {
        let target = geometry.x(at: date) - max(viewportWidth, 1) / 2
        animatedScrollTo(max(0, target))
    }

    /// 用户触发型跳转（对比列表 / 日期 chip / 预览翻图同步）走动画滚动 ——
    /// `.smooth` 比 `.easeInOut` 收尾更利落，0.45s 是"看得见 + 不拖沓"的甜点区间
    private func animatedScrollTo(_ x: Double) {
        withAnimation(.smooth(duration: 0.45)) {
            scrollPosition.scrollTo(x: x)
        }
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

    // MARK: - ⌘+滚轮 缩放（鼠标位置锚点）

    /// 注册一个 local NSEvent monitor 拦截 `scrollWheel` + `magnify` 事件，
    /// 用统一的"鼠标位置为锚点"逻辑去做 timeline 缩放。
    ///
    /// 为什么不用 SwiftUI 的 MagnifyGesture：macOS trackpad 触发 pinch 时，
    /// SwiftUI 拿不到准确的 cursor 位置，`MagnifyGesture.startLocation` 经常是 0
    /// 或上一帧的旧值，结果就是"双指放大时间轴直接飞到末端"。
    /// NSEvent 的 `locationInWindow` 始终是真实鼠标坐标，所以走 AppKit。
    private func installScrollWheelMonitor(geometryProvider: @escaping () -> TimelineGeometry?) {
        if scrollWheelMonitor != nil { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [self] event in
            // 只处理本视图所在文档窗口的事件；预览窗里的滚动 / 捏合不要错算到 timeline 坐标里
            guard let window = event.window,
                  let host = hostWindow,
                  window === host
            else { return event }

            // 把鼠标点转到 timeline rightPane 内的坐标系
            let contentHeight = window.contentView?.bounds.height ?? 0
            let mouseX = event.locationInWindow.x
            let mouseY = contentHeight - event.locationInWindow.y  // AppKit Y 向上、SwiftUI .global Y 向下
            let frame = rightPaneFrameInWindow
            guard frame.contains(CGPoint(x: mouseX, y: mouseY)) else { return event }

            // 决定缩放因子：⌘+滚轮 / 触控板捏合 各自一套公式
            let factor: Double
            switch event.type {
            case .scrollWheel:
                guard event.modifierFlags.contains(.command) else { return event }
                factor = exp(event.scrollingDeltaY * 0.02)
            case .magnify:
                // event.magnification 是这一帧的增量缩放（约 -0.05 ~ 0.05），可直接当成 (1+delta)
                factor = 1.0 + event.magnification
            default:
                return event
            }

            guard let geometry = geometryProvider() else { return nil }

            let mouseInViewportX = mouseX - frame.minX
            let contentX = mouseInViewportX + scrollX
            let anchorDate = geometry.date(at: contentX)
            let target = clamp(pxPerSecond * factor, minPxPerSecond, maxPxPerSecond)
            applyZoom(
                targetPxPerSecond: target,
                anchorDate: anchorDate,
                anchorViewportX: mouseInViewportX,
                currentGeometry: geometry
            )
            return nil   // 吃掉事件
        }
    }

    private func removeScrollWheelMonitor() {
        if let m = scrollWheelMonitor {
            NSEvent.removeMonitor(m)
            scrollWheelMonitor = nil
        }
    }
}

private struct RightPaneFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// 把承载本 SwiftUI 视图的 NSWindow 抛回给 SwiftUI —— 用来过滤
/// global event monitor 收到的跨窗口事件
private struct HostWindowFinder: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onResolve(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
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

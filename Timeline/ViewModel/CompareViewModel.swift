import Foundation
import Observation

@MainActor
@Observable
final class CompareViewModel {
    struct TrackState {
        var folderURL: URL?
        var clips: [MediaClip] = []
        var isScanning: Bool = false
        var error: String?
        var skippedNonPhotoCount: Int = 0
    }

    var trackA = TrackState()
    var trackB = TrackState()

    var selection: Set<ClipID> = []
    var selectionAnchor: ClipID?

    /// 跳转日期请求：CompareDocumentView 设置，TimelineView 监听并滚到该日期
    var pendingScrollDate: Date?

    enum NavDirection { case prev, next }

    struct TrashResult: Sendable {
        var trashedClipIDs: [ClipID]
        var errors: [String]
    }

    /// 把 clips 对应的所有原始文件（含 RAW+JPG 对的两个文件）移动到系统废纸篓。
    /// 成功删除的 clip 会从 trackA/trackB 中移除，并从 selection / favorites 中清出。
    @discardableResult
    func trash(_ clips: [MediaClip], in document: inout CompareDocument) -> TrashResult {
        var trashed: [ClipID] = []
        var errors: [String] = []
        let fm = FileManager.default

        for clip in clips {
            var allOK = true
            for url in clip.urls {
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    allOK = false
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if allOK { trashed.append(clip.id) }
        }

        let trashedSet = Set(trashed)
        trackA.clips.removeAll { trashedSet.contains($0.id) }
        trackB.clips.removeAll { trashedSet.contains($0.id) }
        selection.subtract(trashedSet)
        if let anchor = selectionAnchor, trashedSet.contains(anchor) {
            selectionAnchor = nil
        }
        if vm_hasFavorites(document: document) {
            let trashedKeys = Set(trashed.map { $0.serialized })
            document.payload.favoriteClipIDs.removeAll { trashedKeys.contains($0) }
        }

        return TrashResult(trashedClipIDs: trashed, errors: errors)
    }

    private func vm_hasFavorites(document: CompareDocument) -> Bool {
        !document.payload.favoriteClipIDs.isEmpty
    }

    /// 在 clip 所属轨道里按时间顺序找上一张/下一张
    func neighbor(of id: ClipID, direction: NavDirection) -> MediaClip? {
        let list = clips(for: id.track)
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return nil }
        switch direction {
        case .prev: return idx > 0 ? list[idx - 1] : nil
        case .next: return idx < list.count - 1 ? list[idx + 1] : nil
        }
    }

    /// 跨轨：在另一条轨道里找按 effectiveDate（含时间偏移）最接近当前 clip 的那张
    func crossTrackNeighbor(of id: ClipID, in document: CompareDocument) -> MediaClip? {
        guard let current = clip(for: id) else { return nil }
        let otherTrack: Track = id.track == .a ? .b : .a
        let otherClips = clips(for: otherTrack)
        guard !otherClips.isEmpty else { return nil }
        let myOffset = document.config(for: id.track).timeOffsetSeconds
        let otherOffset = document.config(for: otherTrack).timeOffsetSeconds
        let myEffective = current.captureDate.addingTimeInterval(myOffset)
        return otherClips.min { a, b in
            let da = abs(a.captureDate.addingTimeInterval(otherOffset).timeIntervalSince(myEffective))
            let db = abs(b.captureDate.addingTimeInterval(otherOffset).timeIntervalSince(myEffective))
            return da < db
        }
    }

    private var activeScopeURLA: URL?
    private var activeScopeURLB: URL?

    func clips(for track: Track) -> [MediaClip] {
        switch track {
        case .a: trackA.clips
        case .b: trackB.clips
        }
    }

    func clip(for id: ClipID) -> MediaClip? {
        clips(for: id.track).first { $0.id == id }
    }

    func selectedClips() -> [MediaClip] {
        selection.compactMap { clip(for: $0) }
    }

    func clearSelection() {
        selection.removeAll()
        selectionAnchor = nil
    }

    func selectOnly(_ id: ClipID) {
        selection = [id]
        selectionAnchor = id
    }

    func toggle(_ id: ClipID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        selectionAnchor = id
    }

    /// Shift+click：在同一 track 内选中 anchor 到 id 之间的所有 clip（按时间序）。
    func extendSelection(to id: ClipID) {
        guard let anchor = selectionAnchor, anchor.track == id.track else {
            selectOnly(id)
            return
        }
        let trackClips = clips(for: id.track)
        guard
            let anchorIdx = trackClips.firstIndex(where: { $0.id == anchor }),
            let targetIdx = trackClips.firstIndex(where: { $0.id == id })
        else {
            selectOnly(id)
            return
        }
        let range = anchorIdx <= targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
        selection = Set(trackClips[range].map(\.id))
    }

    func selectAll() {
        selection = Set(trackA.clips.map(\.id)).union(trackB.clips.map(\.id))
    }

    // MARK: - 红心收藏

    func isFavorite(_ id: ClipID, in document: CompareDocument) -> Bool {
        document.payload.favoriteClipIDs.contains(id.serialized)
    }

    func toggleFavorite(_ id: ClipID, in document: inout CompareDocument) {
        let key = id.serialized
        if let idx = document.payload.favoriteClipIDs.firstIndex(of: key) {
            document.payload.favoriteClipIDs.remove(at: idx)
        } else {
            document.payload.favoriteClipIDs.append(key)
        }
    }

    func setFavorite(_ id: ClipID, to value: Bool, in document: inout CompareDocument) {
        let key = id.serialized
        let has = document.payload.favoriteClipIDs.contains(key)
        if value && !has {
            document.payload.favoriteClipIDs.append(key)
        } else if !value, let idx = document.payload.favoriteClipIDs.firstIndex(of: key) {
            document.payload.favoriteClipIDs.remove(at: idx)
        }
    }

    func favoriteClips(in document: CompareDocument) -> [MediaClip] {
        let keys = Set(document.payload.favoriteClipIDs)
        let all = trackA.clips + trackB.clips
        return all.filter { keys.contains($0.id.serialized) }
    }

    func favoriteCount(in document: CompareDocument) -> Int {
        document.payload.favoriteClipIDs.count
    }

    /// 拍摄时间最早 / 最晚（基于 effectiveDate，含时间偏移）
    func dateRange(in document: CompareDocument) -> ClosedRange<Date>? {
        let offsetA = document.payload.trackA.timeOffsetSeconds
        let offsetB = document.payload.trackB.timeOffsetSeconds
        let all = trackA.clips.map { $0.captureDate.addingTimeInterval(offsetA) }
            + trackB.clips.map { $0.captureDate.addingTimeInterval(offsetB) }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        return lo...hi
    }

    /// 当前是否处于"AB 可对比"的有效状态：选中恰好 1 张 A + 1 张 B
    var abPair: (a: MediaClip, b: MediaClip)? {
        let clips = selectedClips()
        guard clips.count == 2,
              let a = clips.first(where: { $0.track == .a }),
              let b = clips.first(where: { $0.track == .b })
        else { return nil }
        return (a, b)
    }

    func state(for track: Track) -> TrackState {
        switch track {
        case .a: trackA
        case .b: trackB
        }
    }

    func updateState(_ mutate: (inout TrackState) -> Void, for track: Track) {
        switch track {
        case .a: mutate(&trackA)
        case .b: mutate(&trackB)
        }
    }

    /// Resolve bookmark (if any), start security scope, scan folder, publish results.
    /// 调用方应在 bookmark 变更或视图首次出现时调用。
    func applyBookmark(_ data: Data?, for track: Track) async {
        stopScope(for: track)
        // 切换文件夹时把这条轨的旧选区清掉
        selection = selection.filter { $0.track != track }
        if let anchor = selectionAnchor, anchor.track == track { selectionAnchor = nil }

        guard let data else {
            updateState({
                $0 = TrackState()
            }, for: track)
            return
        }

        let resolved: ResolvedFolder
        do {
            resolved = try BookmarkStore.resolve(data)
        } catch {
            updateState({
                $0 = TrackState()
                $0.error = "无法解析文件夹书签：\(error.localizedDescription)"
            }, for: track)
            return
        }

        guard resolved.url.startAccessingSecurityScopedResource() else {
            updateState({
                $0 = TrackState()
                $0.error = "未授权访问该文件夹，请重新选择"
            }, for: track)
            return
        }
        setActiveScope(resolved.url, for: track)

        updateState({
            $0.folderURL = resolved.url
            $0.isScanning = true
            $0.error = nil
        }, for: track)

        let folderURL = resolved.url
        let result = await Task.detached(priority: .userInitiated) { () -> Result<ScanResult, Error> in
            do {
                return .success(try MediaScanner.scan(folder: folderURL, track: track))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let scan):
            updateState({
                $0.clips = scan.clips
                $0.skippedNonPhotoCount = scan.skippedNonPhotoCount
                $0.isScanning = false
                $0.folderURL = scan.folderURL
            }, for: track)
        case .failure(let error):
            updateState({
                $0.clips = []
                $0.isScanning = false
                $0.error = error.localizedDescription
            }, for: track)
        }
    }

    /// 释放所有 security-scoped 访问。视图消失时调用。
    func releaseAllScopes() {
        stopScope(for: .a)
        stopScope(for: .b)
    }

    private func setActiveScope(_ url: URL, for track: Track) {
        switch track {
        case .a: activeScopeURLA = url
        case .b: activeScopeURLB = url
        }
    }

    private func stopScope(for track: Track) {
        switch track {
        case .a:
            activeScopeURLA?.stopAccessingSecurityScopedResource()
            activeScopeURLA = nil
        case .b:
            activeScopeURLB?.stopAccessingSecurityScopedResource()
            activeScopeURLB = nil
        }
    }
}

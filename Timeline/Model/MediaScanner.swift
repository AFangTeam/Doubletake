import Foundation

nonisolated struct ScanResult: Sendable {
    var clips: [MediaClip]
    var folderURL: URL
    var skippedNonPhotoCount: Int
}

enum MediaScannerError: Error, LocalizedError {
    case folderUnreadable

    var errorDescription: String? {
        switch self {
        case .folderUnreadable: "无法读取所选文件夹"
        }
    }
}

enum MediaScanner {
    /// 同步扫描，应在后台执行。返回时不主动 stop security-scoped resource —
    /// caller 负责 start/stop 生命周期。
    nonisolated static func scan(folder: URL, track: Track) throws -> ScanResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MediaScannerError.folderUnreadable
        }

        struct RawEntry {
            let url: URL
            let format: PhotoFormat
            let fileSize: Int64
            let creationDate: Date?
        }

        var entries: [RawEntry] = []
        var skipped = 0

        for case let url as URL in enumerator {
            let ext = url.pathExtension
            guard let format = PhotoFormat.detect(extension: ext) else {
                skipped += 1
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey])
            guard values?.isRegularFile == true else { continue }
            entries.append(RawEntry(
                url: url,
                format: format,
                fileSize: Int64(values?.fileSize ?? 0),
                creationDate: values?.creationDate
            ))
        }

        let grouped = Dictionary(grouping: entries) { entry -> String in
            let folder = entry.url.deletingLastPathComponent().path
            let base = entry.url.deletingPathExtension().lastPathComponent
            return folder + "/" + base
        }

        var clips: [MediaClip] = []
        for (groupKey, groupEntries) in grouped {
            let jpgs = groupEntries.filter { $0.format.isJPGFamily }
            let raws = groupEntries.filter { $0.format.isRAW }
            let others = groupEntries.filter { !$0.format.isJPGFamily && !$0.format.isRAW }

            if let jpg = jpgs.first, let raw = raws.first {
                let totalSize = (jpgs + raws).reduce(Int64(0)) { $0 + $1.fileSize }
                if let clip = buildClip(
                    track: track,
                    displayURL: jpg.url,
                    urls: [jpg.url, raw.url],
                    kind: .pair(jpgURL: jpg.url, rawURL: raw.url),
                    stableKey: groupKey,
                    totalBytes: totalSize,
                    fallbackDate: jpg.creationDate ?? raw.creationDate
                ) {
                    clips.append(clip)
                }
                for extra in others {
                    if let clip = buildClip(
                        track: track,
                        displayURL: extra.url,
                        urls: [extra.url],
                        kind: .single(format: extra.format),
                        stableKey: groupKey + "#" + extra.url.lastPathComponent,
                        totalBytes: extra.fileSize,
                        fallbackDate: extra.creationDate
                    ) {
                        clips.append(clip)
                    }
                }
            } else {
                for entry in groupEntries {
                    if let clip = buildClip(
                        track: track,
                        displayURL: entry.url,
                        urls: [entry.url],
                        kind: .single(format: entry.format),
                        stableKey: groupKey + "#" + entry.url.lastPathComponent,
                        totalBytes: entry.fileSize,
                        fallbackDate: entry.creationDate
                    ) {
                        clips.append(clip)
                    }
                }
            }
        }

        clips.sort { $0.captureDate < $1.captureDate }

        return ScanResult(clips: clips, folderURL: folder, skippedNonPhotoCount: skipped)
    }

    nonisolated private static func buildClip(
        track: Track,
        displayURL: URL,
        urls: [URL],
        kind: ClipKind,
        stableKey: String,
        totalBytes: Int64,
        fallbackDate: Date?
    ) -> MediaClip? {
        var metadata = ExifReader.read(from: displayURL)
        if metadata.captureDate == nil, urls.count > 1 {
            for u in urls.dropFirst() where metadata.captureDate == nil {
                metadata = ExifReader.read(from: u)
            }
        }
        guard let date = metadata.captureDate ?? fallbackDate else {
            return nil
        }
        return MediaClip(
            id: ClipID(track: track, stableKey: stableKey),
            track: track,
            urls: urls,
            displayURL: displayURL,
            captureDate: date,
            kind: kind,
            metadata: metadata,
            totalBytes: totalBytes
        )
    }
}

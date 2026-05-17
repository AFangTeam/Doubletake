import Foundation
import ImageIO

enum ExifReader {
    nonisolated static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    nonisolated static func read(from url: URL) -> ExifMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .empty
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .empty
        }

        var m = ExifMetadata()

        if let w = props[kCGImagePropertyPixelWidth] as? Int { m.pixelWidth = w }
        if let h = props[kCGImagePropertyPixelHeight] as? Int { m.pixelHeight = h }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        if let make = tiff[kCGImagePropertyTIFFMake] as? String, !make.isEmpty {
            m.cameraMake = make
        }
        if let model = tiff[kCGImagePropertyTIFFModel] as? String, !model.isEmpty {
            m.cameraModel = model
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
            m.lensModel = lens
        } else if let lens = exifAux[kCGImagePropertyExifAuxLensModel] as? String, !lens.isEmpty {
            m.lensModel = lens
        }

        if let f = exif[kCGImagePropertyExifFocalLength] as? Double { m.focalLengthMm = f }
        if let f35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double { m.focalLength35mmEquivMm = f35 }
        if let fn = exif[kCGImagePropertyExifFNumber] as? Double { m.fNumber = fn }
        if let et = exif[kCGImagePropertyExifExposureTime] as? Double { m.exposureTimeSeconds = et }
        if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArr.first {
            m.isoSpeed = iso
        } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
            m.isoSpeed = iso
        }

        if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let offsetStr = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            m.captureDate = parseExifDate(dateStr, offset: offsetStr)
        } else if let dateStr = exif[kCGImagePropertyExifDateTimeDigitized] as? String {
            m.captureDate = parseExifDate(dateStr, offset: nil)
        } else if let dateStr = tiff[kCGImagePropertyTIFFDateTime] as? String {
            m.captureDate = parseExifDate(dateStr, offset: nil)
        }

        return m
    }

    nonisolated private static func parseExifDate(_ s: String, offset: String?) -> Date? {
        if let offset, !offset.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let d = f.date(from: s + offset) { return d }
        }
        return exifDateFormatter.date(from: s)
    }
}

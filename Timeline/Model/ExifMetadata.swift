import Foundation

nonisolated struct ExifMetadata: Hashable, Sendable {
    var captureDate: Date?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLengthMm: Double?
    var focalLength35mmEquivMm: Double?
    var fNumber: Double?
    var exposureTimeSeconds: Double?
    var isoSpeed: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?

    static let empty = ExifMetadata()

    var focalLengthDisplay: String? {
        if let f = focalLengthMm {
            if let eq = focalLength35mmEquivMm, abs(eq - f) > 0.5 {
                return String(format: "%.0fmm (35mm 等效 %.0fmm)", f, eq)
            }
            return String(format: "%.0fmm", f)
        }
        if let eq = focalLength35mmEquivMm {
            return String(format: "%.0fmm (35mm 等效)", eq)
        }
        return nil
    }

    var apertureDisplay: String? {
        guard let f = fNumber else { return nil }
        return String(format: "f/%.1f", f)
    }

    var shutterDisplay: String? {
        guard let t = exposureTimeSeconds else { return nil }
        if t >= 1 {
            return String(format: "%.1fs", t)
        }
        let denom = Int((1.0 / t).rounded())
        return "1/\(denom)s"
    }

    var isoDisplay: String? {
        guard let iso = isoSpeed else { return nil }
        return "ISO \(iso)"
    }

    var pixelSizeDisplay: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w) × \(h)"
    }
}

import Foundation

/// Deterministic look of the artwork placeholder (gradient + initial), as in the mockups.
public enum PlaceholderStyle {
    /// Stable hue in degrees `0..<360` for a title (FNV-1a: `hashValue` is randomized per launch).
    public static func hue(for title: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in title.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 360)
    }

    /// First letter or digit, uppercased; `?` when there is none.
    public static func initial(for title: String) -> String {
        title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?"
    }

    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    /// HSL (hue in degrees, saturation and lightness in `0...1`) to sRGB.
    public static func rgb(hue: Double, saturation: Double, lightness: Double) -> RGB {
        let h = hue.truncatingRemainder(dividingBy: 360)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - chroma / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (chroma, x, 0)
        case ..<120: (x, chroma, 0)
        case ..<180: (0, chroma, x)
        case ..<240: (0, x, chroma)
        case ..<300: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}

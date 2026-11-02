import Foundation

/// Chapter geometry, shared by the bar's markers and the Chapitres tab.
public enum ChapterMarks {
    /// Where to draw a marker on the bar, 0...1 of the file. The first chapter (the start) and any chapter
    /// outside the file draw nothing.
    public static func fractions(starts: [Double], duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return starts
            .filter { $0.isFinite && $0 > 0 && $0 < duration }
            .map { $0 / duration }
    }

    /// The chapter the playhead is in: the last one that started. Nil before the first one or without chapters.
    public static func currentIndex(starts: [Double], position: Double) -> Int? {
        starts.lastIndex { $0 <= position + 0.5 }
    }

    /// The bar's segments as (start, end) fractions, split at each mark: `[0.2, 0.6]` -> 0-0.2, 0.2-0.6, 0.6-1.
    public static func segments(marks: [Double]) -> [ClosedRange<Double>] {
        let bounds = [0.0] + marks.sorted().filter { $0 > 0 && $0 < 1 } + [1.0]
        return zip(bounds, bounds.dropFirst()).map { $0...$1 }
    }

    /// The width of each segment once `gap` points are left between neighbours; they sum to `width`.
    public static func segmentWidths(_ segments: [ClosedRange<Double>], width: Double, gap: Double) -> [Double] {
        let usable = max(width - gap * Double(max(segments.count - 1, 0)), 0)
        return segments.map { ($0.upperBound - $0.lowerBound) * usable }
    }

    /// Where the playhead sits in points: inside its segment, after the gaps of the segments before it.
    public static func playheadX(progress: Double, segments: [ClosedRange<Double>], width: Double, gap: Double) -> Double {
        let widths = segmentWidths(segments, width: width, gap: gap)
        let progress = min(max(progress, 0), 1)
        var x = 0.0
        for (segment, w) in zip(segments, widths) {
            if progress <= segment.upperBound || segment == segments.last {
                let span = segment.upperBound - segment.lowerBound
                let local = span > 0 ? (min(progress, segment.upperBound) - segment.lowerBound) / span : 0
                return x + w * local
            }
            x += w + gap
        }
        return x
    }
}

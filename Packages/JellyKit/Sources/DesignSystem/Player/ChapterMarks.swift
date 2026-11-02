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
}

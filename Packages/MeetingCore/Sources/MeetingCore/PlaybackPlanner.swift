import Foundation

/// A span of the original recording to play.
public struct Clip: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = max(end, start)
    }
    public var duration: Double { end - start }
}

/// Turns word/sentence timings into playable clips with a little context around them,
/// so a tapped word is not cut off mid-sound.
public enum PlaybackPlanner {
    public static let wordPreRoll = 0.18
    public static let wordPostRoll = 0.12
    public static let minWordClip = 0.4
    public static let sentencePreRoll = 0.1
    public static let sentencePostRoll = 0.3

    public static func clip(for timing: WordTiming, duration: Double) -> Clip {
        var s = timing.start - wordPreRoll
        var e = timing.end + wordPostRoll
        if e - s < minWordClip {
            let pad = (minWordClip - (e - s)) / 2
            s -= pad; e += pad
        }
        return clamp(Clip(start: s, end: e), duration)
    }

    public static func clip(for range: ClosedRange<Double>, duration: Double) -> Clip {
        clamp(Clip(start: range.lowerBound - sentencePreRoll, end: range.upperBound + sentencePostRoll), duration)
    }

    static func clamp(_ c: Clip, _ duration: Double) -> Clip {
        let upper = duration > 0 ? duration : c.end
        return Clip(start: min(max(0, c.start), upper), end: min(max(0, c.end), upper))
    }

    /// Supported playback speeds.
    public static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]
}

public enum TimeFormat {
    /// 00:13:21.120 style (hours always shown for long meetings).
    public static func precise(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// 04:30 or 1:04:30.
    public static func short(_ t: Double) -> String {
        let s = Int(max(0, t).rounded(.down))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Parses "13:21.12", "00:13:21,120" or "801.5" into seconds.
    public static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let v = Double(t) { return v >= 0 ? v : nil }
        let parts = t.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (i, p) in parts.enumerated() {
            guard let v = Double(p), v >= 0 else { return nil }
            if i < parts.count - 1 && v != v.rounded() { return nil }
            total = total * 60 + v
        }
        return total
    }
}

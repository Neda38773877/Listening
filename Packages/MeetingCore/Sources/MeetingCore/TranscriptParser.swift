import Foundation

/// A word read from an imported transcript file.
public struct ParsedWord: Hashable, Sendable {
    public var text: String
    public var speaker: String?
    /// True when the word starts a new paragraph / subtitle cue / speaker turn.
    /// Used as a hint by sentence segmentation.
    public var startsBlock: Bool

    public init(text: String, speaker: String? = nil, startsBlock: Bool = false) {
        self.text = text
        self.speaker = speaker
        self.startsBlock = startsBlock
    }
}

/// Reads transcripts from Voice Memos (.txt), Markdown, SRT or WebVTT.
///
/// It only removes *formatting* (timestamps, cue numbers, markdown syntax, speaker
/// labels). It never changes the spoken words; the untouched file is stored separately.
public enum TranscriptParser {

    public static func parse(_ raw: String) -> [ParsedWord] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        let names = recurringNameLabels(lines)
        var out: [ParsedWord] = []
        var speaker: String?
        var newBlock = true

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { newBlock = true; continue }
            if isSubtitleHeader(line) || isCueNumber(line) || isCueTiming(line) { newBlock = true; continue }

            line = stripMarkdown(line)
            line = stripTimestamps(line)
            line = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // VTT/HTML tags
            if case let (label, rest)? = splitSpeakerLabel(line, knownNames: names) {
                if label != speaker { newBlock = true }
                speaker = label
                line = rest
            }
            for w in GermanText.words(line) {
                // Keep pure punctuation tokens (e.g. "–") attached to the previous word.
                if GermanText.stripPunctuation(w).isEmpty {
                    if !out.isEmpty { out[out.count - 1].text += w }
                    continue
                }
                out.append(ParsedWord(text: w, speaker: speaker, startsBlock: newBlock))
                newBlock = false
            }
        }
        return out
    }

    // MARK: - Line classifiers

    static func isSubtitleHeader(_ line: String) -> Bool {
        line.hasPrefix("WEBVTT") || line.hasPrefix("NOTE ") || line == "NOTE" || line.hasPrefix("STYLE") || line.hasPrefix("Kind:") || line.hasPrefix("Language:")
    }

    static func isCueNumber(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy(\.isNumber) && line.count <= 6
    }

    static func isCueTiming(_ line: String) -> Bool {
        line.contains("-->")
    }

    /// Removes timestamps like "00:12", "[01:02:03]", "(12:30.5)" that Voice Memos
    /// exports and other tools put at the start of lines.
    static func stripTimestamps(_ line: String) -> String {
        // Only at the start of a line or inside brackets: a spoken "um 14:30 Uhr"
        // in the middle of a sentence is part of the transcript and must stay.
        let leading = #"^(?:[\[(]?\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?[\])]?\s*)+"#
        let bracketed = #"[\[(]\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?[\])]"#
        return line.replacingOccurrences(of: leading, with: "", options: .regularExpression)
            .replacingOccurrences(of: bracketed, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func stripMarkdown(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*+>]\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        return s
    }

    static let bracketLabel = #"^\[([^\]]{1,40})\]\s*:?\s*"#
    static let genericLabel = #"^((?:Sprecher|Sprecherin|Speaker|Teilnehmer|Person)\s*\d{1,2})\s*:\s*"#
    static let nameLabel = #"^([A-ZÄÖÜ][\p{L}.'-]{1,24}(?:\s[A-ZÄÖÜ][\p{L}.'-]{1,24})?)\s*:\s+"#

    /// "Name:" prefixes are only treated as speaker labels when the same name starts
    /// at least three lines — otherwise "Wichtig: ..." would lose a spoken word.
    static func recurringNameLabels(_ lines: [String]) -> Set<String> {
        guard let re = try? NSRegularExpression(pattern: nameLabel) else { return [] }
        var counts: [String: Int] = [:]
        for raw in lines {
            let line = stripTimestamps(stripMarkdown(raw.trimmingCharacters(in: .whitespaces)))
            let ns = line as NSString
            if let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                counts[ns.substring(with: m.range(at: 1)), default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 3 }.keys)
    }

    /// Recognizes "Sprecher 1:", "Speaker 2:", "[Anna]" and recurring "Carlos:" at the start of a line.
    static func splitSpeakerLabel(_ line: String, knownNames: Set<String> = []) -> (String, String)? {
        for p in [bracketLabel, genericLabel, nameLabel] {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = line as NSString
            if let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let label = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if p == nameLabel && !knownNames.contains(label) { continue }
                let rest = ns.substring(from: m.range.location + m.range.length)
                if rest.isEmpty { continue }
                return (label, rest)
            }
        }
        return nil
    }
}

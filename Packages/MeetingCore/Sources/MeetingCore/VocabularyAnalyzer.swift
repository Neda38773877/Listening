import Foundation

/// A content word that was actually heard in the meeting.
public struct HeardWord: Hashable, Sendable {
    /// Most common surface form in the transcript (e.g. "Kalibrierung").
    public var form: String
    public var key: String
    public var count: Int
    /// Token index of every occurrence.
    public var occurrences: [Int]
}

/// Where a word in the vocabulary analysis comes from. The UI keeps these apart so
/// that suggested vocabulary is never presented as if it had been spoken.
public enum VocabularySource: String, Codable, Sendable {
    case heardInMeeting          // A
    case relatedWorkplace        // B
    case meetingExpression       // C
    case technical               // D
    case userDefined             // E

    public var title: String {
        switch self {
        case .heardInMeeting: return "Heard in this meeting"
        case .relatedWorkplace: return "Related workplace vocabulary (not necessarily heard)"
        case .meetingExpression: return "Common meeting expressions (recommended)"
        case .technical: return "Technical vocabulary (from your glossary)"
        case .userDefined: return "Your custom vocabulary"
        }
    }
}

public enum VocabularyAnalyzer {

    /// Stem key that groups simple inflections: Kalibrierung/Kalibrierungen, prüfen/prüft.
    public static func groupKey(_ word: String) -> String {
        let k = GermanText.normalize(word)
        guard k.count > 5 else { return k }
        for suffix in ["en", "er", "es", "e", "n", "s", "t"] where k.hasSuffix(suffix) && k.count - suffix.count >= 5 {
            return String(k.dropLast(suffix.count))
        }
        return k
    }

    /// Content words of the meeting ranked by frequency (function words and fillers removed).
    public static func heardWords(_ tokens: [Token]) -> [HeardWord] {
        var groups: [String: (forms: [String: Int], occ: [Int])] = [:]
        for (i, t) in tokens.enumerated() {
            let w = t.word
            let n = GermanText.normalize(w)
            guard n.count >= 3, !GermanText.isFunctionWord(w), !n.allSatisfy(\.isNumber),
                  !MeetingAssembler.fillers.contains(n), w != Correction.unclearMarker else { continue }
            let key = groupKey(w)
            var g = groups[key] ?? (forms: [:], occ: [])
            g.forms[w, default: 0] += 1
            g.occ.append(i)
            groups[key] = g
        }
        return groups.map { key, g in
            let form = g.forms.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key ?? key
            return HeardWord(form: form, key: key, count: g.occ.count, occurrences: g.occ)
        }
        .sorted { $0.count == $1.count ? $0.form < $1.form : $0.count > $1.count }
    }

    /// Whether a (possibly multi-word) term occurs in the meeting.
    public static func occurs(_ term: String, in tokens: [Token]) -> Bool {
        let parts = GermanText.words(term).map(groupKey)
        guard !parts.isEmpty, tokens.count >= parts.count else { return false }
        let keys = tokens.map { groupKey($0.word) }
        for i in 0...(keys.count - parts.count) where keys[i] == parts[0] {
            if Array(keys[i..<(i + parts.count)]) == parts { return true }
        }
        return false
    }

    /// Curated related workplace vocabulary (category B). Shown as suggestions only.
    public static let relatedWorkplace: [(german: String, english: String, persian: String)] = [
        ("die Besprechung", "meeting", "جلسه"),
        ("das Protokoll", "minutes", "صورت‌جلسه"),
        ("die Maßnahme", "measure / action", "اقدام"),
        ("die Ursache", "cause", "علت"),
        ("die Abweichung", "deviation", "انحراف"),
        ("der Ausschuss", "scrap / reject", "ضایعات"),
        ("die Nacharbeit", "rework", "دوباره‌کاری"),
        ("die Stichprobe", "random sample", "نمونهٔ تصادفی"),
        ("die Freigabe", "release / approval", "تأیید / آزادسازی"),
        ("die Rückmeldung", "feedback", "بازخورد"),
        ("der Zeitplan", "schedule", "برنامهٔ زمانی"),
        ("der Liefertermin", "delivery date", "تاریخ تحویل"),
        ("die Schicht", "shift", "شیفت"),
        ("die Auswertung", "evaluation / analysis", "ارزیابی / تحلیل"),
        ("abstimmen", "to coordinate / align", "هماهنگ کردن"),
        ("nachfragen", "to follow up / ask", "پیگیری کردن / پرسیدن"),
        ("klären", "to clarify", "روشن کردن"),
        ("umsetzen", "to implement", "اجرا کردن"),
        ("überprüfen", "to check / verify", "بررسی کردن"),
        ("dokumentieren", "to document", "مستند کردن"),
    ]
}

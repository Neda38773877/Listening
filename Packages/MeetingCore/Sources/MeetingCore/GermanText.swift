import Foundation

/// Text utilities tuned for German meeting transcripts.
public enum GermanText {

    /// Removes leading/trailing punctuation and quotes but keeps inner hyphens,
    /// apostrophes and dots ("z.B.", "PV-Modul", "geht's").
    public static func stripPunctuation(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars)
        var lo = 0, hi = scalars.count
        while lo < hi, !isWordScalar(scalars[lo]) { lo += 1 }
        while hi > lo, !isWordScalar(scalars[hi - 1]) { hi -= 1 }
        var s = String.UnicodeScalarView()
        s.append(contentsOf: scalars[lo..<hi])
        return String(s)
    }

    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(u)
    }

    /// Lower-cased, NFC, letters and digits only. "Überprüfen," → "überprüfen".
    public static func normalize(_ word: String) -> String {
        let lowered = word.precomposedStringWithCanonicalMapping.lowercased()
        var out = String.UnicodeScalarView()
        for u in lowered.unicodeScalars where CharacterSet.alphanumerics.contains(u) {
            out.append(u)
        }
        return String(out)
    }

    /// Normalization used for search: additionally folds ä→ae, ß→ss etc. so that
    /// "Pruefung" finds "Prüfung".
    public static func searchKey(_ text: String) -> String {
        var s = normalize(text)
        for (a, b) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s
    }

    /// Splits text into whitespace-separated words (punctuation stays attached).
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    // MARK: Similarity

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    /// 1.0 for identical strings, 0 for completely different ones.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let n = max(a.count, b.count)
        guard n > 0 else { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(n)
    }

    /// Kölner Phonetik: a German phonetic code, so "Botting" ≈ "Potting".
    public static func colognePhonetic(_ word: String) -> String {
        let chars = Array(normalize(word)
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "s"))
            .filter { $0.isLetter }
        guard !chars.isEmpty else { return "" }
        var codes: [Character] = []
        for i in 0..<chars.count {
            let c = chars[i]
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let code: String
            switch c {
            case "a", "e", "i", "j", "o", "u", "y": code = "0"
            case "h": code = "-"
            case "b": code = "1"
            case "p": code = next == "h" ? "3" : "1"
            case "d", "t": code = (next != nil && "csz".contains(next!)) ? "8" : "2"
            case "f", "v", "w": code = "3"
            case "g", "k", "q": code = "4"
            case "c":
                if i == 0 {
                    code = (next != nil && "ahkloqrux".contains(next!)) ? "4" : "8"
                } else if let p = prev, "sz".contains(p) {
                    code = "8"
                } else {
                    code = (next != nil && "ahkoqux".contains(next!)) ? "4" : "8"
                }
            case "x": code = (prev != nil && "ckq".contains(prev!)) ? "8" : "48"
            case "l": code = "5"
            case "m", "n": code = "6"
            case "r": code = "7"
            case "s", "z": code = "8"
            default: code = "-"
            }
            codes.append(contentsOf: code)
        }
        // Collapse repeats, then drop "-" and all "0" except a leading one.
        var collapsed: [Character] = []
        for c in codes where collapsed.last != c { collapsed.append(c) }
        var out = ""
        for (i, c) in collapsed.enumerated() {
            if c == "-" { continue }
            if c == "0" && i != 0 { continue }
            out.append(c)
        }
        return out
    }

    /// True when two words are plausibly the same spoken word: same stem with a
    /// different ending, a small spelling difference, or the same phonetic code.
    public static func soundsAlike(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        if x == y { return true }
        guard x.count >= 3, y.count >= 3 else { return false }
        if similarity(x, y) >= 0.75 { return true }
        let shorter = x.count <= y.count ? x : y, longer = x.count <= y.count ? y : x
        if shorter.count >= 5 && longer.hasPrefix(shorter) && longer.count - shorter.count <= 3 { return true }
        if x.count >= 4 && y.count >= 4 {
            let px = colognePhonetic(x), py = colognePhonetic(y)
            if !px.isEmpty && px == py { return true }
        }
        return false
    }

    // MARK: Function words

    /// High-frequency German function words that are not worth saving as vocabulary.
    public static let stopwords: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines",
        "und", "oder", "aber", "doch", "denn", "sondern", "als", "wie", "wenn", "dass", "ob", "weil",
        "ich", "du", "er", "sie", "es", "wir", "ihr", "mich", "dich", "sich", "uns", "euch", "mir", "dir", "ihm", "ihn",
        "mein", "dein", "sein", "unser", "euer", "meine", "deine", "seine", "unsere", "ihre", "ihren", "ihrem",
        "ist", "sind", "war", "waren", "bin", "bist", "hat", "haben", "habe", "hast", "hatte", "wird", "werden", "wurde",
        "kann", "können", "muss", "müssen", "soll", "sollen", "will", "wollen", "darf", "mag",
        "nicht", "kein", "keine", "keinen", "auch", "noch", "schon", "nur", "mal", "ja", "nein", "so", "da", "hier", "dort",
        "in", "im", "an", "am", "auf", "aus", "bei", "mit", "nach", "von", "vom", "zu", "zum", "zur", "für", "über", "unter",
        "vor", "hinter", "durch", "gegen", "ohne", "um", "bis", "seit", "ab",
        "was", "wer", "wo", "wann", "warum", "welche", "welcher", "welches", "dann", "also", "jetzt", "halt", "eben",
        "äh", "ähm", "hm", "okay", "ok", "genau", "gut", "man", "diese", "dieser", "dieses", "diesen", "diesem",
        "alle", "alles", "viel", "mehr", "sehr", "einfach", "ganz", "gibt", "geht", "mach", "macht", "machen",
    ]

    public static func isFunctionWord(_ word: String) -> Bool {
        stopwords.contains(normalize(word))
    }
}

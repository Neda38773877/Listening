import Foundation

/// Splits the token stream into sentences / speech segments for playback and study.
///
/// Boundaries come from, in order of preference: sentence-final punctuation in the
/// transcript, a speaker change or new paragraph, and — for unpunctuated or very
/// long stretches — real pauses measured in the audio.
public enum SentenceSegmenter {

    public struct Options: Sendable {
        /// Pause (seconds) that ends a segment when the transcript has no punctuation.
        public var pause: Double = 0.7
        /// Segments longer than this are split at the best comma or pause.
        public var maxWords: Int = 28
        public var minWords: Int = 3
        public init() {}
    }

    /// German abbreviations whose trailing dot does not end a sentence.
    static let abbreviations: Set<String> = [
        "z.b", "d.h", "u.a", "bzw", "ca", "evtl", "ggf", "inkl", "exkl", "nr", "dr", "prof", "hr", "fr", "usw", "etc",
        "vgl", "s.o", "s.u", "o.ä", "u.u", "z.t", "bspw", "max", "min", "mind", "tel", "abt", "st", "std", "sek",
        "jan", "feb", "mär", "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez", "kw", "mio", "mrd",
    ]

    public static func segment(_ tokens: [Token], blockStarts: Set<Int> = [], options: Options = Options()) -> [Sentence] {
        let visible = tokens.indices.filter { !tokens[$0].display.isEmpty || tokens[$0].isInsertion }
        guard !visible.isEmpty else { return [] }
        let hasPunctuation = tokens.contains { endsSentence($0.display, next: nil) }

        var cuts: [Int] = [0]   // token indices that start a sentence
        var countSinceCut = 0
        for i in tokens.indices {
            if i > 0 && i != cuts.last! {
                let prev = tokens[i - 1]
                var cut = false
                if !prev.isInsertion && endsSentence(prev.display, next: tokens[i].isInsertion ? nil : tokens[i].display) { cut = true }
                if blockStarts.contains(i) && countSinceCut >= 1 { cut = true }
                if let s = tokens[i].speaker, let ps = prev.speaker, s != ps { cut = true }
                if !hasPunctuation, countSinceCut >= options.minWords, let g = gap(before: i, tokens), g >= options.pause { cut = true }
                if cut { cuts.append(i); countSinceCut = 0 }
            }
            if !tokens[i].isInsertion { countSinceCut += 1 }
        }

        // Split overlong segments.
        var refined: [Int] = []
        for (k, start) in cuts.enumerated() {
            let end = k + 1 < cuts.count ? cuts[k + 1] : tokens.count
            refined.append(contentsOf: splitLong(start, end, tokens, options))
        }

        var sentences: [Sentence] = []
        for (k, start) in refined.enumerated() {
            let end = k + 1 < refined.count ? refined[k + 1] : tokens.count
            if end > start { sentences.append(Sentence(id: sentences.count, firstToken: start, endToken: end)) }
        }
        return mergeTiny(sentences, tokens, options)
    }

    // MARK: - Helpers

    static func endsSentence(_ word: String, next: String?) -> Bool {
        guard let last = word.last(where: { !"\"'»«“”„)]".contains($0) }) else { return false }
        if last == "?" || last == "!" || last == "…" { return true }
        guard last == "." else { return false }
        let core = GermanText.stripPunctuation(word).lowercased()
        if abbreviations.contains(core) || abbreviations.contains(core.replacingOccurrences(of: ".", with: "")) { return false }
        // Single letters ("A.") and ordinal numbers ("3. Oktober") are not sentence ends
        // when followed by more text on the same line.
        if core.count == 1 { return false }
        if core.allSatisfy(\.isNumber), let n = next, let f = n.first, !f.isUppercase || isMonth(n) { return false }
        return true
    }

    static func isMonth(_ w: String) -> Bool {
        ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]
            .contains(GermanText.normalize(w))
    }

    /// Silence between token i-1 and token i, from real timings only.
    static func gap(before i: Int, _ tokens: [Token]) -> Double? {
        guard i > 0, let a = tokens[i - 1].timing, let b = tokens[i].timing,
              a.source != .between, b.source != .between else { return nil }
        return b.start - a.end
    }

    static func splitLong(_ start: Int, _ end: Int, _ tokens: [Token], _ o: Options) -> [Int] {
        let words = (start..<end).filter { !tokens[$0].isInsertion }.count
        guard words > o.maxWords else { return [start] }
        // Best cut: a comma/semicolon/colon or long pause near the middle, not too close to the edges.
        var best: (index: Int, score: Double)?
        let lo = start + o.minWords + 2, hi = end - o.minWords - 2
        if lo < hi {
            for i in lo..<hi {
                let prev = tokens[i - 1].display
                var score = 0.0
                if let c = prev.last, ",;:–-".contains(c) { score += 2 }
                if let g = gap(before: i, tokens) { score += min(g, 2) * 2 }
                let mid = Double(start + end) / 2
                score -= abs(Double(i) - mid) / Double(end - start)   // prefer the middle
                if score > (best?.score ?? 0.2) { best = (i, score) }
            }
        }
        let cut = best?.index ?? (start + (end - start) / 2)
        return splitLong(start, cut, tokens, o) + splitLong(cut, end, tokens, o)
    }

    /// Segments made only of hidden insertion tokens are glued onto the previous sentence.
    static func mergeTiny(_ s: [Sentence], _ tokens: [Token], _ o: Options) -> [Sentence] {
        var out: [Sentence] = []
        for sent in s {
            let words = sent.tokenRange.filter { !tokens[$0].isInsertion }.count
            if let last = out.last, words == 0 {
                out[out.count - 1] = Sentence(id: last.id, firstToken: last.firstToken, endToken: sent.endToken)
                continue
            }
            out.append(sent)
        }
        for i in out.indices { out[i].id = i }
        return out
    }
}

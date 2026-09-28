import Foundation

/// Builds tokens (with audio timing) and correction suggestions from the imported
/// transcript and the recognizer output.
///
/// Rules this type enforces:
/// * the transcript text is never changed — differences become *suggestions*;
/// * every timestamp comes from a recognized word (or is explicitly marked as
///   approximate, bounded by aligned neighbours);
/// * a custom-dictionary term is only suggested when the audio evidence sounds like it.
public enum MeetingAssembler {

    public struct Output: Sendable {
        public var tokens: [Token]
        public var corrections: [Correction]
        /// Token indices where the transcript started a new paragraph / speaker turn.
        public var blockStarts: Set<Int>
    }

    /// Filler words that are never suggested as insertions.
    static let fillers: Set<String> = ["äh", "ähm", "öhm", "hm", "hmm", "mhm", "ah", "oh", "eh", "em"]
    /// Longest span shown as "somewhere between the neighbours". Beyond that there is no useful timing.
    static let maxBetweenSpan = 6.0

    public static func assemble(parsed: [ParsedWord], recognized: [RecognizedWord],
                                dictionary: CustomDictionary = CustomDictionary()) -> Output {
        if parsed.isEmpty { return fromRecognitionOnly(recognized) }

        let alignment = WordAligner.align(transcript: parsed.map(\.text), recognized: recognized.map(\.text))

        // 1. Base tokens with timing from their linked recognized word.
        var tokens: [Token] = []
        tokens.reserveCapacity(parsed.count + alignment.unmatchedRecognized.count)
        var links: [AlignmentLink?] = []
        for (i, w) in parsed.enumerated() {
            var t = Token(id: 0, original: w.text, speaker: w.speaker)
            if let link = alignment.links[i] {
                let r = recognized[link.recognizedIndex]
                let c = effectiveConfidence(r)
                switch link.kind {
                case .exact: t.timing = WordTiming(start: r.start, end: r.end, source: .aligned, confidence: c)
                case .similar: t.timing = WordTiming(start: r.start, end: r.end, source: .fuzzy, confidence: c * 0.8)
                case .substituted: t.timing = WordTiming(start: r.start, end: r.end, source: .fuzzy, confidence: c * 0.5)
                }
            }
            tokens.append(t)
            links.append(alignment.links[i])
        }

        // 2. Unlinked transcript words: split compounds share their partner's timing,
        //    everything else is bounded by aligned neighbours and flagged for review.
        for i in tokens.indices where links[i] == nil {
            if let shared = compoundPartnerTiming(i, parsed: parsed, links: links, recognized: recognized) {
                tokens[i].timing = shared
                continue
            }
            tokens[i].needsReview = true
            tokens[i].timing = betweenTiming(i, tokens: tokens, links: links)
        }

        // 3. Corrections for mismatched pairs.
        var corrections: [Correction] = []
        var blockStarts = Set<Int>()
        for i in tokens.indices {
            if parsed[i].startsBlock { blockStarts.insert(i) }
            if let link = links[i], link.kind != .exact {
                if let c = replacementSuggestion(tokenIndex: i, original: parsed[i].text,
                                                  heard: recognized[link.recognizedIndex], kind: link.kind,
                                                  dictionary: dictionary) {
                    corrections.append(c)
                }
            } else if links[i] == nil, tokens[i].timing?.source != .fuzzy, !GermanText.isFunctionWord(parsed[i].text) {
                corrections.append(Correction(id: 0, tokenID: i, kind: .unverified, original: parsed[i].text,
                                              suggested: parsed[i].text, confidence: .low,
                                              reason: "No matching word was found in the audio recognition. Listen and confirm."))
            }
        }

        // 4. Words heard in the audio but missing from the transcript become
        //    hidden insertion tokens (empty original) with a pending suggestion.
        var insertAfter: [Int: [Int]] = [:]   // transcript index (-1 = start) → recognized indices
        var lastLinkedTranscript = -1
        var recToTranscript = [Int: Int]()
        for (i, l) in links.enumerated() { if let l = l { recToTranscript[l.recognizedIndex] = i } }
        let unmatched = Set(alignment.unmatchedRecognized)
        for r in recognized.indices {
            if let ti = recToTranscript[r] { lastLinkedTranscript = ti; continue }
            guard unmatched.contains(r) else { continue }
            let key = GermanText.normalize(recognized[r].text)
            if key.isEmpty || fillers.contains(key) { continue }
            if effectiveConfidence(recognized[r]) < 0.5 { continue }
            insertAfter[lastLinkedTranscript, default: []].append(r)
        }

        let (merged, remap) = mergeInsertions(tokens: tokens, insertAfter: insertAfter, recognized: recognized)
        tokens = merged
        corrections = corrections.map { c in var c = c; c.tokenID = remap[c.tokenID] ?? c.tokenID; return c }
        blockStarts = Set(blockStarts.compactMap { remap[$0] })
        for (idx, t) in tokens.enumerated() where t.isInsertion {
            guard let timing = t.timing else { continue }
            let heard = t.corrected ?? ""
            tokens[idx].corrected = nil
            let conf: Confidence = timing.confidence >= 0.9 ? .medium : .low
            corrections.append(Correction(id: 0, tokenID: idx, kind: .insert, original: "", suggested: heard,
                                          confidence: conf,
                                          reason: "Heard in the audio but missing from the transcript."))
        }

        corrections.sort { $0.tokenID < $1.tokenID }
        for i in corrections.indices { corrections[i].id = i }
        for i in tokens.indices { tokens[i].id = i }
        return Output(tokens: tokens, corrections: corrections, blockStarts: blockStarts)
    }

    // MARK: - Pieces

    static func effectiveConfidence(_ r: RecognizedWord) -> Double {
        // The recognizer reports 0 when it has no score; treat that as "unknown, fairly good".
        r.confidence > 0 ? r.confidence : 0.7
    }

    static func fromRecognitionOnly(_ recognized: [RecognizedWord]) -> Output {
        var tokens: [Token] = []
        var corrections: [Correction] = []
        for (i, r) in recognized.enumerated() {
            let c = effectiveConfidence(r)
            var t = Token(id: i, original: r.text, timing: WordTiming(start: r.start, end: r.end, source: .aligned, confidence: c))
            if c < 0.35 {
                t.needsReview = true
                corrections.append(Correction(id: corrections.count, tokenID: i, kind: .replace, original: r.text,
                                              suggested: Correction.unclearMarker, confidence: .low,
                                              reason: "The recognizer was unsure about this word (\(Int(c * 100))%). Listen and correct."))
            }
            tokens.append(t)
        }
        return Output(tokens: tokens, corrections: corrections, blockStarts: [0])
    }

    /// "Laminat Inspektion" in the transcript vs. "Laminatinspektion" heard: the
    /// unlinked half shares the timing of the linked half.
    static func compoundPartnerTiming(_ i: Int, parsed: [ParsedWord], links: [AlignmentLink?],
                                      recognized: [RecognizedWord]) -> WordTiming? {
        for n in [i - 1, i + 1] where n >= 0 && n < parsed.count {
            guard let l = links[n], l.kind != .exact else { continue }
            let heard = GermanText.normalize(recognized[l.recognizedIndex].text)
            let joined = n < i ? GermanText.normalize(parsed[n].text + parsed[i].text)
                               : GermanText.normalize(parsed[i].text + parsed[n].text)
            if joined == heard || GermanText.soundsAlike(joined, heard) {
                let r = recognized[l.recognizedIndex]
                return WordTiming(start: r.start, end: r.end, source: .fuzzy, confidence: effectiveConfidence(r) * 0.6)
            }
        }
        return nil
    }

    /// Interval between the nearest timed neighbours, or nil when that is too vague.
    static func betweenTiming(_ i: Int, tokens: [Token], links: [AlignmentLink?]) -> WordTiming? {
        var p = i - 1
        while p >= 0 && (links[p] == nil) { p -= 1 }
        var n = i + 1
        while n < tokens.count && (links[n] == nil) { n += 1 }
        guard p >= 0, n < tokens.count, let a = tokens[p].timing, let b = tokens[n].timing else { return nil }
        var start = a.end, end = b.start
        if end - start < 0.08 { start = a.start; end = b.end }
        guard end > start, end - start <= maxBetweenSpan else { return nil }
        return WordTiming(start: start, end: end, source: .between, confidence: 0.2)
    }

    static func replacementSuggestion(tokenIndex i: Int, original: String, heard: RecognizedWord, kind: LinkKind,
                                      dictionary: CustomDictionary) -> Correction? {
        let c = effectiveConfidence(heard)
        let heardText = GermanText.stripPunctuation(heard.text)
        let originalWord = GermanText.stripPunctuation(original)
        guard !heardText.isEmpty else { return nil }

        var suggested = heardText
        var confidence: Confidence
        var reason: String

        switch kind {
        case .exact:
            return nil
        case .similar:
            confidence = c >= 0.85 ? .high : (c >= 0.6 ? .medium : .low)
            reason = "The audio sounds like “\(heardText)” (recognizer \(Int(c * 100))%)."
        case .substituted:
            if c < 0.35 {
                suggested = Correction.unclearMarker
                confidence = .low
                reason = "Transcript and audio recognition disagree and the audio is unclear."
            } else {
                confidence = c >= 0.9 ? .medium : .low
                reason = "The recognizer heard a different word: “\(heardText)” (\(Int(c * 100))%)."
            }
        }

        // Custom dictionary: protect known terms, and point out dictionary terms only
        // when the audio itself sounds like them.
        if dictionary.exact(originalWord) != nil && dictionary.exact(heardText) == nil {
            confidence = .low
            reason += " “\(originalWord)” is in your custom dictionary, so the transcript is probably right."
        } else if let term = dictionary.exact(heardText) {
            reason += " “\(term.term)” is in your custom dictionary."
        } else if let term = dictionary.soundAlike(heardText), GermanText.soundsAlike(term.term, originalWord) {
            suggested = term.term
            confidence = min(confidence, .medium)
            reason = "Transcript “\(originalWord)” and audio “\(heardText)” both sound like your dictionary term “\(term.term)”."
        }

        // Keep the transcript's punctuation around the suggested word.
        if suggested != Correction.unclearMarker {
            suggested = transferPunctuation(from: original, to: suggested)
        }
        if GermanText.normalize(suggested) == GermanText.normalize(original) && suggested != Correction.unclearMarker { return nil }
        return Correction(id: 0, tokenID: i, kind: .replace, original: original, suggested: suggested,
                          confidence: confidence, reason: reason)
    }

    static func transferPunctuation(from original: String, to word: String) -> String {
        let core = GermanText.stripPunctuation(original)
        guard !core.isEmpty, let r = original.range(of: core) else { return word }
        return String(original[..<r.lowerBound]) + word + String(original[r.upperBound...])
    }

    /// Inserts hidden tokens for words heard but missing from the transcript.
    /// Returns the new token list and a map old index → new index.
    static func mergeInsertions(tokens: [Token], insertAfter: [Int: [Int]], recognized: [RecognizedWord]) -> ([Token], [Int: Int]) {
        guard !insertAfter.isEmpty else {
            return (tokens, Dictionary(uniqueKeysWithValues: tokens.indices.map { ($0, $0) }))
        }
        var out: [Token] = []
        var remap: [Int: Int] = [:]
        func emit(_ recIdx: [Int]?, speaker: String?) {
            for r in recIdx ?? [] {
                let w = recognized[r]
                // `corrected` temporarily carries the heard text; assemble() moves it into a suggestion.
                out.append(Token(id: 0, original: "", corrected: GermanText.stripPunctuation(w.text),
                                 timing: WordTiming(start: w.start, end: w.end, source: .aligned, confidence: effectiveConfidence(w)),
                                 speaker: speaker, needsReview: true))
            }
        }
        emit(insertAfter[-1], speaker: tokens.first?.speaker)
        for (i, t) in tokens.enumerated() {
            remap[i] = out.count
            out.append(t)
            emit(insertAfter[i], speaker: t.speaker)
        }
        return (out, remap)
    }
}

import Foundation

/// User decisions on correction suggestions. The original transcript text stays in
/// `Token.original`; only `Token.corrected` changes, so every edit is traceable.
public extension MeetingDocument {

    mutating func accept(correction id: Int) {
        guard let c = corrections.first(where: { $0.id == id }) else { return }
        apply(correction: id, text: c.suggested, status: .accepted)
    }

    mutating func edit(correction id: Int, text: String) {
        apply(correction: id, text: text, status: .edited)
    }

    mutating func reject(correction id: Int) {
        guard let k = corrections.firstIndex(where: { $0.id == id }) else { return }
        let c = corrections[k]
        corrections[k].status = .rejected
        corrections[k].finalText = nil
        guard tokens.indices.contains(c.tokenID) else { return }
        tokens[c.tokenID].corrected = nil
        if c.kind == .unverified { tokens[c.tokenID].needsReview = false }
    }

    /// Reverts a decision back to "pending".
    mutating func reopen(correction id: Int) {
        guard let k = corrections.firstIndex(where: { $0.id == id }) else { return }
        corrections[k].status = .pending
        corrections[k].finalText = nil
        let t = corrections[k].tokenID
        if tokens.indices.contains(t) { tokens[t].corrected = nil; tokens[t].needsReview = true }
    }

    private mutating func apply(correction id: Int, text: String, status: CorrectionStatus) {
        guard let k = corrections.firstIndex(where: { $0.id == id }) else { return }
        let t = corrections[k].tokenID
        guard tokens.indices.contains(t) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        corrections[k].status = status
        corrections[k].finalText = clean
        tokens[t].corrected = (clean == tokens[t].original) ? nil : clean
        tokens[t].needsReview = clean == Correction.unclearMarker
    }

    /// Free edit of any word (not tied to a suggestion). Recorded as an edited correction.
    mutating func editToken(_ tokenID: Int, text: String) {
        guard tokens.indices.contains(tokenID) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = corrections.firstIndex(where: { $0.tokenID == tokenID }) {
            corrections[k].status = .edited
            corrections[k].finalText = clean
        } else {
            let nextID = (corrections.map(\.id).max() ?? -1) + 1
            corrections.append(Correction(id: nextID, tokenID: tokenID, kind: .replace, original: tokens[tokenID].original,
                                          suggested: clean, confidence: .high, reason: "Edited by you.",
                                          status: .edited, finalText: clean))
        }
        tokens[tokenID].corrected = (clean == tokens[tokenID].original) ? nil : clean
        tokens[tokenID].needsReview = false
    }

    /// Manual timing fix for a word (automatic alignment is never assumed perfect).
    mutating func setTiming(_ tokenID: Int, start: Double, end: Double) {
        guard tokens.indices.contains(tokenID), end > start, start >= 0 else { return }
        tokens[tokenID].timing = WordTiming(start: start, end: end, source: .manual, confidence: 1)
    }

    /// Shifts the whole sentence's timings by `delta` seconds (for a consistently early/late segment).
    mutating func shiftSentence(_ sentenceIndex: Int, by delta: Double) {
        guard sentences.indices.contains(sentenceIndex) else { return }
        for i in sentences[sentenceIndex].tokenRange {
            guard var t = tokens[i].timing else { continue }
            t.start = max(0, t.start + delta)
            t.end = max(t.start, t.end + delta)
            t.source = .manual
            tokens[i].timing = t
        }
    }

    /// Replaces the words of one sentence with user-typed text, keeping the originals
    /// traceable. Words are matched one-to-one; extra typed words attach to the last one.
    mutating func editSentence(_ sentenceIndex: Int, text: String) {
        guard sentences.indices.contains(sentenceIndex) else { return }
        let ids = sentences[sentenceIndex].tokenRange.filter { !tokens[$0].display.isEmpty }
        var words = GermanText.words(text)
        guard !ids.isEmpty else { return }
        if words.count > ids.count {
            let tail = words[(ids.count - 1)...].joined(separator: " ")
            words = Array(words[..<(ids.count - 1)]) + [tail]
        }
        for (k, id) in ids.enumerated() {
            let new = k < words.count ? words[k] : ""
            if new != tokens[id].display { editToken(id, text: new) }
        }
    }
}

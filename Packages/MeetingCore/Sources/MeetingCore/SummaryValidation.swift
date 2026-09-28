import Foundation

/// Guards against invented content in AI output: every summary statement must cite
/// sentence numbers that exist, and quoted people must appear in the transcript.
public enum SummaryValidator {

    public static func validate(_ summary: MeetingSummary, sentenceCount: Int, transcript: String) -> MeetingSummary {
        var dropped = summary.droppedUnsupportedItems
        let lowerTranscript = transcript.lowercased()

        func clean(_ items: [EvidencedItem], requireNameInTranscript: Bool = false) -> [EvidencedItem] {
            items.compactMap { item in
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                if text == SummarySection.notStated { return nil }
                let ev = Array(Set(item.evidence.filter { $0 >= 0 && $0 < sentenceCount })).sorted()
                guard !ev.isEmpty else { dropped += 1; return nil }
                if requireNameInTranscript {
                    // A responsible person must be named in the transcript itself.
                    let names = GermanText.words(text).map(GermanText.stripPunctuation).filter { ($0.first?.isUppercase ?? false) && $0.count >= 3 }
                    if !names.isEmpty && !names.contains(where: { lowerTranscript.contains($0.lowercased()) }) {
                        dropped += 1
                        return nil
                    }
                }
                return EvidencedItem(text: text, evidence: ev)
            }
        }

        var sections: [SummarySection] = []
        for s in summary.sections {
            var n = s
            n.discussed = clean(s.discussed)
            n.problems = clean(s.problems)
            n.causes = clean(s.causes)
            n.actions = clean(s.actions)
            n.responsible = clean(s.responsible, requireNameInTranscript: true)
            n.deadlines = clean(s.deadlines)
            n.decisions = clean(s.decisions)
            n.openQuestions = clean(s.openQuestions)
            sections.append(n)
        }
        return MeetingSummary(sections: sections, provider: summary.provider, createdAt: summary.createdAt, droppedUnsupportedItems: dropped)
    }

    /// Topics must reference a valid, ordered sentence range.
    public static func validate(_ topics: [Topic], sentenceCount: Int) -> [Topic] {
        var out: [Topic] = []
        for t in topics.sorted(by: { $0.firstSentence < $1.firstSentence }) {
            guard t.firstSentence >= 0, t.firstSentence < sentenceCount, t.lastSentence >= t.firstSentence,
                  !t.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            var c = t
            c.lastSentence = min(t.lastSentence, sentenceCount - 1)
            if let prev = out.last, c.firstSentence <= prev.lastSentence { c.firstSentence = prev.lastSentence + 1 }
            if c.firstSentence > c.lastSentence { continue }
            c.id = out.count
            out.append(c)
        }
        return out
    }
}

/// Offline timeline: splits the meeting into sections at long pauses (about every
/// few minutes) and labels each with its most frequent content words. These labels
/// are marked `.automatic` — they are keywords, not an interpretation.
public enum AutomaticTopics {

    public static func detect(_ doc: MeetingDocument, targetMinutes: Double = 5) -> [Topic] {
        guard !doc.sentences.isEmpty else { return [] }
        let times = doc.sentences.map { doc.timeRange(of: $0) }
        var boundaries: [Int] = [0]
        var sectionStart = times.first??.lowerBound ?? 0
        let target = targetMinutes * 60
        var bestGap = (index: -1, gap: 0.0)
        for i in 1..<doc.sentences.count {
            guard let cur = times[i], let prev = times[i - 1] else { continue }
            let elapsed = cur.lowerBound - sectionStart
            let gap = cur.lowerBound - prev.upperBound
            if elapsed >= target * 0.6 && gap > bestGap.gap { bestGap = (i, gap) }
            if elapsed >= target * 1.4 || (elapsed >= target && bestGap.index > 0) {
                let cut = bestGap.index > boundaries.last! ? bestGap.index : i
                boundaries.append(cut)
                sectionStart = times[cut]?.lowerBound ?? cur.lowerBound
                bestGap = (-1, 0)
            }
        }
        var topics: [Topic] = []
        for (k, b) in boundaries.enumerated() {
            let last = (k + 1 < boundaries.count ? boundaries[k + 1] : doc.sentences.count) - 1
            guard last >= b else { continue }
            let first = doc.sentences[b].firstToken, end = doc.sentences[last].endToken
            let words = VocabularyAnalyzer.heardWords(Array(doc.tokens[first..<end]))
                .filter { $0.form.count >= 5 }
                .prefix(3).map(\.form)
            let title = words.isEmpty ? "Section \(k + 1)" : words.joined(separator: " · ")
            topics.append(Topic(id: k, title: title, firstSentence: b, lastSentence: last, provenance: .automatic))
        }
        return topics
    }
}

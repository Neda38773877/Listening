import Foundation

public enum SearchHitKind: String, Sendable {
    case word, sentence, translation, topic, redemittel
}

public struct SearchHit: Hashable, Sendable {
    public var meetingID: UUID
    public var kind: SearchHitKind
    public var sentenceIndex: Int?
    /// Token to play for word hits.
    public var tokenIndex: Int?
    public var text: String
    public var time: Double?
}

/// Full-text search over processed meetings: German words (inflection-tolerant),
/// sentences, English/Persian translations and topics.
public enum MeetingSearch {

    public static func search(_ query: String, in doc: MeetingDocument, limit: Int = 200) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let key = GermanText.searchKey(q)
        let isPhrase = GermanText.words(q).count > 1
        var hits: [SearchHit] = []

        if !isPhrase && !key.isEmpty {
            for (i, t) in doc.tokens.enumerated() where !t.display.isEmpty {
                let k = GermanText.searchKey(t.word)
                if k.hasPrefix(key) || (key.count >= 5 && k.contains(key)) {
                    let si = doc.sentenceIndex(containingToken: i)
                    let text = si.map { doc.text(of: doc.sentences[$0]) } ?? t.display
                    hits.append(SearchHit(meetingID: doc.id, kind: .word, sentenceIndex: si, tokenIndex: i, text: text, time: t.timing?.start))
                    if hits.count >= limit { return hits }
                }
            }
        }

        let lowered = q.lowercased()
        for (si, s) in doc.sentences.enumerated() {
            let german = doc.text(of: s)
            if isPhrase && german.lowercased().contains(lowered) {
                hits.append(SearchHit(meetingID: doc.id, kind: .sentence, sentenceIndex: si, tokenIndex: nil, text: german,
                                      time: doc.timeRange(of: s)?.lowerBound))
            }
            for tr in [s.english, s.persian].compactMap({ $0 }) where tr.text.lowercased().contains(lowered) {
                hits.append(SearchHit(meetingID: doc.id, kind: .translation, sentenceIndex: si, tokenIndex: nil,
                                      text: german + "\n" + tr.text, time: doc.timeRange(of: s)?.lowerBound))
            }
            if hits.count >= limit { return hits }
        }

        for t in doc.topics where t.title.lowercased().contains(lowered) {
            let time = doc.sentences.indices.contains(t.firstSentence) ? doc.timeRange(of: doc.sentences[t.firstSentence])?.lowerBound : nil
            hits.append(SearchHit(meetingID: doc.id, kind: .topic, sentenceIndex: t.firstSentence, tokenIndex: nil, text: t.title, time: time))
        }
        return hits
    }
}

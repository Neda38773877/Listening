import Foundation

/// Runs the pure (non-audio) processing steps on a meeting document.
public enum MeetingBuilder {

    /// Called by the processing pipeline, before the user has reviewed anything:
    /// correction decisions are reset. Rebuilds tokens, corrections, sentences and automatic topics from the stored
    /// original transcript and recognition result. Translations of sentences whose
    /// text did not change are carried over.
    public static func rebuild(_ doc: inout MeetingDocument, dictionary: CustomDictionary = CustomDictionary()) {
        let previous = Dictionary(doc.sentences.map { (doc.text(of: $0), $0) }, uniquingKeysWith: { a, _ in a })
        let parsed = TranscriptParser.parse(doc.originalTranscript)
        let out = MeetingAssembler.assemble(parsed: parsed, recognized: doc.recognized, dictionary: dictionary)
        doc.tokens = out.tokens
        doc.corrections = out.corrections
        doc.sentences = SentenceSegmenter.segment(out.tokens, blockStarts: out.blockStarts)
        for i in doc.sentences.indices {
            if let old = previous[doc.text(of: doc.sentences[i])] {
                doc.sentences[i].english = old.english
                doc.sentences[i].persian = old.persian
            }
        }
        if doc.topics.allSatisfy({ $0.provenance == .automatic }) {
            doc.topics = AutomaticTopics.detect(doc)
        } else {
            doc.topics = SummaryValidator.validate(doc.topics, sentenceCount: doc.sentences.count)
        }
    }

    /// Redemittel actually found in this meeting.
    public static func redemittel(in doc: MeetingDocument) -> [RedemittelHit] {
        RedemittelCatalog.find(in: doc.sentences.map { doc.text(of: $0) })
    }
}

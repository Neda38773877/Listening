import Foundation

// MARK: - Recognition input

/// One word as produced by the on-device speech recognizer. These are the only
/// source of audio timing in the app: every timestamp shown to the user can be
/// traced back to one of these (or to a manual correction).
public struct RecognizedWord: Codable, Hashable, Sendable {
    public var text: String
    /// Seconds from the start of the recording.
    public var start: Double
    public var end: Double
    /// Recognizer confidence 0…1 (0 when the recognizer did not report one).
    public var confidence: Double

    public init(text: String, start: Double, end: Double, confidence: Double) {
        self.text = text
        self.start = start
        self.end = max(end, start)
        self.confidence = confidence
    }

    public var duration: Double { end - start }
}

// MARK: - Timing

public enum TimingSource: String, Codable, Sendable {
    /// Transcript word matched the recognized word exactly.
    case aligned
    /// Transcript word matched a recognized word that is spelled differently
    /// (inflection, compound split, recognition error).
    case fuzzy
    /// No recognized counterpart; the interval is bounded by the two nearest
    /// aligned neighbours. Shown as approximate.
    case between
    /// Set by the user.
    case manual
}

public struct WordTiming: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var source: TimingSource
    /// 0…1. For `.between` this is always low.
    public var confidence: Double

    public init(start: Double, end: Double, source: TimingSource, confidence: Double) {
        self.start = start
        self.end = max(end, start)
        self.source = source
        self.confidence = confidence
    }

    public var isApproximate: Bool { source == .between }
}

// MARK: - Transcript tokens

/// A single word of the meeting transcript. `original` is never modified after
/// import; accepted corrections live in `corrected`.
public struct Token: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// The word exactly as it appeared in the imported transcript, including
    /// attached punctuation. Empty for words inserted from the audio.
    public var original: String
    /// User-accepted or user-edited text. `nil` means "unchanged".
    public var corrected: String?
    public var timing: WordTiming?
    /// Speaker label from the transcript (e.g. "Sprecher 1"), if any.
    public var speaker: String?
    /// True when the word could not be verified against the audio.
    public var needsReview: Bool

    public init(id: Int, original: String, corrected: String? = nil, timing: WordTiming? = nil,
                speaker: String? = nil, needsReview: Bool = false) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.timing = timing
        self.speaker = speaker
        self.needsReview = needsReview
    }

    /// Text to display: the correction if one was accepted, else the original.
    public var display: String { corrected ?? original }
    public var isInsertion: Bool { original.isEmpty }
    /// The bare word without surrounding punctuation, for lookups.
    public var word: String { GermanText.stripPunctuation(display) }
}

// MARK: - Sentences

public struct TranslationText: Codable, Hashable, Sendable {
    public var text: String
    /// Human-readable provider, e.g. "Apple Translation (on-device)", "Claude (external)", "You".
    public var provider: String
    public var createdAt: Date

    public init(text: String, provider: String, createdAt: Date = Date()) {
        self.text = text
        self.provider = provider
        self.createdAt = createdAt
    }
}

public struct Sentence: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// Half-open range into `MeetingDocument.tokens`.
    public var firstToken: Int
    public var endToken: Int
    public var english: TranslationText?
    public var persian: TranslationText?

    public init(id: Int, firstToken: Int, endToken: Int, english: TranslationText? = nil, persian: TranslationText? = nil) {
        self.id = id
        self.firstToken = firstToken
        self.endToken = endToken
        self.english = english
        self.persian = persian
    }

    public var tokenRange: Range<Int> { firstToken..<endToken }
}

// MARK: - Corrections

public enum Confidence: String, Codable, Sendable, CaseIterable, Comparable {
    case low, medium, high

    private var rank: Int { self == .low ? 0 : (self == .medium ? 1 : 2) }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
    public var label: String { rawValue.capitalized }
}

public enum CorrectionKind: String, Codable, Sendable {
    /// Transcript word differs from what the recognizer heard.
    case replace
    /// Recognizer heard a word that is missing from the transcript.
    case insert
    /// Transcript word has no audio evidence at all (nothing to suggest, only review).
    case unverified
}

public enum CorrectionStatus: String, Codable, Sendable {
    case pending, accepted, rejected, edited
}

public struct Correction: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var tokenID: Int
    public var kind: CorrectionKind
    public var original: String
    /// Suggested text. `"[UNCLEAR]"` when the audio is too uncertain to name a word.
    public var suggested: String
    public var confidence: Confidence
    public var reason: String
    public var status: CorrectionStatus
    /// What was finally written into the token (set when accepted/edited).
    public var finalText: String?

    public init(id: Int, tokenID: Int, kind: CorrectionKind, original: String, suggested: String,
                confidence: Confidence, reason: String, status: CorrectionStatus = .pending, finalText: String? = nil) {
        self.id = id
        self.tokenID = tokenID
        self.kind = kind
        self.original = original
        self.suggested = suggested
        self.confidence = confidence
        self.reason = reason
        self.status = status
        self.finalText = finalText
    }

    public static let unclearMarker = "[UNCLEAR]"
}

// MARK: - Topics / summary

public enum Provenance: String, Codable, Sendable {
    /// Derived locally from the transcript (keywords, pauses). Labelled as automatic.
    case automatic
    /// Produced by the external AI and validated against sentence evidence.
    case ai
    /// Entered by the user.
    case user
}

public struct Topic: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var firstSentence: Int
    public var lastSentence: Int
    public var provenance: Provenance

    public init(id: Int, title: String, firstSentence: Int, lastSentence: Int, provenance: Provenance) {
        self.id = id
        self.title = title
        self.firstSentence = firstSentence
        self.lastSentence = lastSentence
        self.provenance = provenance
    }
}

/// A single statement in the summary, tied to the sentences that support it.
public struct EvidencedItem: Codable, Hashable, Sendable {
    public var text: String
    public var evidence: [Int]

    public init(text: String, evidence: [Int]) {
        self.text = text
        self.evidence = evidence
    }
}

public struct SummarySection: Codable, Hashable, Sendable {
    public var topic: String
    public var discussed: [EvidencedItem]
    public var problems: [EvidencedItem]
    public var causes: [EvidencedItem]
    public var actions: [EvidencedItem]
    public var responsible: [EvidencedItem]
    public var deadlines: [EvidencedItem]
    public var decisions: [EvidencedItem]
    public var openQuestions: [EvidencedItem]

    public init(topic: String, discussed: [EvidencedItem] = [], problems: [EvidencedItem] = [], causes: [EvidencedItem] = [],
                actions: [EvidencedItem] = [], responsible: [EvidencedItem] = [], deadlines: [EvidencedItem] = [],
                decisions: [EvidencedItem] = [], openQuestions: [EvidencedItem] = []) {
        self.topic = topic
        self.discussed = discussed
        self.problems = problems
        self.causes = causes
        self.actions = actions
        self.responsible = responsible
        self.deadlines = deadlines
        self.decisions = decisions
        self.openQuestions = openQuestions
    }

    public static let notStated = "Not clearly stated in the meeting."
}

public struct MeetingSummary: Codable, Hashable, Sendable {
    public var sections: [SummarySection]
    public var provider: String
    public var createdAt: Date
    /// Items the model returned without valid evidence — dropped, but counted so the UI can say so.
    public var droppedUnsupportedItems: Int

    public init(sections: [SummarySection], provider: String, createdAt: Date = Date(), droppedUnsupportedItems: Int = 0) {
        self.sections = sections
        self.provider = provider
        self.createdAt = createdAt
        self.droppedUnsupportedItems = droppedUnsupportedItems
    }
}

// MARK: - Processing state

public enum ProcessingStage: String, Codable, Sendable, CaseIterable {
    case audioAnalysis, alignment, segmentation, vocabulary, translation, meetingAnalysis

    public var title: String {
        switch self {
        case .audioAnalysis: return "Audio analysis"
        case .alignment: return "Transcript alignment"
        case .segmentation: return "Sentence segmentation"
        case .vocabulary: return "Vocabulary extraction"
        case .translation: return "Translation"
        case .meetingAnalysis: return "Meeting analysis"
        }
    }
}

public struct ProcessingState: Codable, Hashable, Sendable {
    public var completed: Set<ProcessingStage> = []
    /// Recognition chunks already finished (for resuming a long recording).
    public var recognizedChunks: Set<Int> = []
    public var totalChunks: Int = 0
    public var lastError: String?

    public init() {}
}

// MARK: - Meeting document

/// Everything derived from one meeting. Stored as a JSON file next to the audio
/// (a 1-hour meeting has ~10k tokens — far too many for one database row each).
public struct MeetingDocument: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var audioFileName: String?
    public var duration: Double
    /// The transcript file exactly as imported. Never modified.
    public var originalTranscript: String
    public var transcriptFileName: String?
    public var recognized: [RecognizedWord]
    public var tokens: [Token]
    public var sentences: [Sentence]
    public var corrections: [Correction]
    public var topics: [Topic]
    public var summary: MeetingSummary?
    public var processing: ProcessingState

    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), audioFileName: String? = nil,
                duration: Double = 0, originalTranscript: String = "", transcriptFileName: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.audioFileName = audioFileName
        self.duration = duration
        self.originalTranscript = originalTranscript
        self.transcriptFileName = transcriptFileName
        self.recognized = []
        self.tokens = []
        self.sentences = []
        self.corrections = []
        self.topics = []
        self.summary = nil
        self.processing = ProcessingState()
    }

    // MARK: Convenience

    public func text(of sentence: Sentence) -> String {
        tokens[sentence.tokenRange].filter { !$0.display.isEmpty }.map(\.display).joined(separator: " ")
    }

    /// Original-transcript wording of the sentence (before any corrections).
    public func originalText(of sentence: Sentence) -> String {
        tokens[sentence.tokenRange].filter { !$0.isInsertion }.map(\.original).joined(separator: " ")
    }

    /// Audio span of a sentence, from its first to its last timed word.
    public func timeRange(of sentence: Sentence) -> ClosedRange<Double>? {
        let timed = tokens[sentence.tokenRange].compactMap(\.timing)
        guard let first = timed.first, let last = timed.last else { return nil }
        return first.start...max(first.start, last.end)
    }

    public func sentenceIndex(containingToken tokenID: Int) -> Int? {
        var lo = 0, hi = sentences.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = sentences[mid]
            if tokenID < s.firstToken { hi = mid - 1 } else if tokenID >= s.endToken { lo = mid + 1 } else { return mid }
        }
        return nil
    }

    /// Sentence playing at `time` (or the last one that started before it).
    public func sentenceIndex(at time: Double) -> Int? {
        var best: Int?
        for (i, s) in sentences.enumerated() {
            guard let r = timeRange(of: s) else { continue }
            if r.lowerBound <= time { best = i } else { break }
        }
        return best
    }

    /// Token being spoken at `time`, if any.
    public func tokenIndex(at time: Double, within sentence: Sentence) -> Int? {
        var best: Int?
        for i in sentence.tokenRange {
            guard let t = tokens[i].timing else { continue }
            if t.start <= time + 0.02 { best = i } else { break }
        }
        return best
    }

    public var pendingCorrections: [Correction] { corrections.filter { $0.status == .pending } }

    public var alignedWordRatio: Double {
        let real = tokens.filter { !$0.isInsertion }
        guard !real.isEmpty else { return 0 }
        let good = real.filter { t in
            guard let s = t.timing?.source else { return false }
            return s == .aligned || s == .fuzzy || s == .manual
        }
        return Double(good.count) / Double(real.count)
    }
}

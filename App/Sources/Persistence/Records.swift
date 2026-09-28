import Foundation
import SwiftData
import MeetingCore

/// One imported meeting. The heavy data (tokens, sentences, …) lives in a JSON
/// file managed by `MeetingStore`; this record is what lists and the dashboard query.
@Model
final class MeetingRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var statusRaw: String
    var statusDetail: String?
    var hasAudio: Bool
    var hasTranscript: Bool
    var sentenceCount: Int
    var pendingCorrections: Int
    var alignedRatio: Double
    /// JSON `[groupKey: count]` of the meeting's content words, for cross-meeting frequency.
    var wordCountsJSON: String
    var lastOpened: Date?
    var lastPosition: Double

    init(id: UUID, title: String, createdAt: Date = Date(), hasAudio: Bool, hasTranscript: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = 0
        self.statusRaw = MeetingStatus.imported.rawValue
        self.hasAudio = hasAudio
        self.hasTranscript = hasTranscript
        self.sentenceCount = 0
        self.pendingCorrections = 0
        self.alignedRatio = 0
        self.wordCountsJSON = "{}"
        self.lastPosition = 0
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .imported }
        set { statusRaw = newValue.rawValue }
    }

    var wordCounts: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: Data(wordCountsJSON.utf8))) ?? [:] }
        set { wordCountsJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}" }
    }
}

enum MeetingStatus: String {
    case imported, processing, ready, failed
}

/// A saved vocabulary entry with its spaced-repetition state.
@Model
final class VocabItem {
    @Attribute(.unique) var id: UUID
    var german: String
    /// Grouping key (see `VocabularyAnalyzer.groupKey`) used to count frequency across meetings.
    var key: String
    var english: String
    var persian: String
    var synonyms: [String]
    var partOfSpeech: String
    /// Where the meanings came from, e.g. "Claude (external)", "Your glossary", "You".
    var meaningSource: String
    var exampleSentence: String
    var exampleEnglish: String
    var examplePersian: String
    var meetingID: UUID?
    var meetingTitle: String
    var tokenIndex: Int?
    var clipStart: Double?
    var clipEnd: Double?
    var dateAdded: Date
    var notes: String
    var category: String
    /// 1 (easy) … 5 (hard)
    var difficulty: Int
    var mastered: Bool
    var savedManually: Bool
    var isExpression: Bool

    // SRS
    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var lapses: Int
    var due: Date
    var lastReviewed: Date?
    var timesSeen: Int
    var timesWrong: Int

    init(german: String, category: String = VocabCategory.work.rawValue, savedManually: Bool = true) {
        self.id = UUID()
        self.german = german
        self.key = VocabularyAnalyzer.groupKey(german)
        self.english = ""
        self.persian = ""
        self.synonyms = []
        self.partOfSpeech = ""
        self.meaningSource = ""
        self.exampleSentence = ""
        self.exampleEnglish = ""
        self.examplePersian = ""
        self.meetingTitle = ""
        self.dateAdded = Date()
        self.notes = ""
        self.category = category
        self.difficulty = 3
        self.mastered = false
        self.savedManually = savedManually
        self.isExpression = false
        self.ease = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.lapses = 0
        self.due = Date()
        self.timesSeen = 0
        self.timesWrong = 0
    }

    var srs: SRSState {
        get {
            var s = SRSState(due: due)
            s.ease = ease; s.intervalDays = intervalDays; s.repetitions = repetitions; s.lapses = lapses; s.lastReviewed = lastReviewed
            return s
        }
        set {
            ease = newValue.ease; intervalDays = newValue.intervalDays; repetitions = newValue.repetitions
            lapses = newValue.lapses; due = newValue.due; lastReviewed = newValue.lastReviewed
            if newValue.isMastered { mastered = true }
        }
    }

    var hasClip: Bool { meetingID != nil && clipStart != nil && clipEnd != nil }
}

enum VocabCategory: String, CaseIterable, Identifiable {
    case work = "Work", quality = "Quality", pv = "PV", production = "Production", engineering = "Engineering"
    case meetings = "Meetings", everyday = "Everyday German", grammar = "Grammar", people = "People"
    case machines = "Machines", processes = "Processes", other = "Other"

    var id: String { rawValue }

    /// Workplace categories rank higher in reviews than everyday German.
    static func weight(_ name: String) -> Double {
        switch VocabCategory(rawValue: name) {
        case .work, .quality, .pv, .production, .engineering, .meetings, .machines, .processes: return 1
        case .people, .grammar: return 0.6
        case .everyday: return 0.4
        case .other, .none: return 0.5
        }
    }
}

/// User-created vocabulary categories in addition to the built-in ones.
@Model
final class CustomCategory {
    @Attribute(.unique) var name: String
    init(name: String) { self.name = name }
}

/// Names, machines, abbreviations, … used as recognition hints and correction guards.
@Model
final class CustomTermRecord {
    @Attribute(.unique) var term: String
    var categoryRaw: String
    var english: String
    var persian: String
    var added: Date
    var seeded: Bool

    init(term: String, category: TermCategory, english: String = "", persian: String = "", seeded: Bool = false) {
        self.term = term
        self.categoryRaw = category.rawValue
        self.english = english
        self.persian = persian
        self.added = Date()
        self.seeded = seeded
    }

    var category: TermCategory {
        get { TermCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    var asTerm: CustomTerm {
        CustomTerm(term: term, category: category, english: english.isEmpty ? nil : english, persian: persian.isEmpty ? nil : persian)
    }
}

/// Learning activity log for the dashboard and streak.
@Model
final class PracticeEvent {
    var date: Date
    var kindRaw: String
    var count: Int
    var seconds: Double
    var meetingID: UUID?

    init(kind: PracticeKind, count: Int = 1, seconds: Double = 0, meetingID: UUID? = nil) {
        self.date = Date()
        self.kindRaw = kind.rawValue
        self.count = count
        self.seconds = seconds
        self.meetingID = meetingID
    }

    var kind: PracticeKind { PracticeKind(rawValue: kindRaw) ?? .listening }
}

enum PracticeKind: String {
    case listening, sentencePractice, shadowing, recording, review, reviewWrong, wordSaved, redemittelSaved
}

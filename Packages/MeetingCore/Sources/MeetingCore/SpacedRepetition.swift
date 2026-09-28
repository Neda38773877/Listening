import Foundation

public enum ReviewGrade: Int, Codable, Sendable, CaseIterable {
    case again = 0, hard = 1, good = 2, easy = 3

    public var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// Scheduling state of one vocabulary item (SM-2 family, with a learning phase).
public struct SRSState: Codable, Hashable, Sendable {
    public var ease: Double = 2.5
    /// Days until next review once the item has graduated.
    public var intervalDays: Double = 0
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var due: Date
    public var lastReviewed: Date?

    public init(due: Date = Date()) { self.due = due }

    public var isNew: Bool { lastReviewed == nil }
    /// Mastered: survived several spaced reviews and currently at a long interval.
    public var isMastered: Bool { repetitions >= 4 && intervalDays >= 21 }
}

public enum SpacedRepetition {

    /// Minutes for the learning steps (again / hard within the same session).
    static let againMinutes = 1.0
    static let hardMinutes = 8.0

    public static func review(_ s: SRSState, grade: ReviewGrade, now: Date = Date()) -> SRSState {
        var n = s
        n.lastReviewed = now
        switch grade {
        case .again:
            n.lapses += s.repetitions > 0 ? 1 : 0
            n.repetitions = 0
            n.intervalDays = 0
            n.ease = max(1.3, s.ease - 0.2)
            n.due = now.addingTimeInterval(againMinutes * 60)
        case .hard:
            n.ease = max(1.3, s.ease - 0.15)
            if s.repetitions == 0 {
                n.due = now.addingTimeInterval(hardMinutes * 60)
            } else {
                n.intervalDays = max(1, s.intervalDays * 1.2)
                n.due = now.addingTimeInterval(n.intervalDays * 86_400)
            }
        case .good, .easy:
            n.repetitions = s.repetitions + 1
            if grade == .easy { n.ease = s.ease + 0.15 }
            switch n.repetitions {
            case 1: n.intervalDays = grade == .easy ? 3 : 1
            case 2: n.intervalDays = grade == .easy ? 7 : 3
            default: n.intervalDays = max(s.intervalDays + 1, s.intervalDays * n.ease * (grade == .easy ? 1.3 : 1))
            }
            n.due = now.addingTimeInterval(n.intervalDays * 86_400)
        }
        return n
    }
}

/// Inputs for ranking what to review first.
public struct PriorityInput: Sendable {
    public var state: SRSState
    /// How often the word occurs across all processed meetings.
    public var meetingFrequency: Int
    /// Number of different meetings it occurred in.
    public var meetingCount: Int
    public var savedManually: Bool
    /// Category weight: workplace categories rank above everyday German.
    public var categoryWeight: Double

    public init(state: SRSState, meetingFrequency: Int, meetingCount: Int, savedManually: Bool, categoryWeight: Double) {
        self.state = state
        self.meetingFrequency = meetingFrequency
        self.meetingCount = meetingCount
        self.savedManually = savedManually
        self.categoryWeight = categoryWeight
    }
}

public enum ReviewPriority {
    /// Higher = review sooner. Overdue items first; among them the ones that are
    /// frequent in your meetings, often missed, and saved by you.
    public static func score(_ p: PriorityInput, now: Date = Date()) -> Double {
        let overdueDays = now.timeIntervalSince(p.state.due) / 86_400
        var s = 0.0
        s += overdueDays >= 0 ? 10 + min(overdueDays, 30) : -100 + overdueDays // not yet due sinks
        s += log2(Double(p.meetingFrequency) + 1) * 2
        s += Double(min(p.meetingCount, 5)) * 1.5
        s += Double(min(p.state.lapses, 5)) * 3
        s += p.savedManually ? 3 : 0
        s += p.categoryWeight * 4
        return s
    }

    /// Builds today's queue: due items by priority, plus a limited number of new ones.
    public static func queue<ID>(_ items: [(id: ID, input: PriorityInput)], newLimit: Int = 15, now: Date = Date()) -> [ID] {
        let due = items.filter { !$0.input.state.isNew && $0.input.state.due <= now }
            .sorted { score($0.input, now: now) > score($1.input, now: now) }
        let fresh = items.filter { $0.input.state.isNew }
            .sorted { score($0.input, now: now) > score($1.input, now: now) }
            .prefix(newLimit)
        return due.map(\.id) + fresh.map(\.id)
    }
}

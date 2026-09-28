import Foundation

/// The steps of one shadowing round for a sentence:
/// listen → your turn (pause) → listen again → (optional) record → compare.
public enum ShadowingPhase: Equatable, Sendable {
    case idle
    case listening(pass: Int)
    /// Silent gap in which the learner repeats aloud.
    case repeating(seconds: Double)
    case recording
    case comparing
    case finished
}

public struct ShadowingSettings: Codable, Hashable, Sendable {
    /// How many times the original is played before the learner's turn.
    public var listenPasses: Int = 1
    /// Pause length = sentence duration × factor + extra.
    public var pauseFactor: Double = 1.3
    public var pauseExtra: Double = 1.0
    /// Play the original a second time after the pause.
    public var replayAfterPause: Bool = true
    /// Record the learner after the second listen.
    public var recordAfter: Bool = false
    /// Continue with the next sentence automatically.
    public var autoAdvance: Bool = false

    public init() {}

    public func pause(for sentenceDuration: Double, rate: Double) -> Double {
        let d = sentenceDuration / max(rate, 0.1)
        return min(30, d * pauseFactor + pauseExtra)
    }
}

/// Pure state machine; the app drives audio/recording and reports events.
public struct ShadowingMachine: Sendable {
    public private(set) var phase: ShadowingPhase = .idle
    public var settings: ShadowingSettings
    public var sentenceDuration: Double
    public var rate: Double
    private var passesDone = 0
    private var replayed = false

    public init(settings: ShadowingSettings, sentenceDuration: Double, rate: Double = 1) {
        self.settings = settings
        self.sentenceDuration = sentenceDuration
        self.rate = rate
    }

    public mutating func start() {
        passesDone = 0
        replayed = false
        phase = .listening(pass: 1)
    }

    /// The original finished playing.
    public mutating func playbackEnded() {
        guard case .listening = phase else { return }
        passesDone += 1
        if replayed {
            phase = settings.recordAfter ? .recording : .finished
        } else if passesDone < max(1, settings.listenPasses) {
            phase = .listening(pass: passesDone + 1)
        } else {
            phase = .repeating(seconds: settings.pause(for: sentenceDuration, rate: rate))
        }
    }

    /// The learner's pause is over.
    public mutating func pauseEnded() {
        guard case .repeating = phase else { return }
        if settings.replayAfterPause {
            replayed = true
            phase = .listening(pass: passesDone + 1)
        } else {
            phase = settings.recordAfter ? .recording : .finished
        }
    }

    public mutating func recordingEnded() {
        guard phase == .recording else { return }
        phase = .comparing
    }

    public mutating func comparisonDone() {
        guard phase == .comparing else { return }
        phase = .finished
    }

    public mutating func stop() { phase = .idle }
}

import XCTest
@testable import MeetingCore

func makeDocument(_ transcript: String, heard: String? = nil, step: Double = 0.4) -> MeetingDocument {
    var doc = MeetingDocument(title: "Test", originalTranscript: transcript)
    let clean = (heard ?? transcript)
    doc.recognized = recognized(clean, step: step)
    doc.duration = (doc.recognized.last?.end ?? 0) + 1
    MeetingBuilder.rebuild(&doc)
    return doc
}

final class SegmentationTests: XCTestCase {

    func testSplitsOnPunctuationButNotAbbreviations() {
        let doc = makeDocument("Wir prüfen z.B. die Kalibrierung. Das Problem ist, dass der Flasher am 3. Oktober ausfällt! Passt das?")
        let texts = doc.sentences.map { doc.text(of: $0) }
        XCTAssertEqual(texts, [
            "Wir prüfen z.B. die Kalibrierung.",
            "Das Problem ist, dass der Flasher am 3. Oktober ausfällt!",
            "Passt das?",
        ])
    }

    func testUnpunctuatedTextSplitsOnRealPauses() {
        var tokens: [Token] = []
        let words = ["wir", "müssen", "das", "prüfen", "und", "dann", "schauen", "wir", "weiter"]
        var t = 0.0
        for (i, w) in words.enumerated() {
            if i == 4 { t += 1.2 } // long pause before "und"
            tokens.append(Token(id: i, original: w, timing: WordTiming(start: t, end: t + 0.3, source: .aligned, confidence: 0.9)))
            t += 0.35
        }
        let s = SentenceSegmenter.segment(tokens)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].tokenRange, 0..<4)
    }

    func testVeryLongSentenceIsSplit() {
        let long = (0..<60).map { $0 == 30 ? "Wort\($0)," : "Wort\($0)" }.joined(separator: " ") + "."
        let doc = makeDocument(long)
        XCTAssertGreaterThan(doc.sentences.count, 1)
        for s in doc.sentences { XCTAssertLessThanOrEqual(s.tokenRange.count, 28) }
        // Nothing lost.
        XCTAssertEqual(doc.sentences.map(\.tokenRange.count).reduce(0, +), 60)
    }

    func testSentenceTimeRangeAndLookup() {
        let doc = makeDocument("Guten Morgen. Wir fangen an.")
        let r = try! XCTUnwrap(doc.timeRange(of: doc.sentences[1]))
        XCTAssertEqual(r.lowerBound, 0.8, accuracy: 0.001)
        XCTAssertEqual(doc.sentenceIndex(at: 1.0), 1)
        XCTAssertEqual(doc.sentenceIndex(containingToken: 3), 1)
    }
}

final class CorrectionActionTests: XCTestCase {

    func testAcceptEditRejectAreTraceable() {
        var doc = makeDocument("Die Kalibrierungen ist fertig.", heard: "die Kalibrierung ist fertig")
        let c = try! XCTUnwrap(doc.corrections.first)
        doc.accept(correction: c.id)
        XCTAssertEqual(doc.tokens[c.tokenID].display, "Kalibrierung")
        XCTAssertEqual(doc.tokens[c.tokenID].original, "Kalibrierungen")
        XCTAssertEqual(doc.corrections[0].status, .accepted)

        doc.edit(correction: c.id, text: "Kalibrierung (Flasher)")
        XCTAssertEqual(doc.tokens[c.tokenID].display, "Kalibrierung (Flasher)")

        doc.reject(correction: c.id)
        XCTAssertEqual(doc.tokens[c.tokenID].display, "Kalibrierungen")
        XCTAssertEqual(doc.originalTranscript, "Die Kalibrierungen ist fertig.")
    }

    func testFreeEditAndManualTiming() {
        var doc = makeDocument("Das ist gut.")
        doc.editToken(2, text: "super.")
        XCTAssertEqual(doc.text(of: doc.sentences[0]), "Das ist super.")
        XCTAssertEqual(doc.originalText(of: doc.sentences[0]), "Das ist gut.")
        doc.setTiming(2, start: 5, end: 5.4)
        XCTAssertEqual(doc.tokens[2].timing?.source, .manual)
        doc.shiftSentence(0, by: 0.25)
        XCTAssertEqual(doc.tokens[2].timing?.start ?? 0, 5.25, accuracy: 0.0001)
    }

    func testDocumentRoundTripsThroughJSON() throws {
        var doc = makeDocument("Wir müssen das heute noch überprüfen.")
        doc.sentences[0].persian = TranslationText(text: "باید همین امروز بررسی کنیم.", provider: "You",
                                                    createdAt: Date(timeIntervalSinceReferenceDate: 1000))
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(MeetingDocument.self, from: data)
        XCTAssertEqual(back.tokens, doc.tokens)
        XCTAssertEqual(back.sentences, doc.sentences)
        XCTAssertEqual(back.originalTranscript, doc.originalTranscript)
    }
}

final class SpacedRepetitionTests: XCTestCase {

    func testGoodAnswersGrowIntervals() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var s = SRSState(due: now)
        s = SpacedRepetition.review(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 1)
        s = SpacedRepetition.review(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 3)
        s = SpacedRepetition.review(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 7.5, accuracy: 0.001)
        XCTAssertFalse(s.isNew)
    }

    func testAgainResetsAndCountsLapse() {
        let now = Date()
        var s = SRSState(due: now)
        s = SpacedRepetition.review(s, grade: .good, now: now)
        s = SpacedRepetition.review(s, grade: .again, now: now)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertLessThan(s.due.timeIntervalSince(now), 120)
        XCTAssertLessThan(s.ease, 2.5)
    }

    func testPriorityPrefersFrequentMissedWorkWords() {
        let now = Date()
        var missed = SRSState(due: now.addingTimeInterval(-3600)); missed.lapses = 3; missed.lastReviewed = now.addingTimeInterval(-86_400)
        var easy = SRSState(due: now.addingTimeInterval(-3600)); easy.lastReviewed = now.addingTimeInterval(-86_400)
        let notDue: SRSState = { var s = SRSState(due: now.addingTimeInterval(86_400 * 5)); s.lastReviewed = now; return s }()
        let q = ReviewPriority.queue([
            (id: "easy", input: PriorityInput(state: easy, meetingFrequency: 1, meetingCount: 1, savedManually: false, categoryWeight: 0.2)),
            (id: "missed", input: PriorityInput(state: missed, meetingFrequency: 12, meetingCount: 4, savedManually: true, categoryWeight: 1)),
            (id: "later", input: PriorityInput(state: notDue, meetingFrequency: 50, meetingCount: 5, savedManually: true, categoryWeight: 1)),
            (id: "new", input: PriorityInput(state: SRSState(due: now), meetingFrequency: 2, meetingCount: 1, savedManually: true, categoryWeight: 1)),
        ], now: now)
        XCTAssertEqual(q, ["missed", "easy", "new"])
    }
}

final class RedemittelTests: XCTestCase {

    func testFindsOnlyExpressionsThatOccur() {
        let hits = RedemittelCatalog.find(in: [
            "Das Problem ist, dass der Flasher nicht kalibriert ist.",
            "Kannst du bitte die Messwerte schicken?",
            "Ich würde vorschlagen, dass wir morgen anfangen.",
            "Heute ist schönes Wetter.",
        ])
        XCTAssertTrue(hits.contains { $0.category == .introducingProblem && $0.sentenceIndex == 0 && $0.matchedText.lowercased() == "das problem ist" })
        XCTAssertTrue(hits.contains { $0.category == .request && $0.sentenceIndex == 1 })
        XCTAssertTrue(hits.contains { $0.category == .suggestion && $0.sentenceIndex == 2 })
        XCTAssertFalse(hits.contains { $0.sentenceIndex == 3 })
        // Matched text is copied verbatim from the sentence.
        for h in hits {
            let s = ["Das Problem ist, dass der Flasher nicht kalibriert ist.", "Kannst du bitte die Messwerte schicken?",
                     "Ich würde vorschlagen, dass wir morgen anfangen."][h.sentenceIndex]
            XCTAssertTrue(s.contains(h.matchedText))
        }
    }

    func testAllPatternsCompileAndEveryCategoryHasRecommendations() {
        for p in RedemittelCatalog.patterns {
            XCTAssertNoThrow(try NSRegularExpression(pattern: p.regex, options: [.caseInsensitive]), p.pattern)
        }
        for c in RedemittelCategory.allCases {
            XCTAssertFalse(RedemittelCatalog.recommended[c, default: []].isEmpty, c.title)
            XCTAssertTrue(RedemittelCatalog.patterns.contains { $0.category == c }, c.title)
        }
    }
}

final class AnalysisTests: XCTestCase {

    func testHeardWordsGroupInflectionsAndSkipFunctionWords() {
        let doc = makeDocument("Die Kalibrierung ist wichtig. Zwei Kalibrierungen fehlen. Die Kalibrierung prüfen wir.")
        let words = VocabularyAnalyzer.heardWords(doc.tokens)
        XCTAssertEqual(words.first?.form, "Kalibrierung")
        XCTAssertEqual(words.first?.count, 3)
        XCTAssertFalse(words.contains { $0.form.lowercased() == "die" })
        XCTAssertTrue(VocabularyAnalyzer.occurs("Kalibrierung", in: doc.tokens))
        XCTAssertFalse(VocabularyAnalyzer.occurs("Laminator", in: doc.tokens))
    }

    func testSearchFindsInflectedWordsAndTranslations() {
        var doc = makeDocument("Die Kalibrierungen sind fertig. Wir messen morgen.")
        doc.sentences[1].english = TranslationText(text: "We measure tomorrow.", provider: "test")
        let hits = MeetingSearch.search("Kalibrierung", in: doc)
        XCTAssertEqual(hits.first?.kind, .word)
        XCTAssertEqual(hits.first?.tokenIndex, 1)
        XCTAssertNotNil(hits.first?.time)
        XCTAssertEqual(MeetingSearch.search("tomorrow", in: doc).first?.kind, .translation)
    }

    func testSummaryValidatorDropsUnsupportedClaims() {
        let s = MeetingSummary(sections: [
            SummarySection(topic: "Kalibrierung",
                           actions: [EvidencedItem(text: "Flasher neu kalibrieren", evidence: [0]),
                                     EvidencedItem(text: "Invented action", evidence: [])],
                           responsible: [EvidencedItem(text: "Carlos", evidence: [0]),
                                         EvidencedItem(text: "Bernhard", evidence: [0])],
                           deadlines: [EvidencedItem(text: "Freitag", evidence: [99])]),
        ], provider: "test")
        let v = SummaryValidator.validate(s, sentenceCount: 2, transcript: "Carlos kalibriert den Flasher neu.")
        XCTAssertEqual(v.sections[0].actions.map(\.text), ["Flasher neu kalibrieren"])
        XCTAssertEqual(v.sections[0].responsible.map(\.text), ["Carlos"])
        XCTAssertTrue(v.sections[0].deadlines.isEmpty)
        XCTAssertEqual(v.droppedUnsupportedItems, 3)
    }

    func testAutomaticTopicsCoverWholeMeeting() {
        let sentence = "Wir besprechen die Kalibrierung vom Flasher heute ausführlich."
        let text = Array(repeating: sentence, count: 120).joined(separator: " ")
        let doc = makeDocument(text, step: 0.5) // ~ 8 words × 0.5 s × 120 = 8 minutes
        let topics = doc.topics
        XCTAssertFalse(topics.isEmpty)
        XCTAssertEqual(topics.first?.firstSentence, 0)
        XCTAssertEqual(topics.last?.lastSentence, doc.sentences.count - 1)
        XCTAssertTrue(topics.allSatisfy { $0.provenance == .automatic })
    }
}

final class ShadowingTests: XCTestCase {

    func testFullRound() {
        var s = ShadowingSettings(); s.recordAfter = true
        var m = ShadowingMachine(settings: s, sentenceDuration: 2, rate: 1)
        m.start()
        XCTAssertEqual(m.phase, .listening(pass: 1))
        m.playbackEnded()
        guard case .repeating(let secs) = m.phase else { return XCTFail("expected pause") }
        XCTAssertEqual(secs, 2 * 1.3 + 1, accuracy: 0.001)
        m.pauseEnded()
        XCTAssertEqual(m.phase, .listening(pass: 2))
        m.playbackEnded()
        XCTAssertEqual(m.phase, .recording)
        m.recordingEnded()
        XCTAssertEqual(m.phase, .comparing)
        m.comparisonDone()
        XCTAssertEqual(m.phase, .finished)
    }

    func testSlowerRateGivesLongerPause() {
        let s = ShadowingSettings()
        XCTAssertGreaterThan(s.pause(for: 2, rate: 0.5), s.pause(for: 2, rate: 1))
    }
}

import XCTest
@testable import MeetingCore

/// Helpers to fake recognizer output: one word every `step` seconds.
func recognized(_ text: String, from start: Double = 0, step: Double = 0.4, confidence: Double = 0.9) -> [RecognizedWord] {
    GermanText.words(text).enumerated().map { i, w in
        RecognizedWord(text: w, start: start + Double(i) * step, end: start + Double(i) * step + step * 0.8, confidence: confidence)
    }
}

final class WordAlignerTests: XCTestCase {

    func testIdenticalSequencesAlignOneToOne() {
        let words = GermanText.words("Wir müssen das heute noch überprüfen.")
        let r = WordAligner.align(transcript: words, recognized: words)
        XCTAssertEqual(r.links.map { $0?.recognizedIndex }, Array(0..<words.count))
        XCTAssertTrue(r.links.allSatisfy { $0?.kind == .exact })
        XCTAssertTrue(r.unmatchedRecognized.isEmpty)
    }

    func testInflectionIsSimilarNotExact() {
        let r = WordAligner.align(transcript: GermanText.words("Die Kalibrierungen sind fertig"),
                                  recognized: GermanText.words("die Kalibrierung sind fertig"))
        XCTAssertEqual(r.links[1]?.recognizedIndex, 1)
        XCTAssertEqual(r.links[1]?.kind, .similar)
        XCTAssertEqual(r.links[0]?.kind, .exact) // case-insensitive
    }

    func testMissingAndExtraWords() {
        // Transcript misses "noch"; recognizer misses "bitte".
        let t = GermanText.words("Kannst du bitte das heute überprüfen")
        let h = GermanText.words("Kannst du das heute noch überprüfen")
        let r = WordAligner.align(transcript: t, recognized: h)
        XCTAssertNil(r.links[2]) // "bitte" has no audio counterpart
        XCTAssertEqual(r.links[5]?.recognizedIndex, 5) // "überprüfen"
        XCTAssertEqual(r.unmatchedRecognized, [4]) // "noch"
    }

    func testLongMeetingUsesAnchorsAndStaysMonotonic() {
        // ~12 000 words: a full matrix would be 144M cells.
        var t: [String] = [], h: [String] = []
        let vocab = ["Kalibrierung", "Flasher", "Modul", "Laminator", "Messung", "Qualität", "Produktion", "Linie",
                     "prüfen", "morgen", "Schicht", "Ausschuss", "Reklamation", "Ursache", "Maßnahme"]
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for i in 0..<12_000 {
            let w = vocab[rnd(vocab.count)] + (i % 7 == 0 ? "\(i)" : "")
            t.append(w)
            if rnd(50) == 0 { continue }              // recognizer drops a word
            h.append(rnd(40) == 0 ? "Fehlwort" : w)   // or mishears it
        }
        let start = Date()
        let r = WordAligner.align(transcript: t, recognized: h)
        XCTAssertLessThan(Date().timeIntervalSince(start), 60)
        let pairs = r.links.enumerated().compactMap { i, l in l.map { (i, $0.recognizedIndex) } }
        XCTAssertGreaterThan(Double(pairs.count) / Double(t.count), 0.9)
        for k in 1..<pairs.count {
            XCTAssertLessThan(pairs[k - 1].1, pairs[k].1, "alignment must be monotonic")
        }
    }

    func testUnrelatedTextStaysUnaligned() {
        let t = (0..<900).map { "alpha\($0)" }
        let h = (0..<900).map { "omega\($0)" }
        let r = WordAligner.align(transcript: t, recognized: h)
        // No shared evidence: nothing is linked as exact or similar.
        XCTAssertFalse(r.links.contains { $0?.kind == .exact || $0?.kind == .similar })
    }
}

final class MeetingAssemblerTests: XCTestCase {

    func testTimingComesFromRecognizedWords() {
        let heard = recognized("Wir müssen das heute noch überprüfen", from: 801.12)
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Wir müssen das heute noch überprüfen."),
                                            recognized: heard)
        XCTAssertEqual(out.tokens.count, 6)
        for (t, h) in zip(out.tokens, heard) {
            XCTAssertEqual(t.timing?.start, h.start)
            XCTAssertEqual(t.timing?.end, h.end)
            XCTAssertEqual(t.timing?.source, .aligned)
        }
        XCTAssertEqual(out.tokens.last?.original, "überprüfen.")
        XCTAssertTrue(out.corrections.isEmpty)
    }

    func testCorrectionSuggestionKeepsOriginal() {
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Die Kalibrierungen ist fertig."),
                                            recognized: recognized("die Kalibrierung ist fertig", confidence: 0.95))
        let c = try! XCTUnwrap(out.corrections.first)
        XCTAssertEqual(c.original, "Kalibrierungen")
        XCTAssertEqual(c.suggested, "Kalibrierung")
        XCTAssertEqual(c.confidence, .high)
        XCTAssertEqual(c.status, .pending)
        // The token itself is untouched until the user accepts.
        XCTAssertEqual(out.tokens[1].display, "Kalibrierungen")
    }

    func testUnclearAudioSuggestsUnclearMarker() {
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Der Flasher steht heute."),
                                            recognized: [
                                                RecognizedWord(text: "Der", start: 0, end: 0.3, confidence: 0.9),
                                                RecognizedWord(text: "Wascher", start: 0.3, end: 0.8, confidence: 0.2),
                                                RecognizedWord(text: "steht", start: 0.8, end: 1.1, confidence: 0.9),
                                                RecognizedWord(text: "heute", start: 1.1, end: 1.5, confidence: 0.9),
                                            ])
        let c = out.corrections.first { $0.tokenID == 1 }
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.confidence, .low)
    }

    func testDictionaryProtectsKnownTerms() {
        let dict = CustomDictionary(terms: [CustomTerm(term: "OMO", category: .abbreviation)])
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Das OMO ist frei."),
                                            recognized: recognized("das Oma ist frei", confidence: 0.95), dictionary: dict)
        let c = out.corrections.first { $0.tokenID == 1 }
        XCTAssertEqual(c?.confidence, .low)
        XCTAssertTrue(c?.reason.contains("custom dictionary") ?? false)
    }

    func testDictionaryTermIsOnlySuggestedWithAudioEvidence() {
        let dict = CustomDictionary(terms: [CustomTerm(term: "Potting", category: .process)])
        // Transcript "Botting", audio "Botting": both sound like the dictionary term → suggestion, never auto-applied.
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Das Botting ist fertig."),
                                            recognized: recognized("das Bottich ist fertig", confidence: 0.9), dictionary: dict)
        XCTAssertEqual(out.tokens[1].display, "Botting")
        // Unrelated words never get the dictionary term.
        let out2 = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Das Wetter ist gut."),
                                             recognized: recognized("das Wetter ist gut"), dictionary: dict)
        XCTAssertTrue(out2.corrections.isEmpty)
    }

    func testMissingWordBecomesPendingInsertion() {
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Wir müssen das heute überprüfen."),
                                            recognized: recognized("wir müssen das heute noch überprüfen", confidence: 0.95))
        let ins = try! XCTUnwrap(out.corrections.first { $0.kind == .insert })
        XCTAssertEqual(ins.suggested, "noch")
        XCTAssertTrue(out.tokens[ins.tokenID].isInsertion)
        XCTAssertEqual(out.tokens[ins.tokenID].display, "") // hidden until accepted
    }

    func testUnmatchedWordGetsApproximateTimingAndReviewFlag() {
        let out = MeetingAssembler.assemble(parsed: TranscriptParser.parse("Kannst du bitte das prüfen?"),
                                            recognized: [
                                                RecognizedWord(text: "Kannst", start: 0, end: 0.3, confidence: 0.9),
                                                RecognizedWord(text: "du", start: 0.3, end: 0.5, confidence: 0.9),
                                                RecognizedWord(text: "das", start: 1.0, end: 1.2, confidence: 0.9),
                                                RecognizedWord(text: "prüfen", start: 1.2, end: 1.7, confidence: 0.9),
                                            ])
        let bitte = out.tokens[2]
        XCTAssertEqual(bitte.original, "bitte")
        XCTAssertTrue(bitte.needsReview)
        XCTAssertEqual(bitte.timing?.source, .between)
        XCTAssertEqual(bitte.timing?.start, 0.5)
        XCTAssertEqual(bitte.timing?.end, 1.0)
    }

    func testRecognitionOnlyMarksUnsureWords() {
        let out = MeetingAssembler.assemble(parsed: [], recognized: [
            RecognizedWord(text: "Guten", start: 0, end: 0.3, confidence: 0.9),
            RecognizedWord(text: "Morgen", start: 0.3, end: 0.6, confidence: 0.2),
        ])
        XCTAssertEqual(out.tokens.count, 2)
        XCTAssertEqual(out.corrections.first?.suggested, Correction.unclearMarker)
    }
}

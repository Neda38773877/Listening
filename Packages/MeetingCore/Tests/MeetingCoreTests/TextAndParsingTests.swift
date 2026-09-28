import XCTest
@testable import MeetingCore

final class GermanTextTests: XCTestCase {

    func testNormalizeAndStrip() {
        XCTAssertEqual(GermanText.normalize("Überprüfen,"), "überprüfen")
        XCTAssertEqual(GermanText.stripPunctuation("„Kalibrierung“."), "Kalibrierung")
        XCTAssertEqual(GermanText.stripPunctuation("z.B."), "z.B")
        XCTAssertEqual(GermanText.stripPunctuation("PV-Modul,"), "PV-Modul")
        XCTAssertEqual(GermanText.searchKey("Prüfung"), "pruefung")
    }

    func testSimilarity() {
        XCTAssertEqual(GermanText.levenshtein("kitten", "sitting"), 3)
        XCTAssertTrue(GermanText.soundsAlike("Kalibrierung", "Kalibrierungen"))
        XCTAssertTrue(GermanText.soundsAlike("Potting", "Botting"))
        XCTAssertFalse(GermanText.soundsAlike("heute", "Kalibrierung"))
        XCTAssertFalse(GermanText.soundsAlike("in", "im")) // too short to judge
    }

    func testColognePhonetic() {
        // Reference values of the Kölner Phonetik.
        XCTAssertEqual(GermanText.colognePhonetic("Müller-Lüdenscheidt"), "65752682")
        XCTAssertEqual(GermanText.colognePhonetic("Wikipedia"), "3412")
        XCTAssertEqual(GermanText.colognePhonetic("Potting"), GermanText.colognePhonetic("Botting"))
    }
}

final class TranscriptParserTests: XCTestCase {

    func testPlainTextWithLeadingTimestamps() {
        let raw = """
        00:00 Guten Morgen zusammen.
        00:04 Wir müssen das heute noch überprüfen.
        """
        let words = TranscriptParser.parse(raw).map(\.text)
        XCTAssertEqual(words, ["Guten", "Morgen", "zusammen.", "Wir", "müssen", "das", "heute", "noch", "überprüfen."])
    }

    func testSpokenTimeInsideSentenceIsKept() {
        let words = TranscriptParser.parse("Wir treffen uns um 14:30 Uhr.").map(\.text)
        XCTAssertEqual(words, ["Wir", "treffen", "uns", "um", "14:30", "Uhr."])
    }

    func testSRT() {
        let raw = """
        1
        00:00:01,000 --> 00:00:03,000
        Das Problem ist,

        2
        00:00:03,000 --> 00:00:05,500
        dass der Flasher spinnt.
        """
        let words = TranscriptParser.parse(raw)
        XCTAssertEqual(words.map(\.text), ["Das", "Problem", "ist,", "dass", "der", "Flasher", "spinnt."])
        XCTAssertTrue(words[0].startsBlock)
        XCTAssertTrue(words[3].startsBlock)
    }

    func testSpeakerLabels() {
        let raw = """
        Sprecher 1: Guten Morgen.
        Carlos: Morgen!
        Carlos: Wie weit sind wir?
        Carlos: Gut.
        Wichtig: das bleibt drin.
        """
        let words = TranscriptParser.parse(raw)
        XCTAssertEqual(words.first?.speaker, "Sprecher 1")
        XCTAssertEqual(words.first?.text, "Guten")
        XCTAssertTrue(words.contains { $0.text == "Morgen!" && $0.speaker == "Carlos" })
        // "Wichtig:" appears once only — it is a spoken word, not a speaker.
        XCTAssertTrue(words.contains { $0.text == "Wichtig:" })
    }

    func testMarkdownIsStripped() {
        let words = TranscriptParser.parse("## Meeting\n- **Kalibrierung** prüfen").map(\.text)
        XCTAssertEqual(words, ["Meeting", "Kalibrierung", "prüfen"])
    }
}

final class TimeFormatTests: XCTestCase {
    func testFormatAndParse() {
        XCTAssertEqual(TimeFormat.precise(801.12), "00:13:21.120")
        XCTAssertEqual(TimeFormat.short(270), "04:30")
        XCTAssertEqual(TimeFormat.short(3870), "1:04:30")
        XCTAssertEqual(TimeFormat.parse("13:21.12")!, 801.12, accuracy: 0.0001)
        XCTAssertEqual(TimeFormat.parse("00:13:21,120")!, 801.12, accuracy: 0.0001)
        XCTAssertNil(TimeFormat.parse("abc"))
    }

    func testWordClipHasPreRollAndIsClamped() {
        let c = PlaybackPlanner.clip(for: WordTiming(start: 10, end: 10.3, source: .aligned, confidence: 1), duration: 100)
        XCTAssertLessThan(c.start, 10)
        XCTAssertGreaterThanOrEqual(10 - c.start, 0.1)
        XCTAssertLessThanOrEqual(10 - c.start, 0.3)
        XCTAssertGreaterThan(c.end, 10.3)
        let edge = PlaybackPlanner.clip(for: WordTiming(start: 0.05, end: 0.1, source: .aligned, confidence: 1), duration: 100)
        XCTAssertEqual(edge.start, 0)
    }
}

import Foundation
import Combine
import SwiftData
import MeetingCore

/// Meaning of a word as shown on the word card, with its source.
struct WordMeaning: Equatable {
    var lemma: String?
    var partOfSpeech: String?
    var english: String?
    var persian: String?
    var synonyms: [String] = []
    var note: String?
    var source: String
    var certain: Bool = true
}

enum InspectorItem: Equatable {
    case word(Int)
    case sentence(Int)
}

/// State of one open meeting: the document, playback, selection and lookups.
@MainActor
final class MeetingSession: ObservableObject {
    @Published var doc: MeetingDocument
    @Published var inspector: InspectorItem?
    @Published private(set) var playingSentence: Int?
    @Published private(set) var playingToken: Int?
    @Published var followPlayback = true
    @Published var meanings: [String: WordMeaning] = [:]
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    /// Sentence to repeat in a loop (nil = no loop).
    @Published var loopSentence: Int?

    let player = AudioPlayer()
    let recorder = VoiceRecorder()
    let store = MeetingStore.shared
    let record: MeetingRecord
    private var context: ModelContext?
    private var cancellables: Set<AnyCancellable> = []
    private var saveTask: Task<Void, Never>?
    private var glossary: [String: CustomTermRecord] = [:]

    init(doc: MeetingDocument, record: MeetingRecord) {
        self.doc = doc
        self.record = record
        player.rate = AppSettings.shared.playbackRate
        if let url = store.audioURL(for: doc) { player.load(url, duration: doc.duration) }
        player.$currentTime
            .removeDuplicates()
            .sink { [weak self] t in self?.updatePlaying(t) }
            .store(in: &cancellables)
        player.onClipFinished = { [weak self] in self?.clipFinished() }
    }

    func attach(_ context: ModelContext) {
        self.context = context
        let terms = (try? context.fetch(FetchDescriptor<CustomTermRecord>())) ?? []
        glossary = Dictionary(terms.map { (GermanText.normalize($0.term), $0) }, uniquingKeysWith: { a, _ in a })
        if record.lastPosition > 0 { player.seek(to: record.lastPosition) }
        record.lastOpened = Date()
    }

    func close() {
        logListening()
        record.lastPosition = player.currentTime
        player.unload()
        saveNow()
    }

    // MARK: - Persistence

    func changed() {
        objectWillChange.send()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do { try store.save(doc) } catch { errorMessage = "Could not save: \(error.localizedDescription)" }
        record.pendingCorrections = doc.pendingCorrections.count
        record.sentenceCount = doc.sentences.count
        record.alignedRatio = doc.alignedWordRatio
        try? context?.save()
    }

    // MARK: - Playback

    var hasAudio: Bool { player.url != nil }

    private func updatePlaying(_ t: Double) {
        guard player.isPlaying || player.activeClip != nil else { return }
        let s = doc.sentenceIndex(at: t)
        if s != playingSentence { playingSentence = s }
        let tok = s.flatMap { doc.tokenIndex(at: t, within: doc.sentences[$0]) }
        if tok != playingToken { playingToken = tok }
    }

    func playWord(_ tokenIndex: Int) {
        guard doc.tokens.indices.contains(tokenIndex), let timing = doc.tokens[tokenIndex].timing else { return }
        loopSentence = nil
        player.play(PlaybackPlanner.clip(for: timing, duration: player.duration))
    }

    func clip(forSentence i: Int) -> Clip? {
        guard doc.sentences.indices.contains(i), let r = doc.timeRange(of: doc.sentences[i]) else { return nil }
        return PlaybackPlanner.clip(for: r, duration: player.duration)
    }

    func playSentence(_ i: Int, rate: Double? = nil) {
        guard let c = clip(forSentence: i) else { return }
        playingSentence = i
        player.play(c, rate: rate)
        log(.sentencePractice)
    }

    func togglePlay() {
        if player.isPlaying { player.pause(); logListening() } else { loopSentence = nil; player.play() }
    }

    func step(_ delta: Int) {
        let base = playingSentence ?? currentSentenceIndex ?? 0
        let next = min(max(0, base + delta), max(0, doc.sentences.count - 1))
        select(.sentence(next))
        playSentence(next)
    }

    var currentSentenceIndex: Int? {
        if case .sentence(let i) = inspector { return i }
        if case .word(let t) = inspector { return doc.sentenceIndex(containingToken: t) }
        return playingSentence
    }

    func jump(toSentence i: Int) {
        guard let r = doc.sentences.indices.contains(i) ? doc.timeRange(of: doc.sentences[i]) : nil else { return }
        playingSentence = i
        player.seek(to: max(0, r.lowerBound - 0.1), thenPlay: true)
    }

    private func clipFinished() {
        logListening()
        if let i = loopSentence, let c = clip(forSentence: i) {
            player.play(c)
        }
    }

    func setRate(_ r: Double) {
        player.rate = r
        AppSettings.shared.playbackRate = r
    }

    // MARK: - Selection

    func select(_ item: InspectorItem?) {
        inspector = item
        if case .word(let t) = item { lookUp(tokenIndex: t) }
    }

    func tapWord(_ tokenIndex: Int) {
        select(.word(tokenIndex))
        playWord(tokenIndex)
    }

    // MARK: - Word meanings (offline first)

    func meaningKey(_ tokenIndex: Int) -> String { VocabularyAnalyzer.groupKey(doc.tokens[tokenIndex].word) }

    private func lookUp(tokenIndex: Int) {
        let key = meaningKey(tokenIndex)
        if meanings[key] != nil { return }
        let word = doc.tokens[tokenIndex].word
        if let saved = savedVocab(for: word), !(saved.english.isEmpty && saved.persian.isEmpty) {
            meanings[key] = WordMeaning(lemma: saved.german, partOfSpeech: saved.partOfSpeech.isEmpty ? nil : saved.partOfSpeech,
                                        english: saved.english.isEmpty ? nil : saved.english,
                                        persian: saved.persian.isEmpty ? nil : saved.persian,
                                        synonyms: saved.synonyms, source: saved.meaningSource.isEmpty ? "Your word list" : saved.meaningSource)
            return
        }
        if let g = glossaryEntry(for: word) {
            meanings[key] = WordMeaning(lemma: g.term, english: g.english.isEmpty ? nil : g.english,
                                        persian: g.persian.isEmpty ? nil : g.persian,
                                        source: g.seeded ? "Your glossary" : "Your custom dictionary")
        }
    }

    func glossaryEntry(for word: String) -> CustomTermRecord? {
        let k = GermanText.normalize(word)
        if let g = glossary[k] { return g }
        for suffix in ["en", "n", "e", "s", "es", "er", "ern", "t", "st"] where k.count > suffix.count + 3 && k.hasSuffix(suffix) {
            if let g = glossary[String(k.dropLast(suffix.count))] { return g }
        }
        return nil
    }

    func savedVocab(for word: String) -> VocabItem? {
        let key = VocabularyAnalyzer.groupKey(word)
        let d = FetchDescriptor<VocabItem>(predicate: #Predicate { $0.key == key })
        return try? context?.fetch(d).first
    }

    /// External, user-initiated explanation of a word.
    func explainWithAI(tokenIndex: Int) async {
        guard let s = doc.sentenceIndex(containingToken: tokenIndex) else { return }
        do {
            let ai = try ClaudeService.make(for: doc.id)
            busyMessage = "Asking Claude…"
            defer { busyMessage = nil }
            let info = try await ai.explain(word: doc.tokens[tokenIndex].word, sentence: doc.text(of: doc.sentences[s]))
            meanings[meaningKey(tokenIndex)] = WordMeaning(lemma: info.lemma, partOfSpeech: info.partOfSpeech, english: info.english,
                                                          persian: info.persian, synonyms: info.synonyms,
                                                          note: info.note.isEmpty ? nil : info.note,
                                                          source: ClaudeService.providerName, certain: info.certain)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Translation on demand

    func translateSentence(_ i: Int, external: Bool) async {
        guard doc.sentences.indices.contains(i) else { return }
        await translate(sentences: [i], external: external)
    }

    /// Translates sentences missing a translation. On-device first; the external AI only when asked.
    func translate(sentences ids: [Int], external: Bool) async {
        let items = ids.map { (id: $0, text: doc.text(of: doc.sentences[$0])) }
        if external {
            do {
                let ai = try ClaudeService.make(for: doc.id)
                let terms = glossary.values.filter { !$0.seeded || !$0.persian.isEmpty }.prefix(80).map(\.asTerm)
                for start in stride(from: 0, to: items.count, by: 30) {
                    busyMessage = "Translating with Claude… \(start)/\(items.count)"
                    let batch = Array(items[start..<min(start + 30, items.count)]).map { (id: $0.id, german: $0.text) }
                    let result = try await ai.translate(batch, glossary: Array(terms))
                    for r in result where doc.sentences.indices.contains(r.id) {
                        let provider = ClaudeService.providerName + (r.uncertain ? " · uncertain" : "")
                        doc.sentences[r.id].english = TranslationText(text: r.english, provider: provider)
                        doc.sentences[r.id].persian = TranslationText(text: r.persian, provider: provider)
                    }
                    changed()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
            return
        }
        for lang in ["en", "fa"] {
            guard await OnDeviceTranslator.availability(to: lang) != .unsupported else { continue }
            let missing = items.filter { lang == "en" ? doc.sentences[$0.id].english == nil : doc.sentences[$0.id].persian == nil }
            guard !missing.isEmpty else { continue }
            if let result = try? await OnDeviceTranslator.shared.translate(missing, to: lang) {
                for (id, text) in result where doc.sentences.indices.contains(id) {
                    let t = TranslationText(text: text, provider: OnDeviceTranslator.providerName)
                    if lang == "en" { doc.sentences[id].english = t } else { doc.sentences[id].persian = t }
                }
                changed()
            }
        }
    }

    func setTranslation(_ i: Int, english: String?, persian: String?) {
        if let e = english { doc.sentences[i].english = e.isEmpty ? nil : TranslationText(text: e, provider: "You") }
        if let p = persian { doc.sentences[i].persian = p.isEmpty ? nil : TranslationText(text: p, provider: "You") }
        changed()
    }

    // MARK: - Summary

    func analyzeWithAI() async {
        do {
            let ai = try ClaudeService.make(for: doc.id)
            busyMessage = "Analysing the meeting with Claude…"
            defer { busyMessage = nil }
            let (summary, topics) = try await ai.analyze(doc)
            doc.summary = summary
            if !topics.isEmpty { doc.topics = topics }
            changed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Vocabulary

    /// Saves a word (or expression) with its meeting context and audio position.
    @discardableResult
    func saveWord(tokenIndex: Int, category: String, meaning: WordMeaning?) -> VocabItem? {
        guard let context else { return nil }
        let token = doc.tokens[tokenIndex]
        let word = meaning?.lemma.flatMap { $0.isEmpty ? nil : $0 } ?? token.word
        if let existing = savedVocab(for: token.word) {
            existing.savedManually = true
            existing.category = category
            try? context.save()
            return existing
        }
        let item = VocabItem(german: word, category: category)
        item.key = VocabularyAnalyzer.groupKey(token.word)
        item.english = meaning?.english ?? ""
        item.persian = meaning?.persian ?? ""
        item.synonyms = meaning?.synonyms ?? []
        item.partOfSpeech = meaning?.partOfSpeech ?? ""
        item.meaningSource = meaning?.source ?? ""
        fillContext(item, tokenIndex: tokenIndex)
        context.insert(item)
        log(.wordSaved)
        try? context.save()
        return item
    }

    /// Saves a Redemittel / sentence expression as a review item.
    func saveExpression(_ text: String, sentence: Int, english: String, persian: String) {
        guard let context else { return }
        let item = VocabItem(german: text, category: VocabCategory.meetings.rawValue)
        item.isExpression = true
        item.english = english
        item.persian = persian
        item.meaningSource = "Redemittel catalogue"
        fillContext(item, tokenIndex: doc.sentences[sentence].firstToken)
        if let c = clip(forSentence: sentence) { item.clipStart = c.start; item.clipEnd = c.end }
        context.insert(item)
        log(.redemittelSaved)
        try? context.save()
    }

    private func fillContext(_ item: VocabItem, tokenIndex: Int) {
        item.meetingID = doc.id
        item.meetingTitle = doc.title
        item.tokenIndex = tokenIndex
        if let timing = doc.tokens[tokenIndex].timing {
            let c = PlaybackPlanner.clip(for: timing, duration: player.duration)
            item.clipStart = c.start
            item.clipEnd = c.end
        }
        if let s = doc.sentenceIndex(containingToken: tokenIndex) {
            item.exampleSentence = doc.text(of: doc.sentences[s])
            item.exampleEnglish = doc.sentences[s].english?.text ?? ""
            item.examplePersian = doc.sentences[s].persian?.text ?? ""
        }
    }

    // MARK: - Logging

    func log(_ kind: PracticeKind, count: Int = 1, seconds: Double = 0) {
        guard let context else { return }
        context.insert(PracticeEvent(kind: kind, count: count, seconds: seconds, meetingID: doc.id))
    }

    func logListening() {
        let s = player.takeListenedSeconds()
        if s >= 1 { log(.listening, count: 0, seconds: s) }
    }
}

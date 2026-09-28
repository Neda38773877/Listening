import SwiftUI
import SwiftData
import MeetingCore

struct InspectorView: View {
    @ObservedObject var session: MeetingSession
    var onShadow: () -> Void = {}
    @Environment(\.modelContext) var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if case .word = session.inspector {
                    Text("Word")
                        .font(.headline)
                } else if case .sentence = session.inspector {
                    Text("Sentence")
                        .font(.headline)
                }
                Spacer()
                Button(action: { session.select(nil) }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .borderBottom()

            ScrollView {
                if session.inspector == nil {
                    Text("Tap a word to hear it and see its meaning. Tap the time to play the whole sentence.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if case .word(let tokenIndex) = session.inspector {
                    if session.doc.tokens.indices.contains(tokenIndex) {
                        WordCardView(session: session, tokenIndex: tokenIndex)
                            .id(tokenIndex)
                    } else {
                        Text("Word index out of range")
                            .foregroundStyle(.secondary)
                    }
                } else if case .sentence(let index) = session.inspector {
                    if session.doc.sentences.indices.contains(index) {
                        SentenceCardView(session: session, index: index, onShadow: onShadow)
                            .id(index)
                    } else {
                        Text("Sentence index out of range")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

struct WordCardView: View {
    @ObservedObject var session: MeetingSession
    let tokenIndex: Int
    @Environment(\.modelContext) var modelContext

    @State private var newText: String = ""
    @State private var showCorrectionSheet = false
    @State private var showTimingSheet = false
    @State private var showDictionary = false
    @State private var savedFlag = false
    @State private var timingStart: Double = 0
    @State private var timingEnd: Double = 0
    @State private var selectedCategory: String = "Work"

    @Query(sort: \CustomCategory.name) var customCategories: [CustomCategory]

    var token: Token { session.doc.tokens[tokenIndex] }
    var meaning: WordMeaning? { session.meanings[session.meaningKey(tokenIndex)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Word display
            VStack(alignment: .leading, spacing: 4) {
                Text(token.display)
                    .font(.system(size: 28, weight: .bold, design: .serif))

                if let corrected = token.corrected {
                    Text("Original transcript: \(token.original)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Timing line
            VStack(alignment: .leading, spacing: 4) {
                if let timing = token.timing {
                    HStack {
                        Text("\(TimeFormat.precise(timing.start)) – \(TimeFormat.precise(timing.end))")
                            .font(.system(.caption, design: .monospaced))

                        timingBadge(for: timing.source)
                    }
                } else {
                    Text("No audio timing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if token.needsReview {
                    Text("Not verified in the audio — check by listening.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Buttons row
            HStack(spacing: 12) {
                Button(action: { session.playWord(tokenIndex) }) {
                    Label("Play", systemImage: "play.fill")
                        .font(.caption)
                }
                .disabled(!session.hasAudio || token.timing == nil)

                Button(action: playSlowSpeed) {
                    Label("Slow", systemImage: "tortoise.fill")
                        .font(.caption)
                }
                .disabled(!session.hasAudio || token.timing == nil)

                Button(action: playSentence) {
                    Label("Sentence", systemImage: "text.bubble.fill")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)

                Spacer()
            }

            // Meaning section
            meaningSection

            // In this meeting
            sentenceContextSection

            // Save to word list
            saveSection

            // Correct this word
            DisclosureGroup("Correct this word") {
                HStack(spacing: 8) {
                    TextField("New text", text: $newText)
                    Button("Save correction") {
                        session.doc.editToken(tokenIndex, text: newText)
                        session.changed()
                        savedFlag.toggle()
                    }
                    .disabled(newText.isEmpty)
                }
                .padding(.vertical, 8)
                Text("The original transcript is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { newText = token.display }

            // Adjust timing
            DisclosureGroup("Adjust timing") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Start:")
                        Spacer()
                        Stepper("", value: $timingStart, step: 0.05)
                        Text(TimeFormat.precise(timingStart))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 80)
                    }

                    HStack {
                        Text("End:")
                        Spacer()
                        Stepper("", value: $timingEnd, step: 0.05)
                        Text(TimeFormat.precise(timingEnd))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 80)
                    }

                    HStack(spacing: 12) {
                        Button("Preview") {
                            session.player.play(Clip(start: timingStart, end: timingEnd))
                        }
                        Button("Save timing") {
                            session.doc.setTiming(tokenIndex, start: timingStart, end: timingEnd)
                            session.changed()
                        }
                        .disabled(timingEnd <= timingStart)
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                if let timing = token.timing {
                    timingStart = timing.start
                    timingEnd = timing.end
                } else if let sentenceIndex = session.doc.sentenceIndex(containingToken: tokenIndex),
                          let range = session.doc.timeRange(of: session.doc.sentences[sentenceIndex]) {
                    timingStart = range.lowerBound
                    timingEnd = range.upperBound
                }
            }
        }
        .padding()
    }

    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meaning")
                .font(.headline)

            if let m = meaning {
                // Existing meaning display
                if let lemma = m.lemma { row("German", lemma) }
                if let english = m.english { row("English", english) }
                if let persian = m.persian {
                    row("Persian", persian)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if let pos = m.partOfSpeech { row("Part of speech", pos) }
                if !m.synonyms.isEmpty { row("German synonyms", m.synonyms.joined(separator: ", ")) }
                if let note = m.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                }

                Text("Source: \(m.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !m.certain {
                    Label("Uncertain", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Ask Claude instead button if not Claude source
                if m.source != ClaudeService.providerName {
                    ExternalAIButton(
                        title: "Ask Claude instead",
                        meetingID: session.doc.id,
                        purpose: "explain this word"
                    ) {
                        Task { await session.explainWithAI(tokenIndex: tokenIndex) }
                    }
                    .environmentObject(AppSettings.shared)
                }
            } else {
                // No offline meaning
                Text("No meaning stored offline for this word.")
                    .foregroundStyle(.secondary)

                // System dictionary button
                if SystemDictionaryView.hasDefinition(token.word) {
                    Button("System dictionary") {
                        showDictionary = true
                    }
                    .sheet(isPresented: $showDictionary) {
                        SystemDictionaryView(term: token.word)
                    }
                }

                // External AI button
                ExternalAIButton(
                    title: "Explain with Claude",
                    meetingID: session.doc.id,
                    purpose: "explain this word"
                ) {
                    Task { await session.explainWithAI(tokenIndex: tokenIndex) }
                }
                .environmentObject(AppSettings.shared)
            }
        }
    }

    private var sentenceContextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In this meeting")
                .font(.headline)

            if let sentenceIndex = session.doc.sentenceIndex(containingToken: tokenIndex) {
                let s = session.doc.sentences[sentenceIndex]

                HStack {
                    highlightedSentence(s)
                        .lineLimit(nil)
                    Spacer()
                }

                if let english = s.english {
                    Text(english.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let persian = s.persian {
                    Text(persian.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func highlightedSentence(_ s: Sentence) -> Text {
        let tokens = session.doc.tokens[s.tokenRange]
        var textParts: [Text] = []
        for (i, t) in tokens.enumerated() {
            if i > 0 { textParts.append(Text(" ")) }
            let display = t.display
            if t.id == token.id {
                textParts.append(Text(display).fontWeight(.bold).foregroundStyle(Color.accentColor))
            } else {
                textParts.append(Text(display))
            }
        }
        return textParts.reduce(Text(""), +)
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save to your word list")
                .font(.headline)

            if session.savedVocab(for: token.word) != nil {
                Label("In your word list", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(VocabCategory.allCases, id: \.rawValue) { cat in
                        Text(cat.rawValue).tag(cat.rawValue)
                    }
                    Divider()
                    ForEach(customCategories, id: \.name) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }

                Button("Save to Word List") {
                    session.saveWord(tokenIndex: tokenIndex, category: selectedCategory, meaning: meaning)
                    savedFlag.toggle()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func timingBadge(for source: TimingSource) -> some View {
        switch source {
        case .aligned:
            return AnyView(Label("Synced", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green))
        case .fuzzy:
            return AnyView(Text("Synced · spelling differs").font(.caption).foregroundStyle(.secondary))
        case .between:
            return AnyView(Text("Approximate").font(.caption).foregroundStyle(.orange))
        case .manual:
            return AnyView(Text("Set by you").font(.caption).foregroundStyle(.blue))
        }
    }

    private func playSlowSpeed() {
        guard let timing = token.timing else { return }
        let clip = PlaybackPlanner.clip(for: timing, duration: session.player.duration)
        session.player.play(clip, rate: 0.5)
    }

    private func playSentence() {
        guard let sentenceIndex = session.doc.sentenceIndex(containingToken: tokenIndex) else { return }
        session.playSentence(sentenceIndex)
    }
}

struct SentenceCardView: View {
    @ObservedObject var session: MeetingSession
    let index: Int
    var onShadow: () -> Void = {}

    @State private var editText: String = ""
    @State private var showEditSheet = false
    @State private var showTranslationEditSheet = false
    @State private var editEnglish: String = ""
    @State private var editPersian: String = ""

    var sentence: Sentence { session.doc.sentences[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // German text
            VStack(alignment: .leading, spacing: 4) {
                Text(session.doc.text(of: sentence))
                    .font(.system(size: 18, weight: .semibold, design: .serif))

                if session.doc.text(of: sentence) != session.doc.originalText(of: sentence) {
                    Text("Original transcript:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.doc.originalText(of: sentence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Time range
            if let range = session.doc.timeRange(of: sentence) {
                Text("\(TimeFormat.short(range.lowerBound)) – \(TimeFormat.short(range.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Playback buttons
            HStack(spacing: 8) {
                Button(action: { session.playSentence(index) }) {
                    Label("Play", systemImage: "play.fill")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)

                Button(action: { session.playSentence(index) }) {
                    Label("Replay", systemImage: "repeat")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)

                Button(action: { session.playSentence(index, rate: 0.75) }) {
                    Text("0.75×")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)

                Button(action: { session.playSentence(index, rate: 0.5) }) {
                    Text("0.5×")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)

                Button(action: toggleRepeat) {
                    Label(session.loopSentence == index ? "Repeating" : "Repeat", systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(session.loopSentence == index ? Color.accentColor : Color.primary)
                }
                .disabled(!session.hasAudio)

                Button(action: onShadow) {
                    Label("Shadow", systemImage: "person.wave.2.fill")
                        .font(.caption)
                }
                .disabled(!session.hasAudio)
            }

            // Translations
            translationsSection

            // Record & compare
            recordingSection

            // Redemittel
            redemittelSection

            // Save sentence for review
            Button("Save sentence for review") {
                session.saveExpression(
                    session.doc.text(of: sentence),
                    sentence: index,
                    english: sentence.english?.text ?? "",
                    persian: sentence.persian?.text ?? ""
                )
            }
            .buttonStyle(.bordered)

            // Edit sentence
            Button("Edit sentence") {
                editText = session.doc.text(of: sentence)
                showEditSheet = true
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showEditSheet) {
                NavigationStack {
                    TextEditor(text: $editText)
                        .padding()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    session.doc.editSentence(index, text: editText)
                                    session.changed()
                                    showEditSheet = false
                                }
                            }
                        }
                }
            }

            // Timing adjustment
            HStack(spacing: 12) {
                Button("Earlier 0.1 s") {
                    session.doc.shiftSentence(index, by: -0.1)
                    session.changed()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Later 0.1 s") {
                    session.doc.shiftSentence(index, by: 0.1)
                    session.changed()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding()
    }

    private var translationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translations")
                .font(.headline)

            // English
            VStack(alignment: .leading, spacing: 4) {
                if let english = sentence.english {
                    VStack(alignment: .leading) {
                        Text(english.text)
                        Text("by \(english.provider)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not translated yet")
                        .foregroundStyle(.secondary)

                    Button("Translate on device") {
                        Task { await session.translateSentence(index, external: false) }
                    }
                    .font(.caption)

                    ExternalAIButton(
                        title: "Translate with Claude",
                        meetingID: session.doc.id,
                        purpose: "translate sentences"
                    ) {
                        Task { await session.translateSentence(index, external: true) }
                    }
                    .environmentObject(AppSettings.shared)
                    .font(.caption)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)

            // Persian
            VStack(alignment: .leading, spacing: 4) {
                if let persian = sentence.persian {
                    VStack(alignment: .leading) {
                        Text(persian.text)
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("by \(persian.provider)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not translated yet")
                        .foregroundStyle(.secondary)

                    Button("Translate on device") {
                        Task { await session.translateSentence(index, external: false) }
                    }
                    .font(.caption)

                    ExternalAIButton(
                        title: "Translate with Claude",
                        meetingID: session.doc.id,
                        purpose: "translate sentences"
                    ) {
                        Task { await session.translateSentence(index, external: true) }
                    }
                    .environmentObject(AppSettings.shared)
                    .font(.caption)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)

            Button("Edit translation") {
                editEnglish = sentence.english?.text ?? ""
                editPersian = sentence.persian?.text ?? ""
                showTranslationEditSheet = true
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .sheet(isPresented: $showTranslationEditSheet) {
                NavigationStack {
                    VStack(spacing: 16) {
                        TextField("English", text: $editEnglish)
                            .textFieldStyle(.roundedBorder)

                        TextField("Persian", text: $editPersian)
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                session.setTranslation(index, english: editEnglish.isEmpty ? nil : editEnglish,
                                                      persian: editPersian.isEmpty ? nil : editPersian)
                                showTranslationEditSheet = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var recordingSection: some View {
        RecordControls(recorder: session.recorder, session: session, index: index)
    }

    private var redemittelSection: some View {
        let sentence = session.doc.sentences[index]
        let hits = RedemittelCatalog.find(in: [session.doc.text(of: sentence)])

        return Group {
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Redemittel in this sentence")
                        .font(.headline)

                    ForEach(hits, id: \.self) { hit in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                (Text("\(hit.category.title): ") + Text(""").font(.caption).fontWeight(.semibold) + Text("\(hit.matchedText)").font(.caption).fontWeight(.semibold) + Text(""").font(.caption).fontWeight(.semibold))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("Pattern: \(hit.pattern)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func toggleRepeat() {
        if session.loopSentence == index {
            session.loopSentence = nil
        } else {
            session.loopSentence = index
            session.playSentence(index)
        }
    }
}

private struct RecordControls: View {
    @ObservedObject var recorder: VoiceRecorder
    @ObservedObject var session: MeetingSession
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record & compare")
                .font(.headline)

            HStack(spacing: 12) {
                if recorder.isRecording {
                    Button("Stop recording") {
                        recorder.stop()
                        session.log(.recording)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                } else {
                    Button("Record myself") {
                        Task { await recorder.start(into: session.store.recordingsFolder(session.doc.id)) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                if recorder.lastRecording != nil {
                    Button("Play my recording") {
                        recorder.playLast()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button("Play original") {
                        session.playSentence(index)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if recorder.permissionDenied {
                Text("Microphone access denied in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

extension View {
    fileprivate func borderBottom() -> some View {
        VStack {
            self
            Divider()
        }
    }
}

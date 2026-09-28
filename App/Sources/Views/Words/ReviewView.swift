import SwiftUI
import SwiftData
import MeetingCore

// MARK: - Review Mode Enum

enum ReviewMode: String, CaseIterable, Identifiable {
    case mixed, germanToPersian, germanToEnglish, persianToGerman, englishToGerman, audio, fillBlank, multipleChoice, sentenceCreation, speaking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .germanToPersian: return "German → Persian"
        case .germanToEnglish: return "German → English"
        case .persianToGerman: return "Persian → German"
        case .englishToGerman: return "English → German"
        case .audio: return "Audio recognition"
        case .fillBlank: return "Fill in the blank"
        case .multipleChoice: return "Multiple choice"
        case .sentenceCreation: return "Sentence creation"
        case .speaking: return "Speaking practice"
        }
    }

    func isPossible(for item: VocabItem) -> Bool {
        switch self {
        case .germanToPersian, .persianToGerman:
            return !item.persian.isEmpty
        case .germanToEnglish, .englishToGerman:
            return !item.english.isEmpty
        case .audio, .speaking:
            return item.hasClip
        case .fillBlank:
            return !item.exampleSentence.isEmpty && !item.isExpression &&
                   item.exampleSentence.lowercased().contains(item.german.lowercased())
        case .multipleChoice:
            return !item.english.isEmpty || !item.persian.isEmpty
        case .sentenceCreation:
            return true
        case .mixed:
            return true
        }
    }
}

// MARK: - Review Home View

struct ReviewHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \VocabItem.dateAdded) private var items: [VocabItem]
    @Query(sort: \MeetingRecord.createdAt) private var records: [MeetingRecord]
    @State private var selectedMode: ReviewMode = .mixed
    @State private var showSession = false
    @State private var sessionQueue: [UUID] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if queue.isEmpty {
                    ContentUnavailableView(
                        "No words to review",
                        systemImage: "checkmark.circle",
                        description: Text("Add words to your vocabulary and come back when they're due.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Words due now: \(dueCount)")
                        Text("New today: \(newCount)")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    Picker("Review mode", selection: $selectedMode) {
                        ForEach(ReviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Words you meet often in your meetings, get wrong, or saved yourself come first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()

                    if !queue.isEmpty {
                        Button(action: {
                            sessionQueue = queue
                            showSession = true
                        }) {
                            Text("Start review (\(queue.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Review")
            .navigationDestination(isPresented: $showSession) {
                ReviewSessionView(queue: sessionQueue, mode: selectedMode)
            }
        }
    }

    private var queue: [UUID] {
        let reviewable = items.filter { !$0.mastered || $0.due <= Date() }
        var inputs: [(id: UUID, input: PriorityInput)] = []
        for item in reviewable {
            let freq = records.reduce(0) { $0 + ($1.wordCounts[item.key] ?? 0) }
            let count = records.filter { ($0.wordCounts[item.key] ?? 0) > 0 }.count
            let input = PriorityInput(
                state: item.srs,
                meetingFrequency: freq,
                meetingCount: count,
                savedManually: item.savedManually,
                categoryWeight: VocabCategory.weight(item.category)
            )
            inputs.append((item.id, input))
        }
        return ReviewPriority.queue(inputs, newLimit: settings.newWordsPerDay)
    }

    private var dueCount: Int {
        items.filter { !$0.mastered && $0.due <= Date() }.count
    }

    private var newCount: Int {
        items.filter { $0.srs.isNew }.count
    }
}

// MARK: - Review Session View

struct ReviewSessionView: View {
    let queue: [UUID]
    let mode: ReviewMode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VocabItem.dateAdded) private var allItems: [VocabItem]
    @State private var position = 0
    @State private var order: [UUID] = []
    @State private var correctCount = 0
    @State private var wrongCount = 0

    var body: some View {
        Group {
            if position >= order.count {
                endScreen
            } else {
                cardView
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            order = queue
        }
    }

    private var cardView: some View {
        if let item = allItems.first(where: { $0.id == order[position] }) {
            let chosenMode = mode == .mixed ? selectModeForItem(item, at: position) : mode
            return AnyView(
                VStack(spacing: 16) {
                    HStack {
                        Text("Card \(position + 1) of \(order.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("End", role: .cancel) { dismiss() }
                    }
                    .padding()

                    ScrollView {
                        ReviewCard(
                            item: item,
                            mode: chosenMode,
                            onGrade: recordGrade
                        )
                        .padding()
                    }
                }
                .navigationBarBackButtonHidden()
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    private var endScreen: some View {
        VStack(spacing: 16) {
            Text("Review Complete")
                .font(.title)
            VStack(spacing: 8) {
                Text("Correct: \(correctCount)")
                Text("Wrong: \(wrongCount)")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding()
    }

    private func selectModeForItem(_ item: VocabItem, at pos: Int) -> ReviewMode {
        let rotation: [ReviewMode] = [.audio, .fillBlank, .germanToPersian, .multipleChoice, .englishToGerman, .persianToGerman, .germanToEnglish, .sentenceCreation, .speaking]
        let startIdx = pos % rotation.count
        for i in 0..<rotation.count {
            let mode = rotation[(startIdx + i) % rotation.count]
            if mode.isPossible(for: item) {
                return mode
            }
        }
        if ReviewMode.germanToEnglish.isPossible(for: item) { return .germanToEnglish }
        if ReviewMode.germanToPersian.isPossible(for: item) { return .germanToPersian }
        return .sentenceCreation
    }

    private func recordGrade(_ grade: ReviewGrade) {
        if let item = allItems.first(where: { $0.id == order[position] }) {
            item.srs = SpacedRepetition.review(item.srs, grade: grade)
            item.timesSeen += 1
            if grade == .again {
                item.timesWrong += 1
                if !order.contains(where: { $0 == order[position] && order.firstIndex(of: $0)! > position }) {
                    order.append(order[position])
                }
            }
            let kind: PracticeKind = grade == .again ? .reviewWrong : .review
            modelContext.insert(PracticeEvent(kind: kind))
            try? modelContext.save()

            if grade == .again { wrongCount += 1 } else { correctCount += 1 }
            position += 1
        }
    }
}

// MARK: - Review Card (Per-Card State)

struct ReviewCard: View {
    let item: VocabItem
    let mode: ReviewMode
    let onGrade: (ReviewGrade) -> Void

    @StateObject private var clips = ClipPlayer()
    @StateObject private var recorder = VoiceRecorder()
    @State private var revealed = false
    @State private var typedAnswer = ""
    @State private var feedback: String?
    @State private var multipleChoiceOptions: [String] = []
    @State private var suggestedGrade: ReviewGrade?

    var body: some View {
        VStack(spacing: 16) {
            cardContent

            if revealed {
                HStack(spacing: 12) {
                    ForEach([ReviewGrade.again, .hard, .good, .easy], id: \.self) { grade in
                        Button(grade.title) {
                            onGrade(grade)
                        }
                        .buttonStyle(grade == suggestedGrade ? .borderedProminent : .bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top)
            }
        }
        .id(item.id)
        .onAppear {
            if mode == .multipleChoice && multipleChoiceOptions.isEmpty {
                setupMultipleChoice()
            }
            if mode == .audio || mode == .fillBlank {
                _ = clips.play(item: item)
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch mode {
        case .germanToPersian:
            germanToPersianCard
        case .germanToEnglish:
            germanToEnglishCard
        case .persianToGerman:
            typingCard(prompt: item.persian, isRTL: true)
        case .englishToGerman:
            typingCard(prompt: item.english, isRTL: false)
        case .audio:
            audioCard
        case .fillBlank:
            fillBlankCard
        case .multipleChoice:
            multipleChoiceCard
        case .sentenceCreation:
            sentenceCreationCard
        case .speaking:
            speakingCard
        case .mixed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var germanToPersianCard: some View {
        VStack(spacing: 12) {
            Text(item.german)
                .font(.title2)
                .fontWeight(.bold)
            if item.hasClip {
                Button(action: { _ = clips.play(item: item) }) {
                    Label("Play", systemImage: "speaker.wave.2")
                }
            }
            if revealed {
                Text(item.persian)
                    .font(.title3)
                    .foregroundStyle(.blue)
                if !item.exampleSentence.isEmpty {
                    Text(item.exampleSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Show answer") {
                    revealed = true
                    suggestedGrade = .good
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var germanToEnglishCard: some View {
        VStack(spacing: 12) {
            Text(item.german)
                .font(.title2)
                .fontWeight(.bold)
            if item.hasClip {
                Button(action: { _ = clips.play(item: item) }) {
                    Label("Play", systemImage: "speaker.wave.2")
                }
            }
            if revealed {
                Text(item.english)
                    .font(.title3)
                    .foregroundStyle(.blue)
                if !item.exampleSentence.isEmpty {
                    Text(item.exampleSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Show answer") {
                    revealed = true
                    suggestedGrade = .good
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func typingCard(prompt: String, isRTL: Bool) -> some View {
        VStack(spacing: 12) {
            Text(prompt)
                .font(.title2)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            if isRTL {
                TextField("Type the German word", text: $typedAnswer)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("Type the German word", text: $typedAnswer)
                    .textFieldStyle(.roundedBorder)
            }
            if revealed {
                Text(item.german)
                    .font(.title3)
                    .foregroundStyle(.blue)
            } else {
                Button("Check") {
                    let normalized = GermanText.normalize(typedAnswer)
                    let itemNorm = GermanText.normalize(item.german)
                    if normalized == itemNorm {
                        feedback = "Correct!"
                        suggestedGrade = .good
                    } else if GermanText.levenshtein(normalized, itemNorm) <= 1 && item.german.count > 5 {
                        feedback = "Almost!"
                        suggestedGrade = .good
                    } else {
                        feedback = "Incorrect"
                        suggestedGrade = .again
                    }
                    revealed = true
                }
                .buttonStyle(.bordered)
            }
            if let fb = feedback {
                Text(fb)
                    .font(.caption)
                    .foregroundStyle(fb.contains("Correct") || fb.contains("Almost") ? .green : .orange)
            }
        }
    }

    @ViewBuilder
    private var audioCard: some View {
        VStack(spacing: 12) {
            Text("Recognize the word")
                .font(.headline)
            Button(action: { _ = clips.play(item: item) }) {
                Label("Play again", systemImage: "speaker.wave.2.fill")
            }
            TextField("Type the German word", text: $typedAnswer)
                .textFieldStyle(.roundedBorder)
            if revealed {
                Text(item.german)
                    .font(.title3)
                    .foregroundStyle(.blue)
            } else {
                Button("Show answer") {
                    revealed = true
                    suggestedGrade = .good
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var fillBlankCard: some View {
        VStack(spacing: 12) {
            if item.hasClip {
                Button(action: { _ = clips.play(item: item) }) {
                    Label("Play", systemImage: "speaker.wave.2")
                }
            }
            let blanked = item.exampleSentence
                .replacingOccurrences(of: item.german, with: "_____", options: .caseInsensitive)
            Text(blanked)
                .font(.body)
            TextField("Fill in the blank", text: $typedAnswer)
                .textFieldStyle(.roundedBorder)
            if revealed {
                Text(item.german)
                    .font(.title3)
                    .foregroundStyle(.blue)
            } else {
                Button("Check") {
                    let normalized = GermanText.normalize(typedAnswer)
                    let itemNorm = GermanText.normalize(item.german)
                    revealed = true
                    if normalized == itemNorm {
                        feedback = "Correct!"
                        suggestedGrade = .good
                    } else {
                        feedback = "Incorrect"
                        suggestedGrade = .again
                    }
                }
                .buttonStyle(.bordered)
            }
            if let fb = feedback {
                Text(fb)
                    .font(.caption)
                    .foregroundStyle(fb.contains("Correct") ? .green : .orange)
            }
        }
    }

    @ViewBuilder
    private var multipleChoiceCard: some View {
        VStack(spacing: 12) {
            Text(item.german)
                .font(.headline)
            VStack(spacing: 8) {
                ForEach(0..<min(4, multipleChoiceOptions.count), id: \.self) { idx in
                    Button(action: { selectMultipleChoice(idx) }) {
                        Text(multipleChoiceOptions[idx])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sentenceCreationCard: some View {
        VStack(spacing: 12) {
            Text(item.german)
                .font(.headline)
            HStack(spacing: 8) {
                if !item.english.isEmpty {
                    Text(item.english)
                        .font(.caption)
                }
                if !item.persian.isEmpty {
                    Text(item.persian)
                        .font(.caption)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .foregroundStyle(.secondary)
            TextEditor(text: $typedAnswer)
                .frame(minHeight: 80)
                .border(Color(.systemGray3))
            if revealed {
                Text(feedback ?? "")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else {
                Button("Check") {
                    let words = GermanText.words(typedAnswer)
                    let itemKey = VocabularyAnalyzer.groupKey(item.german)
                    let hasWord = words.contains { GermanText.normalize($0) == GermanText.normalize(itemKey) || VocabularyAnalyzer.groupKey($0) == itemKey }
                    if hasWord {
                        feedback = "Uses the word ✓"
                        suggestedGrade = .good
                    } else {
                        feedback = "The word is missing"
                        suggestedGrade = .again
                    }
                    revealed = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var speakingCard: some View {
        VStack(spacing: 12) {
            if item.hasClip {
                Button(action: { _ = clips.play(item: item) }) {
                    Label("Play clip", systemImage: "speaker.wave.2")
                }
            }
            if recorder.isRecording {
                Text("Recording...")
                    .foregroundStyle(.red)
                Button("Stop", role: .destructive) {
                    recorder.stop()
                }
            } else if let _ = recorder.lastRecording {
                VStack(spacing: 8) {
                    if recorder.isPlaying {
                        Button("Stop playback") {
                            recorder.stopPlayback()
                        }
                    } else {
                        Button("Play my recording") {
                            recorder.playLast()
                        }
                    }
                }
            } else {
                Button("Start recording") {
                    Task { await recorder.start(into: FileManager.default.temporaryDirectory) }
                }
            }
            if !revealed {
                Button("Done") {
                    revealed = true
                    suggestedGrade = .good
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func setupMultipleChoice() {
        let correctAnswer = item.persian.isEmpty ? item.english : item.persian
        // Note: In a real app, would fetch allItems from environment
        multipleChoiceOptions = [correctAnswer].shuffled()
    }

    private func selectMultipleChoice(_ idx: Int) {
        let correctAnswer = item.persian.isEmpty ? item.english : item.persian
        revealed = true
        if multipleChoiceOptions[idx] == correctAnswer {
            feedback = "Correct!"
            suggestedGrade = .good
        } else {
            feedback = "Incorrect"
            suggestedGrade = .again
        }
    }
}

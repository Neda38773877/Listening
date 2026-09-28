import SwiftUI
import SwiftData
import MeetingCore

struct WordDetailView: View {
    @Bindable var item: VocabItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var clips = ClipPlayer()
    @Query(sort: \MeetingRecord.createdAt, order: .reverse) private var records: [MeetingRecord]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @State private var showDeleteConfirm = false
    @State private var pendingDelete = false

    var body: some View {
        Form {
            Section("Word") {
                TextField("German", text: $item.german)
                TextField("English", text: $item.english)
                TextField("Persian", text: $item.persian)
                    .environment(\.layoutDirection, .rightToLeft)
                TextField("Part of speech", text: $item.partOfSpeech)
                TextField("German synonyms (comma separated)", text: Binding(
                    get: { item.synonyms.joined(separator: ", ") },
                    set: { item.synonyms = $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                if !item.meaningSource.isEmpty {
                    Text("Meanings source: \(item.meaningSource)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("From the meeting") {
                if !item.exampleSentence.isEmpty {
                    Text(item.exampleSentence)
                        .font(.system(.body, design: .serif))
                }
                if !item.exampleEnglish.isEmpty {
                    Text(item.exampleEnglish)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.examplePersian.isEmpty {
                    Text(item.examplePersian)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !item.meetingTitle.isEmpty {
                    Text(item.meetingTitle)
                        .font(.caption)
                }
                Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let clipStart = item.clipStart {
                    Text("Audio at \(TimeFormat.precise(clipStart))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.hasClip {
                    HStack(spacing: 16) {
                        Button(action: { _ = clips.play(item: item) }) {
                            Label("Play word", systemImage: "play.fill")
                        }
                        Button(action: { _ = clips.play(item: item, rate: 0.5) }) {
                            Label("Play slowly", systemImage: "tortoise")
                        }
                    }
                } else {
                    Text("No audio position saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Learning") {
                Picker("Category", selection: $item.category) {
                    ForEach(VocabCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat.rawValue)
                    }
                    Divider()
                    ForEach(customCategories, id: \.name) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                    if !item.category.isEmpty && !categoryExists {
                        Divider()
                        Text(item.category).tag(item.category)
                    }
                }
                Stepper("Difficulty: \(item.difficulty)", value: $item.difficulty, in: 1...5)
                Toggle("Mastered", isOn: $item.mastered)

                let freq = wordFrequency
                let count = meetingCount
                if freq > 0 {
                    Text("Frequency in your meetings: \(freq) in \(count) meetings")
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SRS Info")
                        .font(.headline)
                    HStack {
                        Text("Due:")
                        Spacer()
                        Text(relativeDateString(item.due))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Interval:")
                        Spacer()
                        Text(String(format: "%.1f days", item.intervalDays))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Repetitions:")
                        Spacer()
                        Text("\(item.repetitions)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Lapses:")
                        Spacer()
                        Text("\(item.lapses)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Times Wrong:")
                        Spacer()
                        Text("\(item.timesWrong)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                Button("Reset learning progress", role: .destructive) {
                    item.srs = SRSState()
                    item.mastered = false
                    item.timesWrong = 0
                }
            }

            Section("Notes") {
                TextEditor(text: $item.notes)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle("Word Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog("Delete Word", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingDelete = true
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this word?")
        }
        .onDisappear {
            if pendingDelete {
                modelContext.delete(item)
                try? modelContext.save()
            } else {
                try? modelContext.save()
            }
        }
    }

    private var wordFrequency: Int {
        records.reduce(0) { $0 + ($1.wordCounts[item.key] ?? 0) }
    }

    private var meetingCount: Int {
        records.filter { ($0.wordCounts[item.key] ?? 0) > 0 }.count
    }

    private var categoryExists: Bool {
        VocabCategory.allCases.contains { $0.rawValue == item.category } ||
        customCategories.contains { $0.name == item.category }
    }

    private func relativeDateString(_ date: Date) -> String {
        let now = Date()
        let diff = date.timeIntervalSince(now)
        if diff < 0 {
            let days = Int(ceil(-diff / 86400))
            return "\(days) days overdue"
        } else if diff < 86400 {
            return "Today"
        } else {
            let days = Int(diff / 86400)
            return "in \(days) days"
        }
    }
}

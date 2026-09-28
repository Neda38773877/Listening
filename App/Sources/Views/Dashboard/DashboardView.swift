import SwiftUI
import SwiftData
import Charts
import MeetingCore

struct DashboardView: View {
    @Query(sort: \MeetingRecord.createdAt, order: .reverse) private var records: [MeetingRecord]
    @Query(sort: \VocabItem.dateAdded, order: .reverse) private var vocabItems: [VocabItem]
    @Query(sort: \PracticeEvent.date, order: .reverse) private var events: [PracticeEvent]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Stats Cards Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        statCard("Meetings", value: readyMeetingCount, icon: "waveform")
                        statCard("Listening time", value: listeningTime, icon: "clock")
                        statCard("Words saved", value: String(wordsSavedCount), icon: "character.book.closed")
                        statCard("Words learned", value: String(masteredCount), icon: "checkmark.circle")
                        statCard("Words repeatedly missed", value: String(weakVocabCount), icon: "exclamationmark.circle")
                        statCard("Sentences practiced", value: String(sentencePracticeCount), icon: "text.alignleft")
                        statCard("Shadowing reps", value: String(shadowingCount), icon: "waveform.circle")
                        statCard("Redemittel learned", value: String(redemittelCount), icon: "sparkles")
                        statCard("Learning streak", value: String(streakDays), icon: "flame")
                    }
                    .padding()

                    // Chart
                    let chartData = last14Days
                    VStack(alignment: .leading) {
                        Text("Listening time (last 14 days)")
                            .font(.headline)
                            .padding(.horizontal)

                        Chart(chartData, id: \.date) { data in
                            BarMark(
                                x: .value("Date", data.date, unit: .day),
                                y: .value("Minutes", data.minutes)
                            )
                            .foregroundStyle(.blue)
                        }
                        .frame(height: 200)
                        .padding()
                    }

                    // Most common vocabulary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most common vocabulary in your meetings")
                            .font(.headline)
                            .padding(.horizontal)

                        let topWords = mostCommonVocab
                        if topWords.isEmpty {
                            Text("No vocabulary data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 4) {
                                ForEach(topWords, id: \.key) { entry in
                                    HStack {
                                        Text(entry.key)
                                        Spacer()
                                        Text("\(entry.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding()
                        }
                    }

                    // Weak vocabulary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weak vocabulary")
                            .font(.headline)
                            .padding(.horizontal)

                        if weakVocab.isEmpty {
                            Text("No weak vocabulary")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 8) {
                                ForEach(weakVocab) { item in
                                    NavigationLink(destination: WordDetailView(item: item)) {
                                        HStack {
                                            Text(item.german)
                                                .font(.caption)
                                            Spacer()
                                            HStack(spacing: 8) {
                                                Text("Wrong: \(item.timesWrong)")
                                                    .font(.caption2)
                                                Text("Lapses: \(item.lapses)")
                                                    .font(.caption2)
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    @ViewBuilder
    private func statCard(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var readyMeetingCount: String {
        String(records.filter { $0.status == .ready }.count)
    }

    private var listeningTime: String {
        let totalSeconds = events
            .filter { $0.kindRaw == PracticeKind.listening.rawValue }
            .reduce(0) { $0 + $1.seconds }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var wordsSavedCount: Int {
        vocabItems.filter { !$0.isExpression }.count
    }

    private var masteredCount: Int {
        vocabItems.filter(\.mastered).count
    }

    private var weakVocabCount: Int {
        vocabItems.filter { $0.lapses >= 2 || $0.timesWrong >= 3 }.count
    }

    private var sentencePracticeCount: Int {
        events.filter { $0.kindRaw == PracticeKind.sentencePractice.rawValue }.reduce(0) { $0 + $1.count }
    }

    private var shadowingCount: Int {
        events.filter { $0.kindRaw == PracticeKind.shadowing.rawValue }.reduce(0) { $0 + $1.count }
    }

    private var redemittelCount: Int {
        vocabItems.filter { $0.isExpression && $0.repetitions >= 2 }.count
    }

    private var streakDays: Int {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        while true {
            let dayEvents = events.filter { Calendar.current.isDate($0.date, inSameDayAs: checkDate) }
            if dayEvents.isEmpty {
                if Calendar.current.isDateInToday(checkDate) && streak == 0 {
                    checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate)!
                    continue
                }
                break
            }
            streak += 1
            checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }

    private var last14Days: [(date: Date, minutes: Double)] {
        var data: [Date: Double] = [:]
        let calendar = Calendar.current

        for event in events {
            let startOfDay = calendar.startOfDay(for: event.date)
            if calendar.dateComponents([.day], from: startOfDay, to: Date()).day ?? 0 <= 14 {
                if event.kindRaw == PracticeKind.listening.rawValue {
                    data[startOfDay, default: 0] += event.seconds / 60
                }
            }
        }

        var result: [(date: Date, minutes: Double)] = []
        for i in 0..<14 {
            let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date()))!
            result.append((date: date, minutes: data[date] ?? 0))
        }
        return result.reversed()
    }

    private var mostCommonVocab: [(key: String, count: Int)] {
        var wordCounts: [String: Int] = [:]
        for record in records {
            for (word, count) in record.wordCounts {
                wordCounts[word, default: 0] += count
            }
        }
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { ($0.key, $0.value) }
    }

    private var weakVocab: [VocabItem] {
        vocabItems
            .filter { $0.lapses >= 2 || $0.timesWrong >= 3 }
            .sorted { (a, b) in
                let aScore = a.lapses + a.timesWrong
                let bScore = b.lapses + b.timesWrong
                return aScore > bScore
            }
            .prefix(10)
            .map { $0 }
    }
}

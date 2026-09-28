import SwiftUI
import MeetingCore

struct SummaryView: View {
    @ObservedObject var session: MeetingSession
    @Environment(\.dismiss) var dismiss

    @State private var heardWords: [HeardWord] = []
    @State private var redemittelPatterns: [RedemittelHit] = []

    var summary: MeetingSummary? { session.doc.summary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if summary == nil {
                        // Create summary section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The summary is created by Claude (external AI) from the transcript text. Every statement must cite sentences from the meeting; statements without evidence are removed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ExternalAIButton(
                                title: "Create summary with Claude",
                                meetingID: session.doc.id,
                                purpose: "summarise the meeting"
                            ) {
                                Task { await session.analyzeWithAI() }
                            }
                            .environmentObject(AppSettings.shared)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    } else {
                        // Display existing summary
                        summaryHeader

                        if let sum = summary, sum.droppedUnsupportedItems > 0 {
                            Text("\(sum.droppedUnsupportedItems) statements were removed because they were not supported by the meeting.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(8)
                                .background(Color(.systemOrange).opacity(0.1))
                                .cornerRadius(6)
                        }

                        // Summary sections
                        if let sum = summary {
                            ForEach(Array(sum.sections.enumerated()), id: \.offset) { i, section in
                                summarySection(section)
                            }
                        }

                        // Regenerate button
                        ExternalAIButton(
                            title: "Regenerate",
                            meetingID: session.doc.id,
                            purpose: "summarise the meeting"
                        ) {
                            Task { await session.analyzeWithAI() }
                        }
                        .environmentObject(AppSettings.shared)
                    }

                    Divider()

                    // Always-present offline sections
                    offlineVocabSection
                    offlineRedemittelSection
                }
                .padding()
            }
            .navigationTitle("Meeting Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            heardWords = VocabularyAnalyzer.heardWords(session.doc.tokens)
                .filter { $0.form.count >= 5 }
                .prefix(15).map { $0 }
            redemittelPatterns = MeetingBuilder.redemittel(in: session.doc)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sum = summary {
                HStack {
                    Text("By \(sum.provider)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let dateStr = DateFormatter.localizedString(from: sum.createdAt, dateStyle: .short, timeStyle: .short)
                    Text("· \(dateStr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summarySection(_ section: SummarySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.topic)
                .font(.headline)

            summaryField("What was discussed?", items: section.discussed)
            summaryField("Problem", items: section.problems)
            summaryField("Cause", items: section.causes)
            summaryField("Action", items: section.actions)
            summaryField("Responsible person", items: section.responsible)
            summaryField("Deadline", items: section.deadlines)
            summaryField("Decision", items: section.decisions)
            summaryField("Open question", items: section.openQuestions)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func summaryField(_ title: String, items: [EvidencedItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(SummarySection.notStated)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• " + item.text)
                            .font(.caption)

                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(item.evidence, id: \.self) { sentenceIndex in
                                if session.doc.sentences.indices.contains(sentenceIndex) {
                                    Button(action: {
                                        session.select(.sentence(sentenceIndex))
                                        session.jump(toSentence: sentenceIndex)
                                        dismiss()
                                    }) {
                                        if let range = session.doc.timeRange(of: session.doc.sentences[sentenceIndex]) {
                                            Text("#\(sentenceIndex + 1) \(TimeFormat.short(range.lowerBound))")
                                                .font(.caption2)
                                        } else {
                                            Text("#\(sentenceIndex + 1)")
                                                .font(.caption2)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var offlineVocabSection: some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text("Important vocabulary (heard in this meeting)")
                .font(.headline)

            if heardWords.isEmpty {
                Text("No significant vocabulary found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(heardWords, id: \.form) { word in
                        VStack(alignment: .center, spacing: 2) {
                            Text(word.form)
                                .font(.caption)
                            Text("×\(word.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    private var offlineRedemittelSection: some View {
        let uniquePatterns = Array(Set(redemittelPatterns.map { $0.pattern })).prefix(10)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Important Redemittel (found in this meeting)")
                .font(.headline)

            if uniquePatterns.isEmpty {
                Text("No expressions found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(uniquePatterns, id: \.self) { pattern in
                        HStack {
                            if let hit = redemittelPatterns.first(where: { $0.pattern == pattern }) {
                                Text("\(hit.category.title): \(pattern)")
                                    .font(.caption)
                            } else {
                                Text(pattern)
                                    .font(.caption)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

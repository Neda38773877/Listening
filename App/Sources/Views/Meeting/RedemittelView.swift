import SwiftUI
import MeetingCore

struct RedemittelView: View {
    @ObservedObject var session: MeetingSession
    @Environment(\.dismiss) var dismiss

    @State private var categoryFilter: RedemittelCategory?
    @State private var hits: [RedemittelHit] = []

    var filteredHits: [RedemittelHit] {
        if let cat = categoryFilter {
            return hits.filter { $0.category == cat }
        }
        return hits
    }

    var categoriesWithHits: Set<RedemittelCategory> {
        Set(hits.map { $0.category })
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Category", selection: $categoryFilter) {
                    Text("All").tag(RedemittelCategory?.none)
                    Divider()
                    ForEach(RedemittelCategory.allCases, id: \.self) { cat in
                        Text(cat.title).tag(RedemittelCategory?.some(cat))
                    }
                }
                .pickerStyle(.menu)
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Found in this meeting
                        if !filteredHits.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Found in this meeting (\(filteredHits.count))")
                                    .font(.headline)

                                ForEach(filteredHits, id: \.self) { hit in
                                    foundHitRow(hit)
                                }
                            }
                        } else if categoryFilter != nil {
                            Text("No catalogue expressions in this category.")
                                .foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView(
                                "No catalogue expressions were detected in this meeting.",
                                systemImage: "sparkles"
                            )
                        }

                        Divider()

                        // Recommended expressions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recommended additional expressions — NOT from this meeting")
                                .font(.headline)

                            if let cat = categoryFilter {
                                recommendedForCategory(cat)
                            } else {
                                ForEach(RedemittelCategory.allCases, id: \.self) { cat in
                                    recommendedForCategory(cat)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Redemittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { hits = MeetingBuilder.redemittel(in: session.doc) }
    }

    private func foundHitRow(_ hit: RedemittelHit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category and pattern
            (Text("\(hit.category.title): ") + Text("“") + Text("\(hit.matchedText)") + Text("”"))
                .font(.headline)

            // Full sentence with highlighted match
            if session.doc.sentences.indices.contains(hit.sentenceIndex) {
                let sentence = session.doc.text(of: session.doc.sentences[hit.sentenceIndex])
                let range = sentence.range(of: hit.matchedText, options: .caseInsensitive) ?? sentence.startIndex..<sentence.startIndex

                HStack {
                    Text(String(sentence[..<range.lowerBound])) +
                    Text(String(sentence[range])).fontWeight(.bold).foregroundStyle(Color.accentColor) +
                    Text(String(sentence[range.upperBound...]))
                }
                .lineLimit(nil)

                // Pattern details
                if let pattern = RedemittelCatalog.patterns.first(where: { $0.pattern == hit.pattern }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pattern: \(hit.pattern)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(pattern.english)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(pattern.persian)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }

                // Time
                if let range = session.doc.timeRange(of: session.doc.sentences[hit.sentenceIndex]) {
                    Text("\(TimeFormat.short(range.lowerBound)) – \(TimeFormat.short(range.upperBound))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { session.playSentence(hit.sentenceIndex) }) {
                    Image(systemName: "play.circle.fill")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if let pattern = RedemittelCatalog.patterns.first(where: { $0.pattern == hit.pattern }) {
                        session.saveExpression(hit.pattern, sentence: hit.sentenceIndex, english: pattern.english, persian: pattern.persian)
                    }
                }) {
                    Image(systemName: "bookmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func recommendedForCategory(_ category: RedemittelCategory) -> some View {
        if let recommended = RedemittelCatalog.recommended[category] {
            VStack(alignment: .leading, spacing: 8) {
                Text(category.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(recommended, id: \.self) { expr in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expr)
                                .font(.caption)
                            Label("Recommended", systemImage: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

import SwiftUI
import SwiftData
import MeetingCore

struct MeetingVocabularyView: View {
    @ObservedObject var session: MeetingSession
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State private var source: VocabularySource = .heardInMeeting
    @State private var heardWords: [HeardWord] = []
    @State private var heardTermKeys: Set<String> = []

    @Query(filter: #Predicate<CustomTermRecord> { $0.seeded == true }) var technicalTerms: [CustomTermRecord]
    @Query(filter: #Predicate<CustomTermRecord> { $0.seeded == false }) var userTerms: [CustomTermRecord]

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("Source", selection: $source) {
                        ForEach([VocabularySource.heardInMeeting, .relatedWorkplace, .meetingExpression, .technical, .userDefined], id: \.self) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding()

                Text(source.title)
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, -12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch source {
                        case .heardInMeeting:
                            heardInMeetingSection

                        case .relatedWorkplace:
                            relatedWorkplaceSection

                        case .meetingExpression:
                            meetingExpressionSection

                        case .technical:
                            technicalSection

                        case .userDefined:
                            userDefinedSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Meeting Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            heardWords = VocabularyAnalyzer.heardWords(session.doc.tokens)

            // Compute heard term keys once for performance
            var keys: Set<String> = []
            for term in technicalTerms + userTerms {
                let german = term.term.replacingOccurrences(of: "^(der|die|das) ", with: "", options: .regularExpression)
                if VocabularyAnalyzer.occurs(german, in: session.doc.tokens) {
                    keys.insert(term.term)
                }
            }
            for item in VocabularyAnalyzer.relatedWorkplace {
                let german = item.german.replacingOccurrences(of: "^(der|die|das) ", with: "", options: .regularExpression)
                if VocabularyAnalyzer.occurs(german, in: session.doc.tokens) {
                    keys.insert(item.german)
                }
            }
            heardTermKeys = keys
        }
    }

    private var heardInMeetingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(heardWords, id: \.key) { word in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.form)
                            .fontWeight(.semibold)
                        Text("×\(word.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let firstOcc = word.occurrences.first {
                        Button(action: { session.playWord(firstOcc) }) {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if session.savedVocab(for: word.form) != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(action: {
                            if let firstOcc = word.occurrences.first {
                                session.saveWord(tokenIndex: firstOcc, category: "Work", meaning: nil)
                            }
                        }) {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
    }

    private var relatedWorkplaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            suggestionBanner

            ForEach(VocabularyAnalyzer.relatedWorkplace, id: \.german) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.german)
                        .fontWeight(.semibold)
                    Text(item.english)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.persian)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)

                    if heardTermKeys.contains(item.german) {
                        Label("Heard in this meeting", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("Suggestion", systemImage: "lightbulb")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
    }

    private var meetingExpressionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            suggestionBanner

            let allExpressions = RedemittelCatalog.recommended.values.flatMap { $0 }

            ForEach(allExpressions, id: \.self) { expr in
                HStack {
                    Text(expr)
                        .font(.caption)
                    Spacer()
                    Label("Recommended", systemImage: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
    }

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            suggestionBanner

            let heardTerms = technicalTerms.filter { heardTermKeys.contains($0.term) }
            let notHeardTerms = technicalTerms.filter { !heardTermKeys.contains($0.term) }.prefix(60)

            if !heardTerms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heard in this meeting")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(heardTerms, id: \.term) { term in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(term.term)
                                    .font(.caption)
                                Text(term.persian)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                }
            }

            if !notHeardTerms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From your glossary (not heard in this meeting)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(Array(notHeardTerms), id: \.term) { term in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(term.term)
                                    .font(.caption)
                                Text(term.persian)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .environment(\.layoutDirection, .rightToLeft)
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

    private var userDefinedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            suggestionBanner

            let heardTerms = userTerms.filter { heardTermKeys.contains($0.term) }
            let notHeardTerms = userTerms.filter { !heardTermKeys.contains($0.term) }.prefix(60)

            if !heardTerms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heard in this meeting")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(heardTerms, id: \.term) { term in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(term.term)
                                    .font(.caption)
                                Text(term.persian)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                }
            }

            if !notHeardTerms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your custom vocabulary (not heard in this meeting)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(Array(notHeardTerms), id: \.term) { term in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(term.term)
                                    .font(.caption)
                                Text(term.persian)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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

    private var suggestionBanner: some View {
        Text("Suggestions — these are not necessarily said in this meeting.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(6)
    }
}

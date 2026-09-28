import SwiftUI
import SwiftData
import MeetingCore

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingRecord.createdAt, order: .reverse) private var records: [MeetingRecord]
    @Query(sort: \VocabItem.dateAdded, order: .reverse) private var vocabItems: [VocabItem]
    @Query(sort: \CustomTermRecord.added) private var customTerms: [CustomTermRecord]
    @StateObject private var clips = ClipPlayer()
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all
    @State private var results: [SearchResult] = []
    @State private var loadedDocs: [UUID: MeetingDocument] = [:]
    @State private var cachedRedemittel: [UUID: [RedemittelHit]] = [:]

    enum SearchScope: String, CaseIterable {
        case all = "All", meetings = "Meetings", words = "Word list", dictionary = "Dictionary", redemittel = "Redemittel"
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && searchText.count >= 2 {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try different search terms")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Search for words, meanings, people, topics…")
                    )
                } else {
                    List {
                        ForEach(groupedResults, id: \.key) { section, sectionResults in
                            Section(section) {
                                ForEach(sectionResults, id: \.self) { result in
                                    searchResultRow(result)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Word, meaning, person, topic…")
            .safeAreaInset(edge: .top) {
                Picker("Scope", selection: $searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            .navigationTitle("Search")
            .task(id: "\(searchText)|\(searchScope.rawValue)") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await performSearch()
            }
        }
    }

    private var groupedResults: [(key: String, value: [SearchResult])] {
        var sections: [String: [SearchResult]] = [:]

        var meetingSections: [String: [SearchResult]] = [:]
        var currentMeetingOrder: [String] = []

        for result in results {
            switch result.kind {
            case .word, .sentence, .translation, .topic:
                if let meetingTitle = result.meetingTitle {
                    if meetingSections[meetingTitle] == nil {
                        currentMeetingOrder.append(meetingTitle)
                    }
                    meetingSections[meetingTitle, default: []].append(result)
                }
            case .vocab:
                sections["Word list", default: []].append(result)
            case .customTerm:
                sections["Dictionary", default: []].append(result)
            case .redemittel:
                sections["Redemittel", default: []].append(result)
            }
        }

        var ordered: [(key: String, value: [SearchResult])] = []
        for title in currentMeetingOrder {
            ordered.append((key: title, value: meetingSections[title] ?? []))
        }

        for (key, value) in ["Word list", "Dictionary", "Redemittel"] {
            if let results = sections[key] {
                ordered.append((key: key, value: results))
            }
        }

        return ordered
    }

    @ViewBuilder
    private func searchResultRow(_ result: SearchResult) -> some View {
        switch result.kind {
        case .word:
            wordResultRow(result)
        case .sentence:
            sentenceResultRow(result)
        case .translation:
            translationResultRow(result)
        case .topic:
            topicResultRow(result)
        case .vocab:
            vocabResultRow(result)
        case .customTerm:
            customTermRow(result)
        case .redemittel:
            redemittelResultRow(result)
        }
    }

    @ViewBuilder
    private func wordResultRow(_ result: SearchResult) -> some View {
        Button(action: { playWord(result) }) {
            HStack {
                Image(systemName: "textformat")
                    .foregroundStyle(.blue)
                Text(result.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sentenceResultRow(_ result: SearchResult) -> some View {
        Button(action: { playSentence(result) }) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.green)
                Text(result.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func translationResultRow(_ result: SearchResult) -> some View {
        Button(action: { playSentence(result) }) {
            HStack {
                Image(systemName: "character.bubble")
                    .foregroundStyle(.purple)
                Text(result.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func topicResultRow(_ result: SearchResult) -> some View {
        Button(action: { playSentence(result) }) {
            HStack {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.orange)
                Text(result.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func vocabResultRow(_ result: SearchResult) -> some View {
        NavigationLink(destination: result.vocabItem.map { WordDetailView(item: $0) }) {
            HStack {
                Text(result.vocabItem?.german ?? "")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if result.vocabItem?.hasClip ?? false {
                    Button(action: {
                        if let item = result.vocabItem {
                            _ = clips.play(item: item)
                        }
                    }) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func customTermRow(_ result: SearchResult) -> some View {
        HStack {
            Text(result.customTerm?.term ?? "")
                .font(.caption)
                .fontWeight(.semibold)
            Spacer()
            Text(result.customTerm?.category.title ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func redemittelResultRow(_ result: SearchResult) -> some View {
        Button(action: { playRedemittel(result) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.text)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(result.redemittelCategory?.title ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func performSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }

        var newResults: [SearchResult] = []

        if searchScope == .all || searchScope == .meetings {
            for record in records {
                guard record.status == .ready else { continue }
                guard let doc = MeetingStore.shared.load(record.id) else { continue }

                loadedDocs[doc.id] = doc
                let hits = MeetingSearch.search(q, in: doc, limit: 100)
                for hit in hits {
                    var result = SearchResult(from: hit)
                    result.meetingTitle = record.title
                    newResults.append(result)
                }
            }
        }

        if searchScope == .all || searchScope == .words {
            let matching = vocabItems.filter { item in
                [item.german, item.english, item.persian, item.notes].contains { term in
                    term.lowercased().contains(q.lowercased())
                }
            }
            for item in matching {
                newResults.append(SearchResult(vocabItem: item))
            }
        }

        if searchScope == .all || searchScope == .dictionary {
            let matching = customTerms.filter { term in
                [term.term, term.english, term.persian].contains { t in
                    t.lowercased().contains(q.lowercased())
                }
            }
            for term in matching {
                newResults.append(SearchResult(customTerm: term))
            }
        }

        if searchScope == .all || searchScope == .redemittel {
            for record in records {
                guard record.status == .ready else { continue }
                guard let doc = MeetingStore.shared.load(record.id) else { continue }

                if cachedRedemittel[doc.id] == nil {
                    cachedRedemittel[doc.id] = MeetingBuilder.redemittel(in: doc)
                }

                if let hits = cachedRedemittel[doc.id] {
                    let matching = hits.filter { hit in
                        hit.pattern.lowercased().contains(q.lowercased()) ||
                        hit.matchedText.lowercased().contains(q.lowercased()) ||
                        hit.category.title.lowercased().contains(q.lowercased())
                    }
                    for hit in matching {
                        newResults.append(SearchResult(redemittel: hit, meetingID: doc.id, meetingTitle: record.title))
                    }
                }
                loadedDocs[doc.id] = doc
            }
        }

        results = newResults
    }

    private func playWord(_ result: SearchResult) {
        guard let meetingID = result.meetingID,
              let tokenIndex = result.tokenIndex,
              let doc = loadedDocs[meetingID],
              tokenIndex < doc.tokens.count,
              let timing = doc.tokens[tokenIndex].timing else { return }
        let clip = PlaybackPlanner.clip(for: timing, duration: doc.duration)
        _ = clips.play(meetingID: meetingID, clip: clip)
    }

    private func playSentence(_ result: SearchResult) {
        guard let meetingID = result.meetingID,
              let sentenceIndex = result.sentenceIndex,
              let doc = loadedDocs[meetingID],
              sentenceIndex < doc.sentences.count,
              let timeRange = doc.timeRange(of: doc.sentences[sentenceIndex]) else { return }
        let clip = PlaybackPlanner.clip(for: timeRange, duration: doc.duration)
        _ = clips.play(meetingID: meetingID, clip: clip)
    }

    private func playRedemittel(_ result: SearchResult) {
        playSentence(result)
    }
}

// MARK: - Search Result

struct SearchResult: Hashable {
    enum Kind: Hashable {
        case word, sentence, translation, topic, vocab, customTerm, redemittel
    }

    let kind: Kind
    let text: String
    let meetingID: UUID?
    let sentenceIndex: Int?
    let tokenIndex: Int?
    let time: Double?
    var meetingTitle: String?
    var vocabItem: VocabItem?
    var customTerm: CustomTermRecord?
    var redemittelCategory: RedemittelCategory?

    init(from hit: SearchHit) {
        self.meetingID = hit.meetingID
        self.sentenceIndex = hit.sentenceIndex
        self.tokenIndex = hit.tokenIndex
        self.time = hit.time
        self.text = hit.text
        self.meetingTitle = nil
        switch hit.kind {
        case .word: self.kind = .word
        case .sentence: self.kind = .sentence
        case .translation: self.kind = .translation
        case .topic: self.kind = .topic
        case .redemittel: self.kind = .redemittel
        }
    }

    init(vocabItem: VocabItem) {
        self.kind = .vocab
        self.text = vocabItem.german
        self.meetingID = nil
        self.sentenceIndex = nil
        self.tokenIndex = nil
        self.time = nil
        self.vocabItem = vocabItem
    }

    init(customTerm: CustomTermRecord) {
        self.kind = .customTerm
        self.text = customTerm.term
        self.meetingID = nil
        self.sentenceIndex = nil
        self.tokenIndex = nil
        self.time = nil
        self.customTerm = customTerm
    }

    init(redemittel: RedemittelHit, meetingID: UUID, meetingTitle: String) {
        self.kind = .redemittel
        self.text = redemittel.pattern
        self.meetingID = meetingID
        self.sentenceIndex = redemittel.sentenceIndex
        self.tokenIndex = nil
        self.time = nil
        self.meetingTitle = meetingTitle
        self.redemittelCategory = redemittel.category
    }
}

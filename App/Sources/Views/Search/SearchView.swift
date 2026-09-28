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
    @State private var searchScope = "All"
    @State private var results: [SearchResult] = []
    @State private var loadedDocs: [UUID: MeetingDocument] = [:]

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
                        ForEach(results.indices, id: \.self) { idx in
                            searchResultRow(results[idx])
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Word, meaning, person, topic…")
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Scope", selection: $searchScope) {
                        ForEach(["All", "Meetings", "Word list", "Dictionary", "Redemittel"], id: \.self) { scope in
                            Text(scope).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await performSearch()
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: SearchResult) -> some View {
        switch result.kind {
        case .word:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "textformat")
                        .foregroundStyle(.blue)
                    Text(result.text)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    if let meetingID = result.meetingID {
                        Button(action: {
                            if let doc = loadedDocs[meetingID] {
                                playWord(in: doc, result: result)
                            }
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                if let time = result.time {
                    Text(TimeFormat.short(time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .sentence:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.green)
                    Text(result.text)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    if let meetingID = result.meetingID {
                        Button(action: {
                            if let doc = loadedDocs[meetingID] {
                                playSentence(in: doc, result: result)
                            }
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                if let time = result.time {
                    Text(TimeFormat.short(time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .translation:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "character.bubble")
                        .foregroundStyle(.purple)
                    Text(result.text)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    if let meetingID = result.meetingID {
                        Button(action: {
                            if let doc = loadedDocs[meetingID] {
                                playSentence(in: doc, result: result)
                            }
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.purple)
                        }
                    }
                }
                if let time = result.time {
                    Text(TimeFormat.short(time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .topic:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(.orange)
                    Text(result.text)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    if let meetingID = result.meetingID {
                        Button(action: {
                            if let doc = loadedDocs[meetingID] {
                                playSentence(in: doc, result: result)
                            }
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let time = result.time {
                    Text(TimeFormat.short(time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .vocab:
            NavigationLink(destination: WordDetailView(item: result.vocabItem!)) {
                VStack(alignment: .leading, spacing: 4) {
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
                        }
                    }
                    if let english = result.vocabItem?.english, !english.isEmpty {
                        Text(english)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .customTerm:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.customTerm?.term ?? "")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(result.customTerm?.category.title ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let english = result.customTerm?.english, !english.isEmpty {
                        Text(english)
                            .font(.caption2)
                    }
                    if let persian = result.customTerm?.persian, !persian.isEmpty {
                        Text(persian)
                            .font(.caption2)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                .foregroundStyle(.secondary)
            }

        case .redemittel:
            VStack(alignment: .leading, spacing: 4) {
                Text(result.text)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(result.redemittelCategory?.title ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func performSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }

        var newResults: [SearchResult] = []

        switch searchScope {
        case "Meetings", "All":
            for record in records {
                guard record.status == .ready else { continue }
                guard let doc = MeetingStore.shared.load(record.id) else { continue }

                loadedDocs[doc.id] = doc
                let hits = MeetingSearch.search(q, in: doc, limit: 100)
                for hit in hits {
                    newResults.append(SearchResult(from: hit))
                }
            }
            if searchScope == "All" { fallthrough }
            else { break }
            fallthrough

        case "Word list":
            if searchScope == "All" || searchScope == "Word list" {
                let matching = vocabItems.filter { item in
                    [item.german, item.english, item.persian, item.notes].contains { term in
                        term.lowercased().contains(q.lowercased())
                    }
                }
                for item in matching {
                    newResults.append(SearchResult(vocabItem: item))
                }
            }
            if searchScope == "All" { fallthrough }
            else { break }
            fallthrough

        case "Dictionary":
            if searchScope == "All" || searchScope == "Dictionary" {
                let matching = customTerms.filter { term in
                    [term.term, term.english, term.persian].contains { t in
                        t.lowercased().contains(q.lowercased())
                    }
                }
                for term in matching {
                    newResults.append(SearchResult(customTerm: term))
                }
            }
            if searchScope == "All" { fallthrough }
            else { break }
            fallthrough

        case "Redemittel":
            if searchScope == "All" || searchScope == "Redemittel" {
                for record in records {
                    guard record.status == .ready else { continue }
                    guard let doc = MeetingStore.shared.load(record.id) else { continue }
                    loadedDocs[doc.id] = doc
                    let hits = MeetingBuilder.redemittel(in: doc)
                    let matching = hits.filter { hit in
                        hit.pattern.lowercased().contains(q.lowercased()) ||
                        hit.matchedText.lowercased().contains(q.lowercased()) ||
                        hit.category.title.lowercased().contains(q.lowercased())
                    }
                    for hit in matching {
                        newResults.append(SearchResult(redemittel: hit, meetingID: doc.id))
                    }
                }
            }

        default:
            break
        }

        results = newResults.prefix(100).map { $0 }
    }

    private func playWord(in doc: MeetingDocument, result: SearchResult) {
        guard let tokenIndex = result.tokenIndex,
              tokenIndex < doc.tokens.count,
              let timing = doc.tokens[tokenIndex].timing else { return }
        let clip = PlaybackPlanner.clip(for: timing, duration: doc.duration)
        _ = clips.play(meetingID: doc.id, clip: clip)
    }

    private func playSentence(in doc: MeetingDocument, result: SearchResult) {
        guard let sentenceIndex = result.sentenceIndex,
              sentenceIndex < doc.sentences.count,
              let timeRange = doc.timeRange(of: doc.sentences[sentenceIndex]) else { return }
        let clip = PlaybackPlanner.clip(for: timeRange, duration: doc.duration)
        _ = clips.play(meetingID: doc.id, clip: clip)
    }
}

// MARK: - Search Result

struct SearchResult {
    enum Kind {
        case word, sentence, translation, topic, vocab, customTerm, redemittel
    }

    let kind: Kind
    let text: String
    let meetingID: UUID?
    let sentenceIndex: Int?
    let tokenIndex: Int?
    let time: Double?
    var vocabItem: VocabItem?
    var customTerm: CustomTermRecord?
    var redemittelCategory: RedemittelCategory?

    init(from hit: SearchHit) {
        self.meetingID = hit.meetingID
        self.sentenceIndex = hit.sentenceIndex
        self.tokenIndex = hit.tokenIndex
        self.time = hit.time
        self.text = hit.text
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

    init(redemittel: RedemittelHit, meetingID: UUID) {
        self.kind = .redemittel
        self.text = redemittel.pattern
        self.meetingID = meetingID
        self.sentenceIndex = redemittel.sentenceIndex
        self.tokenIndex = nil
        self.time = nil
        self.redemittelCategory = redemittel.category
    }
}

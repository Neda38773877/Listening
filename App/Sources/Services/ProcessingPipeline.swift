import Foundation
import SwiftData
import UIKit
import BackgroundTasks
import MeetingCore

/// Runs the processing stages for a meeting, reporting progress per stage.
/// Every stage saves its result, so an interrupted run (app killed, phone locked)
/// resumes where it stopped.
@MainActor
final class ProcessingPipeline: ObservableObject {
    static let shared = ProcessingPipeline()
    static let backgroundTaskID = "com.hoerentrainer.processing"

    struct Progress: Equatable {
        var fraction: [ProcessingStage: Double] = [:]
        var current: ProcessingStage?
        var message: String?
    }

    @Published private(set) var progress: [UUID: Progress] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Document being built while recognition chunks arrive.
    private var working: [UUID: MeetingDocument] = [:]
    let store = MeetingStore.shared

    func isRunning(_ id: UUID) -> Bool { tasks[id] != nil }
    var hasRunningWork: Bool { !tasks.isEmpty }

    func cancelAll() {
        for t in tasks.values { t.cancel() }
    }

    func waitForAll() async {
        while let t = tasks.values.first {
            await t.value
            // `start` removes finished tasks; guard against a task that never clears.
            if tasks.values.first.map({ $0 == t }) ?? false { break }
        }
    }

    func start(_ id: UUID, container: ModelContainer) {
        guard tasks[id] == nil else { return }
        let bg = UIApplication.shared.beginBackgroundTask(withName: "Process meeting") { [weak self] in
            Task { @MainActor in self?.scheduleBackgroundResume() }
        }
        tasks[id] = Task { [weak self] in
            await self?.run(id, container: container)
            await MainActor.run {
                self?.tasks[id] = nil
                UIApplication.shared.endBackgroundTask(bg)
            }
        }
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    /// Resumes meetings left in the "processing" state (e.g. after the app was closed).
    func resumeUnfinished(container: ModelContainer) {
        let ctx = container.mainContext
        let processing = MeetingStatus.processing.rawValue
        let records = (try? ctx.fetch(FetchDescriptor<MeetingRecord>(predicate: #Predicate { $0.statusRaw == processing }))) ?? []
        for r in records { start(r.id, container: container) }
    }

    // MARK: - Stages

    private func set(_ id: UUID, _ stage: ProcessingStage, _ value: Double, message: String? = nil) {
        var p = progress[id] ?? Progress()
        p.fraction[stage] = value
        p.current = value < 1 ? stage : nil
        if let m = message { p.message = m }
        progress[id] = p
    }

    private func run(_ id: UUID, container: ModelContainer) async {
        let ctx = container.mainContext
        guard var doc = store.load(id),
              let record = try? ctx.fetch(FetchDescriptor<MeetingRecord>(predicate: #Predicate { $0.id == id })).first else { return }
        record.status = .processing
        record.statusDetail = nil
        try? ctx.save()
        progress[id] = Progress()
        for s in doc.processing.completed { set(id, s, 1) }

        let terms = ((try? ctx.fetch(FetchDescriptor<CustomTermRecord>())) ?? []).map(\.asTerm)
        let dictionary = CustomDictionary(terms: terms)

        do {
            // 1. Audio analysis: on-device speech recognition in chunks.
            if !doc.processing.completed.contains(.audioAnalysis) {
                if let url = store.audioURL(for: doc) {
                    let total = SpeechRecognitionService.chunkCount(duration: doc.duration)
                    doc.processing.totalChunks = total
                    set(id, .audioAnalysis, Double(doc.processing.recognizedChunks.count) / Double(total),
                        message: "Recognizing speech on this device…")
                    let service = SpeechRecognitionService()
                    working[id] = doc
                    defer { working[id] = nil }
                    do {
                        try await service.recognize(audioURL: url, duration: doc.duration, hints: dictionary.contextualStrings,
                                                    skip: doc.processing.recognizedChunks,
                                                    allowServer: AppSettings.shared.allowServerRecognition) { [weak self] chunk, words in
                            await self?.addRecognized(id, chunk: chunk, words: words, total: total)
                        }
                    } catch {
                        // Keep the chunks that did finish.
                        if let w = working[id] { doc = w }
                        throw error
                    }
                    if let w = working[id] { doc = w }
                    doc.recognized.sort { $0.start < $1.start }
                }
                doc.processing.completed.insert(.audioAnalysis)
                set(id, .audioAnalysis, 1)
                try store.save(doc)
            }
            try Task.checkCancellation()

            // 2 + 3. Alignment and sentence segmentation (pure, fast).
            if !doc.processing.completed.contains(.alignment) || !doc.processing.completed.contains(.segmentation) {
                set(id, .alignment, 0.1, message: "Aligning transcript with audio…")
                let snapshot = doc
                let built = await Task.detached(priority: .userInitiated) { () -> MeetingDocument in
                    var d = snapshot
                    MeetingBuilder.rebuild(&d, dictionary: dictionary)
                    return d
                }.value
                doc = built
                doc.processing.completed.formUnion([.alignment, .segmentation])
                set(id, .alignment, 1)
                set(id, .segmentation, 1)
                try store.save(doc)
            }

            // 4. Vocabulary statistics for cross-meeting frequency.
            if !doc.processing.completed.contains(.vocabulary) {
                set(id, .vocabulary, 0.5, message: "Extracting vocabulary…")
                let heard = VocabularyAnalyzer.heardWords(doc.tokens)
                record.wordCounts = Dictionary(heard.prefix(800).map { ($0.key, $0.count) }, uniquingKeysWith: +)
                doc.processing.completed.insert(.vocabulary)
                set(id, .vocabulary, 1)
                try store.save(doc)
            }

            updateRecord(record, from: doc)
            try? ctx.save()

            // 5. Translation (on-device only here; external AI is always an explicit user action).
            if !doc.processing.completed.contains(.translation) {
                set(id, .translation, 0, message: "Translating on this device…")
                await translateOnDevice(&doc, id: id)
                doc.processing.completed.insert(.translation)
                set(id, .translation, 1)
                try store.save(doc)
            }

            // 6. Meeting analysis: automatic timeline was built with the sentences; Redemittel are
            //    detected live from the transcript. An AI summary is optional and user-initiated.
            doc.processing.completed.insert(.meetingAnalysis)
            set(id, .meetingAnalysis, 1, message: "Done")
            doc.processing.lastError = nil
            try store.save(doc)
            record.status = .ready
        } catch is CancellationError {
            record.status = .processing
            record.statusDetail = "Paused — will resume"
        } catch {
            doc.processing.lastError = error.localizedDescription
            try? store.save(doc)
            // A meeting with a transcript is still usable without audio alignment.
            record.status = doc.tokens.isEmpty && doc.originalTranscript.isEmpty ? .failed : .ready
            record.statusDetail = error.localizedDescription
            if doc.tokens.isEmpty && !doc.originalTranscript.isEmpty {
                MeetingBuilder.rebuild(&doc, dictionary: dictionary)
                try? store.save(doc)
            }
        }
        updateRecord(record, from: doc)
        try? ctx.save()
    }

    private func addRecognized(_ id: UUID, chunk: Int, words: [RecognizedWord], total: Int) {
        guard var d = working[id] else { return }
        d.recognized.append(contentsOf: words)
        d.processing.recognizedChunks.insert(chunk)
        working[id] = d
        try? store.save(d)
        set(id, .audioAnalysis, Double(d.processing.recognizedChunks.count) / Double(total))
    }

    private func updateRecord(_ r: MeetingRecord, from doc: MeetingDocument) {
        r.duration = doc.duration
        r.sentenceCount = doc.sentences.count
        r.pendingCorrections = doc.pendingCorrections.count
        r.alignedRatio = doc.alignedWordRatio
        r.hasAudio = doc.audioFileName != nil
        r.hasTranscript = !doc.originalTranscript.isEmpty
    }

    private func translateOnDevice(_ doc: inout MeetingDocument, id: UUID) async {
        guard UIApplication.shared.applicationState == .active else { return }
        for (lang, total) in [("en", 0.5), ("fa", 1.0)] {
            let availability = await OnDeviceTranslator.availability(to: lang)
            guard availability != .unsupported else { continue }
            let items = doc.sentences.enumerated().compactMap { i, s -> (id: Int, text: String)? in
                let existing = lang == "en" ? s.english : s.persian
                return existing == nil ? (id: i, text: doc.text(of: s)) : nil
            }
            guard !items.isEmpty else { continue }
            do {
                let result = try await OnDeviceTranslator.shared.translate(items, to: lang)
                for (i, text) in result where doc.sentences.indices.contains(i) {
                    let t = TranslationText(text: text, provider: OnDeviceTranslator.providerName)
                    if lang == "en" { doc.sentences[i].english = t } else { doc.sentences[i].persian = t }
                }
                set(id, .translation, total)
            } catch {
                set(id, .translation, total, message: "On-device translation unavailable: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Background resume

    func scheduleBackgroundResume() {
        let req = BGProcessingTaskRequest(identifier: Self.backgroundTaskID)
        req.requiresExternalPower = false
        req.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(req)
    }
}

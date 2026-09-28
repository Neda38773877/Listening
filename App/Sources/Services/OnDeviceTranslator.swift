import Foundation
import SwiftUI
import Translation

/// Apple's on-device Translation framework. A `TranslationSession` can only be
/// obtained from SwiftUI's `.translationTask`, so a hidden host view (installed in
/// the root view) runs queued jobs.
@MainActor
final class OnDeviceTranslator: ObservableObject {
    static let shared = OnDeviceTranslator()
    static let providerName = "Apple Translation (on-device)"

    @Published var configuration: TranslationSession.Configuration?

    private struct Job {
        let target: String
        let items: [(id: Int, text: String)]
        let continuation: CheckedContinuation<[Int: String], Error>
    }
    private var queue: [Job] = []
    private var running = false

    enum Availability { case installed, downloadable, unsupported }

    nonisolated static func availability(to target: String) async -> Availability {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "de"), to: Locale.Language(identifier: target))
        switch status {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Translates German texts to `target` ("en", "fa"). Throws if the pair is unsupported.
    func translate(_ items: [(id: Int, text: String)], to target: String) async throws -> [Int: String] {
        if items.isEmpty { return [:] }
        return try await withCheckedThrowingContinuation { cont in
            queue.append(Job(target: target, items: items, continuation: cont))
            startNextIfIdle()
        }
    }

    private func startNextIfIdle() {
        guard !running, let job = queue.first else { return }
        running = true
        let wanted = TranslationSession.Configuration(source: Locale.Language(identifier: "de"),
                                                      target: Locale.Language(identifier: job.target))
        if configuration?.target == wanted.target && configuration?.source == wanted.source {
            configuration?.invalidate()   // re-run the task with the same language pair
        } else {
            configuration = wanted
        }
    }

    /// Called by the host view's `.translationTask`.
    func run(_ session: TranslationSession) async {
        guard !queue.isEmpty else { running = false; return }
        let job = queue.removeFirst()
        do {
            try await session.prepareTranslation()
            var out: [Int: String] = [:]
            for start in stride(from: 0, to: job.items.count, by: 40) {
                let batch = job.items[start..<min(start + 40, job.items.count)]
                let requests = batch.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id)) }
                let responses = try await session.translations(from: requests)
                for r in responses {
                    if let idString = r.clientIdentifier, let id = Int(idString) { out[id] = r.targetText }
                }
            }
            job.continuation.resume(returning: out)
        } catch {
            job.continuation.resume(throwing: error)
        }
        running = false
        startNextIfIdle()
    }
}

/// Invisible view that hosts the translation session.
struct TranslationHost: View {
    @ObservedObject var translator = OnDeviceTranslator.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(translator.configuration) { session in
                await translator.run(session)
            }
    }
}

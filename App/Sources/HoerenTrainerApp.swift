import SwiftUI
import SwiftData
import BackgroundTasks
import MeetingCore

@main
struct HoerenTrainerApp: App {
    let container: ModelContainer
    @StateObject private var inbox = ImportInbox()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var pipeline = ProcessingPipeline.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try ModelContainer(for: MeetingRecord.self, VocabItem.self, CustomTermRecord.self,
                                           PracticeEvent.self, CustomCategory.self)
        } catch {
            fatalError("Could not open the database: \(error)")
        }
        let c = container
        BGTaskScheduler.shared.register(forTaskWithIdentifier: ProcessingPipeline.backgroundTaskID, using: nil) { task in
            Task { @MainActor in
                task.expirationHandler = {
                    Task { @MainActor in ProcessingPipeline.shared.cancelAll() }
                }
                ProcessingPipeline.shared.resumeUnfinished(container: c)
                await ProcessingPipeline.shared.waitForAll()
                task.setTaskCompleted(success: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(inbox)
                .environmentObject(settings)
                .environmentObject(pipeline)
                .onOpenURL { url in inbox.receive(url) }
                .task {
                    SeedData.seedIfNeeded(container.mainContext)
                    pipeline.resumeUnfinished(container: container)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && pipeline.hasRunningWork { pipeline.scheduleBackgroundResume() }
            if phase == .active { pipeline.resumeUnfinished(container: container) }
        }
    }
}

/// Files handed to the app via Share → Open in / Files.
@MainActor
final class ImportInbox: ObservableObject {
    @Published var pending: [URL] = []
    @Published var showImport = false

    func receive(_ url: URL) {
        // Files opened in the app are copied into Documents/Inbox by the system; keep our own copy.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
            pending.append(dest)
        } else {
            pending.append(url)
        }
        showImport = true
    }
}

/// First-launch data: the PV/quality glossary carried over from the web version.
enum SeedData {
    struct Entry: Decodable { let term: String; let persian: String; let kind: String; let priority: Bool }

    @MainActor
    static func seedIfNeeded(_ ctx: ModelContext) {
        let flag = "seededGlossary.v1"
        guard !UserDefaults.standard.bool(forKey: flag),
              let url = Bundle.main.url(forResource: "SeedGlossary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        let existing = Set(((try? ctx.fetch(FetchDescriptor<CustomTermRecord>())) ?? []).map { GermanText.normalize($0.term) })
        for e in entries where !existing.contains(GermanText.normalize(e.term)) {
            ctx.insert(CustomTermRecord(term: e.term, category: e.kind == "verb" ? .general : .pv, persian: e.persian, seeded: true))
        }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: flag)
    }
}

import Foundation
import MeetingCore

/// File storage for meetings: Documents/Meetings/<id>/{audio.*, transcript.*, meeting.json, recordings/}.
/// Everything stays on the device (and in the user's own backups).
final class MeetingStore: @unchecked Sendable {
    static let shared = MeetingStore()

    private let queue = DispatchQueue(label: "MeetingStore")
    private var cache: [UUID: MeetingDocument] = [:]
    let root: URL

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func folder(_ id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func documentURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("meeting.json") }

    func audioURL(for doc: MeetingDocument) -> URL? {
        guard let name = doc.audioFileName else { return nil }
        let url = folder(doc.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func recordingsFolder(_ id: UUID) -> URL {
        let url = folder(id).appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Documents

    func load(_ id: UUID) -> MeetingDocument? {
        if let d = queue.sync(execute: { cache[id] }) { return d }
        guard let data = try? Data(contentsOf: documentURL(id)),
              let doc = try? JSONDecoder().decode(MeetingDocument.self, from: data) else { return nil }
        queue.sync { cache[id] = doc }
        return doc
    }

    func save(_ doc: MeetingDocument) throws {
        queue.sync { cache[doc.id] = doc }
        let data = try JSONEncoder().encode(doc)
        try data.write(to: documentURL(doc.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func allDocuments(ids: [UUID]) -> [MeetingDocument] {
        ids.compactMap(load)
    }

    // MARK: Import

    /// Copies a file into the meeting folder. Security-scoped URLs from the file importer are handled.
    func importFile(_ source: URL, into id: UUID, as baseName: String) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension.lowercased()
        let name = "\(baseName).\(ext)"
        let dest = folder(id).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
        return name
    }

    // MARK: Deletion

    func deleteMeeting(_ id: UUID) {
        queue.sync { cache[id] = nil }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    /// Deletes only the audio file (keeps transcript, translations and vocabulary).
    func deleteAudio(_ doc: inout MeetingDocument) {
        if let url = audioURL(for: doc) { try? FileManager.default.removeItem(at: url) }
        try? FileManager.default.removeItem(at: recordingsFolder(doc.id))
        doc.audioFileName = nil
        try? save(doc)
    }

    /// Deletes the transcript text and everything derived from it, keeping the audio.
    func deleteTranscript(_ doc: inout MeetingDocument) {
        if let name = doc.transcriptFileName { try? FileManager.default.removeItem(at: folder(doc.id).appendingPathComponent(name)) }
        doc.originalTranscript = ""
        doc.transcriptFileName = nil
        doc.tokens = []
        doc.sentences = []
        doc.corrections = []
        doc.topics = []
        doc.summary = nil
        doc.recognized = []
        doc.processing = ProcessingState()
        try? save(doc)
    }

    func deleteEverything() {
        queue.sync { cache.removeAll() }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}

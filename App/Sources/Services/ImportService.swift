import Foundation
import AVFoundation
import PDFKit
import UniformTypeIdentifiers
import MeetingCore

/// An audio recording and/or transcript waiting to be imported as one meeting.
struct ImportCandidate: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var audio: URL?
    var transcript: URL?
}

enum ImportError: LocalizedError {
    case nothingToImport
    case unreadableTranscript(String)
    case unreadableAudio(String)

    var errorDescription: String? {
        switch self {
        case .nothingToImport: return "Choose an audio recording, a transcript, or both."
        case .unreadableTranscript(let n): return "The transcript “\(n)” could not be read as text."
        case .unreadableAudio(let n): return "The audio file “\(n)” could not be opened."
        }
    }
}

enum ImportService {

    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "aif", "aiff", "mp4"]
    static let transcriptExtensions: Set<String> = ["txt", "md", "markdown", "srt", "vtt", "pdf", "text"]

    static var allowedTypes: [UTType] {
        var t: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .plainText, .text, .pdf]
        for ext in ["md", "markdown", "srt", "vtt", "m4a"] { if let u = UTType(filenameExtension: ext) { t.append(u) } }
        return t
    }

    static func isAudio(_ url: URL) -> Bool { audioExtensions.contains(url.pathExtension.lowercased()) }
    static func isTranscript(_ url: URL) -> Bool { transcriptExtensions.contains(url.pathExtension.lowercased()) }

    /// Pairs files by name: "meeting_2026_09_28.m4a" + "meeting_2026_09_28.txt" → one meeting.
    static func pair(_ urls: [URL]) -> [ImportCandidate] {
        var groups: [String: ImportCandidate] = [:]
        var order: [String] = []
        for url in urls {
            let base = url.deletingPathExtension().lastPathComponent
            let key = base.lowercased()
                .replacingOccurrences(of: "_transcript", with: "")
                .replacingOccurrences(of: " transcript", with: "")
                .replacingOccurrences(of: "-transcript", with: "")
            var c = groups[key] ?? ImportCandidate(title: base.replacingOccurrences(of: "_", with: " "))
            if isAudio(url) { c.audio = url } else if isTranscript(url) { c.transcript = url } else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key] = c
        }
        var result = order.compactMap { groups[$0] }
        // Exactly one audio and one transcript with different names: still pair them.
        let audios = result.filter { $0.audio != nil && $0.transcript == nil }
        let texts = result.filter { $0.transcript != nil && $0.audio == nil }
        if audios.count == 1 && texts.count == 1 && result.count == 2 {
            result = [ImportCandidate(title: audios[0].title, audio: audios[0].audio, transcript: texts[0].transcript)]
        }
        return result
    }

    /// Reads a transcript file as text (UTF-8, UTF-16, Latin-1, or PDF text).
    static func readTranscript(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url), let s = pdf.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.unreadableTranscript(url.lastPathComponent)
            }
            return s
        }
        let data = try Data(contentsOf: url)
        for enc in [String.Encoding.utf8, .utf16, .isoLatin1, .windowsCP1252] {
            if let s = String(data: data, encoding: enc), !s.isEmpty { return s }
        }
        throw ImportError.unreadableTranscript(url.lastPathComponent)
    }

    static func audioDuration(_ url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return 0 }
        let s = CMTimeGetSeconds(d)
        return s.isFinite ? s : 0
    }

    /// Creates the meeting folder and document. Processing happens afterwards.
    static func createMeeting(from c: ImportCandidate, store: MeetingStore = .shared) async throws -> MeetingDocument {
        guard c.audio != nil || c.transcript != nil else { throw ImportError.nothingToImport }
        var doc = MeetingDocument(title: c.title)
        if let t = c.transcript {
            doc.originalTranscript = try readTranscript(t)
            doc.transcriptFileName = try store.importFile(t, into: doc.id, as: "transcript")
        }
        if let a = c.audio {
            do {
                doc.audioFileName = try store.importFile(a, into: doc.id, as: "audio")
            } catch {
                store.deleteMeeting(doc.id)
                throw ImportError.unreadableAudio(a.lastPathComponent)
            }
            if let url = store.audioURL(for: doc) { doc.duration = await audioDuration(url) }
        }
        try store.save(doc)
        return doc
    }
}

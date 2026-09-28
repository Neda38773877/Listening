import Foundation
import AVFoundation
import Speech
import MeetingCore

enum RecognitionError: LocalizedError {
    case notAuthorized
    case germanUnavailable
    case onDeviceUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not allowed. Enable it in Settings › Privacy › Speech Recognition."
        case .germanUnavailable:
            return "German speech recognition is not available on this device."
        case .onDeviceUnavailable:
            return "On-device German recognition is not available. Download German dictation in Settings › General › Keyboard › Dictation, or allow Apple server recognition in the app settings."
        case .failed(let m):
            return "Speech recognition failed: \(m)"
        }
    }
}

/// Recognizes the words of a long recording with timestamps, in ~1-minute chunks.
/// Each finished chunk is reported immediately so processing can resume after an
/// interruption without starting over.
final class SpeechRecognitionService {

    static let chunkSeconds = 55.0
    static let overlapSeconds = 2.0

    let locale = Locale(identifier: "de-DE")

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status == .authorized) }
        }
    }

    static func chunkCount(duration: Double) -> Int {
        max(1, Int((duration / chunkSeconds).rounded(.up)))
    }

    /// - Parameters:
    ///   - skip: chunks already recognized in an earlier run.
    ///   - allowServer: when false (default) audio never leaves the device.
    ///   - onChunk: called with (chunk index, words in absolute time).
    func recognize(audioURL: URL, duration: Double, hints: [String], skip: Set<Int>, allowServer: Bool,
                   onChunk: @escaping (Int, [RecognizedWord]) async throws -> Void) async throws {
        guard await Self.requestAuthorization() else { throw RecognitionError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw RecognitionError.germanUnavailable }
        if !recognizer.supportsOnDeviceRecognition && !allowServer { throw RecognitionError.onDeviceUnavailable }

        let file = try AVAudioFile(forReading: audioURL)
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = file.length
        let total = Self.chunkCount(duration: duration > 0 ? duration : Double(totalFrames) / sampleRate)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("recognition", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for chunk in 0..<total {
            try Task.checkCancellation()
            if skip.contains(chunk) { continue }
            let start = Double(chunk) * Self.chunkSeconds
            let readStart = max(0, start - Self.overlapSeconds)
            let readEnd = start + Self.chunkSeconds + Self.overlapSeconds
            let startFrame = AVAudioFramePosition(readStart * sampleRate)
            let endFrame = min(totalFrames, AVAudioFramePosition(readEnd * sampleRate))
            guard endFrame > startFrame else { try await onChunk(chunk, []); continue }

            let chunkURL = tmpDir.appendingPathComponent("chunk-\(chunk).caf")
            try writeChunk(file: file, frames: startFrame..<endFrame, url: chunkURL)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            let words = try await recognizeFile(chunkURL, recognizer: recognizer, hints: hints, onDevice: recognizer.supportsOnDeviceRecognition)
            // Shift to absolute time and keep only the words that belong to this chunk
            // (the overlap is there so no word is cut at a chunk boundary).
            let ownStart = chunk == 0 ? -1 : start
            let ownEnd = chunk == total - 1 ? Double.greatestFiniteMagnitude : start + Self.chunkSeconds
            let absolute = words.map { RecognizedWord(text: $0.text, start: $0.start + readStart, end: $0.end + readStart, confidence: $0.confidence) }
                .filter { $0.start >= ownStart && $0.start < ownEnd }
            try await onChunk(chunk, absolute)
        }
    }

    private func writeChunk(file: AVAudioFile, frames: Range<AVAudioFramePosition>, url: URL) throws {
        let format = file.processingFormat
        let out = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        file.framePosition = frames.lowerBound
        var remaining = AVAudioFrameCount(frames.upperBound - frames.lowerBound)
        let block: AVAudioFrameCount = 65_536
        while remaining > 0 {
            let n = min(block, remaining)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { break }
            try file.read(into: buf, frameCount: n)
            if buf.frameLength == 0 { break }
            try out.write(from: buf)
            remaining -= buf.frameLength
        }
    }

    private func recognizeFile(_ url: URL, recognizer: SFSpeechRecognizer, hints: [String], onDevice: Bool) async throws -> [RecognizedWord] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Array(hints.prefix(100))

        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let result = result, result.isFinal {
                    finished = true
                    let words = result.bestTranscription.segments.map {
                        RecognizedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration,
                                       confidence: Double($0.confidence))
                    }
                    cont.resume(returning: words)
                } else if let error = error {
                    finished = true
                    let ns = error as NSError
                    // "No speech detected" is not an error for a silent minute.
                    if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 203) {
                        cont.resume(returning: [])
                    } else {
                        cont.resume(throwing: RecognitionError.failed(error.localizedDescription))
                    }
                }
            }
        }
    }
}

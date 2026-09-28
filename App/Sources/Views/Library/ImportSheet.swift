import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MeetingCore

/// Pick an audio recording and its transcript; files with the same name are paired.
struct ImportSheet: View {
    var onImported: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var inbox: ImportInbox
    @EnvironmentObject private var pipeline: ProcessingPipeline
    @State private var candidates: [ImportCandidate] = []
    @State private var showPicker = false
    @State private var pickingFor: UUID?   // candidate being completed with a second file
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { pickingFor = nil; showPicker = true } label: {
                        Label("Choose audio and transcript files", systemImage: "folder")
                    }
                } footer: {
                    Text("Audio: .m4a (Voice Memos), .mp3, .wav · Transcript: .txt, .md, .srt, .vtt, .pdf. In Voice Memos: Share › Save to Files, and copy the transcript into a text file. Files with the same name are paired automatically.")
                }

                ForEach($candidates) { $c in
                    Section {
                        TextField("Meeting name", text: $c.title)
                        fileRow("Audio", url: c.audio, icon: "waveform")
                        fileRow("Transcript", url: c.transcript, icon: "doc.text")
                        if c.audio == nil || c.transcript == nil {
                            Button(c.audio == nil ? "Add audio recording" : "Add transcript") {
                                pickingFor = c.id; showPicker = true
                            }
                        }
                        if c.transcript == nil {
                            Text("Without a transcript, the app uses the on-device recognition as the transcript and marks unsure words.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if c.audio == nil {
                            Text("Without audio there is no playback or word timing — only reading, translation and vocabulary.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { candidates.remove(atOffsets: $0) }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Import meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { inbox.pending = []; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await importAll() } }
                        .disabled(candidates.isEmpty || working)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: ImportService.allowedTypes, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): add(urls)
                case .failure(let e): error = e.localizedDescription
                }
            }
            .overlay { if working { ProgressView("Importing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .onAppear {
                if !inbox.pending.isEmpty { add(inbox.pending); inbox.pending = [] }
            }
        }
    }

    private func fileRow(_ title: String, url: URL?, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(url?.lastPathComponent ?? "—").foregroundStyle(url == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func add(_ urls: [URL]) {
        error = nil
        if let target = pickingFor, let i = candidates.firstIndex(where: { $0.id == target }) {
            for u in urls {
                if ImportService.isAudio(u) { candidates[i].audio = u } else if ImportService.isTranscript(u) { candidates[i].transcript = u }
            }
            pickingFor = nil
            return
        }
        let unsupported = urls.filter { !ImportService.isAudio($0) && !ImportService.isTranscript($0) }
        if !unsupported.isEmpty { error = "Unsupported: " + unsupported.map(\.lastPathComponent).joined(separator: ", ") }
        candidates.append(contentsOf: ImportService.pair(urls))
    }

    private func importAll() async {
        working = true
        defer { working = false }
        var ids: [UUID] = []
        for c in candidates {
            do {
                let doc = try await ImportService.createMeeting(from: c)
                let record = MeetingRecord(id: doc.id, title: c.title.isEmpty ? "Meeting" : c.title,
                                           hasAudio: doc.audioFileName != nil, hasTranscript: !doc.originalTranscript.isEmpty)
                record.duration = doc.duration
                context.insert(record)
                try? context.save()
                pipeline.start(doc.id, container: context.container)
                ids.append(doc.id)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
        dismiss()
        onImported(ids)
    }
}

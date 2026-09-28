import SwiftUI
import SwiftData
import MeetingCore

struct MeetingListView: View {
    @Query(sort: \MeetingRecord.createdAt, order: .reverse) private var meetings: [MeetingRecord]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var inbox: ImportInbox
    @EnvironmentObject private var pipeline: ProcessingPipeline
    @State private var toDelete: MeetingRecord?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if meetings.isEmpty {
                    ContentUnavailableView {
                        Label("No meetings yet", systemImage: "waveform.badge.plus")
                    } description: {
                        Text("Import a Voice Memos recording and its transcript. Everything is processed on this device.")
                    } actions: {
                        Button("Import meeting") { inbox.showImport = true }.buttonStyle(.borderedProminent)
                    }
                }
                ForEach(meetings) { m in
                    NavigationLink(value: m.id) { MeetingRow(meeting: m) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { toDelete = m }
                        }
                }
            }
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { inbox.showImport = true } label: { Label("Import", systemImage: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let m = meetings.first(where: { $0.id == id }) { MeetingContainerView(record: m) }
            }
            .sheet(isPresented: $inbox.showImport) {
                ImportSheet { ids in
                    if ids.count == 1, let id = ids.first { path = [id] }
                }
            }
            .confirmationDialog("Delete “\(toDelete?.title ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete meeting, audio and transcript", role: .destructive) {
                    if let m = toDelete { deleteMeeting(m) }
                }
                Button("Delete audio only", role: .destructive) {
                    if let m = toDelete, var doc = MeetingStore.shared.load(m.id) {
                        MeetingStore.shared.deleteAudio(&doc)
                        m.hasAudio = false
                        try? context.save()
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: {
                Text("Saved vocabulary stays in your word list.")
            }
        }
    }

    private func deleteMeeting(_ m: MeetingRecord) {
        pipeline.cancel(m.id)
        MeetingStore.shared.deleteMeeting(m.id)
        context.delete(m)
        try? context.save()
        toDelete = nil
    }
}

struct MeetingRow: View {
    let meeting: MeetingRecord
    @EnvironmentObject private var pipeline: ProcessingPipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).font(.headline).lineLimit(1)
            HStack(spacing: 10) {
                Text(meeting.createdAt, style: .date)
                if meeting.duration > 0 { Label(TimeFormat.short(meeting.duration), systemImage: "clock") }
                if meeting.sentenceCount > 0 { Text("\(meeting.sentenceCount) sentences") }
            }
            .font(.caption).foregroundStyle(.secondary)
            statusLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLine: some View {
        switch meeting.status {
        case .processing:
            if let p = pipeline.progress[meeting.id] {
                let stage = p.current ?? .meetingAnalysis
                ProgressView(value: p.fraction[stage] ?? 0) {
                    Text("\(stage.title) \(Int((p.fraction[stage] ?? 0) * 100))%").font(.caption2)
                }
            } else {
                Label(meeting.statusDetail ?? "Waiting to process", systemImage: "hourglass").font(.caption)
            }
        case .failed:
            Label(meeting.statusDetail ?? "Processing failed", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        case .ready:
            HStack(spacing: 10) {
                if meeting.pendingCorrections > 0 {
                    Label("\(meeting.pendingCorrections) to review", systemImage: "checkmark.bubble").foregroundStyle(.orange)
                }
                if meeting.hasAudio && meeting.alignedRatio > 0 {
                    Label("\(Int(meeting.alignedRatio * 100))% words synced", systemImage: "waveform.path")
                }
                if !meeting.hasAudio { Label("No audio", systemImage: "speaker.slash") }
            }
            .font(.caption).foregroundStyle(.secondary)
        case .imported:
            EmptyView()
        }
    }
}

/// Opens the meeting document and hands it to the workspace.
struct MeetingContainerView: View {
    let record: MeetingRecord
    @EnvironmentObject private var pipeline: ProcessingPipeline
    @Environment(\.modelContext) private var context
    @State private var session: MeetingSession?

    var body: some View {
        Group {
            if record.status == .processing || record.status == .imported {
                ProcessingView(record: record)
            } else if let session {
                MeetingWorkspaceView(session: session)
            } else if record.status == .failed {
                ContentUnavailableView("Processing failed", systemImage: "exclamationmark.triangle",
                                       description: Text(record.statusDetail ?? ""))
            } else {
                ProgressView()
            }
        }
        .task(id: record.statusRaw) { openIfReady() }
        .onDisappear { session?.close() }
    }

    private func openIfReady() {
        guard record.status == .ready, session == nil, let doc = MeetingStore.shared.load(record.id) else { return }
        let s = MeetingSession(doc: doc, record: record)
        s.attach(context)
        session = s
    }
}

struct ProcessingView: View {
    let record: MeetingRecord
    @EnvironmentObject private var pipeline: ProcessingPipeline
    @Environment(\.modelContext) private var context

    var body: some View {
        let p = pipeline.progress[record.id]
        List {
            Section {
                ForEach(ProcessingStage.allCases, id: \.self) { stage in
                    let value = p?.fraction[stage] ?? 0
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(stage.title)
                            Spacer()
                            Text("\(Int(value * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: value)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let m = p?.message { Text(m) }
                    Text("Speech recognition runs on this device. A one-hour meeting takes several minutes; you can leave this screen and processing continues. If the app is closed it resumes where it stopped.")
                }
            }
            if !pipeline.isRunning(record.id) {
                Button("Start processing") { pipeline.start(record.id, container: context.container) }
            }
        }
        .navigationTitle(record.title)
        .onAppear {
            if !pipeline.isRunning(record.id) { pipeline.start(record.id, container: context.container) }
        }
    }
}

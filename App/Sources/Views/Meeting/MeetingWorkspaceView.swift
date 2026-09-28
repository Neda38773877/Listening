import SwiftUI
import MeetingCore

/// The main learning screen.
/// iPad: timeline | transcript | explanation, audio player at the bottom.
/// iPhone: player on top, transcript in the middle, explanation panel at the bottom.
struct MeetingWorkspaceView: View {
    @ObservedObject var session: MeetingSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sheet: WorkspaceSheet?

    enum WorkspaceSheet: String, Identifiable {
        case corrections, shadowing, redemittel, summary, vocabulary, timeline
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if sizeClass == .regular { wideLayout } else { compactLayout }
        }
        .navigationTitle(session.doc.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet) { s in sheetContent(s) }
        .overlay(alignment: .top) {
            if let m = session.busyMessage {
                Label(m, systemImage: "hourglass").font(.footnote).padding(8)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 4)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(session.errorMessage ?? "") }
    }

    private var wideLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MeetingTimelineView(session: session)
                    .frame(width: 250)
                Divider()
                TranscriptView(session: session)
                Divider()
                InspectorView(session: session, onShadow: { sheet = .shadowing })
                    .frame(width: 360)
            }
            Divider()
            PlayerBar(session: session, player: session.player, compact: false) { sheet = .shadowing }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            PlayerBar(session: session, player: session.player, compact: true) { sheet = .shadowing }
            Divider()
            TranscriptView(session: session)
            if session.inspector != nil {
                Divider()
                InspectorView(session: session, onShadow: { sheet = .shadowing })
                    .frame(maxHeight: 330)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: session.inspector)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if session.doc.pendingCorrections.count > 0 {
                Button { sheet = .corrections } label: {
                    Label("Review \(session.doc.pendingCorrections.count)", systemImage: "checkmark.bubble")
                }
            }
            Menu {
                if sizeClass != .regular {
                    Button { sheet = .timeline } label: { Label("Timeline & topics", systemImage: "list.bullet.indent") }
                }
                Button { sheet = .corrections } label: { Label("Transcript corrections", systemImage: "checkmark.bubble") }
                Button { sheet = .shadowing } label: { Label("Shadowing mode", systemImage: "person.wave.2") }
                Button { sheet = .redemittel } label: { Label("Meeting Redemittel", systemImage: "text.quote") }
                Button { sheet = .vocabulary } label: { Label("Meeting vocabulary", systemImage: "character.book.closed") }
                Button { sheet = .summary } label: { Label("Meeting summary", systemImage: "doc.text.magnifyingglass") }
                Divider()
                Button { Task { await session.translate(sentences: Array(session.doc.sentences.indices), external: false) } } label: {
                    Label("Translate on device", systemImage: "character.bubble")
                }
                Toggle(isOn: $session.followPlayback) { Label("Follow playback", systemImage: "arrow.down.to.line") }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder private func sheetContent(_ s: WorkspaceSheet) -> some View {
        switch s {
        case .corrections: CorrectionReviewView(session: session)
        case .shadowing: ShadowingView(session: session, startSentence: session.currentSentenceIndex ?? 0)
        case .redemittel: RedemittelView(session: session)
        case .summary: SummaryView(session: session)
        case .vocabulary: MeetingVocabularyView(session: session)
        case .timeline: NavigationStack { MeetingTimelineView(session: session) { sheet = nil }.navigationTitle("Timeline") }
        }
    }
}

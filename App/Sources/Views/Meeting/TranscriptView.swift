import SwiftUI
import MeetingCore

struct TranscriptView: View {
    @ObservedObject var session: MeetingSession
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if session.doc.sentences.isEmpty {
                        ContentUnavailableView("No transcript", systemImage: "doc.text",
                                               description: Text(session.doc.processing.lastError ?? "Nothing was recognized in this recording."))
                    }
                    ForEach(session.doc.sentences) { s in
                        SentenceRow(
                            index: s.id,
                            tokens: Array(session.doc.tokens[s.tokenRange]),
                            time: session.doc.timeRange(of: s)?.lowerBound,
                            speaker: speakerChange(s),
                            english: settings.showEnglish ? s.english : nil,
                            persian: settings.showPersian ? s.persian : nil,
                            playingToken: session.playingSentence == s.id ? session.playingToken : nil,
                            isPlaying: session.playingSentence == s.id,
                            isSelected: isSelected(s),
                            selectedToken: selectedToken,
                            onWord: { session.tapWord($0) },
                            onSentence: {
                                session.select(.sentence(s.id))
                                session.playSentence(s.id)
                            }
                        )
                        .id(s.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .onChange(of: session.playingSentence) { _, new in
                guard session.followPlayback, session.player.activeClip == nil, let new else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onChange(of: session.inspector) { _, item in
                if case .sentence(let i) = item { withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }

    private var selectedToken: Int? {
        if case .word(let t) = session.inspector { return t }
        return nil
    }

    private func isSelected(_ s: Sentence) -> Bool {
        switch session.inspector {
        case .sentence(let i): return i == s.id
        case .word(let t): return s.tokenRange.contains(t)
        case .none: return false
        }
    }

    private func speakerChange(_ s: Sentence) -> String? {
        guard let sp = session.doc.tokens[s.firstToken].speaker else { return nil }
        if s.id == 0 { return sp }
        let prev = session.doc.sentences[s.id - 1]
        return session.doc.tokens[prev.firstToken].speaker == sp ? nil : sp
    }
}

struct SentenceRow: View {
    let index: Int
    let tokens: [Token]
    let time: Double?
    let speaker: String?
    let english: TranslationText?
    let persian: TranslationText?
    let playingToken: Int?
    let isPlaying: Bool
    let isSelected: Bool
    let selectedToken: Int?
    let onWord: (Int) -> Void
    let onSentence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let speaker {
                Text(speaker).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: onSentence) {
                    Text(time.map(TimeFormat.short) ?? "––:––")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isPlaying ? Color.accentColor : .secondary)
                        .frame(minWidth: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play sentence \(index + 1)")

                FlowLayout(spacing: 5, lineSpacing: 6) {
                    ForEach(tokens.filter { !$0.display.isEmpty }) { t in
                        WordChip(token: t, isPlaying: t.id == playingToken, isSelected: t.id == selectedToken)
                            .onTapGesture { onWord(t.id) }
                    }
                }
            }
            if let english {
                Text(english.text).font(.subheadline).foregroundStyle(.secondary).padding(.leading, 52)
            }
            if let persian {
                Text(persian.text).font(.subheadline).foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onSentence)
    }
}

struct WordChip: View {
    let token: Token
    let isPlaying: Bool
    let isSelected: Bool

    var body: some View {
        Text(token.display)
            .font(.system(.body, design: .serif))
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : (isPlaying ? Color.highlight.opacity(0.45) : .clear))
            )
            .underline(token.needsReview || token.display == Correction.unclearMarker, pattern: .dot, color: .orange)
            .foregroundStyle(token.timing == nil ? Color.secondary : (token.corrected != nil ? Color.accentColor : Color.primary))
            .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        if token.timing == nil { return "No audio timing" }
        if token.timing?.isApproximate == true { return "Approximate timing" }
        return "Plays this word"
    }
}
